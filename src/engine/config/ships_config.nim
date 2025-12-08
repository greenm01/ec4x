## Ships Configuration Loader
##
## Loads ship statistics from config/ships.toml using toml_serialization
## Allows runtime configuration for all ship types and their combat stats

import std/[os, options]
import toml_serialization
import ../../common/logger

type
  ShipStatsConfig* = object
    name*: string
    class*: string
    ship_role*: string
    attack_strength*: int
    defense_strength*: int
    command_cost*: int
    command_rating*: int
    carry_limit*: Option[int]
    tech_level*: int
    build_cost*: int
    upkeep_cost*: int
    maintenance_percent*: Option[int]
    special_capability*: string

  ConstructionTimesConfig* = object
    ## Base construction times for each ship class
    ## Modified by CST tech: ceiling(base_time × (1.0 - (CST_level - 1) × 0.10))
    etac_base_time*: int
    troop_transport_base_time*: int
    corvette_base_time*: int
    frigate_base_time*: int
    destroyer_base_time*: int
    scout_base_time*: int
    cruiser_base_time*: int
    light_cruiser_base_time*: int
    heavy_cruiser_base_time*: int
    battlecruiser_base_time*: int
    battleship_base_time*: int
    carrier_base_time*: int
    raider_base_time*: int
    dreadnought_base_time*: int
    super_dreadnought_base_time*: int
    supercarrier_base_time*: int
    planetbreaker_base_time*: int
    fighter_base_time*: int
    starbase_base_time*: int

  ShipsConfig* = object
    ## Complete ships configuration loaded from TOML
    ## WEP modifiers (+10% AS/DS per level) are applied by the engine
    construction*: ConstructionTimesConfig
    corvette*: ShipStatsConfig
    frigate*: ShipStatsConfig
    destroyer*: ShipStatsConfig
    cruiser*: ShipStatsConfig
    light_cruiser*: ShipStatsConfig
    heavy_cruiser*: ShipStatsConfig
    battlecruiser*: ShipStatsConfig
    battleship*: ShipStatsConfig
    dreadnought*: ShipStatsConfig
    super_dreadnought*: ShipStatsConfig
    planetbreaker*: ShipStatsConfig
    carrier*: ShipStatsConfig
    supercarrier*: ShipStatsConfig
    fighter*: ShipStatsConfig
    raider*: ShipStatsConfig
    scout*: ShipStatsConfig
    starbase*: ShipStatsConfig
    etac*: ShipStatsConfig
    troop_transport*: ShipStatsConfig
    ground_battery*: ShipStatsConfig

proc loadShipsConfig*(configPath: string = "config/ships.toml"): ShipsConfig =
  ## Load ships configuration from TOML file
  ## Uses toml_serialization for type-safe parsing

  if not fileExists(configPath):
    raise newException(IOError, "Ships config not found: " & configPath)

  let configContent = readFile(configPath)
  result = Toml.decode(configContent, ShipsConfig)

  logInfo("Config", "Loaded ships configuration", "path=", configPath)

## Global configuration instance

var globalShipsConfig* = loadShipsConfig()

## Helper to reload configuration (for testing)

proc reloadShipsConfig*() =
  ## Reload configuration from file
  globalShipsConfig = loadShipsConfig()
