## RBA Phase 1.5: GOAP Strategic Planning
##
## Inserted between Phase 1 (Requirements) and Phase 2 (Mediation)
## Extracts strategic goals from world state and generates multi-turn plans
##
## Integration Point:
## - Input: FilteredGameState, IntelligenceSnapshot, Requirements from Phase 1
## - Output: GOAPlan seq, enhanced requirements with cost estimates
## - Called by: order_generation.nim between phase1 and phase2

import std/[tables, options, sequtils, algorithm, times, strformat] # Add times for cpuTime(), strformat for &
import ../goap/core/types as goap_types
import ../goap/state/snapshot as goap_snapshot # Alias to avoid name clashes
import ../goap/planner/search
import ../goap/integration/[conversion, plan_tracking, replanning] # Added replanning for ReplanReason
import ../goap/domains/fleet/bridge as fleet_bridge # MVP: Fleet domain
# TODO: Build domain merged with Fleet in MVP - separate later
# import ../goap/domains/build/bridge as build_bridge # MVP: Build domain
import ../controller_types # For UnfulfillmentReason, RequirementFeedback
import ../shared/intelligence_types # For IntelligenceSnapshot
import ../../common/types as ai_types
import ../../../common/types/core
import ../../../engine/[gamestate, fog_of_war, logger, research/types as res_types] # Added res_types for TechField parsing
import ../../../engine/resolution/types as event_types # Use engine/resolution/types for GameEvent
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
): seq[goap_types.Goal] =
  ## Extract all strategic goals from current game state
  ##
  ## This is the main entry point for GOAP in RBA cycle
  ## Called after Phase 1 (Requirements generation)

  # TODO: This function needs FilteredGameState but doesn't receive it
  # Stubbed out for now since GOAP integration is incomplete
  result = @[]
  return

  # Original implementation (commented out until GOAP is properly integrated):
  # var allGoals: seq[Goal] = @[]
  # let worldState = createWorldStateSnapshot(filtered)
  # allGoals = extractAllGoalsFromState(worldState)
  #
  # # Apply priority weights from config
  # for i in 0 ..< allGoals.len:
  #   case allGoals[i].goalType
  #   # Defense goals - apply defense priority
  #   of GoalType.DefendColony, GoalType.SecureSystem:
  #     allGoals[i].priority *= config.defensePriority
  #
  #   # Offense goals - apply offense priority
  #   of GoalType.InvadeColony, GoalType.EliminateFleet:
  #     allGoals[i].priority *= config.offensePriority
  #
  #   else:
  #     discard
  #
  # # Sort by priority
  # result = prioritizeGoals(allGoals)
  #
  # # Limit to reasonable number based on budget
  # let affordableGoals = filterAffordableGoals(result, worldState.treasury)
  # if affordableGoals.len < result.len:
  #   result = affordableGoals

# =============================================================================
# Phase 1.5: Plan Generation
# =============================================================================

proc generateStrategicPlans*(
  goals: seq[goap_types.Goal],
  houseId: HouseId,
  homeworld: SystemId,
  currentTurn: int,
  intel: IntelligenceSnapshot,
  config: GOAPConfig
): seq[goap_types.GOAPlan] =
  ## Generate GOAP plans for goals
  ##
  ## Returns plans sorted by confidence * priority

  # TODO: This function needs FilteredGameState but doesn't receive it
  # Stubbed out for now since GOAP integration is incomplete
  result = @[]
  return

  # Original implementation (commented out until GOAP is properly integrated):
  # let worldState = createWorldStateSnapshot(filtered)
  #
  # # Generate plan for each goal
  # for goal in goals:
  #   let maybePlan = planForGoal(worldState, goal)
  #   if maybePlan.isSome:
  #     let plan = maybePlan.get()
  #
  #     # Filter by confidence threshold
  #     if plan.confidence >= config.confidenceThreshold:
  #       result.add(plan)
  #       if config.logPlans:
  #         logDebug(LogCategory.lcAI, &"GOAP Plan Generated: {getPlanDescription(plan)}")
  #
  # # Sort by confidence * priority
  # result = result.sortedByIt(-(it.confidence * it.goal.priority))
  #
  # # Limit to max concurrent plans
  # if result.len > config.maxConcurrentPlans:
  #   result = result[0 ..< config.maxConcurrentPlans]
  #   if config.logPlans:
  #     logDebug(LogCategory.lcAI, &"GOAP: Limiting to {config.maxConcurrentPlans} concurrent plans.")


# =============================================================================
# Phase 1.5: Budget Estimation
# =============================================================================

proc estimateBudgetRequirements*(
  plans: seq[goap_types.GOAPlan]
): Table[conversion.DomainType, int] =
  ## Estimate budget requirements by domain
  ##
  ## Used to enhance Phase 2 mediation with GOAP cost estimates
  ## Returns: DomainType → total cost

  result = initTable[conversion.DomainType, int]()

  for plan in plans:
    let domain = getDomainForGoal(plan.goal)

    if not result.hasKey(domain):
      result[domain] = 0

    result[domain] += plan.totalCost

proc convertBudgetEstimatesToStrings*(
  estimates: Table[conversion.DomainType, int]
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
    goals*: seq[goap_types.Goal]                           # Extracted strategic goals
    plans*: seq[goap_types.GOAPlan]                        # Generated plans
    budgetEstimates*: Table[conversion.DomainType, int]    # Budget requirements by domain
    budgetEstimatesStr*: Table[string, int]     # String-keyed estimates for treasurer
    planningTimeMs*: float                      # Performance metric

proc executePhase15_GOAP*(
  controller: var AIController,
  filtered: FilteredGameState,  # NEW: Accept filtered game state directly
  intel: IntelligenceSnapshot,
  config: GOAPConfig
): Phase15Result =
  ## Execute Phase 1.5: GOAP Strategic Planning (MVP: Fleet + Build domains only)
  ##
  ## This is called by order_generation.nim between phase1 and phase2.
  ## If GOAP disabled, returns empty result.

  result = Phase15Result(
    goals: @[],
    plans: @[],
    budgetEstimates: initTable[conversion.DomainType, int](),
    budgetEstimatesStr: initTable[string, int](),
    planningTimeMs: 0.0
  )

  if not config.enabled:
    logDebug(LogCategory.lcAI, &"{controller.houseId} GOAP disabled")
    return

  let startTime = cpuTime()

  # Create world state snapshot from filtered game state
  let worldState = goap_snapshot.createWorldStateSnapshot(filtered, intel)

  # Extract goals (Fleet only for MVP - Build domain merged with Fleet)
  var allGoals: seq[Goal] = @[]
  allGoals.add(fleet_bridge.extractFleetGoalsFromState(
    worldState,
    filtered.starMap,
    config
  ))
  # TODO: Build domain merged with Fleet in MVP - separate later
  # allGoals.add(build_bridge.extractBuildGoalsFromState(worldState))

  # Apply priority weights from config
  for i in 0 ..< allGoals.len:
    case allGoals[i].goalType
    of GoalType.DefendColony, GoalType.SecureSystem:
      allGoals[i].priority *= config.defense_priority
    of GoalType.InvadeColony, GoalType.EliminateFleet:
      allGoals[i].priority *= config.offense_priority
    else:
      discard

  # Sort and filter affordable goals
  result.goals = prioritizeGoals(allGoals)
  let affordableGoals = filterAffordableGoals(result.goals, worldState.treasury)
  if affordableGoals.len < result.goals.len:
    result.goals = affordableGoals

  logInfo(LogCategory.lcAI, &"{controller.houseId} GOAP: Extracted {result.goals.len} goals")

  # Generate plans for each goal
  for goal in result.goals:
    let maybePlan = planForGoal(config, worldState, goal)
    if maybePlan.isSome:
      let plan = maybePlan.get()
      if plan.confidence >= config.confidence_threshold:
        result.plans.add(plan)
        if config.log_plans:
          logDebug(LogCategory.lcAI, &"GOAP Plan: {plan.goal.description}")
      else:
        logDebug(LogCategory.lcAI,
          &"GOAP: Rejected plan for {goal.goalType} (confidence {plan.confidence:.2f} < threshold {config.confidence_threshold})")
    else:
      logDebug(LogCategory.lcAI,
        &"GOAP: No plan found for {goal.goalType} (goal: {goal.description})")

  # Sort by confidence * priority, limit to max concurrent
  result.plans = result.plans.sortedByIt(-(it.confidence * it.goal.priority))
  if result.plans.len > config.max_concurrent_plans:
    result.plans = result.plans[0 ..< config.max_concurrent_plans]

  logInfo(LogCategory.lcAI, &"{controller.houseId} GOAP: Generated {result.plans.len} plans")

  # Estimate budget requirements (for future Phase 2 integration)
  result.budgetEstimates = estimateBudgetRequirements(result.plans)
  result.budgetEstimatesStr = convertBudgetEstimatesToStrings(result.budgetEstimates)

  result.planningTimeMs = (cpuTime() - startTime) * 1000.0
  logInfo(LogCategory.lcAI, &"{controller.houseId} GOAP planning: {result.planningTimeMs:.2f} ms")

  return result

# =============================================================================
# Phase 1.5: Integration Helpers
# =============================================================================

proc integrateGOAPPlansIntoController*(
  controller: var AIController,
  plans: seq[goap_types.GOAPlan]
) =
  ## Store new GOAP plans in AI controller's PlanTracker for active tracking.
  ## This is called after Phase 1.5 if new plans are generated.

  # TODO: GOAP integration incomplete (controller.goapPlanTracker field doesn't exist)
  # Stubbed out for now
  discard

  # Original implementation:
  # for plan in plans:
  #   controller.goapPlanTracker.addPlan(plan)
  #   logInfo(LogCategory.lcAI, &"{controller.houseId} GOAP: Actively tracking plan for goal: {plan.goal.description}")
