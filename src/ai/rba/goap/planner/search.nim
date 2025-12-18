## GOAP A* Search Algorithm
##
## Core planning algorithm: finds optimal action sequence to achieve goal

import std/[tables, options, heapqueue, sequtils, strutils]
import ../../../../common/types/[units, core]  # For ShipClass, SystemId, HouseId
import ../../../../engine/intelligence/types as intel_types  # For IntelQuality
import node
import ../core/[types, conditions, heuristics]
import ../state/[snapshot, effects]
import ../domains/fleet/actions  # For scout/spy action constructors
import ../../config  # For GOAPConfig

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
        actionType: ActionType.InvadePlanet,  # Changed from AttackColony
        cost: 50,
        duration: 1,
        target: goal.target,
        preconditions: @[hasMinBudget(50)],
        effects: @[
          createEffect(EffectKind.GainControl, {"systemId": int(goal.target.get())}.toTable)
        ],
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
# Prerequisite Action Generation (Phase 7: Intelligence Integration)
# =============================================================================

proc findPrerequisiteActions*(
  state: WorldStateSnapshot,
  unmetPrecondition: PreconditionRef,
  config: GOAPConfig
): seq[Action] =
  ## Find actions that can satisfy an unmet precondition
  ##
  ## Phase 7: Enables automatic intelligence gathering prerequisite planning
  ## Returns actions (Scout, Spy) that improve intel quality/freshness

  result = @[]

  let kind = parseEnum[ConditionKind](unmetPrecondition.conditionId)

  case kind
  of HasIntelQuality:
    # Need to improve intel quality for a system
    let systemId = SystemId(unmetPrecondition.params["systemId"])
    let minQuality = unmetPrecondition.params["minQuality"]
    let currentQuality = state.systemIntelQuality.getOrDefault(
      systemId,
      intel_types.IntelQuality.Visual
    )

    # If current quality insufficient, add scout action
    if int(currentQuality) < minQuality:
      # Scout improves to Scan (quality=2)
      if minQuality <= int(intel_types.IntelQuality.Scan):
        result.add(createConductScoutMissionAction(systemId))
      # Spy improves to Spy (quality=3) - requires scout first if no intel
      elif minQuality >= int(intel_types.IntelQuality.Spy):
        # Add scout first if we have no intel
        if currentQuality == intel_types.IntelQuality.Visual:
          result.add(createConductScoutMissionAction(systemId))
        # Then add spy action (requires target house, use placeholder)
        result.add(createSpyOnColonyAction(systemId, HouseId("unknown")))

  of HasFreshIntel:
    # Need fresh intel for a system
    let systemId = SystemId(unmetPrecondition.params["systemId"])
    # Scout mission refreshes intel
    result.add(createConductScoutMissionAction(systemId))

  of MeetsSpeculativeRequirements:
    # Speculative campaigns don't need intel prerequisites
    # These are proximity-based high-risk operations
    discard

  of MeetsRaidRequirements:
    # Raid requires Scan+ quality and ≤10 turn age
    let systemId = SystemId(unmetPrecondition.params["systemId"])
    let currentQuality = state.systemIntelQuality.getOrDefault(
      systemId,
      intel_types.IntelQuality.Visual
    )
    let currentAge = state.systemIntelAge.getOrDefault(systemId, 999)

    # If quality insufficient, scout
    if int(currentQuality) < int(intel_types.IntelQuality.Scan):
      result.add(createConductScoutMissionAction(systemId))
    # If too stale, refresh with scout
    elif currentAge > config.intelligence_thresholds.raid_max_intel_age:
      result.add(createConductScoutMissionAction(systemId))

  of MeetsAssaultRequirements:
    # Assault requires Spy+ quality and ≤5 turn age
    let systemId = SystemId(unmetPrecondition.params["systemId"])
    let currentQuality = state.systemIntelQuality.getOrDefault(
      systemId,
      intel_types.IntelQuality.Visual
    )
    let currentAge = state.systemIntelAge.getOrDefault(systemId, 999)

    # If quality insufficient, spy (may need scout first)
    if int(currentQuality) < int(intel_types.IntelQuality.Spy):
      if currentQuality == intel_types.IntelQuality.Visual:
        result.add(createConductScoutMissionAction(systemId))
      result.add(createSpyOnColonyAction(systemId, HouseId("unknown")))
    # If too stale, refresh
    elif currentAge > config.intelligence_thresholds.assault_max_intel_age:
      result.add(createSpyOnColonyAction(systemId, HouseId("unknown")))

  of MeetsDeliberateRequirements:
    # Deliberate requires Perfect quality and ≤3 turn age
    let systemId = SystemId(unmetPrecondition.params["systemId"])
    let currentQuality = state.systemIntelQuality.getOrDefault(
      systemId,
      intel_types.IntelQuality.Visual
    )

    # Perfect intel typically requires multiple spy missions
    if int(currentQuality) < int(intel_types.IntelQuality.Perfect):
      # Build intel chain: Scout → Spy → Perfect
      if currentQuality == intel_types.IntelQuality.Visual:
        result.add(createConductScoutMissionAction(systemId))
      if int(currentQuality) < int(intel_types.IntelQuality.Spy):
        result.add(createSpyOnColonyAction(systemId, HouseId("unknown")))
      # Additional spy for Perfect quality
      result.add(createSpyOnColonyAction(systemId, HouseId("unknown")))

  else:
    # Other conditions don't have intelligence prerequisites
    discard

# =============================================================================
# A* Search
# =============================================================================

proc planActions*(
  startState: WorldStateSnapshot,
  goal: Goal,
  availableActions: seq[Action],
  config: GOAPConfig,
  maxIterations: int = 1000
): Option[GOAPlan] =
  ## Find optimal action sequence using A* search
  ##
  ## Phase 7: Generates prerequisite intelligence actions when needed
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
        # Phase 7: Try to find prerequisite actions to satisfy unmet preconditions
        for precond in action.preconditions:
          if not checkPrecondition(current.state, precond):
            let prereqActions = findPrerequisiteActions(current.state, precond, config)

            # Add prerequisite actions as expansion nodes
            for prereqAction in prereqActions:
              # Apply prerequisite action to state
              var prereqState = current.state
              for effect in prereqAction.effects:
                applyEffect(prereqState, effect)

              # Calculate costs for prerequisite
              let prereqCost = estimateActionCost(current.state, prereqAction)
              let prereqTotalCost = current.totalCost + prereqCost
              let prereqEstimatedRemaining = estimateRemainingCost(
                prereqState,
                goal,
                current.actionsExecuted & @[prereqAction]
              )

              # Create prerequisite node
              let prereqNode = newPlanNode(
                prereqState,
                actionsExecuted = current.actionsExecuted & @[prereqAction],
                totalCost = prereqTotalCost,
                estimatedRemaining = prereqEstimatedRemaining,
                parent = some(current)
              )

              # Add to open set for exploration
              openSet.push(prereqNode)

        # Skip this action for now (prerequisites will be explored first)
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
    
  # Run A* search to find plan, using planning_depth * 100 as search node limit
  let maxSearchNodes = config.planning_depth * 100  # e.g., 10 turns * 100 = 1000 nodes
  let maybePlan = planActions(state, goal, availableActions, config, maxIterations = maxSearchNodes)
    
  if maybePlan.isSome:
    # Add confidence score to plan
    var plan = maybePlan.get()
    plan.confidence = estimatePlanConfidence(state, plan)
    return some(plan)
  else:
    return none(GOAPlan)
