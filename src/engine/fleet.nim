## Fleet management for EC4X
##
## This module defines fleets which are collections of squadrons that can
## move together and engage in combat as a unit.
##
## ARCHITECTURE FIX (2025-11-23):
## - Combat squadrons and spacelift ships are now SEPARATE
## - Fleet → Squadrons (combat units) + SpaceLiftShips (transport/colonization)
## - Per operations.md:288, spacelift ships are screened during combat

import squadron, spacelift
import ../common/types/[core, combat]
import std/[algorithm, strutils]

export FleetId, SystemId, HouseId, LaneType
export Squadron, EnhancedShip, ShipClass  # Export for fleet users
export SpaceLiftShip, SpaceLiftCargo, CargoType  # Export spacelift types

type
  FleetStatus* {.pure.} = enum
    ## Fleet operational status per economy.md:3.9
    Active,      # Normal active duty (100% maintenance)
    Reserve,     # Reserve status (50% maintenance, half AS/DS, can't move)
    Mothballed   # Mothballed (0% maintenance, offline, screened in combat)

  Fleet* = object
    ## A collection of squadrons and spacelift ships that move together
    id*: FleetId                       # Unique fleet identifier
    squadrons*: seq[Squadron]          # Combat squadrons ONLY
    spaceLiftShips*: seq[SpaceLiftShip] # Spacelift ships (separate)
    owner*: HouseId                    # House that owns this fleet
    location*: SystemId                # Current system location
    status*: FleetStatus               # Operational status (active/reserve/mothballed)
    autoBalanceSquadrons*: bool        # Auto-optimize squadron composition (default: true)
    # NOTE: currentOrder stored in GameState.fleetOrders table to avoid circular dependency

proc newFleet*(squadrons: seq[Squadron] = @[], spaceLiftShips: seq[SpaceLiftShip] = @[],
               id: FleetId = "", owner: HouseId = "", location: SystemId = 0,
               status: FleetStatus = FleetStatus.Active,
               autoBalanceSquadrons: bool = true): Fleet =
  ## Create a new fleet with the given squadrons and spacelift ships
  Fleet(id: id, squadrons: squadrons, spaceLiftShips: spaceLiftShips,
        owner: owner, location: location, status: status,
        autoBalanceSquadrons: autoBalanceSquadrons)

proc `$`*(f: Fleet): string =
  ## String representation of a fleet
  if f.squadrons.len == 0 and f.spaceLiftShips.len == 0:
    "Empty Fleet"
  else:
    var parts: seq[string] = @[]

    if f.squadrons.len > 0:
      var shipClasses: seq[string] = @[]
      for sq in f.squadrons:
        let status = if sq.flagship.isCrippled: "*" else: ""
        shipClasses.add($sq.flagship.shipClass & status)
      parts.add($f.squadrons.len & " squadrons: " & shipClasses.join(", "))

    if f.spaceLiftShips.len > 0:
      var spaceliftStrs: seq[string] = @[]
      for ship in f.spaceLiftShips:
        spaceliftStrs.add($ship)
      parts.add($f.spaceLiftShips.len & " spacelift: " & spaceliftStrs.join(", "))

    "Fleet[" & parts.join(" | ") & "]"

proc len*(f: Fleet): int =
  ## Get the number of squadrons in the fleet
  f.squadrons.len

proc isEmpty*(f: Fleet): bool =
  ## Check if the fleet has no squadrons AND no spacelift ships
  f.squadrons.len == 0 and f.spaceLiftShips.len == 0

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
  ## Per operations.md:9 "Fleets containing crippled ships or Spacelift Command ships can not jump across restricted lanes"
  case laneType
  of LaneType.Restricted:
    # Check for crippled squadrons
    for sq in f.squadrons:
      if sq.flagship.isCrippled:
        return false

    # Check for spacelift ships (ARCHITECTURE FIX: now separate from squadrons)
    if f.spaceLiftShips.len > 0:
      return false  # Cannot cross restricted lanes with ANY spacelift ships

    return true
  else:
    # Major and Minor lanes can be traversed by any fleet
    true

proc combatStrength*(f: Fleet): int =
  ## Calculate the total attack strength of the fleet
  result = 0
  for sq in f.squadrons:
    result += sq.combatStrength()

proc isCloaked*(f: Fleet): bool =
  ## Check if fleet is cloaked
  ## Per assets.md:2.4.3: "Fleets that include Raiders are fully cloaked"
  ## Returns true if fleet has ANY non-crippled raiders
  if f.squadrons.len == 0:
    return false

  # Check if fleet has any operational raiders
  for sq in f.squadrons:
    let raiders = sq.raiderShips()
    for raider in raiders:
      if not raider.isCrippled:
        return true  # Fleet is cloaked if it has ANY operational raider

  return false

proc transportCapacity*(f: Fleet): int =
  ## Calculate the number of operational spacelift ships
  ## ARCHITECTURE FIX: Spacelift ships are now separate from squadrons
  result = 0
  for ship in f.spaceLiftShips:
    if not ship.isCrippled:
      result += 1

proc hasCombatShips*(f: Fleet): bool =
  ## Check if the fleet has any combat-capable squadrons
  for sq in f.squadrons:
    if sq.combatStrength() > 0:
      return true
  return false

proc hasTransportShips*(f: Fleet): bool =
  ## Check if the fleet has any operational spacelift ships
  ## ARCHITECTURE FIX: Spacelift ships are now separate from squadrons
  for ship in f.spaceLiftShips:
    if not ship.isCrippled:
      return true
  return false

proc combatSquadrons*(f: Fleet): seq[Squadron] =
  ## Get all combat-capable squadrons
  result = @[]
  for sq in f.squadrons:
    if sq.combatStrength() > 0:
      result.add(sq)

proc spaceLiftShipsSeq*(f: Fleet): seq[SpaceLiftShip] =
  ## Get all spacelift ships
  ## ARCHITECTURE FIX: Renamed from transportSquadrons, returns SpaceLiftShips not Squadrons
  return f.spaceLiftShips

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
  ## ARCHITECTURE FIX: Merge both squadrons and spacelift ships
  f1.squadrons.add(f2.squadrons)
  f1.spaceLiftShips.add(f2.spaceLiftShips)

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

proc balanceSquadrons*(f: var Fleet) =
  ## Auto-optimize squadron composition within fleet
  ##
  ## **Purpose:** Redistribute escort ships across squadrons to maximize
  ## command capacity utilization and create balanced, effective battle groups.
  ##
  ## **Algorithm:**
  ## 1. Extract all escort ships from all squadrons (preserve flagships)
  ## 2. Sort escorts by command cost (largest first for better bin packing)
  ## 3. Redistribute escorts across squadrons using greedy bin packing
  ##    - Prioritize squadrons with more available capacity
  ##    - Try to balance total command usage across squadrons
  ##
  ## **Result:** Each squadron uses its command capacity more efficiently
  ## and squadrons are more evenly balanced in strength.
  ##
  ## **Note:** Only affects escort ships (ships array), never moves flagships
  ##
  ## **Performance Optimization:**
  ## Checks if balancing is needed before doing expensive sort operation.
  ## Only balances if there's significant imbalance (one squadron empty while another has escorts).

  if f.squadrons.len < 2:
    return  # Nothing to balance with fewer than 2 squadrons

  # Performance optimization: Check if balancing is actually needed
  # Only balance if there's at least one squadron with 0 escorts and another with 2+ escorts
  var minEscorts = 999999
  var maxEscorts = 0
  for sq in f.squadrons:
    let escortCount = sq.ships.len
    if escortCount < minEscorts:
      minEscorts = escortCount
    if escortCount > maxEscorts:
      maxEscorts = escortCount

  # If all squadrons have similar escort counts (within 1), skip balancing
  if maxEscorts - minEscorts <= 1:
    return  # Already balanced enough, skip expensive sort

  # Step 1: Extract all escorts from all squadrons
  var allEscorts: seq[EnhancedShip] = @[]
  for i in 0..<f.squadrons.len:
    allEscorts.add(f.squadrons[i].ships)
    f.squadrons[i].ships = @[]  # Clear escorts (keep flagship)

  if allEscorts.len == 0:
    return  # No escorts to balance

  # Step 2: Sort escorts by command cost (descending) for better bin packing
  # Larger ships first = better capacity utilization
  allEscorts.sort do (a, b: EnhancedShip) -> int:
    result = cmp(b.stats.commandCost, a.stats.commandCost)

  # Step 3: Redistribute escorts using greedy algorithm
  # Try to fill squadrons evenly, prioritizing those with most available space
  for escort in allEscorts:
    # Find squadron with most available command capacity that can fit this escort
    var bestSquadronIdx = -1
    var bestCapacity = -1

    for i in 0..<f.squadrons.len:
      let availableCapacity = f.squadrons[i].availableCommandCapacity()

      # Can this squadron fit this escort?
      if availableCapacity >= escort.stats.commandCost:
        # Is this the squadron with most available capacity?
        if availableCapacity > bestCapacity:
          bestCapacity = availableCapacity
          bestSquadronIdx = i

    # Assign escort to best squadron (if any can fit)
    if bestSquadronIdx >= 0:
      discard f.squadrons[bestSquadronIdx].addShip(escort)
    else:
      # No squadron can fit this escort - add to squadron with most space anyway
      # This handles edge cases where escort CC > any squadron's available CR
      var maxCapacityIdx = 0
      var maxCapacity = f.squadrons[0].availableCommandCapacity()
      for i in 1..<f.squadrons.len:
        let cap = f.squadrons[i].availableCommandCapacity()
        if cap > maxCapacity:
          maxCapacity = cap
          maxCapacityIdx = i

      # Force add (will exceed capacity, but better than losing the ship)
      f.squadrons[maxCapacityIdx].ships.add(escort)
