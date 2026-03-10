import std/[options, sequtils, strutils, tables, unittest]

import ../../src/engine/types/[core, event, fleet, player_state]
import ../../src/player/tui/reports

proc mkVisibleSystem(
    systemId: int,
    name: string,
    visibility: VisibilityLevel,
    planetClass: int32 = -1,
    resourceRating: int32 = -1
): VisibleSystem =
  VisibleSystem(
    systemId: SystemId(systemId),
    name: name,
    visibility: visibility,
    lastScoutedTurn: none(int32),
    planetClass: planetClass,
    resourceRating: resourceRating,
    coordinates: none(tuple[q: int32, r: int32]),
    jumpLaneIds: @[]
  )

proc mkFleet(id: int, name: string, location: int): Fleet =
  Fleet(
    id: FleetId(id),
    name: name,
    ships: @[],
    houseId: HouseId(1),
    location: SystemId(location),
    status: FleetStatus.Active,
    roe: 6,
    command: FleetCommand(
      fleetId: FleetId(id),
      commandType: FleetCommandType.Hold,
      targetSystem: none(SystemId),
      targetFleet: none(FleetId),
      priority: 0,
      roe: none(int32)
    ),
    missionState: MissionState.None,
    missionTarget: none(SystemId),
    missionStartTurn: 0
  )

suite "TUI reports":
  test "visibility upgrade alone does not create survey report":
    var prevSystems = initTable[SystemId, VisibleSystem]()
    var currSystems = initTable[SystemId, VisibleSystem]()
    prevSystems[SystemId(5)] = mkVisibleSystem(
      5,
      "Paisios",
      VisibilityLevel.Adjacent
    )
    currSystems[SystemId(5)] = mkVisibleSystem(
      5,
      "Paisios",
      VisibilityLevel.Scouted,
      2,
      3
    )

    let prevPs = PlayerState(
      viewingHouse: HouseId(1),
      turn: 1,
      visibleSystems: prevSystems
    )
    let currPs = PlayerState(
      viewingHouse: HouseId(1),
      turn: 2,
      visibleSystems: currSystems
    )

    let items = generateClientReports(currPs, some(prevPs))
    check items.allIt(not it.title.contains("Surveyed"))

  test "view world intel report names surveying fleet":
    var systems = initTable[SystemId, VisibleSystem]()
    systems[SystemId(5)] = mkVisibleSystem(
      5,
      "Paisios",
      VisibilityLevel.Scouted,
      2,
      3
    )

    let viewEvent = GameEvent(
      turn: 2,
      houseId: some(HouseId(1)),
      systemId: some(SystemId(5)),
      description: "Gathered long-range planetary scan intelligence",
      sourceHouseId: some(HouseId(1)),
      targetHouseId: some(HouseId(1)),
      fleetId: none(FleetId),
      eventType: GameEventType.IntelGathered,
      intelType: some("long-range planetary scan")
    )
    let completedEvent = GameEvent(
      turn: 2,
      houseId: some(HouseId(1)),
      systemId: some(SystemId(5)),
      description: "scanned 5",
      sourceHouseId: none(HouseId),
      targetHouseId: none(HouseId),
      fleetId: some(FleetId(3)),
      eventType: GameEventType.CommandCompleted,
      orderType: some("ViewWorld"),
      reason: none(string)
    )

    let ps = PlayerState(
      viewingHouse: HouseId(1),
      turn: 2,
      ownFleets: @[mkFleet(3, "A3", 5)],
      visibleSystems: systems,
      turnEvents: @[viewEvent, completedEvent]
    )

    let items = generateClientReports(ps)
    check items.anyIt(it.title == "A3 Surveyed Paisios")
    check items.anyIt(it.summary.contains("A3 completed"))
