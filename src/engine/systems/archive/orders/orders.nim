# Order creation helpers

proc createMoveOrder*(fleetId: FleetId, targetSystem: SystemId, priority: int = 0): FleetOrder =
  ## Create a movement order
  result = FleetOrder(
    fleetId: fleetId,
    orderType: FleetOrderType.Move,
    targetSystem: some(targetSystem),
    targetFleet: none(FleetId),
    priority: priority
  )

proc createColonizeOrder*(fleetId: FleetId, targetSystem: SystemId, priority: int = 0): FleetOrder =
  ## Create a colonization order
  result = FleetOrder(
    fleetId: fleetId,
    orderType: FleetOrderType.Colonize,
    targetSystem: some(targetSystem),
    targetFleet: none(FleetId),
    priority: priority
  )

proc createAttackOrder*(fleetId: FleetId, targetSystem: SystemId, attackType: FleetOrderType, priority: int = 0): FleetOrder =
  ## Create an attack order (bombard, invade, or blitz)
  result = FleetOrder(
    fleetId: fleetId,
    orderType: attackType,
    targetSystem: some(targetSystem),
    targetFleet: none(FleetId),
    priority: priority
  )

proc createHoldOrder*(fleetId: FleetId, priority: int = 0): FleetOrder =
  ## Create a hold position order
  result = FleetOrder(
    fleetId: fleetId,
    orderType: FleetOrderType.Hold,
    targetSystem: none(SystemId),
    targetFleet: none(FleetId),
    priority: priority
  )

# Order validation
proc validateFleetOrder*(order: FleetOrder, state: GameState, issuingHouse: HouseId): ValidationResult =
  ## Validate a fleet order against current game state
  ## Checks:
  ## - Fleet exists
  ## - Fleet ownership (prevents controlling enemy fleets)
  ## - Fleet mission state (locked if OnSpyMission)
  ## - Target validity (system exists, path exists)
  ## - Required capabilities (transport, combat, scout)
  ## Creates GameEvent when orders are rejected
  result = ValidationResult(valid: true, error: "")

  # Check fleet exists
  let fleetOpt = state.getFleet(order.fleetId)
  if fleetOpt.isNone:
    logWarn(LogCategory.lcOrders,
            &"{issuingHouse} Fleet Validation FAILED: {order.fleetId} does not exist")
    return ValidationResult(valid: false, error: "Fleet does not exist")

  let fleet = fleetOpt.get()

  # CRITICAL: Validate fleet ownership (prevent controlling enemy fleets)
  if fleet.owner != issuingHouse:
    logWarn(LogCategory.lcOrders,
            &"SECURITY VIOLATION: {issuingHouse} attempted to control {order.fleetId} " &
            &"(owned by {fleet.owner})")
    return ValidationResult(valid: false,
                           error: &"Fleet {order.fleetId} is not owned by {issuingHouse}")

  # Check if fleet is locked on active spy mission
  # Scouts on active missions (OnSpyMission state) cannot accept new orders
  # Scouts traveling to mission (Traveling state) can change orders (cancel mission)
  if fleet.missionState == FleetMissionState.OnSpyMission:
    logWarn(LogCategory.lcOrders,
            &"{issuingHouse} Order REJECTED: {order.fleetId} is on active spy mission " &
            &"(cannot issue new orders while mission active)")
    return ValidationResult(valid: false,
                           error: "Fleet locked on active spy mission (scouts consumed)")

  logDebug(LogCategory.lcOrders,
           &"{issuingHouse} Validating {order.orderType} order for {order.fleetId} " &
           &"at {fleet.location}")

  # Validate based on order type
  case order.orderType
  of FleetOrderType.Hold:
    # Always valid
    discard

  of FleetOrderType.Move:
    if order.targetSystem.isNone:
      logWarn(LogCategory.lcOrders,
              &"{issuingHouse} Move order REJECTED: {order.fleetId} - no target system specified")
      return ValidationResult(valid: false, error: "Move order requires target system")

    let targetId = order.targetSystem.get()
    if not state.starMap.systems.hasKey(targetId):
      logWarn(LogCategory.lcOrders,
              &"{issuingHouse} Move order REJECTED: {order.fleetId} → {targetId} " &
              &"(target system does not exist)")
      return ValidationResult(valid: false, error: "Target system does not exist")

    # Check pathfinding - can fleet reach target?
    let pathResult = state.starMap.findPath(fleet.location, targetId, fleet)
    if not pathResult.found:
      logWarn(LogCategory.lcOrders,
              &"{issuingHouse} Move order REJECTED: {order.fleetId} → {targetId} " &
              &"(no valid path from {fleet.location})")
      return ValidationResult(valid: false, error: "No valid path to target system")

    logDebug(LogCategory.lcOrders,
             &"{issuingHouse} Move order VALID: {order.fleetId} → {targetId} " &
             &"({pathResult.path.len - 1} jumps via {fleet.location})")

  of FleetOrderType.Colonize:
    # Check fleet has operational ETAC (Expansion squadron)
    logDebug(LogCategory.lcOrders,
            &"{issuingHouse} Validating Colonize order for {order.fleetId} at " &
            &"{fleet.location} ({fleet.squadrons.len} squadrons)")
    var hasETAC = false
    for squadron in fleet.squadrons:
      if squadron.squadronType == SquadronType.Expansion:
        logDebug(LogCategory.lcOrders,
                &"  Squadron {squadron.id}: class={squadron.flagship.shipClass}, " &
                &"crippled={squadron.flagship.isCrippled}, " &
                &"cargo={squadron.flagship.cargo}")
        if squadron.flagship.shipClass == ShipClass.ETAC:
          if not squadron.flagship.isCrippled:
            hasETAC = true
            break

    if not hasETAC:
      logWarn(LogCategory.lcOrders,
              &"{issuingHouse} Colonize order REJECTED: {order.fleetId} - " &
              &"no functional ETAC")
      return ValidationResult(valid: false, error: "Colonize requires functional ETAC")

    if order.targetSystem.isNone:
      logWarn(LogCategory.lcOrders,
              &"{issuingHouse} Colonize order REJECTED: {order.fleetId} - no target system specified")
      return ValidationResult(valid: false, error: "Colonize order requires target system")

    # Check if system already colonized
    let targetId = order.targetSystem.get()
    if targetId in state.colonies:
      logWarn(LogCategory.lcOrders,
              &"{issuingHouse} Colonize order REJECTED: {order.fleetId} → {targetId} " &
              &"(already colonized by {state.colonies[targetId].owner})")
      return ValidationResult(valid: false, error: "Target system is already colonized")

    logDebug(LogCategory.lcOrders,
             &"{issuingHouse} Colonize order VALID: {order.fleetId} → {targetId}")

  of FleetOrderType.Bombard, FleetOrderType.Invade, FleetOrderType.Blitz:
    # Check fleet has no Intel squadrons (Intel squadrons are intelligence-only, not combat units)
    for squadron in fleet.squadrons:
      if squadron.squadronType == SquadronType.Intel:
        logWarn(LogCategory.lcOrders,
                &"{issuingHouse} {order.orderType} order REJECTED: {order.fleetId} - " &
                &"combat orders cannot include Intel squadrons (intelligence-only)")
        return ValidationResult(valid: false, error: "Combat orders cannot include Intel squadrons")

    # Check fleet has combat squadrons
    var hasMilitary = false
    for squadron in fleet.squadrons:
      if squadron.flagship.stats.attackStrength > 0:
        hasMilitary = true
        break

    if not hasMilitary:
      logWarn(LogCategory.lcOrders,
              &"{issuingHouse} {order.orderType} order REJECTED: {order.fleetId} - " &
              &"no combat-capable squadrons")
      return ValidationResult(valid: false, error: "Combat order requires combat-capable squadrons")

    if order.targetSystem.isNone:
      logWarn(LogCategory.lcOrders,
              &"{issuingHouse} {order.orderType} order REJECTED: {order.fleetId} - " &
              &"no target system specified")
      return ValidationResult(valid: false, error: "Combat order requires target system")

    logDebug(LogCategory.lcOrders,
             &"{issuingHouse} {order.orderType} order VALID: {order.fleetId} → " &
             &"{order.targetSystem.get()}")

  of FleetOrderType.SpyPlanet, FleetOrderType.SpySystem, FleetOrderType.HackStarbase:
    # Spy missions require pure Intel fleets (no combat, auxiliary, or expansion squadrons)
    # Multiple Intel squadrons can merge for mesh network ELI bonuses
    if fleet.squadrons.len == 0:
      logWarn(LogCategory.lcOrders,
              &"{issuingHouse} {order.orderType} order REJECTED: {order.fleetId} - " &
              &"requires at least one Intel squadron")
      return ValidationResult(valid: false, error: "Spy missions require at least one Intel squadron")

    # Check fleet is pure Intel (all squadrons must be Intel type)
    var hasIntel = false
    var hasNonIntel = false

    for squadron in fleet.squadrons:
      if squadron.squadronType == SquadronType.Intel:
        hasIntel = true
      else:
        hasNonIntel = true
        logWarn(LogCategory.lcOrders,
                &"{issuingHouse} {order.orderType} order REJECTED: {order.fleetId} - " &
                &"spy missions require pure Intel fleet (found {squadron.squadronType} squadron)")

    if not hasIntel:
      return ValidationResult(valid: false, error: "Spy missions require at least one Intel squadron")

    if hasNonIntel:
      return ValidationResult(valid: false, error: "Spy missions require pure Intel fleet (no combat/auxiliary/expansion)")

    if order.targetSystem.isNone:
      logWarn(LogCategory.lcOrders,
              &"{issuingHouse} {order.orderType} order REJECTED: {order.fleetId} - " &
              &"no target system specified")
      return ValidationResult(valid: false, error: "Spy mission requires target system")

    logDebug(LogCategory.lcOrders,
             &"{issuingHouse} {order.orderType} order VALID: {order.fleetId} → " &
             &"{order.targetSystem.get()}")

  of FleetOrderType.JoinFleet:
    if order.targetFleet.isNone:
      logWarn(LogCategory.lcOrders,
              &"{issuingHouse} JoinFleet order REJECTED: {order.fleetId} - " &
              &"no target fleet specified")
      return ValidationResult(valid: false, error: "Join order requires target fleet")

    let targetFleetId = order.targetFleet.get()
    let targetFleetOpt = state.getFleet(targetFleetId)
    if targetFleetOpt.isNone:
      logWarn(LogCategory.lcOrders,
              &"{issuingHouse} JoinFleet order REJECTED: {order.fleetId} → {targetFleetId} " &
              &"(target fleet does not exist)")
      return ValidationResult(valid: false, error: "Target fleet does not exist")

    # Check fleets are in same location
    let targetFleet = targetFleetOpt.get()
    if fleet.location != targetFleet.location:
      logWarn(LogCategory.lcOrders,
              &"{issuingHouse} JoinFleet order REJECTED: {order.fleetId} → {targetFleetId} " &
              &"(fleets at different systems: {fleet.location} vs {targetFleet.location})")
      return ValidationResult(valid: false, error: "Fleets must be in same system to join")

    # Check scout/combat fleet mixing
    let mergeCheck = fleet.canMergeWith(targetFleet)
    if not mergeCheck.canMerge:
      logWarn(LogCategory.lcOrders,
              &"{issuingHouse} JoinFleet order REJECTED: {order.fleetId} → {targetFleetId} - " &
              &"{mergeCheck.reason}")
      return ValidationResult(valid: false, error: mergeCheck.reason)

    logDebug(LogCategory.lcOrders,
             &"{issuingHouse} JoinFleet order VALID: {order.fleetId} → {targetFleetId} " &
             &"at {fleet.location}")

  of FleetOrderType.Rendezvous:
    if order.targetSystem.isNone:
      logWarn(LogCategory.lcOrders,
              &"{issuingHouse} Rendezvous order REJECTED: {order.fleetId} - " &
              &"no target system specified")
      return ValidationResult(valid: false, error: "Rendezvous order requires target system")

    let targetId = order.targetSystem.get()
    if not state.starMap.systems.hasKey(targetId):
      logWarn(LogCategory.lcOrders,
              &"{issuingHouse} Rendezvous order REJECTED: {order.fleetId} → {targetId} " &
              &"(target system does not exist)")
      return ValidationResult(valid: false, error: "Target system does not exist")

    logDebug(LogCategory.lcOrders,
             &"{issuingHouse} Rendezvous order VALID: {order.fleetId} → {targetId}")

  else:
    # Other order types - basic validation only for now
    discard

