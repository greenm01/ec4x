## Construction Configuration Loader
##
## Loads construction times, costs, repair costs, and upkeep from config/construction.toml
## Allows runtime configuration for construction mechanics

import std/[os]
import toml_serialization
import ../../common/logger

type
  ConstructionTimesConfig* = object
    spaceport_turns*: int
    spaceport_docks*: int
    shipyard_turns*: int
    shipyard_docks*: int
    shipyard_requires_spaceport*: bool
    starbase_turns*: int
    starbase_requires_shipyard*: bool
    starbase_max_per_colony*: int
    planetary_shield_turns*: int
    planetary_shield_max*: int
    planetary_shield_replace_on_upgrade*: bool
    ground_battery_turns*: int
    ground_battery_max*: int
    fighter_squadron_planet_based*: bool

  RepairConfig* = object
    ship_repair_turns*: int
    ship_repair_cost_multiplier*: float
    starbase_repair_cost_multiplier*: float

  ModifiersConfig* = object
    planetside_construction_cost_multiplier*: float
    construction_capacity_increase_per_level*: float

  CostsConfig* = object
    spaceport_cost*: int
    shipyard_cost*: int
    starbase_cost*: int
    ground_battery_cost*: int
    fighter_squadron_cost*: int
    planetary_shield_sld1_cost*: int
    planetary_shield_sld2_cost*: int
    planetary_shield_sld3_cost*: int
    planetary_shield_sld4_cost*: int
    planetary_shield_sld5_cost*: int
    planetary_shield_sld6_cost*: int

  UpkeepConfig* = object
    spaceport_upkeep*: int
    shipyard_upkeep*: int
    starbase_upkeep*: int
    ground_battery_upkeep*: int
    planetary_shield_upkeep*: int

  ConstructionConfig* = object
    ## Complete construction configuration loaded from TOML
    construction*: ConstructionTimesConfig
    repair*: RepairConfig
    modifiers*: ModifiersConfig
    costs*: CostsConfig
    upkeep*: UpkeepConfig

proc loadConstructionConfig*(configPath: string = "config/construction.toml"): ConstructionConfig =
  ## Load construction configuration from TOML file
  ## Uses toml_serialization for type-safe parsing

  if not fileExists(configPath):
    raise newException(IOError, "Construction config not found: " & configPath)

  let configContent = readFile(configPath)
  result = Toml.decode(configContent, ConstructionConfig)

  logInfo("Config", "Loaded construction configuration", "path=", configPath)

## Global configuration instance

var globalConstructionConfig* = loadConstructionConfig()

## Helper to reload configuration (for testing)

proc reloadConstructionConfig*() =
  ## Reload configuration from file
  globalConstructionConfig = loadConstructionConfig()
