## Espionage Configuration Loader
##
## Loads espionage values from config/espionage.toml using toml_serialization
## Allows runtime configuration for balance testing

import std/[os]
import toml_serialization
import ../../common/logger

type
  EspionageCostsConfig* = object
    ebp_cost_pp*: int
    cip_cost_pp*: int
    tech_theft_ebp*: int
    sabotage_low_ebp*: int
    sabotage_high_ebp*: int
    assassination_ebp*: int
    cyber_attack_ebp*: int
    economic_manipulation_ebp*: int
    psyops_campaign_ebp*: int
    counter_intel_sweep_ebp*: int
    intelligence_theft_ebp*: int
    plant_disinformation_ebp*: int

  EspionageInvestmentConfig* = object
    threshold_percentage*: int
    penalty_per_percent*: int

  EspionageDetectionConfig* = object
    cip_per_roll*: int
    cic0_threshold*: int
    cic1_threshold*: int
    cic2_threshold*: int
    cic3_threshold*: int
    cic4_threshold*: int
    cic5_threshold*: int
    cip_0_modifier*: int
    cip_1_5_modifier*: int
    cip_6_10_modifier*: int
    cip_11_15_modifier*: int
    cip_16_20_modifier*: int
    cip_21_plus_modifier*: int

  EspionageEffectsConfig* = object
    tech_theft_srp*: int
    sabotage_low_dice*: int
    sabotage_high_dice*: int
    assassination_srp_reduction*: int
    economic_ncv_reduction*: int
    psyops_tax_reduction*: int
    effect_duration_turns*: int
    failed_espionage_prestige*: int
    intel_block_duration*: int
    disinformation_duration*: int
    disinformation_min_variance*: float
    disinformation_max_variance*: float

  ScoutDetectionConfig* = object
    mesh_2_3_scouts*: int
    mesh_4_5_scouts*: int
    mesh_6_plus_scouts*: int
    starbase_eli_bonus*: int
    dominant_tech_threshold*: float
    max_eli_level*: int

  EspionageConfig* = object ## Complete espionage configuration loaded from TOML
    costs*: EspionageCostsConfig
    investment*: EspionageInvestmentConfig
    detection*: EspionageDetectionConfig
    effects*: EspionageEffectsConfig
    scout_detection*: ScoutDetectionConfig

proc loadEspionageConfig*(
    configPath: string = "config/espionage.toml"
): EspionageConfig =
  ## Load espionage configuration from TOML file
  ## Uses toml_serialization for type-safe parsing

  if not fileExists(configPath):
    raise newException(IOError, "Espionage config not found: " & configPath)

  let configContent = readFile(configPath)
  result = Toml.decode(configContent, EspionageConfig)

  logInfo("Config", "Loaded espionage configuration", "path=", configPath)

## Global configuration instance

var globalEspionageConfig* = loadEspionageConfig()

## Helper to reload configuration (for testing)

proc reloadEspionageConfig*() =
  ## Reload configuration from file
  globalEspionageConfig = loadEspionageConfig()
