# =============================================================================
# Grace Period Management
# =============================================================================

proc resetStandingOrderGracePeriod*(state: var GameState, fleetId: FleetId) =
  ## Reset activation delay countdown when explicit order completes
  ## Gives player time to issue new orders before standing order reactivates
  ## Called after every order completion (via state.fleetOrders.del)
  if fleetId in state.standingOrders:
    var standingOrder = state.standingOrders[fleetId]
    standingOrder.turnsUntilActivation = standingOrder.activationDelayTurns
    state.standingOrders[fleetId] = standingOrder
    logDebug(LogCategory.lcOrders,
      &"Fleet {fleetId} standing order grace period reset to " &
      &"{standingOrder.activationDelayTurns} turn(s)")

# =============================================================================
# Main Activation Function
# =============================================================================

proc activateStandingOrder*(state: var GameState, fleetId: FleetId,
                          standingOrder: StandingOrder, turn: int): ActivationResult =
  ## Execute a single standing order
  ## Called during Command Phase for fleets without explicit orders

  case standingOrder.orderType
  of StandingOrderType.None:
    return ActivationResult(success: true, action: "No standing order")

  of StandingOrderType.PatrolRoute:
    return activatePatrolRoute(state, fleetId, standingOrder.params)

  of StandingOrderType.DefendSystem, StandingOrderType.GuardColony:
    return activateDefendSystem(state, fleetId, standingOrder.params)

  of StandingOrderType.AutoReinforce:
    return activateAutoReinforce(state, fleetId, standingOrder.params)

  of StandingOrderType.AutoRepair:
    return activateAutoRepair(state, fleetId, standingOrder.params)

  of StandingOrderType.BlockadeTarget:
    return activateBlockadeTarget(state, fleetId, standingOrder.params)

proc activateStandingOrders*(state: var GameState, turn: int, events: var seq[resolution_types.GameEvent]) =
  ## Activate standing orders for all fleets without explicit orders
  ## Called during Maintenance Phase Step 1a
  ##
  ## Three-tier order lifecycle:
  ## - Initiate (Command Phase): Player configures standing order rules
  ## - Activate (Maintenance Phase): Standing orders generate fleet orders ← THIS PROC
  ## - Execute (Conflict/Income Phase): Missions happen at targets
  ##
  ## COMPREHENSIVE LOGGING:
  ## - INFO: High-level activation summary
  ## - DEBUG: Per-fleet decision logic
  ## - WARN: Failures and issues
  ##
  ## Phase 7b: Emits StandingOrderActivated events when orders activate

  logInfo(LogCategory.lcOrders,
          &"=== Standing Order Activation: Turn {turn} ===")

  # Check global master switch
  if not globalStandingOrdersConfig.activation.global_enabled:
    logInfo(LogCategory.lcOrders,
            "Standing orders globally disabled in config - skipping all activation")
    return

  var activatedCount = 0
  var skippedCount = 0
  var failedCount = 0
  var notImplementedCount = 0
  var noStandingOrderCount = 0  # Fleets without standing orders assigned

  for fleetId, fleet in state.fleets:
    # Skip if fleet has explicit order this turn
    if fleetId in state.fleetOrders:
      let explicitOrder = state.fleetOrders[fleetId]
      logDebug(LogCategory.lcOrders,
               &"{fleetId} has explicit order ({explicitOrder.orderType}), " &
               &"skipping standing order")
      skippedCount += 1

      # Reset activation countdown when explicit order exists
      if fleetId in state.standingOrders:
        var standingOrder = state.standingOrders[fleetId]
        standingOrder.turnsUntilActivation = standingOrder.activationDelayTurns
        state.standingOrders[fleetId] = standingOrder

        # Emit StandingOrderSuspended event (suspended by explicit order)
        events.add(event_factory.standingOrderSuspended(
          fleet.owner,
          fleetId,
          $standingOrder.orderType,
          "explicit order issued",
          fleet.location
        ))

      continue

    # Check for standing order
    if fleetId notin state.standingOrders:
      logDebug(LogCategory.lcOrders,
               &"{fleetId} (owner: {fleet.owner}) has no standing order assigned, skipping")
      noStandingOrderCount += 1
      continue

    var standingOrder = state.standingOrders[fleetId]

    # Skip if suspended
    if standingOrder.suspended:
      logDebug(LogCategory.lcOrders,
               &"{fleetId} standing order suspended, skipping")
      skippedCount += 1
      continue

    # Skip if not enabled (player control)
    if not standingOrder.enabled:
      logDebug(LogCategory.lcOrders,
               &"{fleetId} standing order disabled by player, skipping")
      skippedCount += 1
      continue

    # Check activation delay countdown
    if standingOrder.turnsUntilActivation > 0:
      # Decrement countdown
      standingOrder.turnsUntilActivation -= 1
      state.standingOrders[fleetId] = standingOrder
      logDebug(LogCategory.lcOrders,
               &"{fleetId} standing order waiting {standingOrder.turnsUntilActivation} more turn(s)")
      skippedCount += 1
      continue

    # Activate standing order
    let result = activateStandingOrder(state, fleetId, standingOrder, turn)

    if result.success:
      activatedCount += 1
      logInfo(LogCategory.lcOrders,
              &"{fleetId} activated {standingOrder.orderType}: {result.action}")

      # Get generated fleet order type
      let generatedOrderType = if fleetId in state.fleetOrders:
        $state.fleetOrders[fleetId].orderType
      else:
        "None"

      # Emit StandingOrderActivated event (Phase 7b)
      events.add(event_factory.standingOrderActivated(
        fleet.owner,
        fleetId,
        $standingOrder.orderType,
        generatedOrderType,
        result.action,
        fleet.location
      ))

      # Update activation tracking and params
      var updatedOrder = standingOrder
      updatedOrder.lastActivatedTurn = turn
      updatedOrder.activationCount += 1

      # Reset activation countdown (standing order generated a new fleet order)
      updatedOrder.turnsUntilActivation = updatedOrder.activationDelayTurns

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
  let totalAttempted = activatedCount + failedCount + notImplementedCount
  let totalFleets = state.fleets.len
  logInfo(LogCategory.lcOrders,
          &"Standing Orders Summary: {totalFleets} total fleets, " &
          &"{noStandingOrderCount} without standing orders, " &
          &"{skippedCount} skipped (explicit orders/suspended/disabled/delay), " &
          &"{activatedCount}/{totalAttempted} activated, " &
          &"{failedCount} failed, {notImplementedCount} not implemented")

proc activateAutoRepair(state: var GameState, fleetId: FleetId,
                      params: StandingOrderParams): ActivationResult =
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
    return ActivationResult(success: false, error: "Fleet has no ships")

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

    return ActivationResult(success: true,
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
    return ActivationResult(success: false,
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

    return ActivationResult(success: true,
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

  return ActivationResult(success: true,
                        action: &"Return to shipyard at system-{targetSystem}")

proc activateAutoReinforce(state: var GameState, fleetId: FleetId,
                         params: StandingOrderParams): ActivationResult =
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

    return ActivationResult(success: true,
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

    return ActivationResult(success: true,
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

  return ActivationResult(success: true,
                        action: &"Move to reinforce {targetId}")

proc activateBlockadeTarget(state: var GameState, fleetId: FleetId,
                          params: StandingOrderParams): ActivationResult =
  ## Execute blockade target - maintain blockade on enemy colony
  ## Moves to target colony and issues BlockadePlanet order
  let fleet = state.fleets[fleetId]
  let targetColony = params.blockadeTargetColony

  logDebug(LogCategory.lcOrders,
           &"{fleetId} BlockadeTarget: Target=system-{targetColony}, " &
           &"Current=system-{fleet.location}")

  # Verify we have intel on target colony (fog-of-war compliant)
  if not hasColonyIntel(state, fleet.owner, targetColony):
    logWarn(LogCategory.lcOrders,
            &"{fleetId} BlockadeTarget failed: No intel on colony at system-{targetColony}")
    return ActivationResult(success: false,
                          error: "No intel on target colony")

  # Verify target exists and is enemy colony
  if targetColony notin state.colonies:
    logWarn(LogCategory.lcOrders,
            &"{fleetId} BlockadeTarget failed: Colony at system-{targetColony} no longer exists " &
            &"(intel may be stale)")
    return ActivationResult(success: false,
                          error: "Target colony no longer exists")

  let colony = state.colonies[targetColony]

  # Verify target is not owned by same house
  if colony.owner == fleet.owner:
    logWarn(LogCategory.lcOrders,
            &"{fleetId} BlockadeTarget failed: Cannot blockade own colony at system-{targetColony}")
    return ActivationResult(success: false,
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

    return ActivationResult(success: true,
                          action: &"Blockade colony at system-{targetColony}")

  # Move to target colony
  let pathResult = state.starMap.findPath(fleet.location, targetColony, fleet)
  if not pathResult.found:
    logWarn(LogCategory.lcOrders,
            &"{fleetId} BlockadeTarget failed: Cannot reach target system-{targetColony}")
    return ActivationResult(success: false,
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

  return ActivationResult(success: true,
                        action: &"Move to blockade target at system-{targetColony}")

proc activatePatrolRoute(state: var GameState, fleetId: FleetId,
                       params: StandingOrderParams): ActivationResult =
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
    return ActivationResult(success: false,
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

  return ActivationResult(
    success: true,
    action: &"Move to system-{nextSystem}",
    updatedParams: some(newParams)
  )

proc activateDefendSystem(state: var GameState, fleetId: FleetId,
                        params: StandingOrderParams): ActivationResult =
  ## Execute defend system - stay at target or return if moved away
  let fleet = state.fleets[fleetId]
  let targetSystem = params.defendTargetSystem

  # CRITICAL: Validate target system
  if targetSystem == SystemId(0):
    logError(LogCategory.lcOrders,
             &"[ENGINE ACTIVATION] {fleetId} DefendSystem: BUG - defendTargetSystem is SystemId(0)!")
    return ActivationResult(success: false,
                          error: "Invalid defend target (SystemId 0)")

  if not state.starMap.systems.hasKey(targetSystem):
    logWarn(LogCategory.lcOrders,
            &"[ENGINE ACTIVATION] {fleetId} DefendSystem: Target system {targetSystem} does not exist")
    return ActivationResult(success: false,
                          error: "Defend target system does not exist")
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

    return ActivationResult(success: true,
                          action: &"Patrol system-{targetSystem}")

  # Check distance from target (via jump lanes, not as the crow flies)
  let pathResult = state.starMap.findPath(fleet.location, targetSystem, fleet)
  if not pathResult.found:
    # Can't reach target - suspended order, log warning
    logWarn(LogCategory.lcOrders,
            &"{fleetId} DefendSystem: Cannot reach target system-{targetSystem}, no valid path")
    return ActivationResult(success: false,
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

    return ActivationResult(success: true,
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

  return ActivationResult(success: true,
                        action: "Hold position within defensive range")

