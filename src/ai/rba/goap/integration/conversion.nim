## GOAP-RBA Conversion Layer
##
## Centralized conversion logic between RBA and GOAP systems
## DRY: Shared conversion functions, not duplicated per advisor

import std/[tables, options, sequtils, algorithm]
import ../core/[types, conditions]
import ../state/snapshot
import ../domains/fleet/[goals as fleet_goals, bridge as fleet_bridge]
# TODO: Build domain merged with Fleet domain in MVP - separate later
# import ../domains/build/[goals as build_goals, bridge as build_bridge]
import ../domains/research/[goals as research_goals, bridge as research_bridge]
import ../domains/diplomatic/[goals as diplomatic_goals, bridge as diplomatic_bridge]
import ../domains/espionage/[goals as espionage_goals, bridge as espionage_bridge]
import ../domains/economic/[goals as economic_goals, bridge as economic_bridge]
import ../../../../common/types/core
import ../../../../engine/starmap
import ../../config

# =============================================================================
# State → Goals Conversion (All Domains)
# =============================================================================

proc extractAllGoalsFromState*(
  state: WorldStateSnapshot,
  starMap: StarMap,
  config: GOAPConfig
): seq[Goal] =
  ## Extract all strategic goals from current world state
  ##
  ## This is the main entry point for GOAP in RBA Phase 1.5
  ## Calls all domain-specific goal extraction functions

  result = @[]

  # Fleet domain goals (Domestikos)
  let fleetGoals = fleet_bridge.extractFleetGoalsFromState(state, starMap, config)
  result.add(fleetGoals)

  # Build domain goals (Domestikos) - TODO: Merged with Fleet in MVP
  # let buildGoals = build_bridge.extractBuildGoalsFromState(state)
  # result.add(buildGoals)

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
     GoalType.EliminateFleet, GoalType.EstablishFleetPresence,
     GoalType.ConductReconnaissance, GoalType.AchieveTotalVictory,
     GoalType.LastStandReconquest:
    return FleetDomain

  # Build domain
  of GoalType.EstablishShipyard, GoalType.BuildFleet,
     GoalType.ConstructStarbase, GoalType.ExpandProduction,
     GoalType.CreateInvasionForce, GoalType.EnsureRepairCapacity:
    return BuildDomain

  # Research domain
  of GoalType.AchieveTechLevel, GoalType.CloseResearchGap,
     GoalType.UnlockCapability:
    return ResearchDomain

  # Diplomatic domain
  of GoalType.SecureAlliance, GoalType.DeclareWar,
     GoalType.ImproveRelations, GoalType.IsolateEnemy:
    return DiplomaticDomain

  # Espionage domain
  of GoalType.GatherIntelligence, GoalType.StealTechnology,
     GoalType.SabotageEconomy, GoalType.AssassinateLeader,
     GoalType.DisruptEconomy, GoalType.PropagandaCampaign,
     GoalType.CyberAttack, GoalType.CounterIntelSweep,
     GoalType.StealIntelligence, GoalType.PlantDisinformation,
     GoalType.EstablishIntelNetwork:
    return EspionageDomain

  # Economic domain
  of GoalType.TransferPopulation, GoalType.TerraformPlanet,
     GoalType.DevelopInfrastructure, GoalType.BalanceEconomy,
     GoalType.MaintainPrestige:
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
# =============================================================================
# Phase 3: GOAP Action → RBA FleetOrder Conversion (CRITICAL)
# =============================================================================

import ../../../../engine/[fog_of_war, order_types, fleet, squadron]
import ../../shared/intelligence_types
import ../../domestikos/fleet_analysis

proc convertGOAPActionToRBAOrder*(
  action: Action,
  filtered: FilteredGameState,
  analyses: seq[FleetAnalysis]
): Option[FleetOrder] =
  ## Convert GOAP action to RBA FleetOrder
  ##
  ## Phase 3: Bridges GOAP strategic planning with RBA tactical execution
  ## Maps GOAP ActionType to appropriate FleetOrderType with ROE

  if action.target.isNone:
    return none(FleetOrder)

  let targetSystem = action.target.get()

  # Request fleet from Domestikos (respects ETAC/Intel priorities)
  let requireCombat = action.actionType in {
    ActionType.InvadePlanet,
    ActionType.BlitzPlanet,
    ActionType.BombardPlanet,
    ActionType.AttackColony
  }

  # CRITICAL: Require marines for invasion/blitz operations
  # Empty transports are useless for offensive operations
  let requireMarines = action.actionType in {
    ActionType.InvadePlanet,
    ActionType.BlitzPlanet
  }

  let fleetOpt = fleet_analysis.requestFleetForOperation(
    analyses,
    targetSystem,
    requireCombatShips = requireCombat,
    requireMarines = requireMarines,
    filtered = filtered
  )

  if fleetOpt.isNone:
    return none(FleetOrder)

  let fleet = fleetOpt.get()

  # Convert action type to fleet order
  case action.actionType
  of ActionType.MoveFleet:
    return some(FleetOrder(
      fleetId: fleet.fleetId,
      orderType: FleetOrderType.Move,
      targetSystem: some(targetSystem),
      priority: 70,  # Strategic movement
      roe: some(6)   # Defensive posture
    ))

  of ActionType.BombardPlanet:
    return some(FleetOrder(
      fleetId: fleet.fleetId,
      orderType: FleetOrderType.Bombard,
      targetSystem: some(targetSystem),
      priority: 95,  # High priority - active campaign
      roe: some(8)   # Aggressive - destroy ground defenses
    ))

  of ActionType.BlitzPlanet:
    # CRITICAL: Check for FULLY loaded marines before allowing ground assault
    # Require full capacity - no partial loads (waste transport space)
    var transportCapacity = 0
    var loadedMarines = 0
    let transportCarryLimit = getShipStats(ShipClass.TroopTransport).carryLimit

    # Look up actual fleet from filtered state (fleet is FleetAnalysis, not Fleet)
    for actualFleet in filtered.ownFleets:
      if actualFleet.id == fleet.fleetId:
        for squadron in actualFleet.squadrons:
          if squadron.squadronType == SquadronType.Auxiliary:
            if squadron.flagship.shipClass == ShipClass.TroopTransport:
              transportCapacity += transportCarryLimit
              if squadron.flagship.cargo.isSome:
                let cargo = squadron.flagship.cargo.get()
                if cargo.cargoType == CargoType.Marines:
                  loadedMarines += cargo.quantity
        break

    if transportCapacity == 0 or loadedMarines < transportCapacity:
      # Not enough loaded marines for a blitz.
      # Return none to signal that the action cannot be executed this turn.
      # The plan will be re-evaluated next turn.
      return none(FleetOrder)

    return some(FleetOrder(
      fleetId: fleet.fleetId,
      orderType: FleetOrderType.Blitz,
      targetSystem: some(targetSystem),
      priority: 100,  # Maximum priority - rapid assault
      roe: some(9)    # Aggressive blitz
    ))

  of ActionType.InvadePlanet:
    # CRITICAL: Check for FULLY loaded marines before allowing ground assault
    # Require full capacity - no partial loads (waste transport space)
    var transportCapacity = 0
    var loadedMarines = 0
    let transportCarryLimit = getShipStats(ShipClass.TroopTransport).carryLimit

    # Look up actual fleet from filtered state (fleet is FleetAnalysis, not Fleet)
    for actualFleet in filtered.ownFleets:
      if actualFleet.id == fleet.fleetId:
        for squadron in actualFleet.squadrons:
          if squadron.squadronType == SquadronType.Auxiliary:
            if squadron.flagship.shipClass == ShipClass.TroopTransport:
              transportCapacity += transportCarryLimit
              if squadron.flagship.cargo.isSome:
                let cargo = squadron.flagship.cargo.get()
                if cargo.cargoType == CargoType.Marines:
                  loadedMarines += cargo.quantity
        break

    if transportCapacity == 0 or loadedMarines < transportCapacity:
      # Not enough loaded marines for an invasion.
      # Return none to signal that the action cannot be executed this turn.
      # The plan will be re-evaluated next turn.
      return none(FleetOrder)

    return some(FleetOrder(
      fleetId: fleet.fleetId,
      orderType: FleetOrderType.Invade,
      targetSystem: some(targetSystem),
      priority: 100,  # Maximum priority - invasion assault
      roe: some(10)   # All-out invasion
    ))

  of ActionType.ConductScoutMission:
    return some(FleetOrder(
      fleetId: fleet.fleetId,
      orderType: FleetOrderType.SpyPlanet,
      targetSystem: some(targetSystem),
      priority: 85,  # High priority - intelligence gathering
      roe: some(4)   # Cautious - gather intel and retreat
    ))

  of ActionType.EstablishDefense:
    return some(FleetOrder(
      fleetId: fleet.fleetId,
      orderType: FleetOrderType.Patrol,
      targetSystem: some(targetSystem),
      priority: 80,  # Important - defensive posture
      roe: some(6)   # Defensive posture
    ))

  of ActionType.AttackColony:
    # Deprecated - use BombardPlanet/BlitzPlanet/InvadePlanet instead
    # Fallback to Bombard for compatibility
    return some(FleetOrder(
      fleetId: fleet.fleetId,
      orderType: FleetOrderType.Bombard,
      targetSystem: some(targetSystem),
      priority: 90,
      roe: some(8)
    ))

  else:
    # Other action types don't map to fleet orders
    return none(FleetOrder)
