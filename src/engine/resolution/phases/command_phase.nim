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
## **Part C: Order Validation & Storage**
## Universal lifecycle: All non-admin orders stored in state.fleetOrders
## - Validate all submitted orders (active orders and standing order configs)
## - Execute administrative orders immediately (Reserve, Mothball - zero-turn)
## - Store all other orders in state.fleetOrders for activation
## - Standing order configs validated, stored in state.standingOrders
##
## **Key Properties:**
## - Commissioning happens FIRST to free dock capacity before new builds
## - Auto-repair can use newly-freed dock capacity from commissioning
## - Universal lifecycle: All orders follow same path (stored → activated → executed)
## - No separate queues or special handling (DRY design)
## - Admin orders execute immediately; all others stored for Maintenance Phase
## - Four-tier lifecycle: Initiate (Part B) → Validate (Part C) → Activate (Maintenance) → Execute (Conflict/Income)

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
  # PART A: SHIP COMMISSIONING & AUTOMATION
  # ===================================================================
  # Commission ships from previous turn's Maintenance
  # This clears shipyard/spaceport dock capacity and makes ships available
  # (Planetary defense commissioned in Maintenance Phase Step 2b)
  logInfo(LogCategory.lcOrders, "[COMMAND PART A] Ship commissioning & automation...")
  if state.pendingMilitaryCommissions.len > 0:
    logInfo(LogCategory.lcEconomy, &"[COMMISSIONING] Processing {state.pendingMilitaryCommissions.len} ships")
    commissioning.commissionShips(state, state.pendingMilitaryCommissions,
                                   events)
    state.pendingMilitaryCommissions = @[]  # Clear after commissioning
  else:
    logInfo(LogCategory.lcEconomy, "[COMMISSIONING] No ships to commission this turn")

  # Colony automation (auto-loading, auto-repair, auto-squadron balancing)
  # Uses newly-freed dock capacity and commissioned units
  logInfo(LogCategory.lcEconomy, "[AUTOMATION] Processing colony automation...")
  automation.processColonyAutomation(state, orders)
  logInfo(LogCategory.lcOrders, "[COMMAND PART A] Completed ship commissioning & automation")

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
  diplomatic_resolution.resolveScoutDetectionEscalations(state, events)

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
  # PART C: ORDER VALIDATION & STORAGE
  # ===================================================================
  # Universal order lifecycle (applies to ALL orders):
  # - Initiate (Command Phase Part B): Player submits orders
  # - Validate (Command Phase Part C): Engine validates and stores orders ← THIS SECTION
  # - Activate (Maintenance Phase Step 1a): Orders become active, fleets start moving
  # - Execute (Conflict/Income Phase): Missions happen at targets
  #
  # Universal order processing (DRY design):
  # - Administrative orders: Validate & execute immediately (zero-turn)
  # - All other orders: Validate & store in state.fleetOrders
  #   * Move, Patrol, SeekHome, Hold
  #   * Bombard, Invade, Blitz, Guard*
  #   * Colonize, SpyPlanet, SpySystem, HackStarbase
  #   * Salvage
  # - Standing order configs: Validate & store in state.standingOrders
  #
  # Key principle: All non-admin orders follow same path → No special cases

  logInfo(LogCategory.lcOrders, "[COMMAND PART C] Validating and storing fleet orders...")

  # Clear legacy queue (no longer used, kept for compatibility)
  state.queuedCombatOrders = @[]

  var ordersStored = 0
  var adminExecuted = 0

  # Collect and categorize orders from all houses
  for houseId in state.houses.keys:
    if houseId in orders:
      for order in orders[houseId].fleetOrders:
        # Execute administrative orders immediately (zero-turn)
        if isAdministrativeOrder(order.orderType):
          let outcome = executor.executeFleetOrder(state, houseId, order, events)
          if outcome == OrderOutcome.Success:
            adminExecuted += 1
            logDebug(LogCategory.lcOrders, &"  [ADMIN] Fleet {order.fleetId}: {order.orderType} executed")
          else:
            logDebug(LogCategory.lcOrders, &"  [ADMIN FAILED] Fleet {order.fleetId}: {order.orderType}")

        # All other orders: store for movement and execution
        # Universal lifecycle: Initiate (here) → Activate (Maintenance) → Execute (Conflict/Income)
        else:
          state.fleetOrders[order.fleetId] = order
          ordersStored += 1
          logDebug(LogCategory.lcOrders, &"  [STORED] Fleet {order.fleetId}: {order.orderType}")

  logInfo(LogCategory.lcOrders, &"[COMMAND PART C] Completed ({ordersStored} orders stored, {adminExecuted} admin executed)")

