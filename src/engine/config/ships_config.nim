## Ships Configuration Loader
##
## Loads ship statistics from config/ships.toml using toml_serialization
## Allows runtime configuration for all ship types and their combat stats

import std/[os, options]
import toml_serialization

type
  ShipStatsConfig* = object
    name*: string
    class*: string
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

  ShipsConfig* = object
    ## Complete ships configuration loaded from TOML
    ## WEP modifiers (+10% AS/DS per level) are applied by the engine
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

  echo "[Config] Loaded ships configuration from ", configPath

## Global configuration instance

var globalShipsConfig* = loadShipsConfig()

## Helper to reload configuration (for testing)

proc reloadShipsConfig*() =
  ## Reload configuration from file
  globalShipsConfig = loadShipsConfig()
