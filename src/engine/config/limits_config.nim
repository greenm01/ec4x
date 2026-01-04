## Limits Configuration Loader
##
## Loads game limits and capacities from config/limits.kdl
## Allows runtime configuration for C2, unit counts, fighter capacity, planet limits

import kdl
import kdl_helpers
import ../../common/logger
import ../types/config

proc parseC2Limits(node: KdlNode, ctx: var KdlConfigContext): C2LimitsConfig =
  result = C2LimitsConfig(
    c2ConversionRatio: node.requireFloat32("c2ConversionRatio", ctx),
    c2OverdraftRatio: node.requireFloat32("c2OverdraftRatio", ctx)
  )

proc parseQuantityLimits(
  node: KdlNode,
  ctx: var KdlConfigContext
): QuantityLimitsConfig =
  result = QuantityLimitsConfig(
    maxStarbasesPerColony: node.requireInt32("maxStarbasesPerColony", ctx),
    maxPlanetaryShieldsPerColony:
      node.requireInt32("maxPlanetaryShieldsPerColony", ctx),
    maxPlanetBreakersPerColony:
      node.requireInt32("maxPlanetBreakersPerColony", ctx)
  )

proc parseFighterCapacity(
  node: KdlNode,
  ctx: var KdlConfigContext
): FighterCapacityConfig =
  result = FighterCapacityConfig(
    iuDivisor: node.requireInt32("iuDivisor", ctx),
    violationGracePeriodTurns:
      node.requireInt32("violationGracePeriodTurns", ctx)
  )

proc parsePopulationLimits(
  node: KdlNode,
  ctx: var KdlConfigContext
): PopulationLimitsConfig =
  result = PopulationLimitsConfig(
    minColonyPopulation: node.requireInt32("minColonyPopulation", ctx),
    maxConcurrentTransfers: node.requireInt32("maxConcurrentTransfers", ctx)
  )

proc parsePlanetCapacity(
  node: KdlNode,
  ctx: var KdlConfigContext
): PlanetCapacityConfig =
  ## Parse: planetClass "Extreme" { puMax 20 }
  let planetClass = node.args[0].getString()
  let puMax = node.requireInt32("puMax", ctx)

  result = PlanetCapacityConfig(planetClass: planetClass, puMax: puMax)

proc parseCapacities(node: KdlNode, ctx: var KdlConfigContext): CapacitiesConfig =
  result.planetCapacities = @[]

  for child in node.children:
    if child.name == "planetClass":
      result.planetCapacities.add(parsePlanetCapacity(child, ctx))

proc parseScScaling(
  node: KdlNode,
  ctx: var KdlConfigContext
): ScScalingConfig =
  ## Parse Strategic Command logarithmic scaling parameters
  result = ScScalingConfig(
    systemsPerPlayerDivisor: node.requireFloat32("systemsPerPlayerDivisor", ctx),
    scaleFactor: node.requireFloat32("scaleFactor", ctx)
  )

proc loadLimitsConfig*(configPath: string): LimitsConfig =
  ## Load limits configuration from KDL file
  ## Uses kdl_helpers for type-safe parsing
  let doc = loadKdlConfig(configPath)
  var ctx = newContext(configPath)

  ctx.withNode("c2Limits"):
    let node = doc.requireNode("c2Limits", ctx)
    result.c2Limits = parseC2Limits(node, ctx)

  ctx.withNode("quantityLimits"):
    let node = doc.requireNode("quantityLimits", ctx)
    result.quantityLimits = parseQuantityLimits(node, ctx)

  ctx.withNode("fighterCapacity"):
    let node = doc.requireNode("fighterCapacity", ctx)
    result.fighterCapacity = parseFighterCapacity(node, ctx)

  ctx.withNode("populationLimits"):
    let node = doc.requireNode("populationLimits", ctx)
    result.populationLimits = parsePopulationLimits(node, ctx)

  ctx.withNode("capacities"):
    let node = doc.requireNode("capacities", ctx)
    result.capacities = parseCapacities(node, ctx)

  ctx.withNode("strategicCommandScaling"):
    let node = doc.requireNode("strategicCommandScaling", ctx)
    result.scScaling = parseScScaling(node, ctx)

  logInfo("Config", "Loaded limits configuration", "path=", configPath)
