## World State Snapshot Creation
##
## Converts FilteredGameState (fog-of-war filtered) into WorldStateSnapshot
## for GOAP planning.
##
## Key Principles:
## - Respects fog-of-war (only uses FilteredGameState data)
## - Immutable snapshot (value type, no mutation)
## - Extracts planning-relevant data only

import std/[tables, options, sequtils, algorithm]
import ../../../../common/types/[core, tech]
import ../../../../engine/[fog_of_war, gamestate, fleet, logger] # Added logger for debug
import ../core/types
import ../../controller_types # For IntelligenceSnapshot and related types
import ../config # For GOAPConfig

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
    for ship in squadron.allShips:
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
  houseId: HouseId, # The AI's house ID
  homeworld: SystemId, # The AI's homeworld system ID
  currentTurn: int,
  config: GOAPConfig, # GOAP configuration (for planning depth, etc.)
  intelSnapshot: IntelligenceSnapshot # Comprehensive intelligence from Drungarius
): WorldStateSnapshot =
  ## Create immutable world state snapshot for GOAP planning.
  ## Converts FilteredGameState (from intelSnapshot) → WorldStateSnapshot.
  ## Respects fog-of-war (only uses visible/known information).

  result = WorldStateSnapshot(
    turn: currentTurn,
    houseId: houseId
  )

  # --- Economic state ---
  result.treasury = intelSnapshot.economy.currentTreasury
  result.production = intelSnapshot.economy.totalProduction
  result.maintenanceCost = intelSnapshot.economy.totalMaintenanceCost
  result.netIncome = intelSnapshot.economy.netIncome

  # --- Military state ---
  var totalCER = 0
  var idleFleetIds: seq[FleetId] = @[]
  result.fleetsAtSystem = initTable[SystemId, seq[FleetIntel]]() # Initialize table

  # Populate fleetsAtSystem and calculate total CER for own fleets
  for fleet in intelSnapshot.military.ownFleets:
    # Use the engine's actual combat strength for GOAP's world state
    totalCER += fleet.combatStrength() 
    if not intelSnapshot.military.ownFleetOrders.hasKey(fleet.fleetId):
      idleFleetIds.add(fleet.fleetId)
    
    # Add to fleetsAtSystem for later use (e.g. for eliminate fleet goal validation)
    if not result.fleetsAtSystem.hasKey(fleet.location):
      result.fleetsAtSystem[fleet.location] = @[]
    result.fleetsAtSystem[fleet.location].add(fleet)

  # Add known enemy fleets to fleetsAtSystem
  for fleet in intelSnapshot.military.enemyFleets:
    if not result.fleetsAtSystem.hasKey(fleet.location):
      result.fleetsAtSystem[fleet.location] = @[]
    result.fleetsAtSystem[fleet.location].add(fleet)

  result.totalFleetStrength = totalCER
  result.idleFleets = idleFleetIds

  # Fleets under threat (from intel snapshot's threat assessment)
  result.fleetsUnderThreat = intelSnapshot.military.fleetsUnderThreat.mapIt((it.fleetId, it.threatLevel.int))

  # --- Territory state ---
  result.ownedColonies = intelSnapshot.economy.ownedColonies.mapIt(it.systemId)
  result.homeworld = homeworld

  # Vulnerable/undefended colonies (from intel snapshot's threat assessment)
  result.vulnerableColonies = intelSnapshot.military.vulnerableColonies
  result.undefendedColonies = intelSnapshot.military.undefendedColonies
  
  # --- Strategic intelligence ---
  result.knownEnemyColonies = intelSnapshot.knownEnemyColonies
  result.invasionOpportunities = intelSnapshot.military.invasionOpportunities.mapIt(it.systemId)
  result.staleIntelSystems = intelSnapshot.intelligence.staleIntelSystems
  result.espionageTargets = intelSnapshot.espionage.highPriorityTargets.mapIt(it.targetHouse.getOrDefault(0.HouseId)) # Map to HouseId if targetHouse exists

  # --- Diplomatic relations ---
  result.diplomaticRelations = intelSnapshot.diplomacy.diplomaticRelations

  # --- Tech state ---
  # Populate tech levels from the intelligence snapshot
  for field, level in intelSnapshot.research.techLevels:
    result.techLevels[field] = level
  for field, rp in intelSnapshot.research.researchProgress:
    result.researchProgress[field] = rp
  result.criticalTechGaps = intelSnapshot.research.criticalTechGaps

  # Other important strategic values
  result.totalColonies = result.ownedColonies.len
  result.totalIU = intelSnapshot.economy.totalIndustrialUnits

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
  if after.totalColonies != before.totalColonies:
    changes.add(&"Total Colonies: {before.totalColonies} -> {after.totalColonies}")
  if after.totalIU != before.totalIU:
    changes.add(&"Total IU: {before.totalIU} -> {after.totalIU}")
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
