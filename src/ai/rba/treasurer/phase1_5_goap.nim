import std/[tables, options, strformat]
import ../../../engine/[gamestate, logger, order_types, starmap]
import ../../../engine/intelligence/types as intel_types
import ../../../ai/goap/types # For Goal, Action, GOAPlan, GOAPConfig
import ../../../ai/goap/plan_tracking # For PlanTracker, TrackedPlan
import ../../../ai/goap/snapshot # For createWorldStateSnapshot
import ../../../ai/goap/conversion # For extractAllGoalsFromState, allocateBudgetToGoals, DomainType
import ../../../ai/goap/search # For planForGoal
import ../../../ai/goap/heuristics # For estimateGoalCost
import ../controller_types # For AIController, BuildRequirements etc.
import ../config # For globalRBAConfig

# Phase 1.5 result type for GOAP budget guidance
type
  Phase15Result* = object
    goapBudgetEstimates*: Option[Table[DomainType, int]]
    activeGoalsDescription*: seq[string] # For logging/debugging

proc defaultGOAPConfig*(): GOAPConfig =
  ## Provides a default GOAP configuration.
  ## This will be loaded from a config file eventually.
  result = GOAPConfig(
    maxSearchNodes: 5000,
    maxPlanLength: 10,
    planHorizonTurns: 5,
    minGoalPriority: 0.1,
    replanIntervalTurns: 3,
    debugLogging: false
  )

proc extractStrategicGoals*(
  controller: var AIController,
  filtered: FilteredGameState,
  domestikosReqs: BuildRequirements,
  logotheteReqs: ResearchRequirements,
  drungariusReqs: EspionageRequirements,
  eparchReqs: EconomicRequirements,
  protostratorReqs: DiplomaticRequirements
): seq[Goal] =
  ## Extracts strategic goals from the current game state and advisor requirements.
  ## This is a placeholder for a more sophisticated goal extraction logic.
  ## For now, it will use the GOAP's internal `extractAllGoalsFromState` which
  ## examines the `WorldStateSnapshot` for predefined goal conditions.

  let worldState = createWorldStateSnapshot(filtered, controller.houseId)
  # TODO: Integrate RBA requirements into GOAP goals more explicitly
  # For now, GOAP's own goal extraction from world state is primary
  result = extractAllGoalsFromState(worldState)

  # For debugging, log extracted goals
  if controller.goapConfig.debugLogging:
    logInfo(LogCategory.lcAI, &"{controller.houseId} GOAP: Extracted {result.len} potential goals.")
    for i, goal in result:
      logInfo(LogCategory.lcAI, &"  Goal {i+1}: {goal.name} (Priority: {goal.priority})")

proc generateStrategicPlans*(
  controller: var AIController,
  filtered: FilteredGameState,
  goals: seq[Goal]
): void =
  ## Generates new GOAP plans for unaddressed goals or refreshes existing ones.
  ## Stores active plans in controller.planTracker.

  let worldState = createWorldStateSnapshot(filtered, controller.houseId)

  # Advance existing plans in the tracker first
  controller.planTracker.advanceTurn(filtered.turn, worldState)

  # Filter out goals for which there are already active plans
  var unaddressedGoals: seq[Goal] = @[]
  for goal in goals:
    var hasActivePlan = false
    for trackedPlan in controller.planTracker.activePlans:
      if trackedPlan.goal == goal: # Assuming Goal comparison works or specific ID check
        hasActivePlan = true
        break
    if not hasActivePlan:
      unaddressedGoals.add(goal)

  if unaddressedGoals.len > 0:
    logInfo(LogCategory.lcAI, &"{controller.houseId} GOAP: Attempting to plan for {unaddressedGoals.len} unaddressed goals.")

  for goal in unaddressedGoals:
    logInfo(LogCategory.lcAI, &"{controller.houseId} GOAP: Planning for goal: {goal.name} (Priority: {goal.priority})")
    let plan = planForGoal(controller.goapConfig, worldState, goal)
    if plan.isSome:
      let newPlan = plan.get()
      controller.planTracker.addPlan(TrackedPlan(
        goal: goal,
        plan: newPlan,
        currentActionIndex: 0,
        status: PlanStatus.Active,
        startedTurn: filtered.turn
      ))
      logInfo(LogCategory.lcAI, &"{controller.houseId} GOAP: Successfully generated plan for {goal.name}.")
      if controller.goapConfig.debugLogging:
        logInfo(LogCategory.lcAI, &"  Plan actions: {newPlan.actions.len}, Estimated Cost: {estimateGoalCost(worldState, goal)}")
    else:
      logWarn(LogCategory.lcAI, &"{controller.houseId} GOAP: Failed to generate plan for {goal.name}.")

  controller.goapLastPlanningTurn = filtered.turn
  controller.goapActiveGoals = newSeq[string]()
  for trackedPlan in controller.planTracker.activePlans:
    controller.goapActiveGoals.add(trackedPlan.goal.name)

proc estimateBudgetRequirements*(
  controller: AIController,
  filtered: FilteredGameState
): Option[Table[DomainType, int]] =
  ## Estimates current-turn budget requirements based on active GOAP plans.
  ## Uses the allocateBudgetToGoals function to sum up costs by domain.

  if controller.planTracker.activePlans.len == 0:
    return none(Table[DomainType, int])

  let worldState = createWorldStateSnapshot(filtered, controller.houseId)
  let estimates = allocateBudgetToGoals(
    filtered.ownHouse.treasury, # Current treasury, for context (not hard limit)
    controller.planTracker.activePlans,
    filtered.turn
  )

  if estimates.len > 0:
    if controller.goapConfig.debugLogging:
      logInfo(LogCategory.lcAI, &"{controller.houseId} GOAP: Current turn budget estimates:")
      for domain, cost in estimates:
        logInfo(LogCategory.lcAI, &"  - {domain}: {cost}PP")
    return some(estimates)
  else:
    return none(Table[DomainType, int])

proc executePhase15_GOAP*(
  controller: var AIController,
  filtered: FilteredGameState,
  domestikosReqs: BuildRequirements,
  logotheteReqs: ResearchRequirements,
  drungariusReqs: EspionageRequirements,
  eparchReqs: EconomicRequirements,
  protostratorReqs: DiplomaticRequirements
): Phase15Result =
  ## Main entry point for GOAP Phase 1.5: Strategic Planning.
  ## Orchestrates goal extraction, plan generation/tracking, and budget estimation.

  result = Phase15Result(
    goapBudgetEstimates: none(Table[DomainType, int]),
    activeGoalsDescription: @[]
  )

  if not controller.goapEnabled:
    logDebug(LogCategory.lcAI, &"{controller.houseId} GOAP: Disabled for this AI.")
    return result

  # Ensure GOAPConfig is initialized
  if controller.goapConfig.maxSearchNodes == 0: # Default check for uninitialized config
    controller.goapConfig = defaultGOAPConfig()
    logInfo(LogCategory.lcAI, &"{controller.houseId} GOAP: Initialized default GOAPConfig.")

  # Step 1: Extract strategic goals
  let goals = extractStrategicGoals(
    controller, filtered, domestikosReqs, logotheteReqs, drungariusReqs,
    eparchReqs, protostratorReqs
  )

  # Step 2: Generate/track strategic plans
  if filtered.turn == 0 or (filtered.turn - controller.goapLastPlanningTurn) >= controller.goapConfig.replanIntervalTurns:
    generateStrategicPlans(controller, filtered, goals)
  else:
    # Still advance plan tracker even if not replanning
    let worldState = createWorldStateSnapshot(filtered, controller.houseId)
    controller.planTracker.advanceTurn(filtered.turn, worldState)
    controller.goapActiveGoals = newSeq[string]()
    for trackedPlan in controller.planTracker.activePlans:
      controller.goapActiveGoals.add(trackedPlan.goal.name)

  # Step 3: Estimate current-turn budget requirements from active plans and store in controller
  let estimates = estimateBudgetRequirements(controller, filtered)
  controller.goapBudgetEstimates = estimates # Store in controller for Basileus to retrieve
  result.goapBudgetEstimates = estimates
  result.activeGoalsDescription = controller.goapActiveGoals

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} GOAP: Phase 1.5 complete - " &
          &"{controller.planTracker.activePlans.len} active plans, " &
          &"estimated budget={result.goapBudgetEstimates.isSome}")

  return result
