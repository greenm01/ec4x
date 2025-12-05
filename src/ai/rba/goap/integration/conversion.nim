## GOAP-RBA Conversion Layer
##
## Centralized conversion logic between RBA and GOAP systems
## DRY: Shared conversion functions, not duplicated per advisor

import std/[tables, options, sequtils, algorithm]
import ../core/[types, conditions]
import ../state/snapshot
import ../domains/fleet/[goals as fleet_goals, bridge as fleet_bridge]
import ../domains/build/[goals as build_goals, bridge as build_bridge]
import ../domains/research/[goals as research_goals, bridge as research_bridge]
import ../domains/diplomatic/[goals as diplomatic_goals, bridge as diplomatic_bridge]
import ../domains/espionage/[goals as espionage_goals, bridge as espionage_bridge]
import ../domains/economic/[goals as economic_goals, bridge as economic_bridge]
import ../../../../common/types/core

# =============================================================================
# State → Goals Conversion (All Domains)
# =============================================================================

proc extractAllGoalsFromState*(state: WorldStateSnapshot): seq[Goal] =
  ## Extract all strategic goals from current world state
  ##
  ## This is the main entry point for GOAP in RBA Phase 1.5
  ## Calls all domain-specific goal extraction functions

  result = @[]

  # Fleet domain goals (Domestikos)
  let fleetGoals = fleet_bridge.extractFleetGoalsFromState(state)
  result.add(fleetGoals)

  # Build domain goals (Domestikos)
  let buildGoals = build_bridge.extractBuildGoalsFromState(state)
  result.add(buildGoals)

  # Research domain goals (Logothete)
  let researchGoals = research_bridge.extractResearchGoalsFromState(state)
  result.add(researchGoals)

  # Diplomatic domain goals (Protostrator)
  let diplomaticGoals = diplomatic_bridge.extractDiplomaticGoalsFromState(state)
  result.add(diplomaticGoals)

  # Espionage domain goals (Drungarius)
  let espionageGoals = espionage_bridge.extractEspionageGoalsFromState(state)
  result.add(espionageGoals)

  # Economic domain goals (Eparch)
  let economicGoals = economic_bridge.extractEconomicGoalsFromState(state)
  result.add(economicGoals)

proc prioritizeGoals*(goals: seq[Goal]): seq[Goal] =
  ## Sort goals by priority (highest first)
  ##
  ## Used for goal selection in budget-constrained scenarios

  result = goals.sortedByIt(-it.priority)

proc filterAffordableGoals*(goals: seq[Goal], availableBudget: int): seq[Goal] =
  ## Filter goals to only those we can afford
  ##
  ## Used in Phase 2 mediation

  result = @[]
  for goal in goals:
    if goal.requiredResources <= availableBudget:
      result.add(goal)

# =============================================================================
# Goal → Domain Mapping
# =============================================================================

type
  DomainType* {.pure.} = enum
    FleetDomain
    BuildDomain
    ResearchDomain
    DiplomaticDomain
    EspionageDomain
    EconomicDomain

proc getDomainForGoal*(goal: Goal): DomainType =
  ## Determine which domain a goal belongs to
  ##
  ## Used for routing goals to appropriate advisors

  case goal.goalType
  # Fleet domain
  of GoalType.DefendColony, GoalType.SecureSystem, GoalType.InvadeColony,
     GoalType.EliminateFleet, GoalType.EstablishFleetPresence, GoalType.ConductReconnaissance:
    return FleetDomain

  # Build domain
  of GoalType.EstablishShipyard, GoalType.BuildFleet, GoalType.ConstructStarbase,
     GoalType.ExpandProduction, GoalType.CreateInvasionForce:
    return BuildDomain

  # Research domain
  of GoalType.AchieveTechLevel, GoalType.CloseResearchGap, GoalType.UnlockCapability:
    return ResearchDomain

  # Diplomatic domain
  of GoalType.SecureAlliance, GoalType.DeclareWar, GoalType.ImproveRelations, GoalType.IsolateEnemy:
    return DiplomaticDomain

  # Espionage domain
  of GoalType.GatherIntelligence, GoalType.StealTechnology, GoalType.SabotageEconomy,
     GoalType.AssassinateLeader, GoalType.DisruptEconomy, GoalType.PropagandaCampaign,
     GoalType.CyberAttack, GoalType.CounterIntelSweep, GoalType.StealIntelligence,
     GoalType.PlantDisinformation, GoalType.EstablishIntelNetwork:
    return EspionageDomain

  # Economic domain
  of GoalType.TransferPopulation, GoalType.TerraformPlanet, GoalType.DevelopInfrastructure,
     GoalType.BalanceEconomy:
    return EconomicDomain

proc groupGoalsByDomain*(goals: seq[Goal]): Table[DomainType, seq[Goal]] =
  ## Group goals by their domain for advisor routing
  ##
  ## Returns table: DomainType → seq[Goal]

  result = initTable[DomainType, seq[Goal]]()

  for goal in goals:
    let domain = getDomainForGoal(goal)
    if not result.hasKey(domain):
      result[domain] = @[]
    result[domain].add(goal)

# =============================================================================
# Budget Allocation
# =============================================================================

type
  GoalAllocation* = tuple
    ## Budget allocation for a goal
    goal: Goal
    allocated: int
    fundingRatio: float  # allocated / required

proc allocateBudgetToGoals*(
  goals: seq[Goal],
  totalBudget: int
): seq[GoalAllocation] =
  ## Allocate budget to goals based on priority
  ##
  ## Greedy allocation: highest priority goals get funded first
  ## Returns: seq of (goal, allocated budget, funding ratio)

  result = @[]

  var remainingBudget = totalBudget
  let sortedGoals = prioritizeGoals(goals)

  for goal in sortedGoals:
    if remainingBudget >= goal.requiredResources:
      # Fully fund this goal
      result.add((
        goal: goal,
        allocated: goal.requiredResources,
        fundingRatio: 1.0
      ))
      remainingBudget -= goal.requiredResources
    elif remainingBudget > 0:
      # Partially fund (if goal can be partially executed)
      let ratio = remainingBudget.float / goal.requiredResources.float
      result.add((
        goal: goal,
        allocated: remainingBudget,
        fundingRatio: ratio
      ))
      remainingBudget = 0
      break
    else:
      break
