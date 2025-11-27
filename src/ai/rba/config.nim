## RBA Configuration Loader
##
## Loads AI tuning parameters from config/rba.toml using toml_serialization
## Enables balance testing without recompilation
##
## Architecture:
## - Type-safe TOML deserialization
## - Global config instance for easy access
## - Follows engine config pattern (economy_config.nim)

import std/[os, tables]
import toml_serialization

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

  StrategyPersonalitiesConfig* = object
    ## All 12 strategy personalities
    aggressive*: StrategyPersonalityConfig
    economic*: StrategyPersonalityConfig
    espionage*: StrategyPersonalityConfig
    diplomatic*: StrategyPersonalityConfig
    balanced*: StrategyPersonalityConfig
    turtle*: StrategyPersonalityConfig
    expansionist*: StrategyPersonalityConfig
    tech_rush*: StrategyPersonalityConfig
    raider*: StrategyPersonalityConfig
    military_industrial*: StrategyPersonalityConfig
    opportunistic*: StrategyPersonalityConfig
    isolationist*: StrategyPersonalityConfig

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

  BudgetAllocationsConfig* = object
    ## Budget allocations across all 4 game acts
    act1_land_grab*: BudgetAllocationConfig
    act2_rising_tensions*: BudgetAllocationConfig
    act3_total_war*: BudgetAllocationConfig
    act4_endgame*: BudgetAllocationConfig

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
  TerraformingCostsConfig* = object
    ## Terraforming costs by planet class transition (in PP)
    extreme_to_desolate*: int
    desolate_to_hostile*: int
    hostile_to_harsh*: int
    harsh_to_benign*: int
    benign_to_lush*: int
    lush_to_eden*: int

  EconomicParametersConfig* = object
    ## Economic-related parameters
    terraforming_costs*: TerraformingCostsConfig

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
  MothballingConfig* = object
    ## Mothballing thresholds
    treasury_threshold_pp*: int
    maintenance_ratio_threshold*: float
    min_fleet_count*: int

  LogisticsConfig* = object
    ## Logistics parameters
    mothballing*: MothballingConfig

# ==============================================================================
# Fleet Composition
# ==============================================================================

type
  FleetCompositionRatioConfig* = object
    ## Target composition ratios for one doctrine
    capital_ratio*: float
    escort_ratio*: float
    specialist_ratio*: float

  FleetCompositionConfig* = object
    ## Fleet composition across all doctrines
    balanced*: FleetCompositionRatioConfig
    aggressive*: FleetCompositionRatioConfig
    defensive*: FleetCompositionRatioConfig

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
# Root Configuration
# ==============================================================================

type
  RBAConfig* = object
    ## Complete RBA configuration loaded from TOML
    strategies*: StrategyPersonalitiesConfig
    budget*: BudgetAllocationsConfig
    tactical*: TacticalConfig
    strategic*: StrategicConfig
    economic*: EconomicParametersConfig
    orders*: OrdersConfig
    logistics*: LogisticsConfig
    fleet_composition*: FleetCompositionConfig
    threat_assessment*: ThreatAssessmentConfig

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

  echo "[Config] Loaded RBA configuration from ", configPath

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
  echo "[Config] Reloaded RBA configuration"

proc reloadRBAConfigFromPath*(configPath: string) =
  ## Reload configuration from custom path
  ## Useful for:
  ## - Testing evolved configs from genetic algorithm
  ## - A/B testing different parameter sets
  globalRBAConfig = loadRBAConfig(configPath)
  echo "[Config] Reloaded RBA configuration from ", configPath
