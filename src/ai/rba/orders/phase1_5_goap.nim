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
import ../goap/integration/[conversion, plan_tracking]
import ../controller_types
import ../../common/types as ai_types
import ../../../common/types/core
import ../../../engine/[gamestate, fog_of_war, logger] # Add logger
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
  houseId: HouseId, # Pass houseId
  homeworld: SystemId, # Pass homeworld
  currentTurn: int, # Pass current turn
  intel: IntelligenceSnapshot,
  config: GOAPConfig
): Phase15Result =
  ## Execute Phase 1.5: GOAP Strategic Planning
  ##
  ## This is called by order_generation.nim between phase1 and phase2
  ## If GOAP disabled, returns empty result

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
  result.goals = extractStrategicGoals(houseId, homeworld, currentTurn, intel, config)
  logInfo(LogCategory.lcAI, &"{houseId} GOAP: Extracted {result.goals.len} strategic goals.")

  # Step 2: Generate plans
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
