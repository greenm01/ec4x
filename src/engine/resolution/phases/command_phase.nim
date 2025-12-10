## Command Phase Resolution - Phase 3 of Canonical Turn Cycle
##
## Executes player order submissions and manages commissioning/automation cycles.
## This is the "player interaction" phase where orders are processed and queued.
##
## **Canonical Execution Order:**
##
## **Part A: Commissioning & Automation**
## - Commission completed projects from state.pendingCommissions
##   (projects completed in previous turn's Maintenance Phase)
## - Auto-create squadrons, auto-assign to fleets
## - Auto-load PTUs onto ETAC ships (1 PTU per ETAC)
## - Colony automation:
##   * Auto-load fighters to carriers (if colony.autoLoadingEnabled)
##   * Auto-submit repair orders (if colony.autoRepairEnabled)
##   * Auto-balance squadrons across fleets (always enabled)
##
## **Part B: Player Submission Window** (24-hour window in multiplayer mode)
## - Process build orders (construction, research allocation)
## - Process colony management orders (tax rates, automation toggles)
## - Process Space Guild population transfers
## - Process diplomatic actions (proposals, treaty modifications)
## - Process spy scout orders (join, move, rendezvous)
## - Process terraforming orders
## - Process zero-turn administrative commands (immediate execution)
##
## **Part C: Order Processing** (categorization & queueing)
## - Queue combat orders for Turn N+1 Conflict Phase
## - Execute administrative orders immediately (Reserve, Mothball, etc.)
## - Store movement orders for Turn N Maintenance Phase execution
## - Store special orders for dedicated phase handlers
##
## **Key Properties:**
## - Commissioning happens FIRST to free dock capacity before new builds
## - Auto-repair can use newly-freed dock capacity from commissioning
## - Combat orders execute Turn N+1 (next Conflict Phase)
## - Movement orders execute Turn N (this turn's Maintenance Phase)

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
  logInfo(LogCategory.lcOrders, &"=== Command Phase === (turn={state.turn})")

  # ===================================================================
  # PART A: COMMISSIONING & AUTOMATION
  # ===================================================================
  # Commission military units from previous turn's Maintenance
  # This clears shipyard/spaceport dock capacity and makes ships available
  # (Planetary defense commissioned in Maintenance Phase same turn)
  logInfo(LogCategory.lcOrders, "[COMMAND PART A] Commissioning & automation...")
  if state.pendingMilitaryCommissions.len > 0:
    logInfo(LogCategory.lcEconomy, &"[COMMISSIONING] Processing {state.pendingMilitaryCommissions.len} military units")
    commissioning.commissionMilitaryUnits(state, state.pendingMilitaryCommissions,
                                           events)
    state.pendingMilitaryCommissions = @[]  # Clear after commissioning
  else:
    logInfo(LogCategory.lcEconomy, "[COMMISSIONING] No military units to commission this turn")

  # Colony automation (auto-loading, auto-repair, auto-squadron balancing)
  # Uses newly-freed dock capacity and commissioned units
  logInfo(LogCategory.lcEconomy, "[AUTOMATION] Processing colony automation...")
  automation.processColonyAutomation(state, orders)
  logInfo(LogCategory.lcOrders, "[COMMAND PART A] Completed commissioning & automation")

  # ===================================================================
  # PART B: PLAYER SUBMISSION WINDOW (simulated by AI)
  # ===================================================================
  # In multiplayer, this would be the window where players submit orders
  # In AI mode, orders are pre-computed and passed to this function
  logInfo(LogCategory.lcOrders, "[COMMAND PART B] Processing player submissions...")

  # Process build orders (new construction using freed capacity)
  logInfo(LogCategory.lcEconomy, "[BUILD ORDERS] Processing construction orders...")
  for houseId in state.houses.keys:
    if houseId in orders:
      construction.resolveBuildOrders(state, orders[houseId], events)

  # Process colony management orders (tax rates, auto-repair toggles)
  for houseId in state.houses.keys:
    if houseId in orders:
      economy_resolution.resolveColonyManagementOrders(state, orders[houseId])

  # Process Space Guild population transfers
  for houseId in state.houses.keys:
    if houseId in orders:
      economy_resolution.resolvePopulationTransfers(state, orders[houseId], events)

  # Process scout detection escalations (from Conflict Phase spy detections)
  # SpyScoutDetected events trigger Hostile escalation
  diplomatic_resolution.resolveScoutDetectionEscalations(state)

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

  logInfo(LogCategory.lcOrders, "[COMMAND PART B] Completed player submissions")

  # ===================================================================
  # PART C: ORDER PROCESSING (categorization & queueing)
  # ===================================================================
  # Per FINAL_TURN_SEQUENCE.md:
  # - Combat orders (Bombard/Invade/Blitz): Queue for Turn N+1 Conflict Phase
  # - Movement orders (Move/SeekHome/Patrol): Execute in Turn N Maintenance Phase
  # - Administrative orders (Reserve/Mothball/etc): Execute immediately
  # - Special orders:
  #   * Colonize: Already handled by simultaneous resolution above
  #   * Salvage: Handled in Income Phase Step 4
  #   * Espionage: Handled in Conflict Phase

  logInfo(LogCategory.lcOrders, "[COMMAND PART C] Processing fleet order submissions...")

  # Clear previous turn's queued combat orders
  state.queuedCombatOrders = @[]

  var combatQueued = 0
  var movementQueued = 0
  var adminExecuted = 0

  # Collect and categorize orders from all houses
  for houseId in state.houses.keys:
    if houseId in orders:
      for order in orders[houseId].fleetOrders:
        # Queue combat orders for next turn's Conflict Phase
        if isCombatOrder(order.orderType):
          state.queuedCombatOrders.add(order)
          combatQueued += 1
          logDebug(LogCategory.lcOrders, &"  [QUEUED COMBAT] Fleet {order.fleetId}: {order.orderType} (executes Turn {state.turn + 1})")

        # Execute administrative orders immediately
        elif isAdministrativeOrder(order.orderType):
          let outcome = executor.executeFleetOrder(state, houseId, order, events)
          if outcome == OrderOutcome.Success:
            adminExecuted += 1
            logDebug(LogCategory.lcOrders, &"  [ADMIN] Fleet {order.fleetId}: {order.orderType} executed")
          else:
            logDebug(LogCategory.lcOrders, &"  [ADMIN FAILED] Fleet {order.fleetId}: {order.orderType}")

        # Movement orders execute in Maintenance Phase (don't process here)
        elif isMovementOrder(order.orderType):
          movementQueued += 1
          logDebug(LogCategory.lcOrders, &"  [MOVEMENT] Fleet {order.fleetId}: {order.orderType} (will execute in Maintenance Phase)")
          # Store in persistent orders so Maintenance Phase can find it
          state.fleetOrders[order.fleetId] = order

        # Special orders handled elsewhere
        elif isSpecialOrder(order.orderType):
          logDebug(LogCategory.lcOrders, &"  [SPECIAL] Fleet {order.fleetId}: {order.orderType} (handled by dedicated system)")
          # Colonize: simultaneous resolution above
          # Salvage: Income Phase Step 4
          # Espionage: Conflict Phase simultaneous resolution

  logInfo(LogCategory.lcOrders, &"[COMMAND PART C] Completed (combat queued: {combatQueued}, movement queued: {movementQueued}, admin executed: {adminExecuted})")

