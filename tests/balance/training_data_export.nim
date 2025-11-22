## Training Data Export for LLM Fine-Tuning
##
## Exports game state + AI decisions in format suitable for Mistral-7B training
## Each training example = (game state, AI decision, reasoning)

import std/[json, tables, sequtils, strformat, options]
import ../../src/engine/[gamestate, orders, fleet]
import ../../src/engine/diplomacy/types as dip_types
import ../../src/common/types/core
import ai_controller

type
  TrainingExample* = object
    ## Single training example: game state → AI decision
    turn*: int
    houseId*: HouseId
    strategy*: AIStrategy

    # Game state snapshot
    gameState*: GameStateSnapshot

    # AI decision (what the AI chose to do)
    aiDecision*: AIDecisionSnapshot

    # Orders generated
    orders*: OrderPacket

  GameStateSnapshot* = object
    ## Condensed game state for training
    treasury*: int
    production*: int  # Total PP production this turn
    colonyCount*: int
    fleetCount*: int

    # Tech levels
    energyLevel*: int
    shieldLevel*: int
    weaponsTech*: int

    # Diplomatic relations
    diplomaticStates*: Table[HouseId, string]  # house → "Neutral"/"NonAggression"/"Enemy"

    # Military situation
    ownMilitaryStrength*: int
    enemyMilitaryStrength*: int  # Total of all enemies

    # Economic situation
    ownEconomicStrength*: int
    enemyEconomicStrength*: int

    # Threats
    coloniesUnderThreat*: int

  AIDecisionSnapshot* = object
    ## What the AI decided to do and why
    diplomaticAction*: Option[DiplomaticActionSummary]
    fleetActions*: seq[FleetActionSummary]
    buildPriority*: string  # "Military"/"Economic"/"Defense"/"Expansion"
    researchFocus*: string  # "Economic"/"Science"/"Weapons"/"Balanced"

  DiplomaticActionSummary* = object
    actionType*: string  # "ProposeNonAggressionPact", "DeclareEnemy", etc.
    targetHouse*: HouseId
    reasoning*: string

  FleetActionSummary* = object
    fleetId*: FleetId
    orderType*: string  # "Attack", "Retreat", "Defend", "Expand"
    targetSystem*: Option[SystemId]
    reasoning*: string

proc captureGameState*(state: GameState, houseId: HouseId, controller: AIController): GameStateSnapshot =
  ## Capture condensed game state for training
  let house = state.houses[houseId]

  # Count colonies and production
  var totalProduction = 0
  var colonyCount = 0
  for colony in state.colonies.values:
    if colony.owner == houseId:
      colonyCount += 1
      totalProduction += colony.production

  # Count fleets
  let fleetCount = state.fleets.values.toSeq.filterIt(it.owner == houseId).len

  # Calculate military strengths
  var ownMilitary = 0
  var enemyMilitary = 0
  for fleet in state.fleets.values:
    if fleet.owner == houseId:
      ownMilitary += combatStrength(fleet)
    else:
      let dipState = dip_types.getDiplomaticState(house.diplomaticRelations, fleet.owner)
      if dipState == dip_types.DiplomaticState.Enemy:
        enemyMilitary += combatStrength(fleet)

  # Calculate economic strengths
  var ownEconomy = house.treasury + (totalProduction * 10)
  var enemyEconomy = 0
  for otherHouse in state.houses.values:
    if otherHouse.id != houseId:
      let dipState = dip_types.getDiplomaticState(house.diplomaticRelations, otherHouse.id)
      if dipState == dip_types.DiplomaticState.Enemy:
        enemyEconomy += otherHouse.treasury

  # Capture diplomatic states
  var dipStates = initTable[HouseId, string]()
  for otherHouse in state.houses.keys:
    if otherHouse != houseId:
      let dipState = dip_types.getDiplomaticState(house.diplomaticRelations, otherHouse)
      dipStates[otherHouse] = case dipState
        of dip_types.DiplomaticState.Neutral: "Neutral"
        of dip_types.DiplomaticState.NonAggression: "NonAggression"
        of dip_types.DiplomaticState.Enemy: "Enemy"

  # Count threatened colonies (simplified)
  var threatenedCount = 0
  for colony in state.colonies.values:
    if colony.owner == houseId and colony.blockaded:
      threatenedCount += 1

  result = GameStateSnapshot(
    treasury: house.treasury,
    production: totalProduction,
    colonyCount: colonyCount,
    fleetCount: fleetCount,
    energyLevel: house.techTree.levels.energyLevel,
    shieldLevel: house.techTree.levels.shieldLevel,
    weaponsTech: house.techTree.levels.weaponsTech,
    diplomaticStates: dipStates,
    ownMilitaryStrength: ownMilitary,
    enemyMilitaryStrength: enemyMilitary,
    ownEconomicStrength: ownEconomy,
    enemyEconomicStrength: enemyEconomy,
    coloniesUnderThreat: threatenedCount
  )

proc analyzeAIDecision*(orders: OrderPacket, state: GameState, controller: AIController): AIDecisionSnapshot =
  ## Analyze what the AI decided to do and infer reasoning
  result = AIDecisionSnapshot()

  # Analyze diplomatic action
  if orders.diplomaticActions.len > 0:
    let dipAction = orders.diplomaticActions[0]
    let actionTypeStr = case dipAction.actionType
      of DiplomaticActionType.ProposeNonAggressionPact: "ProposeNonAggressionPact"
      of DiplomaticActionType.BreakPact: "BreakPact"
      of DiplomaticActionType.DeclareEnemy: "DeclareEnemy"
      of DiplomaticActionType.SetNeutral: "SetNeutral"

    # Infer reasoning from controller personality and game state
    var reasoning = ""
    if controller.strategy == AIStrategy.Aggressive:
      reasoning = "aggressive_strategy"
    elif controller.strategy == AIStrategy.Diplomatic:
      reasoning = "diplomatic_strategy"
    else:
      reasoning = "strategic_assessment"

    result.diplomaticAction = some(DiplomaticActionSummary(
      actionType: actionTypeStr,
      targetHouse: dipAction.targetHouse,
      reasoning: reasoning
    ))

  # Analyze fleet actions
  for fleetOrder in orders.fleetOrders:
    let orderTypeStr = case fleetOrder.orderType
      of FleetOrderType.Move: "Move"
      of FleetOrderType.Patrol: "Patrol"
      of FleetOrderType.Hold: "Hold"
      of FleetOrderType.JoinFleet: "JoinFleet"
      else: "Other"

    let reasoning =
      if fleetOrder.orderType == FleetOrderType.Move and fleetOrder.targetSystem.isSome:
        "attack_or_expand"
      elif fleetOrder.orderType == FleetOrderType.Patrol:
        "defend_colony"
      else:
        "hold_position"

    result.fleetActions.add(FleetActionSummary(
      fleetId: fleetOrder.fleetId,
      orderType: orderTypeStr,
      targetSystem: fleetOrder.targetSystem,
      reasoning: reasoning
    ))

  # Analyze build priority
  if orders.buildOrders.len > 0:
    let firstBuild = orders.buildOrders[0]
    result.buildPriority = case firstBuild.buildType
      of BuildType.Ship: "Military"
      of BuildType.Infrastructure: "Economic"
      of BuildType.Building: "Defense"
  else:
    result.buildPriority = "None"

  # Analyze research focus
  let researchAlloc = orders.researchAllocation
  if researchAlloc.economic > researchAlloc.science and researchAlloc.economic > researchAlloc.technology.values.toSeq.foldl(a + b, 0):
    result.researchFocus = "Economic"
  elif researchAlloc.science > researchAlloc.economic:
    result.researchFocus = "Science"
  else:
    result.researchFocus = "Balanced"

proc exportTrainingExample*(example: TrainingExample): JsonNode =
  ## Export training example as JSON
  result = %* {
    "turn": example.turn,
    "house_id": $example.houseId,
    "strategy": $example.strategy,
    "game_state": {
      "treasury": example.gameState.treasury,
      "production": example.gameState.production,
      "colony_count": example.gameState.colonyCount,
      "fleet_count": example.gameState.fleetCount,
      "tech": {
        "energy_level": example.gameState.energyLevel,
        "shield_level": example.gameState.shieldLevel,
        "weapons_tech": example.gameState.weaponsTech
      },
      "military": {
        "own_strength": example.gameState.ownMilitaryStrength,
        "enemy_strength": example.gameState.enemyMilitaryStrength,
        "ratio": if example.gameState.enemyMilitaryStrength > 0:
          float(example.gameState.ownMilitaryStrength) / float(example.gameState.enemyMilitaryStrength)
        else: 10.0
      },
      "economy": {
        "own_strength": example.gameState.ownEconomicStrength,
        "enemy_strength": example.gameState.enemyEconomicStrength
      },
      "diplomacy": example.gameState.diplomaticStates,
      "threats": {
        "colonies_under_threat": example.gameState.coloniesUnderThreat
      }
    },
    "ai_decision": {
      "diplomatic_action": if example.aiDecision.diplomaticAction.isSome:
        %* {
          "action": example.aiDecision.diplomaticAction.get().actionType,
          "target": $example.aiDecision.diplomaticAction.get().targetHouse,
          "reasoning": example.aiDecision.diplomaticAction.get().reasoning
        }
      else:
        newJNull(),
      "fleet_actions": example.aiDecision.fleetActions.mapIt(%* {
        "fleet": $it.fleetId,
        "order": it.orderType,
        "target": if it.targetSystem.isSome: $it.targetSystem.get() else: "",
        "reasoning": it.reasoning
      }),
      "build_priority": example.aiDecision.buildPriority,
      "research_focus": example.aiDecision.researchFocus
    }
  }

proc createTrainingExample*(turn: int, state: GameState, controller: AIController,
                           orders: OrderPacket): TrainingExample =
  ## Create a complete training example
  let gameState = captureGameState(state, controller.houseId, controller)
  let aiDecision = analyzeAIDecision(orders, state, controller)

  result = TrainingExample(
    turn: turn,
    houseId: controller.houseId,
    strategy: controller.strategy,
    gameState: gameState,
    aiDecision: aiDecision,
    orders: orders
  )
