## Unit Tests for Order 13 (Join Fleet) Following Behavior
##
## Tests that fleets with Order 13 will pursue and follow target fleets
## even when the target moves to different systems.

import std/[unittest, tables, options, strutils]
import ../../src/engine/[gamestate, fleet, squadron, order_types, starmap]
import ../../src/engine/commands/executor
import ../../src/common/[types/core, types/units, types/planets, hex, system]

# ============================================================================
# Test Fixtures
# ============================================================================

proc createTestStarMap(): StarMap =
  ## Create a simple linear star map: System1 -> System2 -> System3 -> System4
  result = StarMap()
  result.systems = initTable[uint, System]()
  result.lanes = @[]
  result.adjacency = initTable[uint, seq[uint]]()

  # Create 4 systems in a line
  for i in 1'u..4'u:
    let coords = Hex(q: int32(i), r: 0)
    let sys = System(
      id: i,
      coords: coords,
      ring: uint32(i),
      player: none(uint),
      planetClass: PlanetClass.Benign,
      resourceRating: ResourceRating.Abundant
    )
    result.systems[i] = sys

  # Create jump lanes connecting them in a line: 1-2-3-4
  result.lanes.add(JumpLane(
    source: 1, destination: 2, laneType: LaneType.Major
  ))
  result.lanes.add(JumpLane(
    source: 2, destination: 3, laneType: LaneType.Major
  ))
  result.lanes.add(JumpLane(
    source: 3, destination: 4, laneType: LaneType.Major
  ))

  # Build adjacency for pathfinding
  result.adjacency[1] = @[2'u]
  result.adjacency[2] = @[1'u, 3'u]
  result.adjacency[3] = @[2'u, 4'u]
  result.adjacency[4] = @[3'u]

proc createTestGameState(): GameState =
  ## Create minimal game state with linear star map
  result = GameState()
  result.turn = 1
  result.starMap = createTestStarMap()
  result.fleets = initTable[FleetId, Fleet]()
  result.fleetOrders = initTable[FleetId, FleetOrder]()
  result.standingOrders = initTable[FleetId, StandingOrder]()

proc createTestFleet(id: string, owner: string, location: SystemId): Fleet =
  ## Create a simple test fleet with one squadron
  let flagship = newShip(ShipClass.Destroyer, techLevel = 1)
  let squadron = newSquadron(flagship, id = id & "_sq1", owner = owner, location = location)

  result = newFleet(
    squadrons = @[squadron],
    id = id,
    owner = owner,
    location = location,
    status = FleetStatus.Active
  )

# ============================================================================
# Order 13 Following Tests
# ============================================================================

suite "Order 13 (Join Fleet) Following Behavior":

  test "Order 13 merges fleets when at same location":
    var state = createTestGameState()

    # Both fleets at system 1
    let fleet1 = createTestFleet("fleet1", "house_alpha", 1)
    let fleet2 = createTestFleet("fleet2", "house_alpha", 1)
    state.fleets["fleet1"] = fleet1
    state.fleets["fleet2"] = fleet2

    # Fleet1 joins Fleet2
    let order = FleetOrder(
      fleetId: "fleet1",
      orderType: FleetOrderType.JoinFleet,
      targetFleet: some("fleet2"),
      priority: 0
    )

    let result = executeFleetOrder(state, fleet1.owner, order)

    check result.success
    check "fleet1" notin state.fleets  # Fleet1 should be deleted
    check "fleet2" in state.fleets      # Fleet2 should still exist

    let mergedFleet = state.fleets["fleet2"]
    check mergedFleet.squadrons.len == 2  # Should have both squadrons

  test "Order 13 moves fleet toward target when not at same location":
    var state = createTestGameState()

    # Fleet1 at system 1, Fleet2 at system 3
    let fleet1 = createTestFleet("fleet1", "house_alpha", 1)
    let fleet2 = createTestFleet("fleet2", "house_alpha", 3)
    state.fleets["fleet1"] = fleet1
    state.fleets["fleet2"] = fleet2

    # Fleet1 joins Fleet2
    let order = FleetOrder(
      fleetId: "fleet1",
      orderType: FleetOrderType.JoinFleet,
      targetFleet: some("fleet2"),
      priority: 0
    )

    let result = executeFleetOrder(state, fleet1.owner, order)

    check result.success
    check "fleet1" in state.fleets  # Fleet1 still exists (hasn't merged yet)
    check "fleet2" in state.fleets  # Fleet2 still exists

    # Fleet1 should have moved one system toward Fleet2 (from 1 to 2)
    let updatedFleet1 = state.fleets["fleet1"]
    check updatedFleet1.location == 2

    # Fleet2 should not have moved
    let updatedFleet2 = state.fleets["fleet2"]
    check updatedFleet2.location == 3

  test "Order 13 continues following target across multiple turns":
    var state = createTestGameState()

    # Fleet1 at system 1, Fleet2 at system 4
    let fleet1 = createTestFleet("fleet1", "house_alpha", 1)
    let fleet2 = createTestFleet("fleet2", "house_alpha", 4)
    state.fleets["fleet1"] = fleet1
    state.fleets["fleet2"] = fleet2

    let order = FleetOrder(
      fleetId: "fleet1",
      orderType: FleetOrderType.JoinFleet,
      targetFleet: some("fleet2"),
      priority: 0
    )

    # Turn 1: Fleet1 moves 1 -> 2
    block turn1:
      let result = executeFleetOrder(state, "house_alpha", order)
      check result.success
      check state.fleets["fleet1"].location == 2

    # Turn 2: Fleet1 moves 2 -> 3
    block turn2:
      let result = executeFleetOrder(state, "house_alpha", order)
      check result.success
      check state.fleets["fleet1"].location == 3

    # Turn 3: Fleet1 moves 3 -> 4 and merges
    block turn3:
      let result = executeFleetOrder(state, "house_alpha", order)
      check result.success
      check "fleet1" notin state.fleets  # Merged and deleted
      check state.fleets["fleet2"].squadrons.len == 2  # Both squadrons merged

  test "Order 13 follows target that moves away":
    var state = createTestGameState()

    # Fleet1 at system 1, Fleet2 at system 3
    let fleet1 = createTestFleet("fleet1", "house_alpha", 1)
    var fleet2 = createTestFleet("fleet2", "house_alpha", 3)
    state.fleets["fleet1"] = fleet1
    state.fleets["fleet2"] = fleet2

    let order = FleetOrder(
      fleetId: "fleet1",
      orderType: FleetOrderType.JoinFleet,
      targetFleet: some("fleet2"),
      priority: 0
    )

    # Turn 1: Fleet1 moves 1 -> 2 (toward system 3), Fleet2 moves to 4
    block turn1:
      let result = executeFleetOrder(state, "house_alpha", order)
      check result.success
      check state.fleets["fleet1"].location == 2

      # Simulate Fleet2 moving away to system 4
      fleet2.location = 4
      state.fleets["fleet2"] = fleet2

    # Turn 2: Fleet1 should recalculate path and continue pursuit toward system 4
    block turn2:
      let result = executeFleetOrder(state, "house_alpha", order)
      check result.success
      check state.fleets["fleet1"].location == 3  # Moved toward system 4

      # Fleet2 is still ahead at system 4
      check state.fleets["fleet2"].location == 4

  test "Order 13 fails if target becomes unreachable":
    var state = createTestGameState()

    # Fleet1 at system 1, Fleet2 at system 100 (doesn't exist)
    let fleet1 = createTestFleet("fleet1", "house_alpha", 1)
    let fleet2 = createTestFleet("fleet2", "house_alpha", 100)
    state.fleets["fleet1"] = fleet1
    state.fleets["fleet2"] = fleet2

    let order = FleetOrder(
      fleetId: "fleet1",
      orderType: FleetOrderType.JoinFleet,
      targetFleet: some("fleet2"),
      priority: 0
    )

    let result = executeFleetOrder(state, fleet1.owner, order)

    check not result.success
    check "No path" in result.message

  test "Order 13 fails if target fleet doesn't exist":
    var state = createTestGameState()

    let fleet1 = createTestFleet("fleet1", "house_alpha", 1)
    state.fleets["fleet1"] = fleet1

    let order = FleetOrder(
      fleetId: "fleet1",
      orderType: FleetOrderType.JoinFleet,
      targetFleet: some("nonexistent"),
      priority: 0
    )

    let result = executeFleetOrder(state, fleet1.owner, order)

    check not result.success
    check "not found" in result.message

  test "Order 13 fails if target owned by different house":
    var state = createTestGameState()

    let fleet1 = createTestFleet("fleet1", "house_alpha", 1)
    let fleet2 = createTestFleet("fleet2", "house_beta", 1)
    state.fleets["fleet1"] = fleet1
    state.fleets["fleet2"] = fleet2

    let order = FleetOrder(
      fleetId: "fleet1",
      orderType: FleetOrderType.JoinFleet,
      targetFleet: some("fleet2"),
      priority: 0
    )

    let result = executeFleetOrder(state, fleet1.owner, order)

    check not result.success
    check "different house" in result.message
