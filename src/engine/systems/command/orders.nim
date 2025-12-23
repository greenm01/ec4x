## Fleet order types and validation for EC4X

import std/[options, tables, strformat, sequtils]
import ../../types/core
import ../../types/game_state
import ../fleet/entity
import ../../state/starmap
import ../../../common/logger
import ../../types/order_types  # Import and re-export fleet order types
import ../../types/espionage as esp_types
import ../../types/research as res_types
import ../economy/projects  # For cost calculation
import ../economy/config_accessors  # For CST requirement checking
import ../economy/capacity/fighter # For colony fighter squadron limits
import ../economy/capacity/capital_squadrons  # For capital squadron capacity enforcement
import ../economy/capacity/total_squadrons  # For total squadron capacity (prevents escort spam)
import ../../types/economy as econ_types  # For FacilityType in cost calculation

# Re-export order types
export order_types.FleetOrderType, order_types.FleetOrder

type
  TerraformOrder* = object
    ## Order to terraform a planet to next class
    ## Per economy.md Section 4.7
    colonySystem*: SystemId
    startTurn*: int           # Turn when terraforming started
    turnsRemaining*: int      # Turns until completion (based on TER level)
    ppCost*: int              # Total PP cost for upgrade
    targetClass*: int         # Target planet class (current + 1)

  OrderPacket* = object
    houseId*: HouseId
    turn*: int
    treasury*: int                                           # Treasury at order generation time (for budget validation)
    fleetOrders*: seq[FleetOrder]
    buildOrders*: seq[BuildOrder]
    researchAllocation*: res_types.ResearchAllocation  # PP allocation to ERP/SRP/TRP
    diplomaticActions*: seq[DiplomaticAction]
    populationTransfers*: seq[PopulationTransferOrder]  # Space Guild transfers
    terraformOrders*: seq[TerraformOrder]                # Terraforming projects
    colonyManagement*: seq[ColonyManagementOrder]        # Colony-level management (tax rates, auto-repair, etc.)
    standingOrders*: Table[FleetId, StandingOrder]       # Persistent fleet behaviors (AutoColonize, DefendSystem, etc.)

    # Espionage budget allocation (diplomacy.md:8.2)
    espionageAction*: Option[esp_types.EspionageAttempt]  # Max 1 per turn
    ebpInvestment*: int      # EBP points to purchase (40 PP each)
    cipInvestment*: int      # CIP points to purchase (40 PP each)

  BuildOrder* = object
    colonySystem*: SystemId
    buildType*: BuildType
    quantity*: int
    shipClass*: Option[ShipClass]      # For Ship type
    buildingType*: Option[string]      # For Building type
    industrialUnits*: int              # For Infrastructure type

  BuildType* {.pure.} = enum
    Ship, Building, Infrastructure

  DiplomaticAction* = object
    targetHouse*: HouseId
    actionType*: DiplomaticActionType
    proposalId*: Option[string]  # For accept/reject/withdraw actions
    message*: Option[string]     # Optional diplomatic message

  DiplomaticActionType* {.pure.} = enum
    ## Diplomatic actions per diplomacy.md:8.1
    ## 3-level diplomatic system: Neutral, Hostile, Enemy
    DeclareHostile,            # Escalate to Hostile (deep space combat)
    DeclareEnemy,              # Escalate to Enemy (open war, planetary attacks)
    SetNeutral                 # De-escalate to Neutral (peace)

  PopulationTransferOrder* = object
    ## Space Guild population transfer between colonies
    ## Source: economy.md:3.7, config/population.toml
    sourceColony*: SystemId
    destColony*: SystemId
    ptuAmount*: int

  ValidationResult* = object
    valid*: bool
    error*: string

  OrderValidationContext* = object
    ## Budget tracking context for validating orders
    ## Prevents overspending by tracking running total of committed costs
    availableTreasury*: int      # Total treasury available at order submission
    committedSpending*: int      # Running total of validated order costs
    rejectedOrders*: int         # Count of orders rejected due to budget

  OrderCostSummary* = object
    ## Summary of order costs for preview/validation
    buildCosts*: int
    researchCosts*: int
    espionageCosts*: int
    totalCost*: int
    canAfford*: bool
    errors*: seq[string]
    warnings*: seq[string]

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

proc validateOrderPacket*(packet: OrderPacket, state: GameState): ValidationResult =
  ## Validate entire order packet for a house
  ## Performs comprehensive validation including:
  ## - Fleet ownership (prevents controlling enemy fleets)
  ## - Target validity (systems exist, paths exist)
  ## - Colony ownership (prevents building at enemy colonies)
  ## Creates GameEvents for rejected orders
  result = ValidationResult(valid: true, error: "")

  # Check house exists
  if packet.houseId notin state.houses:
    logWarn(LogCategory.lcOrders,
            &"Order packet REJECTED: {packet.houseId} does not exist")
    return ValidationResult(valid: false, error: "House does not exist")

  # Check turn number matches
  if packet.turn != state.turn:
    logWarn(LogCategory.lcOrders,
            &"{packet.houseId} Order packet REJECTED: wrong turn " &
            &"(packet={packet.turn}, current={state.turn})")
    return ValidationResult(valid: false, error: "Order packet for wrong turn")

  logInfo(LogCategory.lcOrders,
          &"{packet.houseId} Validating order packet: {packet.fleetOrders.len} fleet orders, " &
          &"{packet.buildOrders.len} build orders")

  # Validate each fleet order with ownership check
  var validFleetOrders = 0
  for order in packet.fleetOrders:
    let orderResult = validateFleetOrder(order, state, packet.houseId)
    if not orderResult.valid:
      return orderResult
    validFleetOrders += 1

  if packet.fleetOrders.len > 0:
    logInfo(LogCategory.lcOrders,
            &"{packet.houseId} Fleet orders: {validFleetOrders}/{packet.fleetOrders.len} valid")

  # Validate build orders (check colony ownership, production capacity)
  var validBuildOrders = 0
  for order in packet.buildOrders:
    # Check colony exists and is owned by house
    if order.colonySystem notin state.colonies:
      logWarn(LogCategory.lcOrders,
              &"{packet.houseId} Build order REJECTED: colony at {order.colonySystem} " &
              &"does not exist")
      return ValidationResult(valid: false, error: "Build order: Colony does not exist at system " & $order.colonySystem)

    let colony = state.colonies[order.colonySystem]
    if colony.owner != packet.houseId:
      logWarn(LogCategory.lcOrders,
              &"SECURITY VIOLATION: {packet.houseId} attempted to build at {order.colonySystem} " &
              &"(owned by {colony.owner})")
      return ValidationResult(valid: false, error: "Build order: House does not own colony at system " & $order.colonySystem)

    # Check CST tech requirement for ships (economy.md:4.5)
    if order.buildType == BuildType.Ship and order.shipClass.isSome:
      let shipClass = order.shipClass.get()
      let required_cst = getShipCSTRequirement(shipClass)

      # Get house's CST level
      if packet.houseId in state.houses:
        let house = state.houses[packet.houseId]
        let house_cst = house.techTree.levels.constructionTech

        if house_cst < required_cst:
          logWarn(LogCategory.lcOrders,
                  &"{packet.houseId} Build order REJECTED: {shipClass} requires CST{required_cst}, " &
                  &"house has CST{house_cst}")
          return ValidationResult(valid: false,
                                 error: &"Build order: {shipClass} requires CST{required_cst}, house has CST{house_cst}")

    # Check CST tech requirement and prerequisites for buildings (assets.md:2.4.4)
    if order.buildType == BuildType.Building and order.buildingType.isSome:
      let buildingType = order.buildingType.get()

      # Check CST requirement (e.g., Starbase requires CST3)
      let required_cst = getBuildingCSTRequirement(buildingType)
      if required_cst > 0 and packet.houseId in state.houses:
        let house = state.houses[packet.houseId]
        let house_cst = house.techTree.levels.constructionTech

        if house_cst < required_cst:
          logWarn(LogCategory.lcOrders,
                  &"{packet.houseId} Build order REJECTED: {buildingType} requires CST{required_cst}, " &
                  &"house has CST{house_cst}")
          return ValidationResult(valid: false,
                                 error: &"Build order: {buildingType} requires CST{required_cst}, house has CST{house_cst}")

      # Check shipyard prerequisite (e.g., Starbase requires shipyard)
      if requiresShipyard(buildingType):
        if not hasOperationalShipyard(colony):
          logWarn(LogCategory.lcOrders,
                  &"{packet.houseId} Build order REJECTED: {buildingType} requires operational shipyard at {order.colonySystem}")
          return ValidationResult(valid: false,
                                 error: &"Build order: {buildingType} requires operational shipyard")

    # NOTE: Multiple build orders per colony per turn are supported (queue system)
    # Dock capacity is validated during resolution (economy_resolution.nim:102-108)
    # Orders beyond capacity remain queued for future turns
    # This allows unlimited PP spending per turn (limited by treasury + dock capacity)

    validBuildOrders += 1
    logDebug(LogCategory.lcOrders,
             &"{packet.houseId} Build order VALID: {order.buildType} at {order.colonySystem}")

  if packet.buildOrders.len > 0:
    logInfo(LogCategory.lcOrders,
            &"{packet.houseId} Build orders: {validBuildOrders}/{packet.buildOrders.len} valid")

  # Validate research allocation (check total points available)
  # Note: Actual PP availability check happens during resolution (after income phase)
  # Here we just validate structure - allocation can't be negative
  if packet.researchAllocation.economic < 0 or packet.researchAllocation.science < 0:
    return ValidationResult(valid: false, error: "Research allocation: Cannot allocate negative PP")

  # Validate technology allocations (per-field)
  for field, amount in packet.researchAllocation.technology:
    if amount < 0:
      return ValidationResult(valid: false, error: "Research allocation: Cannot allocate negative PP to " & $field)

  # Validate diplomatic actions (check diplomatic state and constraints)
  for action in packet.diplomaticActions:
    # Check target house exists
    if action.targetHouse notin state.houses:
      return ValidationResult(valid: false, error: "Diplomatic action: Target house does not exist")

    # Can't take diplomatic actions against eliminated houses
    if state.houses[action.targetHouse].eliminated:
      return ValidationResult(valid: false, error: "Diplomatic action: Target house is eliminated")

    # Can't target self
    if action.targetHouse == packet.houseId:
      return ValidationResult(valid: false, error: "Diplomatic action: Cannot target own house")

  # Validate colony management orders
  for order in packet.colonyManagement:
    # Check colony exists
    if order.colonyId notin state.colonies:
      return ValidationResult(valid: false, error: "Colony management: Colony does not exist at " & $order.colonyId)

    # Check ownership
    let colony = state.colonies[order.colonyId]
    if colony.owner != packet.houseId:
      return ValidationResult(valid: false, error: "Colony management: House does not own colony at " & $order.colonyId)

    # Validate action-specific parameters
    case order.action
    of ColonyManagementAction.SetTaxRate:
      if order.taxRate < 0 or order.taxRate > 100:
        return ValidationResult(valid: false, error: "Colony management: Tax rate must be 0-100")
    of ColonyManagementAction.SetAutoRepair:
      # Boolean flag, no validation needed
      discard

  # All validations passed
  logInfo(LogCategory.lcOrders,
          &"{packet.houseId} Order packet VALIDATED: All orders valid and authorized")
  result = ValidationResult(valid: true, error: "")

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

# Order packet creation

proc newOrderPacket*(houseId: HouseId, turn: int, treasury: int = 0): OrderPacket =
  ## Create empty order packet for a house
  ## treasury: Treasury at order generation time (defaults to 0 for test harnesses)
  result = OrderPacket(
    houseId: houseId,
    turn: turn,
    treasury: treasury,
    fleetOrders: @[],
    buildOrders: @[],
    researchAllocation: res_types.initResearchAllocation(),
    diplomaticActions: @[]
  )

proc addFleetOrder*(packet: var OrderPacket, order: FleetOrder) =
  ## Add a fleet order to packet
  packet.fleetOrders.add(order)

proc addBuildOrder*(packet: var OrderPacket, order: BuildOrder) =
  ## Add a build order to packet
  packet.buildOrders.add(order)

# Budget tracking and validation

proc initOrderValidationContext*(treasury: int): OrderValidationContext =
  ## Create new validation context for order packet
  result = OrderValidationContext(
    availableTreasury: treasury,
    committedSpending: 0,
    rejectedOrders: 0
  )

proc getRemainingBudget*(ctx: OrderValidationContext): int =
  ## Get remaining budget after committed spending
  result = ctx.availableTreasury - ctx.committedSpending

proc calculateBuildOrderCost*(order: BuildOrder, state: GameState, assignedFacilityType: Option[econ_types.FacilityType] = none(econ_types.FacilityType)): int =
  ## Calculate the PP cost of a build order
  ## Returns 0 if cost cannot be determined
  ##
  ## IMPORTANT: Spaceport Commission Penalty (economy.md:5.1, 5.3)
  ## - Ships built at spaceports (planet-side) incur 100% PC increase (double cost)
  ## - Ships built at shipyards (orbital) have no penalty (standard cost)
  ## - Fighters are EXEMPT (distributed planetary manufacturing)
  ## - Shipyard/Starbase buildings are EXEMPT (orbital construction, no penalty)
  ##
  ## If assignedFacilityType is provided, use it to determine cost.
  ## Otherwise, fall back to legacy logic (check if colony has shipyard).
  result = 0

  case order.buildType
  of BuildType.Ship:
    if order.shipClass.isSome:
      let baseCost = projects.getShipConstructionCost(order.shipClass.get()) * order.quantity
      let shipClass = order.shipClass.get()

      # Apply spaceport commission penalty if building planet-side
      # Per economy.md:5.1 - "Ships (excluding fighter squadrons) constructed planet-side incur a 100% PC increase"
      # IMPORTANT: Fighters are EXEMPT from the penalty (planet-based manufacturing)
      if shipClass == ShipClass.Fighter:
        # Fighters never incur commission penalty (distributed planetary manufacturing)
        result = baseCost
      elif assignedFacilityType.isSome:
        # NEW: Per-facility cost calculation
        if assignedFacilityType.get() == econ_types.FacilityType.Spaceport:
          # Planet-side construction (spaceport) → 100% penalty (double cost)
          result = baseCost * 2
        else:
          # Orbital construction (shipyard) → no penalty
          result = baseCost
      elif order.colonySystem in state.colonies:
        # LEGACY: Fall back to colony-wide check (for backwards compatibility)
        let colony = state.colonies[order.colonySystem]
        let hasShipyard = colony.shipyards.len > 0
        let hasSpaceport = colony.spaceports.len > 0

        if not hasShipyard and hasSpaceport:
          # Planet-side construction (spaceport only) → 100% penalty (double cost)
          result = baseCost * 2
        else:
          # Orbital construction (shipyard present) → no penalty
          result = baseCost
      else:
        # Colony doesn't exist (validation will catch this)
        result = baseCost

  of BuildType.Building:
    if order.buildingType.isSome:
      # Buildings never have spaceport penalty (planet-side industry)
      # Shipyard/Starbase are built in orbit and don't get penalty
      result = projects.getBuildingCost(order.buildingType.get()) * order.quantity

  of BuildType.Infrastructure:
    # Infrastructure cost depends on colony state
    if order.colonySystem in state.colonies:
      let colony = state.colonies[order.colonySystem]
      result = projects.getIndustrialUnitCost(colony) * order.industrialUnits

proc validateBuildOrderWithBudget*(order: BuildOrder, state: GameState,
                                   houseId: HouseId,
                                   ctx: var OrderValidationContext): ValidationResult =
  ## Validate build order including budget check and tech requirements
  ## Updates context with committed spending if valid

  # Basic validation first
  if order.colonySystem notin state.colonies:
    return ValidationResult(valid: false,
                           error: &"Build order: Colony not found at system {order.colonySystem}")

  let colony = state.colonies[order.colonySystem]

  # Check CST tech requirement for ships (economy.md:4.5)
  if order.buildType == BuildType.Ship and order.shipClass.isSome:
    let shipClass = order.shipClass.get()
    let required_cst = getShipCSTRequirement(shipClass)

    # Get house's CST level
    if houseId in state.houses:
      let house = state.houses[houseId]
      let house_cst = house.techTree.levels.constructionTech

      if house_cst < required_cst:
        ctx.rejectedOrders += 1
        logWarn(LogCategory.lcEconomy,
                &"{houseId} Build order REJECTED: {shipClass} requires CST{required_cst}, " &
                &"house has CST{house_cst}")
        return ValidationResult(valid: false,
                               error: &"Build order: {shipClass} requires CST{required_cst}, house has CST{house_cst}")

  # Check CST tech requirement and prerequisites for buildings (assets.md:2.4.4)
  if order.buildType == BuildType.Building and order.buildingType.isSome:
    let buildingType = order.buildingType.get()

    # Check CST requirement (e.g., Starbase requires CST3)
    let required_cst = getBuildingCSTRequirement(buildingType)
    if required_cst > 0 and houseId in state.houses:
      let house = state.houses[houseId]
      let house_cst = house.techTree.levels.constructionTech

      if house_cst < required_cst:
        ctx.rejectedOrders += 1
        logWarn(LogCategory.lcEconomy,
                &"{houseId} Build order REJECTED: {buildingType} requires CST{required_cst}, " &
                &"house has CST{house_cst}")
        return ValidationResult(valid: false,
                               error: &"Build order: {buildingType} requires CST{required_cst}, house has CST{house_cst}")

    # Check shipyard prerequisite (e.g., Starbase requires shipyard)
    if requiresShipyard(buildingType):
      if not hasOperationalShipyard(colony):
        ctx.rejectedOrders += 1
        logWarn(LogCategory.lcEconomy,
                &"{houseId} Build order REJECTED: {buildingType} requires operational shipyard at {order.colonySystem}")
        return ValidationResult(valid: false,
                               error: &"Build order: {buildingType} requires operational shipyard")

  # Check capacity limits for fighters and squadrons (military.toml)
  if order.buildType == BuildType.Ship and order.shipClass.isSome:
    let shipClass = order.shipClass.get()

    # Check fighter capacity (if building fighters)
    if shipClass == ShipClass.Fighter:
      if houseId in state.houses:
        let house = state.houses[houseId]
        if canCommissionFighter(state, colony) == false:
          ctx.rejectedOrders += 1
          return ValidationResult(valid: false,
            error: &"Fighter capacity limit exceeded by {house.name}")

    # Check capital squadron limit (if building capital ships)
    # Fighters are exempt from squadron limits (separate per-colony limits)
    if shipClass != ShipClass.Fighter:
      # First check capital squadron limit (subset of total limit)
      if capital_squadrons.isCapitalShip(shipClass):
        if not capital_squadrons.canBuildCapitalShip(state, houseId):
          let violation = capital_squadrons.analyzeCapacity(state, houseId)
          let underConstruction = capital_squadrons.countCapitalSquadronsUnderConstruction(state, houseId)

          ctx.rejectedOrders += 1
          logWarn(LogCategory.lcEconomy,
                  &"{houseId} Build order REJECTED: Capital squadron limit exceeded " &
                  &"(current={violation.current}, queued={underConstruction}, max={violation.maximum})")
          return ValidationResult(valid: false,
                                 error: &"Capital squadron limit exceeded ({violation.current}+{underConstruction}/{violation.maximum})")

      # Then check total squadron limit (all combat ships)
      # This prevents escort spam while allowing flexible fleet composition
      if not total_squadrons.canBuildSquadron(state, houseId, shipClass):
        let violation = total_squadrons.analyzeCapacity(state, houseId)
        let underConstruction = total_squadrons.countTotalSquadronsUnderConstruction(state, houseId)

        ctx.rejectedOrders += 1
        logWarn(LogCategory.lcEconomy,
                &"{houseId} Build order REJECTED: Total squadron limit exceeded " &
                &"(commissioned={violation.current}, queued={underConstruction}, " &
                &"max={violation.maximum}, ship={shipClass}). " &
                &"Increase Industrial Units to expand capacity.")
        return ValidationResult(valid: false,
                               error: &"Total squadron limit exceeded " &
                                      &"({violation.current}+{underConstruction}/{violation.maximum}). " &
                                      &"Requires more Industrial Units.")

    # Check planet-breaker limit (1 per colony owned, assets.md:2.4.8)
    # TODO use new economy/capacity planet_breakers module
    if shipClass == ShipClass.PlanetBreaker:
      let currentPBs = state.houses[houseId].planetBreakerCount
      let maxPBs = state.getPlanetBreakerLimit(houseId)

      # Count planet-breakers under construction house-wide
      var pbsUnderConstruction = 0
      for colId, col in state.colonies:
        if col.owner == houseId:
          pbsUnderConstruction += col.constructionQueue.filterIt(
            it.projectType == ConstructionType.Ship and
            it.itemId == "PlanetBreaker"
          ).len

      if currentPBs + pbsUnderConstruction + 1 > maxPBs:
        ctx.rejectedOrders += 1
        logWarn(LogCategory.lcEconomy,
                &"{houseId} Build order REJECTED: Planet-breaker limit exceeded " &
                &"(current={currentPBs}, queued={pbsUnderConstruction}, max={maxPBs} [1 per colony])")
        return ValidationResult(valid: false,
                               error: &"Planet-breaker limit exceeded ({currentPBs}+{pbsUnderConstruction}/{maxPBs}, limited to 1 per colony)")

  # Calculate cost
  let cost = calculateBuildOrderCost(order, state)
  if cost <= 0:
    return ValidationResult(valid: false,
                           error: &"Build order: Invalid cost calculation ({cost} PP)")

  # Check budget
  let remaining = ctx.getRemainingBudget()
  if cost > remaining:
    ctx.rejectedOrders += 1
    logInfo(LogCategory.lcEconomy,
            &"Build order rejected: need {cost} PP, have {remaining} PP remaining " &
            &"(treasury={ctx.availableTreasury}, committed={ctx.committedSpending})")
    return ValidationResult(valid: false,
                           error: &"Insufficient funds: need {cost} PP, have {remaining} PP remaining")

  # Valid - commit spending
  ctx.committedSpending += cost
  logDebug(LogCategory.lcEconomy,
           &"Build order validated: {cost} PP committed, {ctx.getRemainingBudget()} PP remaining")

  return ValidationResult(valid: true, error: "")

proc previewOrderPacketCost*(packet: OrderPacket, state: GameState): OrderCostSummary =
  ## Calculate total costs for an order packet without committing
  ## Useful for UI preview before submission
  result = OrderCostSummary(
    buildCosts: 0,
    researchCosts: 0,
    espionageCosts: 0,
    totalCost: 0,
    canAfford: false,
    errors: @[],
    warnings: @[]
  )

  # Calculate build costs
  for order in packet.buildOrders:
    let cost = calculateBuildOrderCost(order, state)
    if cost > 0:
      result.buildCosts += cost
    else:
      result.warnings.add(&"Build order at {order.colonySystem}: cost calculation failed")

  # Calculate research costs
  result.researchCosts = packet.researchAllocation.economic +
                        packet.researchAllocation.science
  for field, amount in packet.researchAllocation.technology:
    result.researchCosts += amount

  # Calculate espionage costs (40 PP per EBP/CIP)
  result.espionageCosts = (packet.ebpInvestment + packet.cipInvestment) * 40

  # Total
  result.totalCost = result.buildCosts + result.researchCosts + result.espionageCosts

  # Check affordability
  if packet.houseId in state.houses:
    let house = state.houses[packet.houseId]
    result.canAfford = house.treasury >= result.totalCost

    if not result.canAfford:
      result.errors.add(&"Insufficient funds: need {result.totalCost} PP, have {house.treasury} PP")

    # Warnings for spending >90% of treasury
    if result.totalCost > (house.treasury * 9 div 10):
      result.warnings.add(&"Warning: Spending {result.totalCost}/{house.treasury} PP (>90% of treasury)")
  else:
    result.errors.add(&"House {packet.houseId} not found")

  logInfo(LogCategory.lcEconomy,
          &"{packet.houseId} Order Cost Preview: Build={result.buildCosts}PP, " &
          &"Research={result.researchCosts}PP, Espionage={result.espionageCosts}PP, " &
          &"Total={result.totalCost}PP, CanAfford={result.canAfford}")
