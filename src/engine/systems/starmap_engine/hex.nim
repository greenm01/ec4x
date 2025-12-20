import ../../types/map/types

# Hex-related procedures
proc newHex*(q, r: int32): Hex = Hex(q: q, r: r)

proc `$`*(h: Hex): string = "Hex(q: " & $h.q & ", r: " & $h.r & ")"

proc `==`*(a, b: Hex): bool = a.q == b.q and a.r == b.r

proc hash*(h: Hex): Hash =
  var h = h
  result = h.q.hash !& h.r.hash
  result = !$result

proc toId*(h: Hex, numRings: uint32): uint =
  let maxCoord = numRings.int32 * 2
  let qShifted = h.q + numRings.int32
  let rShifted = h.r + numRings.int32
  (qShifted * (maxCoord + 1) + rShifted).uint

proc distance*(h1, h2: Hex): uint32 =
  let dq = abs(h1.q - h2.q)
  let dr = abs(h1.r - h2.r)
  let ds = abs(h1.q + h1.r - h2.q - h2.r)
  ((dq + dr + ds) div 2).uint32

proc withinRadius*(center: Hex, radius: int32): seq[Hex] =
  result = @[]
  for q in -radius..radius:
    let r1 = max(-radius, -q - radius)
    let r2 = min(radius, -q + radius)
    for r in r1..r2:
      result.add(newHex(center.q + q, center.r + r))

proc neighbor*(h: Hex, direction: int): Hex =
  const directions = [
    (1'i32, 0'i32), (1'i32, -1'i32), (0'i32, -1'i32),
    (-1'i32, 0'i32), (-1'i32, 1'i32), (0'i32, 1'i32)
  ]
  let (dq, dr) = directions[direction mod 6]
  newHex(h.q + dq, h.r + dr)

proc neighbors*(h: Hex): seq[Hex] =
  result = @[]
  for i in 0..5:
    result.add(h.neighbor(i))

proc hex*(q, r: int32): Hex = newHex(q, r)

proc hex*(q, r: int): Hex = newHex(q.int32, r.int32)

const HexOrigin* = Hex(q: 0, r: 0)

# System-related procedures
proc newSystem*(coords: Hex, ring: uint32, numRings: uint32, player: Option[uint] = none(uint)): System =
  let id = coords.toId(numRings)
  var rng = initRand(int64(id))
  let planetRoll = rng.rand(99)
  let planetClass =
    if planetRoll < 10: PlanetClass.Extreme
    elif planetRoll < 20: PlanetClass.Desolate
    elif planetRoll < 45: PlanetClass.Hostile
    elif planetRoll < 70: PlanetClass.Harsh
    elif planetRoll < 90: PlanetClass.Benign
    elif planetRoll < 98: PlanetClass.Lush
    else: PlanetClass.Eden
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
  let playerStr = if s.player.isSome: " (Player " & $s.player.get & ")" else: ""
  "System " & $s.id & " at " & $s.coords & " (Ring " & $s.ring & ")" & playerStr

proc `==`*(a, b: System): bool = a.id == b.id

proc isControlled*(s: System): bool = s.player.isSome

proc controlledBy*(s: System, playerId: uint): bool = s.player.isSome and s.player.get == playerId

proc setController*(s: var System, playerId: uint) = s.player = some(playerId)

proc clearController*(s: var System) = s.player = none(uint)

proc isHomeSystem*(s: System): bool = s.ring == 0

proc isHub*(s: System): bool = s.coords == HexOrigin and s.ring == 0

proc distanceFromHub*(s: System): uint32 = distance(s.coords, HexOrigin)

proc isAdjacent*(s1, s2: System): bool = distance(s1.coords, s2.coords) == 1

proc adjacentCoords*(s: System): seq[Hex] = s.coords.neighbors()
