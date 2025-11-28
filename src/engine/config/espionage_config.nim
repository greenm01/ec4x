## Espionage Configuration Loader
##
## Loads espionage values from config/espionage.toml using toml_serialization
## Allows runtime configuration for balance testing

import std/[os]
import toml_serialization
import ../../common/logger

type
  ThresholdRange* = array[2, int]  ## [min_threshold, max_threshold]

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

  RaiderDetectionConfig* = object
    threshold_variance_dice*: int
    eli_advantage_major*: int
    eli_advantage_minor*: int

  SpyDetectionTable* = object
    ## 5x5 detection matrix for spy scouts
    eli1_vs_spy_eli1*: ThresholdRange
    eli1_vs_spy_eli2*: ThresholdRange
    eli1_vs_spy_eli3*: ThresholdRange
    eli1_vs_spy_eli4*: ThresholdRange
    eli1_vs_spy_eli5*: ThresholdRange
    eli2_vs_spy_eli1*: ThresholdRange
    eli2_vs_spy_eli2*: ThresholdRange
    eli2_vs_spy_eli3*: ThresholdRange
    eli2_vs_spy_eli4*: ThresholdRange
    eli2_vs_spy_eli5*: ThresholdRange
    eli3_vs_spy_eli1*: ThresholdRange
    eli3_vs_spy_eli2*: ThresholdRange
    eli3_vs_spy_eli3*: ThresholdRange
    eli3_vs_spy_eli4*: ThresholdRange
    eli3_vs_spy_eli5*: ThresholdRange
    eli4_vs_spy_eli1*: ThresholdRange
    eli4_vs_spy_eli2*: ThresholdRange
    eli4_vs_spy_eli3*: ThresholdRange
    eli4_vs_spy_eli4*: ThresholdRange
    eli4_vs_spy_eli5*: ThresholdRange
    eli5_vs_spy_eli1*: ThresholdRange
    eli5_vs_spy_eli2*: ThresholdRange
    eli5_vs_spy_eli3*: ThresholdRange
    eli5_vs_spy_eli4*: ThresholdRange
    eli5_vs_spy_eli5*: ThresholdRange

  RaiderDetectionTable* = object
    ## 5x5 detection matrix for raiders
    eli1_vs_clk1*: ThresholdRange
    eli1_vs_clk2*: ThresholdRange
    eli1_vs_clk3*: ThresholdRange
    eli1_vs_clk4*: ThresholdRange
    eli1_vs_clk5*: ThresholdRange
    eli2_vs_clk1*: ThresholdRange
    eli2_vs_clk2*: ThresholdRange
    eli2_vs_clk3*: ThresholdRange
    eli2_vs_clk4*: ThresholdRange
    eli2_vs_clk5*: ThresholdRange
    eli3_vs_clk1*: ThresholdRange
    eli3_vs_clk2*: ThresholdRange
    eli3_vs_clk3*: ThresholdRange
    eli3_vs_clk4*: ThresholdRange
    eli3_vs_clk5*: ThresholdRange
    eli4_vs_clk1*: ThresholdRange
    eli4_vs_clk2*: ThresholdRange
    eli4_vs_clk3*: ThresholdRange
    eli4_vs_clk4*: ThresholdRange
    eli4_vs_clk5*: ThresholdRange
    eli5_vs_clk1*: ThresholdRange
    eli5_vs_clk2*: ThresholdRange
    eli5_vs_clk3*: ThresholdRange
    eli5_vs_clk4*: ThresholdRange
    eli5_vs_clk5*: ThresholdRange

  EspionageConfig* = object
    ## Complete espionage configuration loaded from TOML
    costs*: EspionageCostsConfig
    investment*: EspionageInvestmentConfig
    detection*: EspionageDetectionConfig
    effects*: EspionageEffectsConfig
    scout_detection*: ScoutDetectionConfig
    raider_detection*: RaiderDetectionConfig
    spy_detection_table*: SpyDetectionTable
    raider_detection_table*: RaiderDetectionTable

proc loadEspionageConfig*(configPath: string = "config/espionage.toml"): EspionageConfig =
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

## Detection Table Lookup Functions

proc getSpyDetectionThreshold*(detectorELI: int, spyELI: int): ThresholdRange =
  ## Get detection threshold range for spy scout detection
  ## detectorELI: ELI level of detecting unit (1-5)
  ## spyELI: ELI level of spy scout (1-5)
  ## Returns: [min_threshold, max_threshold] for 1d20 roll
  ##
  ## Usage: Roll 1d3 to pick value in range, then roll 1d20 must exceed threshold
  let table = globalEspionageConfig.spy_detection_table

  case detectorELI
  of 1:
    case spyELI
    of 1: table.eli1_vs_spy_eli1
    of 2: table.eli1_vs_spy_eli2
    of 3: table.eli1_vs_spy_eli3
    of 4: table.eli1_vs_spy_eli4
    of 5: table.eli1_vs_spy_eli5
    else: [21, 21]  # Invalid
  of 2:
    case spyELI
    of 1: table.eli2_vs_spy_eli1
    of 2: table.eli2_vs_spy_eli2
    of 3: table.eli2_vs_spy_eli3
    of 4: table.eli2_vs_spy_eli4
    of 5: table.eli2_vs_spy_eli5
    else: [21, 21]
  of 3:
    case spyELI
    of 1: table.eli3_vs_spy_eli1
    of 2: table.eli3_vs_spy_eli2
    of 3: table.eli3_vs_spy_eli3
    of 4: table.eli3_vs_spy_eli4
    of 5: table.eli3_vs_spy_eli5
    else: [21, 21]
  of 4:
    case spyELI
    of 1: table.eli4_vs_spy_eli1
    of 2: table.eli4_vs_spy_eli2
    of 3: table.eli4_vs_spy_eli3
    of 4: table.eli4_vs_spy_eli4
    of 5: table.eli4_vs_spy_eli5
    else: [21, 21]
  of 5:
    case spyELI
    of 1: table.eli5_vs_spy_eli1
    of 2: table.eli5_vs_spy_eli2
    of 3: table.eli5_vs_spy_eli3
    of 4: table.eli5_vs_spy_eli4
    of 5: table.eli5_vs_spy_eli5
    else: [21, 21]
  else:
    [21, 21]  # Invalid ELI level

proc getRaiderDetectionThreshold*(detectorELI: int, cloakLevel: int): ThresholdRange =
  ## Get detection threshold range for raider detection
  ## detectorELI: ELI level of detecting unit (1-5)
  ## cloakLevel: Cloaking level of raider fleet (1-5)
  ## Returns: [min_threshold, max_threshold] for 1d20 roll
  ##
  ## Usage: Roll 1d3 to pick value in range, then roll 1d20 must exceed threshold
  let table = globalEspionageConfig.raider_detection_table

  case detectorELI
  of 1:
    case cloakLevel
    of 1: table.eli1_vs_clk1
    of 2: table.eli1_vs_clk2
    of 3: table.eli1_vs_clk3
    of 4: table.eli1_vs_clk4
    of 5: table.eli1_vs_clk5
    else: [21, 21]  # Invalid
  of 2:
    case cloakLevel
    of 1: table.eli2_vs_clk1
    of 2: table.eli2_vs_clk2
    of 3: table.eli2_vs_clk3
    of 4: table.eli2_vs_clk4
    of 5: table.eli2_vs_clk5
    else: [21, 21]
  of 3:
    case cloakLevel
    of 1: table.eli3_vs_clk1
    of 2: table.eli3_vs_clk2
    of 3: table.eli3_vs_clk3
    of 4: table.eli3_vs_clk4
    of 5: table.eli3_vs_clk5
    else: [21, 21]
  of 4:
    case cloakLevel
    of 1: table.eli4_vs_clk1
    of 2: table.eli4_vs_clk2
    of 3: table.eli4_vs_clk3
    of 4: table.eli4_vs_clk4
    of 5: table.eli4_vs_clk5
    else: [21, 21]
  of 5:
    case cloakLevel
    of 1: table.eli5_vs_clk1
    of 2: table.eli5_vs_clk2
    of 3: table.eli5_vs_clk3
    of 4: table.eli5_vs_clk4
    of 5: table.eli5_vs_clk5
    else: [21, 21]
  else:
    [21, 21]  # Invalid ELI level
