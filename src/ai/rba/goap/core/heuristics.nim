## GOAP Heuristic Functions
##
## Cost estimation functions for A* planner.
## Must be admissible (never overestimate) for optimal planning.
##
## DRY Principle:
## - Shared across all domains (fleet, build, research, diplomatic)
## - Single source of truth for cost calculations
## - Reused by A* planner in planner/search.nim

import std/[math, options]
import types

# =============================================================================
# Heuristic Cost Estimation (A* Admissibility)
# =============================================================================

proc estimateGoalCost*(state: WorldStateSnapshot, goal: Goal): float =
  ## Estimate minimum cost to achieve goal from current state
  ##
  ## Must be admissible: never overestimate actual cost
  ## Used by A* as h(n) heuristic

  case goal.goalType
  # Fleet Domain
  of GoalType.DefendColony:
    # Need at least 1 cruiser (100 PP) to defend
    return 100.0

  of GoalType.InvadeColony:
    # Need transport (60 PP) + marines (50 PP) + escort (100 PP) minimum
    return 210.0

  of GoalType.SecureSystem:
    # Similar to invasion but may need multiple transports
    return 300.0

  of GoalType.EliminateFleet:
    # Need superior fleet strength (estimate 200 PP)
    return 200.0

  of GoalType.EstablishFleetPresence:
    # Just need to move existing fleet (cost: 0 PP, but time cost)
    return 0.0

  of GoalType.ConductReconnaissance:
    # Need scout (30 PP) if no idle scouts
    if state.idleFleets.len > 0:
      return 0.0  # Have idle fleet
    else:
      return 30.0  # Need to build scout

  # Build Domain
  of GoalType.EstablishShipyard:
    # Shipyard costs ~150 PP
    return 150.0

  of GoalType.BuildFleet:
    # Estimate based on goal.requiredResources (set by caller)
    return goal.requiredResources.float

  of GoalType.ConstructStarbase:
    # Starbase costs ~200 PP
    return 200.0

  of GoalType.ExpandProduction:
    # IU investment costs ~50 PP
    return 50.0

  of GoalType.CreateInvasionForce:
    # Transport + marines + escorts
    return 210.0

  of GoalType.EnsureRepairCapacity:
    # Need drydock capacity (estimate cost of drydock infrastructure)
    return 100.0

  # Fleet Domain (strategic goals)
  of GoalType.AchieveTotalVictory:
    # Ultimate goal - very expensive (combined fleet + conquest operations)
    return 1000.0

  of GoalType.LastStandReconquest:
    # Desperate measure - need major fleet rebuild
    return 800.0

  # Research Domain
  of GoalType.AchieveTechLevel:
    # Estimate RP cost (each level costs ~50 RP conservative estimate)
    return 50.0

  of GoalType.CloseResearchGap:
    # Assume 1 level gap = 50 RP
    return 50.0

  of GoalType.UnlockCapability:
    # Assume 2 levels needed = 100 RP
    return 100.0

  # Diplomatic Domain
  of GoalType.SecureAlliance:
    # Diplomacy is free (0 PP cost)
    return 0.0

  of GoalType.DeclareWar:
    # Free action
    return 0.0

  of GoalType.ImproveRelations:
    # May need tribute (estimate 50 PP)
    return 50.0

  of GoalType.IsolateEnemy:
    # Complex multi-step (form alliances with others)
    return 100.0  # Conservative estimate

  # Espionage Domain
  of GoalType.GatherIntelligence:
    # Basic reconnaissance (free if scouts available)
    return 0.0

  of GoalType.StealTechnology:
    # Tech Theft: 5 EBP * 40 PP per EBP
    return 200.0

  of GoalType.SabotageEconomy:
    # Low/High Impact Sabotage: 2-7 EBP
    return 120.0  # Average estimate

  of GoalType.AssassinateLeader:
    # Assassination: 10 EBP * 40 PP
    return 400.0

  of GoalType.DisruptEconomy:
    # Economic Manipulation: 6 EBP * 40 PP
    return 240.0

  of GoalType.PropagandaCampaign:
    # Psyops Campaign: 3 EBP * 40 PP
    return 120.0

  of GoalType.CyberAttack:
    # Cyber Attack: 6 EBP * 40 PP
    return 240.0

  of GoalType.CounterIntelSweep:
    # Counter-Intel Sweep: 4 EBP * 40 PP
    return 160.0

  of GoalType.StealIntelligence:
    # Intelligence Theft: 8 EBP * 40 PP
    return 320.0

  of GoalType.PlantDisinformation:
    # Plant Disinformation: 6 EBP * 40 PP
    return 240.0

  of GoalType.EstablishIntelNetwork:
    # Build EBP/CIP capability (investment over time)
    return 200.0  # Conservative estimate

  # Economic Domain
  of GoalType.TransferPopulation:
    # Space Guild PTU costs (variable)
    return 100.0  # Conservative estimate
  of GoalType.MaintainPrestige:
    # Cost to maintain prestige is typically defensive investments or avoiding penalties
    # Estimate a moderate cost for defensive actions or intel sweeps.
    return 150.0

  of GoalType.TerraformPlanet:
    # Planetary development (expensive, multi-turn)
    return 500.0

  of GoalType.DevelopInfrastructure:
    # IU investment
    return 100.0

  of GoalType.BalanceEconomy:
    # Optimization (no direct cost)
    return 0.0

proc estimateActionCost*(state: WorldStateSnapshot, action: Action): float =
  ## Estimate cost to execute action from current state
  ##
  ## Includes both PP cost and turn-time cost
  ## Used by A* as g(n) accumulator

  # Base PP cost
  result = action.cost.float

  # Add time penalty (1 turn = 10 PP equivalent for priority)
  # This encourages faster plans
  result += action.duration.float * 10.0

proc estimateRemainingCost*(state: WorldStateSnapshot, goal: Goal, actionsExecuted: seq[Action]): float =
  ## Estimate remaining cost after executing some actions
  ##
  ## Used by A* to update h(n) as we progress toward goal
  ## Must remain admissible

  # Simple approach: Goal cost - sum of executed action costs
  let goalCost = estimateGoalCost(state, goal)
  var executedCost = 0.0
  for action in actionsExecuted:
    executedCost += action.cost.float

  result = max(0.0, goalCost - executedCost)

# =============================================================================
# Priority Weighting (From RBA Requirements)
# =============================================================================

proc convertPriorityToWeight*(priority: float): float =
  ## Convert RBA requirement priority (0.0-1.0) to A* goal weight
  ##
  ## Higher priority goals get higher weights (explored first)
  ## Maps:
  ## - 1.0 (Critical) → 1000.0
  ## - 0.7 (High)     → 100.0
  ## - 0.4 (Medium)   → 10.0
  ## - 0.1 (Low)      → 1.0

  if priority >= 0.9:
    return 1000.0  # Critical
  elif priority >= 0.6:
    return 100.0   # High
  elif priority >= 0.3:
    return 10.0    # Medium
  else:
    return 1.0     # Low

# =============================================================================
# Confidence Scoring (Plan Likelihood)
# =============================================================================

proc estimatePlanConfidence*(state: WorldStateSnapshot, plan: GOAPlan): float =
  ## Estimate probability that plan will succeed
  ##
  ## Factors:
  ## - Budget availability (can we afford it?)
  ## - Enemy interference (will they block us?)
  ## - Tech requirements (do we have capabilities?)
  ## - Time constraints (can we finish before deadline?)
  ##
  ## Returns: 0.0-1.0 confidence score

  var confidence = 1.0

  # Budget check: Can we afford this?
  let affordability = state.treasury.float / max(1.0, plan.totalCost.float)
  if affordability < 0.5:
    confidence *= 0.5  # Not enough budget
  elif affordability < 0.8:
    confidence *= 0.8  # Tight budget
  elif affordability < 1.0:
    confidence *= 0.9  # Barely affordable
  # else: fully affordable, no penalty

  # Time check: Can we finish before deadline?
  if plan.goal.deadline.isSome:
    let turnsRemaining = plan.goal.deadline.get() - state.turn
    if plan.estimatedTurns > turnsRemaining:
      confidence *= 0.3  # Won't finish in time
    elif plan.estimatedTurns == turnsRemaining:
      confidence *= 0.7  # Cutting it close
    elif plan.estimatedTurns > turnsRemaining div 2:
      confidence *= 0.9  # Moderate time pressure
    # else: plenty of time, no penalty

  # Enemy interference: Military goals are riskier
  case plan.goal.goalType
  of GoalType.InvadeColony, GoalType.EliminateFleet, GoalType.SecureSystem:
    # Combat operations have inherent risk
    confidence *= 0.7  # 30% chance of failure/delay

  of GoalType.DefendColony, GoalType.EstablishFleetPresence:
    # Defensive operations are safer
    confidence *= 0.9  # 10% chance of disruption

  else:
    # Non-military operations are reliable
    confidence *= 0.95  # 5% chance of unexpected issues

  # Dependency risk: Plans with dependencies are more fragile
  if plan.dependencies.len > 0:
    confidence *= pow(0.9, plan.dependencies.len.float)

  return min(1.0, max(0.0, confidence))

# =============================================================================
# Action Ordering Heuristics
# =============================================================================

proc shouldExecuteFirst*(action1, action2: Action): bool =
  ## Determine if action1 should execute before action2
  ##
  ## Ordering heuristics:
  ## 1. Prerequisites before dependents (tech before builds)
  ## 2. Cheaper actions before expensive (test viability early)
  ## 3. Faster actions before slower (gain options sooner)

  # Tech/infrastructure before units
  if action1.actionType in [ActionType.AllocateResearch, ActionType.BuildFacility] and
     action2.actionType in [ActionType.ConstructShips]:
    return true

  # Cheaper before expensive (if same duration)
  if action1.duration == action2.duration:
    return action1.cost < action2.cost

  # Faster before slower (if similar cost)
  if abs(action1.cost - action2.cost) < 50:
    return action1.duration < action2.duration

  # Default: maintain current order
  return false
