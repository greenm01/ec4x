## Fleet order types and validation for EC4X

import std/[options, tables]
import ../common/[types, hex]
import gamestate, fleet, ship

type
  FleetOrderType* = enum
    foHold              # Hold position, do nothing
    foMove              # Navigate to target system
    foSeekHome          # Find closest friendly system
    foPatrol            # Defend and intercept in system
    foGuardStarbase     # Protect orbital installation
    foGuardPlanet       # Planetary defense
    foBlockadePlanet    # Planetary siege
    foBombard           # Orbital bombardment
    foInvade            # Ground assault
    foBlitz             # Combined bombardment + invasion
    foColonize          # Establish colony
    foSpyPlanet         # Intelligence gathering on planet
    foSpySystem         # Reconnaissance of system
    foHackStarbase      # Electronic warfare
    foJoinFleet         # Merge with another fleet
    foRendezvous        # Coordinate movement with fleet
    foSalvage           # Recover wreckage

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
    researchAllocation*: Table[TechField, int]
    diplomaticActions*: seq[DiplomaticAction]

  BuildOrder* = object
    colonySystem*: SystemId
    buildType*: BuildType
    quantity*: int

  BuildType* = enum
    btShip, btBuilding, btInfrastructure

  DiplomaticAction* = object
    targetHouse*: HouseId
    actionType*: DiplomaticActionType
    message*: string

  DiplomaticActionType* = enum
    daProposeAlliance, daDeclarWar, daSendMessage, daBreakTreaty

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
  of foHold:
    # Always valid
    discard

  of foMove:
    if order.targetSystem.isNone:
      return ValidationResult(valid: false, error: "Move order requires target system")

    let targetId = order.targetSystem.get()
    if not state.starMap.systems.hasKey(targetId):
      return ValidationResult(valid: false, error: "Target system does not exist")

    # TODO: Check pathfinding - can fleet reach target?

  of foColonize:
    # Check fleet has colony ship
    var hasColonyShip = false
    for ship in fleet.ships:
      if ship.shipType == Spacelift and not ship.isCrippled:
        hasColonyShip = true
        break

    if not hasColonyShip:
      return ValidationResult(valid: false, error: "Colonize requires functional spacelift ship")

    if order.targetSystem.isNone:
      return ValidationResult(valid: false, error: "Colonize order requires target system")

    # TODO: Check if system already colonized

  of foBombard, foInvade, foBlitz:
    # Check fleet has military ships
    var hasMilitary = false
    for ship in fleet.ships:
      if ship.shipType == Military and not ship.isCrippled:
        hasMilitary = true
        break

    if not hasMilitary:
      return ValidationResult(valid: false, error: "Combat order requires functional military ships")

    if order.targetSystem.isNone:
      return ValidationResult(valid: false, error: "Combat order requires target system")

  of foJoinFleet:
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
    orderType: foMove,
    targetSystem: some(targetSystem),
    targetFleet: none(FleetId),
    priority: priority
  )

proc createColonizeOrder*(fleetId: FleetId, targetSystem: SystemId, priority: int = 0): FleetOrder =
  ## Create a colonization order
  result = FleetOrder(
    fleetId: fleetId,
    orderType: foColonize,
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
    orderType: foHold,
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
    researchAllocation: initTable[TechField, int](),
    diplomaticActions: @[]
  )

proc addFleetOrder*(packet: var OrderPacket, order: FleetOrder) =
  ## Add a fleet order to packet
  packet.fleetOrders.add(order)

proc addBuildOrder*(packet: var OrderPacket, order: BuildOrder) =
  ## Add a build order to packet
  packet.buildOrders.add(order)
