## Prestige Configuration Loader
##
## Loads prestige values from config/prestige.toml using toml_serialization
## Allows runtime configuration for balance testing

import std/[os]
import toml_serialization

type
  VictoryConfig* = object
    prestige_victory*: int
    starting_prestige*: int
    defeat_threshold*: int
    defeat_consecutive_turns*: int

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
    scout_destroyed*: int

  EspionagePrestigeConfig* = object
    tech_theft*: int
    low_impact_sabotage*: int
    high_impact_sabotage*: int
    assassination*: int
    cyber_attack*: int
    economic_manipulation*: int
    psyops_campaign*: int
    failed_espionage*: int

  EspionageVictimPrestigeConfig* = object
    tech_theft_victim*: int
    low_impact_sabotage_victim*: int
    high_impact_sabotage_victim*: int
    assassination_victim*: int
    cyber_attack_victim*: int
    economic_manipulation_victim*: int
    psyops_campaign_victim*: int

  ScoutPrestigeConfig* = object
    spy_on_planet*: int
    hack_starbase*: int
    spy_on_system*: int

  DiplomacyPrestigeConfig* = object
    diplomatic_pact_formation*: int
    pact_violation*: int
    repeat_violation*: int
    dishonored_expires*: int
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

  echo "[Config] Loaded prestige configuration from ", configPath

## Global configuration instance

var globalPrestigeConfig* = loadPrestigeConfig()

## Helper to reload configuration (for testing)

proc reloadPrestigeConfig*() =
  ## Reload configuration from file
  globalPrestigeConfig = loadPrestigeConfig()
