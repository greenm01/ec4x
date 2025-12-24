## Ground Units Configuration Loader
##
## Loads ground unit stats from config/ground_units.toml using toml_serialization
## Allows runtime configuration for planetary defenses and invasion forces

import std/[os]
import toml_serialization
import ../../common/logger

type
  PlanetaryShieldConfig* = object
    name*: string
    class*: string
    cst_min*: int
    build_cost*: int
    upkeep_cost*: int
    attack_strength*: int
    defense_strength*: int
    description*: string
    build_time*: int
    max_per_planet*: int
    salvage_required*: bool

  GroundBatteryConfig* = object
    name*: string
    class*: string
    cst_min*: int
    build_cost*: int
    upkeep_cost*: int
    maintenance_percent*: int
    attack_strength*: int
    defense_strength*: int
    description*: string
    build_time*: int
    max_per_planet*: int

  ArmyConfig* = object
    name*: string
    class*: string
    cst_min*: int
    build_cost*: int
    upkeep_cost*: int
    maintenance_percent*: int
    attack_strength*: int
    defense_strength*: int
    description*: string
    build_time*: int
    max_per_planet*: int
    population_cost*: int # Souls recruited per division

  MarineDivisionConfig* = object
    name*: string
    class*: string
    cst_min*: int
    build_cost*: int
    upkeep_cost*: int
    maintenance_percent*: int
    attack_strength*: int
    defense_strength*: int
    description*: string
    build_time*: int
    max_per_planet*: int
    requires_transport*: bool
    population_cost*: int # Souls recruited per division

  GroundUnitsConfig* = object ## Complete ground units configuration loaded from TOML
    planetary_shield*: PlanetaryShieldConfig
    ground_battery*: GroundBatteryConfig
    army*: ArmyConfig
    marine_division*: MarineDivisionConfig

proc loadGroundUnitsConfig*(
    configPath: string = "config/ground_units.toml"
): GroundUnitsConfig =
  ## Load ground units configuration from TOML file
  ## Uses toml_serialization for type-safe parsing

  if not fileExists(configPath):
    raise newException(IOError, "Ground units config not found: " & configPath)

  let configContent = readFile(configPath)
  result = Toml.decode(configContent, GroundUnitsConfig)

  logInfo("Config", "Loaded ground units configuration", "path=", configPath)

## Global configuration instance

var globalGroundUnitsConfig* = loadGroundUnitsConfig()

## Helper to reload configuration (for testing)

proc reloadGroundUnitsConfig*() =
  ## Reload configuration from file
  globalGroundUnitsConfig = loadGroundUnitsConfig()
