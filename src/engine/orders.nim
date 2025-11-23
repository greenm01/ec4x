## Fleet order types and validation for EC4X

import std/[options, tables]
import ../common/[hex, types/core, types/units]
import gamestate, fleet, ship
import espionage/types as esp_types
import research/types as res_types

type
  FleetOrderType* {.pure.} = enum
    Hold              # Hold position, do nothing
    Move              # Navigate to target system
    SeekHome          # Find closest friendly system
    Patrol            # Defend and intercept in system
    GuardStarbase     # Protect orbital installation
    GuardPlanet       # Planetary defense
    BlockadePlanet    # Planetary siege
    Bombard           # Orbital bombardment
    Invade            # Ground assault
    Blitz             # Combined bombardment + invasion
    Colonize          # Establish colony
    SpyPlanet         # Intelligence gathering on planet
    SpySystem         # Reconnaissance of system
    HackStarbase      # Electronic warfare
    JoinFleet         # Merge with another fleet
    Rendezvous        # Coordinate movement with fleet
    Salvage           # Recover wreckage

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

  FleetOrder* = object
    fleetId*: FleetId
    orderType*: FleetOrderType
    targetSystem*: Option[SystemId]
    targetFleet*: Option[FleetId]
    priority*: int  # Execution order within turn

  OrderPacket* = object
    houseId*: HouseId
    turn*: int
    fleetOrders*: seq[FleetOrder]
    buildOrders*: seq[BuildOrder]
    researchAllocation*: res_types.ResearchAllocation  # PP allocation to ERP/SRP/TRP
    diplomaticActions*: seq[DiplomaticAction]
    populationTransfers*: seq[PopulationTransferOrder]  # Space Guild transfers
    squadronManagement*: seq[SquadronManagementOrder]    # Ship commissioning and squadron formation

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

  DiplomaticActionType* {.pure.} = enum
    ## Diplomatic actions per diplomacy.md:8.1
    ProposeNonAggressionPact,  # Propose pact with another house
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

    # TODO: Check pathfinding - can fleet reach target?

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

    # TODO: Check if system already colonized

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

    # TODO: Check fleets are in same location

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

  # TODO: Validate build orders (check resources, production capacity)
  # TODO: Validate research allocation (check total points available)
  # TODO: Validate diplomatic actions (check diplomatic state)

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
    squadronManagement: @[]
  )

proc addFleetOrder*(packet: var OrderPacket, order: FleetOrder) =
  ## Add a fleet order to packet
  packet.fleetOrders.add(order)

proc addBuildOrder*(packet: var OrderPacket, order: BuildOrder) =
  ## Add a build order to packet
  packet.buildOrders.add(order)
