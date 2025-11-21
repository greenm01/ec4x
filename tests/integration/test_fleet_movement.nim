## Fleet Movement Integration Tests
##
## Test fleet movement with pathfinding and lane traversal rules
## Per operations.md:6.1 and 6.2

import std/[unittest, tables, options, strformat]
import ../../src/engine/[gamestate, starmap, fleet, ship, squadron, orders, resolve]
import ../../src/common/types/[core, units, combat]
import ../../src/common/[hex, system]

suite "Fleet Movement Integration":

  proc createTestGameState(): GameState =
    ## Create a simple game state with a linear star map for testing
    ## Systems: 1 -- 2 -- 3 -- 4 -- 5 (all major lanes)
    result = GameState()
    result.turn = 1
    result.year = 2501
    result.month = 1
    result.phase = GamePhase.Active

    # Create a simple linear starmap
    result.starMap = StarMap(
      systems: initTable[uint, System](),
      lanes: @[],
      adjacency: initTable[uint, seq[uint]](),
      playerCount: 2,
      numRings: 5,
      hubId: 0,
      playerSystemIds: @[]
    )

    # Add 5 systems in a line
    for i in 1u..5u:
      result.starMap.systems[i] = System(
        id: i,
        coords: hex(int(i), 0),
        ring: uint32(i),
        player: none(uint)
      )

    # Add major lanes connecting them
    for i in 1u..4u:
      result.starMap.lanes.add(JumpLane(
        source: i,
        destination: i + 1,
        laneType: LaneType.Major
      ))

      # Update adjacency
      if i notin result.starMap.adjacency:
        result.starMap.adjacency[i] = @[]
      if (i + 1) notin result.starMap.adjacency:
        result.starMap.adjacency[i + 1] = @[]
      result.starMap.adjacency[i].add(i + 1)
      result.starMap.adjacency[i + 1].add(i)

    # Create two houses
    result.houses[HouseId("house-alpha")] = House(
      id: "house-alpha",
      name: "House Alpha",
      treasury: 10000,
      eliminated: false
    )

    result.houses[HouseId("house-beta")] = House(
      id: "house-beta",
      name: "House Beta",
      treasury: 10000,
      eliminated: false
    )

    # House Alpha owns systems 1, 2, 3
    for sysId in 1u..3u:
      result.colonies[sysId] = Colony(
        systemId: sysId,
        owner: "house-alpha",
        population: 100,
        infrastructure: 50
      )

    # House Beta owns systems 4, 5
    for sysId in 4u..5u:
      result.colonies[sysId] = Colony(
        systemId: sysId,
        owner: "house-beta",
        population: 100,
        infrastructure: 50
      )

  test "Single jump movement - friendly territory":
    var state = createTestGameState()

    # Create fleet at system 1
    let testFleet = newFleet(
      ships = @[newShip(ShipType.Military)],
      id = "fleet-1",
      owner = "house-alpha",
      location = 1
    )
    state.fleets["fleet-1"] = testFleet

    # Create movement order to system 2
    let order = FleetOrder(
      fleetId: "fleet-1",
      orderType: foMove,
      targetSystem: some(2u),
      targetFleet: none(FleetId),
      priority: 1
    )

    var events: seq[GameEvent] = @[]
    resolveMovementOrder(state, "house-alpha", order, events)

    # Fleet should have moved to system 2
    check state.fleets["fleet-1"].location == 2u

  test "Two jump movement - all friendly major lanes":
    var state = createTestGameState()

    # Create fleet at system 1
    let testFleet = newFleet(
      ships = @[newShip(ShipType.Military)],
      id = "fleet-1",
      owner = "house-alpha",
      location = 1
    )
    state.fleets["fleet-1"] = testFleet

    # Order to system 3 (2 jumps away, all friendly)
    let order = FleetOrder(
      fleetId: "fleet-1",
      orderType: foMove,
      targetSystem: some(3u),
      targetFleet: none(FleetId),
      priority: 1
    )

    var events: seq[GameEvent] = @[]
    resolveMovementOrder(state, "house-alpha", order, events)

    # Fleet should have moved 2 jumps to system 3 (all friendly major lanes)
    check state.fleets["fleet-1"].location == 3u

  test "One jump into enemy territory":
    var state = createTestGameState()

    # Create fleet at system 3 (Alpha's border)
    let testFleet = newFleet(
      ships = @[newShip(ShipType.Military)],
      id = "fleet-1",
      owner = "house-alpha",
      location = 3
    )
    state.fleets["fleet-1"] = testFleet

    # Order to system 5 (2 jumps away, but through enemy territory)
    let order = FleetOrder(
      fleetId: "fleet-1",
      orderType: foMove,
      targetSystem: some(5u),
      targetFleet: none(FleetId),
      priority: 1
    )

    var events: seq[GameEvent] = @[]
    resolveMovementOrder(state, "house-alpha", order, events)

    # Fleet should only move 1 jump (system 4) due to enemy territory
    check state.fleets["fleet-1"].location == 4u

  test "Fleet already at destination":
    var state = createTestGameState()

    let testFleet = newFleet(
      ships = @[newShip(ShipType.Military)],
      id = "fleet-1",
      owner = "house-alpha",
      location = 2
    )
    state.fleets["fleet-1"] = testFleet

    # Order to same location
    let order = FleetOrder(
      fleetId: "fleet-1",
      orderType: foMove,
      targetSystem: some(2u),
      targetFleet: none(FleetId),
      priority: 1
    )

    var events: seq[GameEvent] = @[]
    resolveMovementOrder(state, "house-alpha", order, events)

    # Fleet should remain at system 2
    check state.fleets["fleet-1"].location == 2u

  test "Restricted lane - spacelift ships blocked":
    var state = createTestGameState()

    # Clear lanes and add restricted lane between systems 2 and 3
    state.starMap.lanes = @[]
    state.starMap.adjacency = initTable[uint, seq[uint]]()

    state.starMap.lanes.add(JumpLane(
      source: 1,
      destination: 2,
      laneType: LaneType.Major
    ))
    state.starMap.adjacency[1] = @[2u]
    state.starMap.adjacency[2] = @[1u, 3u]

    state.starMap.lanes.add(JumpLane(
      source: 2,
      destination: 3,
      laneType: LaneType.Restricted
    ))
    state.starMap.adjacency[3] = @[2u]

    # Create fleet with spacelift ship at system 2
    let testFleet = newFleet(
      ships = @[newShip(ShipType.Spacelift)],
      id = "fleet-1",
      owner = "house-alpha",
      location = 2
    )
    state.fleets["fleet-1"] = testFleet

    # Order to system 3 (across restricted lane)
    let order = FleetOrder(
      fleetId: "fleet-1",
      orderType: foMove,
      targetSystem: some(3u),
      targetFleet: none(FleetId),
      priority: 1
    )

    var events: seq[GameEvent] = @[]
    resolveMovementOrder(state, "house-alpha", order, events)

    # Fleet should NOT move (blocked by restricted lane)
    check state.fleets["fleet-1"].location == 2u

  test "Fleet encounter detection":
    var state = createTestGameState()

    # Create Alpha fleet at system 1
    let fleet1 = newFleet(
      ships = @[newShip(ShipType.Military)],
      id = "fleet-alpha",
      owner = "house-alpha",
      location = 1
    )
    state.fleets["fleet-alpha"] = fleet1

    # Create Beta fleet at system 2
    let fleet2 = newFleet(
      ships = @[newShip(ShipType.Military)],
      id = "fleet-beta",
      owner = "house-beta",
      location = 2
    )
    state.fleets["fleet-beta"] = fleet2

    # Alpha fleet moves to system 2
    let order = FleetOrder(
      fleetId: "fleet-alpha",
      orderType: foMove,
      targetSystem: some(2u),
      targetFleet: none(FleetId),
      priority: 1
    )

    var events: seq[GameEvent] = @[]
    resolveMovementOrder(state, "house-alpha", order, events)

    # Both fleets should now be at system 2
    check state.fleets["fleet-alpha"].location == 2u
    check state.fleets["fleet-beta"].location == 2u

when isMainModule:
  echo "╔════════════════════════════════════════════════╗"
  echo "║  Fleet Movement Integration Tests             ║"
  echo "╚════════════════════════════════════════════════╝"
