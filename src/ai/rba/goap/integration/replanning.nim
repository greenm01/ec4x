import std/[tables, options, sequtils, algorithm, strformat]
import ../core/[types, heuristics]
import ../state/snapshot
import ../planner/search
import plan_tracking
import ../../../../engine/logger # For logging
import ../../../../common/types/core # For HouseId
import ../../config # For GOAPConfig and RequirementPriority
import ../../controller_types # For UnfulfillmentReason

# =============================================================================
# Replanning Triggers
# =============================================================================

type
  ReplanReason* {.pure.} = enum
    ## Why we're replanning
    PlanFailed          # Action execution failed (explicitly reported)
    PlanInvalidated     # Preconditions no longer hold (detected by validation)
    BudgetShortfall     # Not enough resources to execute next actions
    BetterOpportunity   # New, higher-priority goal emerged (external detection)
    ExternalEvent       # Enemy action changed situation (e.g., system lost)
    PlanStalled         # No progress on plan for too many turns
    TechNeeded          # Failed due to missing tech (e.g., cannot build ship)
    BudgetFailure       # Failed due to insufficient budget for action (general)
    CapacityFull        # Failed due to capacity limits (e.g., colony docks full)

proc toReplanReason*(reason: UnfulfillmentReason): ReplanReason =
  ## Converts an UnfulfillmentReason from RBA into a GOAP ReplanReason.
  case reason
  of UnfulfillmentReason.TechNotAvailable:
    return ReplanReason.TechNeeded
  of UnfulfillmentReason.InsufficientBudget, UnfulfillmentReason.PartialBudget,
     UnfulfillmentReason.BudgetReserved, UnfulfillmentReason.SubstitutionFailed:
    return ReplanReason.BudgetFailure
  of UnfulfillmentReason.ColonyCapacityFull:
    return ReplanReason.CapacityFull
  of UnfulfillmentReason.NoValidColony:
    # This might require a more specific GOAP reason, but for now,
    # it indicates a fundamental issue with the plan's target.
    return ReplanReason.PlanInvalidated

proc shouldReplan*(plan: TrackedPlan, state: WorldStateSnapshot, config: GOAPConfig): (bool, ReplanReason) =
  ## Determine if a plan needs replanning.
  ## Returns: (shouldReplan, reason)

  # 1. Check if plan explicitly failed or invalidated
  if plan.status == PlanStatus.Failed:
    # If the plan failed, use the specific reason from the last failed action if available
    if plan.lastFailedActionReason.isSome:
      return (true, plan.lastFailedActionReason.get().toReplanReason()) # Convert UnfulfillmentReason to ReplanReason
    else:
      return (true, ReplanReason.PlanFailed) # Generic failure
  if plan.status == PlanStatus.Invalidated:
    return (true, ReplanReason.PlanInvalidated)
  if plan.status == PlanStatus.Completed:
    # Completed plans don't need replanning, they should be archived.
    return (false, ReplanReason.PlanFailed) # Dummy reason, as this branch implies no replan

  # 2. Check for budget constraints for immediate next action
  if plan.currentActionIndex < plan.plan.actions.len:
    let nextAction = plan.plan.actions[plan.currentActionIndex]
    # Check if treasury is less than required budget * replanBudgetShortfallRatio
    # This prevents triggering replan too early if a small amount is missing.
    if state.treasury < nextAction.cost and
       state.treasury.float / max(nextAction.cost, 1).float < config.replanBudgetShortfallRatio:
      logInfo(LogCategory.lcAI, &"GOAP Replan: Budget shortfall detected for '{plan.plan.goal.description}'. Next action cost {nextAction.cost}, treasury {state.treasury}, ratio {state.treasury.float / max(nextAction.cost, 1).float:.2f} < {config.replanBudgetShortfallRatio:.2f}")
      return (true, ReplanReason.BudgetShortfall)
  else:
    # If there are no more actions, the plan should probably be marked as completed.
    # This might happen if `advanceTurn` or `markActionComplete` didn't catch it.
    logInfo(LogCategory.lcAI, &"GOAP Replan: Plan '{plan.plan.goal.description}' has no more actions. Marking as invalid/completed.")
    return (true, ReplanReason.PlanInvalidated) # Effectively completed or invalid.

  # 3. Check if plan has stalled (no progress for X turns)
  if config.replanStalledTurns > 0 and state.turn - plan.lastUpdateTurn >= config.replanStalledTurns and plan.actionsCompleted < plan.plan.actions.len:
    logInfo(LogCategory.lcAI, &"GOAP Replan: Plan '{plan.plan.goal.description}' stalled for {state.turn - plan.lastUpdateTurn} turns.")
    return (true, ReplanReason.PlanStalled)

  # 4. Check for external events/critical changes that invalidate the goal
  # This relies on the `isPlanStillValid` in plan_tracking.nim
  if not isPlanStillValid(plan, state):
    logInfo(LogCategory.lcAI, &"GOAP Replan: Plan '{plan.plan.goal.description}' is no longer valid due to world state changes.")
    return (true, ReplanReason.PlanInvalidated)


  # If no explicit triggers, plan looks OK for now.
  return (false, ReplanReason.PlanFailed) # Dummy reason if no replan needed

# =============================================================================
# Alternative Plan Generation
# =============================================================================

proc generateAlternativePlans*(
  state: WorldStateSnapshot,
  goal: Goal,
  maxAlternatives: int = 3,
  planningDepth: int = 5 # Allow specifying depth for alternatives
): seq[GOAPlan] =
  ## Generate multiple alternative plans for a goal.
  ## Uses A* with different heuristic weights or planning depths to explore solution space.

  result = @[]

  # 1. Generate a base plan with default settings
  let basePlan = planForGoal(config, state, goal) # Pass config
  if basePlan.isSome:
    result.add(basePlan.get())
    
  # 2. Try generating plans with different planning depths (for varied time horizons)
  # For now, planForGoal uses config.max_search_nodes. To get alternative depths,
  # we would need to create temporary configs or modify the config object.
  # This part is currently not fully implemented with flexible depths in planForGoal.
      
  # The original comment indicates trying different depths. This would require
  # `planForGoal` to accept a temporary `planningDepth`. The `config` contains
  # `planning_depth`, which is used by `planForGoal`. Generating multiple distinct
  # alternative plans with the *same* config requires more sophisticated GOAP logic
  # than a simple A* search usually provides by default. For now, we rely on the
  # `planForGoal` returning *one* best plan given the config.
    
  # Ensure uniqueness (simple approach for now)
  var unique: seq[GOAPlan] = @[]
  for plan in result:
    var isDuplicate = false
    for existing in unique:
      # Compare goals and actions for uniqueness
      if existing.goal == plan.goal and existing.actions.len == plan.actions.len and existing.totalCost == plan.totalCost:
        isDuplicate = true
        break
    if not isDuplicate:
      unique.add(plan)
  result = unique

  # Ensure uniqueness (simple approach for now)
  # Manual deduplication since deduplicate doesn't support custom comparison
  var unique: seq[GOAPlan] = @[]
  for plan in result:
    var isDuplicate = false
    for existing in unique:
      if existing.goal.description == plan.goal.description and existing.totalCost == plan.totalCost:
        isDuplicate = true
        break
    if not isDuplicate:
      unique.add(plan)
  result = unique

proc selectBestAlternative*(
  alternatives: seq[GOAPlan],
  state: WorldStateSnapshot,
  prioritizeSpeed: bool = false
): Option[GOAPlan] =
  ## Select the best plan from a sequence of alternatives.
  ## Criteria: Highest confidence, then lowest cost, then fewest turns (if prioritizeSpeed).

  if alternatives.len == 0:
    return none(GOAPlan)

  var bestPlan = alternatives[0]
  var bestScore = -Inf # Use negative infinity to ensure any plan is better than none

  for plan in alternatives:
    let confidence = estimatePlanConfidence(state, plan)
    var score = confidence * 10.0 # Give confidence a strong weight

    # Adjust for cost: prefer cheaper plans (lower cost, higher affordability)
    # Avoid division by zero: if totalCost is 0, consider affordability max.
    let affordability = if plan.totalCost > 0: state.treasury.float / plan.totalCost.float else: 100.0
    score += affordability * 0.2  # 20% weight

    # Adjust for speed if requested: prefer plans with fewer turns
    if prioritizeSpeed:
      let speedBonus = if plan.estimatedTurns > 0: 1.0 / plan.estimatedTurns.float else: 1.0
      score += speedBonus * 0.3  # 30% weight

    # Add a small bonus for plans that complete a goal faster (if speed not primary)
    # if not prioritizeSpeed and plan.estimatedTurns > 0:
    #   score += (1.0 / plan.estimatedTurns.float) * 0.05

    if score > bestScore:
      bestScore = score
      bestPlan = plan

  return some(bestPlan)

# =============================================================================
# Plan Repair
# =============================================================================

proc repairPlan*(
  failedPlan: TrackedPlan,
  state: WorldStateSnapshot,
  config: GOAPConfig
): Option[GOAPlan] =
  ## Attempt to repair a failed plan using detailed feedback if available.
  ## Strategy:
  ## - If early in plan: Generate completely new plan for the same goal.
  ## - If late in plan: Try to find alternative actions for the remaining steps (Phase 5).
  ## - If specific failure reason: Attempt targeted repair/re-planning.

  let progress = failedPlan.actionsCompleted.float / max(failedPlan.plan.actions.len, 1).float

  logInfo(LogCategory.lcAI, &"GOAP Repair: Attempting to repair plan '{failedPlan.plan.goal.description}' (Progress: {progress:.2f})")

  # 1. Check for specific failure reasons first (targeted repair)
  if failedPlan.lastFailedActionReason.isSome:
    let unfulfillmentReason = failedPlan.lastFailedActionReason.get()
    let reason = toReplanReason(unfulfillmentReason)  # Convert to ReplanReason
    let suggestion = failedPlan.lastFailedActionSuggestion.get("No specific suggestion.")
    logInfo(LogCategory.lcAI, &"GOAP Repair: Specific failure reason detected: {unfulfillmentReason} -> {reason}. Suggestion: {suggestion}")

    case reason
    of ReplanReason.TechNeeded:
      # If a build/research action failed due to missing tech, generate a new research goal
      logInfo(LogCategory.lcAI, &"GOAP Repair: Action failed due to missing tech. Proposing new research goal.")
      # The detailed feedback should ideally specify *which* tech field/level is needed.
      # For now, if the original goal was related to something that needs tech (e.g., building a ship),
      # we assume the suggestion might contain the tech info or we need to infer it.
      # This part relies heavily on future parsing of 'suggestion' or richer 'Action' data.
      # Placeholder: A new GOAP goal "AchieveTechLevel" needs to be dynamically created.
      # For immediate repair, we might try to replan the original goal, hoping tech will be planned.
      # Or, a direct replanning of a 'Research' goal might be injected into the tracker.
      # For now, we'll fall back to replanning the original goal, expecting requirement generation to pick up tech.
      return planForGoal(config, state, failedPlan.plan.goal) # Pass config

    of ReplanReason.BudgetFailure:
      logInfo(LogCategory.lcAI, &"GOAP Repair: Action failed due to insufficient budget. Trying cheaper alternatives or adjusting cost.")
      # Try to generate alternative plans for the original goal, prioritizing cheaper ones
      let alternatives = generateAlternativePlans(state, failedPlan.plan.goal, maxAlternatives = 3, planningDepth = config.planning_depth)
      let bestAlternative = selectBestAlternative(alternatives, state, prioritizeSpeed = true) # Prefer cheaper/faster
      if bestAlternative.isSome:
        logInfo(LogCategory.lcAI, &"GOAP Repair: Found cheaper alternative plan for '{failedPlan.plan.goal.description}'.")
        return bestAlternative
      else:
        # If no cheaper alternative, maybe generate a 'GainTreasury' goal or just replan original
        logWarn(LogCategory.lcAI, &"GOAP Repair: No cheaper alternative found. Re-planning original goal.")
        return planForGoal(config, state, failedPlan.plan.goal) # Pass config

    of ReplanReason.CapacityFull:
      logInfo(LogCategory.lcAI, &"GOAP Repair: Action failed due to capacity limits. Proposing new facility build goal.")
      # If a build action failed due to full colony capacity,
      # a new GOAP goal "BuildFacility" for Shipyard/Spaceport should be generated.
      # This requires knowing which system was targeted and what facility type (from suggestion/original action).
      # For now, fallback to replanning original goal.
      return planForGoal(config, state, failedPlan.plan.goal) # Pass config

    of ReplanReason.PlanInvalidated:
      logInfo(LogCategory.lcAI, &"GOAP Repair: Plan invalidated by world state. Generating new plan for the same goal.")
      return planForGoal(config, state, failedPlan.plan.goal) # Pass config

    of ReplanReason.ExternalEvent:
      logInfo(LogCategory.lcAI, &"GOAP Repair: Plan affected by external event. Re-planning for '{failedPlan.plan.goal.description}'.")
      return planForGoal(config, state, failedPlan.plan.goal) # Pass config

    else:
      # For other specific failure reasons not explicitly handled, fall through to generic repair.
      logInfo(LogCategory.lcAI, &"GOAP Repair: Unhandled specific failure reason '{reason}'. Falling back to generic repair.")

  # 2. Generic repair based on progress
  if progress < 0.3 or failedPlan.plan.actions.len < 3:
    # Early failure or very short plan - just replan from scratch for the same goal.
    logInfo(LogCategory.lcAI, &"GOAP Repair: Early plan failure or short plan. Re-planning from scratch for goal '{failedPlan.plan.goal.description}'.")
    return planForGoal(config, state, failedPlan.plan.goal) # Pass config

  else:
    # Late failure - try to implement partial plan repair.
    logInfo(LogCategory.lcAI, &"GOAP Repair: Attempting partial plan repair for late failure of '{failedPlan.plan.goal.description}'.")

    # For partial repair, create a new temporary goal representing the remaining actions
    # The preconditions for this sub-goal would be the effects of the last completed action.
    # For now, a simplified approach: replan the remainder of the actions.
    # This is still a full planForGoal, but with an adjusted start state or sub-goal.

    # Create a new goal that is a continuation of the failed plan's goal.
    # The target is the same, but planning will start from the current world state.
    let remainingGoal = failedPlan.plan.goal

    # Attempt to plan from the current action onwards.
    # This effectively tries to find a path for the *rest* of the original plan.
    # A more sophisticated partial repair would modify the preconditions of the remaining actions
    # to reflect the *actual* world state, not just the planned effects.
    let newPartialPlan = planForGoal(config, state, remainingGoal) # Pass config

    if newPartialPlan.isSome:
      logInfo(LogCategory.lcAI, &"GOAP Repair: Successfully generated partial plan for '{failedPlan.plan.goal.description}'.")
      # Adjust the new plan to reflect that it's a continuation
      var repairedPlan = newPartialPlan.get()
      # The total cost/turns should ideally account for what's already done.
      # For simplicity, we are returning a fresh plan for the goal,
      # but the plan tracker will handle its integration.
      return some(repairedPlan)
    else:
      logWarn(LogCategory.lcAI, &"GOAP Repair: Failed to generate partial plan for '{failedPlan.plan.goal.description}'. Falling back to full replan.")
      # Fallback to replanning the entire goal if partial repair fails
      return planForGoal(config, state, failedPlan.plan.goal) # Pass config

# =============================================================================
# Budget-Constrained Replanning
# =============================================================================

proc replanWithBudgetConstraint*(
  tracker: var PlanTracker,
  state: WorldStateSnapshot,
  availableBudget: int,
  config: GOAPConfig
): seq[GOAPlan] =
  ## Replan all active goals with budget constraint.
  ## Used in RBA Phase 2 mediation when budget is limited.
  ## Returns an affordable subset of plans.

  result = @[]

  # Collect all active goals and sort by priority (highest first)
  var allSortedGoals: seq[Goal] = @[]
  for p in tracker.activePlans:
    if p.status == PlanStatus.Active:
      allSortedGoals.add(p.plan.goal)

  # Sort by priority descending (highest priority first)
  allSortedGoals = allSortedGoals.sortedByIt(-it.priority)

  var remainingBudget = availableBudget

  for goal in allSortedGoals:
    # Try to plan for this goal with the configured planning depth
    let maybePlan = planForGoal(state, goal)
    if maybePlan.isNone:
      logDebug(LogCategory.lcAI, &"GOAP Budget Replan: Could not generate plan for goal '{goal.description}'.")
      continue

    let plan = maybePlan.get()

    # Can we afford it?
    if plan.totalCost <= remainingBudget:
      result.add(plan)
      remainingBudget -= plan.totalCost
      logDebug(LogCategory.lcAI, &"GOAP Budget Replan: Added plan for '{goal.description}', cost {plan.totalCost}, remaining budget {remainingBudget}.")
    elif remainingBudget > 0:
      # If not fully affordable, try cheaper alternatives
      logDebug(LogCategory.lcAI, &"GOAP Budget Replan: Plan for '{goal.description}' too expensive ({plan.totalCost}), trying alternatives.")
      let alternatives = generateAlternativePlans(state, goal, maxAlternatives = 3, planningDepth = config.planningDepth)
      let bestAlternative = selectBestAlternative(alternatives, state, prioritizeSpeed = true) # Prefer faster/cheaper alternatives

      if bestAlternative.isSome:
        let altPlan = bestAlternative.get()
        if altPlan.totalCost <= remainingBudget:
          result.add(altPlan)
          remainingBudget -= altPlan.totalCost
          logDebug(LogCategory.lcAI, &"GOAP Budget Replan: Added cheaper alternative for '{goal.description}', cost {altPlan.totalCost}, remaining budget {remainingBudget}.")
        else:
          # Can't afford even the best alternative, mark unfulfilled
          logDebug(LogCategory.lcAI, &"GOAP Budget Replan: Could not afford any plan for '{goal.description}' (cost {altPlan.totalCost}, remaining {remainingBudget}).")
          discard
      else:
        # No alternatives found, mark unfulfilled
        logDebug(LogCategory.lcAI, &"GOAP Budget Replan: No affordable alternatives found for '{goal.description}'.")
        discard

  return result

# =============================================================================
# Opportunistic Replanning
# =============================================================================

proc detectNewOpportunities*(
  currentGoals: seq[Goal],
  state: WorldStateSnapshot
): seq[Goal] =
  ## Detect new high-value goals that weren't in the original set of active goals.
  ## Examples: Weakly defended enemy colony appears, Alliance opportunity emerges.

  result = @[]

  # 1. Check for invasion opportunities (weakly defended enemy colonies)
  for opp in state.invasionOpportunities: # These are already pre-filtered as "opportunities"
    let alreadyTargeted = currentGoals.anyIt(
      it.goalType == GoalType.InvadeColony and
      it.target.isSome and
      it.target.get() == opp
    )

    if not alreadyTargeted:
      # Create an opportunistic invasion goal
      # Need to get owner for the goal description
      var enemyOwner: HouseId
      for enemyColony in state.knownEnemyColonies:
        if enemyColony.systemId == opp:
          enemyOwner = enemyColony.owner
          break
      
      result.add(Goal(
        goalType: GoalType.InvadeColony,
        priority: 0.85, # High priority for opportunistic invasions
        target: some(opp),
        targetHouse: some(enemyOwner),
        requiredResources: 500, # Estimate, actual cost will be planned
        description: &"Invade vulnerable system {opp}"
      ))

  # 2. Check for tech opportunities (if close to breakthrough or significant gap)
  for gap in state.criticalTechGaps:
    let alreadyTargeted = currentGoals.anyIt(
      it.goalType == GoalType.CloseResearchGap and
      it.techField.isSome and
      it.techField.get() == gap
    )
    if not alreadyTargeted:
      result.add(Goal(
        goalType: GoalType.CloseResearchGap,
        priority: 0.75, # High priority to close tech gaps
        techField: some(gap),
        requiredResources: 200, # Estimate
        description: &"Close critical tech gap in {gap}"
      ))

  # 3. Check for diplomatic opportunities (e.g., if relations with a neutral house improved significantly)
  # This would require more sophisticated `WorldStateSnapshot` fields to track relation changes.
  # For now, a placeholder.
  # for houseId, relation in state.diplomaticRelations:
  #   if relation == DiplomaticState.Neutral and houseId notin currentGoals.mapIt(it.targetHouse.get()):
  #     # If there's a neutral house not currently targeted by a diplomatic goal, consider improving relations.
  #     result.add(Goal(
  #       goalType: GoalType.ImproveRelations,
  #       priority: 0.4,
  #       targetHouse: some(houseId),
  #       description: &"Improve relations with {houseId}"
  #     ))

proc integrateNewOpportunities*(
  tracker: var PlanTracker,
  newGoals: seq[Goal],
  state: WorldStateSnapshot,
  config: GOAPConfig
) =
  ## Integrate newly detected opportunities into the plan tracker.
  ## May pause lower-priority plans to pursue high-value opportunities.

  # Get current active plan count
  let activePlanCount = tracker.getActivePlanCount()

  for newGoal in newGoals:
    # Check if a similar goal is already active
    let goalAlreadyActive = tracker.activePlans.anyIt(
      it.status == PlanStatus.Active and it.plan.goal.goalType == newGoal.goalType and
      it.plan.goal.target == newGoal.target and it.plan.goal.targetHouse == newGoal.targetHouse
    )
    if goalAlreadyActive:
      logDebug(LogCategory.lcAI, &"GOAP Opportunity: Goal '{newGoal.description}' already active, skipping integration.")
      continue # Skip if already pursuing this goal

    if activePlanCount >= config.maxConcurrentPlans:
      # At capacity - only add if new goal is higher priority than the lowest-priority active plan
      var lowestPriorityPlanIdx = -1
      var lowestPriority = 1.1 # Higher than any possible priority

      for i in 0 ..< tracker.activePlans.len:
        let plan = tracker.activePlans[i]
        if plan.status == PlanStatus.Active and plan.plan.goal.priority < lowestPriority:
          lowestPriority = plan.plan.goal.priority
          lowestPriorityPlanIdx = i

      # Replace if new goal is strictly higher priority
      if lowestPriorityPlanIdx >= 0 and newGoal.priority > lowestPriority:
        let pausedPlanDescription = tracker.activePlans[lowestPriorityPlanIdx].plan.goal.description
        tracker.pausePlan(lowestPriorityPlanIdx) # Pause the old plan
        let newPlan = planForGoal(state, newGoal)
        if newPlan.isSome:
          tracker.addPlan(newPlan.get())
          logInfo(LogCategory.lcAI, &"GOAP Opportunity: Paused plan for '{pausedPlanDescription}' to pursue new opportunity: '{newPlan.get().goal.description}'")
      else:
        logDebug(LogCategory.lcAI, &"GOAP Opportunity: Cannot integrate '{newGoal.description}' - max concurrent plans reached and new goal not higher priority.")
    else:
      # Under capacity - add all new goals
      let newPlan = planForGoal(state, newGoal)
      if newPlan.isSome:
        tracker.addPlan(newPlan.get())
        logInfo(LogCategory.lcAI, &"GOAP Opportunity: Integrated new goal: '{newPlan.get().goal.description}'")
