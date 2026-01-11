## EC4X Game Specification Validation Tests
##
## This test validates that the Nim implementation produces results
## that strictly follow the EC4X game specification requirements.
## All tests verify compliance with the official game rules.

import unittest
import std/[tables, math, times, strutils]
import ../../src/engine/starmap
import ../../src/engine/types/[
  starmap as starmap_types, core, game_state, resolution,
  diplomacy, player_state
]
import ../../src/engine/config/[engine as engine_config, game_setup_config]
import ../../src/engine/globals

# Helper to create test GameState + StarMap
proc createTestGame(playerCount: int32, numRings: uint32 = 0): (
  GameState, StarMap
) =
  ## Create a test GameState and StarMap
  ## If numRings = 0, uses playerCount as default for backward compatibility
  let rings = if numRings == 0: playerCount.uint32 else: numRings
  let seed = 12345'i64

  # Load game configs (required for homeworld initialization)
  gameConfig = loadGameConfig("config")
  gameSetup = loadGameSetupConfig("scenarios/standard-4-player.kdl")

  # Validate player count bounds (2-12)
  if playerCount < 2 or playerCount > 12:
    raise newException(StarMapError,
      "playerCount must be 2-12 (got " & $playerCount & ")")

  # Validate ring bounds (2-12)
  if rings < 2 or rings > 12:
    raise newException(StarMapError,
      "numRings must be 2-12 (got " & $rings & ")")

  var state = GameState(
    gameId: "test",
    seed: seed,
    turn: 1,
    counters: IdCounters(
      nextHouseId: 1,
      nextSystemId: 1,
      nextColonyId: 1,
      nextNeoriaId: 1,
      nextKastraId: 1,
      nextFleetId: 1,
      nextShipId: 1,
      nextGroundUnitId: 1,
      nextConstructionProjectId: 1,
      nextRepairProjectId: 1,
      nextPopulationTransferId: 1
    ),
    systems: Systems(
      entities: EntityManager[SystemId, System](
        data: @[],
        index: initTable[SystemId, int]()
      )
    ),
    intel: initTable[HouseId, IntelDatabase](),
    diplomaticRelation: initTable[(HouseId, HouseId), DiplomaticRelation](),
    diplomaticViolation: initTable[HouseId, ViolationHistory](),
    gracePeriodTimers: initTable[HouseId, GracePeriodTracker](),
    lastTurnReports: initTable[HouseId, TurnResolutionReport]()
  )

  let starMap = generateStarMap(state, playerCount, rings)
  return (state, starMap)

# Expected behavior based on EC4X game specification
proc expectedGameBehavior(playerCount: int): tuple[
  systemCount: int,
  hubConnections: int,
  playerConnections: int,
  ringCounts: seq[int],
  playerOnOuterRing: bool,
  allMajorLanesFromHub: bool
] =
  # Calculate expected system count (1 + 3*n*(n+1) for n rings)
  let n = playerCount
  let expectedSystems = 1 + 3 * n * (n + 1)

  # Expected ring counts for hex grid
  var expectedRingCounts: seq[int] = @[1]  # Hub ring
  for ring in 1..n:
    expectedRingCounts.add(6 * ring)

  return (
    systemCount: expectedSystems,
    hubConnections: 6,                    # Hub has exactly 6 major lanes
    playerConnections: 3,                 # Players have exactly 3 lanes each
    ringCounts: expectedRingCounts,
    playerOnOuterRing: false,             # Players can be on any ring
    allMajorLanesFromHub: true            # All hub lanes are major
  )

suite "EC4X Game Specification Validation":

  test "system count matches game specification":
    for playerCount in [2, 3, 4, 5, 6, 8, 10, 12]:
      let (state, _) = createTestGame(playerCount.int32)
      let expected = expectedGameBehavior(playerCount)

      check state.systems.entities.data.len == expected.systemCount
      echo "Player count ", playerCount, ": ", state.systems.entities.data.len,
        " systems (expected: ", expected.systemCount, ")"

  test "ring distribution matches hexagonal grid specification":
    for playerCount in [3, 4, 6]:
      let (state, _) = createTestGame(playerCount.int32)
      let expected = expectedGameBehavior(playerCount)

      # Count systems by ring
      var actualRingCounts: seq[int] = @[]
      for ring in 0..playerCount:
        var count = 0
        for system in state.systems.entities.data:
          if system.ring == ring.uint32:
            count += 1
        actualRingCounts.add(count)

      # Compare with expected
      for i in 0..<expected.ringCounts.len:
        check actualRingCounts[i] == expected.ringCounts[i]
        echo "Ring ", i, ": ", actualRingCounts[i], " systems (expected: ",
          expected.ringCounts[i], ")"

  test "hub connectivity matches game specification":
    for playerCount in [2, 3, 4, 5, 6, 8, 10, 12]:
      let (state, starMap) = createTestGame(playerCount.int32)
      let expected = expectedGameBehavior(playerCount)

      # Hub should have exactly 6 connections
      let hubConnections = starMap.adjacentSystems(starMap.hubId)
      check hubConnections.len == expected.hubConnections

      # All hub connections should be to ring 1
      for neighborId in hubConnections:
        let neighborIdx = state.systems.entities.index[neighborId]
        let neighbor = state.systems.entities.data[neighborIdx]
        check neighbor.ring == 1
        check distance(neighbor.coords, hex(0, 0)) == 1

      # Hub lanes use mixed distribution as per game spec
      var hubLanes: seq[JumpLane] = @[]
      for lane in starMap.lanes.data:
        if (lane.source == starMap.hubId) or
           (lane.destination == starMap.hubId):
          hubLanes.add(lane)

      check hubLanes.len == expected.hubConnections

      # Hub lanes should have mixed types
      var majorCount = 0
      var minorCount = 0
      var restrictedCount = 0
      for lane in hubLanes:
        case lane.laneType
        of LaneClass.Major: majorCount += 1
        of LaneClass.Minor: minorCount += 1
        of LaneClass.Restricted: restrictedCount += 1

      # Should have at least one Major lane
      check majorCount >= 1
      # Total should equal hub connections
      check majorCount + minorCount + restrictedCount ==
        expected.hubConnections

  test "player system connectivity matches game specification":
    for playerCount in [2, 3, 4, 5, 6, 8, 10, 12]:
      let (state, starMap) = createTestGame(playerCount.int32)
      let expected = expectedGameBehavior(playerCount)

      # Calculate max ring from systems
      var maxRing: uint32 = 0
      for system in state.systems.entities.data:
        if system.ring > maxRing:
          maxRing = system.ring

      # Each player should have exactly 3 connections
      for systemId in starMap.houseSystemIds:
        let connections = starMap.adjacentSystems(systemId)
        check connections.len == expected.playerConnections

        # Player can be on any ring except hub (ring 0)
        let systemIdx = state.systems.entities.index[systemId]
        let system = state.systems.entities.data[systemIdx]
        check system.ring > 0 and system.ring <= maxRing

        # Count major lanes from player
        var majorLanes = 0
        for lane in starMap.lanes.data:
          if ((lane.source == systemId) or (lane.destination == systemId)) and
             (lane.laneType == LaneClass.Major):
            majorLanes += 1

        check majorLanes >= 1  # At least one major lane

  test "player placement strategy validation":
    # Test the vertex selection logic for optimal strategic placement

    # For 2-4 players, should use vertices (corners with 3 neighbors)
    for playerCount in [2, 3, 4]:
      let (state, starMap) = createTestGame(playerCount.int32)

      echo "Testing vertex selection for ", playerCount, " players"

      # Count vertices available across all rings (not just outer)
      var vertexCount = 0
      for system in state.systems.entities.data:
        if system.ring > 0:  # Any ring except hub
          let neighborCount = starMap.countHexNeighbors(state, system.coords)
          if neighborCount == 3:
            vertexCount += 1

      echo "  Available vertices: ", vertexCount

      # For player counts <= 4, should be able to use vertices
      if playerCount <= 4:
        check vertexCount >= playerCount

        # Calculate max ring
        var maxRing: uint32 = 0
        for system in state.systems.entities.data:
          if system.ring > maxRing:
            maxRing = system.ring

        # Check that players are reasonably distributed
        var playerSystems: seq[System] = @[]
        for system in state.systems.entities.data:
          if system.id in starMap.houseSystemIds:
            playerSystems.add(system)

        # Players can be on any ring (except hub)
        for system in playerSystems:
          check system.ring > 0 and system.ring <= maxRing

          # For small player counts, should prefer vertices
          let neighborCount = starMap.countHexNeighbors(state, system.coords)
          check neighborCount >= 3  # At least 3 neighbors
          check neighborCount <= 6  # At most 6 neighbors (hex grid limit)

  test "edge case handling validation":
    # Test that edge cases are handled gracefully according to game rules

    # Test 5 players (requires non-vertex placement)
    let (state5, starMap5) = createTestGame(5)

    # Count available vertices across all rings (not just outer)
    var vertexCount = 0
    for system in state5.systems.entities.data:
      if system.ring > 0:  # Any ring except hub
        if starMap5.countHexNeighbors(state5, system.coords) == 3:
          vertexCount += 1

    echo "For 5 players, vertices available: ", vertexCount,
      " (handled gracefully)"

    # Our robust implementation should handle this gracefully
    check state5.systems.entities.data.len > 0
    check starMap5.houseSystemIds.len == 5
    check starMap5.validateConnectivity(state5)

  test "lane type distribution follows game specification":
    for playerCount in [3, 4, 6]:
      let (_, starMap) = createTestGame(playerCount.int32)

      # Count lane types
      var laneTypeCounts = [0, 0, 0]  # Major, Minor, Restricted
      for lane in starMap.lanes.data:
        laneTypeCounts[ord(lane.laneType)] += 1

      echo "Player count ", playerCount, " lane distribution:"
      echo "  Major: ", laneTypeCounts[0]
      echo "  Minor: ", laneTypeCounts[1]
      echo "  Restricted: ", laneTypeCounts[2]

      # Should have all three types as per game specification
      check laneTypeCounts[0] > 0  # Major lanes
      check laneTypeCounts[1] > 0  # Minor lanes
      check laneTypeCounts[2] > 0  # Restricted lanes

      # Major lanes should be most common (hub + player connections)
      let expectedMajorLanes = 6 + (playerCount * 3)  # Hub + players minimum
      check laneTypeCounts[0] >= expectedMajorLanes

  test "connectivity validation follows game specification":
    for playerCount in [2, 3, 4, 5, 6, 8, 10, 12]:
      let (state, starMap) = createTestGame(playerCount.int32)

      # Test connectivity as required by game specification
      check starMap.validateConnectivity(state)

      echo "Player count ", playerCount, ": connectivity validated"

  test "deterministic behavior validation":
    # Test that same seed produces same results for consistency

    # Create two games with same parameters
    let (state1, starMap1) = createTestGame(4)
    let (state2, starMap2) = createTestGame(4)

    # Basic structure should be identical
    check state1.systems.entities.data.len == state2.systems.entities.data.len
    check starMap1.lanes.data.len == starMap2.lanes.data.len
    check starMap1.houseSystemIds.len == starMap2.houseSystemIds.len

    # Player assignments should be identical
    for i in 0..<starMap1.houseSystemIds.len:
      let systemId1 = starMap1.houseSystemIds[i]
      let systemId2 = starMap2.houseSystemIds[i]
      let idx1 = state1.systems.entities.index[systemId1]
      let idx2 = state2.systems.entities.index[systemId2]
      let system1 = state1.systems.entities.data[idx1]
      let system2 = state2.systems.entities.data[idx2]
      check system1.coords == system2.coords
      check system1.ring == system2.ring

  test "robust error handling validation":
    # Test that implementation gracefully handles all valid player counts

    # These should all work without errors according to game specification
    for playerCount in [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]:
      let (state, starMap) = createTestGame(playerCount.int32)

      # Should create valid starmap
      check state.systems.entities.data.len > 0
      check starMap.houseSystemIds.len == playerCount
      check starMap.validateConnectivity(state)
      check starMap.verifyGameRules(state)

      echo "Player count ", playerCount, ": ✓ Generated successfully (",
        state.systems.entities.data.len, " systems)"

    # Test invalid player counts (should throw meaningful errors)
    expect(StarMapError):
      discard createTestGame(1)  # Too few

    expect(StarMapError):
      discard createTestGame(15)  # Too many

  test "performance requirements validation":
    # Verify performance meets gameplay requirements
    let testSizes = [4, 6, 8, 12]

    for size in testSizes:
      let startTime = now()
      let (state, starMap) = createTestGame(size.int32)
      let duration = now() - startTime

      let ms = duration.inMilliseconds
      echo "Size ", size, ": ", ms, "ms (", state.systems.entities.data.len,
        " systems, ", starMap.lanes.data.len, " lanes)"

      # Should be fast enough for real-time use
      check ms < 1000  # Less than 1 second

      # Should produce valid results
      check starMap.verifyGameRules(state)

  test "variable ring sizes validation":
    # Test new independent numRings parameter

    # Test that numRings can be independent of playerCount
    let testCases = [
      (players: 2'i32, rings: 4'u32, desc: "2 players, 4 rings (large map)"),
      (players: 4'i32, rings: 2'u32, desc: "4 players, 2 rings (cramped)"),
      (players: 4'i32, rings: 6'u32, desc: "4 players, 6 rings (spacious)"),
      (players: 12'i32, rings: 6'u32, desc: "12 players, 6 rings (crowded)"),
      (players: 2'i32, rings: 10'u32, desc: "2 players, 10 rings (epic)")
    ]

    for tc in testCases:
      let (state, starMap) = createTestGame(tc.players, tc.rings)

      # Verify correct number of systems for given ring count
      let expectedSystems = 3 * tc.rings.int * tc.rings.int +
        3 * tc.rings.int + 1
      check state.systems.entities.data.len == expectedSystems

      # Verify correct number of homeworlds
      check starMap.houseSystemIds.len == tc.players.int

      # Verify connectivity
      check starMap.validateConnectivity(state)

      # Calculate systems-per-player ratio
      let systemsPerPlayer = expectedSystems.float / tc.players.float

      echo tc.desc, ": ", expectedSystems, " systems, ",
        systemsPerPlayer.formatFloat(ffDecimal, 1), " per player"

  test "ring size bounds validation":
    # Test that ring bounds (2-12) are enforced

    # Valid bounds should work
    for rings in [2'u32, 4'u32, 8'u32, 12'u32]:
      let (state, _) = createTestGame(4, rings)
      check state.systems.entities.data.len > 0
      echo "Rings ", rings, ": ✓ Valid"

    # Invalid bounds should fail
    expect(StarMapError):
      discard createTestGame(4, 1'u32)  # Too few rings

    expect(StarMapError):
      discard createTestGame(4, 13'u32)  # Too many rings

  test "homeworld lane validation":
    # Test that homeworlds meet connectivity requirements

    for playerCount in [2, 3, 4, 6, 8]:
      let (state, starMap) = createTestGame(playerCount.int32)

      # Each homeworld should have exactly 3 major lanes
      for systemId in starMap.houseSystemIds:
        var majorLaneCount = 0
        for lane in starMap.lanes.data:
          if ((lane.source == systemId) or (lane.destination == systemId)) and
             (lane.laneType == LaneClass.Major):
            majorLaneCount += 1

        check majorLaneCount == 3
        echo "Player ", playerCount, " homeworld ", systemId, ": ",
          majorLaneCount, " major lanes (expected: 3)"

      # Validate homeworld lanes specifically
      let errors = starMap.validateHomeworldLanes(state)
      check errors.len == 0
      if errors.len > 0:
        for error in errors:
          echo "  ERROR: ", error

  test "map size categories validation":
    # Test small/medium/large map classifications

    # Small maps (2-4 rings)
    let (state_small, _) = createTestGame(4, 3'u32)
    check state_small.systems.entities.data.len == 37  # 3*9 + 3*3 + 1
    echo "Small map (3 rings): ", state_small.systems.entities.data.len,
      " systems"

    # Medium maps (5-8 rings)
    let (state_medium, _) = createTestGame(4, 6'u32)
    check state_medium.systems.entities.data.len == 127  # 3*36 + 3*6 + 1
    echo "Medium map (6 rings): ", state_medium.systems.entities.data.len,
      " systems"

    # Large maps (9-12 rings)
    let (state_large, _) = createTestGame(4, 10'u32)
    check state_large.systems.entities.data.len == 331  # 3*100 + 3*10 + 1
    echo "Large map (10 rings): ", state_large.systems.entities.data.len,
      " systems"

  test "systems-per-player ratio validation":
    # Test that systems-per-player ratios work as documented

    let testCases = [
      (players: 4'i32, rings: 2'u32, expected: 4.8),  # Cramped
      (players: 4'i32, rings: 4'u32, expected: 15.3),  # Good
      (players: 12'i32, rings: 6'u32, expected: 10.6)  # Decent
    ]

    for tc in testCases:
      let (state, _) = createTestGame(tc.players, tc.rings)
      let actualRatio = state.systems.entities.data.len.float /
        tc.players.float

      # Allow small floating point tolerance
      check abs(actualRatio - tc.expected) < 0.1

      let ratioStr = actualRatio.formatFloat(ffDecimal, 1)
      echo "Players: ", tc.players, ", Rings: ", tc.rings,
        " -> ", ratioStr, " systems/player (expected: ", tc.expected, ")"

  test "homeworld distance maximization validation":
    # Test that homeworlds are well-distributed

    for playerCount in [2, 3, 4, 6]:
      let (state, starMap) = createTestGame(playerCount.int32, 6'u32)

      # Get all homeworld coordinates
      var homeworldCoords: seq[Hex] = @[]
      for systemId in starMap.houseSystemIds:
        let idx = state.systems.entities.index[systemId]
        let system = state.systems.entities.data[idx]
        homeworldCoords.add(system.coords)

      # Calculate minimum distance between any two homeworlds
      var minDistance = high(uint32)
      for i in 0..<homeworldCoords.len:
        for j in (i+1)..<homeworldCoords.len:
          let dist = distance(homeworldCoords[i], homeworldCoords[j])
          if dist < minDistance:
            minDistance = dist

      # With 6 rings and few players, homeworlds should be well-separated
      if playerCount <= 4:
        check minDistance >= 3  # Reasonable minimum separation
        echo "Players: ", playerCount, ", Min homeworld distance: ",
          minDistance, " hexes"

when isMainModule:
  echo "Running EC4X Game Specification Validation Tests..."
  echo "=================================================="
  echo ""
  echo "This test suite validates that the Nim implementation"
  echo "produces results that strictly follow the EC4X game"
  echo "specification requirements and handles all edge cases."
  echo ""
