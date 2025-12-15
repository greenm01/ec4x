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
    min_population_for_reload*: int

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

  EparchMaintenanceConfig* = object
    ## Maintenance shortfall penalty avoidance
    penalty_turns_critical*: int

  EparchFacilitiesConfig* = object
    ## Facility threat penalties and target ratios by Act
    # Threat penalty multipliers (0.0-1.0)
    threat_penalty_critical_shipyard*: float
    threat_penalty_high_shipyard*: float
    threat_penalty_moderate_shipyard*: float
    threat_penalty_critical_spaceport*: float
    threat_penalty_high_spaceport*: float
    threat_penalty_moderate_spaceport*: float
    threat_penalty_critical_starbase*: float
    threat_penalty_high_starbase*: float
    threat_penalty_moderate_starbase*: float
    staleness_penalty_facility*: float
    staleness_penalty_starbase*: float
    # Facility ratios by Act (multipliers)
    shipyard_ratio_act1*: float
    shipyard_ratio_act2*: float
    shipyard_ratio_act3*: float
    shipyard_ratio_act4*: float
    starbase_ratio_act1*: float
    starbase_ratio_act2*: float
    starbase_ratio_act3*: float
    starbase_ratio_act4*: float

  EparchTerraformingConfig* = object
    ## Terraforming priority calculation parameters
    priority_base*: float
    priority_cost_divisor*: float
    priority_critical_threshold*: float

  EparchEconomicPressureConfig* = object
    ## Competitive economic assessment thresholds
    production_ratio_moderate*: float
    production_ratio_severe*: float
    shipyard_advantage_threshold*: int
    boost_moderate_pressure*: float
    boost_severe_pressure*: float
    boost_shipyard_disadvantage*: float

  EparchReprioritizationConfig* = object
    ## Eparch-specific reprioritization parameters
    max_iterations*: int
    expensive_requirement_ratio*: float

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
# Act Transitions
# ==============================================================================

type
  ActTransitionsConfig* = object
    ## Game Act transition thresholds
    act1_colonization_threshold*: float  # Act 1 ends when ≥X% colonized
    act2_colonization_threshold*: float  # Act 2 → Act 3 when ≥X% colonized
    act2_max_turn*: int                  # Act 2 ends at turn X
    act3_max_turn*: int                  # Act 3 ends at turn X

# ==============================================================================
# Act-Specific Advisor Priorities
# ==============================================================================

type
  ActPrioritiesConfig* = object
    ## Advisor priority multipliers for a single game Act
    ## Applied during Basileus mediation to reflect strategic focus
    ## Based on docs/ai/architecture/ai_architecture.adoc lines 301-407
    eparch_multiplier*: float
    domestikos_multiplier*: float
    drungarius_multiplier*: float
    logothete_multiplier*: float
    protostrator_multiplier*: float

# ==============================================================================
# Colonization Parameters
# ==============================================================================

type
  RBAColonizationConfig* = object
    ## Proximity-weighted colonization targeting configuration
    proximity_max_distance*: int
    proximity_bonus_per_jump*: float
    proximity_weight_act1*: float
    proximity_weight_act4*: float

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
# Domestikos Configuration
# ==============================================================================

type
  DomestikosOffensiveConfig* = object
    ## Offensive operations parameters
    priority_base*: int
    priority_high*: int
    priority_medium*: int
    priority_low*: int
    priority_deferred*: int
    distance_bonus_1_2_jumps*: float
    distance_bonus_3_4_jumps*: float
    distance_bonus_5_6_jumps*: float
    weakness_threshold_vulnerable*: float
    weakness_threshold_weak*: float
    weakness_priority_boost*: float
    fleet_strength_multiplier*: float
    estimated_value_multiplier*: float
    vulnerability_multiplier*: float
    ground_defense_divisor*: int
    max_intel_age_turns*: int
    conservative_ship_estimate*: int
    roe_blitz_priority*: int
    roe_bombardment_priority*: int

  DomestikosDefensiveConfig* = object
    ## Defensive operations parameters
    production_weight*: float
    threat_boost_critical*: float
    threat_boost_high*: float
    threat_boost_moderate*: float
    proximity_multiplier_1_jump*: float
    proximity_multiplier_2_jumps*: float
    movement_boost_base*: float
    stale_intel_penalty*: float
    frontier_bonus_per_distance*: float
    owned_system_priority_boost*: float
    defend_max_range*: int

  DomestikosIntelligenceOpsConfig* = object
    ## Intelligence operations scoring
    threat_contribution_per_fleet*: float
    threat_level_high_score*: float
    threat_level_moderate_score*: float
    threat_level_low_score*: float

  DomestikosStagingConfig* = object
    ## Staging location priority scoring
    priority_acceptable_close*: float
    priority_acceptable_far*: float
    priority_owned_system*: float

  ShipClassScores* = object
    ## Unit priority scores for all ship classes (0.0 - 4.0 points)
    ## Used by unit_priority.nim for Act-aware ship construction
    etac*: float
    destroyer*: float
    frigate*: float
    corvette*: float
    scout*: float
    light_cruiser*: float
    cruiser*: float
    raider*: float
    battlecruiser*: float
    heavy_cruiser*: float
    battleship*: float
    dreadnought*: float
    super_dreadnought*: float
    carrier*: float
    super_carrier*: float
    planet_breaker*: float
    troop_transport*: float
    fighter*: float

  UnitPrioritiesConfig* = object
    ## Act-aware unit priority scoring tables
    ## Based on src/ai/rba/domestikos/unit_priority.nim
    act1_land_grab*: ShipClassScores
    act2_rising_tensions*: ShipClassScores
    act3_total_war*: ShipClassScores
    act4_endgame*: ShipClassScores
    strategic_values*: ShipClassScores  # Act-independent strategic value (0.0-2.0)

  DomestikosConfig* = object
    ## Domestikos module parameters (fleet rebalancing)
    enabled*: bool
    split_threshold_act1*: int
    merge_threshold_act2*: int
    rendezvous_preference*: string
    max_invasion_eta_turns*: int # Max turns for a fleet to reach an invasion target

    # Affordability thresholds (how much of treasury per build request)
    affordability_act1*: float
    affordability_act2*: float
    affordability_act3*: float
    affordability_act4*: float

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

    # Phase 2: Invasion Campaign Management
    max_concurrent_campaigns*: int
    campaign_stall_timeout*: int
    campaign_bombardment_max*: int
    campaign_intel_freshness*: int

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

  DrungariusOperationsConfig* = object
    ## Espionage operations parameters (src/ai/rba/drungarius/operations.nim)
    # EBP thresholds for operations
    ebp_intelligence_theft*: int
    ebp_assassination*: int
    ebp_sabotage_high*: int
    ebp_plant_disinformation*: int
    ebp_economic_manipulation*: int
    ebp_cyber_attack*: int
    ebp_tech_theft*: int
    ebp_psyops_campaign*: int
    ebp_sabotage_low*: int
    # CIP thresholds
    cip_minimum_counter_intel*: int
    cip_activation_threshold*: int
    # Prestige thresholds
    prestige_gap_assassination*: int
    prestige_gap_sabotage_high*: int
    prestige_gap_intelligence_theft*: int
    prestige_gap_disinformation*: int
    prestige_high_target_threshold*: int
    prestige_safety_threshold*: int
    # Operation chances
    chance_intelligence_theft*: float
    chance_assassination*: float
    chance_sabotage_high*: float
    chance_plant_disinformation*: float
    chance_economic_manipulation*: float
    chance_psyops_campaign*: float
    # Target selection
    target_prestige_gap_multiplier*: float
    target_enemy_priority_boost*: float
    target_random_factor_max*: float
    # Espionage frequency
    frequency_espionage_focused*: float
    frequency_economic_focused*: float
    frequency_aggressive*: float
    frequency_balanced*: float
    # Personality thresholds
    frequency_risk_tolerance_threshold*: float
    frequency_economic_focus_threshold*: float
    frequency_aggression_threshold*: float
    frequency_economic_focus_cap*: float
    # Counter-intel periodic
    counter_intel_periodic_frequency*: int
    counter_intel_aggression_threshold*: float
    economic_focus_manipulation*: float

  DrungariusRequirementsConfig* = object
    ## Espionage requirements parameters (src/ai/rba/drungarius/requirements.nim)
    # Target scoring normalization
    tech_value_divisor*: float
    economic_value_divisor*: float
    military_threat_divisor*: float
    # CI weakness scores
    ci_weakness_unknown*: float
    ci_weakness_low*: float
    ci_weakness_moderate*: float
    ci_weakness_high*: float
    ci_weakness_critical*: float
    ci_weakness_default*: float
    # Diplomatic weights
    diplomatic_weight_enemy*: float
    diplomatic_weight_hostile*: float
    diplomatic_weight_neutral*: float
    # Score weights
    score_weight_tech*: float
    score_weight_economic*: float
    score_weight_military*: float
    score_weight_ci_weakness*: float
    score_weight_diplomatic*: float
    # Sabotage bottleneck scoring
    sabotage_shipyard_weight*: int
    sabotage_project_weight*: int
    sabotage_activity_very_high*: int
    sabotage_activity_high*: int
    sabotage_activity_moderate*: int
    sabotage_activity_low*: int
    sabotage_infrastructure_unit_value*: int
    sabotage_starbase_value*: int
    sabotage_shipyard_concentration*: int
    # Counter-intelligence assessment
    ci_detection_heavy_activity*: int
    ci_detection_moderate_activity*: int
    ci_total_threat_threshold*: int
    ci_emergency_cip_boost_max*: int
    ci_pp_per_point*: int
    ci_significant_activity*: int
    # EBP/CIP investment
    ebp_critical_threshold*: int
    ebp_high_gap_threshold*: int
    cip_high_gap_threshold*: int
    cip_high_priority_threshold*: int
    cip_risk_averse_threshold*: int
    # Act 3 bonuses
    act3_war_ebp_bonus*: int
    act3_war_cip_bonus*: int
    # Operation thresholds
    req_ebp_sabotage_bottleneck*: int
    req_ebp_secondary_sabotage*: int
    req_ebp_operations_vs_enemies*: int
    req_ebp_disinformation*: int
    req_ebp_economic_manipulation*: int
    req_ebp_cyber_attack*: int
    req_ebp_assassination*: int
    # Cost estimates
    cost_sabotage*: int
    cost_intelligence_theft*: int
    cost_disinformation*: int
    cost_economic_manipulation*: int
    cost_cyber_attack*: int
    cost_assassination*: int
    cost_counter_intel_sweep*: int
    # Personality thresholds
    aggression_secondary_sabotage*: float
    aggression_disinformation*: float
    aggression_assassination*: float
    risk_tolerance_ci_maintenance*: float
    # Prestige awareness
    prestige_penalty_threshold_ratio*: float

  DrungariusConfig* = object
    ## Intelligence coordinator settings
    intel_processing_enabled*: bool
    use_combat_lessons*: bool
    use_starbase_surveillance*: bool
    prioritize_high_value_targets*: bool
    # Espionage budget allocation by Act
    espionage_budget_act1*: int
    espionage_budget_act2*: int
    espionage_budget_act3*: int
    espionage_budget_act4*: int
    # Research budget allocation by Act
    research_budget_act1*: int
    research_budget_act2*: int
    research_budget_act3*: int
    research_budget_act4*: int

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

    # Phase 3: Invasion Planning Parameters
    invasion_min_strength_ratio*: float # Need X times estimated enemy strength
    invasion_max_distance*: int         # Max jumps to invasion target
    invasion_bombardment_estimate*: int # Estimated bombardment turns
    invasion_priority_boost*: float     # Priority boost for invasion goals

    # Phase 3: Campaign Coordination
    disable_rba_campaigns_with_goap*: bool # Disable Phase 2 RBA campaigns when GOAP handles invasions


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

  BasileusConfig* = object
    ## Basileus (decision mediator) personality-driven weight adjustments
    # Personality influence multipliers
    personality_domestikos_multiplier*: float
    personality_logothete_multiplier*: float
    personality_drungarius_multiplier*: float
    personality_protostrator_multiplier*: float
    personality_eparch_multiplier*: float
    # Act-specific adjustments
    act1_research_multiplier*: float
    act2_war_research_multiplier*: float
    act2_hostile_research_multiplier*: float
    act3_war_military_multiplier*: float
    act4_war_military_multiplier*: float
    act3_war_research_multiplier*: float
    act4_war_research_multiplier*: float
    act3_war_diplomacy_multiplier*: float
    act3_peace_diplomacy_multiplier*: float
    act4_peace_research_multiplier*: float
    act3_peace_research_multiplier*: float

# ==============================================================================
# Protostrator Configuration (Strategic & Diplomatic Advisor)
# ==============================================================================

type
  ProtostratorPactAssessmentConfig* = object
    ## Pact recommendation scoring
    shared_enemies_weight*: float
    mutual_enemies_weight*: float
    diplomacy_trait_weight*: float
    trust_weight*: float
    recommendation_threshold*: float

  ProtostratorStanceConfig* = object
    ## Stance change recommendation thresholds
    hostile_threshold*: float
    enemy_threshold*: float
    escalate_threshold*: float
    deescalate_threshold*: float
    normalize_threshold*: float
    aggression_hostile_weight*: float
    aggression_enemy_weight*: float
    opportunity_hostile_weight*: float
    opportunity_enemy_weight*: float
    diplomacy_deescalate_weight*: float
    diplomacy_normalize_weight*: float
    peace_bias_weight*: float

  ProtostratorConfig* = object
    ## Protostrator (strategic/diplomatic advisor) parameters
    infrastructure_value_per_point*: int
    combat_freshness_turns*: int
    opportunity_score_recent_combat*: float
    opportunity_score_at_war*: float
    opportunity_score_tensions*: float
    opportunity_score_multiple_fronts*: float
    baseline_risk*: float
    urgency_critical_threats*: int
    urgency_economic_pressure*: int
    urgency_diplomatic_isolation*: int
    urgency_border_tension*: int
    urgency_prestige_threat*: int
    threshold_multiplier_act1*: float
    threshold_multiplier_act2*: float
    threshold_multiplier_act3*: float
    threshold_multiplier_act4*: float
    mutual_enemies_base_score*: float

# ==============================================================================
# Logothete Configuration (Research & Technology Advisor)
# ==============================================================================

type
  TechFieldAllocation* = object
    ## Tech field allocation percentages (0.0-1.0) for a strategy
    ## Values should sum to ~1.0 across all fields
    weapons_tech*: float
    construction_tech*: float
    cloaking_tech*: float
    electronic_intelligence*: float
    terraforming_tech*: float
    shield_tech*: float
    counter_intelligence*: float
    fighter_doctrine*: float
    advanced_carrier_ops*: float

  LogotheteTechAllocationsThresholds* = object
    ## Personality-driven tech field allocation strategy thresholds
    tech_priority_threshold*: float
    economic_focus_threshold*: float
    aggression_threshold*: float
    aggression_peaceful*: float

  LogotheteAllocationConfig* = object
    ## Research budget allocation ratios
    act1_economic_ratio*: float
    act1_science_ratio*: float
    act1_remainder_split*: bool
    act3_economic_ratio*: float
    act3_science_ratio*: float
    war_economic_ratio*: float
    war_science_ratio*: float
    default_economic_ratio*: float
    default_science_ratio*: float

  LogotheteCounterTechConfig* = object
    ## Counter-technology parameters
    enemy_advantage_critical*: int
    enemy_advantage_high*: int

  LogotheteConfig* = object
    ## Logothete (research/tech advisor) parameters
    max_science_level*: int
    cost_urgent_tech*: int
    cost_counter_tech*: int
    cost_field_research*: int

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
    # Act transitions
    act_transitions*: ActTransitionsConfig
    # Act-specific advisor priorities
    act_priorities_act1_land_grab*: ActPrioritiesConfig
    act_priorities_act2_rising_tensions*: ActPrioritiesConfig
    act_priorities_act3_total_war*: ActPrioritiesConfig
    act_priorities_act4_endgame*: ActPrioritiesConfig
    # Colonization parameters
    colonization*: RBAColonizationConfig
    # Logistics parameters
    logistics*: LogisticsConfig
    # Fleet composition ratios (3 doctrines)
    fleet_composition_balanced*: FleetCompositionRatioConfig
    fleet_composition_aggressive*: FleetCompositionRatioConfig
    fleet_composition_defensive*: FleetCompositionRatioConfig
    # Threat assessment
    threat_assessment*: ThreatAssessmentConfig
    # Domestikos module (fleet rebalancing)
    domestikos*: DomestikosConfig
    # Domestikos sub-configurations (flattened for toml_serialization)
    domestikos_offensive*: DomestikosOffensiveConfig
    domestikos_defensive*: DomestikosDefensiveConfig
    domestikos_intelligence_ops*: DomestikosIntelligenceOpsConfig
    domestikos_staging*: DomestikosStagingConfig
    # Unit priorities (fully flattened - toml_serialization doesn't support any nesting)
    domestikos_unit_priorities_act1_land_grab*: ShipClassScores
    domestikos_unit_priorities_act2_rising_tensions*: ShipClassScores
    domestikos_unit_priorities_act3_total_war*: ShipClassScores
    domestikos_unit_priorities_act4_endgame*: ShipClassScores
    domestikos_unit_priorities_strategic_values*: ShipClassScores
    # Eparch module (economic administration)
    eparch*: EparchConfig
    eparch_maintenance*: EparchMaintenanceConfig
    eparch_facilities*: EparchFacilitiesConfig
    eparch_terraforming*: EparchTerraformingConfig
    eparch_economic_pressure*: EparchEconomicPressureConfig
    eparch_reprioritization*: EparchReprioritizationConfig
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
    drungarius_operations*: DrungariusOperationsConfig
    drungarius_requirements*: DrungariusRequirementsConfig
    # Gap Fix modules (Phase 1-2)
    feedback_system*: FeedbackSystemConfig
    reprioritization*: ReprioritizationConfig
    standing_orders_integration*: StandingOrdersIntegrationConfig
    # Eparch industrial investment (refactoring Phase 4)
    eparch_industrial*: EparchIndustrialConfig
    treasury_thresholds*: TreasuryThresholdsConfig
    affordability_checks*: AffordabilityChecksConfig
    basileus*: BasileusConfig
    protostrator*: ProtostratorConfig
    protostrator_pact_assessment*: ProtostratorPactAssessmentConfig
    protostrator_stance_recommendations*: ProtostratorStanceConfig
    logothete*: LogotheteConfig
    logothete_allocation*: LogotheteAllocationConfig
    logothete_counter_tech*: LogotheteCounterTechConfig
    logothete_tech_allocations_thresholds*: LogotheteTechAllocationsThresholds
    logothete_tech_allocations_tech_priority_aggressive*: TechFieldAllocation
    logothete_tech_allocations_tech_priority_peaceful*: TechFieldAllocation
    logothete_tech_allocations_economic_focus*: TechFieldAllocation
    logothete_tech_allocations_war_economy*: TechFieldAllocation
    logothete_tech_allocations_balanced_default*: TechFieldAllocation
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
  validatePositive(config.tactical.min_population_for_reload, "tactical.min_population_for_reload")

  # Validate Domestikos config
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

  # Validate Eparch configuration
  validatePositive(config.eparch.auto_repair_threshold, "eparch.auto_repair_threshold")
  validatePositive(config.eparch_maintenance.penalty_turns_critical, "eparch_maintenance.penalty_turns_critical")

  # Validate facility threat penalties are ratios
  validateRatio(config.eparch_facilities.threat_penalty_critical_shipyard, "eparch_facilities.threat_penalty_critical_shipyard")
  validateRatio(config.eparch_facilities.threat_penalty_high_shipyard, "eparch_facilities.threat_penalty_high_shipyard")
  validateRatio(config.eparch_facilities.threat_penalty_moderate_shipyard, "eparch_facilities.threat_penalty_moderate_shipyard")
  validateRatio(config.eparch_facilities.threat_penalty_critical_spaceport, "eparch_facilities.threat_penalty_critical_spaceport")
  validateRatio(config.eparch_facilities.threat_penalty_high_spaceport, "eparch_facilities.threat_penalty_high_spaceport")
  validateRatio(config.eparch_facilities.threat_penalty_moderate_spaceport, "eparch_facilities.threat_penalty_moderate_spaceport")
  validateRatio(config.eparch_facilities.threat_penalty_critical_starbase, "eparch_facilities.threat_penalty_critical_starbase")
  validateRatio(config.eparch_facilities.threat_penalty_high_starbase, "eparch_facilities.threat_penalty_high_starbase")
  validateRatio(config.eparch_facilities.threat_penalty_moderate_starbase, "eparch_facilities.threat_penalty_moderate_starbase")
  validateRatio(config.eparch_facilities.staleness_penalty_facility, "eparch_facilities.staleness_penalty_facility")
  validateRatio(config.eparch_facilities.staleness_penalty_starbase, "eparch_facilities.staleness_penalty_starbase")

  # Validate facility ratios are non-negative
  validateNonNegative(config.eparch_facilities.shipyard_ratio_act1, "eparch_facilities.shipyard_ratio_act1")
  validateNonNegative(config.eparch_facilities.shipyard_ratio_act2, "eparch_facilities.shipyard_ratio_act2")
  validateNonNegative(config.eparch_facilities.shipyard_ratio_act3, "eparch_facilities.shipyard_ratio_act3")
  validateNonNegative(config.eparch_facilities.shipyard_ratio_act4, "eparch_facilities.shipyard_ratio_act4")
  validateNonNegative(config.eparch_facilities.starbase_ratio_act1, "eparch_facilities.starbase_ratio_act1")
  validateNonNegative(config.eparch_facilities.starbase_ratio_act2, "eparch_facilities.starbase_ratio_act2")
  validateNonNegative(config.eparch_facilities.starbase_ratio_act3, "eparch_facilities.starbase_ratio_act3")
  validateNonNegative(config.eparch_facilities.starbase_ratio_act4, "eparch_facilities.starbase_ratio_act4")

  # Validate terraforming parameters
  validateRatio(config.eparch_terraforming.priority_base, "eparch_terraforming.priority_base")
  validatePositive(config.eparch_terraforming.priority_cost_divisor, "eparch_terraforming.priority_cost_divisor")
  validateRatio(config.eparch_terraforming.priority_critical_threshold, "eparch_terraforming.priority_critical_threshold")

  # Validate economic pressure parameters
  validateRatio(config.eparch_economic_pressure.production_ratio_moderate, "eparch_economic_pressure.production_ratio_moderate")
  validateRatio(config.eparch_economic_pressure.production_ratio_severe, "eparch_economic_pressure.production_ratio_severe")
  validatePositive(config.eparch_economic_pressure.shipyard_advantage_threshold, "eparch_economic_pressure.shipyard_advantage_threshold")
  validateNonNegative(config.eparch_economic_pressure.boost_moderate_pressure, "eparch_economic_pressure.boost_moderate_pressure")
  validateNonNegative(config.eparch_economic_pressure.boost_severe_pressure, "eparch_economic_pressure.boost_severe_pressure")
  validateNonNegative(config.eparch_economic_pressure.boost_shipyard_disadvantage, "eparch_economic_pressure.boost_shipyard_disadvantage")

  # Validate reprioritization parameters
  validatePositive(config.eparch_reprioritization.max_iterations, "eparch_reprioritization.max_iterations")
  validateRatio(config.eparch_reprioritization.expensive_requirement_ratio, "eparch_reprioritization.expensive_requirement_ratio")

  # Validate Domestikos affordability thresholds
  validateRatio(config.domestikos.affordability_act1, "domestikos.affordability_act1")
  validateRatio(config.domestikos.affordability_act2, "domestikos.affordability_act2")
  validateRatio(config.domestikos.affordability_act3, "domestikos.affordability_act3")
  validateRatio(config.domestikos.affordability_act4, "domestikos.affordability_act4")

  # Validate Drungarius budget allocations
  validatePositive(config.drungarius.espionage_budget_act1, "drungarius.espionage_budget_act1")
  validatePositive(config.drungarius.espionage_budget_act2, "drungarius.espionage_budget_act2")
  validatePositive(config.drungarius.espionage_budget_act3, "drungarius.espionage_budget_act3")
  validatePositive(config.drungarius.espionage_budget_act4, "drungarius.espionage_budget_act4")
  validatePositive(config.drungarius.research_budget_act1, "drungarius.research_budget_act1")
  validatePositive(config.drungarius.research_budget_act2, "drungarius.research_budget_act2")
  validatePositive(config.drungarius.research_budget_act3, "drungarius.research_budget_act3")
  validatePositive(config.drungarius.research_budget_act4, "drungarius.research_budget_act4")

  # Validate Drungarius operations config
  let ops = config.drungarius_operations
  validateNonNegative(ops.ebp_intelligence_theft, "drungarius_operations.ebp_intelligence_theft")
  validateNonNegative(ops.ebp_assassination, "drungarius_operations.ebp_assassination")
  validateNonNegative(ops.ebp_sabotage_high, "drungarius_operations.ebp_sabotage_high")
  validateNonNegative(ops.ebp_plant_disinformation, "drungarius_operations.ebp_plant_disinformation")
  validateNonNegative(ops.ebp_economic_manipulation, "drungarius_operations.ebp_economic_manipulation")
  validateNonNegative(ops.ebp_cyber_attack, "drungarius_operations.ebp_cyber_attack")
  validateNonNegative(ops.ebp_tech_theft, "drungarius_operations.ebp_tech_theft")
  validateNonNegative(ops.ebp_psyops_campaign, "drungarius_operations.ebp_psyops_campaign")
  validateNonNegative(ops.ebp_sabotage_low, "drungarius_operations.ebp_sabotage_low")
  validateNonNegative(ops.cip_minimum_counter_intel, "drungarius_operations.cip_minimum_counter_intel")
  validateNonNegative(ops.cip_activation_threshold, "drungarius_operations.cip_activation_threshold")
  validateNonNegative(ops.prestige_gap_assassination, "drungarius_operations.prestige_gap_assassination")
  validateNonNegative(ops.prestige_gap_sabotage_high, "drungarius_operations.prestige_gap_sabotage_high")
  validateNonNegative(ops.prestige_gap_intelligence_theft, "drungarius_operations.prestige_gap_intelligence_theft")
  validateNonNegative(ops.prestige_gap_disinformation, "drungarius_operations.prestige_gap_disinformation")
  validateNonNegative(ops.prestige_high_target_threshold, "drungarius_operations.prestige_high_target_threshold")
  validateNonNegative(ops.prestige_safety_threshold, "drungarius_operations.prestige_safety_threshold")
  validateRatio(ops.chance_intelligence_theft, "drungarius_operations.chance_intelligence_theft")
  validateRatio(ops.chance_assassination, "drungarius_operations.chance_assassination")
  validateRatio(ops.chance_sabotage_high, "drungarius_operations.chance_sabotage_high")
  validateRatio(ops.chance_plant_disinformation, "drungarius_operations.chance_plant_disinformation")
  validateRatio(ops.chance_economic_manipulation, "drungarius_operations.chance_economic_manipulation")
  validateRatio(ops.chance_psyops_campaign, "drungarius_operations.chance_psyops_campaign")
  validateNonNegative(ops.target_prestige_gap_multiplier, "drungarius_operations.target_prestige_gap_multiplier")
  validateNonNegative(ops.target_enemy_priority_boost, "drungarius_operations.target_enemy_priority_boost")
  validateNonNegative(ops.target_random_factor_max, "drungarius_operations.target_random_factor_max")
  validateRatio(ops.frequency_espionage_focused, "drungarius_operations.frequency_espionage_focused")
  validateRatio(ops.frequency_economic_focused, "drungarius_operations.frequency_economic_focused")
  validateRatio(ops.frequency_aggressive, "drungarius_operations.frequency_aggressive")
  validateRatio(ops.frequency_balanced, "drungarius_operations.frequency_balanced")
  validateRatio(ops.frequency_risk_tolerance_threshold, "drungarius_operations.frequency_risk_tolerance_threshold")
  validateRatio(ops.frequency_economic_focus_threshold, "drungarius_operations.frequency_economic_focus_threshold")
  validateRatio(ops.frequency_aggression_threshold, "drungarius_operations.frequency_aggression_threshold")
  validateRatio(ops.frequency_economic_focus_cap, "drungarius_operations.frequency_economic_focus_cap")
  validateRatio(ops.economic_focus_manipulation, "drungarius_operations.economic_focus_manipulation")
  validatePositive(ops.counter_intel_periodic_frequency, "drungarius_operations.counter_intel_periodic_frequency")
  validateRatio(ops.counter_intel_aggression_threshold, "drungarius_operations.counter_intel_aggression_threshold")

  # Validate Drungarius requirements config
  let req = config.drungarius_requirements
  validatePositive(req.tech_value_divisor, "drungarius_requirements.tech_value_divisor")
  validatePositive(req.economic_value_divisor, "drungarius_requirements.economic_value_divisor")
  validatePositive(req.military_threat_divisor, "drungarius_requirements.military_threat_divisor")
  validateNonNegative(req.ci_weakness_unknown, "drungarius_requirements.ci_weakness_unknown")
  validateNonNegative(req.ci_weakness_low, "drungarius_requirements.ci_weakness_low")
  validateNonNegative(req.ci_weakness_moderate, "drungarius_requirements.ci_weakness_moderate")
  validateNonNegative(req.ci_weakness_high, "drungarius_requirements.ci_weakness_high")
  validateNonNegative(req.ci_weakness_critical, "drungarius_requirements.ci_weakness_critical")
  validateNonNegative(req.ci_weakness_default, "drungarius_requirements.ci_weakness_default")
  validateNonNegative(req.diplomatic_weight_enemy, "drungarius_requirements.diplomatic_weight_enemy")
  validateNonNegative(req.diplomatic_weight_hostile, "drungarius_requirements.diplomatic_weight_hostile")
  validateNonNegative(req.diplomatic_weight_neutral, "drungarius_requirements.diplomatic_weight_neutral")
  validateNonNegative(req.score_weight_tech, "drungarius_requirements.score_weight_tech")
  validateNonNegative(req.score_weight_economic, "drungarius_requirements.score_weight_economic")
  validateNonNegative(req.score_weight_military, "drungarius_requirements.score_weight_military")
  validateNonNegative(req.score_weight_ci_weakness, "drungarius_requirements.score_weight_ci_weakness")
  validateNonNegative(req.score_weight_diplomatic, "drungarius_requirements.score_weight_diplomatic")
  validateNonNegative(req.sabotage_shipyard_weight, "drungarius_requirements.sabotage_shipyard_weight")
  validateNonNegative(req.sabotage_project_weight, "drungarius_requirements.sabotage_project_weight")
  validateNonNegative(req.sabotage_activity_very_high, "drungarius_requirements.sabotage_activity_very_high")
  validateNonNegative(req.sabotage_activity_high, "drungarius_requirements.sabotage_activity_high")
  validateNonNegative(req.sabotage_activity_moderate, "drungarius_requirements.sabotage_activity_moderate")
  validateNonNegative(req.sabotage_activity_low, "drungarius_requirements.sabotage_activity_low")
  validateNonNegative(req.sabotage_infrastructure_unit_value, "drungarius_requirements.sabotage_infrastructure_unit_value")
  validateNonNegative(req.sabotage_starbase_value, "drungarius_requirements.sabotage_starbase_value")
  validateNonNegative(req.sabotage_shipyard_concentration, "drungarius_requirements.sabotage_shipyard_concentration")
  validateNonNegative(req.ci_detection_heavy_activity, "drungarius_requirements.ci_detection_heavy_activity")
  validateNonNegative(req.ci_detection_moderate_activity, "drungarius_requirements.ci_detection_moderate_activity")
  validateNonNegative(req.ci_total_threat_threshold, "drungarius_requirements.ci_total_threat_threshold")
  validatePositive(req.ci_emergency_cip_boost_max, "drungarius_requirements.ci_emergency_cip_boost_max")
  validatePositive(req.ci_pp_per_point, "drungarius_requirements.ci_pp_per_point")
  validatePositive(req.ci_significant_activity, "drungarius_requirements.ci_significant_activity")
  validateNonNegative(req.ebp_critical_threshold, "drungarius_requirements.ebp_critical_threshold")
  validatePositive(req.ebp_high_gap_threshold, "drungarius_requirements.ebp_high_gap_threshold")
  validatePositive(req.cip_high_gap_threshold, "drungarius_requirements.cip_high_gap_threshold")
  validatePositive(req.cip_high_priority_threshold, "drungarius_requirements.cip_high_priority_threshold")
  validatePositive(req.cip_risk_averse_threshold, "drungarius_requirements.cip_risk_averse_threshold")
  validateNonNegative(req.act3_war_ebp_bonus, "drungarius_requirements.act3_war_ebp_bonus")
  validateNonNegative(req.act3_war_cip_bonus, "drungarius_requirements.act3_war_cip_bonus")
  validateNonNegative(req.req_ebp_sabotage_bottleneck, "drungarius_requirements.req_ebp_sabotage_bottleneck")
  validateNonNegative(req.req_ebp_secondary_sabotage, "drungarius_requirements.req_ebp_secondary_sabotage")
  validateNonNegative(req.req_ebp_operations_vs_enemies, "drungarius_requirements.req_ebp_operations_vs_enemies")
  validateNonNegative(req.req_ebp_disinformation, "drungarius_requirements.req_ebp_disinformation")
  validateNonNegative(req.req_ebp_economic_manipulation, "drungarius_requirements.req_ebp_economic_manipulation")
  validateNonNegative(req.req_ebp_cyber_attack, "drungarius_requirements.req_ebp_cyber_attack")
  validateNonNegative(req.req_ebp_assassination, "drungarius_requirements.req_ebp_assassination")
  validatePositive(req.cost_sabotage, "drungarius_requirements.cost_sabotage")
  validatePositive(req.cost_intelligence_theft, "drungarius_requirements.cost_intelligence_theft")
  validatePositive(req.cost_disinformation, "drungarius_requirements.cost_disinformation")
  validatePositive(req.cost_economic_manipulation, "drungarius_requirements.cost_economic_manipulation")
  validatePositive(req.cost_cyber_attack, "drungarius_requirements.cost_cyber_attack")
  validatePositive(req.cost_assassination, "drungarius_requirements.cost_assassination")
  validatePositive(req.cost_counter_intel_sweep, "drungarius_requirements.cost_counter_intel_sweep")
  validateRatio(req.aggression_secondary_sabotage, "drungarius_requirements.aggression_secondary_sabotage")
  validateRatio(req.aggression_disinformation, "drungarius_requirements.aggression_disinformation")
  validateRatio(req.aggression_assassination, "drungarius_requirements.aggression_assassination")
  validateRatio(req.risk_tolerance_ci_maintenance, "drungarius_requirements.risk_tolerance_ci_maintenance")
  validateRatio(req.prestige_penalty_threshold_ratio, "drungarius_requirements.prestige_penalty_threshold_ratio")

  # Validate Basileus personality multipliers
  validateNonNegative(config.basileus.personality_domestikos_multiplier, "basileus.personality_domestikos_multiplier")
  validateNonNegative(config.basileus.personality_logothete_multiplier, "basileus.personality_logothete_multiplier")
  validateNonNegative(config.basileus.personality_drungarius_multiplier, "basileus.personality_drungarius_multiplier")
  validateNonNegative(config.basileus.personality_protostrator_multiplier, "basileus.personality_protostrator_multiplier")
  validateNonNegative(config.basileus.personality_eparch_multiplier, "basileus.personality_eparch_multiplier")

  # Validate Basileus act-specific adjustments
  validateNonNegative(config.basileus.act1_research_multiplier, "basileus.act1_research_multiplier")
  validateNonNegative(config.basileus.act2_war_research_multiplier, "basileus.act2_war_research_multiplier")
  validateNonNegative(config.basileus.act2_hostile_research_multiplier, "basileus.act2_hostile_research_multiplier")
  validateNonNegative(config.basileus.act3_war_military_multiplier, "basileus.act3_war_military_multiplier")
  validateNonNegative(config.basileus.act4_war_military_multiplier, "basileus.act4_war_military_multiplier")
  validateNonNegative(config.basileus.act3_war_research_multiplier, "basileus.act3_war_research_multiplier")
  validateNonNegative(config.basileus.act4_war_research_multiplier, "basileus.act4_war_research_multiplier")
  validateNonNegative(config.basileus.act3_war_diplomacy_multiplier, "basileus.act3_war_diplomacy_multiplier")
  validateNonNegative(config.basileus.act3_peace_diplomacy_multiplier, "basileus.act3_peace_diplomacy_multiplier")
  validateNonNegative(config.basileus.act4_peace_research_multiplier, "basileus.act4_peace_research_multiplier")
  validateNonNegative(config.basileus.act3_peace_research_multiplier, "basileus.act3_peace_research_multiplier")

  # Validate Domestikos offensive operations
  validatePositive(config.domestikos_offensive.priority_base, "domestikos_offensive.priority_base")
  validateNonNegative(config.domestikos_offensive.distance_bonus_1_2_jumps, "domestikos_offensive.distance_bonus_1_2_jumps")
  validateRatio(config.domestikos_offensive.weakness_threshold_vulnerable, "domestikos_offensive.weakness_threshold_vulnerable")
  validatePositive(config.domestikos_offensive.max_intel_age_turns, "domestikos_offensive.max_intel_age_turns")

  # Validate Domestikos defensive operations
  validateNonNegative(config.domestikos_defensive.production_weight, "domestikos_defensive.production_weight")
  validateNonNegative(config.domestikos_defensive.threat_boost_critical, "domestikos_defensive.threat_boost_critical")
  validateRatio(config.domestikos_defensive.stale_intel_penalty, "domestikos_defensive.stale_intel_penalty")
  validatePositive(config.domestikos_defensive.defend_max_range, "domestikos_defensive.defend_max_range")

  # Validate Domestikos intelligence_ops
  validateNonNegative(config.domestikos_intelligence_ops.threat_contribution_per_fleet, "domestikos_intelligence_ops.threat_contribution_per_fleet")
  validateRatio(config.domestikos_intelligence_ops.threat_level_high_score, "domestikos_intelligence_ops.threat_level_high_score")

  # Validate Domestikos staging
  validateNonNegative(config.domestikos_staging.priority_acceptable_close, "domestikos_staging.priority_acceptable_close")

  # Validate Domestikos unit priorities (all ship class scores should be non-negative)
  proc validateShipClassScores(scores: ShipClassScores, prefix: string) =
    validateNonNegative(scores.etac, &"{prefix}.etac")
    validateNonNegative(scores.destroyer, &"{prefix}.destroyer")
    validateNonNegative(scores.frigate, &"{prefix}.frigate")
    validateNonNegative(scores.corvette, &"{prefix}.corvette")
    validateNonNegative(scores.scout, &"{prefix}.scout")
    validateNonNegative(scores.light_cruiser, &"{prefix}.light_cruiser")
    validateNonNegative(scores.cruiser, &"{prefix}.cruiser")
    validateNonNegative(scores.raider, &"{prefix}.raider")
    validateNonNegative(scores.battlecruiser, &"{prefix}.battlecruiser")
    validateNonNegative(scores.heavy_cruiser, &"{prefix}.heavy_cruiser")
    validateNonNegative(scores.battleship, &"{prefix}.battleship")
    validateNonNegative(scores.dreadnought, &"{prefix}.dreadnought")
    validateNonNegative(scores.super_dreadnought, &"{prefix}.super_dreadnought")
    validateNonNegative(scores.carrier, &"{prefix}.carrier")
    validateNonNegative(scores.super_carrier, &"{prefix}.super_carrier")
    validateNonNegative(scores.planet_breaker, &"{prefix}.planet_breaker")
    validateNonNegative(scores.troop_transport, &"{prefix}.troop_transport")
    validateNonNegative(scores.fighter, &"{prefix}.fighter")

  validateShipClassScores(config.domestikos_unit_priorities_act1_land_grab, "domestikos_unit_priorities_act1_land_grab")
  validateShipClassScores(config.domestikos_unit_priorities_act2_rising_tensions, "domestikos_unit_priorities_act2_rising_tensions")
  validateShipClassScores(config.domestikos_unit_priorities_act3_total_war, "domestikos_unit_priorities_act3_total_war")
  validateShipClassScores(config.domestikos_unit_priorities_act4_endgame, "domestikos_unit_priorities_act4_endgame")
  validateShipClassScores(config.domestikos_unit_priorities_strategic_values, "domestikos_unit_priorities_strategic_values")

  # Validate Protostrator
  validatePositive(config.protostrator.infrastructure_value_per_point, "protostrator.infrastructure_value_per_point")
  validatePositive(config.protostrator.combat_freshness_turns, "protostrator.combat_freshness_turns")
  validateRatio(config.protostrator.opportunity_score_recent_combat, "protostrator.opportunity_score_recent_combat")
  validateRatio(config.protostrator.baseline_risk, "protostrator.baseline_risk")
  validatePositive(config.protostrator.urgency_critical_threats, "protostrator.urgency_critical_threats")
  validateNonNegative(config.protostrator.threshold_multiplier_act1, "protostrator.threshold_multiplier_act1")
  validateRatio(config.protostrator_pact_assessment.recommendation_threshold, "protostrator_pact_assessment.recommendation_threshold")
  validateRatio(config.protostrator_stance_recommendations.hostile_threshold, "protostrator_stance_recommendations.hostile_threshold")

  # Validate Logothete
  validatePositive(config.logothete.max_science_level, "logothete.max_science_level")
  validatePositive(config.logothete.cost_urgent_tech, "logothete.cost_urgent_tech")
  validateRatio(config.logothete_allocation.act1_economic_ratio, "logothete_allocation.act1_economic_ratio")
  validateRatio(config.logothete_allocation.act1_science_ratio, "logothete_allocation.act1_science_ratio")
  validatePositive(config.logothete_counter_tech.enemy_advantage_critical, "logothete_counter_tech.enemy_advantage_critical")

  # Validate Logothete tech allocations
  proc validateTechFieldAllocation(alloc: TechFieldAllocation, prefix: string) =
    ## Validate tech field allocation percentages (0.0-1.0)
    validateRatio(alloc.weapons_tech, &"{prefix}.weapons_tech")
    validateRatio(alloc.construction_tech, &"{prefix}.construction_tech")
    validateRatio(alloc.cloaking_tech, &"{prefix}.cloaking_tech")
    validateRatio(alloc.electronic_intelligence, &"{prefix}.electronic_intelligence")
    validateRatio(alloc.terraforming_tech, &"{prefix}.terraforming_tech")
    validateRatio(alloc.shield_tech, &"{prefix}.shield_tech")
    validateRatio(alloc.counter_intelligence, &"{prefix}.counter_intelligence")
    validateRatio(alloc.fighter_doctrine, &"{prefix}.fighter_doctrine")
    validateRatio(alloc.advanced_carrier_ops, &"{prefix}.advanced_carrier_ops")

  let ta_thresholds = config.logothete_tech_allocations_thresholds
  validateRatio(ta_thresholds.tech_priority_threshold, "logothete_tech_allocations_thresholds.tech_priority_threshold")
  validateRatio(ta_thresholds.economic_focus_threshold, "logothete_tech_allocations_thresholds.economic_focus_threshold")
  validateRatio(ta_thresholds.aggression_threshold, "logothete_tech_allocations_thresholds.aggression_threshold")
  validateRatio(ta_thresholds.aggression_peaceful, "logothete_tech_allocations_thresholds.aggression_peaceful")
  validateTechFieldAllocation(config.logothete_tech_allocations_tech_priority_aggressive, "logothete_tech_allocations_tech_priority_aggressive")
  validateTechFieldAllocation(config.logothete_tech_allocations_tech_priority_peaceful, "logothete_tech_allocations_tech_priority_peaceful")
  validateTechFieldAllocation(config.logothete_tech_allocations_economic_focus, "logothete_tech_allocations_economic_focus")
  validateTechFieldAllocation(config.logothete_tech_allocations_war_economy, "logothete_tech_allocations_war_economy")
  validateTechFieldAllocation(config.logothete_tech_allocations_balanced_default, "logothete_tech_allocations_balanced_default")

  # Validate Act-Specific Advisor Priorities
  # All multipliers should be positive (0.6-1.5 typical range)
  let actPriorities = [
    ("act1_land_grab", config.act_priorities_act1_land_grab),
    ("act2_rising_tensions", config.act_priorities_act2_rising_tensions),
    ("act3_total_war", config.act_priorities_act3_total_war),
    ("act4_endgame", config.act_priorities_act4_endgame)
  ]

  for (actName, priorities) in actPriorities:
    let prefix = "act_priorities_" & actName
    validateNonNegative(priorities.eparch_multiplier, &"{prefix}.eparch_multiplier")
    validateNonNegative(priorities.domestikos_multiplier, &"{prefix}.domestikos_multiplier")
    validateNonNegative(priorities.drungarius_multiplier, &"{prefix}.drungarius_multiplier")
    validateNonNegative(priorities.logothete_multiplier, &"{prefix}.logothete_multiplier")
    validateNonNegative(priorities.protostrator_multiplier, &"{prefix}.protostrator_multiplier")

  # Validate GOAP parameters
  validatePositive(config.goap.planning_depth, "goap.planning_depth")
  validateRatio(config.goap.confidence_threshold, "goap.confidence_threshold")
  validatePositive(config.goap.max_concurrent_plans, "goap.max_concurrent_plans")
  validateRatio(config.goap.defense_priority, "goap.defense_priority")
  validateRatio(config.goap.offense_priority, "goap.offense_priority")
  validateRatio(config.goap.budget_guidance_boost_factor,
    "goap.budget_guidance_boost_factor")
  validatePositive(config.goap.replan_stalled_turns,
    "goap.replan_stalled_turns")
  validateRatio(config.goap.replan_budget_shortfall_ratio,
    "goap.replan_budget_shortfall_ratio")
  validateNonNegative(config.goap.new_opportunity_scan_frequency,
    "goap.new_opportunity_scan_frequency")

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
