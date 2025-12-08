## Military Configuration Loader
##
## Loads military mechanics from config/military.toml using toml_serialization
## Allows runtime configuration for squadron limits and salvage

import std/[os]
import toml_serialization
import ../../common/logger

type
  FighterMechanicsConfig* = object
    fighter_capacity_iu_divisor*: int
    starbase_per_fighter_squadrons*: int
    capacity_violation_grace_period*: int

  SquadronLimitsConfig* = object
    squadron_limit_iu_divisor*: int  # IU divisor for capital squadron limit calculation
    squadron_limit_minimum*: int
    total_squadron_iu_divisor*: int  # IU divisor for total squadron limit calculation
    total_squadron_minimum*: int
    capital_ship_cr_threshold*: int

  SalvageConfig* = object
    salvage_value_multiplier*: float
    emergency_salvage_multiplier*: float

  MilitaryConfig* = object
    ## Complete military configuration loaded from TOML
    fighter_mechanics*: FighterMechanicsConfig
    squadron_limits*: SquadronLimitsConfig
    salvage*: SalvageConfig

proc loadMilitaryConfig*(configPath: string = "config/military.toml"): MilitaryConfig =
  ## Load military configuration from TOML file
  ## Uses toml_serialization for type-safe parsing

  if not fileExists(configPath):
    raise newException(IOError, "Military config not found: " & configPath)

  let configContent = readFile(configPath)
  result = Toml.decode(configContent, MilitaryConfig)

  logInfo("Config", "Loaded military configuration", "path=", configPath)

## Global configuration instance

var globalMilitaryConfig* = loadMilitaryConfig()

## Helper to reload configuration (for testing)

proc reloadMilitaryConfig*() =
  ## Reload configuration from file
  globalMilitaryConfig = loadMilitaryConfig()
