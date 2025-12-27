## Ground Units Configuration Loader
##
## Loads ground unit stats from config/ground_units.kdl using nimkdl
## Allows runtime configuration for planetary defenses and invasion forces

import kdl
import kdl_helpers
import ../../common/logger
import ../types/config

proc parsePlanetaryShield(node: KdlNode, ctx: var KdlConfigContext): PlanetaryShieldConfig =
  result = PlanetaryShieldConfig(
    description: node.requireString("description", ctx),
    minCST: node.requireInt32("minCST", ctx),
    productionCost: node.requireInt32("buildCost", ctx),
    maintenanceCost: node.requireInt32("upkeepCost", ctx),
    defenseStrength: node.requireInt32("defenseStrength", ctx),
    buildTime: node.requireInt32("buildTime", ctx),
    maxPerPlanet: node.requireInt32("maxPerPlanet", ctx),
    sld1BlockChance: node.requireFloat32("sld1BlockChance", ctx),
    sld2BlockChance: node.requireFloat32("sld2BlockChance", ctx),
    sld3BlockChance: node.requireFloat32("sld3BlockChance", ctx),
    sld4BlockChance: node.requireFloat32("sld4BlockChance", ctx),
    sld5BlockChance: node.requireFloat32("sld5BlockChance", ctx),
    sld6BlockChance: node.requireFloat32("sld6BlockChance", ctx),
    shieldDamageReduction: node.requireFloat32("shieldDamageReduction", ctx),
    shieldInvasionDifficulty: node.requireFloat32("shieldInvasionDifficulty", ctx)
  )

proc parseGroundBattery(node: KdlNode, ctx: var KdlConfigContext): GroundBatteryConfig =
  result = GroundBatteryConfig(
    description: node.requireString("description", ctx),
    minCST: node.requireInt32("minCST", ctx),
    productionCost: node.requireInt32("buildCost", ctx),
    maintenanceCost: node.requireInt32("upkeepCost", ctx),
    defenseStrength: node.requireInt32("defenseStrength", ctx),
    buildTime: node.requireInt32("buildTime", ctx),
    maxPerPlanet: node.requireInt32("maxPerPlanet", ctx)
  )

proc parseArmy(node: KdlNode, ctx: var KdlConfigContext): ArmyConfig =
  result = ArmyConfig(
    description: node.requireString("description", ctx),
    minCST: node.requireInt32("minCST", ctx),
    productionCost: node.requireInt32("buildCost", ctx),
    maintenanceCost: node.requireInt32("upkeepCost", ctx),
    defenseStrength: node.requireInt32("defenseStrength", ctx),
    buildTime: node.requireInt32("buildTime", ctx),
    maxPerPlanet: node.requireInt32("maxPerPlanet", ctx),
    populationCost: node.requireInt32("populationCost", ctx)
  )

proc parseMarineDivision(node: KdlNode, ctx: var KdlConfigContext): MarineDivisionConfig =
  result = MarineDivisionConfig(
    description: node.requireString("description", ctx),
    minCST: node.requireInt32("minCST", ctx),
    productionCost: node.requireInt32("buildCost", ctx),
    maintenanceCost: node.requireInt32("upkeepCost", ctx),
    defenseStrength: node.requireInt32("defenseStrength", ctx),
    buildTime: node.requireInt32("buildTime", ctx),
    maxPerPlanet: node.requireInt32("maxPerPlanet", ctx),
    populationCost: node.requireInt32("populationCost", ctx)
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
