## GOAP Replanning
##
## Generates alternative plans when original plan fails or becomes invalid
## Used in RBA Phase 4 (Feedback) for adaptive planning

import std/[tables, options, sequtils, algorithm]
import ../core/[types, heuristics]
import ../state/snapshot
import ../planner/search
import plan_tracking

# =============================================================================
# Replanning Triggers
# =============================================================================

type
  ReplanReason* {.pure.} = enum
    ## Why we're replanning
    PlanFailed          # Action execution failed
    PlanInvalidated     # Preconditions no longer hold
    BudgetShortfall     # Not enough resources
    BetterOpportunity   # New, higher-priority goal emerged
    ExternalEvent       # Enemy action changed situation

proc shouldReplan*(plan: TrackedPlan, state: WorldStateSnapshot): (bool, ReplanReason) =
  ## Determine if a plan needs replanning
  ##
  ## Returns: (shouldReplan, reason)

  # Check if plan explicitly failed or invalidated
  if plan.status == PlanStatus.Failed:
    return (true, ReplanReason.PlanFailed)
  if plan.status == PlanStatus.Invalidated:
    return (true, ReplanReason.PlanInvalidated)

  # Check budget constraints
  var remainingCost = 0
  for i in plan.currentActionIndex ..< plan.plan.actions.len:
    remainingCost += plan.plan.actions[i].cost

  if state.treasury < remainingCost div 2:  # Less than 50% of needed budget
    return (true, ReplanReason.BudgetShortfall)

  # Plan looks OK
  return (false, ReplanReason.PlanFailed)  # dummy reason

# =============================================================================
# Alternative Plan Generation
# =============================================================================

proc generateAlternativePlans*(
  state: WorldStateSnapshot,
  goal: Goal,
  maxAlternatives: int = 3
): seq[GOAPlan] =
  ## Generate multiple alternative plans for a goal
  ##
  ## Uses A* with different heuristic weights to explore solution space

  result = @[]

  # Generate base plan
  let basePlan = planForGoal(state, goal)
  if basePlan.isSome:
    result.add(basePlan.get())

  # TODO Phase 5: Implement alternative plan generation
  # - Try different action ordering
  # - Try different resource allocation
  # - Try different intermediate goals
  # For Phase 4, we just return the base plan

proc selectBestAlternative*(
  alternatives: seq[GOAPlan],
  state: WorldStateSnapshot,
  prioritizeSpeed: bool = false
): Option[GOAPlan] =
  ## Select best plan from alternatives
  ##
  ## Criteria:
  ## - Highest confidence
  ## - Lowest cost (if confidence similar)
  ## - Fewest turns (if prioritizeSpeed)

  if alternatives.len == 0:
    return none(GOAPlan)

  var bestPlan = alternatives[0]
  var bestScore = 0.0

  for plan in alternatives:
    let confidence = estimatePlanConfidence(state, plan)
    var score = confidence

    # Adjust for cost
    let affordability = state.treasury.float / max(plan.totalCost, 1).float
    score += affordability * 0.2  # 20% weight

    # Adjust for speed if requested
    if prioritizeSpeed:
      let speedBonus = 1.0 / max(plan.estimatedTurns, 1).float
      score += speedBonus * 0.3  # 30% weight

    if score > bestScore:
      bestScore = score
      bestPlan = plan

  return some(bestPlan)

# =============================================================================
# Plan Repair
# =============================================================================

proc repairPlan*(
  failedPlan: TrackedPlan,
  state: WorldStateSnapshot
): Option[GOAPlan] =
  ## Attempt to repair a failed plan
  ##
  ## Strategy:
  ## - If early in plan: Generate completely new plan for same goal
  ## - If late in plan: Try to find alternative actions for remaining steps

  let progress = failedPlan.actionsCompleted.float / max(failedPlan.plan.actions.len, 1).float

  if progress < 0.3:
    # Early failure - just replan from scratch
    return planForGoal(state, failedPlan.plan.goal)

  else:
    # Late failure - try to continue with alternative actions
    # For Phase 4, we just replan entirely
    # TODO Phase 5: Implement partial plan repair
    return planForGoal(state, failedPlan.plan.goal)

# =============================================================================
# Budget-Constrained Replanning
# =============================================================================

proc replanWithBudgetConstraint*(
  tracker: var PlanTracker,
  state: WorldStateSnapshot,
  availableBudget: int
): seq[GOAPlan] =
  ## Replan all active goals with budget constraint
  ##
  ## Used in RBA Phase 2 mediation when budget is limited
  ## Returns affordable subset of plans

  result = @[]

  # Collect all goals from active plans
  var goals: seq[Goal] = @[]
  for plan in tracker.activePlans:
    if plan.status == PlanStatus.Active:
      goals.add(plan.plan.goal)

  # Sort by priority
  goals = goals.sortedByIt(-it.priority)

  # Allocate budget greedily
  var remainingBudget = availableBudget

  for goal in goals:
    # Try to plan for this goal
    let maybePlan = planForGoal(state, goal)
    if maybePlan.isNone:
      continue

    let plan = maybePlan.get()

    # Can we afford it?
    if plan.totalCost <= remainingBudget:
      result.add(plan)
      remainingBudget -= plan.totalCost
    elif remainingBudget > 0:
      # Try cheaper alternatives
      let alternatives = generateAlternativePlans(state, goal, maxAlternatives = 5)
      for altPlan in alternatives:
        if altPlan.totalCost <= remainingBudget:
          result.add(altPlan)
          remainingBudget -= altPlan.totalCost
          break

# =============================================================================
# Opportunistic Replanning
# =============================================================================

proc detectNewOpportunities*(
  currentGoals: seq[Goal],
  state: WorldStateSnapshot
): seq[Goal] =
  ## Detect new high-value goals that weren't in original set
  ##
  ## Examples:
  ## - Weakly defended enemy colony appears
  ## - Alliance opportunity emerges
  ## - Critical tech breakthrough available

  result = @[]

  # Check for invasion opportunities
  for enemyColony in state.knownEnemyColonies:
    # Is this colony weakly defended?
    # (Simplified check for Phase 4)
    let alreadyTargeted = currentGoals.anyIt(
      it.goalType == GoalType.InvadeColony and
      it.target.isSome and
      it.target.get() == enemyColony.systemId
    )

    if not alreadyTargeted:
      # New opportunity!
      result.add(Goal(
        goalType: GoalType.InvadeColony,
        target: some(enemyColony.systemId),
        targetHouse: some(enemyColony.owner),
        priority: 0.8,  # High priority
        deadline: none(int),
        requiredResources: 300,  # Estimate
        successCondition: nil
      ))

  # TODO Phase 5: Add more opportunity detection
  # - Alliance opportunities (relations improved)
  # - Research breakthroughs (tech almost complete)
  # - Economic opportunities (high-value colonies available)

proc integrateNewOpportunities*(
  tracker: var PlanTracker,
  newGoals: seq[Goal],
  state: WorldStateSnapshot,
  maxConcurrentPlans: int = 5
) =
  ## Integrate newly detected opportunities into plan tracker
  ##
  ## May pause lower-priority plans to pursue high-value opportunities

  # Get current active plan count
  let activePlans = tracker.getActivePlanCount()

  if activePlans >= maxConcurrentPlans:
    # At capacity - only add if new goal is higher priority
    for newGoal in newGoals:
      # Find lowest-priority active plan
      var lowestPriorityIdx = -1
      var lowestPriority = 1.0

      for i in 0 ..< tracker.activePlans.len:
        let plan = tracker.activePlans[i]
        if plan.status == PlanStatus.Active and plan.plan.goal.priority < lowestPriority:
          lowestPriority = plan.plan.goal.priority
          lowestPriorityIdx = i

      # Replace if new goal is higher priority
      if lowestPriorityIdx >= 0 and newGoal.priority > lowestPriority:
        tracker.pausePlan(lowestPriorityIdx)

        # Create plan for new goal
        let newPlan = planForGoal(state, newGoal)
        if newPlan.isSome:
          tracker.addPlan(newPlan.get())

  else:
    # Under capacity - add all new goals
    for newGoal in newGoals:
      let newPlan = planForGoal(state, newGoal)
      if newPlan.isSome:
        tracker.addPlan(newPlan.get())
