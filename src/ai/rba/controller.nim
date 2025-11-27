## Main AI Controller for EC4X Rule-Based AI
##
## Coordinates all AI subsystems and manages AI state

import std/[tables, options]
import ../common/types
import ./controller_types
export controller_types
import ../../engine/[gamestate, fog_of_war]
import ../../engine/order_types
export StandingOrder, StandingOrderType, StandingOrderParams
import ../../common/types/core
import ./config  # RBA configuration system

# =============================================================================
# Strategy Profiles
# =============================================================================

proc getStrategyPersonality*(strategy: AIStrategy): AIPersonality =
  ## Get personality parameters from config
  ## Loads values from config/rba.toml instead of hardcoded constants
  let cfg = case strategy
    of AIStrategy.Aggressive: globalRBAConfig.strategies_aggressive
    of AIStrategy.Economic: globalRBAConfig.strategies_economic
    of AIStrategy.Espionage: globalRBAConfig.strategies_espionage
    of AIStrategy.Diplomatic: globalRBAConfig.strategies_diplomatic
    of AIStrategy.Balanced: globalRBAConfig.strategies_balanced
    of AIStrategy.Turtle: globalRBAConfig.strategies_turtle
    of AIStrategy.Expansionist: globalRBAConfig.strategies_expansionist
    of AIStrategy.TechRush: globalRBAConfig.strategies_tech_rush
    of AIStrategy.Raider: globalRBAConfig.strategies_raider
    of AIStrategy.MilitaryIndustrial: globalRBAConfig.strategies_military_industrial
    of AIStrategy.Opportunistic: globalRBAConfig.strategies_opportunistic
    of AIStrategy.Isolationist: globalRBAConfig.strategies_isolationist

  AIPersonality(
    aggression: cfg.aggression,
    riskTolerance: cfg.risk_tolerance,
    economicFocus: cfg.economic_focus,
    expansionDrive: cfg.expansion_drive,
    diplomacyValue: cfg.diplomacy_value,
    techPriority: cfg.tech_priority
  )

# =============================================================================
# Constructor Functions
# =============================================================================

proc newAIController*(houseId: HouseId, strategy: AIStrategy, homeworld: SystemId = 0.SystemId): AIController =
  ## Create a new AI controller for a house
  ## Note: homeworld should be set from GameState after initialization if not provided
  AIController(
    houseId: houseId,
    strategy: strategy,
    personality: getStrategyPersonality(strategy),
    intelligence: initTable[SystemId, IntelligenceReport](),
    operations: @[],
    reserves: @[],
    fallbackRoutes: @[],
    homeworld: homeworld,
    standingOrders: initTable[FleetId, StandingOrder]()
  )

proc newAIControllerWithPersonality*(houseId: HouseId, personality: AIPersonality, homeworld: SystemId = 0.SystemId): AIController =
  ## Create a new AI controller with a custom personality (for genetic algorithm)
  ## Note: homeworld should be set from GameState after initialization if not provided
  AIController(
    houseId: houseId,
    strategy: AIStrategy.Balanced,
    personality: personality,
    intelligence: initTable[SystemId, IntelligenceReport](),
    operations: @[],
    reserves: @[],
    fallbackRoutes: @[],
    homeworld: homeworld,
    standingOrders: initTable[FleetId, StandingOrder]()
  )

# =============================================================================
# High-Level Coordination Functions
# =============================================================================

# Note: Tactical/strategic functions imported later to avoid circular dependency
