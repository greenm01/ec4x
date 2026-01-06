## Construction Configuration Loader
##
## Loads construction times, costs, repair costs, and upkeep from config/construction.kdl
## Allows runtime configuration for construction mechanics

import kdl_helpers
import ../../common/logger
import ../types/config

proc loadConstructionConfig*(configPath: string): ConstructionConfig =
  ## Load construction configuration from KDL file
  ## Uses kdl_config_helpers for type-safe parsing
  let doc = loadKdlConfig(configPath)
  var ctx = newContext(configPath)

  # Parse buildTimes to get construction times
  var construction: ConstructionTimesConfig
  ctx.withNode("buildTimes"):
    let timesNode = doc.requireNode("buildTimes", ctx)
    construction.shipTurns = timesNode.requireInt32("ship", ctx)
    construction.armyTurns = timesNode.requireInt32("army", ctx)
    construction.marineTurns = timesNode.requireInt32("marine", ctx)
    construction.groundBatteryTurns = timesNode.requireInt32("groundBattery", ctx)
    construction.planetaryShieldTurns = timesNode.requireInt32("planetaryShield", ctx)
    construction.spaceportTurns = timesNode.requireInt32("spaceport", ctx)
    construction.shipyardTurns = timesNode.requireInt32("shipyard", ctx)
    construction.drydockTurns = timesNode.requireInt32("drydock", ctx)
    construction.starbaseTurns = timesNode.requireInt32("starbase", ctx)
    # Defaults for fields not in KDL (docks/flags moved to facilities.kdl)
    construction.spaceportDocks = 3
    construction.shipyardDocks = 1
    construction.shipyardRequiresSpaceport = true
    construction.starbaseRequiresShipyard = false
    construction.starbaseMaxPerColony = 3
    construction.planetaryShieldMax = 1
    construction.planetaryShieldReplaceOnUpgrade = true
    construction.groundBatteryMax = 10
    construction.fighterSquadronPlanetBased = false
  result.construction = construction

  # Parse repair
  var repair: RepairConfig
  ctx.withNode("repair"):
    let repairNode = doc.requireNode("repair", ctx)
    repair.shipRepairTurns = repairNode.requireInt32("shipRepairTurns", ctx)
    repair.shipRepairCostMultiplier = repairNode.requireFloat32("shipRepairCostMultiplier", ctx)
    repair.starbaseRepairTurns = repairNode.requireInt32("starbaseRepairTurns", ctx)
    repair.starbaseRepairCostMultiplier = repairNode.requireFloat32("starbaseRepairCostMultiplier", ctx)
    repair.starbaseRepairRequires = repairNode.requireString("starbaseRepairRequires", ctx)
    repair.starbaseRepairUsesDockCapacity = repairNode.requireBool("starbaseRepairUsesDockCapacity", ctx)
  result.repair = repair

  # Parse constructionModifiers
  var modifiers: ModifiersConfig
  ctx.withNode("constructionModifiers"):
    let modNode = doc.requireNode("constructionModifiers", ctx)
    modifiers.planetsideConstructionCostMultiplier = modNode.requireFloat32("planetsideShipCostMultiplier", ctx)
    modifiers.constructionCapacityIncreasePerLevel = 0.0  # Default
  result.modifiers = modifiers

  logInfo("Config", "Loaded construction configuration", "path=", configPath)
