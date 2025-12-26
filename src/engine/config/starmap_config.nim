## Starmap Configuration Loader
##
## Loads starmap generation parameters from config/starmap.kdl using nimkdl
## Allows runtime configuration for lane weights and map generation

import kdl
import kdl_config_helpers
import ../../common/logger
import ../types/config

proc parseLaneWeights(node: KdlNode, ctx: var KdlConfigContext): LaneWeightsConfig =
  result = LaneWeightsConfig(
    majorWeight: node.requireFloat32("majorWeight", ctx),
    minorWeight: node.requireFloat32("minorWeight", ctx),
    restrictedWeight: node.requireFloat32("restrictedWeight", ctx)
  )

proc parseGeneration(node: KdlNode, ctx: var KdlConfigContext): GenerationConfig =
  result = GenerationConfig(
    useDistanceMaximization: node.requireBool("useDistanceMaximization", ctx),
    preferVertexPositions: node.requireBool("preferVertexPositions", ctx),
    hubUsesMixedLanes: node.requireBool("hubUsesMixedLanes", ctx)
  )

proc parseHomeworldPlacement(node: KdlNode, ctx: var KdlConfigContext): HomeworldPlacementConfig =
  result = HomeworldPlacementConfig(
    homeworldLaneCount: node.requireInt32("homeworldLaneCount", ctx)
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
