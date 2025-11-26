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
      economicFocus: 0.5,
      expansionDrive: 0.8,
      diplomacyValue: 0.2,
      techPriority: 0.4
    )
  of AIStrategy.Economic:
    AIPersonality(
      aggression: 0.3,
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
      expansionDrive: 0.65,
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
      aggression: 0.4,
      riskTolerance: 0.5,
      economicFocus: 0.7,
      expansionDrive: 0.5,
      diplomacyValue: 0.6,
      techPriority: 0.5
    )
  of AIStrategy.Turtle:
    AIPersonality(
      aggression: 0.1,
      riskTolerance: 0.3,
      economicFocus: 0.7,
      expansionDrive: 0.4,
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
  of AIStrategy.TechRush:
    AIPersonality(
      aggression: 0.2,
      riskTolerance: 0.4,
      economicFocus: 0.8,
      expansionDrive: 0.4,
      diplomacyValue: 0.7,
      techPriority: 0.95
    )
  of AIStrategy.Raider:
    AIPersonality(
      aggression: 0.85,
      riskTolerance: 0.9,
      economicFocus: 0.4,
      expansionDrive: 0.6,
      diplomacyValue: 0.1,
      techPriority: 0.5
    )
  of AIStrategy.MilitaryIndustrial:
    AIPersonality(
      aggression: 0.7,
      riskTolerance: 0.5,
      economicFocus: 0.75,
      expansionDrive: 0.6,
      diplomacyValue: 0.3,
      techPriority: 0.6
    )
  of AIStrategy.Opportunistic:
    AIPersonality(
      aggression: 0.5,
      riskTolerance: 0.6,
      economicFocus: 0.6,
      expansionDrive: 0.6,
      diplomacyValue: 0.5,
      techPriority: 0.5
    )
  of AIStrategy.Isolationist:
    AIPersonality(
      aggression: 0.15,
      riskTolerance: 0.2,
      economicFocus: 0.85,
      expansionDrive: 0.3,
      diplomacyValue: 0.2,
      techPriority: 0.75
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
