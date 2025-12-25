## Construction Configuration Loader
##
## Loads construction times, costs, repair costs, and upkeep from config/construction.kdl
## Allows runtime configuration for construction mechanics

import kdl
import kdl_config_helpers
import ../../common/logger

type
  ConstructionTimesConfig* = object
    spaceportTurns*: int32
    spaceportDocks*: int32
    shipyardTurns*: int32
    shipyardDocks*: int32
    shipyardRequiresSpaceport*: bool
    starbaseTurns*: int32
    starbaseRequiresShipyard*: bool
    starbaseMaxPerColony*: int32
    planetaryShieldTurns*: int32
    planetaryShieldMax*: int32
    planetaryShieldReplaceOnUpgrade*: bool
    groundBatteryTurns*: int32
    groundBatteryMax*: int32
    fighterSquadronPlanetBased*: bool

  RepairConfig* = object
    shipRepairTurns*: int32
    shipRepairCostMultiplier*: float32
    starbaseRepairCostMultiplier*: float32

  ModifiersConfig* = object
    planetsideConstructionCostMultiplier*: float32
    constructionCapacityIncreasePerLevel*: float32

  CostsConfig* = object
    spaceportCost*: int32
    shipyardCost*: int32
    starbaseCost*: int32
    groundBatteryCost*: int32
    fighterSquadronCost*: int32
    planetaryShieldSld1Cost*: int32
    planetaryShieldSld2Cost*: int32
    planetaryShieldSld3Cost*: int32
    planetaryShieldSld4Cost*: int32
    planetaryShieldSld5Cost*: int32
    planetaryShieldSld6Cost*: int32

  UpkeepConfig* = object
    spaceportUpkeep*: int32
    shipyardUpkeep*: int32
    starbaseUpkeep*: int32
    groundBatteryUpkeep*: int32
    planetaryShieldUpkeep*: int32

  ConstructionConfig* = object ## Complete construction configuration loaded from KDL
    construction*: ConstructionTimesConfig
    repair*: RepairConfig
    modifiers*: ModifiersConfig
    costs*: CostsConfig
    upkeep*: UpkeepConfig

proc parseConstruction(node: KdlNode, ctx: var KdlConfigContext): ConstructionTimesConfig =
  result = ConstructionTimesConfig(
    spaceportTurns: node.requireInt("spaceportTurns", ctx).int32,
    spaceportDocks: node.requireInt("spaceportDocks", ctx).int32,
    shipyardTurns: node.requireInt("shipyardTurns", ctx).int32,
    shipyardDocks: node.requireInt("shipyardDocks", ctx).int32,
    shipyardRequiresSpaceport: node.requireBool("shipyardRequiresSpaceport", ctx),
    starbaseTurns: node.requireInt("starbaseTurns", ctx).int32,
    starbaseRequiresShipyard: node.requireBool("starbaseRequiresShipyard", ctx),
    starbaseMaxPerColony: node.requireInt("starbaseMaxPerColony", ctx).int32,
    planetaryShieldTurns: node.requireInt("planetaryShieldTurns", ctx).int32,
    planetaryShieldMax: node.requireInt("planetaryShieldMax", ctx).int32,
    planetaryShieldReplaceOnUpgrade: node.requireBool("planetaryShieldReplaceOnUpgrade", ctx),
    groundBatteryTurns: node.requireInt("groundBatteryTurns", ctx).int32,
    groundBatteryMax: node.requireInt("groundBatteryMax", ctx).int32,
    fighterSquadronPlanetBased: node.requireBool("fighterSquadronPlanetBased", ctx)
  )

proc parseRepair(node: KdlNode, ctx: var KdlConfigContext): RepairConfig =
  result = RepairConfig(
    shipRepairTurns: node.requireInt("shipRepairTurns", ctx).int32,
    shipRepairCostMultiplier: node.requireFloat("shipRepairCostMultiplier", ctx).float32,
    starbaseRepairCostMultiplier: node.requireFloat("starbaseRepairCostMultiplier", ctx).float32
  )

proc parseModifiers(node: KdlNode, ctx: var KdlConfigContext): ModifiersConfig =
  result = ModifiersConfig(
    planetsideConstructionCostMultiplier: node.requireFloat("planetsideConstructionCostMultiplier", ctx).float32,
    constructionCapacityIncreasePerLevel: node.requireFloat("constructionCapacityIncreasePerLevel", ctx).float32
  )

proc parseCosts(node: KdlNode, ctx: var KdlConfigContext): CostsConfig =
  result = CostsConfig(
    spaceportCost: node.requireInt("spaceportCost", ctx).int32,
    shipyardCost: node.requireInt("shipyardCost", ctx).int32,
    starbaseCost: node.requireInt("starbaseCost", ctx).int32,
    groundBatteryCost: node.requireInt("groundBatteryCost", ctx).int32,
    fighterSquadronCost: node.requireInt("fighterSquadronCost", ctx).int32,
    planetaryShieldSld1Cost: node.requireInt("planetaryShieldSld1Cost", ctx).int32,
    planetaryShieldSld2Cost: node.requireInt("planetaryShieldSld2Cost", ctx).int32,
    planetaryShieldSld3Cost: node.requireInt("planetaryShieldSld3Cost", ctx).int32,
    planetaryShieldSld4Cost: node.requireInt("planetaryShieldSld4Cost", ctx).int32,
    planetaryShieldSld5Cost: node.requireInt("planetaryShieldSld5Cost", ctx).int32,
    planetaryShieldSld6Cost: node.requireInt("planetaryShieldSld6Cost", ctx).int32
  )

proc parseUpkeep(node: KdlNode, ctx: var KdlConfigContext): UpkeepConfig =
  result = UpkeepConfig(
    spaceportUpkeep: node.requireInt("spaceportUpkeep", ctx).int32,
    shipyardUpkeep: node.requireInt("shipyardUpkeep", ctx).int32,
    starbaseUpkeep: node.requireInt("starbaseUpkeep", ctx).int32,
    groundBatteryUpkeep: node.requireInt("groundBatteryUpkeep", ctx).int32,
    planetaryShieldUpkeep: node.requireInt("planetaryShieldUpkeep", ctx).int32
  )

proc loadConstructionConfig*(
    configPath: string = "config/construction.kdl"
): ConstructionConfig =
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

## Global configuration instance

var globalConstructionConfig* = loadConstructionConfig()

## Helper to reload configuration (for testing)

proc reloadConstructionConfig*() =
  ## Reload configuration from file
  globalConstructionConfig = loadConstructionConfig()
