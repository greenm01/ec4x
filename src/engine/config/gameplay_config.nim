## Gameplay Configuration Loader
##
## Loads gameplay mechanics from config/gameplay.toml using toml_serialization
## Allows runtime configuration for core game rules

import std/[os]
import toml_serialization

type
  StartingTechConfig* = object
    ## Starting tech levels per gameplay.md:1.2 and economy.md tech tables
    ## CRITICAL: ALL tech starts at level 1, not 0!
    energy_level*: int              # EL1
    shield_level*: int              # SL1
    construction_tech*: int         # CST1
    weapons_tech*: int              # WEP1
    terraforming_tech*: int         # TER1
    electronic_intelligence*: int   # ELI1
    counter_intelligence*: int      # CIC1
    fighter_doctrine*: int          # FD I (starts at 1)
    advanced_carrier_ops*: int      # ACO I (starts at 1)

  EliminationConfig* = object
    defensive_collapse_turns*: int
    defensive_collapse_threshold*: int

  AutopilotConfig* = object
    mia_turns_threshold*: int

  AutopilotBehaviorConfig* = object
    continue_standing_orders*: bool
    patrol_home_systems*: bool
    maintain_economy*: bool
    defensive_construction*: bool
    no_offensive_ops*: bool
    maintain_diplomacy*: bool

  DefensiveCollapseBehaviorConfig* = object
    retreat_to_home*: bool
    defend_only*: bool
    no_construction*: bool
    no_diplomacy_changes*: bool
    economy_ceases*: bool
    permanent_elimination*: bool

  VictoryConfig* = object
    prestige_victory_enabled*: bool
    last_player_victory_enabled*: bool
    autopilot_can_win*: bool
    final_conflict_auto_enemy*: bool

  GameplayConfig* = object
    ## Complete gameplay configuration loaded from TOML
    starting_tech*: StartingTechConfig
    elimination*: EliminationConfig
    autopilot*: AutopilotConfig
    autopilot_behavior*: AutopilotBehaviorConfig
    defensive_collapse_behavior*: DefensiveCollapseBehaviorConfig
    victory*: VictoryConfig

proc loadGameplayConfig*(configPath: string = "config/gameplay.toml"): GameplayConfig =
  ## Load gameplay configuration from TOML file
  ## Uses toml_serialization for type-safe parsing

  if not fileExists(configPath):
    raise newException(IOError, "Gameplay config not found: " & configPath)

  let configContent = readFile(configPath)
  result = Toml.decode(configContent, GameplayConfig)

  echo "[Config] Loaded gameplay configuration from ", configPath

## Global configuration instance

var globalGameplayConfig* = loadGameplayConfig()

## Helper to reload configuration (for testing)

proc reloadGameplayConfig*() =
  ## Reload configuration from file
  globalGameplayConfig = loadGameplayConfig()
