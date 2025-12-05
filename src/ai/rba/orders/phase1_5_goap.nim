## RBA Phase 1.5: GOAP Strategic Planning
##
## Inserted between Phase 1 (Requirements) and Phase 2 (Mediation)
## Extracts strategic goals from world state and generates multi-turn plans
##
## Integration Point:
## - Input: FilteredGameState, IntelligenceSnapshot, Requirements from Phase 1
## - Output: GOAPlan seq, enhanced requirements with cost estimates
## - Called by: order_generation.nim between phase1 and phase2

import std/[tables, options, sequtils, algorithm]
import ../goap/core/types
import ../goap/state/snapshot
import ../goap/planner/search
import ../goap/integration/[conversion, plan_tracking]
import ../controller_types
import ../../common/types as ai_types
import ../../../common/types/core
import ../../../engine/[gamestate, fog_of_war]

# =============================================================================
# GOAP Integration Configuration
# =============================================================================

type
  GOAPConfig* = object
    ## Configuration for GOAP strategic planning
    enabled*: bool                    # Enable/disable GOAP
    planningDepth*: int               # Max turns to plan ahead
    confidenceThreshold*: float       # Min confidence to execute plan
    maxConcurrentPlans*: int          # Max active plans at once
    defensePriority*: float           # Weight for defensive goals (0.0-1.0)
    offensePriority*: float           # Weight for offensive goals (0.0-1.0)
    logPlans*: bool                   # Debug: log all generated plans

proc defaultGOAPConfig*(): GOAPConfig =
  ## Default GOAP configuration
  result = GOAPConfig(
    enabled: true,
    planningDepth: 5,
    confidenceThreshold: 0.6,
    maxConcurrentPlans: 5,
    defensePriority: 0.7,
    offensePriority: 0.5,
    logPlans: false
  )

# =============================================================================
# Phase 1.5: Goal Extraction
# =============================================================================

proc extractStrategicGoals*(
  state: FilteredGameState,
  intel: IntelligenceSnapshot,
  config: GOAPConfig
): seq[Goal] =
  ## Extract all strategic goals from current game state
  ##
  ## This is the main entry point for GOAP in RBA cycle
  ## Called after Phase 1 (Requirements generation)

  # Convert to WorldStateSnapshot for GOAP
  let worldState = createWorldStateSnapshot(state, intel)

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
  state: FilteredGameState,
  intel: IntelligenceSnapshot,
  config: GOAPConfig
): seq[GOAPlan] =
  ## Generate GOAP plans for goals
  ##
  ## Returns plans sorted by confidence * priority

  result = @[]

  let worldState = createWorldStateSnapshot(state, intel)

  # Generate plan for each goal
  for goal in goals:
    let maybePlan = planForGoal(worldState, goal)
    if maybePlan.isSome:
      let plan = maybePlan.get()

      # Filter by confidence threshold
      if plan.confidence >= config.confidenceThreshold:
        result.add(plan)

  # Sort by confidence * priority
  result = result.sortedByIt(-(it.confidence * it.goal.priority))

  # Limit to max concurrent plans
  if result.len > config.maxConcurrentPlans:
    result = result[0 ..< config.maxConcurrentPlans]

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

proc annotatePlansWithBudget*(
  plans: seq[GOAPlan],
  availableBudget: int
): seq[tuple[plan: GOAPlan, allocated: int, fundingRatio: float]] =
  ## Annotate plans with budget allocation
  ##
  ## Used when budget is limited - determines how much each plan gets

  result = @[]

  let goals = plans.mapIt(it.goal)
  let allocations = allocateBudgetToGoals(goals, availableBudget)

  for alloc in allocations:
    # Find the plan matching this goal
    for plan in plans:
      if plan.goal.goalType == alloc.goal.goalType and
         plan.goal.target == alloc.goal.target:
        result.add((
          plan: plan,
          allocated: alloc.allocated,
          fundingRatio: alloc.fundingRatio
        ))
        break

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
  state: FilteredGameState,
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
    return  # GOAP disabled, skip

  # TODO: Add timing
  # let startTime = cpuTime()

  # Step 1: Extract strategic goals
  result.goals = extractStrategicGoals(state, intel, config)

  # Step 2: Generate plans
  result.plans = generateStrategicPlans(result.goals, state, intel, config)

  # Step 3: Estimate budget requirements
  result.budgetEstimates = estimateBudgetRequirements(result.plans)
  result.budgetEstimatesStr = convertBudgetEstimatesToStrings(result.budgetEstimates)

  # TODO: Calculate planning time
  # result.planningTimeMs = (cpuTime() - startTime) * 1000.0

  # Debug logging
  if config.logPlans:
    # TODO: Add proper logging
    # logger.info(&"Phase 1.5 GOAP: Generated {result.plans.len} plans from {result.goals.len} goals")
    discard

# =============================================================================
# Phase 1.5: Integration Helpers
# =============================================================================

proc mergeGOAPEstimatesIntoDomestikosRequirements*(
  requirements: var BuildRequirements,
  budgetEstimates: Table[DomainType, int]
) =
  ## Merge GOAP budget estimates into Domestikos build requirements
  ##
  ## Enhances Phase 2 mediation with strategic cost awareness
  ## Modifies requirements in-place

  # TODO Phase 4: Implement requirements enhancement
  # This would add GOAP cost estimates as additional data on requirements
  # For now, this is a placeholder

  discard

proc integrateGOAPPlansIntoController*(
  controller: var AIController,
  plans: seq[GOAPlan]
) =
  ## Store GOAP plans in AI controller for tracking
  ##
  ## Allows Phase 5 strategic coordinator to track multi-turn execution

  # TODO Phase 4: Add activeGOAPlans field to AIController
  # For now, this is a placeholder
  # controller.activeGOAPlans = plans

  discard
