## Unit Tests: Hex Grid Utilities
##
## Tests hex coordinate math from starmap.nim
## Pure functions - no GameState needed
##
## Per assets.md hex coordinate system

import std/[unittest, math]
import ../../src/engine/types/starmap
import ../../src/engine/starmap

suite "Hex: Coordinate Creation":

  test "hex creates coordinate":
    let h = hex(3, -2)
    check h.q == 3
    check h.r == -2

  test "hex origin is (0,0)":
    let origin = hex(0, 0)
    check origin.q == 0
    check origin.r == 0

  test "hex with negative coordinates":
    let h = hex(-5, -3)
    check h.q == -5
    check h.r == -3

suite "Hex: Distance Calculation":
  ## Hex distance uses cube coordinate formula
  ## distance = max(|dq|, |dr|, |ds|) where ds = -(dq + dr)

  test "distance to self is 0":
    let h = hex(5, 3)
    check distance(h, h) == 0

  test "distance to origin":
    check distance(hex(0, 0), hex(1, 0)) == 1
    check distance(hex(0, 0), hex(0, 1)) == 1
    check distance(hex(0, 0), hex(-1, 1)) == 1

  test "distance is symmetric":
    let a = hex(2, 3)
    let b = hex(-1, 4)
    check distance(a, b) == distance(b, a)

  test "distance along q axis":
    check distance(hex(0, 0), hex(5, 0)) == 5
    check distance(hex(0, 0), hex(-3, 0)) == 3

  test "distance along r axis":
    check distance(hex(0, 0), hex(0, 4)) == 4
    check distance(hex(0, 0), hex(0, -2)) == 2

  test "diagonal distance":
    # Moving diagonally in hex grid
    check distance(hex(0, 0), hex(2, -2)) == 2
    check distance(hex(0, 0), hex(-3, 3)) == 3

  test "arbitrary distance":
    # (3, -1) to (-2, 4)
    # dq = -5, dr = 5, ds = 0
    # max(5, 5, 0) = 5
    check distance(hex(3, -1), hex(-2, 4)) == 5

suite "Hex: Neighbor Calculation":
  ## Hex grid has 6 neighbors (directions 0-5)

  test "origin has 6 neighbors":
    let origin = hex(0, 0)
    var neighbors: seq[Hex] = @[]
    for dir in 0 .. 5:
      neighbors.add(origin.neighbor(dir))
    check neighbors.len == 6

  test "all neighbors are distance 1":
    let center = hex(3, -2)
    for dir in 0 .. 5:
      let n = center.neighbor(dir)
      check distance(center, n) == 1

  test "neighbors are unique":
    let center = hex(0, 0)
    var seen: seq[Hex] = @[]
    for dir in 0 .. 5:
      let n = center.neighbor(dir)
      check n notin seen
      seen.add(n)

  test "direction wraps at 6":
    let center = hex(0, 0)
    check center.neighbor(0) == center.neighbor(6)
    check center.neighbor(1) == center.neighbor(7)
    check center.neighbor(5) == center.neighbor(11)

  test "specific neighbor directions":
    let center = hex(0, 0)
    # Direction 0: (+1, 0)
    check center.neighbor(0) == hex(1, 0)
    # Direction 1: (+1, -1)
    check center.neighbor(1) == hex(1, -1)
    # Direction 2: (0, -1)
    check center.neighbor(2) == hex(0, -1)
    # Direction 3: (-1, 0)
    check center.neighbor(3) == hex(-1, 0)
    # Direction 4: (-1, +1)
    check center.neighbor(4) == hex(-1, 1)
    # Direction 5: (0, +1)
    check center.neighbor(5) == hex(0, 1)

suite "Hex: Radius Calculation":
  ## withinRadius returns all hexes within N steps

  test "radius 0 returns only center":
    let center = hex(0, 0)
    let hexes = withinRadius(center, 0)
    check hexes.len == 1
    check hexes[0] == center

  test "radius 1 returns 7 hexes":
    # Center + 6 neighbors
    let hexes = withinRadius(hex(0, 0), 1)
    check hexes.len == 7

  test "radius 2 returns 19 hexes":
    # Formula: 1 + 3*n*(n+1) for n rings
    # n=2: 1 + 3*2*3 = 19
    let hexes = withinRadius(hex(0, 0), 2)
    check hexes.len == 19

  test "radius 3 returns 37 hexes":
    # n=3: 1 + 3*3*4 = 37
    let hexes = withinRadius(hex(0, 0), 3)
    check hexes.len == 37

  test "all hexes within radius are at correct distance":
    let center = hex(2, -1)
    let radius = 3'i32
    let hexes = withinRadius(center, radius)

    for h in hexes:
      check distance(center, h) <= radius.uint32

  test "radius works with non-origin center":
    let center = hex(5, -3)
    let hexes = withinRadius(center, 1)
    check hexes.len == 7

    # Verify center is included
    check center in hexes

    # Verify all neighbors included
    for dir in 0 .. 5:
      check center.neighbor(dir) in hexes

suite "Hex: Lane Weights":
  ## Lane type movement costs for pathfinding

  test "Major lane weight is 1":
    check weight(LaneClass.Major) == 1

  test "Minor lane weight is 2":
    check weight(LaneClass.Minor) == 2

  test "Restricted lane weight is 3":
    check weight(LaneClass.Restricted) == 3

  test "Major is cheapest":
    check weight(LaneClass.Major) < weight(LaneClass.Minor)
    check weight(LaneClass.Minor) < weight(LaneClass.Restricted)

suite "Hex: Map Size Calculations":
  ## totalSystems and systemsPerHouse formulas

  test "totalSystems formula: 3n^2 + 3n + 1":
    check totalSystems(2) == 19 # 3*4 + 6 + 1
    check totalSystems(3) == 37 # 3*9 + 9 + 1
    check totalSystems(4) == 61 # 3*16 + 12 + 1
    check totalSystems(6) == 127 # 3*36 + 18 + 1

  test "systemsPerHouse scaling":
    # 2 houses: 19/2 = 9.5
    check abs(systemsPerHouse(2) - 9.5) < 0.1
    # 4 houses: 61/4 = 15.25
    check abs(systemsPerHouse(4) - 15.25) < 0.1
    # 6 houses: 127/6 = 21.17
    check abs(systemsPerHouse(6) - 21.17) < 0.1

  test "larger maps give more systems per house":
    check systemsPerHouse(4) > systemsPerHouse(2)
    check systemsPerHouse(6) > systemsPerHouse(4)
    check systemsPerHouse(12) > systemsPerHouse(6)

suite "Hex: Map Validation":
  ## validateMapRings domain validation

  test "zero rings is invalid":
    let errors = validateMapRings(0)
    check errors.len > 0

  test "one ring is valid":
    let errors = validateMapRings(1)
    check errors.len == 0

  test "20 rings is valid":
    let errors = validateMapRings(20)
    check errors.len == 0

  test "21 rings is invalid":
    let errors = validateMapRings(21)
    check errors.len > 0

  test "negative rings is invalid":
    let errors = validateMapRings(-1)
    check errors.len > 0

when isMainModule:
  echo "========================================"
  echo "  Hex Grid Unit Tests"
  echo "========================================"
