## Main AI Controller for EC4X Rule-Based AI
##
## Coordinates all AI subsystems and manages AI state

import std/[tables, options, sets]
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

proc getStrategyPersonality*(strategy: AIStrategy,
                             rbaConfig: RBAConfig): AIPersonality =
  ## Get personality parameters from config
  ## Takes RBAConfig explicitly to avoid global state in FFI context
  let cfg = case strategy
    of AIStrategy.Aggressive: rbaConfig.strategies_aggressive
    of AIStrategy.Economic: rbaConfig.strategies_economic
    of AIStrategy.Espionage: rbaConfig.strategies_espionage
    of AIStrategy.Diplomatic: rbaConfig.strategies_diplomatic
    of AIStrategy.Balanced: rbaConfig.strategies_balanced
    of AIStrategy.Turtle: rbaConfig.strategies_turtle
    of AIStrategy.Expansionist: rbaConfig.strategies_expansionist
    of AIStrategy.TechRush: rbaConfig.strategies_tech_rush
    of AIStrategy.Raider: rbaConfig.strategies_raider
    of AIStrategy.MilitaryIndustrial: rbaConfig.strategies_military_industrial
    of AIStrategy.Opportunistic: rbaConfig.strategies_opportunistic
    of AIStrategy.Isolationist: rbaConfig.strategies_isolationist

  AIPersonality(
    aggression: cfg.aggression,
    riskTolerance: cfg.risk_tolerance,
    economicFocus: cfg.economic_focus,
    expansionDrive: cfg.expansion_drive,
    diplomacyValue: cfg.diplomacy_value,
    techPriority: cfg.tech_priority
  )

proc getStrategyPersonality*(strategy: AIStrategy): AIPersonality =
  ## Get personality parameters from global config
  ## Convenience overload for non-FFI context
  getStrategyPersonality(strategy, globalRBAConfig)

# =============================================================================
# Constructor Functions
# =============================================================================

proc newAIController*(houseId: HouseId, strategy: AIStrategy,
                     rbaConfig: RBAConfig,
                     homeworld: SystemId = 0.SystemId): AIController =
  ## Create a new AI controller for a house with explicit config
  ## Takes RBAConfig explicitly to avoid global state in FFI context
  ## Note: homeworld should be set from GameState after initialization if not
  ## provided
  AIController(
    houseId: houseId,
    strategy: strategy,
    personality: getStrategyPersonality(strategy, rbaConfig),
    # intelligence field removed - use intelligenceSnapshot instead
    operations: @[],
    reserves: @[],
    fallbackRoutes: @[],
    homeworld: homeworld,
    standingOrders: initTable[FleetId, StandingOrder](),
    offensiveFleetOrders: @[],
    fleetManagementCommands: @[],
    pendingIntelUpdates: @[],
    # REMOVED: eparchColonizationOrders - now in EconomicRequirements.colonizationOrders
    # GOAP strategic planning integration (MVP: Fleet + Build domains)
    goapEnabled: rbaConfig.goap.enabled,
    goapLastPlanningTurn: -1,
    goapActiveGoals: @[],
    goapBudgetEstimates: none(Table[conversion.DomainType, int]),
    goapReservedBudget: none(int),
    goapConfig: rbaConfig.goap,
    goapPlanTracker: newPlanTracker(),
    rbaConfig: rbaConfig,  # Store full config for subsystems
    intelligenceNeedsRefresh: false,  # Initialize refresh flag
    # Phase 2: Multi-turn invasion campaigns
    activeCampaigns: @[]
  )

proc newAIController*(houseId: HouseId, strategy: AIStrategy,
                     homeworld: SystemId = 0.SystemId): AIController =
  ## Create a new AI controller for a house using global config
  ## Convenience overload for non-FFI context
  newAIController(houseId, strategy, globalRBAConfig, homeworld)

proc newAIControllerWithPersonality*(houseId: HouseId,
                                     personality: AIPersonality,
                                     rbaConfig: RBAConfig,
                                     homeworld: SystemId = 0.SystemId): AIController =
  ## Create a new AI controller with a custom personality (for genetic algorithm)
  ## Takes explicit config to avoid global state in FFI context
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
    # REMOVED: eparchColonizationOrders - now in EconomicRequirements.colonizationOrders
    # GOAP strategic planning integration (MVP: Fleet + Build domains)
    goapEnabled: rbaConfig.goap.enabled,
    goapLastPlanningTurn: -1,
    goapActiveGoals: @[],
    goapBudgetEstimates: none(Table[conversion.DomainType, int]),
    goapReservedBudget: none(int),
    goapConfig: rbaConfig.goap,
    goapPlanTracker: newPlanTracker(),
    rbaConfig: rbaConfig,  # Store full config for subsystems
    intelligenceNeedsRefresh: false,  # Initialize refresh flag
    # Phase 2: Multi-turn invasion campaigns
    activeCampaigns: @[]
  )

proc newAIControllerWithPersonality*(houseId: HouseId,
                                     personality: AIPersonality,
                                     homeworld: SystemId = 0.SystemId): AIController =
  ## Create a new AI controller with a custom personality using global config
  ## Convenience overload for non-FFI context
  newAIControllerWithPersonality(houseId, personality, globalRBAConfig,
                                 homeworld)

# =============================================================================
# High-Level Coordination Functions
# =============================================================================

# TODO: Note: Tactical/strategic functions imported later to avoid circular dependency
