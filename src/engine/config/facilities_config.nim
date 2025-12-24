## Facilities Configuration Loader
##
## Loads facility stats from config/facilities.toml using toml_serialization
## Allows runtime configuration for spaceports and shipyards

import std/[os]
import toml_serialization
import ../../common/logger

type
  SpaceportConfig* = object
    name*: string
    class*: string
    cst_min*: int
    build_cost*: int
    upkeep_cost*: int
    defense_strength*: int
    carry_limit*: int
    description*: string
    build_time*: int
    docks*: int
    max_per_planet*: int
    required_for_shipyard*: bool

  ShipyardConfig* = object
    name*: string
    class*: string
    cst_min*: int
    build_cost*: int
    upkeep_cost*: int
    defense_strength*: int
    carry_limit*: int
    description*: string
    build_time*: int
    docks*: int
    max_per_planet*: int
    requires_spaceport*: bool
    fixed_orbit*: bool

  DrydockConfig* = object
    name*: string
    class*: string
    cst_min*: int
    build_cost*: int
    upkeep_cost*: int
    defense_strength*: int
    carry_limit*: int
    description*: string
    build_time*: int
    docks*: int
    max_per_planet*: int
    requires_spaceport*: bool
    fixed_orbit*: bool
    repair_only*: bool

  StarbaseConfig* = object
    name*: string
    class*: string
    cst_min*: int
    build_cost*: int
    upkeep_cost*: int
    defense_strength*: int
    attack_strength*: int
    description*: string
    build_time*: int
    max_per_planet*: int
    requires_spaceport*: bool
    fixed_orbit*: bool
    economic_lift_bonus*: int
    growth_bonus*: float

  ConstructionConfig* = object
    repair_rate_per_turn*: float
    multiple_docks_allowed*: bool
    squadron_commission_location*: string

  FacilitiesConfig* = object ## Complete facilities configuration loaded from TOML
    spaceport*: SpaceportConfig
    shipyard*: ShipyardConfig
    drydock*: DrydockConfig
    starbase*: StarbaseConfig
    construction*: ConstructionConfig

proc loadFacilitiesConfig*(
    configPath: string = "config/facilities.toml"
): FacilitiesConfig =
  ## Load facilities configuration from TOML file
  ## Uses toml_serialization for type-safe parsing

  if not fileExists(configPath):
    raise newException(IOError, "Facilities config not found: " & configPath)

  let configContent = readFile(configPath)
  result = Toml.decode(configContent, FacilitiesConfig)

  logInfo("Config", "Loaded facilities configuration", "path=", configPath)

## Global configuration instance

var globalFacilitiesConfig* = loadFacilitiesConfig()

## Helper to reload configuration (for testing)

proc reloadFacilitiesConfig*() =
  ## Reload configuration from file
  globalFacilitiesConfig = loadFacilitiesConfig()
