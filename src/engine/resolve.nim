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
## 1. **Conflict Phase** (simultaneous) [resolution/phases/conflict_phase.nim]
##    - Spy scout detection
##    - Space/orbital combat resolution
##    - Blockade resolution (simultaneous)
##    - Planetary combat (bombard/invade/blitz, simultaneous)
##    - Espionage operations (fleet + EBP, simultaneous)
##    - Spy scout travel
##
## 2. **Income Phase** (sequential) [resolution/phases/income_phase.nim]
##    - Resource generation (PP, RP, EP, CP, IP)
##    - Maintenance costs deducted
##    - Colony growth/decline
##    - Capacity enforcement (disband excess units after IU loss)
##
## 3. **Command Phase** (sequential) [resolution/phases/command_phase.nim]
##    a. Commission completed projects (frees dock capacity)
##    b. Colony automation (processColonyAutomation):
##       - Auto-load fighters to carriers (if colony.autoLoadingEnabled)
##       - Auto-repair submission (if colony.autoRepairEnabled)
##       - Auto-squadron balancing (always on)
##    c. Process new build orders (uses freed capacity)
##    d. Colony management (tax rates, auto-repair toggles)
##    e. Space Guild population transfers
##    f. Scout detection escalations
##    g. Spy scout orders (join, move, rendezvous)
##    h. Auto-load cargo at colonies
##    i. Terraforming orders
##    j. Fleet order submission (combat orders queued for Turn N+1)
##
## 4. **Maintenance Phase** (sequential) [resolution/phases/maintenance_phase.nim]
##    - Advance construction queues (facility + colony)
##    - Advance repair queues
##    - Store completed projects in state.pendingCommissions
##    - Diplomatic state changes
##    - Research advancement
##    - House elimination checks
##    - Fleet movement execution
##    - Fleet upkeep and status decay
##
## **COMMISSIONING & AUTOMATION FLOW:**
## - Turn N: Build orders submitted → queued
## - Turn N: Maintenance advances queues → stores completions in pendingCommissions
## - Turn N+1: Command Phase commissions → automation → new builds
##
## This ordering ensures:
## - Commissioning frees dock capacity before automation
## - Auto-repair can use newly freed capacity
## - New builds see accurate available capacity

import std/[tables, algorithm, options, random, sequtils, hashes, sets, strformat]
import ../common/types/core
import ../common/logger as common_logger
import gamestate, orders, fleet, squadron, ai_special_modes, standing_orders, logger
import espionage/[types as esp_types, engine as esp_engine]
import diplomacy/[types as dip_types]
import research/[types as res_types_research]
import commands/[executor, spy_scout_orders]
import intelligence/[spy_travel, spy_resolution]
import economy/repair_queue
# Import resolution modules
import resolution/[types as res_types, fleet_orders, economy_resolution, diplomatic_resolution, combat_resolution, simultaneous, simultaneous_planetary, simultaneous_espionage, commissioning, automation, construction]
import resolution/phases/[command_phase, conflict_phase]
import prestige as prestige_types
import prestige/application as prestige_app

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

  logDebug("Resolve", "Turn resolution starting", "turn=", $state.turn)

  result.newState = state  # Start with current state
  result.events = @[]
  result.combatReports = @[]

  # Initialize RNG for this turn (use turn number as seed for reproducibility)
  # Using turn number as seed ensures deterministic replay for debugging
  var rng = initRand(state.turn)
  logRNG("RNG initialized for stochastic resolution", "turn=", $state.turn, " seed=", $state.turn)

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

  # Update combat statistics from combat reports (for diagnostics)
  for report in result.combatReports:
    if report.victor.isSome:
      let victorId = report.victor.get()
      # Victor gets a win
      result.newState.houses[victorId].lastTurnSpaceCombatWins += 1
      result.newState.houses[victorId].lastTurnSpaceCombatTotal += 1

      # Losers get losses
      for attackerId in report.attackers:
        if attackerId != victorId:
          result.newState.houses[attackerId].lastTurnSpaceCombatLosses += 1
          result.newState.houses[attackerId].lastTurnSpaceCombatTotal += 1
      for defenderId in report.defenders:
        if defenderId != victorId:
          result.newState.houses[defenderId].lastTurnSpaceCombatLosses += 1
          result.newState.houses[defenderId].lastTurnSpaceCombatTotal += 1
    else:
      # No victor - all participants get combat counted but no win/loss
      for houseId in report.attackers:
        result.newState.houses[houseId].lastTurnSpaceCombatTotal += 1
      for houseId in report.defenders:
        result.newState.houses[houseId].lastTurnSpaceCombatTotal += 1

  # Phase 2: Income (resource collection + capacity enforcement after IU loss)
  # Note: Auto-repair submission now happens in Command Phase after commissioning
  resolveIncomePhase(result.newState, effectiveOrders, result.events)

  # Phase 3: Command (commissioning → build orders → fleet orders → diplomatic actions)
  command_phase.resolveCommandPhase(result.newState, effectiveOrders, result.combatReports, result.events, rng)

  # Phase 4: Maintenance (upkeep, effect decrements, status updates, queue advancement, fleet movement)
  let completedProjects = resolveMaintenancePhase(result.newState, result.events, effectiveOrders, rng)

  # Store completed projects for next turn's commissioning
  # These will be commissioned at the start of next turn's Command Phase
  result.newState.pendingCommissions = completedProjects
  logDebug(LogCategory.lcEconomy, &"Stored {completedProjects.len} completed projects for next turn commissioning")

  # Validate all commissioning pools are empty before advancing turn
  # All commissioned units should be auto-assigned to fleets/colonies
  # Fighter squadrons are OK to remain at colonies (they're not "unassigned")
  for systemId, colony in result.newState.colonies:
    if colony.unassignedSquadrons.len > 0:
      logError("Resolve", "Turn ending with unassigned combat squadrons", "colony=", $systemId, " count=", $colony.unassignedSquadrons.len)
      # This should never happen - indicates auto-assignment bug
      raise newException(ValueError, "Colony " & $systemId & " has " & $colony.unassignedSquadrons.len & " unassigned combat squadrons at turn end")

    if colony.unassignedSpaceLiftShips.len > 0:
      logError("Resolve", "Turn ending with unassigned spacelift ships", "colony=", $systemId, " count=", $colony.unassignedSpaceLiftShips.len)
      # This should never happen - indicates auto-assignment bug
      raise newException(ValueError, "Colony " & $systemId & " has " & $colony.unassignedSpaceLiftShips.len & " unassigned spacelift ships at turn end")

  logDebug("Resolve", "Turn validation passed - all commissioned units assigned", "turn=", $result.newState.turn)

  # Advance to next turn
  result.newState.turn += 1
  # Advance strategic cycle (handled by advanceTurn)

  return result

## Phase 3: Command
## OLD IMPLEMENTATION - NOW DISABLED
## Command Phase logic has been extracted to resolution/phases/command_phase.nim
## This implementation is kept for reference but is no longer used

