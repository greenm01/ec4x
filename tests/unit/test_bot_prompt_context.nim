import std/[unittest, options, tables, strutils]

import ../../src/bot/prompt_context
import ../../src/engine/types/[core, player_state]
import ../../src/engine/types/diplomacy

suite "bot prompt context":
  test "builds key sections":
    var state = PlayerState(
      viewingHouse: HouseId(1),
      turn: 7'i32,
      treasuryBalance: some(120'i32),
      netIncome: some(14'i32),
      ebpPool: some(2'i32),
      cipPool: some(1'i32),
      taxRate: some(20'i32),
      ownColonies: @[],
      ownFleets: @[],
      ownShips: @[],
      visibleColonies: @[],
      visibleFleets: @[],
      turnEvents: @[],
      visibleSystems: initTable[SystemId, VisibleSystem](),
      housePrestige: initTable[HouseId, int32](),
      houseColonyCounts: initTable[HouseId, int32](),
      houseNames: initTable[HouseId, string](),
      diplomaticRelations: initTable[(HouseId, HouseId), DiplomaticState](),
      ltuSystems: initTable[SystemId, int32](),
      ltuColonies: initTable[ColonyId, int32](),
      ltuFleets: initTable[FleetId, int32]()
    )
    state.houseNames[HouseId(1)] = "Atreides"
    state.houseNames[HouseId(2)] = "Harkonnen"
    state.housePrestige[HouseId(2)] = 33
    state.housePrestige[HouseId(1)] = 40
    state.houseColonyCounts[HouseId(1)] = 4
    state.houseColonyCounts[HouseId(2)] = 2
    state.visibleSystems[SystemId(11)] = VisibleSystem(
      systemId: SystemId(11),
      name: "Arrakis",
      visibility: VisibilityLevel.Owned
    )

    let context = buildTurnContext(state)
    check context.contains("# EC4X Bot Turn Context")
    check context.contains("## Strategic Overview")
    check context.contains("Viewing House: Atreides")
    check context.contains("## Visible Intel")
    check context.contains("11 Arrakis")

  test "public standings are deterministic by house id":
    var state = PlayerState(
      viewingHouse: HouseId(1),
      turn: 3'i32,
      ownColonies: @[],
      ownFleets: @[],
      ownShips: @[],
      visibleColonies: @[],
      visibleFleets: @[],
      turnEvents: @[],
      visibleSystems: initTable[SystemId, VisibleSystem](),
      housePrestige: initTable[HouseId, int32](),
      houseColonyCounts: initTable[HouseId, int32](),
      houseNames: initTable[HouseId, string](),
      diplomaticRelations: initTable[(HouseId, HouseId), DiplomaticState](),
      ltuSystems: initTable[SystemId, int32](),
      ltuColonies: initTable[ColonyId, int32](),
      ltuFleets: initTable[FleetId, int32]()
    )
    state.houseNames[HouseId(2)] = "B"
    state.houseNames[HouseId(1)] = "A"
    state.housePrestige[HouseId(2)] = 5
    state.housePrestige[HouseId(1)] = 6

    let context = buildTurnContext(state)
    let aIdx = context.find("A: prestige=6")
    let bIdx = context.find("B: prestige=5")
    check aIdx >= 0
    check bIdx >= 0
    check aIdx < bIdx
