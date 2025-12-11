## GOAP A* Search Algorithm
##
## Core planning algorithm: finds optimal action sequence to achieve goal

import std/[tables, options, heapqueue, sequtils]
import ../../../../common/types/units  # For ShipClass
import node
import ../core/[types, conditions, heuristics]
import ../state/[snapshot, effects]

# =============================================================================
# Goal Success Checking
# =============================================================================

proc isGoalAchieved(state: WorldStateSnapshot, goal: Goal): bool =
  ## Goal-specific success checks (pragmatic for MVP)
  ## Returns true if the goal has been achieved in the current state
  case goal.goalType
  of GoalType.DefendColony:
    if goal.target.isNone: return false
    return goal.target.get() notin state.undefendedColonies

  of GoalType.InvadeColony:
    if goal.target.isNone: return false
    return goal.target.get() in state.ownedColonies

  of GoalType.BuildFleet:
    return state.idleFleets.len > 0

  of GoalType.EstablishShipyard:
    return true  # Assume success for MVP (track shipyards post-MVP)

  else:
    return false

# =============================================================================
# Action Library (Domain-Specific)
# =============================================================================

proc getAvailableActionsForGoal(state: WorldStateSnapshot, goal: Goal): seq[Action] =
  ## Return actions applicable to this goal type (Fleet + Build only for MVP)
  result = @[]

  case goal.goalType
  of GoalType.DefendColony:
    if goal.target.isSome and state.idleFleets.len > 0:
      result.add(Action(
        actionType: ActionType.MoveFleet,
        cost: 10,
        duration: 1,
        target: goal.target,
        preconditions: @[hasMinBudget(10)],
        effects: @[],
        description: "Move fleet to " & $goal.target.get()
      ))
      result.add(Action(
        actionType: ActionType.EstablishDefense,
        cost: 0,
        duration: 1,
        target: goal.target,
        preconditions: @[],
        effects: @[],
        description: "Assign defense duty"
      ))

  of GoalType.InvadeColony:
    if goal.target.isSome:
      result.add(Action(
        actionType: ActionType.MoveFleet,
        cost: 10,
        duration: 2,
        target: goal.target,
        preconditions: @[hasMinBudget(10)],
        effects: @[],
        description: "Move invasion force"
      ))
      result.add(Action(
        actionType: ActionType.AttackColony,
        cost: 50,
        duration: 1,
        target: goal.target,
        preconditions: @[hasMinBudget(50)],
        effects: @[],
        description: "Invade colony"
      ))

  of GoalType.BuildFleet:
    if goal.target.isSome:
      result.add(Action(
        actionType: ActionType.ConstructShips,
        cost: 100,
        duration: 2,
        target: goal.target,
        shipClass: some(ShipClass.Cruiser),
        quantity: 1,
        preconditions: @[hasMinBudget(100), controlsSystem(goal.target.get())],
        effects: @[],
        description: "Build 1 Cruiser"
      ))

  of GoalType.EstablishShipyard:
    if goal.target.isSome:
      result.add(Action(
        actionType: ActionType.BuildFacility,
        cost: 150,
        duration: 3,
        target: goal.target,
        preconditions: @[hasMinBudget(150), controlsSystem(goal.target.get())],
        effects: @[],
        description: "Build Shipyard"
      ))

  else:
    discard

# =============================================================================
# A* Search
# =============================================================================

proc planActions*(
  startState: WorldStateSnapshot,
  goal: Goal,
  availableActions: seq[Action],
  maxIterations: int = 1000
): Option[GOAPlan] =
  ## Find optimal action sequence using A* search
  ##
  ## Returns none if no plan found within iteration limit

  # Initialize open set (priority queue)
  var openSet = initHeapQueue[ref PlanNode]()

  # Initial node
  let initialNode = newPlanNode(
    startState,
    actionsExecuted = @[],
    totalCost = 0.0,
    estimatedRemaining = estimateGoalCost(startState, goal)
  )
  openSet.push(initialNode)

  # Closed set (visited states)
  var closedStates: seq[int] = @[]  # Simplified: hash of state

  var iterations = 0

  while openSet.len > 0 and iterations < maxIterations:
    iterations.inc()

    # Get node with lowest f(n)
    let current = openSet.pop()

    # Goal check: Are we there yet?
    if isGoalAchieved(current.state, goal):
      # Found solution! Reconstruct path
      return some(GOAPlan(
        goal: goal,
        actions: current.actionsExecuted,
        totalCost: current.totalCost.int,
        estimatedTurns: current.actionsExecuted.mapIt(it.duration).foldl(a + b, 0),
        confidence: estimatePlanConfidence(current.state, GOAPlan(
          goal: goal,
          actions: current.actionsExecuted,
          totalCost: current.totalCost.int,
          estimatedTurns: 0,
          confidence: 0.0,
          dependencies: @[]
        )),
        dependencies: @[]
      ))

    # Expand node: try all applicable actions
    for action in availableActions:
      # Check if action is applicable (preconditions met)
      if not allPreconditionsMet(current.state, action.preconditions):
        continue

      # Apply action to get successor state
      var successorState = current.state
      for effect in action.effects:
        applyEffect(successorState, effect)

      # Calculate costs
      let actionCost = estimateActionCost(current.state, action)
      let newTotalCost = current.totalCost + actionCost
      let newEstimatedRemaining = estimateRemainingCost(
        successorState,
        goal,
        current.actionsExecuted & @[action]
      )

      # Create successor node
      let successorNode = newPlanNode(
        successorState,
        actionsExecuted = current.actionsExecuted & @[action],
        totalCost = newTotalCost,
        estimatedRemaining = newEstimatedRemaining,
        parent = some(current)
      )

      # Add to open set
      openSet.push(successorNode)

  # No plan found
  return none(GOAPlan)

# =============================================================================
# High-Level Planning Interface
# =============================================================================

proc planForGoal*(
  config: GOAPConfig, # NEW: Pass GOAP config
  state: WorldStateSnapshot,
  goal: Goal
): Option[GOAPlan] =
  ## Plan action sequence for goal (MVP: Fleet + Build domains)
  ##
  ## Uses A* search to find optimal action sequence
  ## Returns none if no actions available or no plan found
    
  # Get domain-specific actions for this goal
  let availableActions = getAvailableActionsForGoal(state, goal)
    
  if availableActions.len == 0:
    return none(GOAPlan)
    
  # Run A* search to find plan, using max_search_nodes from config
  let maybePlan = planActions(state, goal, availableActions, maxIterations = config.max_search_nodes)
    
  if maybePlan.isSome:
    # Add confidence score to plan
    var plan = maybePlan.get()
    plan.confidence = estimatePlanConfidence(state, plan)
    return some(plan)
  else:
    return none(GOAPlan)
