## Multi-Turn Plan Tracking
##
## Tracks GOAP plan execution across multiple turns
## Detects when plans succeed, fail, or become invalid

import std/[tables, options, sequtils]
import ../core/types
import ../state/snapshot

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
  ## Mark current action as complete and advance to next
  if planIndex < 0 or planIndex >= tracker.activePlans.len:
    return

  tracker.activePlans[planIndex].currentActionIndex.inc()
  tracker.activePlans[planIndex].actionsCompleted.inc()
  tracker.activePlans[planIndex].lastUpdateTurn = tracker.currentTurn

  # Check if plan is complete
  let plan = tracker.activePlans[planIndex]
  if plan.currentActionIndex >= plan.plan.actions.len:
    tracker.activePlans[planIndex].status = PlanStatus.Completed

proc failPlan*(tracker: var PlanTracker, planIndex: int) =
  ## Mark plan as failed
  if planIndex < 0 or planIndex >= tracker.activePlans.len:
    return

  tracker.activePlans[planIndex].status = PlanStatus.Failed
  tracker.activePlans[planIndex].actionsFailed.inc()
  tracker.activePlans[planIndex].lastUpdateTurn = tracker.currentTurn

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

  # Check goal-specific validity
  case plan.plan.goal.goalType
  of GoalType.DefendColony:
    # If colony no longer vulnerable, plan succeeded early
    if plan.plan.goal.target.isSome:
      let targetSystem = plan.plan.goal.target.get()
      if targetSystem notin state.vulnerableColonies:
        return true  # Actually succeeded, not invalid

  of GoalType.InvadeColony:
    # If target colony no longer exists or already conquered
    if plan.plan.goal.target.isSome:
      let targetSystem = plan.plan.goal.target.get()
      # Check if we already own it (success)
      if targetSystem in state.ownedColonies:
        return true  # Succeeded
      # Check if target still exists as enemy colony
      let stillEnemy = state.knownEnemyColonies.anyIt(it.systemId == targetSystem)
      if not stillEnemy:
        return false  # Target disappeared (maybe destroyed)

  else:
    # Default: assume plan is still valid
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
