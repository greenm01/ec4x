## Hex label helpers for human-friendly coordinates
##
## Provides ring+position labels for axial hex coordinates.
## Example: Hub=H, Ring 1=A1..A6, Ring 2=B1..B12.

import std/[options, strutils]

type
  RingDirection = object
    q: int
    r: int

const
  RingDirections: array[6, RingDirection] = [
    RingDirection(q: 1, r: 0),
    RingDirection(q: 0, r: 1),
    RingDirection(q: -1, r: 1),
    RingDirection(q: -1, r: 0),
    RingDirection(q: 0, r: -1),
    RingDirection(q: 1, r: -1)
  ]

proc axialDistance(q1, r1, q2, r2: int): int =
  ## Hex distance using axial coordinates
  let dq = q1 - q2
  let dr = r1 - r2
  (abs(dq) + abs(dq + dr) + abs(dr)) div 2

proc ringIndex(q, r: int): int =
  ## Ring number from the origin
  axialDistance(q, r, 0, 0)

proc ringLabel(ring: int): string =
  ## Convert ring number (1-based) to letters (A, B, ..., Z, AA, AB...)
  if ring <= 0:
    return ""

  var index = ring - 1
  result = ""

  while true:
    let letter = char(ord('A') + (index mod 26))
    result = $letter & result
    index = index div 26 - 1
    if index < 0:
      break

proc ringPosition(q, r, ring: int): int =
  ## Position within ring starting at 12 o'clock clockwise
  if ring == 0:
    return 0

  var currentQ = 0
  var currentR = -ring
  var position = 1

  if currentQ == q and currentR == r:
    return position

  for dir in RingDirections:
    for _ in 0 ..< ring:
      currentQ += dir.q
      currentR += dir.r
      position += 1
      if currentQ == q and currentR == r:
        return position

  0

proc coordLabel*(q, r: int): string =
  ## Convert axial coordinate to ring+position label
  let ring = ringIndex(q, r)
  if ring == 0:
    return "H"

  let position = ringPosition(q, r, ring)
  let label = ringLabel(ring)

  if position > 0:
    label & $position
  else:
    label

proc coordLabel*(coord: tuple[q, r: int]): string =
  ## Convert tuple coordinate to ring+position label
  coordLabel(coord.q, coord.r)

proc parseLabelRing(label: string): int =
  ## Parse letter prefix to ring number (A=1, B=2, ..., Z=26, AA=27, ...)
  ## Returns 0 if invalid
  if label.len == 0:
    return 0
  
  result = 0
  for ch in label:
    if ch < 'A' or ch > 'Z':
      return 0
    result = result * 26 + (ord(ch) - ord('A') + 1)

proc ringCoordAtPosition(ring, position: int): tuple[q, r: int] =
  ## Get axial coordinates for a position within a ring
  ## Position 1 starts at 12 o'clock, clockwise
  if ring <= 0 or position <= 0:
    return (0, 0)
  
  let totalPositions = ring * 6
  if position > totalPositions:
    return (0, 0)
  
  # Start at 12 o'clock (0, -ring)
  var q = 0
  var r = -ring
  var pos = 1
  
  if pos == position:
    return (q, r)
  
  for dir in RingDirections:
    for _ in 0 ..< ring:
      q += dir.q
      r += dir.r
      pos += 1
      if pos == position:
        return (q, r)
  
  (0, 0)

proc labelToAxial*(label: string): Option[tuple[q, r: int]] =
  ## Convert ring+position label to axial coordinates
  ## Examples: "H" -> (0,0), "A1" -> (0,-1), "B7" -> coords for B7
  ## Returns none if label is invalid
  if label.len == 0:
    return none(tuple[q, r: int])
  
  # Handle hub
  let upper = label.toUpperAscii()
  if upper == "H":
    return some((0, 0))
  
  # Find where letters end and digits begin
  var letterEnd = 0
  for i, ch in upper:
    if ch >= 'A' and ch <= 'Z':
      letterEnd = i + 1
    else:
      break
  
  if letterEnd == 0:
    return none(tuple[q, r: int])
  
  let letterPart = upper[0 ..< letterEnd]
  let ring = parseLabelRing(letterPart)
  
  if ring <= 0:
    return none(tuple[q, r: int])
  
  # Parse position number
  if letterEnd >= upper.len:
    return none(tuple[q, r: int])
  
  let numPart = upper[letterEnd ..< upper.len]
  var position: int
  try:
    position = parseInt(numPart)
  except ValueError:
    return none(tuple[q, r: int])
  
  # Validate position is within ring bounds
  let maxPosition = ring * 6
  if position < 1 or position > maxPosition:
    return none(tuple[q, r: int])
  
  let coords = ringCoordAtPosition(ring, position)
  some(coords)

proc labelToAxial*(label: string, q, r: var int): bool =
  ## Convert label to axial coordinates, returning success status
  ## Alternative API for direct variable assignment
  let coordOpt = labelToAxial(label)
  if coordOpt.isSome:
    q = coordOpt.get.q
    r = coordOpt.get.r
    true
  else:
    false
