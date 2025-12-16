## RBA Orders Module - Byzantine Imperial Government
##
## Main orchestrator for multi-advisor order generation with full Basileus integration
##
## Architecture:
## Phase 0: Intelligence Distribution (Drungarius hub)
## Phase 1: Requirement Generation (all 6 advisors)
## Phase 2: Basileus Mediation & Budget Allocation (Treasurer)
## Phase 3: Requirement Execution
## Phase 4: Multi-Advisor Feedback Loop (max 3 iterations)
## Phase 5+: Fleet Operations, Logistics, Standing Orders (unchanged)

import std/[tables, options, random, sequtils, sets, strformat]
import ../../common/types/[core, tech, units]
import ../../engine/[gamestate, fog_of_war, orders, logger, fleet]
import ../../engine/resolution/types as event_types # Use engine/resolution/types for GameEvent
import ../../engine/commands/zero_turn_commands
import ../../engine/research/types as res_types
import ../common/types as ai_types
import ./[controller_types, budget, drungarius, tactical, intelligence, logistics, standing_orders_manager, logothete, fleet_organization]
import ./orders/[phase0_intelligence, phase1_requirements, phase1_5_goap, phase2_mediation, phase3_execution, colony_management, phase4_feedback]
import ./goap/integration/plan_tracking  # For addPlan
import ./basileus/execution  # For AdvisorType and centralized execution
import ./domestikos/fleet_analysis  # For GOAP plan execution

export core, orders, standing_orders_manager, zero_turn_commands

type
  AIOrderSubmission* = object
    ## Complete AI order submission containing both zero-turn commands and order packet
    ##
    ## Zero-turn commands execute immediately during order submission (0 turns)
    ## Order packet is queued for normal turn resolution
    ##
    ## Processing order:
    ## 1. Execute zeroTurnCommands first (immediate, at friendly colonies)
    ## 2. Submit orderPacket for turn resolution queue
    zeroTurnCommands*: seq[ZeroTurnCommand]  # Execute first
    orderPacket*: OrderPacket                # Execute after

proc generateAIOrders*(controller: var AIController, filtered: FilteredGameState, rng: var Rand, events: seq[GameEvent]): AIOrderSubmission =
  ## Generate complete AI order submission using Byzantine Imperial Government structure
  ##
  ## Returns both zero-turn commands (immediate execution) and order packet (turn resolution)
  ## Multi-advisor coordination with Basileus mediation and feedback loops

  result = AIOrderSubmission(
    zeroTurnCommands: @[],
    orderPacket: OrderPacket(
      houseId: controller.houseId,
      turn: filtered.turn,
      treasury: filtered.ownHouse.treasury,
      fleetOrders: @[],
      buildOrders: @[],
      researchAllocation: res_types.ResearchAllocation(
        economic: 0,
        science: 0,
        technology: initTable[TechField, int]()
      ),
      diplomaticActions: @[],
      populationTransfers: @[],
      terraformOrders: @[],
      colonyManagement: @[],
      standingOrders: initTable[FleetId, StandingOrder](),
      espionageAction: none(EspionageAttempt),
      ebpInvestment: 0,
      cipInvestment: 0
    )
  )

  let p = controller.personality

  # Calculate total colonized systems from public leaderboard
  # Get current act from game state (updated during turn resolution)
  var currentAct: gamestate.GameAct = filtered.actProgression.currentAct

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} ========================================")
  logInfo(LogCategory.lcAI,
          &"{controller.houseId} === BYZANTINE IMPERIAL GOVERNMENT ===")
  logInfo(LogCategory.lcAI,
          &"{controller.houseId} === Turn {filtered.turn}, Act {currentAct} ===")
  logInfo(LogCategory.lcAI,
          &"{controller.houseId} ========================================")

  # ==========================================================================
  # PHASE 0: INTELLIGENCE DISTRIBUTION
  # ==========================================================================
  let intelSnapshot = generateIntelligenceSnapshot(filtered, controller)

  # Store intelligence snapshot in controller for advisor access
  controller.intelligenceSnapshot = some(intelSnapshot)

  # ==========================================================================
  # PHASE 1: MULTI-ADVISOR REQUIREMENT GENERATION
  # ==========================================================================
  generateAllAdvisorRequirements(controller, filtered, intelSnapshot, currentAct)

  # ==========================================================================
  # PHASE 1.5: GOAP STRATEGIC PLANNING (if enabled)
  # ==========================================================================
  if controller.goapEnabled:
    logInfo(LogCategory.lcAI, &"{controller.houseId} === Phase 1.5: GOAP Planning ===")

    let phase15Result = phase1_5_goap.executePhase15_GOAP(
      controller,
      filtered,
      intelSnapshot,
      controller.goapConfig
    )

    # Store results for potential Phase 2 integration
    controller.goapBudgetEstimates = some(phase15Result.budgetEstimates)
    controller.goapActiveGoals = phase15Result.plans.mapIt(it.goal.description)
    controller.goapLastPlanningTurn = filtered.turn

    # Add plans to tracker
    for plan in phase15Result.plans:
      controller.goapPlanTracker.addPlan(plan)

  # ==========================================================================
  # PHASE 2: BASILEUS MEDIATION & BUDGET ALLOCATION
  # ==========================================================================
  var allocation = mediateAndAllocateBudget(controller, filtered, currentAct)

  # ==========================================================================
  # PHASE 3: REQUIREMENT EXECUTION
  # ==========================================================================
  logInfo(LogCategory.lcAI,
          &"{controller.houseId} === Phase 3: Requirement Execution ===")

  # Execute research allocation (via Basileus)
  let researchBudget = allocation.budgets.getOrDefault(controller_types.AdvisorType.Logothete, 0)
  result.orderPacket.researchAllocation = execution.executeResearchAllocation(controller, filtered, researchBudget)

  # Execute espionage action
  result.orderPacket.espionageAction = executeEspionageAction(controller, filtered, allocation, rng)

  # Set EBP/CIP investment from allocation
  # Extract from Drungarius requirements
  if controller.drungariusRequirements.isSome:
    for req in controller.drungariusRequirements.get().requirements:
      case req.requirementType
      of EspionageRequirementType.EBPInvestment:
        result.orderPacket.ebpInvestment += req.estimatedCost
      of EspionageRequirementType.CIPInvestment:
        result.orderPacket.cipInvestment += req.estimatedCost
      else:
        discard

  # Execute terraform orders
  result.orderPacket.terraformOrders = executeTerraformOrders(controller, filtered, allocation, rng)

  # Execute diplomatic actions (via Basileus)
  result.orderPacket.diplomaticActions = execution.executeDiplomaticActions(controller, filtered)

  # Execute build orders (using existing budget module for now)
  # TODO: Refactor budget.nim to use Domestikos requirements directly
  let myColonies = getOwnedColonies(filtered, controller.houseId)
  let cst = filtered.ownHouse.techTree.levels.constructionTech

  # Context flags for build system (compatibility with existing code)
  var militaryCount = 0
  var scoutCount = 0
  var planetBreakerCount = 0
  for fleet in filtered.ownFleets:
    for squadron in fleet.squadrons:
      if squadron.flagship.shipClass == ShipClass.Scout:
        scoutCount += 1
      elif squadron.flagship.shipClass == ShipClass.PlanetBreaker:
        planetBreakerCount += 1
      else:
        militaryCount += 1

  # ==========================================================================
  # PHASE 3/4: UNIFIED FEEDBACK LOOP
  # ==========================================================================
  # FIX: Requirements now processed once per iteration (not duplicated)
  # Feedback loop always runs at least once to generate orders
  # Subsequent iterations reprioritize and regenerate if needed
  # ==========================================================================
  logInfo(LogCategory.lcAI,
          &"{controller.houseId} === Phase 3/4: Feedback Loop (Unified) ===")

  const MAX_FEEDBACK_ITERATIONS = 3
  var feedbackIteration = 0

  # Loop condition: Always run once (feedbackIteration == 0), then continue if unfulfilled Critical/High
  while feedbackIteration == 0 or
        (hasUnfulfilledCriticalOrHigh(controller) and feedbackIteration < MAX_FEEDBACK_ITERATIONS):

    if feedbackIteration > 0:
      # Iterations 2-3: Reprioritize and reallocate budget
      logInfo(LogCategory.lcAI,
              &"{controller.houseId} Feedback iteration {feedbackIteration + 1}/{MAX_FEEDBACK_ITERATIONS} - " &
              &"unfulfilled: {getUnfulfilledSummary(controller)}")

      # Reprioritize all advisors (budget-aware with substitution)
      let cstLevel = filtered.ownHouse.techTree.levels.constructionTech
      reprioritizeAllAdvisors(controller, filtered.ownHouse.treasury, cstLevel)

      # Re-run mediation with adjusted priorities
      allocation = mediateAndAllocateBudget(controller, filtered, currentAct)
    else:
      # First iteration: Use initial priorities and budget allocation
      logInfo(LogCategory.lcAI,
              &"{controller.houseId} Feedback iteration 1/{MAX_FEEDBACK_ITERATIONS} (initial pass)")

    # Execute ALL advisor orders (research, espionage, terraform, diplomacy, build)
    # Each iteration processes with current priorities and budget allocation
    let researchBudgetFeedback = allocation.budgets.getOrDefault(controller_types.AdvisorType.Logothete, 0)
    result.orderPacket.researchAllocation = execution.executeResearchAllocation(controller, filtered, researchBudgetFeedback)
    result.orderPacket.espionageAction = executeEspionageAction(controller, filtered, allocation, rng)
    result.orderPacket.terraformOrders = executeTerraformOrders(controller, filtered, allocation, rng)
    result.orderPacket.diplomaticActions = execution.executeDiplomaticActions(controller, filtered)

    # Execute build orders (ships, buildings, ground units)
    # Use Treasurer's mediation feedback - no re-calculation (DRY principle)
    var buildOrders = generateBuildOrdersWithBudget(
      controller, filtered, filtered.ownHouse, myColonies, currentAct, p,
      allocation.budgets[AdvisorType.Domestikos],
      allocation.treasurerFeedback  # From multi-advisor mediation
    )

    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Domestikos build orders: {buildOrders.len}")

    # Append facility orders from Eparch (Shipyards/Spaceports)
    let facilityOrdersLoop = executeFacilityOrders(controller, filtered, allocation)
    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Eparch facility orders: {facilityOrdersLoop.len}")

    buildOrders.add(facilityOrdersLoop)

    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Total build orders after Eparch: {buildOrders.len}")

    result.orderPacket.buildOrders = buildOrders

    feedbackIteration += 1

  if feedbackIteration > 1:
    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Feedback loop converged after {feedbackIteration} iterations")
  else:
    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Feedback loop complete (no reprioritization needed)")

  # ==========================================================================
  # PHASE 5: STRATEGIC OPERATIONS PLANNING
  # ==========================================================================
  # Act-aware invasion planning (user preference: undefended only in Act 1)
  let allowInvasions = case currentAct
    of ai_types.GameAct.Act1_LandGrab:
      false  # Will be conditionally allowed in identifyInvasionOpportunities
    else:
      p.aggression > 0.4

  if allowInvasions or currentAct == ai_types.GameAct.Act1_LandGrab:
    let invasionTargets = identifyInvasionOpportunities(controller, filtered, currentAct)

    for targetSystem in invasionTargets:
      var alreadyTargeted = false
      for op in controller.operations:
        if op.targetSystem == targetSystem:
          alreadyTargeted = true
          break

      if not alreadyTargeted:
        planCoordinatedInvasion(controller, filtered, targetSystem, filtered.turn)

  # ==========================================================================
  # PHASE 6: STANDING ORDERS ASSIGNMENT
  # ==========================================================================
  logInfo(LogCategory.lcAI,
          &"{controller.houseId} === Standing Orders Assignment ===")

  let standingOrders = assignStandingOrders(controller, filtered, filtered.turn)
  controller.standingOrders = standingOrders

  # Add standing orders to order packet so they're written to GameState
  result.orderPacket.standingOrders = standingOrders

  # TODO: Add Logistics-generated build requirements (e.g., for Drydocks) to Domestikos requirements
  # Commented out - AIOrderSubmission doesn't have buildRequirements field
  # if result.buildRequirements.len > 0:
  #   if controller.domestikosRequirements.isNone:
  #     controller.domestikosRequirements = some(BuildRequirements(requirements: @[], totalEstimatedCost: 0))
  #   controller.domestikosRequirements.get().requirements.add(result.buildRequirements)
  #   logInfo(LogCategory.lcAI,
  #           &"{controller.houseId} Logistics added {result.buildRequirements.len} build requirements (e.g., Drydocks)")

  # NOTE: Standing orders are now handled by engine's standing order system
  # They're submitted via orderPacket.standingOrders and activate in Maintenance Phase
  # RBA no longer converts standing orders to fleet orders - engine handles activation
  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Assigned {standingOrders.len} standing orders (engine will activate in Maintenance Phase)")

  # ==========================================================================
  # PHASE 6.5: GOAP PLAN EXECUTION (Phase 3 Integration)
  # ==========================================================================
  # Execute active GOAP plans (strategic multi-turn operations)
  # Priority: GOAP plans > RBA campaigns > RBA tactical
  if controller.goapEnabled and controller.goapPlanTracker.getActivePlanCount() > 0:
    logInfo(LogCategory.lcAI,
            &"{controller.houseId} === Phase 6.5: GOAP Plan Execution ===")

    # Analyze fleets for plan execution
    let analyses = fleet_analysis.analyzeFleetUtilization(
      filtered,
      controller.houseId,
      initTable[FleetId, FleetOrder](),  # No tactical orders yet
      controller.standingOrders
    )

    # Execute all active plans
    let goapOrders = plan_tracking.executeAllPlans(
      controller.goapPlanTracker,
      filtered,
      analyses
    )

    logInfo(LogCategory.lcAI,
            &"{controller.houseId} GOAP generated {goapOrders.len} strategic orders")

    # Add GOAP orders with highest priority
    for order in goapOrders:
      result.orderPacket.fleetOrders.add(order)

  # ==========================================================================
  # PHASE 6.9: ETAC COLONIZATION ORDERS
  # ==========================================================================
  # Execute ETAC colonization orders generated by Eparch in Phase 1
  # Eparch is single source of truth for all expansion operations
  logInfo(LogCategory.lcAI,
          &"{controller.houseId} === Phase 6.9: ETAC Colonization (Eparch) ===")

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Eparch generated {controller.eparchColonizationOrders.len} colonization orders")

  for order in controller.eparchColonizationOrders:
    result.orderPacket.fleetOrders.add(order)

  # ==========================================================================
  # PHASE 7: TACTICAL FLEET ORDERS
  # ==========================================================================
  # Pass standingOrders so tactical knows which fleets have standing orders (skip those fleets)
  # No need to pass alreadyTargeted - engine coordinates ETAC targets during standing order activation
  let tacticalOrders = generateFleetOrders(controller, filtered, rng, standingOrders, initHashSet[SystemId]())

  for order in tacticalOrders:
    result.orderPacket.fleetOrders.add(order)

  # ==========================================================================
  # PHASE 7.5: COLONY MANAGEMENT (Auto-repair, tax rates)
  # ==========================================================================
  let colonyOrders = colony_management.generateColonyManagementOrders(controller, filtered, currentAct)
  result.orderPacket.colonyManagement = colonyOrders

  # ==========================================================================
  # PHASE 8: LOGISTICS OPTIMIZATION
  # ==========================================================================
  logInfo(LogCategory.lcAI,
          &"{controller.houseId} === Logistics Optimization ===")

  let logisticsOrders = logistics.generateLogisticsOrders(controller, filtered, currentAct)

  # Convert deprecated cargo/squadron orders to zero-turn commands
  # These will be executed by game loop BEFORE OrderPacket processing
  let cargoCommands = logistics.convertCargoToZeroTurnCommands(logisticsOrders.cargo)
  let squadronCommands = logistics.convertSquadronToZeroTurnCommands(logisticsOrders.squadrons)

  # Populate zero-turn commands for execution
  result.zeroTurnCommands.add(cargoCommands)
  result.zeroTurnCommands.add(squadronCommands)

  # Add Domestikos fleet management commands (merge/detach/transfer)
  # Generated in Phase 1 by generateAllAdvisorRequirements()
  result.zeroTurnCommands.add(controller.fleetManagementCommands)

  # Comprehensive fleet organization at colonies
  # Detach ETACs, assign squadrons, load cargo, merge undersized fleets
  let fleetOrgCommands = fleet_organization.organizeFleets(controller, filtered)
  result.zeroTurnCommands.add(fleetOrgCommands)

  # Unload cargo from ETACs at colonies (before salvage or after arriving)
  # Two cases:
  # 1. ETAC at colony with Salvage order → unload then salvage
  # 2. ETAC at colony with Move/Hold order (arrived) → unload, next turn salvage
  for fleet in filtered.ownFleets:
    # Check if this is an ETAC at a colony
    let atColony = fleet.location in filtered.ownColonies.mapIt(it.systemId)
    if not atColony:
      continue

    # Check if has cargo to unload
    var totalPTU = 0
    for ship in fleet.spaceLiftShips:
      if ship.cargo.cargoType == CargoType.Colonists and ship.cargo.quantity > 0:
        totalPTU += ship.cargo.quantity

    if totalPTU == 0:
      continue  # No cargo to unload

    # Check if this ETAC has orders that indicate it's ready for salvage
    # (Salvage order already issued, or Move/Hold at colony after 100% colonization)
    let hasOrderAtColony = fleet.id in filtered.ownFleetOrders
    if hasOrderAtColony:
      let order = filtered.ownFleetOrders[fleet.id]
      # Unload if:
      # - Has Salvage order (ready to salvage after unload)
      # - Has Move/Hold at colony (arrived, will get Salvage next turn)
      if order.orderType in {FleetOrderType.Salvage, FleetOrderType.Move, FleetOrderType.Hold}:
        # Check if colonization is complete (indicates this is salvage-related)
        let totalSystems = filtered.starMap.systems.len
        var totalColonized = 0
        for houseId, colonyCount in filtered.houseColonies:
          totalColonized += colonyCount
        let colonizationComplete = totalColonized >= totalSystems

        if colonizationComplete:
          # Generate unload command for this ETAC
          let unloadCmd = ZeroTurnCommand(
            houseId: controller.houseId,
            commandType: ZeroTurnCommandType.UnloadCargo,
            sourceFleetId: some(fleet.id)
          )
          result.zeroTurnCommands.add(unloadCmd)
          logInfo(LogCategory.lcAI,
                  &"{controller.houseId} ETAC {fleet.id} at colony unloading {totalPTU} PTU " &
                  &"(order: {order.orderType}, colonization: {totalColonized}/{totalSystems})")

  # Population transfers still use OrderPacket (not deprecated)
  result.orderPacket.populationTransfers = logisticsOrders.population

  # Remove tactical orders for fleets that logistics is managing
  var logisticsControlledFleets: HashSet[FleetId]
  for order in logisticsOrders.fleetOrders:
    logisticsControlledFleets.incl(order.fleetId)

  var filteredTacticalOrders: seq[FleetOrder] = @[]
  for order in result.orderPacket.fleetOrders:
    if order.fleetId notin logisticsControlledFleets:
      filteredTacticalOrders.add(order)

  result.orderPacket.fleetOrders = filteredTacticalOrders
  result.orderPacket.fleetOrders.add(logisticsOrders.fleetOrders)
  result.orderPacket.fleetOrders.add(controller.offensiveFleetOrders)  # Add Domestikos offensive operations

  # ==========================================================================
  # SUMMARY
  # ==========================================================================
  logInfo(LogCategory.lcAI,
          &"{controller.houseId} ========================================")
  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Order generation complete:")
  logInfo(LogCategory.lcAI,
          &"{controller.houseId}   Zero-turn commands: {result.zeroTurnCommands.len}")
  logInfo(LogCategory.lcAI,
          &"{controller.houseId}   Fleet orders: {result.orderPacket.fleetOrders.len}")
  logInfo(LogCategory.lcAI,
          &"{controller.houseId}   Build orders: {result.orderPacket.buildOrders.len}")
  logInfo(LogCategory.lcAI,
          &"{controller.houseId}   Research: EL={result.orderPacket.researchAllocation.economic}PP, " &
          &"SL={result.orderPacket.researchAllocation.science}PP")
  logInfo(LogCategory.lcAI,
          &"{controller.houseId}   Espionage: EBP={result.orderPacket.ebpInvestment}PP, CIP={result.orderPacket.cipInvestment}PP")
  # ==========================================================================
  # PHASE 8.5: REPORT GOAP PROGRESS (RBA -> GOAP Feedback)
  # ==========================================================================
  if controller.goapEnabled:
    logInfo(LogCategory.lcAI, &"{controller.houseId} === Phase 8.5: GOAP Feedback ===")

    phase4_feedback.reportGOAPProgress(
      controller,
      allocation,
      filtered.turn,
      intelSnapshot
    )

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} ========================================")
  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Order generation complete:")
  logInfo(LogCategory.lcAI,
          &"{controller.houseId}   Zero-turn commands: {result.zeroTurnCommands.len}")
  logInfo(LogCategory.lcAI,
          &"{controller.houseId}   Fleet orders: {result.orderPacket.fleetOrders.len}")
  logInfo(LogCategory.lcAI,
          &"{controller.houseId}   Build orders: {result.orderPacket.buildOrders.len}")
  logInfo(LogCategory.lcAI,
          &"{controller.houseId}   Research: EL={result.orderPacket.researchAllocation.economic}PP, " &
          &"SL={result.orderPacket.researchAllocation.science}PP")
  logInfo(LogCategory.lcAI,
          &"{controller.houseId}   Espionage: EBP={result.orderPacket.ebpInvestment}PP, CIP={result.orderPacket.cipInvestment}PP")
  logInfo(LogCategory.lcAI,
          &"{controller.houseId}   Terraform orders: {result.orderPacket.terraformOrders.len}")
  logInfo(LogCategory.lcAI,
          &"{controller.houseId} ========================================")

  # Store allocation result for diagnostics (budget flow verification)
  controller.lastTurnAllocationResult = some(allocation)

  return result
