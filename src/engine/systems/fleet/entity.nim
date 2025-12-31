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

import ../squadron/entity as squadron
import ../ship/entity as ship_entity # Ship helper functions
import ../../types/[core, fleet, ship, squadron as squadron_types, combat, starmap]
import ../../state/entity_manager # For getEntity()
import std/[algorithm, strutils, options]

export FleetId, SystemId, HouseId, LaneClass, FleetMissionState
export Squadron, Ship, ShipClass # Export for fleet users
export
  SquadronClass, ShipCargo, CargoClass # Export squadron classification and cargo types

proc newFleet*(
    squadronIds: seq[SquadronId] = @[],
    id: FleetId = FleetId(0),
    owner: HouseId = HouseId(0),
    location: SystemId = SystemId(0),
    status: FleetStatus = FleetStatus.Active,
    autoBalanceSquadrons: bool = true,
): Fleet =
  ## Create a new fleet with the given squadron IDs
  ## Supports all squadron types: Combat, Intel, Expansion, Auxiliary, Fighter
  Fleet(
    id: id,
    squadrons: squadronIds,
    houseId: owner,
    location: location,
    status: status,
    autoBalanceSquadrons: autoBalanceSquadrons,
    missionState: FleetMissionState.None,
    missionType: none(int32),
    missionTarget: none(SystemId),
    missionStartTurn: 0,
  )

proc `$`*(f: Fleet, squadrons: Squadrons, ships: Ships): string =
  ## String representation of a fleet
  if f.squadrons.len == 0:
    "Empty Fleet"
  else:
    var shipClasses: seq[string] = @[]
    for sqId in f.squadrons:
      let sq = squadrons.entities.getEntity(sqId).get
      let flagship = ships.entities.getEntity(sq.flagshipId).get
      let status = if flagship.isCrippled: "*" else: ""
      let typeTag =
        case sq.squadronType
        of SquadronClass.Expansion: "[E]"
        of SquadronClass.Auxiliary: "[A]"
        of SquadronClass.Intel: "[I]"
        of SquadronClass.Fighter: "[F]"
        else: ""
      shipClasses.add($flagship.shipClass & status & typeTag)
    "Fleet[" & $f.squadrons.len & " squadrons: " & shipClasses.join(", ") & "]"

proc len*(f: Fleet): int =
  ## Get the number of squadrons in the fleet
  f.squadrons.len

proc isEmpty*(f: Fleet): bool =
  ## Check if the fleet has no squadrons
  f.squadrons.len == 0

proc hasIntelSquadrons*(f: Fleet, squadrons: Squadrons): bool =
  ## Check if fleet has any Intel squadrons (Scouts)
  for sqId in f.squadrons:
    let sq = squadrons.entities.getEntity(sqId).get
    if sq.squadronType == SquadronClass.Intel:
      return true
  return false

proc hasNonIntelSquadrons*(f: Fleet, squadrons: Squadrons): bool =
  ## Check if fleet has any non-Intel squadrons
  for sqId in f.squadrons:
    let sq = squadrons.entities.getEntity(sqId).get
    if sq.squadronType != SquadronClass.Intel:
      return true
  return false

proc canAddSquadron*(
    f: Fleet, squadron: Squadron, squadrons: Squadrons
): tuple[canAdd: bool, reason: string] =
  ## Check if a squadron can be added to this fleet
  ## RULE: Intel squadrons cannot be mixed with other squadron types

  if f.squadrons.len == 0:
    # Empty fleet - any squadron type can be added
    return (canAdd: true, reason: "")

  let isIntelSquadron = squadron.squadronType == SquadronClass.Intel
  let fleetHasIntel = f.hasIntelSquadrons(squadrons)
  let fleetHasNonIntel = f.hasNonIntelSquadrons(squadrons)

  if isIntelSquadron and fleetHasNonIntel:
    return (
      canAdd: false,
      reason: "Cannot add Intel squadron to fleet with non-Intel squadrons",
    )

  if not isIntelSquadron and fleetHasIntel:
    return (canAdd: false, reason: "Cannot add non-Intel squadron to Intel-only fleet")

  return (canAdd: true, reason: "")

proc add*(f: var Fleet, squadron: Squadron, squadrons: Squadrons) =
  ## Add a squadron to the fleet
  ## Validates that Intel squadrons are not mixed with other types
  let validation = f.canAddSquadron(squadron, squadrons)
  if not validation.canAdd:
    raise newException(
      ValueError,
      "Fleet composition violation: " & validation.reason & " (fleet: " & $f.id &
        ", squadron: " & $squadron.id & ")",
    )

  f.squadrons.add(squadron.id)

proc remove*(f: var Fleet, index: int) =
  ## Remove a squadron at the given index
  if index >= 0 and index < f.squadrons.len:
    f.squadrons.delete(index)

proc clear*(f: var Fleet) =
  ## Remove all squadrons from the fleet
  f.squadrons.setLen(0)

proc canTraverse*(
    f: Fleet, laneType: LaneClass, squadrons: Squadrons, ships: Ships
): bool =
  ## Check if the fleet can traverse a specific type of jump lane
  ## Per operations.md:9 "Fleets containing crippled ships or Expansion/Auxiliary squadrons can not jump across restricted lanes"
  case laneType
  of LaneClass.Restricted:
    # Check for crippled squadrons
    for sqId in f.squadrons:
      let sq = squadrons.entities.getEntity(sqId).get
      let flagship = ships.entities.getEntity(sq.flagshipId).get
      if flagship.isCrippled:
        return false

    # Check for Expansion/Auxiliary squadrons (ETAC, TroopTransport)
    for sqId in f.squadrons:
      let sq = squadrons.entities.getEntity(sqId).get
      if sq.squadronType in {SquadronClass.Expansion, SquadronClass.Auxiliary}:
        return false # Cannot cross restricted lanes with Expansion/Auxiliary squadrons

    return true
  else:
    # Major and Minor lanes can be traversed by any fleet
    true

proc combatStrength*(f: Fleet, squadrons: Squadrons, ships: Ships): int =
  ## Calculate the total attack strength of the fleet
  result = 0
  for sqId in f.squadrons:
    let sq = squadrons.entities.getEntity(sqId).get
    result += sq.combatStrength(ships)

proc isCloaked*(f: Fleet, squadrons: Squadrons, ships: Ships): bool =
  ## Check if fleet is cloaked
  ## Per assets.md:2.4.3: "Fleets that include Raiders are fully cloaked"
  ## Returns true if fleet has ANY non-crippled raiders
  if f.squadrons.len == 0:
    return false

  # Check if fleet has any operational raiders
  for sqId in f.squadrons:
    let sq = squadrons.entities.getEntity(sqId).get
    let raiderIds = sq.raiderShips(ships)
    for raiderId in raiderIds:
      let raider = ships.entities.getEntity(raiderId).get
      if not raider.isCrippled:
        return true # Fleet is cloaked if it has ANY operational raider

  return false

proc transportCapacity*(f: Fleet, squadrons: Squadrons, ships: Ships): int =
  ## Calculate the number of operational Expansion/Auxiliary squadrons
  result = 0
  for sqId in f.squadrons:
    let sq = squadrons.entities.getEntity(sqId).get
    if sq.squadronType in {SquadronClass.Expansion, SquadronClass.Auxiliary}:
      let flagship = ships.entities.getEntity(sq.flagshipId).get
      if not flagship.isCrippled:
        result += 1

proc hasCombatShips*(f: Fleet, squadrons: Squadrons, ships: Ships): bool =
  ## Check if the fleet has any combat-capable squadrons
  for sqId in f.squadrons:
    let sq = squadrons.entities.getEntity(sqId).get
    if sq.combatStrength(ships) > 0:
      return true
  return false

proc hasTransportShips*(f: Fleet, squadrons: Squadrons, ships: Ships): bool =
  ## Check if the fleet has any operational Expansion/Auxiliary squadrons
  for sqId in f.squadrons:
    let sq = squadrons.entities.getEntity(sqId).get
    if sq.squadronType in {SquadronClass.Expansion, SquadronClass.Auxiliary}:
      let flagship = ships.entities.getEntity(sq.flagshipId).get
      if not flagship.isCrippled:
        return true
  return false

proc isScoutOnly*(f: Fleet, squadrons: Squadrons, ships: Ships): bool =
  ## Check if fleet contains ONLY scout squadrons (no combat ships)
  ## Scouts are intelligence-only units that cannot join combat operations
  if f.squadrons.len == 0:
    return false
  for sqId in f.squadrons:
    let sq = squadrons.entities.getEntity(sqId).get
    let flagship = ships.entities.getEntity(sq.flagshipId).get
    if flagship.shipClass != ShipClass.Scout:
      return false
  return true

proc hasScouts*(f: Fleet, squadrons: Squadrons, ships: Ships): bool =
  ## Check if fleet contains any scout squadrons
  for sqId in f.squadrons:
    let sq = squadrons.entities.getEntity(sqId).get
    let flagship = ships.entities.getEntity(sq.flagshipId).get
    if flagship.shipClass == ShipClass.Scout:
      return true
  return false

proc countScoutSquadrons*(f: Fleet, squadrons: Squadrons, ships: Ships): int =
  ## Count number of scout squadrons in fleet
  ## Used for Scout-on-Scout detection formula
  result = 0
  for sqId in f.squadrons:
    let sq = squadrons.entities.getEntity(sqId).get
    let flagship = ships.entities.getEntity(sq.flagshipId).get
    if flagship.shipClass == ShipClass.Scout:
      result += 1

proc hasCombatSquadrons*(f: Fleet, squadrons: Squadrons, ships: Ships): bool =
  ## Check if fleet has any non-scout combat squadrons
  for sqId in f.squadrons:
    let sq = squadrons.entities.getEntity(sqId).get
    let flagship = ships.entities.getEntity(sq.flagshipId).get
    if flagship.shipClass != ShipClass.Scout:
      return true
  return false

proc canMergeWith*(
    f1: Fleet, f2: Fleet, squadrons: Squadrons
): tuple[canMerge: bool, reason: string] =
  ## Check if two fleets can merge (validates Intel/combat mixing)
  ## RULE: Intel squadrons cannot be mixed with other squadron types
  ## Intel fleets NEVER mix with anything (pure intelligence operations)
  ## Combat, Auxiliary, and Expansion can mix (combat escorts for transports)
  ## Fighters stay at colonies and don't join fleets

  let f1HasIntel = f1.hasIntelSquadrons(squadrons)
  let f2HasIntel = f2.hasIntelSquadrons(squadrons)
  let f1HasNonIntel = f1.hasNonIntelSquadrons(squadrons)
  let f2HasNonIntel = f2.hasNonIntelSquadrons(squadrons)

  # Intel squadrons cannot mix with non-Intel squadrons
  if (f1HasIntel and f2HasNonIntel) or (f1HasNonIntel and f2HasIntel):
    return (false, "Intel squadrons cannot be mixed with other squadron types")

  # Both fleets are compatible (either both Intel-only or both have no Intel)
  return (true, "")

proc combatSquadrons*(f: Fleet, squadrons: Squadrons, ships: Ships): seq[SquadronId] =
  ## Get all combat-capable squadron IDs
  result = @[]
  for sqId in f.squadrons:
    let sq = squadrons.entities.getEntity(sqId).get
    if sq.combatStrength(ships) > 0:
      result.add(sqId)

proc expansionSquadrons*(f: Fleet, squadrons: Squadrons): seq[SquadronId] =
  ## Get all Expansion squadron IDs (ETACs for colonization)
  result = @[]
  for sqId in f.squadrons:
    let sq = squadrons.entities.getEntity(sqId).get
    if sq.squadronType == SquadronClass.Expansion:
      result.add(sqId)

proc auxiliarySquadrons*(f: Fleet, squadrons: Squadrons): seq[SquadronId] =
  ## Get all Auxiliary squadron IDs (TroopTransports for invasion)
  result = @[]
  for sqId in f.squadrons:
    let sq = squadrons.entities.getEntity(sqId).get
    if sq.squadronType == SquadronClass.Auxiliary:
      result.add(sqId)

proc crippledSquadrons*(f: Fleet, squadrons: Squadrons, ships: Ships): seq[SquadronId] =
  ## Get all squadron IDs with crippled flagships
  result = @[]
  for sqId in f.squadrons:
    let sq = squadrons.entities.getEntity(sqId).get
    let flagship = ships.entities.getEntity(sq.flagshipId).get
    if flagship.isCrippled:
      result.add(sqId)

proc effectiveSquadrons*(
    f: Fleet, squadrons: Squadrons, ships: Ships
): seq[SquadronId] =
  ## Get all squadron IDs with non-crippled flagships
  result = @[]
  for sqId in f.squadrons:
    let sq = squadrons.entities.getEntity(sqId).get
    let flagship = ships.entities.getEntity(sq.flagshipId).get
    if not flagship.isCrippled:
      result.add(sqId)

proc merge*(f1: var Fleet, f2: Fleet) =
  ## Merge another fleet into this one
  ## Merges all squadron types: Combat, Intel, Expansion, Auxiliary, Fighter
  f1.squadrons.add(f2.squadrons)

proc split*(f: var Fleet, indices: seq[int]): Fleet =
  ## Split off squadrons at the given indices into a new fleet
  var newSquadronIds: seq[SquadronId] = @[]
  var toRemove: seq[int] = @[]

  for i in indices:
    if i >= 0 and i < f.squadrons.len:
      newSquadronIds.add(f.squadrons[i])
      toRemove.add(i)

  # Remove squadrons from original fleet (in reverse order to maintain indices)
  for i in toRemove.sorted(Descending):
    f.squadrons.delete(i)

  newFleet(newSquadronIds)

## TODO: balanceSquadrons needs to be refactored for DoD
## This proc mutates squadron internal structure (redistributing escort ships).
## In DoD architecture, this belongs in:
## - entities/squadron_ops.nim (handles squadron mutations + index maintenance)
## - OR: systems/fleet/engine.nim with GameState access
##
## The proc needs mutable access to Squadrons and Ships entity managers,
## and should use updateEntity() to commit changes. This is complex domain
## logic that requires careful handling of the entity graph.
##
## Signature should be:
## proc balanceFleetSquadrons*(state: var GameState, fleetId: FleetId)
##
# proc balanceSquadrons*(f: var Fleet) =
#   ## DEPRECATED - needs DoD refactoring
#   discard

# ============================================================================
# Fleet Management Command Support (for administrative ship reorganization)
# ============================================================================

proc getAllShips*(f: Fleet, squadrons: Squadrons, ships: Ships): seq[Ship] =
  ## Get flat list of all ships in fleet for player UI
  ## Order: squadron flagships + escorts for all squadron types
  ## Used by FleetManagementCommand to present ships to player
  ## Player selects ships by index in this list
  result = @[]

  # Add all squadron ships (flagship first, then escorts)
  # Includes all squadron types: Combat, Intel, Expansion, Auxiliary, Fighter
  for sqId in f.squadrons:
    let sq = squadrons.entities.getEntity(sqId).get
    let flagship = ships.entities.getEntity(sq.flagshipId).get
    result.add(flagship)
    for shipId in sq.ships:
      let ship = ships.entities.getEntity(shipId).get
      result.add(ship)

proc translateShipIndicesToSquadrons*(
    f: Fleet, squadrons: Squadrons, indices: seq[int]
): seq[int] =
  ## Convert flat ship indices (from getAllShips()) to squadron indices
  ## Player selects ships by index, this translates to backend structure
  ##
  ## Note: Squadron index means "remove entire squadron"
  ## (flagship always moves with its escorts)
  ##
  ## Returns: Which squadrons to remove (by squadron index)

  var shipIndexToSquadron: seq[int] = @[] # Maps ship index → squadron index

  # Build mapping: ship index → squadron index
  for sqIdx in 0 ..< f.squadrons.len:
    let sqId = f.squadrons[sqIdx]
    let sq = squadrons.entities.getEntity(sqId).get
    shipIndexToSquadron.add(sqIdx) # Flagship
    for _ in sq.ships:
      shipIndexToSquadron.add(sqIdx) # Each escort

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
  for sqIdx in 0 ..< f.squadrons.len:
    if squadronsToRemove[sqIdx]:
      result.add(sqIdx)
