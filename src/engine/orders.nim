## Fleet order types and validation for EC4X

import std/[options, tables, strformat]
import ../common/[hex, types/core, types/units]
import gamestate, fleet, ship, spacelift, starmap, logger
import order_types  # Import and re-export fleet order types
import espionage/types as esp_types
import research/types as res_types
import economy/construction  # For cost calculation

# Re-export order types
export order_types.FleetOrderType, order_types.FleetOrder

type
  SquadronManagementAction* {.pure.} = enum
    ## Squadron and ship management actions at colonies
    TransferShip      # Move ship directly between squadrons at colony
    AssignToFleet     # Assign squadron to fleet (new or existing)

  SquadronManagementOrder* = object
    ## Order to form squadrons, transfer ships, or assign to fleets at colonies
    houseId*: HouseId
    colonySystem*: SystemId              # Colony where action takes place
    action*: SquadronManagementAction

    # For FormSquadron: select ships from commissioning pool
    shipIndices*: seq[int]               # Indices into colony.commissionedShips
    newSquadronId*: Option[string]       # Optional custom squadron ID

    # For TransferShip: move ship between squadrons
    sourceSquadronId*: Option[string]    # Squadron to transfer from
    targetSquadronId*: Option[string]    # Squadron to transfer to (or create new)
    shipIndex*: Option[int]              # Index of ship in source squadron

    # For AssignToFleet: assign squadron to fleet
    squadronId*: Option[string]          # Squadron to assign
    targetFleetId*: Option[FleetId]      # Fleet to assign to (or create new)

  CargoManagementAction* {.pure.} = enum
    ## Cargo loading/unloading actions at colonies
    LoadCargo      # Load marines or colonists onto spacelift ships
    UnloadCargo    # Unload cargo from spacelift ships

  CargoManagementOrder* = object
    ## Order to load/unload cargo on spacelift ships at colonies
    houseId*: HouseId
    colonySystem*: SystemId              # Colony where action takes place
    action*: CargoManagementAction
    fleetId*: FleetId                    # Fleet containing spacelift ships
    cargoType*: Option[CargoType]        # Type of cargo (Marines, Colonists)
    quantity*: Option[int]               # Amount to load/unload (0 = all available)

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
    fleetOrders*: seq[FleetOrder]
    buildOrders*: seq[BuildOrder]
    researchAllocation*: res_types.ResearchAllocation  # PP allocation to ERP/SRP/TRP
    diplomaticActions*: seq[DiplomaticAction]
    populationTransfers*: seq[PopulationTransferOrder]  # Space Guild transfers
    squadronManagement*: seq[SquadronManagementOrder]    # Ship commissioning and squadron formation
    cargoManagement*: seq[CargoManagementOrder]          # Cargo loading/unloading at colonies
    terraformOrders*: seq[TerraformOrder]                # Terraforming projects

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
    ProposeNonAggressionPact,  # Propose pact with another house
    AcceptProposal,            # Accept pending proposal
    RejectProposal,            # Reject pending proposal
    WithdrawProposal,          # Cancel own proposal
    BreakPact,                 # Break existing non-aggression pact
    DeclareEnemy,              # Set diplomatic status to Enemy
    SetNeutral                 # Set diplomatic status to Neutral

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

proc validateFleetOrder*(order: FleetOrder, state: GameState): ValidationResult =
  ## Validate a fleet order against current game state
  result = ValidationResult(valid: true, error: "")

  # Check fleet exists
  let fleetOpt = state.getFleet(order.fleetId)
  if fleetOpt.isNone:
    return ValidationResult(valid: false, error: "Fleet does not exist")

  let fleet = fleetOpt.get()

  # Validate based on order type
  case order.orderType
  of FleetOrderType.Hold:
    # Always valid
    discard

  of FleetOrderType.Move:
    if order.targetSystem.isNone:
      return ValidationResult(valid: false, error: "Move order requires target system")

    let targetId = order.targetSystem.get()
    if not state.starMap.systems.hasKey(targetId):
      return ValidationResult(valid: false, error: "Target system does not exist")

    # Check pathfinding - can fleet reach target?
    let pathResult = state.starMap.findPath(fleet.location, targetId, fleet)
    if not pathResult.found:
      return ValidationResult(valid: false, error: "No valid path to target system")

  of FleetOrderType.Colonize:
    # Check fleet has spacelift squadron
    var hasColonyShip = false
    for squadron in fleet.squadrons:
      if squadron.flagship.shipClass in [ShipClass.TroopTransport, ShipClass.ETAC]:
        if not squadron.flagship.isCrippled:
          hasColonyShip = true
          break

    if not hasColonyShip:
      return ValidationResult(valid: false, error: "Colonize requires functional spacelift squadron")

    if order.targetSystem.isNone:
      return ValidationResult(valid: false, error: "Colonize order requires target system")

    # Check if system already colonized
    let targetId = order.targetSystem.get()
    if targetId in state.colonies:
      return ValidationResult(valid: false, error: "Target system is already colonized")

  of FleetOrderType.Bombard, FleetOrderType.Invade, FleetOrderType.Blitz:
    # Check fleet has combat squadrons
    var hasMilitary = false
    for squadron in fleet.squadrons:
      if squadron.flagship.stats.attackStrength > 0:
        hasMilitary = true
        break

    if not hasMilitary:
      return ValidationResult(valid: false, error: "Combat order requires combat-capable squadrons")

    if order.targetSystem.isNone:
      return ValidationResult(valid: false, error: "Combat order requires target system")

  of FleetOrderType.SpyPlanet, FleetOrderType.SpySystem, FleetOrderType.HackStarbase:
    # Spy missions require single-scout squadrons for stealth
    # Multi-ship squadrons significantly increase detection risk
    if fleet.squadrons.len != 1:
      return ValidationResult(valid: false, error: "Spy missions require single squadron")

    let squadron = fleet.squadrons[0]
    if squadron.flagship.shipClass != ShipClass.Scout:
      return ValidationResult(valid: false, error: "Spy missions require Scout squadron")

    if squadron.ships.len > 0:
      return ValidationResult(valid: false, error: "Spy missions require single-scout squadron (no additional ships)")

    if order.targetSystem.isNone:
      return ValidationResult(valid: false, error: "Spy mission requires target system")

  of FleetOrderType.JoinFleet:
    if order.targetFleet.isNone:
      return ValidationResult(valid: false, error: "Join order requires target fleet")

    let targetFleetOpt = state.getFleet(order.targetFleet.get())
    if targetFleetOpt.isNone:
      return ValidationResult(valid: false, error: "Target fleet does not exist")

    # Check fleets are in same location
    let targetFleet = targetFleetOpt.get()
    if fleet.location != targetFleet.location:
      return ValidationResult(valid: false, error: "Fleets must be in same system to join")

  else:
    # Other order types - basic validation only for now
    discard

proc validateOrderPacket*(packet: OrderPacket, state: GameState): ValidationResult =
  ## Validate entire order packet for a house
  result = ValidationResult(valid: true, error: "")

  # Check house exists
  if packet.houseId notin state.houses:
    return ValidationResult(valid: false, error: "House does not exist")

  # Check turn number matches
  if packet.turn != state.turn:
    return ValidationResult(valid: false, error: "Order packet for wrong turn")

  # Validate each fleet order
  for order in packet.fleetOrders:
    let orderResult = validateFleetOrder(order, state)
    if not orderResult.valid:
      return orderResult

  # Validate build orders (check colony ownership, production capacity)
  for order in packet.buildOrders:
    # Check colony exists and is owned by house
    if order.colonySystem notin state.colonies:
      return ValidationResult(valid: false, error: "Build order: Colony does not exist at system " & $order.colonySystem)

    let colony = state.colonies[order.colonySystem]
    if colony.owner != packet.houseId:
      return ValidationResult(valid: false, error: "Build order: House does not own colony at system " & $order.colonySystem)

    # Check for duplicate build orders at same colony (can only build one thing at a time)
    if colony.underConstruction.isSome:
      return ValidationResult(valid: false, error: "Build order: Colony at system " & $order.colonySystem & " already has active construction")

  # Validate research allocation (check total points available)
  let house = state.houses[packet.houseId]
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

proc newOrderPacket*(houseId: HouseId, turn: int): OrderPacket =
  ## Create empty order packet for a house
  result = OrderPacket(
    houseId: houseId,
    turn: turn,
    fleetOrders: @[],
    buildOrders: @[],
    researchAllocation: res_types.initResearchAllocation(),
    diplomaticActions: @[],
    squadronManagement: @[],
    cargoManagement: @[]
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

proc calculateBuildOrderCost*(order: BuildOrder, state: GameState): int =
  ## Calculate the PP cost of a build order
  ## Returns 0 if cost cannot be determined
  result = 0

  case order.buildType
  of BuildType.Ship:
    if order.shipClass.isSome:
      result = construction.getShipConstructionCost(order.shipClass.get()) * order.quantity

  of BuildType.Building:
    if order.buildingType.isSome:
      result = construction.getBuildingCost(order.buildingType.get()) * order.quantity

  of BuildType.Infrastructure:
    # Infrastructure cost depends on colony state
    if order.colonySystem in state.colonies:
      let colony = state.colonies[order.colonySystem]
      result = construction.getIndustrialUnitCost(colony) * order.industrialUnits

proc validateBuildOrderWithBudget*(order: BuildOrder, state: GameState,
                                   ctx: var OrderValidationContext): ValidationResult =
  ## Validate build order including budget check
  ## Updates context with committed spending if valid

  # Basic validation first
  if order.colonySystem notin state.colonies:
    return ValidationResult(valid: false,
                           error: &"Build order: Colony not found at system {order.colonySystem}")

  let colony = state.colonies[order.colonySystem]

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
