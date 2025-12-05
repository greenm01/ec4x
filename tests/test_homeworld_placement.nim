## Homeworld Placement Tests
## Validates that starmap generation places player homeworlds correctly

import unittest
import ../src/engine/starmap
import std/[options, tables, math, strformat]

suite "Homeworld Placement Validation":

  test "4-player map has exactly 4 homeworlds":
    let map = starMap(4)
    check map.playerSystemIds.len == 4
    check map.playerCount == 4

  test "All homeworlds are on outer ring":
    let map = starMap(4)
    for systemId in map.playerSystemIds:
      let system = map.systems[systemId]
      check system.ring == map.numRings

  test "All homeworlds have player field set":
    let map = starMap(4)
    for i, systemId in map.playerSystemIds:
      let system = map.systems[systemId]
      check system.player.isSome
      check system.player.get() == uint(i)

  test "All homeworlds have neighbors (connectivity)":
    let map = starMap(4)
    for systemId in map.playerSystemIds:
      let neighbors = map.getAdjacentSystems(systemId)
      check neighbors.len > 0

  test "Homeworlds are in different quadrant sectors":
    let map = starMap(4)

    # Calculate angles for each homeworld
    var sectors: array[4, int] = [0, 0, 0, 0]
    for systemId in map.playerSystemIds:
      let system = map.systems[systemId]
      let angle = arctan2(system.coords.r.float, system.coords.q.float) * 180.0 / PI
      let normalizedAngle = if angle < 0: angle + 360.0 else: angle
      let sector = int(normalizedAngle / 90.0) mod 4
      sectors[sector] += 1

    # Each sector should have exactly 1 homeworld (evenly distributed)
    for count in sectors:
      check count <= 1  # No sector should have more than 1 homeworld

  test "Outer ring has sufficient systems":
    let map = starMap(4)

    var outerRingCount = 0
    for system in map.systems.values:
      if system.ring == map.numRings:
        outerRingCount += 1

    # Outer ring should have at least as many systems as players
    check outerRingCount >= 4

  test "Map has hub system":
    let map = starMap(4)
    check map.hubId in map.systems
    check map.systems[map.hubId].ring == 0  # Hub is at ring 0

  test "All homeworlds are unique systems":
    let map = starMap(4)

    # Check no duplicates in playerSystemIds
    var systemSet: seq[uint] = @[]
    for systemId in map.playerSystemIds:
      check systemId notin systemSet
      systemSet.add(systemId)

    check systemSet.len == 4
