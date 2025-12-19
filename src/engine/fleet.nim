## Fleet management for EC4X
##
## This module defines fleets which are collections of squadrons that can
## move together and engage in combat as a unit.
##
## UNIFIED ARCHITECTURE (2025-12-17):
## - Fleet → Squadrons (all types: Combat, Intel, Expansion, Auxiliary, Fighter)
## - Expansion squadrons (ETAC) handle colonization
## - Auxiliary squadrons (TroopTransport) handle invasion support
## - All ships use unified Squadron structure with squadronType classification

import ./squadron
import ../common/types/[core, combat]
import std/[algorithm, strutils, options]

export FleetId, SystemId, HouseId, LaneType, FleetMissionState
export Squadron, Ship, ShipClass  # Export for fleet users
export SquadronType, ShipCargo, CargoType  # Export squadron classification and cargo types

type
  FleetStatus* {.pure.} = enum
    ## Fleet operational status per economy.md:3.9
    Active,      # Normal active duty (100% maintenance)
    Reserve,     # Reserve status (50% maintenance, half AS/DS, can't move)
    Mothballed   # Mothballed (0% maintenance, offline, screened in combat)

  Fleet* = object
    ## A collection of squadrons that move together
    ## All squadron types: Combat, Intel, Expansion, Auxiliary, Fighter
    id*: FleetId                       # Unique fleet identifier
    squadrons*: seq[Squadron]          # All squadron types (Combat, Intel, Expansion, Auxiliary)
    owner*: HouseId                    # House that owns this fleet
    location*: SystemId                # Current system location
    status*: FleetStatus               # Operational status (active/reserve/mothballed)
    autoBalanceSquadrons*: bool        # Auto-optimize squadron composition (default: true)
    # NOTE: currentOrder stored in GameState.fleetOrders table to avoid circular dependency

    # Spy mission state (for Scout-only fleets)
    missionState*: FleetMissionState      # Spy mission state
    missionType*: Option[int]             # Type of active mission (SpyMissionType)
    missionTarget*: Option[SystemId]      # Target system for mission
    missionStartTurn*: int                # Turn mission began (for duration tracking)

proc newFleet*(squadrons: seq[Squadron] = @[],
               id: FleetId = "", owner: HouseId = "", location: SystemId = 0,
               status: FleetStatus = FleetStatus.Active,
               autoBalanceSquadrons: bool = true): Fleet =
  ## Create a new fleet with the given squadrons
  ## Supports all squadron types: Combat, Intel, Expansion, Auxiliary, Fighter
  Fleet(id: id, squadrons: squadrons,
        owner: owner, location: location, status: status,
        autoBalanceSquadrons: autoBalanceSquadrons,
        missionState: FleetMissionState.None,
        missionType: none(int),
        missionTarget: none(SystemId),
        missionStartTurn: 0)

proc `$`*(f: Fleet): string =
  ## String representation of a fleet
  if f.squadrons.len == 0:
    "Empty Fleet"
  else:
    var shipClasses: seq[string] = @[]
    for sq in f.squadrons:
      let status = if sq.flagship.isCrippled: "*" else: ""
      let typeTag = case sq.squadronType
        of SquadronType.Expansion: "[E]"
        of SquadronType.Auxiliary: "[A]"
        of SquadronType.Intel: "[I]"
        of SquadronType.Fighter: "[F]"
        else: ""
      shipClasses.add($sq.flagship.shipClass & status & typeTag)
    "Fleet[" & $f.squadrons.len & " squadrons: " & shipClasses.join(", ") & "]"

proc len*(f: Fleet): int =
  ## Get the number of squadrons in the fleet
  f.squadrons.len

proc isEmpty*(f: Fleet): bool =
  ## Check if the fleet has no squadrons
  f.squadrons.len == 0

proc hasIntelSquadrons*(f: Fleet): bool =
  ## Check if fleet has any Intel squadrons (Scouts)
  for sq in f.squadrons:
    if sq.squadronType == SquadronType.Intel:
      return true
  return false

proc hasNonIntelSquadrons*(f: Fleet): bool =
  ## Check if fleet has any non-Intel squadrons
  for sq in f.squadrons:
    if sq.squadronType != SquadronType.Intel:
      return true
  return false

proc canAddSquadron*(f: Fleet, squadron: Squadron): tuple[canAdd: bool, reason: string] =
  ## Check if a squadron can be added to this fleet
  ## RULE: Intel squadrons cannot be mixed with other squadron types

  if f.squadrons.len == 0:
    # Empty fleet - any squadron type can be added
    return (canAdd: true, reason: "")

  let isIntelSquadron = squadron.squadronType == SquadronType.Intel
  let fleetHasIntel = f.hasIntelSquadrons()
  let fleetHasNonIntel = f.hasNonIntelSquadrons()

  if isIntelSquadron and fleetHasNonIntel:
    return (canAdd: false, reason: "Cannot add Intel squadron to fleet with non-Intel squadrons")

  if not isIntelSquadron and fleetHasIntel:
    return (canAdd: false, reason: "Cannot add non-Intel squadron to Intel-only fleet")

  return (canAdd: true, reason: "")

proc add*(f: var Fleet, squadron: Squadron) =
  ## Add a squadron to the fleet
  ## Validates that Intel squadrons are not mixed with other types
  let validation = f.canAddSquadron(squadron)
  if not validation.canAdd:
    raise newException(ValueError,
      "Fleet composition violation: " & validation.reason &
      " (fleet: " & f.id & ", squadron: " & $squadron.flagship.shipClass & ")")

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
  ## Per operations.md:9 "Fleets containing crippled ships or Expansion/Auxiliary squadrons can not jump across restricted lanes"
  case laneType
  of LaneType.Restricted:
    # Check for crippled squadrons
    for sq in f.squadrons:
      if sq.flagship.isCrippled:
        return false

    # Check for Expansion/Auxiliary squadrons (ETAC, TroopTransport)
    for sq in f.squadrons:
      if sq.squadronType in {SquadronType.Expansion, SquadronType.Auxiliary}:
        return false  # Cannot cross restricted lanes with Expansion/Auxiliary squadrons

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
  ## Calculate the number of operational Expansion/Auxiliary squadrons
  result = 0
  for sq in f.squadrons:
    if sq.squadronType in {SquadronType.Expansion, SquadronType.Auxiliary}:
      if not sq.flagship.isCrippled:
        result += 1

proc hasCombatShips*(f: Fleet): bool =
  ## Check if the fleet has any combat-capable squadrons
  for sq in f.squadrons:
    if sq.combatStrength() > 0:
      return true
  return false

proc hasTransportShips*(f: Fleet): bool =
  ## Check if the fleet has any operational Expansion/Auxiliary squadrons
  for sq in f.squadrons:
    if sq.squadronType in {SquadronType.Expansion, SquadronType.Auxiliary}:
      if not sq.flagship.isCrippled:
        return true
  return false

proc isScoutOnly*(f: Fleet): bool =
  ## Check if fleet contains ONLY scout squadrons (no combat ships)
  ## Scouts are intelligence-only units that cannot join combat operations
  if f.squadrons.len == 0:
    return false
  for sq in f.squadrons:
    if sq.flagship.shipClass != ShipClass.Scout:
      return false
  return true

proc hasScouts*(f: Fleet): bool =
  ## Check if fleet contains any scout squadrons
  for sq in f.squadrons:
    if sq.flagship.shipClass == ShipClass.Scout:
      return true
  return false

proc countScoutSquadrons*(f: Fleet): int =
  ## Count number of scout squadrons in fleet
  ## Used for Scout-on-Scout detection formula
  result = 0
  for sq in f.squadrons:
    if sq.flagship.shipClass == ShipClass.Scout:
      result += 1

proc hasCombatSquadrons*(f: Fleet): bool =
  ## Check if fleet has any non-scout combat squadrons
  for sq in f.squadrons:
    if sq.flagship.shipClass != ShipClass.Scout:
      return true
  return false

proc canMergeWith*(f1: Fleet, f2: Fleet): tuple[canMerge: bool, reason: string] =
  ## Check if two fleets can merge (validates Intel/combat mixing)
  ## RULE: Intel squadrons cannot be mixed with other squadron types
  ## Intel fleets NEVER mix with anything (pure intelligence operations)
  ## Combat, Auxiliary, and Expansion can mix (combat escorts for transports)
  ## Fighters stay at colonies and don't join fleets

  let f1HasIntel = f1.hasIntelSquadrons()
  let f2HasIntel = f2.hasIntelSquadrons()
  let f1HasNonIntel = f1.hasNonIntelSquadrons()
  let f2HasNonIntel = f2.hasNonIntelSquadrons()

  # Intel squadrons cannot mix with non-Intel squadrons
  if (f1HasIntel and f2HasNonIntel) or (f1HasNonIntel and f2HasIntel):
    return (false, "Intel squadrons cannot be mixed with other squadron types")

  # Both fleets are compatible (either both Intel-only or both have no Intel)
  return (true, "")

proc combatSquadrons*(f: Fleet): seq[Squadron] =
  ## Get all combat-capable squadrons
  result = @[]
  for sq in f.squadrons:
    if sq.combatStrength() > 0:
      result.add(sq)

proc expansionSquadrons*(f: Fleet): seq[Squadron] =
  ## Get all Expansion squadrons (ETACs for colonization)
  result = @[]
  for sq in f.squadrons:
    if sq.squadronType == SquadronType.Expansion:
      result.add(sq)

proc auxiliarySquadrons*(f: Fleet): seq[Squadron] =
  ## Get all Auxiliary squadrons (TroopTransports for invasion)
  result = @[]
  for sq in f.squadrons:
    if sq.squadronType == SquadronType.Auxiliary:
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
  ## Merges all squadron types: Combat, Intel, Expansion, Auxiliary, Fighter
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
  var allEscorts: seq[Ship] = @[]
  for i in 0..<f.squadrons.len:
    allEscorts.add(f.squadrons[i].ships)
    f.squadrons[i].ships = @[]  # Clear escorts (keep flagship)

  if allEscorts.len == 0:
    return  # No escorts to balance

  # Step 2: Sort escorts by command cost (descending) for better bin packing
  # Larger ships first = better capacity utilization
  allEscorts.sort do (a, b: Ship) -> int:
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

# ============================================================================
# Fleet Management Command Support (for administrative ship reorganization)
# ============================================================================

proc getAllShips*(f: Fleet): seq[Ship] =
  ## Get flat list of all ships in fleet for player UI
  ## Order: squadron flagships + escorts for all squadron types
  ## Used by FleetManagementCommand to present ships to player
  ## Player selects ships by index in this list
  result = @[]

  # Add all squadron ships (flagship first, then escorts)
  # Includes all squadron types: Combat, Intel, Expansion, Auxiliary, Fighter
  for sq in f.squadrons:
    result.add(sq.flagship)
    for ship in sq.ships:
      result.add(ship)

proc translateShipIndicesToSquadrons*(f: Fleet, indices: seq[int]): seq[int] =
  ## Convert flat ship indices (from getAllShips()) to squadron indices
  ## Player selects ships by index, this translates to backend structure
  ##
  ## Note: Squadron index means "remove entire squadron"
  ## (flagship always moves with its escorts)
  ##
  ## Returns: Which squadrons to remove (by squadron index)

  var shipIndexToSquadron: seq[int] = @[]  # Maps ship index → squadron index

  # Build mapping: ship index → squadron index
  for sqIdx, sq in f.squadrons:
    shipIndexToSquadron.add(sqIdx)  # Flagship
    for _ in sq.ships:
      shipIndexToSquadron.add(sqIdx)  # Each escort

  # Track which squadrons have ANY ship selected
  var squadronsToRemove: seq[bool] = newSeq[bool](f.squadrons.len)

  # Process each selected ship index
  for idx in indices:
    if idx < shipIndexToSquadron.len:
      # Ship is in a squadron - mark entire squadron for removal
      let sqIdx = shipIndexToSquadron[idx]
      squadronsToRemove[sqIdx] = true

  # Build final squadron indices list
  result = @[]
  for sqIdx in 0..<f.squadrons.len:
    if squadronsToRemove[sqIdx]:
      result.add(sqIdx)
