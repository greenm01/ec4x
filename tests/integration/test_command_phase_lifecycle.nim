## Integration Tests for Command Phase Lifecycle
##
## Verifies that:
## 1. Orders completed earlier in the turn are cleaned up and not re-stored
## 2. Completed colonize orders are not re-rejected after ETAC consumption
## 3. Incomplete movement orders remain active for Production Phase travel

import std/[unittest, options, random, tables, sequtils]

import ../../src/engine/engine
import ../../src/engine/starmap
import ../../src/engine/types/[command, core, event, fleet, ship, tech,
  colony]
import ../../src/engine/state/[engine, iterators]
import ../../src/engine/entities/ship_ops
import ../../src/engine/systems/command/commands
import ../../src/engine/turn_cycle/[command_phase, engine as turn_engine]
import ../../src/engine/event_factory/init

proc emptyPacket(houseId: HouseId, turn: int32): CommandPacket =
  CommandPacket(
    houseId: houseId,
    turn: turn,
    zeroTurnCommands: @[],
    fleetCommands: @[],
    buildCommands: @[],
    repairCommands: @[],
    scrapCommands: @[],
    researchDeposits: ResearchDeposits(),
    techPurchases: TechPurchaseSet(),
    researchLiquidation: ResearchLiquidation(),
    diplomaticCommand: @[],
    populationTransfers: @[],
    terraformCommands: @[],
    colonyManagement: @[],
    espionageActions: @[],
    ebpInvestment: 0,
    cipInvestment: 0
  )

proc firstOwnedColony(state: GameState, houseId: HouseId): Colony =
  for colony in state.coloniesOwned(houseId):
    return colony
  raise newException(ValueError, "house has no colony")

proc firstFleetWithShipClass(
    state: GameState,
    houseId: HouseId,
    shipClass: ShipClass
): Fleet =
  for fleet in state.fleetsOwned(houseId):
    for shipId in fleet.ships:
      let ship = state.ship(shipId).get()
      if ship.shipClass == shipClass:
        return fleet
  raise newException(ValueError, "matching fleet not found")

suite "Command Phase Lifecycle":

  test "completed colonize orders are cleaned up instead of re-rejected":
    var state = newGame(gameName = "Command Lifecycle Colonize")
    let houseId = state.allHouses().toSeq[0].id
    let colony = state.firstOwnedColony(houseId)
    let targetSystem = state.starMap.adjacentSystems(colony.systemId)[0]
    let colonizeFleet = state.firstFleetWithShipClass(houseId, ShipClass.ETAC)

    var packet = emptyPacket(houseId, state.turn)
    let colonizeCommand = FleetCommand(
      fleetId: colonizeFleet.id,
      commandType: FleetCommandType.Colonize,
      targetSystem: some(targetSystem),
      targetFleet: none(FleetId),
      priority: 0,
      roe: none(int32)
    )
    packet.fleetCommands = @[colonizeCommand]

    var fleetMut = state.fleet(colonizeFleet.id).get()
    fleetMut.command = colonizeCommand
    fleetMut.missionState = MissionState.Executing
    fleetMut.missionTarget = some(targetSystem)
    state.updateFleet(colonizeFleet.id, fleetMut)

    for shipId in colonizeFleet.ships:
      let ship = state.ship(shipId).get()
      if ship.shipClass == ShipClass.ETAC:
        state.destroyShip(shipId)
        break

    var orders = initTable[HouseId, CommandPacket]()
    orders[houseId] = packet

    var events: seq[GameEvent] = @[
      commandCompleted(
        houseId,
        colonizeFleet.id,
        "Colonize",
        details = "colony established",
        systemId = some(targetSystem),
      )
    ]
    var rng = initRand(7)

    state.resolveCommandPhase(orders, events, rng)

    let updatedFleet = state.fleet(colonizeFleet.id).get()
    check updatedFleet.command.commandType == FleetCommandType.Hold
    check updatedFleet.missionState == MissionState.None
    check updatedFleet.missionTarget.isNone

    let rejectionCount = events.countIt(
      it.eventType == GameEventType.CommandRejected and
      it.fleetId == some(colonizeFleet.id)
    )
    check rejectionCount == 0

  test "completed move orders stay cleaned up on next command phase":
    var state = newGame(gameName = "Command Lifecycle Move Complete")
    let houseId = state.allHouses().toSeq[0].id
    let moveFleet = state.firstFleetWithShipClass(houseId, ShipClass.Destroyer)
    let targetSystem = state.starMap.adjacentSystems(moveFleet.location)[0]

    var packet = emptyPacket(houseId, state.turn)
    let moveCommand = FleetCommand(
      fleetId: moveFleet.id,
      commandType: FleetCommandType.Move,
      targetSystem: some(targetSystem),
      targetFleet: none(FleetId),
      priority: 0,
      roe: some(6'i32)
    )
    packet.fleetCommands = @[moveCommand]

    var fleetMut = state.fleet(moveFleet.id).get()
    fleetMut.location = targetSystem
    fleetMut.command = moveCommand
    fleetMut.missionState = MissionState.Executing
    fleetMut.missionTarget = some(targetSystem)
    state.updateFleet(moveFleet.id, fleetMut)

    var orders = initTable[HouseId, CommandPacket]()
    orders[houseId] = packet

    var events: seq[GameEvent] = @[
      commandCompleted(
        houseId,
        moveFleet.id,
        "Move",
        details = "arrived at destination",
        systemId = some(targetSystem),
      )
    ]
    var rng = initRand(11)

    state.resolveCommandPhase(orders, events, rng)

    let updatedFleet = state.fleet(moveFleet.id).get()
    check updatedFleet.location == targetSystem
    check updatedFleet.command.commandType == FleetCommandType.Hold
    check updatedFleet.missionState == MissionState.None
    check updatedFleet.missionTarget.isNone

  test "incomplete move orders remain active for production travel":
    var state = newGame(gameName = "Command Lifecycle Move Active")
    let houseId = state.allHouses().toSeq[0].id
    let moveFleet = state.firstFleetWithShipClass(houseId, ShipClass.Destroyer)
    let targetSystem = state.starMap.adjacentSystems(moveFleet.location)[0]

    var packet = emptyPacket(houseId, state.turn)
    let moveCommand = FleetCommand(
      fleetId: moveFleet.id,
      commandType: FleetCommandType.Move,
      targetSystem: some(targetSystem),
      targetFleet: none(FleetId),
      priority: 0,
      roe: some(6'i32)
    )
    packet.fleetCommands = @[moveCommand]

    var orders = initTable[HouseId, CommandPacket]()
    orders[houseId] = packet

    var events: seq[GameEvent] = @[]
    var rng = initRand(17)

    state.resolveCommandPhase(orders, events, rng)

    let updatedFleet = state.fleet(moveFleet.id).get()
    check updatedFleet.command.commandType == FleetCommandType.Move
    check updatedFleet.command.targetSystem == some(targetSystem)
    check updatedFleet.missionState == MissionState.Traveling
    check updatedFleet.missionTarget == some(targetSystem)

  test "production-completed move orders are reset before next player turn":
    var state = newGame(gameName = "Production Cleanup Move")
    let houseId = state.allHouses().toSeq[0].id
    let moveFleet = state.firstFleetWithShipClass(houseId, ShipClass.Destroyer)
    let targetSystem = state.starMap.adjacentSystems(moveFleet.location)[0]

    var packet = emptyPacket(houseId, state.turn)
    packet.fleetCommands = @[FleetCommand(
      fleetId: moveFleet.id,
      commandType: FleetCommandType.Move,
      targetSystem: some(targetSystem),
      targetFleet: none(FleetId),
      priority: 0,
      roe: some(6'i32)
    )]

    var orders = initTable[HouseId, CommandPacket]()
    orders[houseId] = packet

    var rng = initRand(23)
    discard turn_engine.resolveTurn(state, orders, rng)

    let updatedFleet = state.fleet(moveFleet.id).get()
    check updatedFleet.location == targetSystem
    check updatedFleet.command.commandType == FleetCommandType.Hold
    check updatedFleet.missionState == MissionState.None
    check updatedFleet.missionTarget.isNone
