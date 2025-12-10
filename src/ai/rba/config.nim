## RBA Configuration Loader
##
## Loads AI tuning parameters from config/rba.toml using toml_serialization
## Enables balance testing without recompilation
##
## Architecture:
## - Type-safe TOML deserialization
## - Global config instance for easy access
## - Follows engine config pattern (economy_config.nim)

import std/[os, strformat]
import toml_serialization
import ../../engine/config/validators
import ../../engine/logger

# ==============================================================================
# Strategy Personalities
# ==============================================================================

type
  StrategyPersonalityConfig* = object
    ## Personality parameters for a single AI strategy
    aggression*: float
    risk_tolerance*: float
    economic_focus*: float
    expansion_drive*: float
    diplomacy_value*: float
    tech_priority*: float


# ==============================================================================
# Budget Allocations
# ==============================================================================

type
  BudgetAllocationConfig* = object
    ## Budget allocation percentages for one game act
    expansion*: float
    defense*: float
    military*: float
    reconnaissance*: float
    special_units*: float
    technology*: float
    filler_budget_reserved*: float  # Capacity filler budget reservation (Gap Fix)


# ==============================================================================
# Tactical Parameters
# ==============================================================================

type
  TacticalConfig* = object
    ## Operational limits for fleet movements
    response_radius_jumps*: int
    max_invasion_eta_turns*: int
    max_response_eta_turns*: int

# ==============================================================================
# Strategic Parameters
# ==============================================================================

type
  StrategicConfig* = object
    ## Combat engagement thresholds
    attack_threshold*: float
    aggressive_attack_threshold*: float
    retreat_threshold*: float

# ==============================================================================
# Economic Parameters
# ==============================================================================

type
  EconomicParametersConfig* = object
    ## Economic-related parameters (terraforming costs in PP)
    terraforming_costs_extreme_to_desolate*: int
    terraforming_costs_desolate_to_hostile*: int
    terraforming_costs_hostile_to_harsh*: int
    terraforming_costs_harsh_to_benign*: int
    terraforming_costs_benign_to_lush*: int
    terraforming_costs_lush_to_eden*: int

  EparchConfig* = object
    ## Eparch (economic administration) parameters
    ## Colony management, auto-repair thresholds, tax rates
    auto_repair_threshold*: int  # Min treasury (PP) to enable auto-repair

# ==============================================================================
# Orders Parameters
# ==============================================================================

type
  OrdersConfig* = object
    ## Order generation parameters
    research_max_percent*: float
    espionage_investment_percent*: float
    scout_count_act1*: int
    scout_count_act2*: int
    scout_count_act3_plus*: int

# ==============================================================================
# Logistics Parameters
# ==============================================================================

type
  LogisticsConfig* = object
    ## Logistics parameters (mothballing thresholds)
    mothballing_treasury_threshold_pp*: int
    mothballing_maintenance_ratio_threshold*: float
    mothballing_min_fleet_count*: int

# ==============================================================================
# Fleet Composition
# ==============================================================================

type
  FleetCompositionRatioConfig* = object
    ## Target composition ratios for one doctrine
    capital_ratio*: float
    escort_ratio*: float
    specialist_ratio*: float

# ==============================================================================
# Threat Assessment
# ==============================================================================

type
  ThreatAssessmentConfig* = object
    ## Threat level classification thresholds
    critical_threshold*: float
    high_threshold*: float
    moderate_threshold*: float
    low_threshold*: float

# ==============================================================================
# Admiral Configuration
# ==============================================================================

type
  AdmiralConfig* = object
    ## Admiral module parameters (fleet rebalancing)
    enabled*: bool
    split_threshold_act1*: int
    merge_threshold_act2*: int
    rendezvous_preference*: string
    max_invasion_eta_turns*: int # Max turns for a fleet to reach an invasion target

    # ZeroTurnCommand Fleet Management (merge/detach/transfer)
    fleet_management_enabled*: bool

    # Phase 3: Build Requirements System
    build_requirements_enabled*: bool
    defense_gap_detection_enabled*: bool
    defense_gap_max_distance*: int
    offensive_requirements_enabled*: bool
    critical_priority_homeworld*: bool
    high_priority_production_threshold*: int
    threat_assessment_radius*: int

    # Strategic Triage Budget Reserves
    min_recon_budget_percent*: float
    min_expansion_budget_percent*: float

    # Escalation Thresholds
    escalation_low_to_medium_turns*: int
    escalation_medium_to_high_turns*: int
    escalation_high_to_critical_turns*: int

    # Intelligence-Driven Ship Building (Phase F)
    capacity_high_utilization_threshold*: float
    scouts_per_stale_intel_system*: float
    scouts_per_enemy_house*: float
    max_scouts_act1*: int
    etacs_per_uncolonized_system*: float
    max_etacs_queued*: int
    aggressive_transport_ratio*: float
    aggressive_marine_per_transport*: int
    reactive_invasion_multiplier*: float
    fighter_threat_threshold_low*: float
    fighter_threat_threshold_high*: float
    max_fighters*: int
    fighters_per_carrier*: int
    max_carriers*: int

# ==============================================================================
# Intelligence Integration Configuration (Phase B+)
# ==============================================================================

type
  ThreatResponseConfig* = object
    ## Threat-aware budget allocation parameters (Phase D)
    low_threat_boost*: float
    moderate_threat_boost*: float
    high_threat_boost*: float
    critical_threat_boost*: float
    multi_threat_multiplier*: float
    defense_boost_ratio*: float
    military_boost_ratio*: float

  SurveillanceConfig* = object
    ## Surveillance gap priority weights (Phase D)
    border_system_priority*: float
    high_value_priority*: float
    transit_route_priority*: float
    recent_activity_priority*: float

  DiplomaticEventsConfig* = object
    ## Diplomatic event analysis parameters (Phase E)
    war_significance_threshold*: int
    alliance_significance_threshold*: int
    blockade_critical_threshold*: float

  CounterintelConfig* = object
    ## Counter-intelligence priorities (Phase E)
    high_frequency_threshold*: int
    detection_success_threshold*: float
    priority_boost_espionage*: float

  ConstructionAnalysisConfig* = object
    ## Construction trend detection parameters (Phase E)
    buildup_threshold_shipyards*: int
    velocity_threat_threshold*: float
    observation_window_turns*: int

  PatrolDetectionConfig* = object
    ## Patrol pattern recognition parameters (Phase E)
    min_sightings_for_pattern*: int
    pattern_confidence_threshold*: float
    staleness_threshold_turns*: int

  IntelligenceConfig* = object
    ## Enhanced intelligence processing parameters
    # Report freshness thresholds (turns)
    colony_intel_stale_threshold*: int
    system_intel_stale_threshold*: int
    starbase_intel_stale_threshold*: int

    # Threat assessment weights (must sum to 1.0)
    threat_fleet_strength_weight*: float
    threat_proximity_weight*: float
    threat_recent_activity_weight*: float

    # Threat distance thresholds (jumps)
    threat_critical_distance*: int
    threat_high_distance*: int
    threat_moderate_distance*: int

    # Vulnerability assessment
    vulnerability_defense_ratio_threshold*: float
    vulnerability_value_threshold*: int

    # Combat learning (Phase C)
    combat_report_learning_enabled*: bool
    combat_lesson_retention_turns*: int
    combat_doctrine_detection_threshold*: int

    # Economic intelligence (Phase C)
    economic_assessment_min_colonies*: int
    economic_strength_production_weight*: float
    economic_strength_income_weight*: float

    # Research intelligence (Phase C)
    tech_gap_critical_threshold*: int
    tech_gap_high_threshold*: int

  DrungariusConfig* = object
    ## Intelligence coordinator settings
    intel_processing_enabled*: bool
    use_combat_lessons*: bool
    use_starbase_surveillance*: bool
    prioritize_high_value_targets*: bool

# ==============================================================================
# Gap Fix Configuration (Phase 1-2)
# ==============================================================================



type
  GOAPConfig* = object
    ## Configuration for GOAP strategic planning
    enabled*: bool                    # Enable/disable GOAP
    planning_depth*: int               # Max turns to plan ahead
    confidence_threshold*: float       # Min confidence to execute plan
    max_concurrent_plans*: int          # Max active plans at once
    defense_priority*: float           # Weight for defensive goals (0.0-1.0)
    offense_priority*: float           # Weight for offensive goals (0.0-1.0)
    log_plans*: bool                   # Debug: log all generated plans
    budget_guidance_boost_factor*: float # How much GOAP estimates boost RBA requirements (0.0-1.0)
    replan_stalled_turns*: int         # Number of turns without progress to trigger replan
    replan_budget_shortfall_ratio*: float # % of remaining cost below which to trigger replan
    new_opportunity_scan_frequency*: int # How often to check for new opportunities (turns)


type
  FeedbackSystemConfig* = object
    ## Rich feedback generation configuration (Gap 6)
    enabled*: bool
    suggest_cheaper_alternatives*: bool
    min_partial_fulfillment_ratio*: float

  ReprioritizationConfig* = object
    ## Enhanced reprioritization configuration (Gap 4)
    enable_quantity_adjustment*: bool
    min_quantity_reduction*: int
    enable_substitution*: bool
    max_cost_reduction_factor*: float
    facility_critical_to_high_turns*: int
    facility_high_to_medium_turns*: int

  StandingOrdersIntegrationConfig* = object
    ## Standing order integration configuration (Gap 5)
    generate_support_requirements*: bool
    defense_gap_priority_boost*: int
    filler_standing_order_bias*: float
    track_colony_defense_history*: bool
    max_history_entries*: int

# ==============================================================================
# Eparch Industrial Investment Configuration
# ==============================================================================

type
  EparchIndustrialConfig* = object
    ## Industrial investment thresholds and parameters
    iu_growth_divisor*: float
    iu_payback_threshold_turns*: int
    iu_affordability_multiplier*: int
    iu_investment_fraction*: float
    iu_minimum_investment*: int

  TreasuryThresholdsConfig* = object
    ## Treasury health thresholds for various AI decisions
    terraform_minimum*: int
    terraform_buffer*: int
    transfer_healthy*: int
    salvage_critical*: int
    reactivation_healthy*: int

  AffordabilityChecksConfig* = object
    ## Treasury multipliers for affordability checks
    general_multiplier*: float
    shield_multiplier*: float
    critical_multiplier*: float

# ==============================================================================
# Root Configuration
# ==============================================================================

type
  RBAConfig* = object
    ## Complete RBA configuration loaded from TOML
    # Strategy personalities (12 strategies)
    strategies_aggressive*: StrategyPersonalityConfig
    strategies_economic*: StrategyPersonalityConfig
    strategies_espionage*: StrategyPersonalityConfig
    strategies_diplomatic*: StrategyPersonalityConfig
    strategies_balanced*: StrategyPersonalityConfig
    strategies_turtle*: StrategyPersonalityConfig
    strategies_expansionist*: StrategyPersonalityConfig
    strategies_tech_rush*: StrategyPersonalityConfig
    strategies_raider*: StrategyPersonalityConfig
    strategies_military_industrial*: StrategyPersonalityConfig
    strategies_opportunistic*: StrategyPersonalityConfig
    strategies_isolationist*: StrategyPersonalityConfig
    # Budget allocations (4 acts)
    budget_act1_land_grab*: BudgetAllocationConfig
    budget_act2_rising_tensions*: BudgetAllocationConfig
    budget_act3_total_war*: BudgetAllocationConfig
    budget_act4_endgame*: BudgetAllocationConfig
    # Tactical parameters
    tactical*: TacticalConfig
    # Strategic parameters
    strategic*: StrategicConfig
    # Economic parameters
    economic*: EconomicParametersConfig
    # Orders parameters
    orders*: OrdersConfig
    # Logistics parameters
    logistics*: LogisticsConfig
    # Fleet composition ratios (3 doctrines)
    fleet_composition_balanced*: FleetCompositionRatioConfig
    fleet_composition_aggressive*: FleetCompositionRatioConfig
    fleet_composition_defensive*: FleetCompositionRatioConfig
    # Threat assessment
    threat_assessment*: ThreatAssessmentConfig
    # Admiral module (fleet rebalancing)
    domestikos*: AdmiralConfig
    # Eparch module (economic administration)
    eparch*: EparchConfig
    # Intelligence integration (Phase B+)
    intelligence*: IntelligenceConfig
    # Intelligence sub-configurations (Phase D+)
    intelligence_threat_response*: ThreatResponseConfig
    intelligence_surveillance*: SurveillanceConfig
    intelligence_diplomatic_events*: DiplomaticEventsConfig
    intelligence_counterintel*: CounterintelConfig
    intelligence_construction_analysis*: ConstructionAnalysisConfig
    intelligence_patrol_detection*: PatrolDetectionConfig
    # Drungarius module (intelligence coordinator)
    drungarius*: DrungariusConfig
    # Gap Fix modules (Phase 1-2)
    feedback_system*: FeedbackSystemConfig
    reprioritization*: ReprioritizationConfig
    standing_orders_integration*: StandingOrdersIntegrationConfig
    # Eparch industrial investment (refactoring Phase 4)
    eparch_industrial*: EparchIndustrialConfig
    treasury_thresholds*: TreasuryThresholdsConfig
    affordability_checks*: AffordabilityChecksConfig
    goap*: GOAPConfig # New GOAP configuration section

# ==============================================================================
# Config Validation
# ==============================================================================

proc validateRBAConfig*(config: RBAConfig) =
  ## Validates RBA configuration after loading
  ## Ensures all parameters are within valid ranges and constraints
  ##
  ## Validates:
  ## - Strategy personality traits (0.0-1.0)
  ## - Budget allocations per act (sum to 1.0)
  ## - Fleet composition ratios (sum to 1.0)
  ## - Tactical/strategic thresholds

  # Validate all strategy personality traits are ratios (0.0-1.0)
  let strategies = [
    ("aggressive", config.strategies_aggressive),
    ("economic", config.strategies_economic),
    ("espionage", config.strategies_espionage),
    ("diplomatic", config.strategies_diplomatic),
    ("balanced", config.strategies_balanced),
    ("turtle", config.strategies_turtle),
    ("expansionist", config.strategies_expansionist),
    ("tech_rush", config.strategies_tech_rush),
    ("raider", config.strategies_raider),
    ("military_industrial", config.strategies_military_industrial),
    ("opportunistic", config.strategies_opportunistic),
    ("isolationist", config.strategies_isolationist)
  ]

  for (name, strategy) in strategies:
    validateRatio(strategy.aggression, &"strategies_{name}.aggression")
    validateRatio(strategy.risk_tolerance, &"strategies_{name}.risk_tolerance")
    validateRatio(strategy.economic_focus, &"strategies_{name}.economic_focus")
    validateRatio(strategy.expansion_drive, &"strategies_{name}.expansion_drive")
    validateRatio(strategy.diplomacy_value, &"strategies_{name}.diplomacy_value")
    validateRatio(strategy.tech_priority, &"strategies_{name}.tech_priority")

  # Validate budget allocations sum to 1.0 for each act
  let budgets = [
    ("act1_land_grab", config.budget_act1_land_grab),
    ("act2_rising_tensions", config.budget_act2_rising_tensions),
    ("act3_total_war", config.budget_act3_total_war),
    ("act4_endgame", config.budget_act4_endgame)
  ]

  for (actName, budget) in budgets:
    validateSumToOne([
      budget.expansion,
      budget.defense,
      budget.military,
      budget.reconnaissance,
      budget.special_units,
      budget.technology
    ], tolerance = 0.01, context = &"budget_{actName}")

  # Validate fleet composition ratios sum to 1.0
  let compositions = [
    ("balanced", config.fleet_composition_balanced),
    ("aggressive", config.fleet_composition_aggressive),
    ("defensive", config.fleet_composition_defensive)
  ]

  for (name, comp) in compositions:
    validateSumToOne([
      comp.capital_ratio,
      comp.escort_ratio,
      comp.specialist_ratio
    ], tolerance = 0.01, context = &"fleet_composition_{name}")

  # Validate strategic thresholds are ratios
  validateRatio(config.strategic.attack_threshold, "strategic.attack_threshold")
  validateRatio(config.strategic.aggressive_attack_threshold, "strategic.aggressive_attack_threshold")
  validateRatio(config.strategic.retreat_threshold, "strategic.retreat_threshold")

  # Validate threat assessment thresholds are ratios
  validateRatio(config.threat_assessment.critical_threshold, "threat_assessment.critical_threshold")
  validateRatio(config.threat_assessment.high_threshold, "threat_assessment.high_threshold")
  validateRatio(config.threat_assessment.moderate_threshold, "threat_assessment.moderate_threshold")
  validateRatio(config.threat_assessment.low_threshold, "threat_assessment.low_threshold")

  # Validate tactical parameters are positive
  validatePositive(config.tactical.response_radius_jumps, "tactical.response_radius_jumps")
  validatePositive(config.tactical.max_invasion_eta_turns, "tactical.max_invasion_eta_turns")
  validatePositive(config.tactical.max_response_eta_turns, "tactical.max_response_eta_turns")

  # Validate Domestikos Admiral config
  validatePositive(config.domestikos.max_invasion_eta_turns, "domestikos.max_invasion_eta_turns")

  # Validate orders parameters are ratios
  validateRatio(config.orders.research_max_percent, "orders.research_max_percent")
  validateRatio(config.orders.espionage_investment_percent, "orders.espionage_investment_percent")

  # Validate orders scout counts are positive
  validatePositive(config.orders.scout_count_act1, "orders.scout_count_act1")
  validatePositive(config.orders.scout_count_act2, "orders.scout_count_act2")
  validatePositive(config.orders.scout_count_act3_plus, "orders.scout_count_act3_plus")

  # Validate logistics parameters
  validatePositive(config.logistics.mothballing_treasury_threshold_pp, "logistics.mothballing_treasury_threshold_pp")
  validateRatio(config.logistics.mothballing_maintenance_ratio_threshold, "logistics.mothballing_maintenance_ratio_threshold")
  validatePositive(config.logistics.mothballing_min_fleet_count, "logistics.mothballing_min_fleet_count")

  # Validate economic parameters are positive
  validatePositive(config.economic.terraforming_costs_extreme_to_desolate, "economic.terraforming_costs_extreme_to_desolate")
  validatePositive(config.economic.terraforming_costs_desolate_to_hostile, "economic.terraforming_costs_desolate_to_hostile")
  validatePositive(config.economic.terraforming_costs_hostile_to_harsh, "economic.terraforming_costs_hostile_to_harsh")
  validatePositive(config.economic.terraforming_costs_harsh_to_benign, "economic.terraforming_costs_harsh_to_benign")
  validatePositive(config.economic.terraforming_costs_benign_to_lush, "economic.terraforming_costs_benign_to_lush")
  validatePositive(config.economic.terraforming_costs_lush_to_eden, "economic.terraforming_costs_lush_to_eden")

# Validate GOAP parameters
validatePositive(config.goap.planning_depth, "goap.planning_depth")
validateRatio(config.goap.confidence_threshold, "goap.confidence_threshold")
validatePositive(config.goap.max_concurrent_plans, "goap.max_concurrent_plans")
validateRatio(config.goap.defense_priority, "goap.defense_priority")
validateRatio(config.goap.offense_priority, "goap.offense_priority")
validateRatio(config.goap.budget_guidance_boost_factor, "goap.budget_guidance_boost_factor")
validatePositive(config.goap.replan_stalled_turns, "goap.replan_stalled_turns")
validateRatio(config.goap.replan_budget_shortfall_ratio, "goap.replan_budget_shortfall_ratio")
validateNonNegative(config.goap.new_opportunity_scan_frequency, "goap.new_opportunity_scan_frequency") # Can be 0 for every turn

# Validate GOAP parameters
validatePositive(config.goap.planning_depth, "goap.planning_depth")
validateRatio(config.goap.confidence_threshold, "goap.confidence_threshold")
validatePositive(config.goap.max_concurrent_plans, "goap.max_concurrent_plans")
validateRatio(config.goap.defense_priority, "goap.defense_priority")
validateRatio(config.goap.offense_priority, "goap.offense_priority")
validateRatio(config.goap.budget_guidance_boost_factor, "goap.budget_guidance_boost_factor")
validatePositive(config.goap.replan_stalled_turns, "goap.replan_stalled_turns")
validateRatio(config.goap.replan_budget_shortfall_ratio, "goap.replan_budget_shortfall_ratio")
validateNonNegative(config.goap.new_opportunity_scan_frequency, "goap.new_opportunity_scan_frequency") # Can be 0 for every turn

# Validate GOAP parameters
validatePositive(config.goap.planning_depth, "goap.planning_depth")
validateRatio(config.goap.confidence_threshold, "goap.confidence_threshold")
validatePositive(config.goap.max_concurrent_plans, "goap.max_concurrent_plans")
validateRatio(config.goap.defense_priority, "goap.defense_priority")
validateRatio(config.goap.offense_priority, "goap.offense_priority")
validateRatio(config.goap.budget_guidance_boost_factor, "goap.budget_guidance_boost_factor")
validatePositive(config.goap.replan_stalled_turns, "goap.replan_stalled_turns")
validateRatio(config.goap.replan_budget_shortfall_ratio, "goap.replan_budget_shortfall_ratio")
validatePositive(config.goap.new_opportunity_scan_frequency, "goap.new_opportunity_scan_frequency")

# ==============================================================================
# Config Loading
# ==============================================================================

proc loadRBAConfig*(configPath: string = "config/rba.toml"): RBAConfig =
  ## Load RBA configuration from TOML file
  ## Uses toml_serialization for type-safe parsing
  ##
  ## Follows engine config pattern (see src/engine/config/economy_config.nim)

  if not fileExists(configPath):
    raise newException(IOError, "RBA config not found: " & configPath)

  let configContent = readFile(configPath)
  result = Toml.decode(configContent, RBAConfig)

  # Validate configuration after loading
  validateRBAConfig(result)

  logInfo(LogCategory.lcAI, &"Loaded RBA configuration from {configPath}")

## Global configuration instance
## Loaded once at module initialization
var globalRBAConfig* = loadRBAConfig()

## Helper to reload configuration (for testing and genetic algorithm)
proc reloadRBAConfig*() =
  ## Reload configuration from file
  ## Useful for:
  ## - Balance testing with different configs
  ## - Genetic algorithm parameter evolution
  ## - Iterative tuning during development
  globalRBAConfig = loadRBAConfig()
  logInfo(LogCategory.lcAI, "Reloaded RBA configuration")

proc reloadRBAConfigFromPath*(configPath: string) =
  ## Reload configuration from custom path
  ## Useful for:
  ## - Testing evolved configs from genetic algorithm
  ## - A/B testing different parameter sets
  globalRBAConfig = loadRBAConfig(configPath)
  logInfo(LogCategory.lcAI, &"Reloaded RBA configuration from {configPath}")
