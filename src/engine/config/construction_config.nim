## Construction Configuration Loader
##
## Loads construction times, costs, repair costs, and upkeep from config/construction.kdl
## Allows runtime configuration for construction mechanics

import kdl
import kdl_helpers
import ../../common/logger
import ../types/config

proc parseConstruction(node: KdlNode, ctx: var KdlConfigContext): ConstructionTimesConfig =
  result = ConstructionTimesConfig(
    spaceportTurns: node.requireInt32("spaceportTurns", ctx),
    spaceportDocks: node.requireInt32("spaceportDocks", ctx),
    shipyardTurns: node.requireInt32("shipyardTurns", ctx),
    shipyardDocks: node.requireInt32("shipyardDocks", ctx),
    shipyardRequiresSpaceport: node.requireBool("shipyardRequiresSpaceport", ctx),
    starbaseTurns: node.requireInt32("starbaseTurns", ctx),
    starbaseRequiresShipyard: node.requireBool("starbaseRequiresShipyard", ctx),
    starbaseMaxPerColony: node.requireInt32("starbaseMaxPerColony", ctx),
    planetaryShieldTurns: node.requireInt32("planetaryShieldTurns", ctx),
    planetaryShieldMax: node.requireInt32("planetaryShieldMax", ctx),
    planetaryShieldReplaceOnUpgrade: node.requireBool("planetaryShieldReplaceOnUpgrade", ctx),
    groundBatteryTurns: node.requireInt32("groundBatteryTurns", ctx),
    groundBatteryMax: node.requireInt32("groundBatteryMax", ctx),
    fighterSquadronPlanetBased: node.requireBool("fighterSquadronPlanetBased", ctx)
  )

proc parseRepair(node: KdlNode, ctx: var KdlConfigContext): RepairConfig =
  result = RepairConfig(
    shipRepairTurns: node.requireInt32("shipRepairTurns", ctx),
    shipRepairCostMultiplier: node.requireFloat32("shipRepairCostMultiplier", ctx),
    starbaseRepairCostMultiplier: node.requireFloat32("starbaseRepairCostMultiplier", ctx)
  )

proc parseModifiers(node: KdlNode, ctx: var KdlConfigContext): ModifiersConfig =
  result = ModifiersConfig(
    planetsideConstructionCostMultiplier: node.requireFloat32("planetsideConstructionCostMultiplier", ctx),
    constructionCapacityIncreasePerLevel: node.requireFloat32("constructionCapacityIncreasePerLevel", ctx)
  )

proc parseCosts(node: KdlNode, ctx: var KdlConfigContext): CostsConfig =
  result = CostsConfig(
    spaceportCost: node.requireInt32("spaceportCost", ctx),
    shipyardCost: node.requireInt32("shipyardCost", ctx),
    starbaseCost: node.requireInt32("starbaseCost", ctx),
    groundBatteryCost: node.requireInt32("groundBatteryCost", ctx),
    fighterSquadronCost: node.requireInt32("fighterSquadronCost", ctx),
    planetaryShieldSld1Cost: node.requireInt32("planetaryShieldSld1Cost", ctx),
    planetaryShieldSld2Cost: node.requireInt32("planetaryShieldSld2Cost", ctx),
    planetaryShieldSld3Cost: node.requireInt32("planetaryShieldSld3Cost", ctx),
    planetaryShieldSld4Cost: node.requireInt32("planetaryShieldSld4Cost", ctx),
    planetaryShieldSld5Cost: node.requireInt32("planetaryShieldSld5Cost", ctx),
    planetaryShieldSld6Cost: node.requireInt32("planetaryShieldSld6Cost", ctx)
  )

proc parseUpkeep(node: KdlNode, ctx: var KdlConfigContext): UpkeepConfig =
  result = UpkeepConfig(
    spaceportUpkeep: node.requireInt32("spaceportUpkeep", ctx),
    shipyardUpkeep: node.requireInt32("shipyardUpkeep", ctx),
    starbaseUpkeep: node.requireInt32("starbaseUpkeep", ctx),
    groundBatteryUpkeep: node.requireInt32("groundBatteryUpkeep", ctx),
    planetaryShieldUpkeep: node.requireInt32("planetaryShieldUpkeep", ctx)
  )

proc loadConstructionConfig*(configPath: string): ConstructionConfig =
  ## Load construction configuration from KDL file
  ## Uses kdl_config_helpers for type-safe parsing
  let doc = loadKdlConfig(configPath)
  var ctx = newContext(configPath)

  ctx.withNode("construction"):
    let node = doc.requireNode("construction", ctx)
    result.construction = parseConstruction(node, ctx)

  ctx.withNode("repair"):
    let node = doc.requireNode("repair", ctx)
    result.repair = parseRepair(node, ctx)

  ctx.withNode("modifiers"):
    let node = doc.requireNode("modifiers", ctx)
    result.modifiers = parseModifiers(node, ctx)

  ctx.withNode("costs"):
    let node = doc.requireNode("costs", ctx)
    result.costs = parseCosts(node, ctx)

  ctx.withNode("upkeep"):
    let node = doc.requireNode("upkeep", ctx)
    result.upkeep = parseUpkeep(node, ctx)

  logInfo("Config", "Loaded construction configuration", "path=", configPath)
