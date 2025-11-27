## Standing Orders Execution System
##
## Implements persistent fleet behaviors that execute automatically when
## no explicit order is given for a turn. Reduces micromanagement and provides
## quality-of-life improvements for both players and AI.
##
## See docs/architecture/standing-orders.md for complete design.

import std/[tables, options, strformat, algorithm]
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

proc executeAutoRepair(state: var GameState, fleetId: FleetId,
                      params: StandingOrderParams): ExecutionResult =
  ## Execute auto-repair - return to nearest shipyard when ships are crippled
  ## Triggers when crippled ship percentage exceeds threshold
  let fleet = state.fleets[fleetId]

  # Count crippled ships vs total ships
  var totalShips = 0
  var crippledShips = 0

  for squadron in fleet.squadrons:
    totalShips += 1
    if squadron.flagship.isCrippled:
      crippledShips += 1

    # Include wingmen
    for ship in squadron.ships:
      totalShips += 1
      if ship.isCrippled:
        crippledShips += 1

  if totalShips == 0:
    # No ships (shouldn't happen, but safety check)
    return ExecutionResult(success: false, error: "Fleet has no ships")

  let crippledPercent = crippledShips.float / totalShips.float

  logDebug(LogCategory.lcOrders,
           &"{fleetId} AutoRepair: Fleet {crippledShips}/{totalShips} ships crippled " &
           &"({(crippledPercent * 100).int}%), " &
           &"Threshold {(params.repairDamageThreshold * 100).int}%")

  # Check if damage threshold triggered
  if crippledPercent < params.repairDamageThreshold:
    # Fleet healthy, no repair needed
    logDebug(LogCategory.lcOrders,
             &"{fleetId} AutoRepair: Fleet above damage threshold, holding position")

    let holdOrder = FleetOrder(
      fleetId: fleetId,
      orderType: FleetOrderType.Hold,
      targetSystem: none(SystemId),
      priority: 100
    )
    state.fleetOrders[fleetId] = holdOrder

    return ExecutionResult(success: true,
                          action: "Hold (fleet healthy)")

  # Fleet damaged - find nearest shipyard
  var nearestShipyard: Option[SystemId] = none(SystemId)
  var minDistance = int.high

  # Check for specific target shipyard
  if params.targetShipyard.isSome:
    let targetSystem = params.targetShipyard.get()
    if targetSystem in state.colonies:
      let colony = state.colonies[targetSystem]
      if colony.owner == fleet.owner and colony.hasOperationalShipyard():
        nearestShipyard = some(targetSystem)
        let pathResult = state.starMap.findPath(fleet.location, targetSystem, fleet)
        if pathResult.found:
          minDistance = pathResult.path.len - 1

  # If no specific target or target not found, search all colonies
  if nearestShipyard.isNone:
    for systemId, colony in state.colonies:
      # Only owned colonies with operational shipyards
      if colony.owner != fleet.owner:
        continue
      if not colony.hasOperationalShipyard():
        continue

      # Calculate distance via jump lanes
      let pathResult = state.starMap.findPath(fleet.location, systemId, fleet)
      if not pathResult.found:
        continue

      let distance = pathResult.path.len - 1
      if distance < minDistance:
        minDistance = distance
        nearestShipyard = some(systemId)

  if nearestShipyard.isNone:
    # No shipyard available
    logWarn(LogCategory.lcOrders,
            &"{fleetId} AutoRepair failed: No accessible shipyard found " &
            &"({crippledShips}/{totalShips} ships crippled)")
    return ExecutionResult(success: false,
                          error: "No accessible shipyard")

  let targetSystem = nearestShipyard.get()

  # If already at shipyard, hold for repairs
  if fleet.location == targetSystem:
    logInfo(LogCategory.lcOrders,
            &"{fleetId} AutoRepair: At shipyard system-{targetSystem}, " &
            &"holding for repairs ({crippledShips}/{totalShips} ships crippled)")

    let holdOrder = FleetOrder(
      fleetId: fleetId,
      orderType: FleetOrderType.Hold,
      targetSystem: none(SystemId),
      priority: 100
    )
    state.fleetOrders[fleetId] = holdOrder

    return ExecutionResult(success: true,
                          action: &"Hold at shipyard (repairing)")

  # Move to shipyard
  logInfo(LogCategory.lcOrders,
          &"{fleetId} AutoRepair: Damaged ({crippledShips}/{totalShips} ships crippled), " &
          &"returning to shipyard at system-{targetSystem} ({minDistance} jumps)")

  let moveOrder = FleetOrder(
    fleetId: fleetId,
    orderType: FleetOrderType.Move,
    targetSystem: some(targetSystem),
    priority: 100
  )
  state.fleetOrders[fleetId] = moveOrder

  return ExecutionResult(success: true,
                        action: &"Return to shipyard at system-{targetSystem}")

proc executeAutoReinforce(state: var GameState, fleetId: FleetId,
                         params: StandingOrderParams): ExecutionResult =
  ## Execute auto-reinforce - join damaged friendly fleet
  ## Finds nearest damaged fleet and moves to join it
  let fleet = state.fleets[fleetId]

  logDebug(LogCategory.lcOrders,
           &"{fleetId} AutoReinforce: Searching for damaged friendly fleets")

  # Find target fleet (specific or nearest damaged)
  var targetFleetId: Option[FleetId] = none(FleetId)
  var targetFleetLocation: SystemId
  var minDistance = int.high

  if params.targetFleet.isSome:
    # Specific target fleet
    let specificTarget = params.targetFleet.get()
    if specificTarget in state.fleets:
      let targetFleet = state.fleets[specificTarget]

      # Check if target belongs to same house
      if targetFleet.owner == fleet.owner:
        # Count crippled ships in target fleet
        var targetTotalShips = 0
        var targetCrippledShips = 0
        for squadron in targetFleet.squadrons:
          targetTotalShips += 1
          if squadron.flagship.isCrippled:
            targetCrippledShips += 1
          for ship in squadron.ships:
            targetTotalShips += 1
            if ship.isCrippled:
              targetCrippledShips += 1

        let targetCrippledPercent = if targetTotalShips > 0:
                                       targetCrippledShips.float / targetTotalShips.float
                                     else: 0.0

        # Check if target is damaged above threshold
        if targetCrippledPercent >= params.reinforceDamageThreshold:
          targetFleetId = some(specificTarget)
          targetFleetLocation = targetFleet.location

          let pathResult = state.starMap.findPath(fleet.location, targetFleet.location, fleet)
          if pathResult.found:
            minDistance = pathResult.path.len - 1

  # If no specific target or target not damaged, search for nearest damaged fleet
  if targetFleetId.isNone:
    for otherFleetId, otherFleet in state.fleets:
      # Skip self
      if otherFleetId == fleetId:
        continue

      # Only same house
      if otherFleet.owner != fleet.owner:
        continue

      # Count crippled ships
      var otherTotalShips = 0
      var otherCrippledShips = 0
      for squadron in otherFleet.squadrons:
        otherTotalShips += 1
        if squadron.flagship.isCrippled:
          otherCrippledShips += 1
        for ship in squadron.ships:
          otherTotalShips += 1
          if ship.isCrippled:
            otherCrippledShips += 1

      if otherTotalShips == 0:
        continue

      let otherCrippledPercent = otherCrippledShips.float / otherTotalShips.float

      # Check if damaged above threshold
      if otherCrippledPercent < params.reinforceDamageThreshold:
        continue

      # Calculate distance via jump lanes
      let pathResult = state.starMap.findPath(fleet.location, otherFleet.location, fleet)
      if not pathResult.found:
        continue

      let distance = pathResult.path.len - 1
      if distance < minDistance:
        minDistance = distance
        targetFleetId = some(otherFleetId)
        targetFleetLocation = otherFleet.location

  if targetFleetId.isNone:
    # No damaged fleets found
    logDebug(LogCategory.lcOrders,
             &"{fleetId} AutoReinforce: No damaged friendly fleets found " &
             &"(threshold {(params.reinforceDamageThreshold * 100).int}%)")

    let holdOrder = FleetOrder(
      fleetId: fleetId,
      orderType: FleetOrderType.Hold,
      targetSystem: none(SystemId),
      priority: 100
    )
    state.fleetOrders[fleetId] = holdOrder

    return ExecutionResult(success: true,
                          action: "Hold (no damaged fleets)")

  let targetId = targetFleetId.get()

  # If already at target location, issue JoinFleet order
  if fleet.location == targetFleetLocation:
    logInfo(LogCategory.lcOrders,
            &"{fleetId} AutoReinforce: At location with {targetId}, joining fleet")

    let joinOrder = FleetOrder(
      fleetId: fleetId,
      orderType: FleetOrderType.JoinFleet,
      targetFleet: some(targetId),
      priority: 100
    )
    state.fleetOrders[fleetId] = joinOrder

    return ExecutionResult(success: true,
                          action: &"Join fleet {targetId}")

  # Move to target fleet
  logInfo(LogCategory.lcOrders,
          &"{fleetId} AutoReinforce: Moving to reinforce {targetId} " &
          &"at system-{targetFleetLocation} ({minDistance} jumps)")

  let moveOrder = FleetOrder(
    fleetId: fleetId,
    orderType: FleetOrderType.Move,
    targetSystem: some(targetFleetLocation),
    priority: 100
  )
  state.fleetOrders[fleetId] = moveOrder

  return ExecutionResult(success: true,
                        action: &"Move to reinforce {targetId}")

proc calculateFleetStrength(fleet: Fleet): int =
  ## Calculate raw combat strength of fleet
  ## Sum of attack strength across all ships
  result = 0
  for squadron in fleet.squadrons:
    result += squadron.flagship.stats.attackStrength
    for ship in squadron.ships:
      result += ship.stats.attackStrength

proc executeAutoEvade(state: var GameState, fleetId: FleetId,
                     params: StandingOrderParams, roe: int): ExecutionResult =
  ## Execute auto-evade - retreat to fallback system when outnumbered
  ## Uses evadeTriggerRatio to determine when to retreat
  let fleet = state.fleets[fleetId]
  let currentLocation = fleet.location

  logDebug(LogCategory.lcOrders,
           &"{fleetId} AutoEvade: Checking for hostile forces at system-{currentLocation}")

  # Calculate our strength
  let ourStrength = calculateFleetStrength(fleet)

  # Find hostile fleets at current location
  var totalHostileStrength = 0
  var hostileCount = 0

  for otherFleetId, otherFleet in state.fleets:
    if otherFleetId == fleetId:
      continue
    if otherFleet.location != currentLocation:
      continue

    # Check diplomatic status - TODO: integrate with diplomacy system
    # For now, treat all non-owned fleets as potential hostiles
    if otherFleet.owner != fleet.owner:
      let hostileStrength = calculateFleetStrength(otherFleet)
      totalHostileStrength += hostileStrength
      hostileCount += 1

      logDebug(LogCategory.lcOrders,
               &"{fleetId} AutoEvade: Detected {otherFleetId} " &
               &"(strength {hostileStrength})")

  if hostileCount == 0:
    # No hostiles - hold position
    logDebug(LogCategory.lcOrders,
             &"{fleetId} AutoEvade: No hostile forces detected, holding position")

    let holdOrder = FleetOrder(
      fleetId: fleetId,
      orderType: FleetOrderType.Hold,
      targetSystem: none(SystemId),
      priority: 100
    )
    state.fleetOrders[fleetId] = holdOrder

    return ExecutionResult(success: true,
                          action: "Hold (no hostiles)")

  # Calculate strength ratio
  let strengthRatio = if totalHostileStrength > 0:
                        ourStrength.float / totalHostileStrength.float
                      else:
                        1.0

  logDebug(LogCategory.lcOrders,
           &"{fleetId} AutoEvade: Strength ratio {strengthRatio:.2f} " &
           &"(us {ourStrength} vs them {totalHostileStrength}), " &
           &"trigger {params.evadeTriggerRatio:.2f}")

  # Check if we should retreat
  if strengthRatio >= params.evadeTriggerRatio:
    # We're strong enough - hold position
    logInfo(LogCategory.lcOrders,
            &"{fleetId} AutoEvade: Strength sufficient ({strengthRatio:.2f} >= " &
            &"{params.evadeTriggerRatio:.2f}), holding position")

    let holdOrder = FleetOrder(
      fleetId: fleetId,
      orderType: FleetOrderType.Hold,
      targetSystem: none(SystemId),
      priority: 100
    )
    state.fleetOrders[fleetId] = holdOrder

    return ExecutionResult(success: true,
                          action: &"Hold (strength ratio {strengthRatio:.2f})")

  # Retreat to fallback system
  let fallbackSystem = params.fallbackSystem

  # Verify fallback system exists and is reachable
  if fallbackSystem notin state.starMap.systems:
    logWarn(LogCategory.lcOrders,
            &"{fleetId} AutoEvade failed: Fallback system-{fallbackSystem} does not exist")
    return ExecutionResult(success: false,
                          error: "Fallback system does not exist")

  let pathResult = state.starMap.findPath(currentLocation, fallbackSystem, fleet)
  if not pathResult.found:
    logWarn(LogCategory.lcOrders,
            &"{fleetId} AutoEvade failed: Cannot reach fallback system-{fallbackSystem}")
    return ExecutionResult(success: false,
                          error: "Cannot reach fallback system")

  let distance = pathResult.path.len - 1

  # If already at fallback, hold position
  if currentLocation == fallbackSystem:
    logInfo(LogCategory.lcOrders,
            &"{fleetId} AutoEvade: Already at fallback system-{fallbackSystem}, holding")

    let holdOrder = FleetOrder(
      fleetId: fleetId,
      orderType: FleetOrderType.Hold,
      targetSystem: none(SystemId),
      priority: 100
    )
    state.fleetOrders[fleetId] = holdOrder

    return ExecutionResult(success: true,
                          action: "Hold at fallback")

  # Retreat to fallback
  logInfo(LogCategory.lcOrders,
          &"{fleetId} AutoEvade: RETREATING - outnumbered " &
          &"({strengthRatio:.2f} < {params.evadeTriggerRatio:.2f}), " &
          &"falling back to system-{fallbackSystem} ({distance} jumps)")

  let moveOrder = FleetOrder(
    fleetId: fleetId,
    orderType: FleetOrderType.Move,
    targetSystem: some(fallbackSystem),
    priority: 100
  )
  state.fleetOrders[fleetId] = moveOrder

  return ExecutionResult(success: true,
                        action: &"Retreat to fallback system-{fallbackSystem}")

proc executeBlockadeTarget(state: var GameState, fleetId: FleetId,
                          params: StandingOrderParams): ExecutionResult =
  ## Execute blockade target - maintain blockade on enemy colony
  ## Moves to target colony and issues BlockadePlanet order
  let fleet = state.fleets[fleetId]
  let targetColony = params.blockadeTargetColony

  logDebug(LogCategory.lcOrders,
           &"{fleetId} BlockadeTarget: Target=system-{targetColony}, " &
           &"Current=system-{fleet.location}")

  # Verify target colony exists
  if targetColony notin state.colonies:
    logWarn(LogCategory.lcOrders,
            &"{fleetId} BlockadeTarget failed: Colony at system-{targetColony} no longer exists")
    return ExecutionResult(success: false,
                          error: "Target colony no longer exists")

  let colony = state.colonies[targetColony]

  # Verify target is not owned by same house
  if colony.owner == fleet.owner:
    logWarn(LogCategory.lcOrders,
            &"{fleetId} BlockadeTarget failed: Cannot blockade own colony at system-{targetColony}")
    return ExecutionResult(success: false,
                          error: "Cannot blockade own colony")

  # If already at target, issue blockade order
  if fleet.location == targetColony:
    logInfo(LogCategory.lcOrders,
            &"{fleetId} BlockadeTarget: At target system-{targetColony}, " &
            &"maintaining blockade (colony owner: {colony.owner})")

    let blockadeOrder = FleetOrder(
      fleetId: fleetId,
      orderType: FleetOrderType.BlockadePlanet,
      targetSystem: some(targetColony),
      priority: 100
    )
    state.fleetOrders[fleetId] = blockadeOrder

    return ExecutionResult(success: true,
                          action: &"Blockade colony at system-{targetColony}")

  # Move to target colony
  let pathResult = state.starMap.findPath(fleet.location, targetColony, fleet)
  if not pathResult.found:
    logWarn(LogCategory.lcOrders,
            &"{fleetId} BlockadeTarget failed: Cannot reach target system-{targetColony}")
    return ExecutionResult(success: false,
                          error: "Cannot reach target colony")

  let distance = pathResult.path.len - 1

  logInfo(LogCategory.lcOrders,
          &"{fleetId} BlockadeTarget: Moving to blockade {colony.owner} colony " &
          &"at system-{targetColony} ({distance} jumps)")

  let moveOrder = FleetOrder(
    fleetId: fleetId,
    orderType: FleetOrderType.Move,
    targetSystem: some(targetColony),
    priority: 100
  )
  state.fleetOrders[fleetId] = moveOrder

  return ExecutionResult(success: true,
                        action: &"Move to blockade target at system-{targetColony}")

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
    return executeAutoReinforce(state, fleetId, standingOrder.params)

  of StandingOrderType.AutoRepair:
    return executeAutoRepair(state, fleetId, standingOrder.params)

  of StandingOrderType.AutoEvade:
    return executeAutoEvade(state, fleetId, standingOrder.params, standingOrder.roe)

  of StandingOrderType.BlockadeTarget:
    return executeBlockadeTarget(state, fleetId, standingOrder.params)

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
