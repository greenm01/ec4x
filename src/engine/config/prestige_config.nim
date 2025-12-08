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
    starting_prestige*: int
    defeat_threshold*: int
    defeat_consecutive_turns*: int

  DynamicScalingConfig* = object
    enabled*: bool
    base_multiplier*: float
    baseline_turns*: int
    baseline_systems_per_player*: int
    turn_scaling_factor*: float
    min_multiplier*: float
    max_multiplier*: float

  MoraleConfig* = object
    crisis_max*: int
    low_max*: int
    average_max*: int
    good_max*: int
    high_max*: int

  EconomicPrestigeConfig* = object
    tech_advancement*: int
    establish_colony*: int
    max_population*: int
    iu_milestone_50*: int
    iu_milestone_75*: int
    iu_milestone_100*: int
    iu_milestone_150*: int
    terraform_planet*: int

  MilitaryPrestigeConfig* = object
    destroy_squadron*: int
    destroy_starbase*: int
    fleet_victory*: int
    invade_planet*: int
    eliminate_house*: int
    system_capture*: int
    lose_planet*: int
    lose_starbase*: int
    ambushed_by_cloak*: int
    force_retreat*: int
    forced_to_retreat*: int  # NEW: Penalty for being forced to retreat (counterpart to force_retreat)
    scout_destroyed*: int
    undefended_colony_penalty_multiplier*: float  # Phase F: Penalty multiplier for losing undefended colonies

  EspionagePrestigeConfig* = object
    tech_theft*: int
    low_impact_sabotage*: int
    high_impact_sabotage*: int
    assassination*: int
    cyber_attack*: int
    economic_manipulation*: int
    psyops_campaign*: int
    counter_intel_sweep*: int
    intelligence_theft*: int
    plant_disinformation*: int
    failed_espionage*: int

  EspionageVictimPrestigeConfig* = object
    tech_theft_victim*: int
    low_impact_sabotage_victim*: int
    high_impact_sabotage_victim*: int
    assassination_victim*: int
    cyber_attack_victim*: int
    economic_manipulation_victim*: int
    psyops_campaign_victim*: int
    counter_intel_sweep_victim*: int
    intelligence_theft_victim*: int
    plant_disinformation_victim*: int

  ScoutPrestigeConfig* = object
    spy_on_planet*: int
    hack_starbase*: int
    spy_on_system*: int

  DiplomacyPrestigeConfig* = object
    diplomatic_pact_formation*: int
    pact_violation*: int
    repeat_violation*: int
    dishonored_bonus*: int
    declare_war*: int
    make_peace*: int

  VictoryAchievementConfig* = object
    victory_achieved*: int

  PenaltiesPrestigeConfig* = object
    high_tax_threshold*: int
    high_tax_penalty*: int
    high_tax_frequency*: int
    very_high_tax_threshold*: int
    very_high_tax_penalty*: int
    very_high_tax_frequency*: int
    maintenance_shortfall_base*: int
    maintenance_shortfall_increment*: int
    blockade_penalty*: int
    over_invest_espionage*: int
    over_invest_counter_intel*: int

  TaxPenaltiesTier* = object
    tier_1_min*: int
    tier_1_max*: int
    tier_1_penalty*: int
    tier_2_min*: int
    tier_2_max*: int
    tier_2_penalty*: int
    tier_3_min*: int
    tier_3_max*: int
    tier_3_penalty*: int
    tier_4_min*: int
    tier_4_max*: int
    tier_4_penalty*: int
    tier_5_min*: int
    tier_5_max*: int
    tier_5_penalty*: int
    tier_6_min*: int
    tier_6_max*: int
    tier_6_penalty*: int

  TaxIncentivesTier* = object
    tier_1_min*: int
    tier_1_max*: int
    tier_1_prestige*: int
    tier_2_min*: int
    tier_2_max*: int
    tier_2_prestige*: int
    tier_3_min*: int
    tier_3_max*: int
    tier_3_prestige*: int
    tier_4_min*: int
    tier_4_max*: int
    tier_4_prestige*: int
    tier_5_min*: int
    tier_5_max*: int
    tier_5_prestige*: int

  PrestigeConfig* = object
    ## Complete prestige configuration loaded from TOML
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

proc calculateDynamicMultiplier*(numSystems: int, numPlayers: int): float =
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
  let systemsPerPlayer = float(numSystems) / float(numPlayers)

  # Calculate target turns based on map density
  let systemDiff = systemsPerPlayer - float(config.baseline_systems_per_player)
  let targetTurns = float(config.baseline_turns) + (systemDiff * config.turn_scaling_factor)

  # Calculate multiplier (inverse relationship: more turns = lower multiplier)
  let multiplier = config.base_multiplier * (float(config.baseline_turns) / targetTurns)

  # Clamp to reasonable bounds
  result = max(config.min_multiplier, min(config.max_multiplier, multiplier))
