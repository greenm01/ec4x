## Starmap Configuration Loader
##
## Loads starmap generation parameters from config/starmap.toml using toml_serialization
## Allows runtime configuration for lane weights and map generation

import std/[os]
import toml_serialization
import ../../common/logger

type
  LaneWeightsConfig* = object
    ## Jump lane type distribution weights
    major_weight*: float
    minor_weight*: float
    restricted_weight*: float

  GenerationConfig* = object
    ## Map generation parameters
    use_distance_maximization*: bool
    prefer_vertex_positions*: bool
    hub_uses_mixed_lanes*: bool

  HomeworldPlacementConfig* = object
    ## Homeworld placement parameters
    homeworld_lane_count*: int  # Number of lanes per homeworld (default: 3)

  StarmapConfig* = object
    ## Complete starmap configuration loaded from TOML
    lane_weights*: LaneWeightsConfig
    generation*: GenerationConfig
    homeworld_placement*: HomeworldPlacementConfig

proc loadStarmapConfig*(configPath: string = "config/starmap.toml"): StarmapConfig =
  ## Load starmap configuration from TOML file
  ## Uses toml_serialization for type-safe parsing

  if not fileExists(configPath):
    raise newException(IOError, "Starmap config not found: " & configPath)

  let configContent = readFile(configPath)
  result = Toml.decode(configContent, StarmapConfig)

  logInfo("Config", "Loaded starmap configuration", "path=", configPath)

## Global configuration instance

var globalStarmapConfig* = loadStarmapConfig()

## Helper to reload configuration (for testing)

proc reloadStarmapConfig*() =
  ## Reload configuration from file
  globalStarmapConfig = loadStarmapConfig()
