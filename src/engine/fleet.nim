## Fleet management for EC4X
##
## This module defines fleets which are collections of ships that can
## move together and engage in combat as a unit.

import ship
import ../common/types
import std/[sequtils, algorithm, strutils]

export FleetId, SystemId, HouseId, LaneType

type
  Fleet* = object
    ## A collection of ships that move and fight together
    id*: FleetId          # Unique fleet identifier
    ships*: seq[Ship]     # Ships in the fleet
    owner*: HouseId       # House that owns this fleet
    location*: SystemId   # Current system location

proc newFleet*(ships: seq[Ship] = @[], id: FleetId = "", owner: HouseId = "", location: SystemId = 0): Fleet =
  ## Create a new fleet with the given ships
  Fleet(id: id, ships: ships, owner: owner, location: location)

proc `$`*(f: Fleet): string =
  ## String representation of a fleet
  if f.ships.len == 0:
    "Empty Fleet"
  else:
    "Fleet[" & $f.ships.len & " ships: " & f.ships.mapIt($it).join(", ") & "]"

proc len*(f: Fleet): int =
  ## Get the number of ships in the fleet
  f.ships.len

proc isEmpty*(f: Fleet): bool =
  ## Check if the fleet has no ships
  f.ships.len == 0

proc add*(f: var Fleet, ship: Ship) =
  ## Add a ship to the fleet
  f.ships.add(ship)

proc remove*(f: var Fleet, index: int) =
  ## Remove a ship at the given index
  if index >= 0 and index < f.ships.len:
    f.ships.delete(index)

proc clear*(f: var Fleet) =
  ## Remove all ships from the fleet
  f.ships.setLen(0)

proc canTraverse*(f: Fleet, laneType: LaneType): bool =
  ## Check if the fleet can traverse a specific type of jump lane
  case laneType
  of LaneType.Restricted:
    # All ships must be able to cross restricted lanes
    f.ships.allIt(it.canCrossRestrictedLane())
  else:
    # Major and Minor lanes can be traversed by any fleet
    true

proc combatStrength*(f: Fleet): int =
  ## Calculate the total combat strength of the fleet
  f.ships.countIt(it.isCombatCapable())

proc transportCapacity*(f: Fleet): int =
  ## Calculate the total transport capacity of the fleet
  f.ships.countIt(it.canCarryTroops())

proc hasCombatShips*(f: Fleet): bool =
  ## Check if the fleet has any combat-capable ships
  f.ships.anyIt(it.isCombatCapable())

proc hasTransportShips*(f: Fleet): bool =
  ## Check if the fleet has any transport-capable ships
  f.ships.anyIt(it.canCarryTroops())

proc militaryShips*(f: Fleet): seq[Ship] =
  ## Get all military ships in the fleet
  f.ships.filterIt(it.shipType == Military)

proc spaceliftShips*(f: Fleet): seq[Ship] =
  ## Get all spacelift ships in the fleet
  f.ships.filterIt(it.shipType == Spacelift)

proc crippledShips*(f: Fleet): seq[Ship] =
  ## Get all crippled ships in the fleet
  f.ships.filterIt(it.isCrippled)

proc effectiveShips*(f: Fleet): seq[Ship] =
  ## Get all non-crippled ships in the fleet
  f.ships.filterIt(not it.isCrippled)

proc merge*(f1: var Fleet, f2: Fleet) =
  ## Merge another fleet into this one
  f1.ships.add(f2.ships)

proc split*(f: var Fleet, indices: seq[int]): Fleet =
  ## Split off ships at the given indices into a new fleet
  var newShips: seq[Ship] = @[]
  var toRemove: seq[int] = @[]

  for i in indices:
    if i >= 0 and i < f.ships.len:
      newShips.add(f.ships[i])
      toRemove.add(i)

  # Remove ships from original fleet (in reverse order to maintain indices)
  for i in toRemove.sorted(Descending):
    f.ships.delete(i)

  newFleet(newShips)

# Convenience constructors
proc fleet*(ships: varargs[Ship]): Fleet =
  ## Create a fleet from individual ships
  newFleet(@ships)

proc militaryFleet*(count: int, crippled: bool = false): Fleet =
  ## Create a fleet of military ships
  var ships: seq[Ship] = @[]
  for i in 0..<count:
    ships.add(militaryShip(crippled))
  newFleet(ships)

proc spaceliftFleet*(count: int, crippled: bool = false): Fleet =
  ## Create a fleet of spacelift ships
  var ships: seq[Ship] = @[]
  for i in 0..<count:
    ships.add(spaceliftShip(crippled))
  newFleet(ships)

proc mixedFleet*(military: int, spacelift: int): Fleet =
  ## Create a mixed fleet with both military and spacelift ships
  var ships: seq[Ship] = @[]
  for i in 0..<military:
    ships.add(militaryShip())
  for i in 0..<spacelift:
    ships.add(spaceliftShip())
  newFleet(ships)
