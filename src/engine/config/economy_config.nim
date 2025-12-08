## Economy Configuration Loader
##
## Loads economy mechanics from config/economy.toml using toml_serialization
## Allows runtime configuration for population, production, research, taxation, colonization

import std/[os]
import toml_serialization
import ../../common/logger

type
  PopulationConfig* = object
    natural_growth_rate*: float
    growth_rate_per_starbase*: float
    max_starbase_bonus*: float
    ptu_growth_rate*: float
    ptu_to_souls*: int
    pu_to_ptu_conversion*: float

  ProductionConfig* = object
    production_per_10_population*: int
    production_split_credits*: float
    production_split_production*: float
    production_split_research*: float

  InfrastructureConfig* = object
    # TODO: Add infrastructure modifiers when defined

  PlanetClassesConfig* = object
    extreme_pu_min*: int
    extreme_pu_max*: int
    desolate_pu_min*: int
    desolate_pu_max*: int
    hostile_pu_min*: int
    hostile_pu_max*: int
    harsh_pu_min*: int
    harsh_pu_max*: int
    benign_pu_min*: int
    benign_pu_max*: int
    lush_pu_min*: int
    lush_pu_max*: int
    eden_pu_min*: int

  ResearchConfig* = object
    research_cost_base*: int
    research_cost_exponent*: int
    research_breakthrough_base_chance*: float
    research_breakthrough_rp_per_percent*: int
    minor_breakthrough_bonus*: int
    moderate_breakthrough_discount*: float
    revolutionary_quantum_computing_el_mod_bonus*: float
    revolutionary_stealth_detection_bonus*: int
    revolutionary_terraforming_growth_bonus*: float
    erp_base_cost*: int
    el_early_base*: int
    el_early_increment*: int
    el_late_increment*: int
    srp_base_cost*: int
    srp_sl_multiplier*: float
    sl_early_base*: int
    sl_early_increment*: int
    sl_late_increment*: int
    trp_first_level_cost*: int
    trp_level_increment*: int

  EspionageConfig* = object
    ebp_cost_per_point*: int
    cip_cost_per_point*: int
    max_actions_per_turn*: int
    budget_threshold_percent*: int
    prestige_loss_per_percent_over*: int
    tech_theft_cost*: int
    sabotage_low_cost*: int
    sabotage_high_cost*: int
    assassination_cost*: int
    cyber_attack_cost*: int
    economic_manipulation_cost*: int
    psyops_campaign_cost*: int
    detection_roll_cost*: int

  RawMaterialEfficiencyConfig* = object
    very_poor_eden*: float
    very_poor_lush*: float
    very_poor_benign*: float
    very_poor_harsh*: float
    very_poor_hostile*: float
    very_poor_desolate*: float
    very_poor_extreme*: float
    poor_eden*: float
    poor_lush*: float
    poor_benign*: float
    poor_harsh*: float
    poor_hostile*: float
    poor_desolate*: float
    poor_extreme*: float
    abundant_eden*: float
    abundant_lush*: float
    abundant_benign*: float
    abundant_harsh*: float
    abundant_hostile*: float
    abundant_desolate*: float
    abundant_extreme*: float
    rich_eden*: float
    rich_lush*: float
    rich_benign*: float
    rich_harsh*: float
    rich_hostile*: float
    rich_desolate*: float
    rich_extreme*: float
    very_rich_eden*: float
    very_rich_lush*: float
    very_rich_benign*: float
    very_rich_harsh*: float
    very_rich_hostile*: float
    very_rich_desolate*: float
    very_rich_extreme*: float

  TaxMechanicsConfig* = object
    tax_averaging_window_turns*: int

  TaxPopulationGrowthConfig* = object
    tier_1_min*: int
    tier_1_max*: int
    tier_1_pop_multiplier*: float
    tier_2_min*: int
    tier_2_max*: int
    tier_2_pop_multiplier*: float
    tier_3_min*: int
    tier_3_max*: int
    tier_3_pop_multiplier*: float
    tier_4_min*: int
    tier_4_max*: int
    tier_4_pop_multiplier*: float
    tier_5_min*: int
    tier_5_max*: int
    tier_5_pop_multiplier*: float

  IndustrialInvestmentConfig* = object
    base_cost*: int
    tier_1_max_percent*: int
    tier_1_multiplier*: float
    tier_1_pp*: int
    tier_2_min_percent*: int
    tier_2_max_percent*: int
    tier_2_multiplier*: float
    tier_2_pp*: int
    tier_3_min_percent*: int
    tier_3_max_percent*: int
    tier_3_multiplier*: float
    tier_3_pp*: int
    tier_4_min_percent*: int
    tier_4_max_percent*: int
    tier_4_multiplier*: float
    tier_4_pp*: int
    tier_5_min_percent*: int
    tier_5_multiplier*: float
    tier_5_pp*: int

  ColonizationConfig* = object
    eden_pp_per_ptu*: int
    lush_pp_per_ptu*: int
    benign_pp_per_ptu*: int
    harsh_pp_per_ptu*: int
    hostile_pp_per_ptu*: int
    desolate_pp_per_ptu*: int
    extreme_pp_per_ptu*: int

  EconomyConfig* = object
    ## Complete economy configuration loaded from TOML
    population*: PopulationConfig
    production*: ProductionConfig
    infrastructure*: InfrastructureConfig
    planet_classes*: PlanetClassesConfig
    research*: ResearchConfig
    espionage*: EspionageConfig
    raw_material_efficiency*: RawMaterialEfficiencyConfig
    tax_mechanics*: TaxMechanicsConfig
    tax_population_growth*: TaxPopulationGrowthConfig
    industrial_investment*: IndustrialInvestmentConfig
    colonization*: ColonizationConfig

proc loadEconomyConfig*(configPath: string = "config/economy.toml"): EconomyConfig =
  ## Load economy configuration from TOML file
  ## Uses toml_serialization for type-safe parsing

  if not fileExists(configPath):
    raise newException(IOError, "Economy config not found: " & configPath)

  let configContent = readFile(configPath)
  result = Toml.decode(configContent, EconomyConfig)

  logInfo("Config", "Loaded economy configuration", "path=", configPath)

## Global configuration instance

var globalEconomyConfig* = loadEconomyConfig()

## Helper to reload configuration (for testing)

proc reloadEconomyConfig*() =
  ## Reload configuration from file
  globalEconomyConfig = loadEconomyConfig()
