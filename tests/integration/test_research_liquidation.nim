## Integration Test: Research Liquidation Behavior
##
## Verifies that:
## 1. Liquidation applies only to accumulated RP from prior turns
## 2. Same-turn deposits are not liquidated
## 3. Prestige penalty applies once when liquidation actually occurs

import std/[unittest, random, tables, sequtils, options]
import ../../src/engine/engine
import ../../src/engine/types/[core, command, tech, event]
import ../../src/engine/state/iterators
import ../../src/engine/state/engine
import ../../src/engine/turn_cycle/command_phase
import ../../src/engine/systems/tech/costs
import ../../src/engine/globals

proc grossHouseOutput(state: GameState, houseId: HouseId): int32 =
  for colony in state.coloniesOwned(houseId):
    result += colony.production
  if result <= 0:
    result = 1

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

suite "Research Liquidation":

  test "liquidation applies prestige penalty once and only uses accumulated RP":
    var state = newGame(gameName = "Research Liquidation Test")
    let houseId = state.allHouses().toSeq[0].id
    let gho = grossHouseOutput(state, houseId)

    var house = state.house(houseId).get()
    house.treasury = 100
    house.techTree.accumulated.srp = 20
    state.updateHouse(houseId, house)

    let startingPrestige = house.prestige
    let addedRP = convertPPToSRP(10, gho, house.techTree.levels.sl)

    var orders = initTable[HouseId, CommandPacket]()
    var packet = emptyPacket(houseId, state.turn)
    packet.researchDeposits.srp = 10
    packet.researchLiquidation.srp = 10
    orders[houseId] = packet

    var events: seq[GameEvent] = @[]
    var rng = initRand(42)
    state.resolveCommandPhase(orders, events, rng)

    let updated = state.house(houseId).get()
    check updated.treasury == 95
    check updated.techTree.accumulated.srp == 10 + addedRP
    check updated.prestige ==
      startingPrestige + gameConfig.prestige.penalties.researchLiquidation

  test "no prestige penalty when liquidation request exceeds zero accumulated RP":
    var state = newGame(gameName = "Research Liquidation Clamp Test")
    let houseId = state.allHouses().toSeq[0].id
    let gho = grossHouseOutput(state, houseId)

    var house = state.house(houseId).get()
    house.treasury = 100
    house.techTree.accumulated.srp = 0
    state.updateHouse(houseId, house)

    let startingPrestige = house.prestige
    let addedRP = convertPPToSRP(10, gho, house.techTree.levels.sl)

    var orders = initTable[HouseId, CommandPacket]()
    var packet = emptyPacket(houseId, state.turn)
    packet.researchDeposits.srp = 10
    packet.researchLiquidation.srp = 10
    orders[houseId] = packet

    var events: seq[GameEvent] = @[]
    var rng = initRand(99)
    state.resolveCommandPhase(orders, events, rng)

    let updated = state.house(houseId).get()
    check updated.treasury == 90
    check updated.techTree.accumulated.srp == addedRP
    check updated.prestige == startingPrestige
