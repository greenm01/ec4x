## Standing Orders Execution System
##
## Implements persistent fleet behaviors that execute automatically when
## no explicit order is given for a turn. Reduces micromanagement and provides
## quality-of-life improvements for both players and AI.
##
## See docs/architecture/standing-orders.md for complete design.

import std/[tables, options, sequtils, strformat, algorithm]
import gamestate, orders, fleet, starmap, logger, spacelift
import order_types
import ../common/types/[core, planets]

export StandingOrderType, StandingOrder, StandingOrderParams

type
  ExecutionResult* = object
    ## Result of standing order execution attempt
    success*: bool
    action*: string               # Description of action taken
    error*: string                # Error message if failed
    updatedParams*: Option[StandingOrderParams]  # Updated params (e.g., patrol index)

# =============================================================================
# Execution Logic - Per Order Type
# =============================================================================

proc executePatrolRoute(state: var GameState, fleetId: FleetId,
                       params: StandingOrderParams): ExecutionResult =
  ## Execute patrol route - move to next system in path
  ## Loops continuously through patrol path
  let fleet = state.fleets[fleetId]
  let currentIndex = params.patrolIndex
  let nextSystem = params.patrolSystems[currentIndex]

  logDebug(LogCategory.lcOrders,
           &"{fleetId} PatrolRoute: Current position {currentIndex + 1}/" &
           &"{params.patrolSystems.len} in patrol path")

  # Verify target system exists and is reachable
  if nextSystem notin state.starMap.systems:
    logWarn(LogCategory.lcOrders,
            &"{fleetId} PatrolRoute failed: Target system {nextSystem} does not exist")
    return ExecutionResult(success: false,
                          error: &"Target system {nextSystem} does not exist")

  # Generate move order to next patrol point
  let moveOrder = FleetOrder(
    fleetId: fleetId,
    orderType: FleetOrderType.Move,
    targetSystem: some(nextSystem),
    priority: 100  # Standing orders have lower priority than explicit orders
  )

  # Advance patrol index (loop back to start when reaching end)
  var newParams = params
  newParams.patrolIndex = (currentIndex + 1) mod params.patrolSystems.len

  # Store order for execution
  state.fleetOrders[fleetId] = moveOrder

  logInfo(LogCategory.lcOrders,
          &"{fleetId} PatrolRoute: {fleet.location} → system-{nextSystem} " &
          &"(step {currentIndex + 1}/{params.patrolSystems.len})")

  return ExecutionResult(
    success: true,
    action: &"Move to system-{nextSystem}",
    updatedParams: some(newParams)
  )

proc executeDefendSystem(state: var GameState, fleetId: FleetId,
                        params: StandingOrderParams): ExecutionResult =
  ## Execute defend system - stay at target or return if moved away
  let fleet = state.fleets[fleetId]
  let targetSystem = params.defendTargetSystem
  let maxRange = params.defendMaxRange

  logDebug(LogCategory.lcOrders,
           &"{fleetId} DefendSystem: Target=system-{targetSystem}, " &
           &"Current=system-{fleet.location}, MaxRange={maxRange}")

  # If already at target system, patrol/guard in place
  if fleet.location == targetSystem:
    let guardOrder = FleetOrder(
      fleetId: fleetId,
      orderType: FleetOrderType.Patrol,
      targetSystem: some(targetSystem),
      priority: 100
    )
    state.fleetOrders[fleetId] = guardOrder

    logInfo(LogCategory.lcOrders,
            &"{fleetId} DefendSystem: At target system-{targetSystem}, patrolling")

    return ExecutionResult(success: true,
                          action: &"Patrol system-{targetSystem}")

  # Check distance from target (via jump lanes, not as the crow flies)
  let pathResult = state.starMap.findPath(fleet.location, targetSystem, fleet)
  if not pathResult.found:
    # Can't reach target - suspended order, log warning
    logWarn(LogCategory.lcOrders,
            &"{fleetId} DefendSystem: Cannot reach target system-{targetSystem}, no valid path")
    return ExecutionResult(success: false,
                          error: "No path to target system")

  let distance = pathResult.path.len - 1  # Path includes start, so subtract 1

  if distance > maxRange:
    # Too far from target - return to defensive position
    let moveOrder = FleetOrder(
      fleetId: fleetId,
      orderType: FleetOrderType.Move,
      targetSystem: some(targetSystem),
      priority: 100
    )
    state.fleetOrders[fleetId] = moveOrder

    logInfo(LogCategory.lcOrders,
            &"{fleetId} DefendSystem: {distance} jumps from target, returning to system-{targetSystem}")

    return ExecutionResult(success: true,
                          action: &"Return to system-{targetSystem}")

  # Within range but not at target - hold position
  let holdOrder = FleetOrder(
    fleetId: fleetId,
    orderType: FleetOrderType.Hold,
    targetSystem: none(SystemId),
    priority: 100
  )
  state.fleetOrders[fleetId] = holdOrder

  logInfo(LogCategory.lcOrders,
          &"{fleetId} DefendSystem: {distance} jumps from target (within range {maxRange}), holding position")

  return ExecutionResult(success: true,
                        action: "Hold position within defensive range")

proc findBestColonizationTarget(state: GameState, fleet: Fleet, currentLocation: SystemId,
                                maxRange: int,
                                preferredClasses: seq[PlanetClass]): Option[SystemId] =
  ## Find best uncolonized system for colonization
  ## Returns nearest system with preferred planet class
  ## Distance calculated via jump lanes (pathfinding), not hex distance
  var candidates: seq[(SystemId, int, PlanetClass)] = @[]

  # Scan all systems within range
  for systemId, system in state.starMap.systems:
    # Skip if already colonized
    if systemId in state.colonies:
      continue

    # Check distance via jump lanes
    let pathResult = state.starMap.findPath(currentLocation, systemId, fleet)
    if not pathResult.found:
      continue  # Can't reach this system

    let distance = pathResult.path.len - 1  # Path includes start, so subtract 1
    if distance > maxRange:
      continue

    # Get planet class
    let planetClass = system.planetClass
    candidates.add((systemId, distance, planetClass))

  if candidates.len == 0:
    return none(SystemId)

  # Sort candidates: preferred classes first, then by distance
  candidates.sort(proc(a, b: (SystemId, int, PlanetClass)): int =
    # Prioritize preferred planet classes
    let aPreferred = a[2] in preferredClasses
    let bPreferred = b[2] in preferredClasses

    if aPreferred and not bPreferred:
      return -1
    elif bPreferred and not aPreferred:
      return 1
    else:
      # Same preference level - sort by distance
      return cmp(a[1], b[1])
  )

  return some(candidates[0][0])

proc executeAutoColonize(state: var GameState, fleetId: FleetId,
                        params: StandingOrderParams): ExecutionResult =
  ## Execute auto-colonize - find and colonize nearest suitable system
  ## For ETAC fleets that should automatically expand
  let fleet = state.fleets[fleetId]

  logDebug(LogCategory.lcOrders,
           &"{fleetId} AutoColonize: Searching for targets within {params.colonizeMaxRange} jumps")

  # Verify fleet has colonization capability (ETAC with colonists)
  if fleet.spaceLiftShips.len == 0:
    logWarn(LogCategory.lcOrders,
            &"{fleetId} AutoColonize failed: Fleet has no spacelift ships")
    return ExecutionResult(success: false,
                          error: "No spacelift ships for colonization")

  # Check if any spacelift ship carries colonists
  var hasColonists = false
  for ship in fleet.spaceLiftShips:
    if ship.cargo.cargoType == CargoType.Colonists:
      hasColonists = true
      break

  if not hasColonists:
    logWarn(LogCategory.lcOrders,
            &"{fleetId} AutoColonize failed: No colonists aboard")
    return ExecutionResult(success: false,
                          error: "No colonists for colonization")

  # Find best colonization target
  let targetOpt = findBestColonizationTarget(state, fleet, fleet.location,
                                             params.colonizeMaxRange,
                                             params.preferredPlanetClasses)

  if targetOpt.isNone:
    logDebug(LogCategory.lcOrders,
             &"{fleetId} AutoColonize: No suitable systems within {params.colonizeMaxRange} jumps")
    return ExecutionResult(success: false,
                          error: "No colonization targets available")

  let targetSystem = targetOpt.get()

  # Calculate distance via jump lanes
  let pathResult = state.starMap.findPath(fleet.location, targetSystem, fleet)
  let distance = if pathResult.found: pathResult.path.len - 1 else: 0

  # If already at target, issue colonize order
  if fleet.location == targetSystem:
    let colonizeOrder = FleetOrder(
      fleetId: fleetId,
      orderType: FleetOrderType.Colonize,
      targetSystem: some(targetSystem),
      priority: 100
    )
    state.fleetOrders[fleetId] = colonizeOrder

    logInfo(LogCategory.lcOrders,
            &"{fleetId} AutoColonize: At target system-{targetSystem}, colonizing")

    return ExecutionResult(success: true,
                          action: &"Colonize system-{targetSystem}")

  # Move to colonization target
  let moveOrder = FleetOrder(
    fleetId: fleetId,
    orderType: FleetOrderType.Move,
    targetSystem: some(targetSystem),
    priority: 100
  )
  state.fleetOrders[fleetId] = moveOrder

  let planetClass = state.starMap.systems[targetSystem].planetClass

  logInfo(LogCategory.lcOrders,
          &"{fleetId} AutoColonize: Moving to system-{targetSystem} " &
          &"({planetClass}, {distance} jumps)")

  return ExecutionResult(success: true,
                        action: &"Move to colonization target system-{targetSystem}")

# =============================================================================
# Main Execution Function
# =============================================================================

proc executeStandingOrder*(state: var GameState, fleetId: FleetId,
                          standingOrder: StandingOrder, turn: int): ExecutionResult =
  ## Execute a single standing order
  ## Called during Command Phase for fleets without explicit orders

  case standingOrder.orderType
  of StandingOrderType.None:
    return ExecutionResult(success: true, action: "No standing order")

  of StandingOrderType.PatrolRoute:
    return executePatrolRoute(state, fleetId, standingOrder.params)

  of StandingOrderType.DefendSystem, StandingOrderType.GuardColony:
    return executeDefendSystem(state, fleetId, standingOrder.params)

  of StandingOrderType.AutoColonize:
    return executeAutoColonize(state, fleetId, standingOrder.params)

  of StandingOrderType.AutoReinforce:
    # TODO: Implement auto-reinforce (join damaged fleets)
    logWarn(LogCategory.lcOrders,
            &"{fleetId} AutoReinforce not yet implemented")
    return ExecutionResult(success: false, error: "Not yet implemented")

  of StandingOrderType.AutoRepair:
    # TODO: Implement auto-repair (return to shipyard when damaged)
    logWarn(LogCategory.lcOrders,
            &"{fleetId} AutoRepair not yet implemented")
    return ExecutionResult(success: false, error: "Not yet implemented")

  of StandingOrderType.AutoEvade:
    # TODO: Implement auto-evade (retreat when outnumbered)
    logWarn(LogCategory.lcOrders,
            &"{fleetId} AutoEvade not yet implemented")
    return ExecutionResult(success: false, error: "Not yet implemented")

  of StandingOrderType.BlockadeTarget:
    # TODO: Implement blockade maintenance
    logWarn(LogCategory.lcOrders,
            &"{fleetId} BlockadeTarget not yet implemented")
    return ExecutionResult(success: false, error: "Not yet implemented")

proc executeStandingOrders*(state: var GameState, turn: int) =
  ## Execute standing orders for all fleets without explicit orders
  ## Called during Command Phase after explicit orders are processed
  ##
  ## COMPREHENSIVE LOGGING:
  ## - INFO: High-level execution summary
  ## - DEBUG: Per-fleet decision logic
  ## - WARN: Failures and issues

  logInfo(LogCategory.lcOrders,
          &"=== Standing Orders Execution: Turn {turn} ===")

  var executedCount = 0
  var skippedCount = 0
  var failedCount = 0
  var notImplementedCount = 0

  for fleetId, fleet in state.fleets:
    # Skip if fleet has explicit order this turn
    if fleetId in state.fleetOrders:
      let explicitOrder = state.fleetOrders[fleetId]
      logDebug(LogCategory.lcOrders,
               &"{fleetId} has explicit order ({explicitOrder.orderType}), " &
               &"skipping standing order")
      skippedCount += 1
      continue

    # Check for standing order
    if fleetId notin state.standingOrders:
      continue

    let standingOrder = state.standingOrders[fleetId]

    # Skip if suspended
    if standingOrder.suspended:
      logDebug(LogCategory.lcOrders,
               &"{fleetId} standing order suspended, skipping")
      skippedCount += 1
      continue

    # Execute standing order
    let result = executeStandingOrder(state, fleetId, standingOrder, turn)

    if result.success:
      executedCount += 1
      logInfo(LogCategory.lcOrders,
              &"{fleetId} executed {standingOrder.orderType}: {result.action}")

      # Update execution tracking and params
      var updatedOrder = standingOrder
      updatedOrder.lastExecutedTurn = turn
      updatedOrder.executionCount += 1

      # Update params if returned (e.g., patrol index advanced)
      if result.updatedParams.isSome:
        updatedOrder.params = result.updatedParams.get()

      state.standingOrders[fleetId] = updatedOrder

    elif result.error == "Not yet implemented":
      notImplementedCount += 1
      logDebug(LogCategory.lcOrders,
               &"{fleetId} {standingOrder.orderType} not yet implemented")

    else:
      failedCount += 1
      logWarn(LogCategory.lcOrders,
              &"{fleetId} {standingOrder.orderType} failed: {result.error}")

  # Summary logging
  let totalAttempted = executedCount + failedCount + notImplementedCount
  logInfo(LogCategory.lcOrders,
          &"Standing Orders Summary: {executedCount}/{totalAttempted} executed, " &
          &"{skippedCount} skipped (explicit orders), {failedCount} failed, " &
          &"{notImplementedCount} not implemented")
