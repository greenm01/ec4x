## Star system representation for EC4X game
##
## This module defines star systems which are the primary locations
## in the game world, arranged in a hexagonal grid pattern.

import hex
import std/options

type
  System* = object
    ## A star system in the game world
    id*: uint           ## Unique identifier for the system
    coords*: Hex        ## Hexagonal coordinates on the star map
    ring*: uint32       ## Distance from the central hub system
    player*: Option[uint]  ## Which player controls this system (if any)

proc newSystem*(coords: Hex, ring: uint32, numRings: uint32, player: Option[uint] = none(uint)): System =
  ## Create a new star system
  let id = coords.toId(numRings)
  System(
    id: id,
    coords: coords,
    ring: ring,
    player: player
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
