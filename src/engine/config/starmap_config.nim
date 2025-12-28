## Starmap Configuration Loader
##
## Loads starmap generation parameters from config/starmap.kdl using nimkdl
## Allows runtime configuration for lane weights and map generation

import kdl
import kdl_helpers
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

proc parseHomeworldPlacement(
    node: KdlNode, ctx: var KdlConfigContext
): HomeworldPlacementConfig =
  result = HomeworldPlacementConfig(
    homeworldLaneCount: node.requireInt32("homeworldLaneCount", ctx)
  )

proc parsePlanetNames(node: KdlNode, ctx: var KdlConfigContext): PlanetNamesConfig =
  ## Parse planetNames node with child 'name' entries
  var names: seq[string] = @[]

  # Iterate through all child nodes named "name"
  for child in node.children:
    if child.name == "name" and child.args.len > 0:
      # Each name node has a string argument
      let arg = child.args[0]
      if arg.kind == KValKind.KString:
        names.add(arg.getString())

  result = PlanetNamesConfig(names: names)

proc loadStarmapConfig*(configPath: string): StarmapConfig =
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

  # Load planet names from separate file
  ctx.withNode("planetNames"):
    let planetsDoc = loadKdlConfig("config/planets.kdl")
    var planetsCtx = newContext("config/planets.kdl")
    let namesNode = planetsDoc.requireNode("planetNames", planetsCtx)
    result.planetNames = parsePlanetNames(namesNode, planetsCtx)

  logInfo(
    "Config",
    "Loaded starmap configuration",
    "path=",
    configPath,
    " planetNames=",
    result.planetNames.names.len
  )
