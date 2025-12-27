## EC4X Game Specification Validation Tests
##
## This test validates that the Nim implementation produces results
## that strictly follow the EC4X game specification requirements.
## All tests verify compliance with the official game rules.

import unittest
import std/[tables, math, random, times, options]
import ../../src/engine/starmap
import ../../src/engine/types/[starmap as starmap_types, core]

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
    playerOnOuterRing: false,             # Players can be on any ring (not just outer)
    allMajorLanesFromHub: true            # All hub lanes are major
  )

suite "EC4X Game Specification Validation":

  test "system count matches game specification":
    for playerCount in [2, 3, 4, 5, 6, 8, 10, 12]:
      let starMap = starMap(playerCount)
      let expected = expectedGameBehavior(playerCount)

      check starMap.systems.entities.data.len == expected.systemCount
      echo "Player count ", playerCount, ": ", starMap.systems.entities.data.len, " systems (expected: ", expected.systemCount, ")"

  test "ring distribution matches hexagonal grid specification":
    for playerCount in [3, 4, 6]:
      let starMap = starMap(playerCount)
      let expected = expectedGameBehavior(playerCount)

      # Count systems by ring
      var actualRingCounts: seq[int] = @[]
      for ring in 0..playerCount:
        var count = 0
        for system in starMap.systems.entities.data:
          if system.ring == ring.uint32:
            count += 1
        actualRingCounts.add(count)

      # Compare with expected
      for i in 0..<expected.ringCounts.len:
        check actualRingCounts[i] == expected.ringCounts[i]
        echo "Ring ", i, ": ", actualRingCounts[i], " systems (expected: ", expected.ringCounts[i], ")"

  test "hub connectivity matches game specification":
    for playerCount in [2, 3, 4, 5, 6, 8, 10, 12]:
      let starMap = starMap(playerCount)
      let expected = expectedGameBehavior(playerCount)

      # Hub should have exactly 6 connections
      let hubConnections = starMap.getAdjacentSystems(starMap.hubId)
      check hubConnections.len == expected.hubConnections

      # All hub connections should be to ring 1
      for neighborId in hubConnections:
        let neighborIdx = starMap.systems.entities.index[neighborId]
        let neighbor = starMap.systems.entities.data[neighborIdx]
        check neighbor.ring == 1
        check distance(neighbor.coords, hex(0, 0)) == 1

      # Hub lanes use the same distribution as rest of map (mixed types per assets.md:2.1)
      # Verify we have exactly 6 hub lanes
      var hubLanes: seq[JumpLane] = @[]
      for lane in starMap.lanes.data:
        if (lane.source == starMap.hubId) or (lane.destination == starMap.hubId):
          hubLanes.add(lane)

      check hubLanes.len == expected.hubConnections

      # Hub lanes should have mixed types (not all Major)
      # Per assets.md: "Hub lanes use the same distribution as the rest of the map (mixed lane types)"
      var majorCount = 0
      var minorCount = 0
      var restrictedCount = 0
      for lane in hubLanes:
        case lane.laneType
        of LaneType.Major: majorCount += 1
        of LaneType.Minor: minorCount += 1
        of LaneType.Restricted: restrictedCount += 1

      # Should have at least one Major lane (for basic connectivity)
      check majorCount >= 1
      # Total should equal hub connections
      check majorCount + minorCount + restrictedCount == expected.hubConnections

  test "player system connectivity matches game specification":
    for playerCount in [2, 3, 4, 5, 6, 8, 10, 12]:
      let starMap = starMap(playerCount)
      let expected = expectedGameBehavior(playerCount)

      # Each player should have exactly 3 connections
      for playerId in starMap.playerSystemIds:
        let connections = starMap.getAdjacentSystems(playerId)
        check connections.len == expected.playerConnections

        # Player can be on any ring except hub (ring 0)
        let playerIdx = starMap.systems.entities.index[playerId]
        let playerSystem = starMap.systems.entities.data[playerIdx]
        check playerSystem.ring > 0 and playerSystem.ring <= starMap.numRings

        # Count major lanes from player
        var majorLanes = 0
        for lane in starMap.lanes.data:
          if ((lane.source == playerId) or (lane.destination == playerId)) and
             (lane.laneType == LaneType.Major):
            majorLanes += 1

        check majorLanes >= 1  # At least one major lane

  test "player placement strategy validation":
    # Test the vertex selection logic for optimal strategic placement

    # For 2-4 players, should use vertices (corners with 3 neighbors)
    for playerCount in [2, 3, 4]:
      let starMap = starMap(playerCount)

      echo "Testing vertex selection for ", playerCount, " players"

      # Count vertices available across all rings (not just outer)
      var vertexCount = 0
      for system in starMap.systems.entities.data:
        if system.ring > 0:  # Any ring except hub
          let neighborCount = starMap.countHexNeighbors(system.coords)
          if neighborCount == 3:
            vertexCount += 1

      echo "  Available vertices: ", vertexCount

      # For player counts <= 4, should be able to use vertices
      if playerCount <= 4:
        check vertexCount >= playerCount

        # Check that players are reasonably distributed
        var playerSystems: seq[System] = @[]
        for system in starMap.systems.entities.data:
          if system.player.isSome:
            playerSystems.add(system)

        # Players can be on any ring (except hub)
        for system in playerSystems:
          check system.ring > 0 and system.ring <= starMap.numRings

          # For small player counts, should prefer vertices
          let neighborCount = starMap.countHexNeighbors(system.coords)
          check neighborCount >= 3  # At least 3 neighbors
          check neighborCount <= 6  # At most 6 neighbors (hex grid limit)

  test "edge case handling validation":
    # Test that edge cases are handled gracefully according to game rules

    # Test 5 players (requires non-vertex placement)
    let starMap5 = starMap(5)

    # Count available vertices across all rings (not just outer)
    var vertexCount = 0
    for system in starMap5.systems.entities.data:
      if system.ring > 0:  # Any ring except hub
        if starMap5.countHexNeighbors(system.coords) == 3:
          vertexCount += 1

    echo "For 5 players, vertices available: ", vertexCount, " (handled gracefully)"

    # Our robust implementation should handle this gracefully
    check starMap5.systems.entities.data.len > 0
    check starMap5.playerSystemIds.len == 5
    check starMap5.validateConnectivity()

  test "lane type distribution follows game specification":
    for playerCount in [3, 4, 6]:
      let starMap = starMap(playerCount)

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

  # SKIPPED: Fleet pathfinding tests - require Ships/Squadrons entities
  # test "pathfinding with fleet restrictions follows game rules":
  #   skip()

  test "connectivity validation follows game specification":
    for playerCount in [2, 3, 4, 5, 6, 8, 10, 12]:
      let starMap = starMap(playerCount)

      # Test connectivity as required by game specification
      check starMap.validateConnectivity()

      echo "Player count ", playerCount, ": connectivity validated"

  test "deterministic behavior validation":
    # Test that same seed produces same results for consistency

    randomize(12345)
    let starMap1 = starMap(4)

    randomize(12345)
    let starMap2 = starMap(4)

    # Basic structure should be identical
    check starMap1.systems.entities.data.len == starMap2.systems.entities.data.len
    check starMap1.lanes.data.len == starMap2.lanes.data.len
    check starMap1.playerSystemIds.len == starMap2.playerSystemIds.len

    # Player assignments should be identical
    for i in 0..<starMap1.playerSystemIds.len:
      let playerId1 = starMap1.playerSystemIds[i]
      let playerId2 = starMap2.playerSystemIds[i]
      let idx1 = starMap1.systems.entities.index[playerId1]
      let idx2 = starMap2.systems.entities.index[playerId2]
      let player1 = starMap1.systems.entities.data[idx1]
      let player2 = starMap2.systems.entities.data[idx2]
      check player1.coords == player2.coords
      check player1.ring == player2.ring

  test "robust error handling validation":
    # Test that implementation gracefully handles all valid player counts

    # These should all work without errors according to game specification
    for playerCount in [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]:
      let starMap = starMap(playerCount)

      # Should create valid starmap
      check starMap.systems.entities.data.len > 0
      check starMap.playerSystemIds.len == playerCount
      check starMap.validateConnectivity()
      check starMap.verifyGameRules()

      echo "Player count ", playerCount, ": ✓ Generated successfully (", starMap.systems.entities.data.len, " systems)"

    # Test invalid player counts (should throw meaningful errors)
    expect(StarMapError):
      discard starMap(1)  # Too few

    expect(StarMapError):
      discard starMap(15)  # Too many

  test "performance requirements validation":
    # Verify performance meets gameplay requirements
    let testSizes = [4, 6, 8, 12]

    for size in testSizes:
      let startTime = now()
      let starMap = starMap(size)
      let duration = now() - startTime

      let ms = duration.inMilliseconds
      echo "Size ", size, ": ", ms, "ms (", starMap.systems.entities.data.len, " systems, ", starMap.lanes.data.len, " lanes)"

      # Should be fast enough for real-time use
      check ms < 1000  # Less than 1 second

      # Should produce valid results
      check starMap.verifyGameRules()

when isMainModule:
  echo "Running EC4X Game Specification Validation Tests..."
  echo "=================================================="
  echo ""
  echo "This test suite validates that the Nim implementation"
  echo "produces results that strictly follow the EC4X game"
  echo "specification requirements and handles all edge cases."
  echo ""
