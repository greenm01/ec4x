## Hexagonal coordinate system for EC4X game maps
##
## This module provides a hexagonal coordinate system using axial coordinates (q, r).
## The hex grid is used to represent star systems in the game world.

import std/[hashes]

type
  Hex* = object
    q*: int32  ## Axial coordinate q
    r*: int32  ## Axial coordinate r

proc newHex*(q, r: int32): Hex =
  ## Create a new hexagonal coordinate
  Hex(q: q, r: r)

proc `$`*(h: Hex): string =
  ## String representation of hex coordinate
  "Hex(q: " & $h.q & ", r: " & $h.r & ")"

proc `==`*(a, b: Hex): bool =
  ## Equality comparison for hex coordinates
  a.q == b.q and a.r == b.r

proc hash*(h: Hex): Hash =
  ## Hash function for hex coordinates
  var h = h
  result = h.q.hash !& h.r.hash
  result = !$result

proc toId*(h: Hex, numRings: uint32): uint =
  ## Convert hex coordinates to a unique ID based on the number of rings
  let maxCoord = numRings.int32 * 2
  let qShifted = h.q + numRings.int32
  let rShifted = h.r + numRings.int32
  (qShifted * (maxCoord + 1) + rShifted).uint

proc distance*(h1, h2: Hex): uint32 =
  ## Calculate the distance between two hex coordinates
  let dq = abs(h1.q - h2.q)
  let dr = abs(h1.r - h2.r)
  let ds = abs(h1.q + h1.r - h2.q - h2.r)
  ((dq + dr + ds) div 2).uint32

proc withinRadius*(center: Hex, radius: int32): seq[Hex] =
  ## Get all hex coordinates within a given radius from center
  result = @[]
  for q in -radius..radius:
    let r1 = max(-radius, -q - radius)
    let r2 = min(radius, -q + radius)
    for r in r1..r2:
      result.add(newHex(center.q + q, center.r + r))

proc neighbor*(h: Hex, direction: int): Hex =
  ## Get the neighbor hex in the specified direction (0-5)
  ## Directions: 0=East, 1=Northeast, 2=Northwest, 3=West, 4=Southwest, 5=Southeast
  const directions = [
    (1'i32, 0'i32),   # East
    (1'i32, -1'i32),  # Northeast
    (0'i32, -1'i32),  # Northwest
    (-1'i32, 0'i32),  # West
    (-1'i32, 1'i32),  # Southwest
    (0'i32, 1'i32)    # Southeast
  ]
  let (dq, dr) = directions[direction mod 6]
  newHex(h.q + dq, h.r + dr)

proc neighbors*(h: Hex): seq[Hex] =
  ## Get all 6 neighbors of a hex coordinate
  result = @[]
  for i in 0..5:
    result.add(h.neighbor(i))

# Convenience constructors
proc hex*(q, r: int32): Hex = newHex(q, r)
proc hex*(q, r: int): Hex = newHex(q.int32, r.int32)

# Origin hex constant
const HexOrigin* = Hex(q: 0, r: 0)
