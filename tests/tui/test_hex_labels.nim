## Unit Tests: Hex Labels
##
## Tests ring+position label conversion for human-readable coordinates.
## H = hub, A1-A6 = ring 1, B1-B12 = ring 2, etc.

import std/[unittest, options, strutils]
import ../../src/player/tui/hex_labels

suite "Hex Labels: coordLabel (axial to label)":

  test "origin is hub (H)":
    check coordLabel(0, 0) == "H"

  test "ring 1 positions (A1-A6)":
    # Starting at 12 o'clock, going clockwise
    check coordLabel(0, -1) == "A1"  # 12 o'clock
    check coordLabel(1, -1) == "A2"  # 2 o'clock
    check coordLabel(1, 0) == "A3"   # 4 o'clock
    check coordLabel(0, 1) == "A4"   # 6 o'clock
    check coordLabel(-1, 1) == "A5"  # 8 o'clock
    check coordLabel(-1, 0) == "A6"  # 10 o'clock

  test "ring 2 has 12 positions (B1-B12)":
    check coordLabel(0, -2) == "B1"  # 12 o'clock
    check coordLabel(2, 0) == "B5"   # Position 5 (not 4)

  test "tuple overload works":
    check coordLabel((0, 0)) == "H"
    check coordLabel((1, -1)) == "A2"

suite "Hex Labels: labelToAxial (label to axial)":

  test "hub parses correctly":
    let result = labelToAxial("H")
    check result.isSome
    check result.get == (0, 0)

  test "lowercase hub works":
    let result = labelToAxial("h")
    check result.isSome
    check result.get == (0, 0)

  test "ring 1 A1 parses":
    let result = labelToAxial("A1")
    check result.isSome
    check result.get == (0, -1)

  test "ring 1 A3 parses":
    let result = labelToAxial("A3")
    check result.isSome
    check result.get == (1, 0)

  test "lowercase ring label works":
    let result = labelToAxial("a3")
    check result.isSome
    check result.get == (1, 0)

  test "ring 2 B1 parses":
    let result = labelToAxial("B1")
    check result.isSome
    check result.get == (0, -2)

  test "invalid labels return none":
    check labelToAxial("").isNone
    check labelToAxial("X").isNone      # No position number
    check labelToAxial("123").isNone    # No letter
    check labelToAxial("A0").isNone     # Position 0 invalid
    check labelToAxial("A7").isNone     # Ring 1 only has 6 positions
    check labelToAxial("B13").isNone    # Ring 2 only has 12 positions

  test "alternative API with var parameters":
    var q, r: int
    check labelToAxial("A1", q, r) == true
    check q == 0
    check r == -1

    check labelToAxial("invalid", q, r) == false

suite "Hex Labels: Round-trip conversion":

  test "coordLabel -> labelToAxial for hub":
    let label = coordLabel(0, 0)
    let result = labelToAxial(label)
    check result.isSome
    check result.get == (0, 0)

  test "coordLabel -> labelToAxial for ring 1":
    for q in -1..1:
      for r in -1..1:
        if q == 0 and r == 0:
          continue  # Skip hub
        # Check if this is a ring 1 coordinate
        let dist = max(abs(q), max(abs(r), abs(q + r)))
        if dist == 1:
          let label = coordLabel(q, r)
          let result = labelToAxial(label)
          check result.isSome
          check result.get.q == q
          check result.get.r == r

  test "coordLabel -> labelToAxial for ring 2":
    # Test a few ring 2 coordinates
    let coords = [(0, -2), (1, -2), (2, -2), (2, -1), (2, 0),
                  (1, 1), (0, 2), (-1, 2), (-2, 2), (-2, 1),
                  (-2, 0), (-1, -1)]
    for coord in coords:
      let (q, r) = coord
      let label = coordLabel(q, r)
      let result = labelToAxial(label)
      check result.isSome
      check result.get.q == q
      check result.get.r == r

suite "Hex Labels: Ring label generation":

  test "ring 1 is A":
    # Checked via coordLabel output prefix
    check coordLabel(0, -1).startsWith("A")

  test "ring 2 is B":
    check coordLabel(0, -2).startsWith("B")

  test "ring 26 is Z":
    # Ring 26 would be very far out (26 * 6 = 156 positions)
    # Check the ringLabel proc directly
    # Ring 26: 12 o'clock is at (0, -26)
    let label = coordLabel(0, -26)
    check label.startsWith("Z")

  test "ring 27 is AA":
    let label = coordLabel(0, -27)
    check label.startsWith("AA")
