## World State Snapshot Creation
##
## Converts FilteredGameState (fog-of-war filtered) into WorldStateSnapshot
## for GOAP planning.
##
## Key Principles:
## - Respects fog-of-war (only uses FilteredGameState data)
## - Immutable snapshot (value type, no mutation)
## - Extracts planning-relevant data only

import std/[tables, options, sequtils]
import ../../../../common/types/[core, tech]
import ../../../../engine/fog_of_war
import ../../../../engine/gamestate
import ../../../../engine/fleet
import ../core/types
import ../../controller_types

# =============================================================================
# Helper Functions
# =============================================================================

proc calculateColonyDefenseStrength(colony: Colony, filtered: FilteredGameState): int =
  ## Calculate defensive strength of colony (Phase 1: simplified)
  ##
  ## Includes:
  ## - Ground forces (armies, marines)
  ## - Orbital defenses (starbases)
  ## - Defending fleets

  result = 0

  # Ground forces (these are int counts, not seqs)
  result += colony.armies
  result += colony.marines

  # Starbases (count operational starbases - each counts as 2 defense)
  for starbase in colony.starbases:
    if not starbase.isCrippled:
      result += 2  # Each operational starbase provides significant defense

  # Planetary shield
  result += colony.planetaryShieldLevel

  # Count defending fleets at this system
  for fleet in filtered.ownFleets:
    if fleet.location == colony.systemId:
      # Fleet defending this colony
      result += 1  # Each fleet counts as 1 defense unit

# =============================================================================
# Snapshot Creation
# =============================================================================

proc createWorldStateSnapshot*(
  filtered: FilteredGameState,
  intelSnapshot: IntelligenceSnapshot
): WorldStateSnapshot =
  ## Create immutable world state snapshot for GOAP planning
  ##
  ## Converts FilteredGameState → WorldStateSnapshot
  ## Respects fog-of-war (only uses visible information)

  result = WorldStateSnapshot(
    turn: filtered.turn,
    houseId: filtered.viewingHouse
  )

  # Economic state
  result.treasury = filtered.ownHouse.treasury

  # Calculate production from own colonies
  var totalProduction = 0
  for colony in filtered.ownColonies:
    totalProduction += colony.production
  result.production = totalProduction

  # Maintenance cost (Phase 1: simplified estimate)
  # TODO: Calculate from actual fleet/colony maintenance in Phase 2
  result.maintenanceCost = 0  # Placeholder
  result.netIncome = result.production - result.maintenanceCost

  # Military state
  var totalCER = 0
  var idleFleetIds: seq[FleetId] = @[]

  for fleet in filtered.ownFleets:
    # Sum fleet strength (Phase 1: simplified - count squadrons)
    # TODO: Calculate actual CER from squadron stats in Phase 2
    totalCER += fleet.squadrons.len

    # Identify idle fleets (no orders)
    if not filtered.ownFleetOrders.hasKey(fleet.id):
      idleFleetIds.add(fleet.id)

  result.totalFleetStrength = totalCER
  result.idleFleets = idleFleetIds

  # Fleets under threat (from intel snapshot)
  result.fleetsUnderThreat = @[]  # TODO: Extract from threat analysis

  # Territory state
  result.ownedColonies = filtered.ownColonies.mapIt(it.systemId)

  # Vulnerable colonies (high production, weak defense)
  var vulnerableSystems: seq[SystemId] = @[]
  var undefendedSystems: seq[SystemId] = @[]

  for colony in filtered.ownColonies:
    let defenseStrength = calculateColonyDefenseStrength(colony, filtered)

    if defenseStrength == 0:
      undefendedSystems.add(colony.systemId)
    elif colony.production >= 30 and defenseStrength < 3:
      # High-value but weak
      vulnerableSystems.add(colony.systemId)

  result.vulnerableColonies = vulnerableSystems
  result.undefendedColonies = undefendedSystems

  # Strategic intelligence (from intel snapshot)
  result.knownEnemyColonies = intelSnapshot.knownEnemyColonies
  result.invasionOpportunities = intelSnapshot.highValueTargets  # Weak enemy colonies
  result.staleIntelSystems = intelSnapshot.staleIntelSystems
  result.espionageTargets = intelSnapshot.espionageOpportunities

  # Diplomatic relations (Phase 1: simplified)
  # TODO: Extract from FilteredGameState in Phase 2
  result.diplomaticRelations = initTable[HouseId, DiplomaticState]()

  # Tech state (Phase 1: placeholder - proper extraction in Phase 2 with TechTree access)
  # TODO: Implement TechTree → Table[TechField, int] conversion when implementing Research domain
  result.techLevels = initTable[TechField, int]()
  result.researchProgress = initTable[TechField, int]()
  result.criticalTechGaps = @[]

# =============================================================================
# Snapshot Updates (For Planning Simulation)
# =============================================================================

proc simulateAction*(state: WorldStateSnapshot, action: Action): WorldStateSnapshot =
  ## Simulate executing an action on world state
  ##
  ## Returns new state with action effects applied
  ## Used by A* planner to explore state space
  ##
  ## NOTE: This is a SHALLOW simulation for planning only
  ## Real execution happens through RBA orders

  result = state  # Copy current state

  # Update treasury
  result.treasury -= action.cost

  # Update turn (if action takes time)
  if action.duration > 0:
    result.turn += action.duration

  # Apply domain-specific effects
  case action.actionType
  of ActionType.ConstructShips:
    # Reduce treasury (already done above)
    # NOTE: Don't update fleet strength (too complex to simulate)
    discard

  of ActionType.BuildFacility:
    # Construction happens over time
    discard

  of ActionType.AllocateResearch:
    # Update research progress
    if action.techField.isSome:
      let field = action.techField.get()
      let currentProgress = result.researchProgress.getOrDefault(field, 0)
      result.researchProgress[field] = currentProgress + action.cost

  of ActionType.MoveFleet:
    # Fleet movement
    # NOTE: Too complex to simulate fleet positions accurately
    discard

  else:
    # Other actions don't affect planning-relevant state
    discard

proc snapshotDelta*(before, after: WorldStateSnapshot): string =
  ## Calculate diff between two snapshots (for debugging)
  ##
  ## Returns human-readable description of changes

  result = ""

  if after.treasury != before.treasury:
    result.add($"Treasury: " & $before.treasury & " → " & $after.treasury & "\n")

  if after.totalFleetStrength != before.totalFleetStrength:
    result.add($"Fleet Strength: " & $before.totalFleetStrength & " → " & $after.totalFleetStrength & "\n")

  if after.ownedColonies.len != before.ownedColonies.len:
    result.add($"Colonies: " & $before.ownedColonies.len & " → " & $after.ownedColonies.len & "\n")
