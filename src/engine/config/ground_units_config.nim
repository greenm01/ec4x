## Ground Units Configuration Loader
##
## Loads ground unit stats from config/ground_units.kdl using nimkdl
## Allows runtime configuration for planetary defenses and invasion forces

import kdl
import kdl_helpers
import ../../common/logger
import ../types/config
import ../types/ground_unit

proc parseGroundUnitStats(
    node: KdlNode, unitType: GroundClass, ctx: var KdlConfigContext
): GroundUnitStatsConfig =
  ## Parse ground unit stats from KDL node
  ## Unified parser for all ground unit types
  result = GroundUnitStatsConfig(
    minCST: node.requireInt32("minCST", ctx),
    productionCost: node.requireInt32("buildCost", ctx),
    maintenanceCost: 0, # Calculated from maintenancePercent elsewhere
    buildTime: 1, # Default
  )

  # Type-specific fields
  case unitType
  of GroundClass.PlanetaryShield:
    result.defenseStrength = node.requireInt32("defenseStrength", ctx)
    result.maxPerPlanet = node.requireInt32("maxPerColony", ctx)
    result.replaceOnUpgrade = node.requireBool("replaceOnUpgrade", ctx)
    result.attackStrength = 0
    result.populationCost = 0
    result.requiresTransport = false
  of GroundClass.GroundBattery:
    result.attackStrength = node.requireInt32("attackStrength", ctx)
    result.defenseStrength = node.requireInt32("defenseStrength", ctx)
    result.maxPerPlanet = 999 # Default
    result.populationCost = 0
    result.requiresTransport = false
    result.replaceOnUpgrade = false
  of GroundClass.Army:
    result.attackStrength = node.requireInt32("attackStrength", ctx)
    result.defenseStrength = node.requireInt32("defenseStrength", ctx)
    result.maxPerPlanet = 999 # Default
    result.populationCost = 0 # Not in current KDL
    result.requiresTransport = false
    result.replaceOnUpgrade = false
  of GroundClass.Marine:
    result.attackStrength = node.requireInt32("attackStrength", ctx)
    result.defenseStrength = node.requireInt32("defenseStrength", ctx)
    result.maxPerPlanet = 999 # Default
    result.populationCost = 0 # Not in current KDL
    result.requiresTransport = node.requireBool("requiresTransport", ctx)
    result.replaceOnUpgrade = false

proc loadGroundUnitsConfig*(configPath: string): GroundUnitsConfig =
  ## Load ground units configuration from KDL file
  ## Uses kdl_config_helpers for type-safe parsing
  ## Builds array indexed by GroundClass for O(1) access
  let doc = loadKdlConfig(configPath)
  var ctx = newContext(configPath)

  # Get the groundUnits parent node
  ctx.withNode("groundUnits"):
    let groundUnitsNode = doc.requireNode("groundUnits", ctx)

    # Parse each unit type and populate array
    for child in groundUnitsNode.children:
      case child.name
      of "planetaryShield":
        ctx.withNode("planetaryShield"):
          result.units[GroundClass.PlanetaryShield] =
            parseGroundUnitStats(child, GroundClass.PlanetaryShield, ctx)
      of "groundBattery":
        ctx.withNode("groundBattery"):
          result.units[GroundClass.GroundBattery] =
            parseGroundUnitStats(child, GroundClass.GroundBattery, ctx)
      of "army":
        ctx.withNode("army"):
          result.units[GroundClass.Army] =
            parseGroundUnitStats(child, GroundClass.Army, ctx)
      of "marine":
        ctx.withNode("marine"):
          result.units[GroundClass.Marine] =
            parseGroundUnitStats(child, GroundClass.Marine, ctx)
      else:
        discard

  logInfo("Config", "Loaded ground units configuration", "path=", configPath)
