## Conflict Phase Resolution - Phase 1 of Canonical Turn Cycle
##
## Per docs/engine/ec4x_canonical_turn_cycle.md:
##
## CON1: Combat Resolution
##   1a-1d: Theater progression (Space → Orbital → Blockade → Planetary)
##   1e: Colonization
##   1f: Scout Intelligence Operations
##   1g: Administrative Completion
##
## CON2: Immediate Combat Effects (handled per-system by combat engine)
##   2a: Remove destroyed entities
##   2b-2c: Clear destroyed/crippled Neoria queues
##   2d: Colony conquest effects
##   2e: Severe bombardment effects
##
## **Architecture Compliance** (per src/engine/architecture.md):
## - Uses state layer APIs (UFCS pattern)
## - Uses iterators for batch access
## - Delegates to specialized modules (no duplicated logic)
## - Uses common/logger for logging

import std/[options, random, tables]
import ../types/core
import ../../common/logger
import ../types/game_state
import ../types/[command, event, combat]
import ../state/[engine, iterators]
import ../systems/combat/engine
import ../systems/combat/multi_house  # For buildMultiHouseBattle (UFCS)
import ../systems/espionage/resolution
import ../systems/colony/colonization
import ../systems/fleet/execution
import ../intel/starbase_surveillance

# =============================================================================
# HELPER PROCS
# =============================================================================

proc identifyCombatSystems(
    state: GameState,
    rng: var Rand,
    events: var seq[event.GameEvent]
): seq[SystemId] =
  ## Identify all systems where combat should occur
  ## Delegates to multi_house.buildMultiHouseBattle() for diplomatic checks
  ## Per docs/engine/ec4x_canonical_turn_cycle.md Combat Participant Determination
  ##
  ## Uses the same logic as the combat system to ensure consistency:
  ## - Checks diplomatic status between houses
  ## - Evaluates threat levels of fleet commands
  ## - Handles diplomatic escalation (Neutral → Hostile → Enemy)
  ##
  ## Returns list of SystemIds where combat will occur

  result = @[]

  # Collect all systems with at least one fleet
  var systemsWithFleets: seq[SystemId] = @[]
  for (systemId, _) in state.allSystemsWithId():
    var hasFleets = false
    for _ in state.fleetsInSystem(systemId):
      hasFleets = true
      break
    if hasFleets:
      systemsWithFleets.add(systemId)

  # Check each system for combat eligibility using multi_house logic
  for systemId in systemsWithFleets:
    # buildMultiHouseBattle returns Some only if combat should occur
    # It handles all diplomatic checks, threat levels, and escalation
    let battleOpt = state.buildMultiHouseBattle(systemId, rng, events)
    if battleOpt.isSome:
      result.add(systemId)
      logDebug("Combat", "Combat identified",
        " system=", systemId, " participants=", battleOpt.get().participants.len)

  logInfo("Combat", "Combat systems identified", " count=", result.len)

# =============================================================================
# MAIN ENTRY POINT
# =============================================================================

proc resolveConflictPhase*(
    state: GameState,
    commands: Table[HouseId, command.CommandPacket],
    combatResults: var seq[CombatResult],
    events: var seq[event.GameEvent],
    rng: var Rand,
) =
  ## Phase 1: Resolve all combat, colonization, and intelligence operations
  ##
  ## Per docs/engine/ec4x_canonical_turn_cycle.md:
  ## - Commands submitted Turn N-1 execute Turn N
  ## - Fleets with missionState == Executing have arrived at targets
  ## - No merge step needed - commands stored in Fleet.command field
  ##
  ## Execution Order:
  ## - CON1a-1d: Combat Resolution (Space → Orbital → Blockade → Planetary)
  ## - CON1e: Colonization
  ## - CON1f: Scout Intelligence Operations
  ## - CON1g: Administrative Completion
  ## - CON2: Immediate Combat Effects (handled per-system by combat engine)

  logInfo("Conflict", "=== Conflict Phase ===", " turn=", state.turn)

  # ===================================================================
  # CON1a-1d: COMBAT RESOLUTION
  # ===================================================================
  # Identify systems where combat should occur
  # Uses multi_house.buildMultiHouseBattle() for consistent diplomatic checks
  let combatSystems = state.identifyCombatSystems(rng, events)

  logInfo("Combat", "[CON1a-1d] Resolving combat theaters",
    " systems=", combatSystems.len)

  # Resolve combat in each system with theater progression enforcement
  # Space → Orbital → Blockade → Planetary (single entry point pattern)
  # CON2 (Immediate Combat Effects) handled per-system by combat engine
  for systemId in combatSystems:
    let results = state.resolveSystemCombat(systemId, events, rng)
    combatResults.add(results)

  logInfo("Combat", "[CON1a-1d] Combat resolution complete",
    " battles=", combatResults.len)

  # ===================================================================
  # CON1e: COLONIZATION
  # ===================================================================
  # ETACs establish colonies, resolve conflicts (winner-takes-all)
  # Fallback logic for losers (fleet holds position)
  # Per docs/engine/ec4x_canonical_turn_cycle.md Section CON1e
  logInfo("Colony", "[CON1e] Resolving colonization attempts...")

  let colonizationResults = state.resolveColonization(rng, events)

  logInfo("Colony", "[CON1e] Colonization complete",
    " attempts=", colonizationResults.len)

  # ===================================================================
  # CON1f: SCOUT INTELLIGENCE OPERATIONS
  # ===================================================================
  # Per docs/engine/ec4x_canonical_turn_cycle.md Section CON1f

  # CON1f.i-ii: Fleet-Based Scout Missions (new + persistent)
  # - New missions: Executing → ScoutLocked, first detection check
  # - Persistent missions: Detection checks for missions from previous turns
  logInfo("Espionage", "[CON1f.i-ii] Scout missions...")
  state.resolveScoutMissions(rng, events)
  logInfo("Espionage", "[CON1f.i-ii] Scout missions complete")

  # CON1f.iii: Space Guild Espionage (EBP-based covert ops)
  # Tech Theft, Sabotage, Assassination, Cyber Attack, etc.
  logInfo("Espionage", "[CON1f.iii] Space Guild espionage (EBP-based)...")
  state.processEspionageActions(commands, rng, events)
  logInfo("Espionage", "[CON1f.iii] Space Guild espionage complete")

  # CON1f.iv: Starbase Surveillance (continuous monitoring)
  # Automatic intelligence gathering from friendly starbases
  # No player action required (passive system)
  # Per docs/specs/09-intel-espionage.md Section 9.1.4
  logInfo("Espionage", "[CON1f.iv] Starbase surveillance...")
  var survRng = initRand(state.turn.int64 + 12345)
  state.processStarbaseSurveillance(state.turn, survRng)
  logInfo("Espionage", "[CON1f.iv] Starbase surveillance complete")

  # ===================================================================
  # CON1g: ADMINISTRATIVE COMPLETION
  # ===================================================================
  # Mark Conflict Phase commands complete after their effects resolved
  # Per docs/engine/ec4x_canonical_turn_cycle.md Section CON1g
  #
  # Commands completed:
  # - Combat: Patrol, GuardStarbase, GuardColony, Blockade, Bombard, Invade, Blitz
  # - Colonization: Colonize
  # - Scout Intelligence: ScoutColony, ScoutSystem, HackStarbase
  #
  # Key: This is NOT command execution - effects already happened in CON1a-1f
  # This step marks commands complete and cleans up their lifecycle
  logInfo("Conflict", "[CON1g] Administrative completion...")

  performCommandMaintenance(
    state, commands, events, rng,
    isConflictCommand,
    "Conflict Phase CON1g"
  )

  logInfo("Conflict", "[CON1g] Administrative completion done")

  # ===================================================================
  # CON2: IMMEDIATE COMBAT EFFECTS
  # ===================================================================
  # Per docs/engine/ec4x_canonical_turn_cycle.md Section CON2
  #
  # CON2 is handled PER-SYSTEM by state.resolveSystemCombat():
  # - 2a: Remove destroyed entities (ships, neorias, kastras, ground units)
  # - 2b: Clear destroyed Neoria queues
  # - 2c: Clear crippled Neoria queues
  # - 2d: Process colony conquest effects
  # - 2e: Process severe bombardment effects (>50% infrastructure)
  #
  # This ensures combat effects apply immediately after each system's combat,
  # not batched at the end (prevents stale state during multi-system combat)
  logInfo("Conflict", "[CON2] Immediate combat effects applied per-system")

  logInfo("Conflict", "=== Conflict Phase Complete ===")

## Design Notes:
##
## **Architecture Compliance:**
## - Uses iterator pattern for fleet access
## - Delegates to specialized modules (no duplicated logic)
## - UFCS style throughout
## - Uses common/logger (not echo)
##
## **Combat Participant Determination:**
## - Delegates to multi_house.buildMultiHouseBattle() for consistency
## - No duplicated diplomatic/threat level logic
## - Handles escalation automatically (Neutral → Hostile → Enemy)
##
## **Immediate Combat Effects (CON2):**
## - Handled per-system by state.resolveSystemCombat()
## - Called after each system's combat, not batched
## - Ensures clean state for subsequent systems
##
## **Command Lifecycle:**
## - Commands stored in Fleet.command field (entity-manager pattern)
## - Fleets with missionState == Executing have arrived at targets
## - Administrative completion marks commands done after effects resolved
