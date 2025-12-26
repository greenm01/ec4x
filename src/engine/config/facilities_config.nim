## Facilities Configuration Loader
##
## Loads facility stats from config/facilities.kdl using nimkdl
## Allows runtime configuration for spaceports and shipyards

import kdl
import kdl_config_helpers
import ../../common/logger
import ../types/config

proc parseSpaceport(node: KdlNode, ctx: var KdlConfigContext): SpaceportConfig =
  result = SpaceportConfig(
    cstMin: node.requireInt("cstMin", ctx),
    buildCost: node.requireInt("buildCost", ctx),
    upkeepCost: node.requireInt("upkeepCost", ctx),
    defenseStrength: node.requireInt("defenseStrength", ctx),
    carryLimit: node.requireInt("carryLimit", ctx),
    description: node.requireString("description", ctx),
    buildTime: node.requireInt("buildTime", ctx),
    docks: node.requireInt("docks", ctx),
    maxPerPlanet: node.requireInt("maxPerPlanet", ctx),
    requiredForShipyard: node.requireBool("requiredForShipyard", ctx)
  )

proc parseShipyard(node: KdlNode, ctx: var KdlConfigContext): ShipyardConfig =
  result = ShipyardConfig(
    cstMin: node.requireInt("cstMin", ctx),
    buildCost: node.requireInt("buildCost", ctx),
    upkeepCost: node.requireInt("upkeepCost", ctx),
    defenseStrength: node.requireInt("defenseStrength", ctx),
    carryLimit: node.requireInt("carryLimit", ctx),
    description: node.requireString("description", ctx),
    buildTime: node.requireInt("buildTime", ctx),
    docks: node.requireInt("docks", ctx),
    maxPerPlanet: node.requireInt("maxPerPlanet", ctx),
    requiresSpaceport: node.requireBool("requiresSpaceport", ctx),
    fixedOrbit: node.requireBool("fixedOrbit", ctx)
  )

proc parseDrydock(node: KdlNode, ctx: var KdlConfigContext): DrydockConfig =
  result = DrydockConfig(
    cstMin: node.requireInt("cstMin", ctx),
    buildCost: node.requireInt("buildCost", ctx),
    upkeepCost: node.requireInt("upkeepCost", ctx),
    defenseStrength: node.requireInt("defenseStrength", ctx),
    carryLimit: node.requireInt("carryLimit", ctx),
    description: node.requireString("description", ctx),
    buildTime: node.requireInt("buildTime", ctx),
    docks: node.requireInt("docks", ctx),
    maxPerPlanet: node.requireInt("maxPerPlanet", ctx),
    requiresSpaceport: node.requireBool("requiresSpaceport", ctx),
    fixedOrbit: node.requireBool("fixedOrbit", ctx),
    repairOnly: node.requireBool("repairOnly", ctx)
  )

proc parseStarbase(node: KdlNode, ctx: var KdlConfigContext): StarbaseConfig =
  result = StarbaseConfig(
    cstMin: node.requireInt("cstMin", ctx),
    buildCost: node.requireInt("buildCost", ctx),
    upkeepCost: node.requireInt("upkeepCost", ctx),
    defenseStrength: node.requireInt("defenseStrength", ctx),
    attackStrength: node.requireInt("attackStrength", ctx),
    description: node.requireString("description", ctx),
    buildTime: node.requireInt("buildTime", ctx),
    maxPerPlanet: node.requireInt("maxPerPlanet", ctx),
    requiresSpaceport: node.requireBool("requiresSpaceport", ctx),
    fixedOrbit: node.requireBool("fixedOrbit", ctx),
    economicLiftBonus: node.requireInt("economicLiftBonus", ctx),
    growthBonus: node.requireFloat("growthBonus", ctx)
  )

proc parseConstruction(node: KdlNode, ctx: var KdlConfigContext): ConstructionConfig =
  result = ConstructionConfig(
    repairRatePerTurn: node.requireFloat("repairRatePerTurn", ctx),
    multipleDocksAllowed: node.requireBool("multipleDocksAllowed", ctx)
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

  ctx.withNode("construction"):
    let node = doc.requireNode("construction", ctx)
    result.construction = parseConstruction(node, ctx)

  logInfo("Config", "Loaded facilities configuration", "path=", configPath)

## Global configuration instance

var globalFacilitiesConfig* = loadFacilitiesConfig()

## Helper to reload configuration (for testing)

proc reloadFacilitiesConfig*() =
  ## Reload configuration from file
  globalFacilitiesConfig = loadFacilitiesConfig()
