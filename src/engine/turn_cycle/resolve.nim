## Turn resolution engine - the heart of EC4X gameplay
##
## OFFLINE GAMEPLAY SYSTEM - No network dependencies
## This module is designed to work standalone for local/hotseat multiplayer
## Network transport (Nostr) wraps around this engine without modifying it
##
## ARCHITECTURE: Main orchestrator that coordinates resolution phases
## All phase logic extracted to resolution/phases/* modules for maintainability
##
## **TURN RESOLUTION PHASES:**
##
## **PHASE 1: CONFLICT PHASE** [resolution/phases/conflict_phase.nim]
##   Step 0: Merge Active Fleet Orders (from state.fleetOrders)
##   Step 1: Space Combat (simultaneous resolution)
##   Step 2: Orbital Combat (simultaneous resolution)
##   Step 3: Blockade Resolution (simultaneous)
##   Step 4: Planetary Combat (bombard/invade/blitz, simultaneous)
##   Step 5: Colonization (ETAC operations, simultaneous)
##   Step 6: Espionage Operations (simultaneous)
##     6a: Fleet-Based Espionage Arrival (SpyPlanet, SpySystem, HackStarbase)
##     6a.5: Persistent Spy Mission Detection (active missions from prior turns)
##     6b: Space Guild Espionage (EBP-based covert ops)
##     6c: Starbase Surveillance (continuous monitoring)
##
## **PHASE 2: INCOME PHASE** [resolution/phases/income_phase.nim]
##   Step 0: Apply Ongoing Espionage Effects (SRP/NCV/Tax reduction, intel corruption)
##   Step 0b: Process EBP/CIP Investment (purchase espionage points, over-investment penalty)
##   Step 1: Calculate Base Production (colony GCO → PP)
##   Step 2: Apply Blockades (reduce GCO for blockaded colonies)
##   Step 3: Calculate Maintenance Costs (deduct from gross production)
##   Step 4: Execute Salvage Orders (recover PP from wreckage)
##   Step 5: Capacity Enforcement (after IU loss from combat/blockades)
##     5a: Capital Squadron Capacity (immediate, no grace period)
##     5b: Total Squadron Limit (2-turn grace period)
##     5c: Fighter Squadron Capacity (2-turn grace period)
##     5d: Planet-Breaker Enforcement (immediate, colony-based limit)
##   Step 6: Collect Resources (apply PP/RP to house treasuries)
##   Step 7: Calculate Prestige (award/deduct for turn events)
##   Step 8: House Elimination & Victory Checks
##     8a: House Elimination (standard elimination + defensive collapse)
##     8b: Victory Conditions (prestige/elimination/turn limit)
##   Step 9: Advance Timers (espionage effects, diplomatic timers, grace periods)
##
## **PHASE 3: COMMAND PHASE** [resolution/phases/command_phase.nim]
##   Step 0: Order Cleanup (clean completed/failed/aborted orders from previous turn)
##   Part A: Ship Commissioning & Automation
##     - Commission completed ships from pendingMilitaryCommissions
##     - Auto-create squadrons, auto-assign to fleets
##     - Auto-load PTUs onto ETAC ships
##     - Colony automation (auto-repair, auto-load fighters)
##   Part B: Player Submission Window (24-hour window in multiplayer)
##     - Process build orders
##     - Process colony management orders
##     - Process Space Guild population transfers
##     - Process diplomatic actions
##     - Process terraforming orders
##   Part C: Order Processing (categorization & queueing)
##     - Queue combat orders for Turn N+1 Conflict Phase
##     - Execute administrative orders immediately
##     - Store movement orders for Maintenance Phase execution
##     - Process research allocation (PP → ERP/SRP/TRP, with treasury scaling)
##
## **PHASE 4: MAINTENANCE PHASE** [resolution/phases/maintenance_phase.nim]
##   Step 1: Fleet Movement & Order Activation
##     1a: Order Activation (activate orders, generate standing orders)
##     1b: Order Maintenance (lifecycle management)
##     1c: Fleet Movement (fleets move toward targets)
##     1d: Fleet Arrival Detection (populate state.arrivedFleets for Conflict/Income execution)
##   Step 2: Construction & Repair Advancement
##     2a: Advance all queues (facility + colony construction)
##     2b: Commission planetary defense (fighters, facilities, ground forces)
##   Step 3: Diplomatic Actions (state changes take effect)
##   Step 4: Population Arrivals (Space Guild transfers complete)
##   Step 5: Terraforming Projects (advance active projects)
##   Step 6: Cleanup (expire proposals, update diplomatic timers)
##   Step 7: Research Advancement (process tech upgrades)
##     7a: Breakthrough Rolls (every 5 turns)
##     7b: EL Advancement (economic level)
##     7c: SL Advancement (science level)
##     7d: Tech Field Advancement (CST, WEP, TFM, ELI, CI)
##
## **COMMISSIONING & AUTOMATION FLOW:**
## - Turn N: Build orders submitted → queued
## - Turn N: Maintenance advances queues → commissions planetary defense (same turn)
## - Turn N: Maintenance stores ship completions in pendingMilitaryCommissions
## - Turn N+1: Command Phase commissions ships → automation → new builds
##
## **Split Commissioning Rationale:**
## - Planetary defense (fighters, facilities, ground forces) commission same turn
##   → Available for defense in next turn's Conflict Phase
## - Ships commission next turn (after Conflict Phase dock survival check)
##   → Frees dock capacity before automation and new builds
## - Auto-repair and new builds see accurate available capacity

import std/[tables, algorithm, options, random, sequtils, hashes, sets, strformat]
import ../common/types/core
import ../common/logger as common_logger
import gamestate, orders, fleet, squadron, ai_special_modes, standing_orders, logger
import index_maintenance
import espionage/[types as esp_types, engine as esp_engine]
import diplomacy/[types as dip_types] # Renamed to avoid conflict with gamestate.diplomacy
import research/[types as res_types_research]
import commands/[executor]
import intelligence/[spy_resolution]
import intelligence/event_processor/init as event_processor
import economy/repair_queue
# Import resolution modules
import resolution/[types as res_types, fleet_orders, economy_resolution, diplomatic_resolution, combat_resolution, simultaneous, simultaneous_planetary, simultaneous_espionage, commissioning, automation, construction]
import resolution/phases/[conflict_phase, income_phase, command_phase, maintenance_phase]
import prestige as prestige_types
import prestige/application as prestige_app
import ../ai/rba/config as rba_config  # For act progression config

# Import debug-only modules
when not defined(release):
  import resolution/simultaneous_blockade

# Re-export resolution types for backward compatibility
export res_types.GameEvent, res_types.GameEventType, res_types.CombatReport

type
  TurnResult* = object
    newState*: GameState
    events*: seq[res_types.GameEvent]
    combatReports*: seq[res_types.CombatReport]

# Phase functions imported from resolution/phases/
# - resolveConflictPhase from conflict_phase.nim
# - resolveCommandPhase from command_phase.nim

## Main Turn Resolution

proc resolveTurn*(state: GameState, orders: Table[HouseId, OrderPacket]): TurnResult =
  ## Resolve a complete game turn
  ## Returns new game state and events that occurred

  logResolve("Turn resolution starting", "turn=", $state.turn)

  result.newState = state  # Start with current state
  result.events = @[]
  result.combatReports = @[]

  # Initialize RNG for this turn (use turn number as seed for reproducibility)
  # Using turn number as seed ensures deterministic replay for debugging
  var rng = initRand(state.turn)
  logRNG("RNG initialized for stochastic resolution", "turn=", $state.turn, " seed=", $state.turn)

  # Update act progression (checks gates and transitions if needed)
  discard getCurrentGameAct(result.newState, rba_config.globalRBAConfig.act_progression)

  logResolve("Starting strategic cycle", "turn=", $state.turn)

  # Generate AI orders for special modes (Defensive Collapse & MIA Autopilot)
  # These override player/AI orders for affected houses
  var effectiveOrders = orders  # Start with submitted orders

  for houseId, house in result.newState.houses:
    case house.status
    of HouseStatus.DefensiveCollapse:
      # Generate defensive collapse AI orders
      let defensiveOrders = getDefensiveCollapseOrders(result.newState, houseId)

      # Create empty order packet (no construction, research, diplomacy)
      var collapsePacket = OrderPacket(
        houseId: houseId,
        turn: state.turn,
        fleetOrders: @[],
        buildOrders: @[],
        researchAllocation: res_types_research.initResearchAllocation(),
        diplomaticActions: @[],
        populationTransfers: @[],
        terraformOrders: @[],
        espionageAction: none(esp_types.EspionageAttempt),
        ebpInvestment: 0,
        cipInvestment: 0
      )

      # Add defensive fleet orders
      for (fleetId, order) in defensiveOrders:
        collapsePacket.fleetOrders.add(order)

      effectiveOrders[houseId] = collapsePacket
      logInfo("Resolve", "Defensive Collapse mode active", house.name, " orders=", $defensiveOrders.len)

    of HouseStatus.Autopilot:
      # Generate autopilot AI orders
      let autopilotOrders = getAutopilotOrders(result.newState, houseId)

      # Create minimal order packet (no construction, no new research, no diplomacy)
      var autopilotPacket = OrderPacket(
        houseId: houseId,
        turn: state.turn,
        fleetOrders: @[],
        buildOrders: @[],
        researchAllocation: res_types_research.initResearchAllocation(),
        diplomaticActions: @[],
        populationTransfers: @[],
        terraformOrders: @[],
        espionageAction: none(esp_types.EspionageAttempt),
        ebpInvestment: 0,
        cipInvestment: 0
      )

      # Add autopilot fleet orders
      for (fleetId, order) in autopilotOrders:
        autopilotPacket.fleetOrders.add(order)

      effectiveOrders[houseId] = autopilotPacket
      logInfo("Resolve", "Autopilot mode active", house.name, " orders=", $autopilotOrders.len)

    of HouseStatus.Active:
      # Normal play - use submitted orders
      discard

  # Phase 1: Conflict (combat, infrastructure damage, espionage)
  conflict_phase.resolveConflictPhase(result.newState, effectiveOrders, result.combatReports, result.events, rng)

  # Phase 2: Income (resource collection + capacity enforcement after IU loss)
  income_phase.resolveIncomePhase(result.newState, effectiveOrders, result.events)

  # Phase 3: Command (ship commissioning → automation → build orders → fleet orders → diplomatic actions)
  command_phase.resolveCommandPhase(result.newState, effectiveOrders, result.combatReports, result.events, rng)

  # Phase 4: Maintenance (fleet movement → construction advancement → planetary defense commissioning → diplomatic actions)
  let completedShips = maintenance_phase.resolveMaintenancePhase(result.newState, result.events, effectiveOrders, rng)

  # Store completed ships for next turn's commissioning
  # (Planetary defense already commissioned in Maintenance Phase Step 2b)
  # Ships will be commissioned at start of next turn's Command Phase Part A
  result.newState.pendingMilitaryCommissions = completedShips
  logDebug(LogCategory.lcEconomy, &"Stored {completedShips.len} ships for next turn commissioning")

  # Validate all commissioning pools are empty before advancing turn
  # All commissioned units should be auto-assigned to fleets/colonies
  # Fighter squadrons are OK to remain at colonies (they're not "unassigned")
  for systemId, colony in result.newState.colonies:
    if colony.unassignedSquadrons.len > 0:
      logError("Resolve", "Turn ending with unassigned squadrons", "colony=", $systemId, " count=", $colony.unassignedSquadrons.len)
      # This should never happen - indicates auto-assignment bug
      raise newException(ValueError, "Colony " & $systemId & " has " & $colony.unassignedSquadrons.len & " unassigned squadrons at turn end")

  logDebug("Resolve", "Turn validation passed - all commissioned units assigned", "turn=", $result.newState.turn)

  # Process events for intelligence generation (fog-of-war filtered)
  # Converts GameEvents into per-house intelligence reports
  event_processor.processEventsForIntelligence(
    result.newState,
    result.events,
    result.newState.turn
  )
  logInfo(LogCategory.lcOrders, &"Intelligence event processing complete ({result.events.len} events)")

  # Validate index consistency in debug builds
  when defined(debug) or defined(validateIndices):
    let indexErrors = result.newState.validateIndices()
    if indexErrors.len > 0:
      logError("Resolve", "Index validation failed at end of turn", "errors=", $indexErrors.len)
      for err in indexErrors:
        logError("Resolve", "  " & err)
      raise newException(ValueError, "Index inconsistency detected: " & indexErrors[0])

  # Advance to next turn
  result.newState.turn += 1
  # Advance strategic cycle (handled by advanceTurn)

  return result

## Phase 3: Command
## OLD IMPLEMENTATION - NOW DISABLED
## Command Phase logic has been extracted to resolution/phases/command_phase.nim
## This implementation is kept for reference but is no longer used
