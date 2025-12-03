## Balance Testing Framework with JSON Export
##
## Simulates full games with various AI strategies and exports detailed
## JSON data for AI-powered balance analysis and recommendations.
##
## Output format designed for LLM consumption with complete game trajectory,
## metrics, and context for balance evaluation.

import std/[json, tables, options, strformat, times, os]
import ../../engine/[gamestate, resolve, orders]
import ../../common/types/[core, units, planets, tech]

# =============================================================================
# JSON Export Types
# =============================================================================

type
  BalanceTestConfig* = object
    ## Configuration for a balance test scenario
    testName*: string
    description*: string
    numberOfHouses*: int
    numberOfTurns*: int
    mapSize*: int
    startingConditions*: string
    aiStrategies*: seq[string]
    tags*: seq[string]  # e.g., ["early-game", "military", "economic"]

  TurnSnapshot* = object
    ## Complete state snapshot for one turn
    turn*: int
    year*: int
    month*: int
    houses*: seq[HouseSnapshot]
    combatEvents*: seq[CombatEventSnapshot]
    economicEvents*: seq[EconomicEventSnapshot]
    diplomaticEvents*: seq[DiplomaticEventSnapshot]
    espionageEvents*: seq[EspionageEventSnapshot]

  HouseSnapshot* = object
    ## Per-house metrics for one turn
    houseId*: string
    prestige*: int
    treasury*: int
    totalGCO*: int
    totalNCV*: int
    totalFleetStrength*: int
    colonyCount*: int
    systemsControlled*: int
    techLevels*: Table[string, int]
    moraleLevel*: string
    isEliminated*: bool
    eliminatedOnTurn*: int
    # Strategic posture
    militarySpending*: int
    researchSpending*: int
    espionageSpending*: int
    taxRate*: int
    # Diplomatic status
    activePacts*: seq[string]
    atWarWith*: seq[string]
    # Resource accumulation
    cumulativeGCO*: int
    cumulativeNCV*: int
    cumulativePrestige*: int

  CombatEventSnapshot* = object
    turn*: int
    systemId*: string
    attacker*: string
    defender*: string
    attackerInitialStrength*: int
    defenderInitialStrength*: int
    attackerFinalStrength*: int
    defenderFinalStrength*: int
    attackerLosses*: int
    defenderLosses*: int
    victor*: string
    rounds*: int
    prestigeChange*: Table[string, int]

  EconomicEventSnapshot* = object
    turn*: int
    houseId*: string
    eventType*: string  # "colony_established", "tax_change", "construction"
    systemId*: string
    impact*: int  # GCO/NCV change
    details*: string

  DiplomaticEventSnapshot* = object
    turn*: int
    house1*: string
    house2*: string
    eventType*: string  # "pact_signed", "pact_broken", "war_declared"
    prestigeImpact*: Table[string, int]

  EspionageEventSnapshot* = object
    turn*: int
    agentHouse*: string
    targetHouse*: string
    action*: string
    success*: bool
    detected*: bool
    impact*: int
    prestigeChange*: int

  GameOutcome* = object
    ## Final game results
    victor*: string
    victoryType*: string  # "prestige", "last_standing", "turn_limit"
    victoryTurn*: int
    finalRankings*: seq[HouseRanking]
    gameLength*: int

  HouseRanking* = object
    rank*: int
    houseId*: string
    finalPrestige*: int
    eliminated*: bool
    eliminatedTurn*: int
    peakPrestige*: int
    peakPrestigeTurn*: int
    totalCombatVictories*: int
    totalCombatLosses*: int
    coloniesEstablished*: int
    techAdvancementsCompleted*: int

  BalanceTestResult* = object
    ## Complete test output for AI analysis
    metadata*: TestMetadata
    config*: BalanceTestConfig
    turnSnapshots*: seq[TurnSnapshot]
    outcome*: GameOutcome
    metrics*: GameMetrics
    recommendations*: seq[string]  # Populated by AI analysis

  TestMetadata* = object
    testId*: string
    timestamp*: string
    engineVersion*: string
    configVersion*: string
    executionTimeMs*: int

  GameMetrics* = object
    ## Aggregate metrics for balance analysis
    averageGameLength*: float
    winRateByStrategy*: Table[string, float]
    averagePrestigeByTurn*: seq[float]
    economicGrowthRates*: Table[string, seq[float]]
    combatFrequency*: float
    espionageEffectiveness*: float
    diplomaticStability*: float
    # Balance indicators
    prestigeVolatility*: float  # Std dev of prestige changes
    leaderChanges*: int  # How often the prestige leader changed
    comebacksObserved*: int  # Houses recovering from negative prestige
    dominationGames*: int  # Games with runaway leader
    closenessScore*: float  # How competitive the game was

# =============================================================================
# JSON Serialization
# =============================================================================

proc toJson*(snapshot: HouseSnapshot): JsonNode =
  result = %* {
    "house_id": snapshot.houseId,
    "prestige": snapshot.prestige,
    "treasury": snapshot.treasury,
    "total_gco": snapshot.totalGCO,
    "total_ncv": snapshot.totalNCV,
    "total_fleet_strength": snapshot.totalFleetStrength,
    "colony_count": snapshot.colonyCount,
    "systems_controlled": snapshot.systemsControlled,
    "tech_levels": snapshot.techLevels,
    "morale_level": snapshot.moraleLevel,
    "is_eliminated": snapshot.isEliminated,
    "eliminated_on_turn": snapshot.eliminatedOnTurn,
    "military_spending": snapshot.militarySpending,
    "research_spending": snapshot.researchSpending,
    "espionage_spending": snapshot.espionageSpending,
    "tax_rate": snapshot.taxRate,
    "active_pacts": snapshot.activePacts,
    "at_war_with": snapshot.atWarWith,
    "cumulative_gco": snapshot.cumulativeGCO,
    "cumulative_ncv": snapshot.cumulativeNCV,
    "cumulative_prestige": snapshot.cumulativePrestige
  }

proc toJson*(event: CombatEventSnapshot): JsonNode =
  result = %* {
    "turn": event.turn,
    "system_id": event.systemId,
    "attacker": event.attacker,
    "defender": event.defender,
    "attacker_initial_strength": event.attackerInitialStrength,
    "defender_initial_strength": event.defenderInitialStrength,
    "attacker_final_strength": event.attackerFinalStrength,
    "defender_final_strength": event.defenderFinalStrength,
    "attacker_losses": event.attackerLosses,
    "defender_losses": event.defenderLosses,
    "victor": event.victor,
    "rounds": event.rounds,
    "prestige_change": event.prestigeChange
  }

proc toJson*(event: EconomicEventSnapshot): JsonNode =
  result = %* {
    "turn": event.turn,
    "house_id": event.houseId,
    "event_type": event.eventType,
    "system_id": event.systemId,
    "impact": event.impact,
    "details": event.details
  }

proc toJson*(event: DiplomaticEventSnapshot): JsonNode =
  result = %* {
    "turn": event.turn,
    "house1": event.house1,
    "house2": event.house2,
    "event_type": event.eventType,
    "prestige_impact": event.prestigeImpact
  }

proc toJson*(event: EspionageEventSnapshot): JsonNode =
  result = %* {
    "turn": event.turn,
    "agent_house": event.agentHouse,
    "target_house": event.targetHouse,
    "action": event.action,
    "success": event.success,
    "detected": event.detected,
    "impact": event.impact,
    "prestige_change": event.prestigeChange
  }

proc toJson*(snapshot: TurnSnapshot): JsonNode =
  var housesJson = newJArray()
  for house in snapshot.houses:
    housesJson.add(house.toJson())

  var combatJson = newJArray()
  for combat in snapshot.combatEvents:
    combatJson.add(combat.toJson())

  var economicJson = newJArray()
  for econ in snapshot.economicEvents:
    economicJson.add(econ.toJson())

  var diplomaticJson = newJArray()
  for dip in snapshot.diplomaticEvents:
    diplomaticJson.add(dip.toJson())

  var espionageJson = newJArray()
  for esp in snapshot.espionageEvents:
    espionageJson.add(esp.toJson())

  result = %* {
    "turn": snapshot.turn,
    "year": snapshot.year,
    "month": snapshot.month,
    "houses": housesJson,
    "combat_events": combatJson,
    "economic_events": economicJson,
    "diplomatic_events": diplomaticJson,
    "espionage_events": espionageJson
  }

proc toJson*(ranking: HouseRanking): JsonNode =
  result = %* {
    "rank": ranking.rank,
    "house_id": ranking.houseId,
    "final_prestige": ranking.finalPrestige,
    "eliminated": ranking.eliminated,
    "eliminated_turn": ranking.eliminatedTurn,
    "peak_prestige": ranking.peakPrestige,
    "peak_prestige_turn": ranking.peakPrestigeTurn,
    "total_combat_victories": ranking.totalCombatVictories,
    "total_combat_losses": ranking.totalCombatLosses,
    "colonies_established": ranking.coloniesEstablished,
    "tech_advancements_completed": ranking.techAdvancementsCompleted
  }

proc toJson*(outcome: GameOutcome): JsonNode =
  var rankingsJson = newJArray()
  for ranking in outcome.finalRankings:
    rankingsJson.add(ranking.toJson())

  result = %* {
    "victor": outcome.victor,
    "victory_type": outcome.victoryType,
    "victory_turn": outcome.victoryTurn,
    "final_rankings": rankingsJson,
    "game_length": outcome.gameLength
  }

proc toJson*(metrics: GameMetrics): JsonNode =
  result = %* {
    "average_game_length": metrics.averageGameLength,
    "win_rate_by_strategy": metrics.winRateByStrategy,
    "average_prestige_by_turn": metrics.averagePrestigeByTurn,
    "economic_growth_rates": metrics.economicGrowthRates,
    "combat_frequency": metrics.combatFrequency,
    "espionage_effectiveness": metrics.espionageEffectiveness,
    "diplomatic_stability": metrics.diplomaticStability,
    "prestige_volatility": metrics.prestigeVolatility,
    "leader_changes": metrics.leaderChanges,
    "comebacks_observed": metrics.comebacksObserved,
    "domination_games": metrics.dominationGames,
    "closeness_score": metrics.closenessScore
  }

proc toJson*(config: BalanceTestConfig): JsonNode =
  result = %* {
    "test_name": config.testName,
    "description": config.description,
    "number_of_houses": config.numberOfHouses,
    "number_of_turns": config.numberOfTurns,
    "map_size": config.mapSize,
    "starting_conditions": config.startingConditions,
    "ai_strategies": config.aiStrategies,
    "tags": config.tags
  }

proc toJson*(metadata: TestMetadata): JsonNode =
  result = %* {
    "test_id": metadata.testId,
    "timestamp": metadata.timestamp,
    "engine_version": metadata.engineVersion,
    "config_version": metadata.configVersion,
    "execution_time_ms": metadata.executionTimeMs
  }

proc toJson*(testResult: BalanceTestResult): JsonNode =
  var snapshotsJson = newJArray()
  for snapshot in testResult.turnSnapshots:
    snapshotsJson.add(snapshot.toJson())

  var recsJson = newJArray()
  for rec in testResult.recommendations:
    recsJson.add(%rec)

  %* {
    "metadata": testResult.metadata.toJson(),
    "config": testResult.config.toJson(),
    "turn_snapshots": snapshotsJson,
    "outcome": testResult.outcome.toJson(),
    "metrics": testResult.metrics.toJson(),
    "recommendations": recsJson
  }

# =============================================================================
# Snapshot Capture
# =============================================================================

proc captureHouseSnapshot*(state: GameState, houseId: HouseId,
                          cumulativeData: var Table[HouseId, tuple[gco, ncv, prestige: int]]): HouseSnapshot =
  ## Capture complete state for one house
  let house = state.houses[houseId]

  # Calculate totals
  var totalGCO = 0
  var totalNCV = 0
  var colonyCount = 0
  for colony in state.colonies.values:
    if colony.owner == houseId:
      colonyCount.inc
      # TODO: Calculate actual GCO/NCV from colony

  var totalFleetStrength = 0
  for fleet in state.fleets.values:
    if fleet.owner == houseId:
      for squadron in fleet.squadrons:
        totalFleetStrength += squadron.flagship.stats.attackStrength

  # Update cumulative data
  if houseId notin cumulativeData:
    cumulativeData[houseId] = (0, 0, 0)
  var cum = cumulativeData[houseId]
  cum.gco += totalGCO
  cum.ncv += totalNCV
  cum.prestige += house.prestige
  cumulativeData[houseId] = cum

  # Build tech levels table
  var techLevels = initTable[string, int]()
  techLevels["EL"] = house.techTree.levels.economicLevel
  techLevels["SL"] = house.techTree.levels.scienceLevel
  techLevels["CST"] = house.techTree.levels.constructionTech
  techLevels["WEP"] = house.techTree.levels.weaponsTech
  # TODO: Add other tech levels

  result = HouseSnapshot(
    houseId: $houseId,
    prestige: house.prestige,
    treasury: house.treasury,
    totalGCO: totalGCO,
    totalNCV: totalNCV,
    totalFleetStrength: totalFleetStrength,
    colonyCount: colonyCount,
    systemsControlled: colonyCount,  # TODO: Count systems vs colonies
    techLevels: techLevels,
    moraleLevel: "Normal",  # TODO: Calculate from morale system
    isEliminated: house.eliminated,
    eliminatedOnTurn: if house.eliminated: state.turn else: 0,
    militarySpending: 0,  # TODO: Track spending
    researchSpending: 0,
    espionageSpending: 0,
    taxRate: 50,  # TODO: Get from house tax policy
    activePacts: @[],  # TODO: Get from diplomacy
    atWarWith: @[],
    cumulativeGCO: cum.gco,
    cumulativeNCV: cum.ncv,
    cumulativePrestige: cum.prestige
  )

proc captureTurnSnapshot*(state: GameState, turnResult: TurnResult,
                         cumulativeData: var Table[HouseId, tuple[gco, ncv, prestige: int]]): TurnSnapshot =
  ## Capture complete game state for one turn
  var houses: seq[HouseSnapshot] = @[]
  for houseId in state.houses.keys:
    houses.add(captureHouseSnapshot(state, houseId, cumulativeData))

  # TODO: Capture events from turnResult
  var combatEvents: seq[CombatEventSnapshot] = @[]
  var economicEvents: seq[EconomicEventSnapshot] = @[]
  var diplomaticEvents: seq[DiplomaticEventSnapshot] = @[]
  var espionageEvents: seq[EspionageEventSnapshot] = @[]

  # Calculate year and month from turn (13 turns per year in EC4X)
  let year = ((state.turn - 1) div 13) + 1
  let month = ((state.turn - 1) mod 13) + 1

  result = TurnSnapshot(
    turn: state.turn,
    year: year,
    month: month,
    houses: houses,
    combatEvents: combatEvents,
    economicEvents: economicEvents,
    diplomaticEvents: diplomaticEvents,
    espionageEvents: espionageEvents
  )

# =============================================================================
# Test Execution
# =============================================================================

proc runBalanceTest*(config: BalanceTestConfig, initialState: GameState): BalanceTestResult =
  ## Run a complete balance test simulation
  let startTime = cpuTime()

  result.metadata = TestMetadata(
    testId: &"{config.testName}_{now().format(\"yyyyMMddHHmmss\")}",
    timestamp: $now(),
    engineVersion: "0.1.0",  # TODO: Get from build system
    configVersion: "1.0",
    executionTimeMs: 0
  )

  result.config = config
  result.turnSnapshots = @[]

  var state = initialState
  var cumulativeData = initTable[HouseId, tuple[gco, ncv, prestige: int]]()

  # Simulate game
  for turn in 1..config.numberOfTurns:
    # TODO: Generate AI orders for each house based on strategy
    var orders = initTable[HouseId, OrderPacket]()

    # Resolve turn
    let turnResult = resolveTurn(state, orders)
    state = turnResult.newState

    # Capture snapshot
    let snapshot = captureTurnSnapshot(state, turnResult, cumulativeData)
    result.turnSnapshots.add(snapshot)

    # Check victory conditions
    # TODO: Implement victory check

  # Calculate outcome and metrics
  # TODO: Analyze results and populate outcome/metrics

  let endTime = cpuTime()
  result.metadata.executionTimeMs = int((endTime - startTime) * 1000)

proc exportBalanceTest*(testResult: BalanceTestResult, outputPath: string) =
  ## Export test results to JSON file
  let jsonData = testResult.toJson()
  writeFile(outputPath, jsonData.pretty())
  echo &"Balance test exported to: {outputPath}"

# =============================================================================
# Example Usage
# =============================================================================

when isMainModule:
  echo "Balance Testing Framework"
  echo "========================="
  echo ""
  echo "This framework simulates complete games and exports detailed"
  echo "JSON data for AI-powered balance analysis."
  echo ""
  echo "Usage:"
  echo "  1. Define test scenarios in balance test files"
  echo "  2. Run simulations with various AI strategies"
  echo "  3. Export JSON results"
  echo "  4. Feed JSON to AI for analysis and recommendations"
