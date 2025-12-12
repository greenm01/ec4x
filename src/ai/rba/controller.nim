## Main AI Controller for EC4X Rule-Based AI
##
## Coordinates all AI subsystems and manages AI state

import std/[tables, options]
import ../common/types
import ./[controller_types, config]
import ../../engine/[gamestate, order_types]
import ../../common/types/core
import ./goap/core/types as goap_types
import ./goap/integration/[plan_tracking, conversion]

export controller_types
export StandingOrder, StandingOrderType, StandingOrderParams

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
    # intelligence field removed - use intelligenceSnapshot instead
    operations: @[],
    reserves: @[],
    fallbackRoutes: @[],
    homeworld: homeworld,
    standingOrders: initTable[FleetId, StandingOrder](),
    offensiveFleetOrders: @[],
    fleetManagementCommands: @[],
    pendingIntelUpdates: @[],
    # GOAP strategic planning integration (MVP: Fleet + Build domains)
    goapEnabled: globalRBAConfig.goap.enabled,
    goapLastPlanningTurn: -1,
    goapActiveGoals: @[],
    goapBudgetEstimates: none(Table[conversion.DomainType, int]),
    goapReservedBudget: none(int),
    goapConfig: globalRBAConfig.goap,
    goapPlanTracker: newPlanTracker(),
    intelligenceNeedsRefresh: false,  # Initialize refresh flag
    # Phase 2: Multi-turn invasion campaigns
    activeCampaigns: @[]
  )

proc newAIControllerWithPersonality*(houseId: HouseId, personality: AIPersonality, homeworld: SystemId = 0.SystemId): AIController =
  ## Create a new AI controller with a custom personality (for genetic algorithm)
  ## Note: homeworld should be set from GameState after initialization if not provided
  AIController(
    houseId: houseId,
    strategy: AIStrategy.Balanced,
    personality: personality,
    # intelligence field removed - use intelligenceSnapshot instead
    operations: @[],
    reserves: @[],
    fallbackRoutes: @[],
    homeworld: homeworld,
    standingOrders: initTable[FleetId, StandingOrder](),
    offensiveFleetOrders: @[],
    fleetManagementCommands: @[],
    pendingIntelUpdates: @[],
    # GOAP strategic planning integration (MVP: Fleet + Build domains)
    goapEnabled: globalRBAConfig.goap.enabled,
    goapLastPlanningTurn: -1,
    goapActiveGoals: @[],
    goapBudgetEstimates: none(Table[conversion.DomainType, int]),
    goapReservedBudget: none(int),
    goapConfig: globalRBAConfig.goap,
    goapPlanTracker: newPlanTracker(),
    intelligenceNeedsRefresh: false,  # Initialize refresh flag
    # Phase 2: Multi-turn invasion campaigns
    activeCampaigns: @[]
  )

# =============================================================================
# High-Level Coordination Functions
# =============================================================================

# TODO: Note: Tactical/strategic functions imported later to avoid circular dependency
