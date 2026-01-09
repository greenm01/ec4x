## Conflict Phase Resolution - Phase 1 of Canonical Turn Cycle
##
## Resolves all combat and espionage operations for arrived fleets.
## Orders stored in Command Phase execute when fleets arrive at targets.
##
## **Canonical Execution Order:**
##
## 1. Space Combat (simultaneous resolution)
##   1a. Raider Detection
##   1b. Combat Resolution
## 2. Orbital Combat (simultaneous resolution)
##   2a. Raider Detection
##   2b. Combat Resolution
## 3. Blockade Resolution
## 4. Planetary Combat
## 5. Colonization
## 6. Espionage Operations
##   6a. Fleet-Based Espionage (includes Spy Scout Detection)
##   6b. Space Guild Espionage
##   6c. Starbase Surveillance

import std/[options, random, tables]
import ../types/core
import ../../common/logger
import ../types/game_state
import
  ../types/[
    diplomacy as dip_types,
    espionage as esp_types,
    tech as tech_types,
    fleet,
    command,
    event,
    resolution as res_types,
  ]
import ../state/[engine as state_engine, iterators]
import ../systems/combat/orchestrator
import ../systems/espionage/resolution as espionage_resolution
import ../systems/colony/colonization
import ../intel/starbase_surveillance
import ../systems/fleet/execution as fleet_order_execution

proc resolveConflictPhase*(
    state: var GameState,
    commands: Table[HouseId, command.CommandPacket],
    combatReports: var seq[res_types.CombatReport],
    events: var seq[event.GameEvent],
    rng: var Rand,
) =
  ## Phase 1: Resolve all combat and infrastructure damage
  ## This happens FIRST so damaged facilities affect production
  logInfo("Conflict", "=== Conflict Phase ===", "turn=", state.turn)
  logInfo("Conflict", "Using RNG for combat resolution", "seed=", state.turn)

  # Commands are already stored in Fleet.command field (entity-manager pattern)
  # No merge step needed - commands passed directly from Command Phase
  let effectiveCommands = commands

  # Find all systems where combat should occur based on diplomatic status and commands.
  # Use effectiveCommands (includes merged queued combat commands)
  var combatSystems: seq[SystemId] = @[]

  for systemId, system in state.allSystemsWithId():
    # Get all houses with active fleets or colonies at this system
    # Use state/iterators for O(1) indexed lookups
    var housesPresent: seq[HouseId] = @[]
    
    # Collect houses with fleets at this system
    for fleet in state.fleetsInSystem(systemId):
      if fleet.houseId notin housesPresent:
        housesPresent.add(fleet.houseId)
    
    # Add colony owner if present
    let colonyOpt = state.colonyBySystem(systemId)
    if colonyOpt.isSome:
      let colonyOwner = colonyOpt.get().owner
      if colonyOwner notin housesPresent:
        housesPresent.add(colonyOwner)

    # Need at least two houses to have a conflict.
    if housesPresent.len < 2:
      continue

    var systemHasCombat = false
    for i in 0 ..< housesPresent.len:
      for j in (i + 1) ..< housesPresent.len:
        let house1 = housesPresent[i]
        let house2 = housesPresent[j]

        # Get diplomatic state between these two houses (bidirectional)
        let relation1to2Key = (house1, house2)
        let relation2to1Key = (house2, house1)

        let relation1to2 =
          if relation1to2Key in state.diplomaticRelation:
            state.diplomaticRelation[relation1to2Key].state
          else:
            dip_types.DiplomaticState.Neutral  # Default to Neutral

        let relation2to1 =
          if relation2to1Key in state.diplomaticRelation:
            state.diplomaticRelation[relation2to1Key].state
          else:
            dip_types.DiplomaticState.Neutral  # Default to Neutral

        # Combat decision logic per docs/specs/08-diplomacy.md Section 8.1
        # ENEMY: Combat on sight, anywhere, regardless of missionState or command type
        if relation1to2 == dip_types.DiplomaticState.Enemy or
            relation2to1 == dip_types.DiplomaticState.Enemy:
          systemHasCombat = true
          logDebug("Combat", "Combat triggered: Enemy status",
            "house1=", house1, " house2=", house2)

        # HOSTILE: Combat if fleets are EXECUTING Contest or Attack tier commands
        # This is post-escalation state (Neutral→Hostile happened previous turn)
        elif relation1to2 == dip_types.DiplomaticState.Hostile or
            relation2to1 == dip_types.DiplomaticState.Hostile:
          var foundProvocative = false
          for fleet in state.fleetsInSystem(systemId):
            # Only fleets EXECUTING missions have intent at this location
            if fleet.missionState == MissionState.Executing:
              let threatLevel = CommandThreatLevels.getOrDefault(
                fleet.command.commandType, ThreatLevel.Benign
              )
              # Contest (Patrol, Hold, Rendezvous) or Attack (Blockade, Bombard, etc.)
              if threatLevel in [ThreatLevel.Contest, ThreatLevel.Attack]:
                foundProvocative = true
                break
          if foundProvocative:
            systemHasCombat = true
            logDebug("Combat",
              "Combat triggered: Hostile status with executing provoc commands",
              "house1=", house1, " house2=", house2)

        # NEUTRAL: Check for Attack tier commands at their colony
        # Contest tier at their system escalates to Hostile (no combat this turn)
        # Attack tier at their colony escalates to Enemy (combat this turn)
        elif relation1to2 == dip_types.DiplomaticState.Neutral and
            relation2to1 == dip_types.DiplomaticState.Neutral:
          if colonyOpt.isSome:
            let systemOwner = colonyOpt.get().owner
            # Check if non-owner has Attack tier command EXECUTING at this colony
            for fleet in state.fleetsInSystem(systemId):
              if fleet.houseId != systemOwner and fleet.missionState == MissionState.Executing:
                let threatLevel = CommandThreatLevels.getOrDefault(
                  fleet.command.commandType, ThreatLevel.Benign
                )
                # Attack tier (Blockade, Bombard, Invade, Blitz) → Enemy + combat
                if threatLevel == ThreatLevel.Attack:
                  systemHasCombat = true
                  logDebug("Combat",
                    "Combat triggered: Neutral + Attack tier at colony",
                    "attacker=", fleet.houseId, " owner=", systemOwner)
                  break
                # Contest tier (Patrol, Hold, Rendezvous) → Hostile + no combat
                # Escalation handled elsewhere, no combat triggered this turn

        if systemHasCombat:
          break # Found a combat pair, add system and move on.

      if systemHasCombat:
        combatSystems.add(systemId)
        break # System added, move to next system.

  # ===================================================================
  # ARRIVAL FILTERING: Filter commands to only arrived fleets
  # ===================================================================
  # Per ec4x_canonical_turn_cycle.md:486-492 (Production Phase Step 1d)
  #
  # Arrival Detection (Production Phase):
  #   - Fleet location compared to command target
  #   - If match: fleet.missionState set to Executing
  #
  # Execution (Conflict Phase):
  #   - Only commands where fleet.missionState == Executing execute
  #   - Ensures commands execute when fleets reach targets, not before
  #
  # Orders requiring arrival: Bombard, Invade, Blitz, Colonize,
  #                          SpyColony, SpySystem, HackStarbase
  # Create filtered command set once to avoid O(H×O) iteration per step
  var arrivedOrders = effectiveCommands
  for houseId in arrivedOrders.keys:
    var filteredFleetOrders: seq[FleetCommand] = @[]
    for command in arrivedOrders[houseId].fleetCommands:
      # Check if command requires arrival
      const arrivalRequired = [
        FleetCommandType.Bombard, FleetCommandType.Invade, FleetCommandType.Blitz,
        FleetCommandType.Colonize, FleetCommandType.ScoutColony,
        FleetCommandType.ScoutSystem, FleetCommandType.HackStarbase,
      ]
      if command.commandType in arrivalRequired:
        let fleetOpt = state.fleet(command.fleetId)
        if fleetOpt.isSome and fleetOpt.get().missionState == MissionState.Executing:
          filteredFleetOrders.add(command)
        else:
          logDebug("Orders", "  [SKIP] Fleet has not arrived",
            "fleetId=", command.fleetId, " order=", command.commandType)
      else:
        # Keep commands that don't require arrival checking
        filteredFleetOrders.add(command)
    arrivedOrders[houseId].fleetCommands = filteredFleetOrders

  # ===================================================================
  # STEPS 1, 2, & 4: ALL COMBAT THEATERS (orchestrated)
  # ===================================================================
  # Per ec4x_canonical_turn_cycle.md:115-136
  # Resolve combat in each system with theater progression enforcement
  # Space → Orbital → Blockade → Planetary (single entry point pattern)
  logInfo("Combat", "[CONFLICT STEPS 1, 2, & 4] Resolving all combat theaters",
    "systems=", combatSystems.len)
  for systemId in combatSystems:
    state.resolveSystemCombat(
      systemId, effectiveCommands, arrivedOrders, combatReports, events, rng
    )
  logInfo("Combat", "[CONFLICT STEPS 1, 2, & 4] Completed",
    "battles=", combatReports.len)

  # ===================================================================
  # STEP 3: BLOCKADE RESOLUTION
  # ===================================================================
  # Per ec4x_canonical_turn_cycle.md:125-129
  # Blockades resolved per-system by orchestrator.resolveSystemCombat()
  # No separate global resolution needed - handled in Steps 1, 2, & 4 loop above
  logInfo("Conflict", "[CONFLICT STEP 3] Blockade resolution (handled by orchestrator)")

  # ===================================================================
  # STEP 4: PLANETARY COMBAT - HANDLED BY ORCHESTRATOR ABOVE
  # ===================================================================
  # Planetary combat is now resolved as part of theater progression in Step 1-2-4
  # The orchestrator enforces Space → Orbital → Planetary sequence
  # No separate call needed here

  # ===================================================================
  # STEP 5: COLONIZATION
  # ===================================================================
  # Per ec4x_canonical_turn_cycle.md:138-142
  # ETACs establish colonies, resolve conflicts (winner-takes-all)
  # Fallback logic for losers (fleet holds position)
  logInfo("Colony", "[CONFLICT STEP 5] Resolving colonization attempts...")
  let colonizationResults = state.resolveColonization(rng, events)
  logInfo("Colony", "[CONFLICT STEP 5] Completed",
    "attempts=", colonizationResults.len)

  # ===================================================================
  # STEPS 6a & 6a.5: SCOUT MISSIONS (New + Existing)
  # ===================================================================
  # Per ec4x_canonical_turn_cycle.md:146-199
  # Per docs/engine/mechanics/scout-espionage-system.md
  #
  # Unified processing for both new and existing scout missions:
  #
  # Phase 1 (Step 6a): NEW missions (missionState == Executing)
  #   - Transition: Executing → ScoutLocked
  #   - Run first detection check (gates mission registration)
  #   - If detected: Destroy scouts, mission fails
  #   - If undetected: Set fleet.missionState = ScoutLocked, generate Perfect intel
  #
  # Phase 2 (Step 6a.5): EXISTING missions (query fleets with missionState == ScoutLocked)
  #   - Process missions from previous turns (startTurn < state.turn)
  #   - Run persistent detection checks
  #   - If detected: Destroy scouts, end mission, diplomatic escalation
  #   - If undetected: Generate Perfect intel, continue mission
  #
  logInfo("Espionage", "[CONFLICT STEPS 6a & 6a.5] Scout missions...")
  state.resolveScoutMissions(rng, events)
  logInfo("Espionage", "[CONFLICT STEPS 6a & 6a.5] Complete")

  # ===================================================================
  # STEP 6b: SPACE GUILD ESPIONAGE (EBP-based)
  # ===================================================================
  # Per ec4x_canonical_turn_cycle.md:163-167
  # Process OrderPacket.espionageAction (EBP-based espionage)
  logInfo("Espionage",
    "[CONFLICT STEP 6b] Space Guild espionage (EBP-based covert ops)...")
  state.processEspionageActions(effectiveCommands, rng, events)
  logInfo("Espionage", "[CONFLICT STEP 6b] Completed EBP-based espionage processing")

  # ===================================================================
  # STEP 6c: STARBASE SURVEILLANCE
  # ===================================================================
  # Per ec4x_canonical_turn_cycle.md:169-173
  # Process starbase surveillance (continuous monitoring every turn)
  # Intelligence gathering happens AFTER combat
  logInfo("Espionage",
    "[CONFLICT STEP 6c] Starbase surveillance (continuous monitoring)...")
  var survRng = initRand(state.turn + 12345) # Unique seed for surveillance
  state.processAllStarbaseSurveillance(state.turn, survRng)
  logInfo("Espionage", "[CONFLICT STEP 6c] Completed starbase surveillance")

  # ===================================================================
  # STEP 7: ADMINISTRATIVE COMPLETION (Conflict Commands)
  # ===================================================================
  # Handle administrative completion for commands that finish during Conflict Phase:
  # - Combat commands: Patrol, Guard*, Blockade, Bombard, Invade, Blitz
  #   (behavior already handled in combat resolution Steps 1-4)
  # - Colonization: Colonize (already handled in Step 5)
  # - Espionage: SpyColony, SpySystem, HackStarbase (already handled in Steps 6a/6b)
  #
  # This step marks commands complete after combat/colonization/espionage resolves
  # Note: This is NOT command execution - effects already happened in Steps 1-6
  # Commands are behavior parameters that already determined fleet/mission actions
  logInfo("Conflict", "[CONFLICT STEP 7] Administrative completion for Conflict commands...")
  fleet_order_execution.performCommandMaintenance(
    state, arrivedOrders, events, rng,
    fleet_order_execution.isConflictCommand,
    "Conflict Phase Step 7"
  )
  logInfo("Conflict", "[CONFLICT STEP 7] Administrative completion complete")
