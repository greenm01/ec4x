## World State Snapshot Creation
##
## Converts FilteredGameState (fog-of-war filtered) into WorldStateSnapshot
## for GOAP planning.
##
## Key Principles:
## - Respects fog-of-war (only uses FilteredGameState data)
## - Immutable snapshot (value type, no mutation)
## - Extracts planning-relevant data only

import std/[tables, options, sequtils, algorithm, strformat, strutils]
import ../../../../common/types/[core, tech]
import ../../../../engine/[fog_of_war, gamestate, fleet, logger] # Added logger for debug
import ../core/types
import ../../shared/intelligence_types # For IntelligenceSnapshot
import ../../config # For GOAPConfig

# =============================================================================
# Helper Functions
# =============================================================================

proc calculateColonyDefenseStrength(
  colony: Colony,
  filtered: FilteredGameState,
  houseId: HouseId # Add houseId to filter own fleets if needed
): int =
  ## Calculate defensive strength of colony.
  ## Includes: Ground forces (armies, marines), orbital defenses (starbases),
  ## and defending fleets (only own fleets).

  result = 0

  # Ground forces
  result += colony.armies
  result += colony.marines

  # Starbases (count operational starbases - each provides a base defense)
  for starbase in colony.starbases:
    if not starbase.isCrippled:
      result += 2 # Each operational starbase provides significant defense

  # Planetary shield (its level contributes to defense)
  result += colony.planetaryShieldLevel

  # Count defending *own* fleets at this system
  for fleet in filtered.ownFleets:
    if fleet.location == colony.systemId and fleet.owner == houseId:
      # Each combat-capable fleet provides some defense contribution
      if fleet.hasCombatShips:
        result += 1 # Simplified, could be more complex (e.g., based on fleet strength)

proc calculateFleetCombatStrength(fleet: Fleet): int =
  ## Calculates a simplified combat strength for a fleet.
  ## For GOAP, we want a quick heuristic. In-depth combat is for engine resolution.
  var strength = 0
  for squadron in fleet.squadrons:
    # A simple heuristic: heavier ships contribute more
    # Count flagship
    case squadron.flagship.shipClass
    of ShipClass.Fighter: strength += 1
    of ShipClass.Corvette, ShipClass.Frigate: strength += 2
    of ShipClass.Destroyer, ShipClass.Cruiser: strength += 4
    of ShipClass.Battleship, ShipClass.Dreadnought: strength += 8
    of ShipClass.Carrier: strength += 5 # Carriers have fighters, but less direct combat
    of ShipClass.TroopTransport: strength += 1 # Very little combat value
    else: discard

    # Count other ships in squadron
    for ship in squadron.ships:
      case ship.shipClass
      of ShipClass.Fighter: strength += 1
      of ShipClass.Corvette, ShipClass.Frigate: strength += 2
      of ShipClass.Destroyer, ShipClass.Cruiser: strength += 4
      of ShipClass.Battleship, ShipClass.Dreadnought: strength += 8
      of ShipClass.Carrier: strength += 5 # Carriers have fighters, but less direct combat
      of ShipClass.TroopTransport: strength += 1 # Very little combat value
      else: discard
  return strength

# =============================================================================
# Snapshot Creation
# =============================================================================

proc createWorldStateSnapshot*(
  filtered: FilteredGameState
): WorldStateSnapshot =
  ## Create immutable world state snapshot for GOAP planning.
  ## Converts FilteredGameState (fog-of-war filtered) → WorldStateSnapshot.
  ## Respects fog-of-war (only uses visible/known information).

  result = WorldStateSnapshot(
    turn: filtered.turn,
    houseId: filtered.viewingHouse
  )

  # --- Economic state (from own house) ---
  result.treasury = filtered.ownHouse.treasury
  result.production = filtered.ownColonies.mapIt(it.production).foldl(a + b, 0)
  result.maintenanceCost = 0  # TODO: Calculate from fleets and buildings
  result.netIncome = result.production - result.maintenanceCost

  # --- Military state ---
  var totalCER = 0
  var idleFleetIds: seq[FleetId] = @[]

  # Calculate total CER for own fleets
  for fleet in filtered.ownFleets:
    # Calculate simple combat strength
    totalCER += calculateFleetCombatStrength(fleet)

    # Check if fleet has orders
    if not filtered.ownFleetOrders.hasKey(fleet.id):
      idleFleetIds.add(fleet.id)

  result.totalFleetStrength = totalCER
  result.idleFleets = idleFleetIds

  # Fleets under threat - TODO: calculate from visible enemy fleets
  result.fleetsUnderThreat = @[]

  # --- Territory state ---
  result.ownedColonies = filtered.ownColonies.mapIt(it.systemId)
  # Note: homeworld parameter is not stored in WorldStateSnapshot (not part of type definition)

  # Vulnerable/undefended colonies - TODO: assess from local defenses
  result.vulnerableColonies = @[]
  result.undefendedColonies = @[]

  # --- Strategic intelligence (from visible assets) ---
  result.knownEnemyColonies = filtered.visibleColonies.mapIt((it.systemId, it.owner))
  result.invasionOpportunities = @[]  # TODO: analyze visible enemy colonies for weak ones
  result.undefendedEnemyColonies = @[]  # TODO: filter visible colonies by defense strength

  result.staleIntelSystems = @[]  # TODO: track stale intelligence
  result.espionageTargets = @[]  # TODO: identify espionage targets

  # --- Diplomatic relations ---
  result.diplomaticRelations = initTable[HouseId, DiplomaticState]()
  # Extract diplomatic relations for this house
  for key, dipState in filtered.houseDiplomacy:
    let (house1, house2) = key
    if house1 == filtered.viewingHouse:
      result.diplomaticRelations[house2] = dipState
    elif house2 == filtered.viewingHouse:
      result.diplomaticRelations[house1] = dipState

  # --- Tech state (from own house) ---
  # Convert TechLevel object → Table[TechField, int]
  # Note: EL and SL are NOT TechField enum values (they're separate research levels)
  result.techLevels = initTable[TechField, int]()
  let techLvl = filtered.ownHouse.techTree.levels
  result.techLevels[TechField.ConstructionTech] = techLvl.constructionTech
  result.techLevels[TechField.WeaponsTech] = techLvl.weaponsTech
  result.techLevels[TechField.TerraformingTech] = techLvl.terraformingTech
  result.techLevels[TechField.ElectronicIntelligence] = techLvl.electronicIntelligence
  result.techLevels[TechField.CloakingTech] = techLvl.cloakingTech
  result.techLevels[TechField.ShieldTech] = techLvl.shieldTech
  result.techLevels[TechField.CounterIntelligence] = techLvl.counterIntelligence
  result.techLevels[TechField.FighterDoctrine] = techLvl.fighterDoctrine
  result.techLevels[TechField.AdvancedCarrierOps] = techLvl.advancedCarrierOps

  # Extract TRP (technology research points) per field from ResearchPoints
  result.researchProgress = filtered.ownHouse.techTree.accumulated.technology
  result.criticalTechGaps = @[]  # TODO: identify tech gaps vs visible enemies

  # Note: totalColonies and totalIU fields don't exist in WorldStateSnapshot
  # Can be calculated from ownedColonies.len if needed

proc snapshotDelta*(before, after: WorldStateSnapshot): string =
  ## Calculate diff between two snapshots (for debugging)
  ## Returns human-readable description of changes.
  ## Only reports changes in key metrics to keep it concise.

  var changes = newSeq[string]()

  if after.treasury != before.treasury:
    changes.add(&"Treasury: {before.treasury} -> {after.treasury}")
  if after.totalFleetStrength != before.totalFleetStrength:
    changes.add(&"Fleet Strength: {before.totalFleetStrength} -> {after.totalFleetStrength}")
  if after.ownedColonies.len != before.ownedColonies.len:
    changes.add(&"Owned Colonies: {before.ownedColonies.len} -> {after.ownedColonies.len}")
  if after.idleFleets.len != before.idleFleets.len:
    changes.add(&"Idle Fleets: {before.idleFleets.len} -> {after.idleFleets.len}")
  if after.vulnerableColonies.len != before.vulnerableColonies.len:
    changes.add(&"Vulnerable Colonies: {before.vulnerableColonies.len} -> {after.vulnerableColonies.len}")
  if after.undefendedColonies.len != before.undefendedColonies.len:
    changes.add(&"Undefended Colonies: {before.undefendedColonies.len} -> {after.undefendedColonies.len}")
  if after.knownEnemyColonies.len != before.knownEnemyColonies.len:
    changes.add(&"Known Enemy Colonies: {before.knownEnemyColonies.len} -> {after.knownEnemyColonies.len}")
  if after.invasionOpportunities.len != before.invasionOpportunities.len:
    changes.add(&"Invasion Opportunities: {before.invasionOpportunities.len} -> {after.invasionOpportunities.len}")
  if after.staleIntelSystems.len != before.staleIntelSystems.len:
    changes.add(&"Stale Intel Systems: {before.staleIntelSystems.len} -> {after.staleIntelSystems.len}")
  if after.espionageTargets.len != before.espionageTargets.len:
    changes.add(&"Espionage Targets: {before.espionageTargets.len} -> {after.espionageTargets.len}")
  if after.criticalTechGaps.len != before.criticalTechGaps.len:
    changes.add(&"Critical Tech Gaps: {before.criticalTechGaps.len} -> {after.criticalTechGaps.len}")


  if changes.len > 0:
    result = "WorldStateSnapshot Changes:\n" & changes.join("\n")
  else:
    result = "No significant changes detected in WorldStateSnapshot."
