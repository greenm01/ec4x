## Command Phase Resolution - Phase 3 of Canonical Turn Cycle
##
## Executes player order submissions and manages commissioning/automation cycles.
## This is the "player interaction" phase where orders are processed and queued.
##
## **Canonical Execution Order:**
##
## **Part A: Server Processing (BEFORE Player Window)**
## - Step 1: Starport & Shipyard Commissioning
## - Step 2: Colony Automation
##
## **Part B: Player Submission Window**
## - Zero-Turn Administrative Commands
## - Query Commands
## - Order Submission
##
## **Part C: Order Validation & Storage (AFTER Player Window)**
## - Administrative orders execute
## - All other orders: Validate and store in state.fleetOrders
## - Standing order configs: Validated and stored in state.standingOrders
## - Build orders: Add to construction queues
## - Tech research: Allocate RP
##
## **Key Properties:**
## - Commissioning happens FIRST to free dock capacity before new builds
## - Auto-repair can use newly-freed dock capacity from commissioning
## - Universal lifecycle: All orders follow same path (stored → activated → executed)
## - Admin orders execute immediately; all others stored for Maintenance Phase
## - Four-tier lifecycle: Initiate (Part B) → Validate (Part C) → Activate (Maintenance) → Execute (Conflict/Income)

import std/[tables, algorithm, options, random, sequtils, hashes, sets,
            strformat]
import ../../../common/types/core
import ../../../common/logger as common_logger
import ../../gamestate, ../../orders, ../../fleet, ../../squadron, ../../logger, ../../order_types
import ../../diplomacy/[types as dip_types]
import ../../commands/[executor]
import ../[types as res_types, fleet_orders, economy_resolution,
           diplomatic_resolution, combat_resolution, simultaneous,
           commissioning, automation, construction, order_cleanup]
import ../../research/[costs as res_costs]
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
  # STEP 0: ORDER CLEANUP FROM PREVIOUS TURN
  # ===================================================================
  # Clean up completed/failed/aborted orders based on events from previous turn
  # This runs BEFORE Part A to ensure standing orders can activate in Maintenance Phase
  # Per canonical turn cycle: Step 0 runs before commissioning/automation
  logInfo(LogCategory.lcOrders, "[COMMAND STEP 0] Cleaning up orders from previous turn...")
  order_cleanup.cleanFleetOrders(state, events)

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

  # Process colony management orders (tax rates, auto-repair toggles)
  for houseId in state.houses.keys:
    if houseId in orders:
      economy_resolution.resolveColonyManagementOrders(state, orders[houseId])

  # Process Space Guild population transfers
  for houseId in state.houses.keys:
    if houseId in orders:
      economy_resolution.resolvePopulationTransfers(state, orders[houseId], events)


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

  # Process build orders (new construction using freed capacity)
  logInfo(LogCategory.lcEconomy, "[BUILD ORDERS] Processing construction orders...")
  for houseId in state.houses.keys:
    if houseId in orders:
      construction.resolveBuildOrders(state, orders[houseId], events)

  # Process research allocation
  # Per economy.md:4.0: Players allocate PP to research each turn
  # PP is converted to ERP/SRP/TRP based on current tech levels and GHO
  for houseId in state.houses.keys:
    if houseId in orders:
      let packet = orders[houseId]
      let allocation = packet.researchAllocation

      # Calculate total PP cost for this research allocation
      var totalResearchCost = allocation.economic + allocation.science
      for field, pp in allocation.technology:
        totalResearchCost += pp

      # Scale down research allocation if treasury cannot afford it
      # Research is planned at AI time but processed after Income Phase
      # This prevents negative treasury from over-aggressive research budgets
      var scaledAllocation = allocation

      # CRITICAL: If treasury is negative or zero, no research happens
      if state.houses[houseId].treasury <= 0:
        # Zero out all research - house is bankrupt
        scaledAllocation.economic = 0
        scaledAllocation.science = 0
        scaledAllocation.technology = initTable[TechField, int]()
        totalResearchCost = 0

        logWarn(LogCategory.lcResearch,
          &"{houseId} research cancelled - negative treasury ({state.houses[houseId].treasury} PP)")

      elif totalResearchCost > state.houses[houseId].treasury:
        # Calculate scaling factor (how much we can actually afford)
        let affordablePercent = float(state.houses[houseId].treasury) / float(totalResearchCost)

        # Scale all allocations proportionally
        scaledAllocation.economic = int(float(allocation.economic) * affordablePercent)
        scaledAllocation.science = int(float(allocation.science) * affordablePercent)

        var scaledTech = initTable[TechField, int]()
        for field, pp in allocation.technology:
          scaledTech[field] = int(float(pp) * affordablePercent)
        scaledAllocation.technology = scaledTech

        # Recalculate actual cost
        totalResearchCost = scaledAllocation.economic + scaledAllocation.science
        for field, pp in scaledAllocation.technology:
          totalResearchCost += pp

        logWarn(LogCategory.lcResearch,
          &"{houseId} research budget scaled down by {int(affordablePercent * 100)}% due to treasury constraints")

      # Deduct research cost from treasury (CRITICAL FIX)
      # Research competes with builds for treasury resources
      if totalResearchCost > 0:
        state.houses[houseId].treasury -= totalResearchCost
        logInfo(LogCategory.lcResearch,
          &"{houseId} spent {totalResearchCost} PP on research " &
          &"(treasury: {state.houses[houseId].treasury + totalResearchCost} → {state.houses[houseId].treasury})")

      # Calculate GHO for this house
      var gho = 0
      for colony in state.colonies.values:
        if colony.owner == houseId:
          gho += colony.production

      # Get current tech levels
      let currentSL = state.houses[houseId].techTree.levels.scienceLevel  # Science Level

      # Convert PP allocations to RP (use SCALED allocation, not original)
      let earnedRP = res_costs.allocateResearch(scaledAllocation, gho, currentSL)

      # Accumulate RP
      state.houses[houseId].techTree.accumulated.economic += earnedRP.economic
      state.houses[houseId].techTree.accumulated.science += earnedRP.science

      for field, trp in earnedRP.technology:
        if field notin state.houses[houseId].techTree.accumulated.technology:
          state.houses[houseId].techTree.accumulated.technology[field] = 0
        state.houses[houseId].techTree.accumulated.technology[field] += trp

      # Save earned RP to House state for diagnostics tracking
      state.houses[houseId].lastTurnResearchERP = earnedRP.economic
      state.houses[houseId].lastTurnResearchSRP = earnedRP.science
      var totalTRP = 0
      for field, trp in earnedRP.technology:
        totalTRP += trp
      state.houses[houseId].lastTurnResearchTRP = totalTRP

      # Log allocations (use SCALED allocation for accurate reporting)
      if scaledAllocation.economic > 0:
        logDebug(LogCategory.lcResearch,
          &"{houseId} allocated {scaledAllocation.economic} PP → {earnedRP.economic} ERP " &
          &"(total: {state.houses[houseId].techTree.accumulated.economic} ERP)")
      if scaledAllocation.science > 0:
        logDebug(LogCategory.lcResearch,
          &"{houseId} allocated {scaledAllocation.science} PP → {earnedRP.science} SRP " &
          &"(total: {state.houses[houseId].techTree.accumulated.science} SRP)")
      for field, pp in scaledAllocation.technology:
        if pp > 0 and field in earnedRP.technology:
          let totalTRP = state.houses[houseId].techTree.accumulated.technology.getOrDefault(field, 0)
          logDebug(LogCategory.lcResearch,
            &"{houseId} allocated {pp} PP → {earnedRP.technology[field]} TRP ({field}) (total: {totalTRP} TRP)")

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

