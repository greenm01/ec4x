## Ground Units Configuration Loader
##
## Loads ground unit stats from config/ground_units.kdl using nimkdl
## Allows runtime configuration for planetary defenses and invasion forces

import kdl
import kdl_config_helpers
import ../../common/logger
import ../types/config

proc parsePlanetaryShield(node: KdlNode, ctx: var KdlConfigContext): PlanetaryShieldConfig =
  result = PlanetaryShieldConfig(
    cstMin: node.requireInt("cstMin", ctx),
    buildCost: node.requireInt("buildCost", ctx),
    upkeepCost: node.requireInt("upkeepCost", ctx),
    attackStrength: node.requireInt("attackStrength", ctx),
    defenseStrength: node.requireInt("defenseStrength", ctx),
    description: node.requireString("description", ctx),
    buildTime: node.requireInt("buildTime", ctx),
    maxPerPlanet: node.requireInt("maxPerPlanet", ctx),
    salvageRequired: node.requireBool("salvageRequired", ctx)
  )

proc parseGroundBattery(node: KdlNode, ctx: var KdlConfigContext): GroundBatteryConfig =
  result = GroundBatteryConfig(
    cstMin: node.requireInt("cstMin", ctx),
    buildCost: node.requireInt("buildCost", ctx),
    upkeepCost: node.requireInt("upkeepCost", ctx),
    maintenancePercent: node.requireInt("maintenancePercent", ctx),
    attackStrength: node.requireInt("attackStrength", ctx),
    defenseStrength: node.requireInt("defenseStrength", ctx),
    description: node.requireString("description", ctx),
    buildTime: node.requireInt("buildTime", ctx),
    maxPerPlanet: node.requireInt("maxPerPlanet", ctx)
  )

proc parseArmy(node: KdlNode, ctx: var KdlConfigContext): ArmyConfig =
  result = ArmyConfig(
    cstMin: node.requireInt("cstMin", ctx),
    buildCost: node.requireInt("buildCost", ctx),
    upkeepCost: node.requireInt("upkeepCost", ctx),
    maintenancePercent: node.requireInt("maintenancePercent", ctx),
    attackStrength: node.requireInt("attackStrength", ctx),
    defenseStrength: node.requireInt("defenseStrength", ctx),
    description: node.requireString("description", ctx),
    buildTime: node.requireInt("buildTime", ctx),
    maxPerPlanet: node.requireInt("maxPerPlanet", ctx),
    populationCost: node.requireInt("populationCost", ctx)
  )

proc parseMarineDivision(node: KdlNode, ctx: var KdlConfigContext): MarineDivisionConfig =
  result = MarineDivisionConfig(
    cstMin: node.requireInt("cstMin", ctx),
    buildCost: node.requireInt("buildCost", ctx),
    upkeepCost: node.requireInt("upkeepCost", ctx),
    maintenancePercent: node.requireInt("maintenancePercent", ctx),
    attackStrength: node.requireInt("attackStrength", ctx),
    defenseStrength: node.requireInt("defenseStrength", ctx),
    description: node.requireString("description", ctx),
    buildTime: node.requireInt("buildTime", ctx),
    maxPerPlanet: node.requireInt("maxPerPlanet", ctx),
    requiresTransport: node.requireBool("requiresTransport", ctx),
    populationCost: node.requireInt("populationCost", ctx)
  )

proc loadGroundUnitsConfig*(
    configPath: string = "config/ground_units.kdl"
): GroundUnitsConfig =
  ## Load ground units configuration from KDL file
  ## Uses kdl_config_helpers for type-safe parsing
  let doc = loadKdlConfig(configPath)
  var ctx = newContext(configPath)

  ctx.withNode("planetaryShield"):
    let shieldNode = doc.requireNode("planetaryShield", ctx)
    result.planetaryShield = parsePlanetaryShield(shieldNode, ctx)

  ctx.withNode("groundBattery"):
    let batteryNode = doc.requireNode("groundBattery", ctx)
    result.groundBattery = parseGroundBattery(batteryNode, ctx)

  ctx.withNode("army"):
    let armyNode = doc.requireNode("army", ctx)
    result.army = parseArmy(armyNode, ctx)

  ctx.withNode("marineDivision"):
    let marineNode = doc.requireNode("marineDivision", ctx)
    result.marineDivision = parseMarineDivision(marineNode, ctx)

  logInfo("Config", "Loaded ground units configuration", "path=", configPath)

## Global configuration instance

var globalGroundUnitsConfig* = loadGroundUnitsConfig()

## Helper to reload configuration (for testing)

proc reloadGroundUnitsConfig*() =
  ## Reload configuration from file
  globalGroundUnitsConfig = loadGroundUnitsConfig()
