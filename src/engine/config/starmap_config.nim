## Starmap Configuration Loader
##
## Loads starmap generation parameters from config/starmap.kdl using nimkdl
## Allows runtime configuration for lane weights and map generation

import kdl
import kdl_helpers
import ../../common/logger
import ../types/config

proc parseLaneWeights(node: KdlNode, ctx: var KdlConfigContext): LaneWeightsConfig =
  ## Parse lanes { distribution { major 0.50 minor 0.35 restricted 0.15 } }
  var found = false
  var distNode: KdlNode

  for child in node.children:
    if child.name == "distribution":
      distNode = child
      found = true
      break

  if not found:
    raise newConfigError("Missing 'distribution' node in 'lanes'")

  result = LaneWeightsConfig(
    majorWeight: distNode.requireFloat32("major", ctx),
    minorWeight: distNode.requireFloat32("minor", ctx),
    restrictedWeight: distNode.requireFloat32("restricted", ctx)
  )

proc parseGeneration(hubNode: KdlNode, ctx: var KdlConfigContext): GenerationConfig =
  ## Parse hub { mixedLanes #true ... } - other fields have defaults
  result = GenerationConfig(
    useDistanceMaximization: true,  # Default: always use distance maximization
    preferVertexPositions: true,     # Default: prefer vertex positions
    hubUsesMixedLanes: hubNode.requireBool("mixedLanes", ctx)
  )

proc parseHomeworldPlacement(
    node: KdlNode, ctx: var KdlConfigContext
): HomeworldPlacementConfig =
  ## Parse homeworld { guaranteedLaneCount 3 ... }
  result = HomeworldPlacementConfig(
    homeworldLaneCount: node.requireInt32("guaranteedLaneCount", ctx)
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

  ctx.withNode("lanes"):
    let laneNode = doc.requireNode("lanes", ctx)
    result.laneWeights = parseLaneWeights(laneNode, ctx)

  ctx.withNode("hub"):
    let hubNode = doc.requireNode("hub", ctx)
    result.generation = parseGeneration(hubNode, ctx)

  ctx.withNode("homeworld"):
    let homeNode = doc.requireNode("homeworld", ctx)
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
