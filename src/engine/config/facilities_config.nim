## Facilities Configuration Loader
##
## Loads facility stats from config/facilities.kdl using nimkdl
## Allows runtime configuration for spaceports and shipyards

import kdl
import kdl_helpers
import ../../common/logger
import ../types/config

proc parseSpaceport(node: KdlNode, ctx: var KdlConfigContext): SpaceportConfig =
  result = SpaceportConfig(
    description: node.requireString("description", ctx),
    minCST: node.requireInt32("minCST", ctx),
    productionCost: node.requireInt32("productionCost", ctx),
    maintenanceCost: node.requireInt32("maintenanceCost", ctx),
    defenseStrength: node.requireInt32("defenseStrength", ctx),
    buildTime: node.requireInt32("buildTime", ctx),
    docks: node.requireInt32("docks", ctx),
    maxPerPlanet: node.requireInt32("maxPerPlanet", ctx),
    requiredForShipyard: node.requireBool("requiredForShipyard", ctx)
  )

proc parseShipyard(node: KdlNode, ctx: var KdlConfigContext): ShipyardConfig =
  result = ShipyardConfig(
    description: node.requireString("description", ctx),
    minCST: node.requireInt32("minCST", ctx),
    productionCost: node.requireInt32("productionCost", ctx),
    maintenanceCost: node.requireInt32("maintenanceCost", ctx),
    defenseStrength: node.requireInt32("defenseStrength", ctx),
    buildTime: node.requireInt32("buildTime", ctx),
    docks: node.requireInt32("docks", ctx),
    maxPerPlanet: node.requireInt32("maxPerPlanet", ctx),
    requiresSpaceport: node.requireBool("requiresSpaceport", ctx)
  )

proc parseDrydock(node: KdlNode, ctx: var KdlConfigContext): DrydockConfig =
  result = DrydockConfig(
    description: node.requireString("description", ctx),
    minCST: node.requireInt32("minCST", ctx),
    productionCost: node.requireInt32("productionCost", ctx),
    maintenanceCost: node.requireInt32("maintenanceCost", ctx),
    defenseStrength: node.requireInt32("defenseStrength", ctx),
    buildTime: node.requireInt32("buildTime", ctx),
    docks: node.requireInt32("docks", ctx),
    maxPerPlanet: node.requireInt32("maxPerPlanet", ctx),
    requiresSpaceport: node.requireBool("requiresSpaceport", ctx)
  )

proc parseStarbase(node: KdlNode, ctx: var KdlConfigContext): StarbaseConfig =
  result = StarbaseConfig(
    description: node.requireString("description", ctx),
    minCST: node.requireInt32("minCST", ctx),
    productionCost: node.requireInt32("productionCost", ctx),
    maintenanceCost: node.requireInt32("maintenanceCost", ctx),
    defenseStrength: node.requireInt32("defenseStrength", ctx),
    buildTime: node.requireInt32("buildTime", ctx),
    maxPerPlanet: node.requireInt32("maxPerPlanet", ctx),
    requiresSpaceport: node.requireBool("requiresSpaceport", ctx),
    economicLiftBonus: node.requireInt32("economicLiftBonus", ctx),
    growthBonus: node.requireFloat32("growthBonus", ctx)
  )

proc loadFacilitiesConfig*(
    configPath: string = "config/facilities.kdl"
): FacilitiesConfig =
  ## Load facilities configuration from KDL file
  ## Uses kdl_config_helpers for type-safe parsing
  let doc = loadKdlConfig(configPath)
  var ctx = newContext(configPath)

  ctx.withNode("spaceport"):
    let node = doc.requireNode("spaceport", ctx)
    result.spaceport = parseSpaceport(node, ctx)

  ctx.withNode("shipyard"):
    let node = doc.requireNode("shipyard", ctx)
    result.shipyard = parseShipyard(node, ctx)

  ctx.withNode("drydock"):
    let node = doc.requireNode("drydock", ctx)
    result.drydock = parseDrydock(node, ctx)

  ctx.withNode("starbase"):
    let node = doc.requireNode("starbase", ctx)
    result.starbase = parseStarbase(node, ctx)

  logInfo("Config", "Loaded facilities configuration", "path=", configPath)
