## Phase 5: Strategic Operations Coordinator
##
## Multi-turn GOAP plan coordination and adaptive replanning
## Called after Phase 4 (Feedback) to handle strategic plan continuation

import std/[tables, options, strformat, sequtils, algorithm]
import ../../../engine/[fog_of_war, logger, order_types]
import ../controller_types
import ../treasurer/multi_advisor
import ../../common/types as ai_types
import ../goap/core/types
import ../goap/state/snapshot
import ../goap/integration/[plan_tracking, replanning, conversion]
import ../goap/planner/search
import ./phase1_5_goap

# =============================================================================
# Plan Tracker Management
# =============================================================================

proc ensurePlanTracker*(controller: var AIController) =
  ## Ensure controller has a plan tracker initialized
  ##
  ## Called at start of Phase 5 if GOAP is enabled

  if controller.goapEnabled:
    # Initialize plan tracker if not already present
    # For Phase 5, we'll use goapActiveGoals as a simple tracker
    # Full PlanTracker integration would require adding field to AIController
    discard

proc updatePlanTracker*(
  controller: var AIController,
  state: FilteredGameState,
  intel: IntelligenceSnapshot
) =
  ## Update plan tracker with current turn's state
  ##
  ## Validates existing plans, detects invalidations

  if not controller.goapEnabled:
    return  # GOAP disabled, skip

  if controller.goapActiveGoals.len == 0:
    return  # No active plans to track

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Phase 5: Updating {controller.goapActiveGoals.len} active plans")

  # For Phase 5 basic implementation:
  # Simply log that we're tracking plans
  # Full implementation would use PlanTracker to validate and advance plans

  let worldState = createWorldStateSnapshot(state, intel)

  # TODO: When PlanTracker added to AIController:
  # let tracker = controller.goapPlanTracker.get()
  # tracker.advanceTurn(state.turn, worldState)
  # tracker.validateAllPlans(worldState)
  # tracker.archiveCompletedPlans()

# =============================================================================
# Replanning Detection
# =============================================================================

proc shouldTriggerReplanning*(
  controller: AIController,
  allocation: MultiAdvisorAllocation,
  availableBudget: int
): (bool, ReplanReason) =
  ## Determine if replanning is needed based on Phase 2/4 feedback
  ##
  ## Triggers:
  ## - Budget shortfall (>50% requirements unfulfilled)
  ## - Critical requirements unfulfilled
  ## - Major state change (war declared, colony lost)

  if not controller.goapEnabled:
    return (false, ReplanReason.PlanFailed)  # GOAP disabled

  if controller.goapActiveGoals.len == 0:
    return (false, ReplanReason.PlanFailed)  # No active plans

  # Check budget shortfall
  let totalUnfulfilled = allocation.treasurerFeedback.totalUnfulfilledCost +
                         allocation.scienceFeedback.unfulfilledRequirements.len * 50 +  # Estimate
                         allocation.drungariusFeedback.unfulfilledRequirements.len * 30 +
                         allocation.eparchFeedback.unfulfilledRequirements.len * 40

  if totalUnfulfilled > availableBudget div 2:  # >50% unfulfilled
    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Phase 5: Budget shortfall detected " &
            &"({totalUnfulfilled}PP unfulfilled vs {availableBudget}PP available)")
    return (true, ReplanReason.BudgetShortfall)

  # Check critical requirements unfulfilled
  var criticalUnfulfilled = 0
  for req in allocation.treasurerFeedback.unfulfilledRequirements:
    if req.priority == RequirementPriority.Critical:
      criticalUnfulfilled.inc()

  if criticalUnfulfilled > 0:
    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Phase 5: {criticalUnfulfilled} critical requirements unfulfilled")
    return (true, ReplanReason.PlanFailed)

  # No replanning needed
  return (false, ReplanReason.PlanFailed)

# =============================================================================
# Replanning Execution
# =============================================================================

proc executeReplanning*(
  controller: var AIController,
  state: FilteredGameState,
  intel: IntelligenceSnapshot,
  reason: ReplanReason,
  availableBudget: int
): Phase15Result =
  ## Execute adaptive replanning
  ##
  ## Generates alternative plans based on replanning reason
  ## Returns new Phase15Result with adjusted plans

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Phase 5: Executing replanning (reason={reason})")

  case reason
  of ReplanReason.BudgetShortfall:
    # Budget-constrained replanning: prioritize highest-value goals
    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Phase 5: Budget-constrained replanning (budget={availableBudget}PP)")

    # Re-run Phase 1.5 with adjusted config
    var config = defaultGOAPConfig()
    config.confidenceThreshold = 0.7  # Higher threshold for budget constraints
    config.maxConcurrentPlans = 3     # Fewer concurrent plans

    result = executePhase15_GOAP(state, intel, config)

    # Filter to only affordable plans
    let worldState = createWorldStateSnapshot(state, intel)
    let affordableGoals = filterAffordableGoals(result.goals, availableBudget)

    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Phase 5: Filtered to {affordableGoals.len} affordable goals " &
            &"(from {result.goals.len} total)")

    # Regenerate plans with affordable goals only
    result.goals = affordableGoals
    result.plans = generateStrategicPlans(result.goals, state, intel, config)
    result.budgetEstimates = estimateBudgetRequirements(result.plans)
    result.budgetEstimatesStr = convertBudgetEstimatesToStrings(result.budgetEstimates)

  of ReplanReason.PlanFailed, ReplanReason.PlanInvalidated:
    # Plan failure: generate completely new plans
    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Phase 5: Full replanning (plan failed/invalidated)")

    let config = defaultGOAPConfig()
    result = executePhase15_GOAP(state, intel, config)

  of ReplanReason.BetterOpportunity:
    # Opportunistic replanning: check for new high-value goals
    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Phase 5: Opportunistic replanning")

    let worldState = createWorldStateSnapshot(state, intel)
    let currentGoals = extractAllGoalsFromState(worldState)
    let newOpportunities = detectNewOpportunities(currentGoals, worldState)

    if newOpportunities.len > 0:
      logInfo(LogCategory.lcAI,
              &"{controller.houseId} Phase 5: Found {newOpportunities.len} new opportunities")

      # Generate plans for new opportunities
      let config = defaultGOAPConfig()
      result = executePhase15_GOAP(state, intel, config)
    else:
      # No new opportunities, keep existing plans
      result = Phase15Result(
        goals: @[],
        plans: @[],
        budgetEstimates: initTable[DomainType, int](),
        budgetEstimatesStr: initTable[string, int](),
        planningTimeMs: 0.0
      )

  of ReplanReason.ExternalEvent:
    # External event (war, colony lost): emergency replanning
    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Phase 5: Emergency replanning (external event)")

    var config = defaultGOAPConfig()
    config.defensePriority = 0.9  # High defense priority in emergencies
    config.maxConcurrentPlans = 5  # More plans for flexibility

    result = executePhase15_GOAP(state, intel, config)

# =============================================================================
# Plan Continuation
# =============================================================================

proc continuePlans*(
  controller: var AIController,
  state: FilteredGameState,
  intel: IntelligenceSnapshot
) =
  ## Continue execution of multi-turn plans
  ##
  ## For Phase 5 basic implementation: logs plan continuation
  ## Full implementation would use PlanTracker to get next actions

  if not controller.goapEnabled:
    return

  if controller.goapActiveGoals.len == 0:
    return

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Phase 5: Continuing {controller.goapActiveGoals.len} active plans")

  # TODO: When PlanTracker added:
  # let tracker = controller.goapPlanTracker.get()
  # for i in 0 ..< tracker.activePlans.len:
  #   if tracker.activePlans[i].status == PlanStatus.Active:
  #     let nextAction = tracker.getNextAction(i)
  #     if nextAction.isSome:
  #       # Convert action to orders and execute
  #       executeAction(nextAction.get(), controller, state)
  #       tracker.advancePlan(i)

# =============================================================================
# Phase 5 Main Entry Point
# =============================================================================

proc executePhase5_Strategic*(
  controller: var AIController,
  state: FilteredGameState,
  intel: IntelligenceSnapshot,
  allocation: MultiAdvisorAllocation,
  availableBudget: int
): Option[Phase15Result] =
  ## Execute Phase 5: Strategic Operations Coordination
  ##
  ## 1. Update plan tracker (validate existing plans)
  ## 2. Check if replanning needed
  ## 3. Execute replanning if needed
  ## 4. Continue multi-turn plans
  ##
  ## Returns Some(Phase15Result) if replanning occurred, None otherwise

  if not controller.goapEnabled:
    return none(Phase15Result)  # GOAP disabled

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} === Phase 5: Strategic Operations ===")

  # Step 1: Ensure plan tracker exists
  ensurePlanTracker(controller)

  # Step 2: Update plan tracker with current state
  updatePlanTracker(controller, state, intel)

  # Step 3: Check if replanning needed
  let (shouldReplan, reason) = shouldTriggerReplanning(controller, allocation, availableBudget)

  if shouldReplan:
    # Step 4: Execute replanning
    let replanResult = executeReplanning(controller, state, intel, reason, availableBudget)

    # Update controller with new plans
    if replanResult.plans.len > 0:
      controller.goapActiveGoals = @[]
      for plan in replanResult.plans:
        let goalDesc = &"{plan.goal.goalType} (cost={plan.totalCost}PP, " &
                       &"conf={int(plan.confidence * 100)}%)"
        controller.goapActiveGoals.add(goalDesc)

      logInfo(LogCategory.lcAI,
              &"{controller.houseId} Phase 5: Replanning complete - " &
              &"{replanResult.plans.len} new plans generated")

      return some(replanResult)
    else:
      logInfo(LogCategory.lcAI,
              &"{controller.houseId} Phase 5: Replanning yielded no viable plans")
      return none(Phase15Result)

  else:
    # Step 5: Continue existing plans
    continuePlans(controller, state, intel)

    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Phase 5: No replanning needed, continuing existing plans")

    return none(Phase15Result)

# =============================================================================
# Helper: Convert Replanning Result to Orders
# =============================================================================

proc describeReplanResult*(
  replanResult: Phase15Result,
  controller: AIController
): string =
  ## Describe replanning result for logging
  ##
  ## For Phase 5 basic implementation: returns summary string
  ## Full implementation would convert GOAP actions to game orders

  result = &"Phase 5 replanning: {replanResult.plans.len} plans generated"

  if replanResult.plans.len > 0:
    result.add("\n  Goals:")
    for plan in replanResult.plans:
      result.add(&"\n    - {plan.goal.goalType} (cost={plan.totalCost}PP, conf={int(plan.confidence * 100)}%)")

  # TODO: Implement action → order conversion when needed
  # For each plan in replanResult.plans:
  #   For each action in plan.actions:
  #     Convert to game order (MoveOrder, BuildOrder, etc.)
