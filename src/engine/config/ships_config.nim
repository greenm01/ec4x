## Ships Configuration Loader (KDL Version)
##
## Loads ship statistics from config/ships.kdl using nimkdl
## Demonstrates use of kdl_config_helpers for type-safe parsing

import std/[options]
import kdl
import kdl_helpers
import ../../common/logger
import ../types/config

proc parseShipStats(node: KdlNode, ctx: var KdlConfigContext): ShipStatsConfig =
  ## Parse ship stats from KDL node with validation
  result = ShipStatsConfig(
    description: node.requireString("description", ctx),
    minCST: node.requireRangeInt32("minCST", 1, 10, ctx),
    productionCost: node.requirePositiveInt32("productionCost", ctx),
    maintenanceCost: node.requireNonNegativeInt32("maintenanceCost", ctx),
    attackStrength: node.requireNonNegativeInt32("attackStrength", ctx),
    defenseStrength: node.requireNonNegativeInt32("defenseStrength", ctx),
    commandCost: node.requireNonNegativeInt32("commandCost", ctx),
    commandRating: node.requireNonNegativeInt32("commandRating", ctx),
    carryLimit: node.requireNonNegativeInt32("carryLimit", ctx),
    buildTime: node.requireNonNegativeInt32("buildTime", ctx)
  )

proc parseSalvage(node: KdlNode, ctx: var KdlConfigContext): SalvageConfig =
  result = SalvageConfig(
    salvageValueMultiplier: node.requireFloat32("salvageValueMultiplier", ctx),
    emergencySalvageMultiplier: node.requireFloat32("emergencySalvageMultiplier", ctx)
  )

proc loadShipsConfig*(configPath: string): ShipsConfig =
  ## Load ships configuration from KDL file with validation
  let doc = loadKdlConfig(configPath)
  var ctx = newContext(configPath)
  
  # Parse each ship type with context tracking
  template parseShip(nodeName: string, field: untyped) =
    let nodeOpt = doc.findNode(nodeName)
    if nodeOpt.isSome:
      ctx.withNode(nodeName):
        result.field = parseShipStats(nodeOpt.get, ctx)
  
  parseShip("corvette", corvette)
  parseShip("frigate", frigate)
  parseShip("destroyer", destroyer)
  parseShip("lightCruiser", lightCruiser)
  parseShip("heavyCruiser", heavyCruiser)
  parseShip("battlecruiser", battlecruiser)
  parseShip("battleship", battleship)
  parseShip("dreadnought", dreadnought)
  parseShip("superDreadnought", superDreadnought)
  parseShip("carrier", carrier)
  parseShip("supercarrier", supercarrier)
  parseShip("raider", raider)
  parseShip("scout", scout)
  parseShip("etac", etac)
  parseShip("troopTransport", troopTransport)
  parseShip("fighter", fighter)
  parseShip("planetbreaker", planetbreaker)
  
  ctx.withNode("salvage"):
    let salvageNode = doc.requireNode("salvage", ctx)
    result.salvage = parseSalvage(salvageNode, ctx)

  logInfo("Config", "Loaded ships configuration", "path=", configPath)
