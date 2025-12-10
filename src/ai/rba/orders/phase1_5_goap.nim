## RBA Phase 1.5: GOAP Strategic Planning
##
## Inserted between Phase 1 (Requirements) and Phase 2 (Mediation)
## Extracts strategic goals from world state and generates multi-turn plans
##
## Integration Point:
## - Input: FilteredGameState, IntelligenceSnapshot, Requirements from Phase 1
## - Output: GOAPlan seq, enhanced requirements with cost estimates
## - Called by: order_generation.nim between phase1 and phase2

import std/[tables, options, sequtils, algorithm, times] # Add times for cpuTime()
import ../goap/core/types
import ../goap/state/snapshot as goap_snapshot # Alias to avoid name clashes
import ../goap/planner/search
import ../goap/integration/[conversion, plan_tracking, replanning] # Added replanning for ReplanReason
import ../controller_types # For UnfulfillmentReason, RequirementFeedback
import ../../common/types as ai_types
import ../../../common/types/core
import ../../../engine/[gamestate, fog_of_war, logger, research/types as res_types] # Added res_types for TechField parsing
import ../config # Import RBA config for GOAPConfig

export goap_snapshot.createWorldStateSnapshot # Export it for other phases to use

# =============================================================================
# Phase 1.5: Goal Extraction
# =============================================================================

proc extractStrategicGoals*(
  houseId: HouseId, # Pass houseId for snapshot creation
  homeworld: SystemId, # Pass homeworld for snapshot creation
  currentTurn: int, # Pass current turn for snapshot creation
  intel: IntelligenceSnapshot,
  config: GOAPConfig
): seq[Goal] =
  ## Extract all strategic goals from current game state
  ##
  ## This is the main entry point for GOAP in RBA cycle
  ## Called after Phase 1 (Requirements generation)

  # Convert to WorldStateSnapshot for GOAP
  let worldState = createWorldStateSnapshot(houseId, homeworld, currentTurn, config, intel)

  # Extract goals from all domains
  var allGoals = extractAllGoalsFromState(worldState)

  # Apply priority weights from config
  for i in 0 ..< allGoals.len:
    case allGoals[i].goalType
    # Defense goals - apply defense priority
    of GoalType.DefendColony, GoalType.SecureSystem:
      allGoals[i].priority *= config.defensePriority

    # Offense goals - apply offense priority
    of GoalType.InvadeColony, GoalType.EliminateFleet:
      allGoals[i].priority *= config.offensePriority

    else:
      discard

  # Sort by priority
  result = prioritizeGoals(allGoals)

  # Limit to reasonable number based on budget
  # (Don't generate 100 goals if we can only afford 5)
  let affordableGoals = filterAffordableGoals(result, worldState.treasury)
  if affordableGoals.len < result.len:
    result = affordableGoals

# =============================================================================
# Phase 1.5: Plan Generation
# =============================================================================

proc generateStrategicPlans*(
  goals: seq[Goal],
  houseId: HouseId,
  homeworld: SystemId,
  currentTurn: int,
  intel: IntelligenceSnapshot,
  config: GOAPConfig
): seq[GOAPlan] =
  ## Generate GOAP plans for goals
  ##
  ## Returns plans sorted by confidence * priority

  result = @[]

  let worldState = createWorldStateSnapshot(houseId, homeworld, currentTurn, config, intel)

  # Generate plan for each goal
  for goal in goals:
    let maybePlan = planForGoal(worldState, goal, config.planningDepth) # Pass planning depth
    if maybePlan.isSome:
      let plan = maybePlan.get()

      # Filter by confidence threshold
      if plan.confidence >= config.confidenceThreshold:
        result.add(plan)
        if config.logPlans:
          logDebug(LogCategory.lcAI, &"GOAP Plan Generated: {getPlanDescription(plan)}")

  # Sort by confidence * priority
  result = result.sortedByIt(-(it.confidence * it.goal.priority))

  # Limit to max concurrent plans
  if result.len > config.maxConcurrentPlans:
    result = result[0 ..< config.maxConcurrentPlans]
    if config.logPlans:
      logDebug(LogCategory.lcAI, &"GOAP: Limiting to {config.maxConcurrentPlans} concurrent plans.")


# =============================================================================
# Phase 1.5: Budget Estimation
# =============================================================================

proc estimateBudgetRequirements*(
  plans: seq[GOAPlan]
): Table[DomainType, int] =
  ## Estimate budget requirements by domain
  ##
  ## Used to enhance Phase 2 mediation with GOAP cost estimates
  ## Returns: DomainType → total cost

  result = initTable[DomainType, int]()

  for plan in plans:
    let domain = getDomainForGoal(plan.goal)

    if not result.hasKey(domain):
      result[domain] = 0

    result[domain] += plan.totalCost

proc convertBudgetEstimatesToStrings*(
  estimates: Table[DomainType, int]
): Table[string, int] =
  ## Convert DomainType keys to string keys for treasurer
  ##
  ## Treasurer expects string keys for flexible domain naming

  result = initTable[string, int]()

  for domain, cost in estimates:
    let domainName = case domain
      of DomainType.FleetDomain: "Fleet"
      of DomainType.BuildDomain: "Build"
      of DomainType.ResearchDomain: "Research"
      of DomainType.DiplomaticDomain: "Diplomatic"
      of DomainType.EspionageDomain: "Espionage"
      of DomainType.EconomicDomain: "Economic"

    result[domainName] = cost

# =============================================================================
# Phase 1.5: Main Entry Point
# =============================================================================

type
  Phase15Result* = object
    ## Result of Phase 1.5 GOAP planning
    goals*: seq[Goal]                           # Extracted strategic goals
    plans*: seq[GOAPlan]                        # Generated plans
    budgetEstimates*: Table[DomainType, int]    # Budget requirements by domain
    budgetEstimatesStr*: Table[string, int]     # String-keyed estimates for treasurer
    planningTimeMs*: float                      # Performance metric

proc executePhase15_GOAP*(
  controller: var AIController, # Pass the controller for replanning state and tracker
  houseId: HouseId, # Pass houseId
  homeworld: SystemId, # Pass homeworld
  currentTurn: int, # Pass current turn
  intel: IntelligenceSnapshot,
  config: GOAPConfig
): Phase15Result =
  ## Execute Phase 1.5: GOAP Strategic Planning
  ##
  ## This is called by order_generation.nim between phase1 and phase2.
  ## If GOAP disabled, returns empty result.
  ##
  ## Integrates detailed replanning feedback to generate targeted goals.

  result = Phase15Result(
    goals: @[],
    plans: @[],
    budgetEstimates: initTable[DomainType, int](),
    budgetEstimatesStr: initTable[string, int](),
    planningTimeMs: 0.0
  )

  if not config.enabled:
    logDebug(LogCategory.lcAI, &"{houseId} GOAP is disabled for Phase 1.5, skipping.")
    return  # GOAP disabled, skip

  let startTime = cpuTime()

  # Step 1: Extract strategic goals
  var currentGoals = extractStrategicGoals(houseId, homeworld, currentTurn, intel, config)
  logInfo(LogCategory.lcAI, &"{houseId} GOAP: Extracted {currentGoals.len} initial strategic goals.")

  # Step 2: Incorporate replanning feedback to generate targeted goals or adjust priorities
  if controller.replanNeeded:
    logInfo(LogCategory.lcAI, &"{houseId} GOAP: Replanning triggered. Reason: {controller.replanReason.get()}")

    # Find the specific failed plan that triggered the replan, if applicable
    var failedPlan: Option[TrackedPlan] = none(TrackedPlan)
    for p in controller.goapPlanTracker.activePlans:
      if p.status == PlanStatus.Failed and p.lastFailedActionReason == controller.replanReason:
        failedPlan = some(p)
        break

    if failedPlan.isSome:
      let reason = failedPlan.get().lastFailedActionReason.get()
      let suggestion = failedPlan.get().lastFailedActionSuggestion.getOrDefault("")
      logInfo(LogCategory.lcAI, &"{houseId} GOAP: Specific failed plan identified for replanning. Reason: {reason}, Suggestion: '{suggestion}'")

      case reason
      of ReplanReason.TechNeeded:
        # Try to extract required tech from suggestion, or infer from failed action
        if failedPlan.get().plan.actions.len > failedPlan.get().currentActionIndex:
          let failedAction = failedPlan.get().plan.actions[failedPlan.get().currentActionIndex]
          if failedAction.actionType == ActionType.BuildFleet and failedAction.shipClass.isSome:
            # This requires knowing the CST level for the ship.
            # For simplicity, we create a generic research goal if the suggestion is vague,
            # or try to parse the suggestion.
            logWarn(LogCategory.lcAI, &"GOAP: TechNeeded replan triggered by BuildFleet action. Requires more precise tech lookup.")
            # Fallback for now: high priority general tech goal or attempt to parse suggestion
            var targetTechField: Option[TechField] = none(TechField)
            if suggestion.contains("Construction Tech"):
                targetTechField = some(res_types.TechField.ConstructionTech)
            else:
                targetTechField = some(res_types.TechField.WeaponryTech) # Guess
            
            if targetTechField.isSome:
                let newGoal = Goal(
                    goalType: GoalType.AchieveTechLevel,
                    priority: 0.99, # Very high priority
                    techField: targetTechField,
                    requiredTechLevel: some(5), # Assume max level needed
                    description: &"Urgent: Achieve {targetTechField.get()} due to previous plan failure."
                )
                currentGoals.add(newGoal)
                logInfo(LogCategory.lcAI, &"{houseId} GOAP: Injected high-priority '{newGoal.description}' goal.")

          elif failedAction.actionType == ActionType.AllocateResearch and failedAction.techField.isSome:
            let newGoal = Goal(
                goalType: GoalType.AchieveTechLevel,
                priority: 0.99, # Very high priority
                techField: failedAction.techField,
                requiredTechLevel: some(config.planningDepth), # Attempt to reach a higher level
                description: &"Urgent: Advance {failedAction.techField.get()} due to previous plan failure."
            )
            currentGoals.add(newGoal)
            logInfo(LogCategory.lcAI, &"{houseId} GOAP: Injected high-priority '{newGoal.description}' goal.")

        # If we can't infer specific tech, a general push for tech or re-planning original goal might occur.
        # This highlights a need for more structured 'suggestion' content.
        # For now, if no specific tech goal is injected, it will fall through to general replan.

      of ReplanReason.BudgetFailure:
        # Boost economic goals or modify existing goals to be cheaper
        # For now, add a high priority goal to gain treasury
        let newGoal = Goal(
            goalType: GoalType.GainTreasury,
            priority: 0.95, # High priority
            description: "Urgent: Replenish treasury due to previous budget shortfall."
        )
        currentGoals.add(newGoal)
        logInfo(LogCategory.lcAI, &"{houseId} GOAP: Injected high-priority '{newGoal.description}' goal.")
        
        # Also, consider slightly reducing the priority of expensive goals to make way for economic ones
        for i in 0 ..< currentGoals.len:
            if currentGoals[i].requiredResources.isSome and currentGoals[i].requiredResources.get() > config.treasury * 0.5: # Expensive goal
                currentGoals[i].priority *= 0.8 # Reduce priority
                logDebug(LogCategory.lcAI, &"GOAP: Reduced priority of expensive goal '{currentGoals[i].description}' due to budget failure.")


      of ReplanReason.CapacityFull:
        # Add a high priority goal to build a shipyard or spaceport
        if failedPlan.get().plan.actions.len > failedPlan.get().currentActionIndex:
          let failedAction = failedPlan.get().plan.actions[failedPlan.get().currentActionIndex]
          if failedAction.actionType == ActionType.BuildFacility and failedAction.itemId.isSome and failedAction.target.isSome:
            let facilityType = failedAction.itemId.get()
            let targetSystem = failedAction.target.get()
            let newGoal = Goal(
                goalType: GoalType.BuildFacility,
                priority: 0.98, # Very high priority
                target: some(targetSystem),
                itemId: some(facilityType),
                description: &"Urgent: Build {facilityType} at {targetSystem} due to capacity limits."
            )
            currentGoals.add(newGoal)
            logInfo(LogCategory.lcAI, &"{houseId} GOAP: Injected high-priority '{newGoal.description}' goal.")
          # Fallback if no specific facility/system info
          else:
            let newGoal = Goal(
                goalType: GoalType.BuildFacility,
                priority: 0.90, # High priority
                description: "Urgent: Build construction facilities due to capacity limits."
            )
            currentGoals.add(newGoal)
            logInfo(LogCategory.lcAI, &"{houseId} GOAP: Injected high-priority '{newGoal.description}' goal.")

      of ReplanReason.PlanInvalidated:
        # If a plan was invalidated (e.g., target system captured by another house),
        # remove that specific goal from the list to avoid replanning for it.
        # This requires matching goals to the invalidated plan.
        currentGoals = currentGoals.filterIt(it != failedPlan.get().plan.goal)
        logInfo(LogCategory.lcAI, &"{houseId} GOAP: Removed invalidated goal '{failedPlan.get().plan.goal.description}'.")

      of ReplanReason.BetterOpportunity:
        # `detectNewOpportunities` already adds new goals, so here we ensure they are high priority.
        # The 'newOpportunities' are added in checkGOAPReplanningNeeded, this path is just for replan.
        # It's already handled by 'extractStrategicGoals' and prioritization.
        logDebug(LogCategory.lcAI, &"{houseId} GOAP: BetterOpportunity replan handled by general goal extraction and prioritization.")
        discard
      
      of ReplanReason.PlanFailed, ReplanReason.BudgetShortfall, ReplanReason.ExternalEvent, ReplanReason.PlanStalled:
        # For these generic reasons, a general re-evaluation of all goals is the strategy.
        logInfo(LogCategory.lcAI, &"{houseId} GOAP: Generic replan for reason '{reason}'. Re-evaluating all goals.")
      
      else:
        logInfo(LogCategory.lcAI, &"{houseId} GOAP: Unhandled replan reason '{reason}'. Performing general goal re-evaluation.")
    else:
      logWarn(LogCategory.lcAI, &"{houseId} GOAP: Replanning triggered but no specific failed plan found matching reason '{controller.replanReason.get()}'. Performing general goal re-evaluation.")

    # Reset replan flags after handling
    controller.replanNeeded = false
    controller.replanReason = none(ReplanReason)
  
  # Re-prioritize goals after potential injection/modification
  result.goals = prioritizeGoals(currentGoals)
  logInfo(LogCategory.lcAI, &"{houseId} GOAP: {result.goals.len} goals after replan adjustment and prioritization.")


  # Step 3: Generate plans (for the potentially modified/prioritized goals)
  result.plans = generateStrategicPlans(result.goals, houseId, homeworld, currentTurn, intel, config)
  logInfo(LogCategory.lcAI, &"{houseId} GOAP: Generated {result.plans.len} strategic plans.")

  # Step 3: Estimate budget requirements
  result.budgetEstimates = estimateBudgetRequirements(result.plans)
  result.budgetEstimatesStr = convertBudgetEstimatesToStrings(result.budgetEstimates)

  result.planningTimeMs = (cpuTime() - startTime) * 1000.0
  logInfo(LogCategory.lcAI, &"{houseId} GOAP planning completed in {result.planningTimeMs:.2f} ms.")

  # Debug logging
  if config.logPlans:
    logDebug(LogCategory.lcAI, &"{houseId} Phase 1.5 GOAP: Generated {result.plans.len} plans from {result.goals.len} goals")
    for plan in result.plans:
      logDebug(LogCategory.lcAI, &"  - {getPlanDescription(plan)}")
    for domain, cost in result.budgetEstimates:
      logDebug(LogCategory.lcAI, &"  - Estimated budget for {domain}: {cost} PP")

# =============================================================================
# Phase 1.5: Integration Helpers
# =============================================================================

proc integrateGOAPPlansIntoController*(
  controller: var AIController,
  plans: seq[GOAPlan]
) =
  ## Store new GOAP plans in AI controller's PlanTracker for active tracking.
  ## This is called after Phase 1.5 if new plans are generated.

  for plan in plans:
    controller.goapPlanTracker.addPlan(plan)
    logInfo(LogCategory.lcAI, &"{controller.houseId} GOAP: Actively tracking plan for goal: {plan.goal.description}")
