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

import std/[options, random, sequtils, strformat, tables]
import ../types/core
import ../../common/logger
import ../types/game_state
import
  ../types/[
    diplomacy as dip_types,
    espionage as esp_types,
    intel as intel_types,
    fleet,
    command,
    event,
    resolution as res_types,
    simultaneous as simultaneous_types,
  ]
import ../state/engine as state_engine
import ../entities/fleet_ops
import ../systems/combat/orchestrator
import ../systems/espionage/resolution as espionage_resolution
import ../systems/colony/colonization
import ../intel/[spy_resolution, starbase_surveillance]
import ../prestige/engine as prestige_app

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

  # Start with current turn commands (will merge state.fleetCommands below)
  var effectiveCommands = commands

  # ===================================================================
  # STEP 0: MERGE ACTIVE FLEET ORDERS (from state.fleetCommands)
  # ===================================================================
  # Per ec4x_canonical_turn_cycle.md:94-113 (Conflict Phase Step 0)
  #
  # Universal Order Lifecycle:
  #   1. Command Phase Part C: Orders validated → state.fleetCommands
  #   2. Production Phase Step 1a: Standing orders generated → state.fleetCommands  
  #   3. Production Phase Step 1c: Fleets move toward targets
  #   4. Production Phase Step 1d: Arrivals detected → state.arrivedFleets
  #   5. Conflict Phase Step 0: Commands merged for execution ← YOU ARE HERE
  #   6. Conflict Phase Steps 1-6: Commands execute
  #
  # state.fleetCommands contains:
  #   - Active orders (player submission, Command Phase Part C)
  #   - Standing orders (condition-generated, Production Phase Step 1a)
  #
  # Both types follow same lifecycle, stored in same table for consistency.
  # Only merge orders that execute in Conflict Phase (skip Move, Patrol, Salvage).
  logInfo("Orders",
    "[CONFLICT STEP 0] Merging fleet orders for Conflict Phase execution",
    "total_orders=", state.fleetCommands.len)

  var mergedFleetOrderCount = 0
  for fleetId, fleetCommand in state.fleetCommands:
    # Only merge orders that execute in Conflict Phase
    # Skip orders that execute in other phases:
    # - Movement orders (Move, Patrol, etc.): Execute in Production Phase
    # - Salvage: Executes in Income Phase
    const movementOrders = [
      FleetCommandType.Move, FleetCommandType.Patrol, FleetCommandType.SeekHome
    ]
    if fleetCommand.commandType in movementOrders or
        fleetCommand.commandType == FleetCommandType.Salvage:
      continue

    # Find fleet owner
    let fleetOpt = state.fleet(fleetId)
    if fleetOpt.isNone:
      logDebug("Orders", "  [SKIP] Fleet no longer exists", "fleetId=", fleetId)
      continue

    let fleetOwner = fleetOpt.get().houseId

    # Ensure owner has command packet
    if fleetOwner notin effectiveCommands:
      effectiveCommands[fleetOwner] = command.CommandPacket(
        houseId: fleetOwner,
        turn: state.turn,
        treasury: 0,
        fleetCommands: @[],
        buildCommands: @[],
        researchAllocation: ResearchAllocation(),
        diplomaticCommand: @[],
        populationTransfers: @[],
        terraformCommands: @[],
        colonyManagement: @[],
        standingCommands: initTable[FleetId, StandingCommand](),
        espionageAction: none(esp_types.EspionageAttempt),
        ebpInvestment: 0,
        cipInvestment: 0,
      )

    # Add fleet command to owner's commands
    effectiveCommands[fleetOwner].fleetCommands.add(fleetCommand)
    mergedFleetOrderCount += 1
    logDebug("Orders", "  [MERGE] Command from fleet",
      "type=", fleetCommand.commandType,
      " fleetId=", fleetId, " owner=", fleetOwner)

  logInfo("Orders", "Active fleet orders merged",
    "conflict_orders=", mergedFleetOrderCount)

  # Find all systems where combat should occur based on diplomatic status and commands.
  # Use effectiveCommands (includes merged queued combat commands)
  var combatSystems: seq[SystemId] = @[]

  for systemId, system in state.starMap.systems:
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

        # Get diplomatic state between these two houses from house1's perspective.
        let relation1to2 =
          state.houses[house1].diplomaticRelations.getDiplomaticState(house2)
        # Get diplomatic state between these two houses from house2's perspective.
        let relation2to1 =
          state.houses[house2].diplomaticRelations.getDiplomaticState(house1)

        # Combat decision logic per docs/engine/mechanics/diplomatic-combat-resolution.md
        if relation1to2 == dip_types.DiplomaticState.Enemy or
            relation2to1 == dip_types.DiplomaticState.Enemy:
          # If either side declares the other 'Enemy', combat occurs.
          systemHasCombat = true
          logDebug("Combat", "Combat triggered: Enemy status",
            "house1=", house1, " house2=", house2)
        elif relation1to2 == dip_types.DiplomaticState.Hostile or
            relation2to1 == dip_types.DiplomaticState.Hostile:
          # If either side declares 'Hostile', combat occurs if there are ANY threatening or provocative orders
          # from either house in this system.
          var foundProvocativeOrder = false
          for h in @[house1, house2]:
            # Check effective commands (includes queued commands)
            if h in effectiveCommands:
              for command in effectiveCommands[h].fleetCommands:
                # Check if the fleet for this order is actually in the current system
                let fleetOpt = state.fleet(command.fleetId)
                if fleetOpt.isSome and fleetOpt.get().location == systemId:
                  if isThreateningFleetOrder(command.commandType) or
                      isNonThreateningButProvocativeFleetOrder(command.commandType):
                    foundProvocativeOrder = true
                    break
              if foundProvocativeOrder:
                break

          if foundProvocativeOrder:
            systemHasCombat = true
            logDebug("Combat",
              "Combat triggered: Hostile status with provocative orders",
              "house1=", house1, " house2=", house2)
        elif relation1to2 == dip_types.DiplomaticState.Neutral and
            relation2to1 == dip_types.DiplomaticState.Neutral:
          # If both are Neutral, combat only occurs if threatening orders are issued
          # against a system controlled by the other house.
          var house1ThreateningHouse2 = false
          var house2ThreateningHouse1 = false

          # Check if system is controlled (has a colony)
          let colonyOptForOwner = state.colonyBySystem(systemId)
          let systemOwner =
            if colonyOptForOwner.isSome:
              some(colonyOptForOwner.get().owner)
            else:
              none(HouseId)

          # Check effective commands (includes queued commands)
          if house1 in effectiveCommands and systemOwner.isSome and
              systemOwner.get() == house2:
            for command in effectiveCommands[house1].fleetCommands:
              let fleetOpt = state.fleet(command.fleetId)
              if fleetOpt.isSome and fleetOpt.get().location == systemId and
                  isThreateningFleetOrder(command.commandType):
                house1ThreateningHouse2 = true
                break

          if house2 in effectiveCommands and systemOwner.isSome and
              systemOwner.get() == house1:
            for command in effectiveCommands[house2].fleetCommands:
              let fleetOpt = state.fleet(command.fleetId)
              if fleetOpt.isSome and fleetOpt.get().location == systemId and
                  isThreateningFleetOrder(command.commandType):
                house2ThreateningHouse1 = true
                break

          if house1ThreateningHouse2 or house2ThreateningHouse1:
            systemHasCombat = true
            logDebug("Combat",
              "Combat triggered: Neutral status with threatening orders",
              "house1=", house1, " house2=", house2)

        if systemHasCombat:
          break # Found a combat pair, add system and move on.

      if systemHasCombat:
        combatSystems.add(systemId)
        break # System added, move to next system.

  # ===================================================================
  # ARRIVAL FILTERING: Filter orders to only arrived fleets
  # ===================================================================
  # Per ec4x_canonical_turn_cycle.md:486-492 (Production Phase Step 1d)
  #
  # Arrival Detection (Production Phase):
  #   - Fleet location compared to order target
  #   - If match: add to state.arrivedFleets[fleetId] = systemId
  #
  # Execution (Conflict Phase):
  #   - Only orders where command.fleetId in state.arrivedFleets execute
  #   - Ensures orders execute when fleets reach targets, not before
  #
  # Orders requiring arrival: Bombard, Invade, Blitz, Colonize, 
  #                          SpyPlanet, SpySystem, HackStarbase
  # Create filtered order set once to avoid O(H×O) iteration per step
  var arrivedOrders = effectiveOrders
  for houseId in arrivedOrders.keys:
    var filteredFleetOrders: seq[FleetOrder] = @[]
    for command in arrivedOrders[houseId].fleetCommands:
      # Check if order requires arrival
      const arrivalRequired = [
        FleetCommandType.Bombard, FleetCommandType.Invade, FleetCommandType.Blitz,
        FleetCommandType.Colonize, FleetCommandType.SpyColony,
        FleetCommandType.SpySystem, FleetCommandType.HackStarbase,
      ]
      if command.commandType in arrivalRequired:
        if command.fleetId in state.arrivedFleets:
          filteredFleetOrders.add(command)
        else:
          logDebug("Orders", "  [SKIP] Fleet has not arrived",
            "fleetId=", command.fleetId, " order=", command.commandType)
      else:
        # Keep orders that don't require arrival checking
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
      systemId, effectiveOrders, arrivedOrders, combatReports, events, rng
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
  # Fallback logic for losers with AutoColonize standing commands
  logInfo("Colony", "[CONFLICT STEP 5] Resolving colonization attempts...")
  let colonizationResults =
    state.resolveColonization(arrivedOrders, rng, events)
  logInfo("Colony", "[CONFLICT STEP 5] Completed",
    "attempts=", colonizationResults.len)

  # Clear arrivedFleets for executed colonization orders
  for result in colonizationResults:
    if result.fleetId in state.arrivedFleets:
      state.arrivedFleets.del(result.fleetId)
      logDebug("Orders", "  Cleared arrival status for fleet",
        "fleetId=", result.fleetId)

  # ===================================================================
  # STEPS 6a & 6a.5: SCOUT MISSIONS (New + Existing)
  # ===================================================================
  # Per ec4x_canonical_turn_cycle.md:146-199
  # Per docs/engine/mechanics/scout-espionage-system.md
  #
  # Unified processing for both new and existing scout missions:
  #
  # Phase 1 (Step 6a): NEW missions from arrivedFleets
  #   - Transition: Traveling → OnSpyMission
  #   - Run first detection check (gates mission registration)
  #   - If detected: Destroy scouts, mission fails
  #   - If undetected: Register in activeSpyMissions, generate Perfect intel
  #
  # Phase 2 (Step 6a.5): EXISTING missions from activeSpyMissions
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
  state.processEspionageActions(effectiveOrders, rng, events)
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
  state.processAllStarbaseSurveillance(
    state.turn, survRng, events
  )
  logInfo("Espionage", "[CONFLICT STEP 6c] Completed starbase surveillance")
