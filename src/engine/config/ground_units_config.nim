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
    minCST: node.requireInt32("minCST", ctx),
    productionCost: node.requireInt32("buildCost", ctx),
    maintenanceCost: 0,  # Calculated from maintenancePercent elsewhere
    defenseStrength: node.requireInt32("defenseStrength", ctx),
    buildTime: 1,  # Default
    maxPerPlanet: node.requireInt32("maxPerColony", ctx),
    sld1BlockChance: 0.0,  # Defined in tech.kdl
    sld2BlockChance: 0.0,
    sld3BlockChance: 0.0,
    sld4BlockChance: 0.0,
    sld5BlockChance: 0.0,
    sld6BlockChance: 0.0,
    shieldDamageReduction: 0.0,  # Defined in tech.kdl
    shieldInvasionDifficulty: 0.0  # Defined in tech.kdl
  )

proc parseGroundBattery(node: KdlNode, ctx: var KdlConfigContext): GroundBatteryConfig =
  result = GroundBatteryConfig(
    minCST: node.requireInt32("minCST", ctx),
    productionCost: node.requireInt32("buildCost", ctx),
    maintenanceCost: 0,  # Calculated from maintenancePercent elsewhere
    attackStrength: node.requireInt32("attackStrength", ctx),
    defenseStrength: node.requireInt32("defenseStrength", ctx),
    buildTime: 1,  # Default
    maxPerPlanet: 999  # Default
  )

proc parseArmy(node: KdlNode, ctx: var KdlConfigContext): ArmyConfig =
  result = ArmyConfig(
    minCST: node.requireInt32("minCST", ctx),
    productionCost: node.requireInt32("buildCost", ctx),
    maintenanceCost: 0,  # Calculated from maintenancePercent elsewhere
    attackStrength: node.requireInt32("attackStrength", ctx),
    defenseStrength: node.requireInt32("defenseStrength", ctx),
    buildTime: 1,  # Default
    maxPerPlanet: 999,  # Default
    populationCost: 0  # Not in current KDL
  )

proc parseMarineDivision(node: KdlNode, ctx: var KdlConfigContext): MarineDivisionConfig =
  result = MarineDivisionConfig(
    minCST: node.requireInt32("minCST", ctx),
    productionCost: node.requireInt32("buildCost", ctx),
    maintenanceCost: 0,  # Calculated from maintenancePercent elsewhere
    attackStrength: node.requireInt32("attackStrength", ctx),
    defenseStrength: node.requireInt32("defenseStrength", ctx),
    buildTime: 1,  # Default
    maxPerPlanet: 999,  # Default
    populationCost: 0  # Not in current KDL
  )

proc loadGroundUnitsConfig*(configPath: string): GroundUnitsConfig =
  ## Load ground units configuration from KDL file
  ## Uses kdl_config_helpers for type-safe parsing
  let doc = loadKdlConfig(configPath)
  var ctx = newContext(configPath)

  # Get the groundUnits parent node
  ctx.withNode("groundUnits"):
    let groundUnitsNode = doc.requireNode("groundUnits", ctx)

    # Parse each unit type from within groundUnits
    for child in groundUnitsNode.children:
      case child.name
      of "planetaryShield":
        ctx.withNode("planetaryShield"):
          result.planetaryShield = parsePlanetaryShield(child, ctx)
      of "groundBattery":
        ctx.withNode("groundBattery"):
          result.groundBattery = parseGroundBattery(child, ctx)
      of "army":
        ctx.withNode("army"):
          result.army = parseArmy(child, ctx)
      of "marine":
        ctx.withNode("marine"):
          result.marineDivision = parseMarineDivision(child, ctx)
      else:
        discard

  logInfo("Config", "Loaded ground units configuration", "path=", configPath)
