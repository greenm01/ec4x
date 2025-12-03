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
import ../../engine/commands/zero_turn_commands
import ../../engine/research/types as res_types
import ../common/types as ai_types
import ./[controller_types, budget, drungarius, eparch, tactical, strategic, protostrator, intelligence, logistics, standing_orders_manager, domestikos, logothete]
import ./config
import ./orders/[utils, phase0_intelligence, phase1_requirements, phase2_mediation, phase3_execution, phase4_feedback, colony_management]
import ./basileus/[personality, execution]  # For AdvisorType and centralized execution

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

proc generateAIOrders*(controller: var AIController, filtered: FilteredGameState, rng: var Rand): AIOrderSubmission =
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
      espionageAction: none(EspionageAttempt),
      ebpInvestment: 0,
      cipInvestment: 0
    )
  )

  let p = controller.personality
  let currentAct = ai_types.getCurrentGameAct(filtered.turn)

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

  # ==========================================================================
  # PHASE 1: MULTI-ADVISOR REQUIREMENT GENERATION
  # ==========================================================================
  generateAllAdvisorRequirements(controller, filtered, intelSnapshot, currentAct)

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

  let isUnderThreat = filtered.visibleFleets.anyIt(it.owner != controller.houseId)

  # Dynamic ETAC production based on fog-of-war visibility
  # Continue building ETACs as long as there are visible uncolonized systems
  # This scales with map size and adapts to intelligence gathered
  let uncolonizedSystemsVisible = intelligence.countUncolonizedSystems(filtered)
  let needETACs = case currentAct
    of ai_types.GameAct.Act1_LandGrab:
      # Act 1: Always build ETACs (land grab phase)
      uncolonizedSystemsVisible > 0
    of ai_types.GameAct.Act2_RisingTensions:
      # Act 2: Build ETACs if we see uncolonized systems (opportunistic expansion)
      uncolonizedSystemsVisible > 0
    else:
      # Act 3+: Stop ETAC production (focus on military/consolidation)
      false

  # NOTE: Scouts only useful in Act 2+ for espionage (spying on enemy colonies)
  # In Act 1, any ship can explore and reveal map, so scouts provide no advantage
  let needScouts = case currentAct
    of ai_types.GameAct.Act1_LandGrab: false  # Don't build scouts in Act 1 (any ship can explore)
    of ai_types.GameAct.Act2_RisingTensions: scoutCount < 7  # Build scouts for espionage
    else: scoutCount < 9  # More scouts for full ELI mesh coverage

  let needDefenses = cst >= 1
  let needFighters = true  # Engine handles tech-gating via ships.toml tech_level
  let needCarriers = cst >= 3
  let needTransports = cst >= 1 and p.aggression > 0.3
  let needRaiders = cst >= 2 and p.aggression > 0.5
  let canAffordMoreShips = allocation.budgets[AdvisorType.Domestikos] >= 50
  let atSquadronLimit = false

  result.orderPacket.buildOrders = generateBuildOrdersWithBudget(
    controller, filtered, filtered.ownHouse, myColonies, currentAct, p,
    isUnderThreat, needETACs, needDefenses, needScouts, needFighters,
    needCarriers, needTransports, needRaiders, canAffordMoreShips,
    atSquadronLimit, militaryCount, scoutCount, planetBreakerCount,
    allocation.budgets[AdvisorType.Domestikos],
    controller.domestikosRequirements
  )

  # ==========================================================================
  # PHASE 4: MULTI-ADVISOR FEEDBACK LOOP
  # ==========================================================================
  logInfo(LogCategory.lcAI,
          &"{controller.houseId} === Phase 4: Multi-Advisor Feedback Loop ===")

  const MAX_FEEDBACK_ITERATIONS = 3
  var feedbackIteration = 0

  while hasUnfulfilledCriticalOrHigh(controller) and feedbackIteration < MAX_FEEDBACK_ITERATIONS:
    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Feedback iteration {feedbackIteration + 1}/{MAX_FEEDBACK_ITERATIONS} - " &
            &"unfulfilled: {getUnfulfilledSummary(controller)}")

    # Reprioritize all advisors
    reprioritizeAllAdvisors(controller)

    # Re-run mediation with adjusted priorities
    allocation = mediateAndAllocateBudget(controller, filtered, currentAct)

    # Re-execute requirements (via Basileus)
    let researchBudgetFeedback = allocation.budgets.getOrDefault(controller_types.AdvisorType.Logothete, 0)
    result.orderPacket.researchAllocation = execution.executeResearchAllocation(controller, filtered, researchBudgetFeedback)
    result.orderPacket.espionageAction = executeEspionageAction(controller, filtered, allocation, rng)
    result.orderPacket.terraformOrders = executeTerraformOrders(controller, filtered, allocation, rng)
    result.orderPacket.diplomaticActions = execution.executeDiplomaticActions(controller, filtered)

    # Re-execute build orders
    result.orderPacket.buildOrders = generateBuildOrdersWithBudget(
      controller, filtered, filtered.ownHouse, myColonies, currentAct, p,
      isUnderThreat, needETACs, needDefenses, needScouts, needFighters,
      needCarriers, needTransports, needRaiders, canAffordMoreShips,
      atSquadronLimit, militaryCount, scoutCount, planetBreakerCount,
      allocation.budgets[AdvisorType.Domestikos],
      controller.domestikosRequirements
    )

    feedbackIteration += 1

  if feedbackIteration > 0:
    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Feedback loop converged after {feedbackIteration} iterations")
  else:
    logInfo(LogCategory.lcAI,
            &"{controller.houseId} No feedback loop needed (all Critical/High requirements fulfilled)")

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

  # Convert strategic standing orders to explicit fleet orders
  var strategicOrdersConverted = 0
  for fleetId, standingOrder in standingOrders:
    if standingOrder.orderType in {StandingOrderType.DefendSystem, StandingOrderType.AutoRepair}:
      var fleetOpt: Option[Fleet] = none(Fleet)
      for f in filtered.ownFleets:
        if f.id == fleetId:
          fleetOpt = some(f)
          break

      if fleetOpt.isSome:
        let fleet = fleetOpt.get()
        let orderOpt = convertStandingOrderToFleetOrder(standingOrder, fleet, filtered)

        if orderOpt.isSome:
          result.orderPacket.fleetOrders.add(orderOpt.get())
          strategicOrdersConverted += 1

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Converted {strategicOrdersConverted} strategic standing orders")

  # ==========================================================================
  # PHASE 7: TACTICAL FLEET ORDERS
  # ==========================================================================
  let tacticalOrders = generateFleetOrders(controller, filtered, rng)

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
  logInfo(LogCategory.lcAI,
          &"{controller.houseId}   Terraform orders: {result.orderPacket.terraformOrders.len}")
  logInfo(LogCategory.lcAI,
          &"{controller.houseId} ========================================")

  return result
