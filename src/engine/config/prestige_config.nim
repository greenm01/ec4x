## Prestige Configuration Loader
##
## Loads prestige values from config/prestige.toml using toml_serialization
## Allows runtime configuration for balance testing

import std/[os]
import toml_serialization
import ../../common/logger

type
  VictoryConfig* = object
    ## Victory config (prestige_victory removed - now in game_setup/*.toml)
    starting_prestige*: int32
    defeat_threshold*: int32
    defeat_consecutive_turns*: int32

  DynamicScalingConfig* = object
    enabled*: bool
    base_multiplier*: float32
    baseline_turns*: int32
    baseline_systems_per_player*: int32
    turn_scaling_factor*: float32
    min_multiplier*: float32
    max_multiplier*: float32

  MoraleConfig* = object
    crisis_max*: int32
    low_max*: int32
    average_max*: int32
    good_max*: int32
    high_max*: int32

  EconomicPrestigeConfig* = object
    tech_advancement*: int32
    establish_colony*: int32
    max_population*: int32
    iu_milestone_50*: int32
    iu_milestone_75*: int32
    iu_milestone_100*: int32
    iu_milestone_150*: int32
    terraform_planet*: int32

  MilitaryPrestigeConfig* = object
    destroy_squadron*: int32
    destroy_starbase*: int32
    fleet_victory*: int32
    invade_planet*: int32
    eliminate_house*: int32
    system_capture*: int32
    lose_planet*: int32
    lose_starbase*: int32
    ambushed_by_cloak*: int32
    force_retreat*: int32
    forced_to_retreat*: int32
      # NEW: Penalty for being forced to retreat (counterpart to force_retreat)
    scout_destroyed*: int32
    undefended_colony_penalty_multiplier*: float32
      # Phase F: Penalty multiplier for losing undefended colonies

  EspionagePrestigeConfig* = object
    tech_theft*: int32
    low_impact_sabotage*: int32
    high_impact_sabotage*: int32
    assassination*: int32
    cyber_attack*: int32
    economic_manipulation*: int32
    psyops_campaign*: int32
    counter_intel_sweep*: int32
    intelligence_theft*: int32
    plant_disinformation*: int32
    failed_espionage*: int32

  EspionageVictimPrestigeConfig* = object
    tech_theft_victim*: int32
    low_impact_sabotage_victim*: int32
    high_impact_sabotage_victim*: int32
    assassination_victim*: int32
    cyber_attack_victim*: int32
    economic_manipulation_victim*: int32
    psyops_campaign_victim*: int32
    counter_intel_sweep_victim*: int32
    intelligence_theft_victim*: int32
    plant_disinformation_victim*: int32

  ScoutPrestigeConfig* = object
    spy_on_planet*: int32
    hack_starbase*: int32
    spy_on_system*: int32

  DiplomacyPrestigeConfig* = object
    diplomatic_pact_formation*: int32
    pact_violation*: int32
    repeat_violation*: int32
    dishonored_bonus*: int32
    declare_war*: int32
    make_peace*: int32

  VictoryAchievementConfig* = object
    victory_achieved*: int32

  PenaltiesPrestigeConfig* = object
    high_tax_threshold*: int32
    high_tax_penalty*: int32
    high_tax_frequency*: int32
    very_high_tax_threshold*: int32
    very_high_tax_penalty*: int32
    very_high_tax_frequency*: int32
    maintenance_shortfall_base*: int32
    maintenance_shortfall_increment*: int32
    blockade_penalty*: int32
    over_invest_espionage*: int32
    over_invest_counter_intel*: int32

  TaxPenaltiesTier* = object
    tier_1_min*: int32
    tier_1_max*: int32
    tier_1_penalty*: int32
    tier_2_min*: int32
    tier_2_max*: int32
    tier_2_penalty*: int32
    tier_3_min*: int32
    tier_3_max*: int32
    tier_3_penalty*: int32
    tier_4_min*: int32
    tier_4_max*: int32
    tier_4_penalty*: int32
    tier_5_min*: int32
    tier_5_max*: int32
    tier_5_penalty*: int32
    tier_6_min*: int32
    tier_6_max*: int32
    tier_6_penalty*: int32

  TaxIncentivesTier* = object
    tier_1_min*: int32
    tier_1_max*: int32
    tier_1_prestige*: int32
    tier_2_min*: int32
    tier_2_max*: int32
    tier_2_prestige*: int32
    tier_3_min*: int32
    tier_3_max*: int32
    tier_3_prestige*: int32
    tier_4_min*: int32
    tier_4_max*: int32
    tier_4_prestige*: int32
    tier_5_min*: int32
    tier_5_max*: int32
    tier_5_prestige*: int32

  PrestigeConfig* = object ## Complete prestige configuration loaded from TOML
    victory*: VictoryConfig
    dynamic_scaling*: DynamicScalingConfig
    morale*: MoraleConfig
    economic*: EconomicPrestigeConfig
    military*: MilitaryPrestigeConfig
    espionage*: EspionagePrestigeConfig
    espionage_victim*: EspionageVictimPrestigeConfig
    scout*: ScoutPrestigeConfig
    diplomacy*: DiplomacyPrestigeConfig
    victory_achievement*: VictoryAchievementConfig
    penalties*: PenaltiesPrestigeConfig
    tax_penalties*: TaxPenaltiesTier
    tax_incentives*: TaxIncentivesTier

proc loadPrestigeConfig*(configPath: string = "config/prestige.toml"): PrestigeConfig =
  ## Load prestige configuration from TOML file
  ## Uses toml_serialization for type-safe parsing

  if not fileExists(configPath):
    raise newException(IOError, "Prestige config not found: " & configPath)

  let configContent = readFile(configPath)
  result = Toml.decode(configContent, PrestigeConfig)

  logInfo("Config", "Loaded prestige configuration", "path=", configPath)

## Global configuration instance

var globalPrestigeConfig* = loadPrestigeConfig()

## Helper to reload configuration (for testing)

proc reloadPrestigeConfig*() =
  ## Reload configuration from file
  globalPrestigeConfig = loadPrestigeConfig()

## Dynamic Prestige Multiplier Calculation

proc calculateDynamicMultiplier*(numSystems: int32, numPlayers: int32): float32 =
  ## Calculate dynamic prestige multiplier based on map size and player count
  ##
  ## Formula:
  ##   systems_per_player = numSystems / numPlayers
  ##   target_turns = baseline_turns + (systems_per_player - baseline_ratio) * turn_scaling_factor
  ##   multiplier = base_multiplier * (baseline_turns / target_turns)
  ##   multiplier = clamp(multiplier, min_multiplier, max_multiplier)
  ##
  ## This ensures:
  ## - Small maps (few systems per player): Higher multiplier = faster games
  ## - Large maps (many systems per player): Lower multiplier = longer games
  ## - Victory threshold (5000 prestige) stays constant regardless of map size

  let config = globalPrestigeConfig.dynamic_scaling

  # If dynamic scaling is disabled, return base multiplier
  if not config.enabled:
    return config.base_multiplier

  # Calculate systems per player
  let systemsPerPlayer = float32(numSystems) / float32(numPlayers)

  # Calculate target turns based on map density
  let systemDiff = systemsPerPlayer - float32(config.baseline_systems_per_player)
  let targetTurns =
    float32(config.baseline_turns) + (systemDiff * config.turn_scaling_factor)

  # Calculate multiplier (inverse relationship: more turns = lower multiplier)
  let multiplier =
    config.base_multiplier * (float32(config.baseline_turns) / targetTurns)

  # Clamp to reasonable bounds
  result = max(config.min_multiplier, min(config.max_multiplier, multiplier))
