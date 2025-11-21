## Hex Coordinate Unit Tests
##
## Tests for hex grid coordinate system and operations

import unittest
import ../../src/common/hex

suite "Hex Coordinate Tests":
  test "hex creation and basic properties":
    let h1 = newHex(0, 0)
    let h2 = newHex(1, -1)
    let h3 = hex(2, -1)

    check h1.q == 0
    check h1.r == 0
    check h2.q == 1
    check h2.r == -1
    check h3.q == 2
    check h3.r == -1

  test "hex equality":
    let h1 = hex(1, 2)
    let h2 = hex(1, 2)
    let h3 = hex(2, 1)

    check h1 == h2
    check h1 != h3

  test "hex distance calculation":
    let origin = hex(0, 0)
    let h1 = hex(1, 0)
    let h2 = hex(1, -1)
    let h3 = hex(2, -1)

    check distance(origin, h1) == 1
    check distance(origin, h2) == 1
    check distance(origin, h3) == 2
    check distance(h1, h2) == 1
    check distance(h1, h3) == 1

  test "hex neighbors":
    let center = hex(0, 0)
    let neighbors = center.neighbors()

    check neighbors.len == 6
    check hex(1, 0) in neighbors
    check hex(1, -1) in neighbors
    check hex(0, -1) in neighbors
    check hex(-1, 0) in neighbors
    check hex(-1, 1) in neighbors
    check hex(0, 1) in neighbors

  test "hex within radius":
    let center = hex(0, 0)
    let radius1 = center.withinRadius(1)
    let radius2 = center.withinRadius(2)

    check radius1.len == 7  # center + 6 neighbors
    check radius2.len == 19 # center + 6 neighbors + 12 second ring
    check center in radius1
    check center in radius2

  test "hex to ID conversion":
    let h1 = hex(0, 0)
    let h2 = hex(1, 0)
    let h3 = hex(0, 1)

    let id1 = h1.toId(3)
    let id2 = h2.toId(3)
    let id3 = h3.toId(3)

    check id1 != id2
    check id1 != id3
    check id2 != id3

when isMainModule:
  echo "Running Hex Coordinate Tests..."
