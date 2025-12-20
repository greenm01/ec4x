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

## Star system representation for EC4X game
##
## This module defines star systems which are the primary locations
## in the game world, arranged in a hexagonal grid pattern.

import hex
import std/[options, random]
import types/planets

type
  System* = object
    ## A star system in the game world
    id*: uint           ## Unique identifier for the system
    coords*: Hex        ## Hexagonal coordinates on the star map
    ring*: uint32       ## Distance from the central hub system
    player*: Option[uint]  ## Which player controls this system (if any)
    planetClass*: PlanetClass  ## Habitability classification
    resourceRating*: ResourceRating  ## Resource availability

proc newSystem*(coords: Hex, ring: uint32, numRings: uint32, player: Option[uint] = none(uint)): System =
  ## Create a new star system with randomized planet properties
  ## Planet distribution (realistic bell curve):
  ## - Extreme/Desolate: 10% each (harsh frontier)
  ## - Hostile/Harsh: 25% each (challenging colonies)
  ## - Benign: 20% (average)
  ## - Lush/Eden: 8%/2% (prizes worth fighting for)
  ## Uses system ID as seed for deterministic generation
  let id = coords.toId(numRings)

  # Use system ID as seed for deterministic planet generation
  var rng = initRand(int64(id))

  # Generate planet class (weighted distribution)
  let planetRoll = rng.rand(99)
  let planetClass =
    if planetRoll < 10: PlanetClass.Extreme
    elif planetRoll < 20: PlanetClass.Desolate
    elif planetRoll < 45: PlanetClass.Hostile
    elif planetRoll < 70: PlanetClass.Harsh
    elif planetRoll < 90: PlanetClass.Benign
    elif planetRoll < 98: PlanetClass.Lush
    else: PlanetClass.Eden

  # Generate resource rating (bell curve around Abundant)
  let resourceRoll = rng.rand(99)
  let resourceRating =
    if resourceRoll < 10: ResourceRating.VeryPoor
    elif resourceRoll < 30: ResourceRating.Poor
    elif resourceRoll < 70: ResourceRating.Abundant
    elif resourceRoll < 90: ResourceRating.Rich
    else: ResourceRating.VeryRich

  System(
    id: id,
    coords: coords,
    ring: ring,
    player: player,
    planetClass: planetClass,
    resourceRating: resourceRating
  )

proc `$`*(s: System): string =
  ## String representation of a star system
  let playerStr = if s.player.isSome: " (Player " & $s.player.get & ")" else: ""
  "System " & $s.id & " at " & $s.coords & " (Ring " & $s.ring & ")" & playerStr

proc `==`*(a, b: System): bool =
  ## Equality comparison for star systems
  a.id == b.id

proc isControlled*(s: System): bool =
  ## Check if the system is controlled by a player
  s.player.isSome

proc controlledBy*(s: System, playerId: uint): bool =
  ## Check if the system is controlled by a specific player
  s.player.isSome and s.player.get == playerId

proc setController*(s: var System, playerId: uint) =
  ## Set the controlling player for this system
  s.player = some(playerId)

proc clearController*(s: var System) =
  ## Remove player control from this system
  s.player = none(uint)

proc isHomeSystem*(s: System): bool =
  ## Check if this is a home system (ring 0)
  s.ring == 0

proc isHub*(s: System): bool =
  ## Check if this is the central hub system
  s.coords == HexOrigin and s.ring == 0

proc distanceFromHub*(s: System): uint32 =
  ## Get the distance from the central hub
  distance(s.coords, HexOrigin)

proc isAdjacent*(s1, s2: System): bool =
  ## Check if two systems are adjacent (distance = 1)
  distance(s1.coords, s2.coords) == 1

proc adjacentCoords*(s: System): seq[Hex] =
  ## Get the hex coordinates of all adjacent systems
  s.coords.neighbors()