## Fleet management for EC4X
##
## This module defines fleets which are collections of squadrons that can
## move together and engage in combat as a unit.

import ship, squadron
import ../common/types/[core, combat]
import std/[sequtils, algorithm, strutils]

export FleetId, SystemId, HouseId, LaneType
export Squadron, EnhancedShip, ShipClass  # Export for fleet users

type
  Fleet* = object
    ## A collection of squadrons that move and fight together
    id*: FleetId              # Unique fleet identifier
    squadrons*: seq[Squadron] # Squadrons in the fleet (CHANGED from ships)
    owner*: HouseId           # House that owns this fleet
    location*: SystemId       # Current system location

proc newFleet*(squadrons: seq[Squadron] = @[], id: FleetId = "", owner: HouseId = "", location: SystemId = 0): Fleet =
  ## Create a new fleet with the given squadrons
  Fleet(id: id, squadrons: squadrons, owner: owner, location: location)

proc `$`*(f: Fleet): string =
  ## String representation of a fleet
  if f.squadrons.len == 0:
    "Empty Fleet"
  else:
    var shipClasses: seq[string] = @[]
    for sq in f.squadrons:
      let status = if sq.flagship.isCrippled: "*" else: ""
      shipClasses.add($sq.flagship.shipClass & status)
    "Fleet[" & $f.squadrons.len & " squadrons: " & shipClasses.join(", ") & "]"

proc len*(f: Fleet): int =
  ## Get the number of squadrons in the fleet
  f.squadrons.len

proc isEmpty*(f: Fleet): bool =
  ## Check if the fleet has no squadrons
  f.squadrons.len == 0

proc add*(f: var Fleet, squadron: Squadron) =
  ## Add a squadron to the fleet
  f.squadrons.add(squadron)

proc remove*(f: var Fleet, index: int) =
  ## Remove a squadron at the given index
  if index >= 0 and index < f.squadrons.len:
    f.squadrons.delete(index)

proc clear*(f: var Fleet) =
  ## Remove all squadrons from the fleet
  f.squadrons.setLen(0)

proc canTraverse*(f: Fleet, laneType: LaneType): bool =
  ## Check if the fleet can traverse a specific type of jump lane
  case laneType
  of LaneType.Restricted:
    # All squadrons must be able to cross restricted lanes
    # Crippled squadrons and spacelift squadrons cannot
    for sq in f.squadrons:
      if sq.flagship.isCrippled:
        return false
      if sq.flagship.shipClass in [ShipClass.TroopTransport, ShipClass.ETAC]:
        return false
    return true
  else:
    # Major and Minor lanes can be traversed by any fleet
    true

proc combatStrength*(f: Fleet): int =
  ## Calculate the total attack strength of the fleet
  result = 0
  for sq in f.squadrons:
    result += sq.combatStrength()

proc transportCapacity*(f: Fleet): int =
  ## Calculate the number of transport squadrons
  result = 0
  for sq in f.squadrons:
    if sq.flagship.shipClass in [ShipClass.TroopTransport, ShipClass.ETAC]:
      if not sq.flagship.isCrippled:
        result += 1

proc hasCombatShips*(f: Fleet): bool =
  ## Check if the fleet has any combat-capable squadrons
  for sq in f.squadrons:
    if sq.combatStrength() > 0:
      return true
  return false

proc hasTransportShips*(f: Fleet): bool =
  ## Check if the fleet has any transport-capable squadrons
  for sq in f.squadrons:
    if sq.flagship.shipClass in [ShipClass.TroopTransport, ShipClass.ETAC]:
      if not sq.flagship.isCrippled:
        return true
  return false

proc combatSquadrons*(f: Fleet): seq[Squadron] =
  ## Get all combat-capable squadrons
  result = @[]
  for sq in f.squadrons:
    if sq.combatStrength() > 0:
      result.add(sq)

proc transportSquadrons*(f: Fleet): seq[Squadron] =
  ## Get all transport squadrons
  result = @[]
  for sq in f.squadrons:
    if sq.flagship.shipClass in [ShipClass.TroopTransport, ShipClass.ETAC]:
      result.add(sq)

proc crippledSquadrons*(f: Fleet): seq[Squadron] =
  ## Get all squadrons with crippled flagships
  result = @[]
  for sq in f.squadrons:
    if sq.flagship.isCrippled:
      result.add(sq)

proc effectiveSquadrons*(f: Fleet): seq[Squadron] =
  ## Get all squadrons with non-crippled flagships
  result = @[]
  for sq in f.squadrons:
    if not sq.flagship.isCrippled:
      result.add(sq)

proc merge*(f1: var Fleet, f2: Fleet) =
  ## Merge another fleet into this one
  f1.squadrons.add(f2.squadrons)

proc split*(f: var Fleet, indices: seq[int]): Fleet =
  ## Split off squadrons at the given indices into a new fleet
  var newSquadrons: seq[Squadron] = @[]
  var toRemove: seq[int] = @[]

  for i in indices:
    if i >= 0 and i < f.squadrons.len:
      newSquadrons.add(f.squadrons[i])
      toRemove.add(i)

  # Remove squadrons from original fleet (in reverse order to maintain indices)
  for i in toRemove.sorted(Descending):
    f.squadrons.delete(i)

  newFleet(newSquadrons)
