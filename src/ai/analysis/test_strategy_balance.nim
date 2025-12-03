## Strategy Balance Test
##
## Tests different strategic approaches (military, economic, espionage, diplomatic)
## to verify multiple paths to victory exist and are balanced.

import std/[tables, options, random]
import balance_framework
import ../../engine/[gamestate, resolve, orders, starmap]
import ../../engine/espionage/types as esp_types
import ../../engine/research/types as res_types
import ../../common/types/[core, units, planets, tech]
import ../../engine/config/gameplay_config

# =============================================================================
# AI Strategy Types
# =============================================================================

type
  AIStrategy* {.pure.} = enum
    ## Different AI play styles for balance testing
    Aggressive,      # Heavy military, early attacks
    Economic,        # Focus on growth and tech
    Espionage,       # Intelligence and sabotage
    Diplomatic,      # Pacts and manipulation
    Balanced,        # Mixed approach
    Turtle,          # Defensive, slow expansion
    Expansionist     # Rapid colonization

  AIController* = object
    houseId*: HouseId
    strategy*: AIStrategy
    personality*: AIPersonality

  AIPersonality* = object
    aggression*: float       # 0.0-1.0: How likely to attack
    riskTolerance*: float    # 0.0-1.0: Willingness to take risks
    economicFocus*: float    # 0.0-1.0: Priority on economy vs military
    expansionDrive*: float   # 0.0-1.0: How aggressively to expand
    diplomacyValue*: float   # 0.0-1.0: Value placed on alliances
    techPriority*: float     # 0.0-1.0: Research investment priority

# =============================================================================
# Strategy Profiles
# =============================================================================

proc getStrategyPersonality*(strategy: AIStrategy): AIPersonality =
  ## Get personality parameters for a strategy
  case strategy
  of AIStrategy.Aggressive:
    AIPersonality(
      aggression: 0.9,
      riskTolerance: 0.8,
      economicFocus: 0.3,
      expansionDrive: 0.7,
      diplomacyValue: 0.2,
      techPriority: 0.4
    )
  of AIStrategy.Economic:
    AIPersonality(
      aggression: 0.2,
      riskTolerance: 0.3,
      economicFocus: 0.9,
      expansionDrive: 0.5,
      diplomacyValue: 0.6,
      techPriority: 0.8
    )
  of AIStrategy.Espionage:
    AIPersonality(
      aggression: 0.5,
      riskTolerance: 0.6,
      economicFocus: 0.5,
      expansionDrive: 0.4,
      diplomacyValue: 0.4,
      techPriority: 0.6
    )
  of AIStrategy.Diplomatic:
    AIPersonality(
      aggression: 0.3,
      riskTolerance: 0.4,
      economicFocus: 0.6,
      expansionDrive: 0.5,
      diplomacyValue: 0.9,
      techPriority: 0.5
    )
  of AIStrategy.Balanced:
    AIPersonality(
      aggression: 0.5,
      riskTolerance: 0.5,
      economicFocus: 0.5,
      expansionDrive: 0.5,
      diplomacyValue: 0.5,
      techPriority: 0.5
    )
  of AIStrategy.Turtle:
    AIPersonality(
      aggression: 0.1,
      riskTolerance: 0.2,
      economicFocus: 0.7,
      expansionDrive: 0.2,
      diplomacyValue: 0.7,
      techPriority: 0.7
    )
  of AIStrategy.Expansionist:
    AIPersonality(
      aggression: 0.6,
      riskTolerance: 0.7,
      economicFocus: 0.4,
      expansionDrive: 0.95,
      diplomacyValue: 0.3,
      techPriority: 0.3
    )

# =============================================================================
# AI Order Generation
# =============================================================================

proc generateAIOrders*(controller: AIController, state: GameState,
                      rng: var Rand): OrderPacket =
  ## Generate orders for an AI player based on strategy
  result = OrderPacket(
    houseId: controller.houseId,
    turn: 0,  # Will be set by caller
    treasury: 0,  # Will be set by caller
    fleetOrders: @[],
    buildOrders: @[],
    researchAllocation: res_types.ResearchAllocation(
      economic: 0,
      science: 0,
      technology: initTable[TechField, int]()
    ),
    diplomaticActions: @[],
    populationTransfers: @[],
    terraformOrders: @[],
    espionageAction: none(esp_types.EspionageAttempt),
    ebpInvestment: 0,
    cipInvestment: 0
  )

  let p = controller.personality

  # TODO: Set tax rate on colonies directly in state, not in orders
  # Tax rate should be set on House or Colony objects, not in OrderPacket

  # TODO: Research allocation based on tech priority
  # Calculate PP amounts to allocate to economic, science, and tech research
  # For now, leaving empty - would need to calculate from house treasury

  # Espionage based on strategy
  case controller.strategy
  of AIStrategy.Espionage:
    result.ebpInvestment = 200  # Heavy espionage investment
    result.cipInvestment = 100
    # TODO: Select espionage action
  of AIStrategy.Aggressive:
    result.ebpInvestment = 50   # Light espionage
    # TODO: Tech theft or sabotage
  else:
    result.ebpInvestment = 25   # Minimal counter-intel
    result.cipInvestment = 25

  # TODO: Generate fleet orders based on aggression/expansion
  # TODO: Generate build orders based on economic focus
  # TODO: Generate diplomatic actions based on diplomacy value

# =============================================================================
# Test Scenarios
# =============================================================================

proc createStandardTestGame*(numHouses: int, strategies: seq[AIStrategy]): GameState =
  ## Create a standard test game setup using the proper constructor
  # Use newGame() to get a properly initialized game state
  result = newGame("test_strategy_balance_" & $numHouses, numHouses, seed = 42)

proc testMilitaryVsEconomic*(): BalanceTestResult =
  ## Test if military and economic strategies are balanced
  let config = BalanceTestConfig(
    testName: "military_vs_economic",
    description: "Compare aggressive military expansion vs economic growth",
    numberOfHouses: 4,
    numberOfTurns: 100,
    mapSize: 50,
    startingConditions: "equal",
    aiStrategies: @["Aggressive", "Aggressive", "Economic", "Economic"],
    tags: @["strategy-balance", "military", "economic"]
  )

  let initialState = createStandardTestGame(4, @[
    AIStrategy.Aggressive,
    AIStrategy.Aggressive,
    AIStrategy.Economic,
    AIStrategy.Economic
  ])

  result = runBalanceTest(config, initialState)

proc testAllStrategies*(): BalanceTestResult =
  ## Test all 7 strategies against each other
  let config = BalanceTestConfig(
    testName: "all_strategies",
    description: "Full round-robin test of all AI strategies",
    numberOfHouses: 7,
    numberOfTurns: 150,
    mapSize: 80,
    startingConditions: "equal",
    aiStrategies: @[
      "Aggressive", "Economic", "Espionage", "Diplomatic",
      "Balanced", "Turtle", "Expansionist"
    ],
    tags: @["comprehensive", "strategy-balance"]
  )

  let initialState = createStandardTestGame(7, @[
    AIStrategy.Aggressive,
    AIStrategy.Economic,
    AIStrategy.Espionage,
    AIStrategy.Diplomatic,
    AIStrategy.Balanced,
    AIStrategy.Turtle,
    AIStrategy.Expansionist
  ])

  result = runBalanceTest(config, initialState)

proc testEarlyAggression*(): BalanceTestResult =
  ## Test if early aggression is too powerful or too weak
  let config = BalanceTestConfig(
    testName: "early_aggression",
    description: "Test early military rush vs defensive play",
    numberOfHouses: 3,
    numberOfTurns: 50,
    mapSize: 30,
    startingConditions: "close_proximity",
    aiStrategies: @["Aggressive", "Turtle", "Balanced"],
    tags: @["early-game", "military", "timing"]
  )

  let initialState = createStandardTestGame(3, @[
    AIStrategy.Aggressive,
    AIStrategy.Turtle,
    AIStrategy.Balanced
  ])

  result = runBalanceTest(config, initialState)

# =============================================================================
# Main Test Runner
# =============================================================================

when isMainModule:
  import std/[strformat, strutils]

  echo repeat("=", 60)
  echo "EC4X Strategy Balance Tests"
  echo repeat("=", 60)
  echo ""

  # Test 1: Military vs Economic
  echo "Running Test 1: Military vs Economic..."
  let test1 = testMilitaryVsEconomic()
  exportBalanceTest(test1, "balance_results/military_vs_economic.json")
  echo &"  ✓ Exported: balance_results/military_vs_economic.json"
  echo ""

  # Test 2: All Strategies
  echo "Running Test 2: All Strategies..."
  let test2 = testAllStrategies()
  exportBalanceTest(test2, "balance_results/all_strategies.json")
  echo &"  ✓ Exported: balance_results/all_strategies.json"
  echo ""

  # Test 3: Early Aggression
  echo "Running Test 3: Early Aggression..."
  let test3 = testEarlyAggression()
  exportBalanceTest(test3, "balance_results/early_aggression.json")
  echo &"  ✓ Exported: balance_results/early_aggression.json"
  echo ""

  echo repeat("=", 60)
  echo "All tests complete!"
  echo ""
  echo "Next steps:"
  echo "1. Review JSON files in balance_results/"
  echo "2. Feed JSON to Claude/GPT for analysis"
  echo "3. Implement AI recommendations"
  echo "4. Re-run tests to verify improvements"
