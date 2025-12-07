## Command Phase Resolution
##
## Phase 3 of turn resolution - executes player orders (builds, movements,
## diplomatic actions, research allocation).
##
## **Execution Order:**
## 1. Commission completed projects (frees dock capacity)
## 2. Colony automation (auto-loading, auto-repair, auto-squadron balancing)
## 3. Process build orders (uses freed capacity)
## 4. Colony management (tax rates, auto-repair toggles)
## 5. Space Guild population transfers
## 6. Diplomatic actions
## 7. Scout detection escalations
## 8. Spy scout orders (join, move, rendezvous)
## 9. Auto-load cargo at colonies
## 10. Terraforming orders
## 11. Fleet orders (Move, Colonize, Patrol, etc.)
## 12. Squadron auto-balancing within fleets

import std/[tables, algorithm, options, random, sequtils, hashes, sets,
            strformat]
import ../../../common/types/core
import ../../../common/logger as common_logger
import ../../gamestate, ../../orders, ../../fleet, ../../squadron, ../../logger, ../../order_types
import ../../diplomacy/[types as dip_types]
import ../../commands/[executor, spy_scout_orders]
import ../[types as res_types, fleet_orders, economy_resolution,
           diplomatic_resolution, combat_resolution, simultaneous,
           commissioning, automation, construction]
import ../../standing_orders

proc resolveCommandPhase*(state: var GameState,
                          orders: Table[HouseId, OrderPacket],
                          combatReports: var seq[res_types.CombatReport],
                          events: var seq[res_types.GameEvent],
                          rng: var Rand) =
  ## Phase 3: Execute orders
  ## Commissioning happens FIRST to free up dock capacity before new builds
  logInfo("Resolve", "=== Command Phase ===", "turn=", $state.turn)

  # STEP 1: Commission completed projects from previous turn's Maintenance
  # This clears shipyard/spaceport dock capacity and makes ships available
  if state.pendingCommissions.len > 0:
    logInfo(LogCategory.lcEconomy, &"=== Commissioning Phase === ({state.pendingCommissions.len} projects)")
    commissioning.commissionCompletedProjects(state, state.pendingCommissions,
                                               events)
    state.pendingCommissions = @[]  # Clear after commissioning
  else:
    logDebug(LogCategory.lcEconomy, "No projects to commission this turn")

  # STEP 2: Colony automation (auto-loading, auto-repair, auto-squadron
  # balancing) - Uses newly-freed dock capacity and commissioned units
  automation.processColonyAutomation(state, orders)

  # STEP 3: Process build orders (new construction using freed capacity)
  for houseId in state.houses.keys:
    if houseId in orders:
      construction.resolveBuildOrders(state, orders[houseId], events)

  # Process colony management orders (tax rates, auto-repair toggles)
  for houseId in state.houses.keys:
    if houseId in orders:
      resolveColonyManagementOrders(state, orders[houseId])

  # Process Space Guild population transfers
  for houseId in state.houses.keys:
    if houseId in orders:
      resolvePopulationTransfers(state, orders[houseId], events)

  # Process diplomatic actions - MOVED TO MAINTENANCE PHASE
  # Diplomatic state changes happen AFTER all commands execute
  # See maintenance_step.nim for diplomatic action resolution

  # Process scout detection escalations (from Conflict Phase spy detections)
  # SpyScoutDetected events trigger Hostile escalation
  resolveScoutDetectionEscalations(state)

  # Process spy scout orders (join, move, rendezvous)
  # Spy scouts can merge with each other or with normal fleets
  spy_scout_orders.resolveSpyScoutOrders(state)

  # NOTE: Squadron management and cargo management are now handled by
  # zero-turn commands (src/engine/commands/zero_turn_commands.nim)
  # These execute immediately during order submission, not turn resolution

  # Auto-load cargo at colonies (if no manual cargo order exists)
  autoLoadCargo(state, orders, events)

  # Process terraforming orders
  for houseId in state.houses.keys:
    if houseId in orders:
      resolveTerraformOrders(state, orders[houseId], events)

  # ===================================================================
  # FLEET ORDER PROCESSING - PHASE-BASED EXECUTION
  # ===================================================================
  # Per FINAL_TURN_SEQUENCE.md:
  # - Combat orders (Bombard/Invade/Blitz): Queue for Turn N+1 Conflict Phase
  # - Movement orders (Move/SeekHome/Patrol): Execute in Turn N Maintenance Phase
  # - Administrative orders (Reserve/Mothball/etc): Execute immediately
  # - Special orders:
  #   * Colonize: Already handled by simultaneous resolution above
  #   * Salvage: Handled in Income Phase Step 4
  #   * Espionage: Handled in Conflict Phase

  logDebug(LogCategory.lcOrders, "[COMMAND PHASE] Processing fleet order submissions")

  # Clear previous turn's queued combat orders
  state.queuedCombatOrders = @[]

  # Collect and categorize orders from all houses
  for houseId in state.houses.keys:
    if houseId in orders:
      for order in orders[houseId].fleetOrders:
        # Queue combat orders for next turn's Conflict Phase
        if isCombatOrder(order.orderType):
          state.queuedCombatOrders.add(order)
          logDebug(LogCategory.lcOrders, &"  [QUEUED COMBAT] Fleet {order.fleetId}: {order.orderType} (executes Turn {state.turn + 1})")

        # Execute administrative orders immediately
        elif isAdministrativeOrder(order.orderType):
          let result = executor.executeFleetOrder(state, houseId, order)
          if result.success:
            logDebug(LogCategory.lcOrders, &"  [ADMIN] Fleet {order.fleetId}: {order.orderType} executed")
          else:
            logDebug(LogCategory.lcOrders, &"  [ADMIN FAILED] Fleet {order.fleetId}: {order.orderType} - {result.message}")

        # Movement orders execute in Maintenance Phase (don't process here)
        elif isMovementOrder(order.orderType):
          logDebug(LogCategory.lcOrders, &"  [MOVEMENT] Fleet {order.fleetId}: {order.orderType} (will execute in Maintenance Phase)")
          # Store in persistent orders so Maintenance Phase can find it
          state.fleetOrders[order.fleetId] = order

        # Special orders handled elsewhere
        elif isSpecialOrder(order.orderType):
          logDebug(LogCategory.lcOrders, &"  [SPECIAL] Fleet {order.fleetId}: {order.orderType} (handled by dedicated system)")
          # Colonize: simultaneous resolution above
          # Salvage: Income Phase Step 4
          # Espionage: Conflict Phase simultaneous resolution

  logDebug(LogCategory.lcOrders, &"[COMMAND PHASE] Queued {state.queuedCombatOrders.len} combat orders for next turn")

