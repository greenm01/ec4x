## Multi-Turn Plan Tracking
##
## Tracks GOAP plan execution across multiple turns
## Detects when plans succeed, fail, or become invalid

import std/[tables, options, sequtils]
import ../core/types
import ../state/snapshot
import ../../controller_types # For UnfulfillmentReason, RequirementFeedback

# =============================================================================
# Plan Status Types
# =============================================================================

type
  PlanStatus* {.pure.} = enum
    ## Status of a multi-turn plan
    Active        # Plan is currently being executed
    Completed     # Plan successfully achieved its goal
    Failed        # Plan failed (action couldn't be executed)
    Invalidated   # Plan no longer viable (preconditions violated)
    Paused        # Plan temporarily paused (lower priority work)

  TrackedPlan* = object
    ## A GOAP plan being tracked across turns
    plan*: GOAPlan
    status*: PlanStatus
    startTurn*: int
    currentActionIndex*: int  # Which action we're executing
    turnsInExecution*: int    # How many turns we've been working on this

    # Success/failure tracking
    actionsCompleted*: int
    actionsFailed*: int
    lastUpdateTurn*: int
    # Specific feedback for the last failed action, used for intelligent replanning
    lastFailedActionReason*: Option[UnfulfillmentReason]
    lastFailedActionSuggestion*: Option[string]

# =============================================================================
# Plan Tracker
# =============================================================================

type
  PlanTracker* = object
    ## Manages all active GOAP plans for a house
    activePlans*: seq[TrackedPlan]
    completedPlans*: seq[TrackedPlan]  # History
    currentTurn*: int

proc newPlanTracker*(): PlanTracker =
  ## Create a new plan tracker
  result = PlanTracker(
    activePlans: @[],
    completedPlans: @[],
    currentTurn: 0
  )

proc addPlan*(tracker: var PlanTracker, plan: GOAPlan) =
  ## Start tracking a new plan
  let tracked = TrackedPlan(
    plan: plan,
    status: PlanStatus.Active,
    startTurn: tracker.currentTurn,
    currentActionIndex: 0,
    turnsInExecution: 0,
    actionsCompleted: 0,
    actionsFailed: 0,
    lastUpdateTurn: tracker.currentTurn
  )
  tracker.activePlans.add(tracked)

# =============================================================================
# Plan Progress Tracking
# =============================================================================

proc advancePlan*(tracker: var PlanTracker, planIndex: int) =
  ## Mark current action as complete and advance to next action in the plan.
  ## This is typically called by the feedback system after RBA successfully executes a GOAP-aligned action.
  if planIndex < 0 or planIndex >= tracker.activePlans.len:
    return

  tracker.activePlans[planIndex].currentActionIndex.inc()
  tracker.activePlans[planIndex].actionsCompleted.inc()
  tracker.activePlans[planIndex].lastUpdateTurn = tracker.currentTurn

  # Check if the plan is fully completed
  if tracker.activePlans[planIndex].currentActionIndex >= tracker.activePlans[planIndex].plan.actions.len:
    tracker.activePlans[planIndex].status = PlanStatus.Completed
    # Optionally, add some final state assessment to confirm goal achievement
    # For now, reaching the end of actions marks it as completed.

proc markActionComplete*(tracker: var PlanTracker, planIndex: int, actionIndex: int) =
  ## Mark a specific action within a plan as complete, without necessarily advancing.
  ## Useful for out-of-sequence completion or for re-validating the plan.
  if planIndex < 0 or planIndex >= tracker.activePlans.len or
     actionIndex < 0 or actionIndex >= tracker.activePlans[planIndex].plan.actions.len:
    return

  # For now, we only advance the currentActionIndex if the completed action is the *current* one.
  # If an earlier action is reported as complete, we just update total count.
  if actionIndex == tracker.activePlans[planIndex].currentActionIndex:
    tracker.activePlans[planIndex].currentActionIndex.inc()
  tracker.activePlans[planIndex].actionsCompleted.inc()
  tracker.activePlans[planIndex].lastUpdateTurn = tracker.currentTurn

  if tracker.activePlans[planIndex].currentActionIndex >= tracker.activePlans[planIndex].plan.actions.len:
    tracker.activePlans[planIndex].status = PlanStatus.Completed


proc failPlan*(tracker: var PlanTracker, planIndex: int) =
  ## Mark a plan as having failed its execution.
  ## This typically triggers replanning or cancellation.
  if planIndex < 0 or planIndex >= tracker.activePlans.len:
    return

  tracker.activePlans[planIndex].status = PlanStatus.Failed
  tracker.activePlans[planIndex].actionsFailed.inc()
  tracker.activePlans[planIndex].lastUpdateTurn = tracker.currentTurn


proc markActionFailed*(
  tracker: var PlanTracker,
  planIndex: int,
  actionIndex: int,
  unfulfillmentReason: Option[UnfulfillmentReason] = none(UnfulfillmentReason),
  suggestion: Option[string] = none(string)
) =
  ## Mark a specific action within a plan as failed.
  ## If the current action fails, the plan effectively fails.
  if planIndex < 0 or planIndex >= tracker.activePlans.len or
     actionIndex < 0 or actionIndex >= tracker.activePlans[planIndex].plan.actions.len:
    return

  tracker.activePlans[planIndex].actionsFailed.inc()
  tracker.activePlans[planIndex].status = PlanStatus.Failed # A single failed action often means the plan failed
  tracker.activePlans[planIndex].lastUpdateTurn = tracker.currentTurn
  tracker.activePlans[planIndex].lastFailedActionReason = unfulfillmentReason
  tracker.activePlans[planIndex].lastFailedActionSuggestion = suggestion

proc pausePlan*(tracker: var PlanTracker, planIndex: int) =
  ## Temporarily pause a plan
  if planIndex < 0 or planIndex >= tracker.activePlans.len:
    return

  tracker.activePlans[planIndex].status = PlanStatus.Paused
  tracker.activePlans[planIndex].lastUpdateTurn = tracker.currentTurn

proc resumePlan*(tracker: var PlanTracker, planIndex: int) =
  ## Resume a paused plan
  if planIndex < 0 or planIndex >= tracker.activePlans.len:
    return

  if tracker.activePlans[planIndex].status == PlanStatus.Paused:
    tracker.activePlans[planIndex].status = PlanStatus.Active
    tracker.activePlans[planIndex].lastUpdateTurn = tracker.currentTurn

# =============================================================================
# Plan Validation
# =============================================================================

proc isPlanStillValid*(plan: TrackedPlan, state: WorldStateSnapshot): bool =
  ## Check if plan's preconditions are still met
  ##
  ## Returns false if world state changed such that plan can't continue

  # Check if we have budget for remaining actions
  var remainingCost = 0
  for i in plan.currentActionIndex ..< plan.plan.actions.len:
    remainingCost += plan.plan.actions[i].cost

  if state.treasury < remainingCost:
    # NOTE: This is a soft check - plan might still be valid if budget arrives
    # For now, we don't immediately invalidate on budget shortfall
    discard

  # Check goal-specific validity (refined for common cases)
  case plan.plan.goal.goalType
  of GoalType.DefendColony:
    # If the target colony is no longer vulnerable (e.g., threat removed, or defenses built up)
    # AND if the goal's target system is defined.
    if plan.plan.goal.target.isSome:
      let targetSystem = plan.plan.goal.target.get()
      # If the system is not in the list of currently vulnerable colonies (meaning it's safe now)
      if not state.vulnerableColonies.anyIt(it == targetSystem):
        return true  # Goal implicitly achieved/no longer needed, plan is valid but should be completed.

  of GoalType.InvadeColony, GoalType.SecureSystem:
    # If the target system is now owned by us, the goal is achieved.
    # OR if the target no longer exists (destroyed) or is no longer an enemy.
    if plan.plan.goal.target.isSome:
      let targetSystem = plan.plan.goal.target.get()
      if targetSystem in state.ownedColonies:
        return true # Goal achieved.
      # Check if the target is still an *enemy* colony for invasion/securing.
      let stillEnemyTarget = state.knownEnemyColonies.anyIt(it.systemId == targetSystem)
      if not stillEnemyTarget:
        # Target is no longer an enemy colony (e.g., neutral, destroyed, or another AI took it)
        return false # Plan is invalid as its premise (attacking an enemy colony) is false.

  of GoalType.AchieveTechLevel, GoalType.CloseResearchGap:
    # If the house already has the desired tech level.
    if plan.plan.goal.techField.isSome and plan.plan.goal.requiredTechLevel.isSome:
      let field = plan.plan.goal.techField.get()
      let requiredLevel = plan.plan.goal.requiredTechLevel.get()
      if state.techLevels.getOrDefault(field, 0) >= requiredLevel:
        return true # Goal achieved.

  of GoalType.EliminateFleet:
    # If the target fleet no longer exists or is not in the system.
    if plan.plan.goal.targetFleet.isSome and plan.plan.goal.target.isSome:
      let targetFleetId = plan.plan.goal.targetFleet.get()
      let targetSystemId = plan.plan.goal.target.get()
      # Check if any enemy fleet matching the target is still present at the system
      let enemyFleetPresent = state.fleetsAtSystem.getOrDefault(targetSystemId, @[]).anyIt(
        it.owner != state.houseId and it.fleetId == targetFleetId)
      if not enemyFleetPresent:
        return true # Goal achieved (fleet eliminated or moved).

  else:
    # For other goal types, a general check might be applied or they are assumed valid
    # until explicit failure is reported or a more specific validity check is added.
    discard

  return true

proc validateAllPlans*(tracker: var PlanTracker, state: WorldStateSnapshot) =
  ## Check all active plans for validity
  ##
  ## Marks plans as Invalidated if preconditions no longer hold

  for i in 0 ..< tracker.activePlans.len:
    if tracker.activePlans[i].status != PlanStatus.Active:
      continue

    if not isPlanStillValid(tracker.activePlans[i], state):
      tracker.activePlans[i].status = PlanStatus.Invalidated
      tracker.activePlans[i].lastUpdateTurn = tracker.currentTurn

# =============================================================================
# Plan Cleanup
# =============================================================================

proc archiveCompletedPlans*(tracker: var PlanTracker) =
  ## Move completed/failed/invalidated plans to history

  var stillActive: seq[TrackedPlan] = @[]

  for plan in tracker.activePlans:
    if plan.status in [PlanStatus.Completed, PlanStatus.Failed, PlanStatus.Invalidated]:
      tracker.completedPlans.add(plan)
    else:
      stillActive.add(plan)

  tracker.activePlans = stillActive

proc getActivePlanCount*(tracker: PlanTracker): int =
  ## Count currently active plans
  result = 0
  for plan in tracker.activePlans:
    if plan.status == PlanStatus.Active:
      result.inc()

proc getNextAction*(tracker: PlanTracker, planIndex: int): Option[Action] =
  ## Get the next action to execute for a plan
  if planIndex < 0 or planIndex >= tracker.activePlans.len:
    return none(Action)

  let plan = tracker.activePlans[planIndex]
  if plan.currentActionIndex >= plan.plan.actions.len:
    return none(Action)  # Plan complete

  return some(plan.plan.actions[plan.currentActionIndex])

proc getPlanProgress*(plan: TrackedPlan): float =
  ## Returns the progress of the plan as a percentage (0.0 to 1.0).
  if plan.plan.actions.len == 0:
    return 1.0 # A plan with no actions is "completed"

  result = plan.actionsCompleted.float / plan.plan.actions.len.float

proc getPlanDescription*(plan: GOAPlan): string =
  ## Provides a concise description of the GOAP plan and its goal.
  result = $"Goal: {plan.goal.description} (P: {plan.goal.priority:.2f}) - {plan.actions.len} actions, {plan.totalCost} PP, {plan.estimatedTurns} turns"

# =============================================================================
# Turn Update
# =============================================================================

proc advanceTurn*(tracker: var PlanTracker, newTurn: int, state: WorldStateSnapshot) =
  ## Update tracker for new turn
  ##
  ## - Validates all plans
  ## - Archives completed plans
  ## - Updates turn counters

  tracker.currentTurn = newTurn

  # Update execution time for all active plans
  for i in 0 ..< tracker.activePlans.len:
    if tracker.activePlans[i].status == PlanStatus.Active:
      tracker.activePlans[i].turnsInExecution.inc()

  # Validate plans against current state
  validateAllPlans(tracker, state)

  # Archive finished plans
  archiveCompletedPlans(tracker)
