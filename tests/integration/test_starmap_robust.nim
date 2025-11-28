## Comprehensive Tests for Robust Starmap Implementation
##
## This module thoroughly tests the robust starmap implementation to ensure:
## - Compliance with game specification
## - Proper edge case handling
## - Performance and reliability
## - Correct lane traversal rules

import unittest
import std/[options, tables, sequtils, sets, algorithm, math, random, times, strutils]
import ../../src/engine/starmap
import ../../src/engine/[fleet, squadron]
import ../../src/common/[hex, system]
import ../../src/common/types/[combat, units]

suite "Robust Starmap Tests":

  test "player count validation":
    # Test valid player counts
    for count in [2, 3, 4, 5, 6, 8, 10, 12]:
      let starMap = starMap(count)
      check starMap.playerCount == count

    # Test invalid player counts
    expect(StarMapError):
      discard starMap(1)  # Too few players

    expect(StarMapError):
      discard starMap(15)  # Too many players

  test "basic structure follows game spec":
    let starMap = starMap(4)

    # Hub at center
    check starMap.hubId in starMap.systems
    let hub = starMap.systems[starMap.hubId]
    check hub.coords == hex(0, 0)
    check hub.ring == 0
    check hub.player.isNone

    # Correct number of rings
    check starMap.numRings == 4

    # Systems distributed in rings
    var ringCounts = initTable[uint32, int]()
    for system in starMap.systems.values:
      ringCounts[system.ring] = ringCounts.getOrDefault(system.ring, 0) + 1

    check ringCounts[0] == 1    # Hub
    check ringCounts[1] == 6    # First ring
    check ringCounts[2] == 12   # Second ring
    check ringCounts[3] == 18   # Third ring
    check ringCounts[4] == 24   # Fourth ring

    # Total systems matches hex grid formula
    check starMap.systems.len == 61

  test "player homeworld assignment":
    for playerCount in [2, 3, 4, 5, 6, 8, 10, 12]:
      let starMap = starMap(playerCount)

      # Exactly playerCount players assigned
      var playerSystems: seq[System] = @[]
      for system in starMap.systems.values:
        if system.player.isSome:
          playerSystems.add(system)

      check playerSystems.len == playerCount

      # All players can be on any ring (except hub ring 0)
      for system in playerSystems:
        check system.ring > 0 and system.ring <= starMap.numRings

      # Player IDs are sequential
      var playerIds = playerSystems.mapIt(it.player.get).sorted()
      for i in 0..<playerCount:
        check playerIds[i] == i.uint

      # Players are reasonably distributed
      if playerCount <= 4:
        # Should use vertices for optimal placement
        for system in playerSystems:
          let neighbors = starMap.getAdjacentSystems(system.id)
          check neighbors.len >= 3  # Vertices have at least 3 neighbors

  test "hub connectivity per game spec":
    let starMap = starMap(6)

    # Hub has exactly 6 connections
    let hubConnections = starMap.getAdjacentSystems(starMap.hubId)
    check hubConnections.len == 6

    # All connections are to ring 1
    for neighborId in hubConnections:
      let neighbor = starMap.systems[neighborId]
      check neighbor.ring == 1
      check distance(neighbor.coords, hex(0, 0)) == 1

    # All hub lanes are Major type
    var hubLanes: seq[JumpLane] = @[]
    for lane in starMap.lanes:
      if lane.source == starMap.hubId or lane.destination == starMap.hubId:
        hubLanes.add(lane)

    check hubLanes.len == 6
    for lane in hubLanes:
      check lane.laneType == LaneType.Major

  test "player system connectivity per game spec":
    let starMap = starMap(4)

    # Each player system has exactly 3 connections
    for playerId in starMap.playerSystemIds:
      let connections = starMap.getAdjacentSystems(playerId)
      check connections.len == 3

      # Count major lanes from player systems
      var majorLanes = 0
      for lane in starMap.lanes:
        if (lane.source == playerId or lane.destination == playerId) and
           lane.laneType == LaneType.Major:
          majorLanes += 1

      check majorLanes >= 1  # At least one major lane

  test "lane generation and distribution":
    let starMap = starMap(4)

    # Count lane types
    var laneCount = [0, 0, 0]  # Major, Minor, Restricted
    for lane in starMap.lanes:
      laneCount[ord(lane.laneType)] += 1

    # Should have all lane types
    check laneCount[0] > 0  # Major lanes
    check laneCount[1] > 0  # Minor lanes
    check laneCount[2] > 0  # Restricted lanes

    # Major lanes should be most common (hub + player connections)
    check laneCount[0] >= 9  # 6 hub + 3 player systems minimum

  test "connectivity validation":
    let starMap = starMap(4)

    # All systems should be reachable from hub
    check starMap.validateConnectivity()

    # Verify adjacency is bidirectional
    for system in starMap.systems.values:
      let neighbors = starMap.getAdjacentSystems(system.id)
      for neighborId in neighbors:
        let backNeighbors = starMap.getAdjacentSystems(neighborId)
        check system.id in backNeighbors

  test "fleet lane traversal rules":
    # Create different fleet types using the new squadron system

    # Normal combat fleet
    let destroyer = newEnhancedShip(ShipClass.Destroyer)
    var normalSq = newSquadron(destroyer)
    let normalFleet = newFleet(squadrons = @[normalSq])

    # Crippled fleet
    var crippledDestroyer = newEnhancedShip(ShipClass.Destroyer)
    crippledDestroyer.isCrippled = true
    var crippledSq = newSquadron(crippledDestroyer)
    let crippledFleet = newFleet(squadrons = @[crippledSq])

    # Spacelift fleet (using TroopTransport which can't traverse restricted)
    let troopTransport = newEnhancedShip(ShipClass.TroopTransport)
    var spaceliftSq = newSquadron(troopTransport)
    let spaceliftFleet = newFleet(squadrons = @[spaceliftSq])

    # Normal fleet can traverse all lane types
    check canFleetTraverseLane(normalFleet, LaneType.Major)
    check canFleetTraverseLane(normalFleet, LaneType.Minor)
    check canFleetTraverseLane(normalFleet, LaneType.Restricted)

    # Crippled fleet cannot traverse restricted lanes
    check canFleetTraverseLane(crippledFleet, LaneType.Major)
    check canFleetTraverseLane(crippledFleet, LaneType.Minor)
    check not canFleetTraverseLane(crippledFleet, LaneType.Restricted)

    # Spacelift fleet cannot traverse restricted lanes
    check canFleetTraverseLane(spaceliftFleet, LaneType.Major)
    check canFleetTraverseLane(spaceliftFleet, LaneType.Minor)
    check not canFleetTraverseLane(spaceliftFleet, LaneType.Restricted)

  test "pathfinding with fleet restrictions":
    let starMap = starMap(4)

    # Find two player systems for testing
    let playerSystems = starMap.playerSystemIds
    if playerSystems.len >= 2:
      let start = playerSystems[0]
      let goal = playerSystems[1]

      # Normal fleet should find path
      let destroyer1 = newEnhancedShip(ShipClass.Destroyer)
      var normalSq1 = newSquadron(destroyer1)
      let normalFleet = newFleet(squadrons = @[normalSq1])
      let normalPath = findPath(starMap, start, goal, normalFleet)
      check normalPath.found
      check normalPath.path.len > 0
      check normalPath.path[0] == start
      check normalPath.path[^1] == goal

      # Crippled fleet path might be different (avoiding restricted lanes)
      var crippledDestroyer = newEnhancedShip(ShipClass.Destroyer)
      crippledDestroyer.isCrippled = true
      var crippledSq = newSquadron(crippledDestroyer)
      let crippledFleet = newFleet(squadrons = @[crippledSq])
      let crippledPath = findPath(starMap, start, goal, crippledFleet)
      check crippledPath.found  # Should still find a path

  test "edge case handling":
    # Test minimum player count
    let starMap2 = starMap(2)
    check starMap2.playerCount == 2
    check starMap2.validateConnectivity()
    check starMap2.verifyGameRules()

    # Test maximum player count
    let starMap12 = starMap(12)
    check starMap12.playerCount == 12
    check starMap12.validateConnectivity()
    check starMap12.verifyGameRules()

    # Test vertex limitation (>4 players can't all use vertices)
    let starMap6 = starMap(6)
    check starMap6.playerCount == 6
    check starMap6.validateConnectivity()

  test "deterministic generation":
    # Same seed should produce same map
    randomize(42)
    let starMap1 = starMap(4)

    randomize(42)
    let starMap2 = starMap(4)

    # Basic structure should be identical
    check starMap1.systems.len == starMap2.systems.len
    check starMap1.lanes.len == starMap2.lanes.len
    check starMap1.playerCount == starMap2.playerCount
    check starMap1.numRings == starMap2.numRings

  test "no duplicate lanes":
    let starMap = starMap(4)

    # Check for duplicate lanes
    var laneSet = initHashSet[tuple[a: uint, b: uint]]()
    for lane in starMap.lanes:
      let pair = if lane.source < lane.destination:
        (lane.source, lane.destination)
      else:
        (lane.destination, lane.source)

      check pair notin laneSet  # No duplicates
      laneSet.incl(pair)

  test "game rule compliance":
    for playerCount in [2, 3, 4, 5, 6, 8, 10, 12]:
      let starMap = starMap(playerCount)

      # Verify all game rules are followed
      check starMap.verifyGameRules()

      # Additional specific checks
      check starMap.getAdjacentSystems(starMap.hubId).len == 6

      for playerId in starMap.playerSystemIds:
        check starMap.getAdjacentSystems(playerId).len == 3

  test "performance characteristics":
    # Test generation speed for various sizes
    let sizes = [4, 6, 8, 10, 12]

    for size in sizes:
      let start = now()
      let starMap = starMap(size)
      let duration = now() - start

      # Should generate quickly
      check duration.inMilliseconds < 1000  # Less than 1 second

      # Should produce valid results
      check starMap.verifyGameRules()

  test "pathfinding performance":
    let starMap = starMap(8)
    let destroyer = newEnhancedShip(ShipClass.Destroyer)
    var sq = newSquadron(destroyer)
    let fleet = newFleet(squadrons = @[sq])

    # Test pathfinding between various system pairs
    let systems = starMap.systems.keys.toSeq()
    let testPairs = min(50, systems.len * systems.len div 10)  # Sample of paths

    let start = now()
    var pathsFound = 0

    for i in 0..<testPairs:
      let startSys = systems[i mod systems.len]
      let goalSys = systems[(i + systems.len div 2) mod systems.len]

      if startSys != goalSys:
        let result = findPath(starMap, startSys, goalSys, fleet)
        if result.found:
          pathsFound += 1

    let duration = now() - start
    check duration.inMilliseconds < 5000  # Less than 5 seconds for many paths
    check pathsFound > 0  # Found at least some paths

  test "error handling":
    # Test invalid pathfinding requests
    let starMap = starMap(4)
    let destroyer = newEnhancedShip(ShipClass.Destroyer)
    var sq = newSquadron(destroyer)
    let fleet = newFleet(squadrons = @[sq])

    # Non-existent systems
    let invalidPath = findPath(starMap, 99999, 99998, fleet)
    check not invalidPath.found

    # Same start and goal
    let hubId = starMap.hubId
    let samePath = findPath(starMap, hubId, hubId, fleet)
    check samePath.found
    check samePath.path == @[hubId]
    check samePath.totalCost == 0

  test "starmap statistics":
    let starMap = starMap(4)
    let stats = starMap.getStarMapStats()

    # Should contain key information
    check stats.contains("Players: 4")
    check stats.contains("Rings: 4")
    check stats.contains("Total Systems:")
    check stats.contains("Total Lanes:")
    check stats.contains("Fully Connected: true")

when isMainModule:
  echo "Running Robust Starmap Tests..."
  echo "==============================="
