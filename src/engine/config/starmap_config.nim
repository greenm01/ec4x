## Starmap Configuration Loader
##
## Loads starmap generation parameters from config/starmap.kdl using nimkdl
## Allows runtime configuration for lane weights and map generation

import kdl
import kdl_config_helpers
import ../../common/logger

type
  LaneWeightsConfig* = object ## Jump lane type distribution weights
    majorWeight*: float
    minorWeight*: float
    restrictedWeight*: float

  GenerationConfig* = object ## Map generation parameters
    useDistanceMaximization*: bool
    preferVertexPositions*: bool
    hubUsesMixedLanes*: bool

  HomeworldPlacementConfig* = object ## Homeworld placement parameters
    homeworldLaneCount*: int # Number of lanes per homeworld (default: 3)

  StarmapConfig* = object ## Complete starmap configuration loaded from KDL
    laneWeights*: LaneWeightsConfig
    generation*: GenerationConfig
    homeworldPlacement*: HomeworldPlacementConfig

proc parseLaneWeights(node: KdlNode, ctx: var KdlConfigContext): LaneWeightsConfig =
  result = LaneWeightsConfig(
    majorWeight: node.requireFloat("majorWeight", ctx),
    minorWeight: node.requireFloat("minorWeight", ctx),
    restrictedWeight: node.requireFloat("restrictedWeight", ctx)
  )

proc parseGeneration(node: KdlNode, ctx: var KdlConfigContext): GenerationConfig =
  result = GenerationConfig(
    useDistanceMaximization: node.requireBool("useDistanceMaximization", ctx),
    preferVertexPositions: node.requireBool("preferVertexPositions", ctx),
    hubUsesMixedLanes: node.requireBool("hubUsesMixedLanes", ctx)
  )

proc parseHomeworldPlacement(node: KdlNode, ctx: var KdlConfigContext): HomeworldPlacementConfig =
  result = HomeworldPlacementConfig(
    homeworldLaneCount: node.requireInt("homeworldLaneCount", ctx)
  )

proc loadStarmapConfig*(configPath: string = "config/starmap.kdl"): StarmapConfig =
  ## Load starmap configuration from KDL file
  ## Uses kdl_config_helpers for type-safe parsing
  let doc = loadKdlConfig(configPath)
  var ctx = newContext(configPath)

  ctx.withNode("laneWeights"):
    let laneNode = doc.requireNode("laneWeights", ctx)
    result.laneWeights = parseLaneWeights(laneNode, ctx)

  ctx.withNode("generation"):
    let genNode = doc.requireNode("generation", ctx)
    result.generation = parseGeneration(genNode, ctx)

  ctx.withNode("homeworldPlacement"):
    let homeNode = doc.requireNode("homeworldPlacement", ctx)
    result.homeworldPlacement = parseHomeworldPlacement(homeNode, ctx)

  logInfo("Config", "Loaded starmap configuration", "path=", configPath)

## Global configuration instance

var globalStarmapConfig* = loadStarmapConfig()

## Helper to reload configuration (for testing)

proc reloadStarmapConfig*() =
  ## Reload configuration from file
  globalStarmapConfig = loadStarmapConfig()
