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
  let buildCost = node.requirePositiveInt32("buildCost", ctx)
  let maintenancePercent = node.requireFloat32("maintenancePercent", ctx)
  let maintenanceCost = int32(float32(buildCost) * maintenancePercent)

  result = ShipStatsConfig(
    minCST: node.requireRangeInt32("minCST", 1, 10, ctx),
    productionCost: buildCost,
    maintenanceCost: maintenanceCost,
    attackStrength: node.getInt32("attackStrength", 0),
    defenseStrength: node.getInt32("defenseStrength", 0),
    commandCost: node.getInt32("c2Cost", 0),
    commandRating: node.getInt32("crRating", 0),
    carryLimit: node.getInt32("carryLimit", 0),
    buildTime: node.getInt32("buildTime", 0)
  )

proc parseSalvage(node: KdlNode, ctx: var KdlConfigContext): SalvageConfig =
  result = SalvageConfig(
    salvageValueMultiplier: node.requireFloat32("salvageValueMultiplier", ctx)
  )

proc loadShipsConfig*(configPath: string): ShipsConfig =
  ## Load ships configuration from KDL file with validation
  let doc = loadKdlConfig(configPath)
  var ctx = newContext(configPath)

  # Helper to find ship in nested structure
  proc findShip(doc: KdlDoc, shipName: string): Option[KdlNode] =
    for node in doc:
      for child in node.children:
        if child.name == shipName:
          return some(child)
    return none(KdlNode)

  # Parse each ship type with context tracking
  template parseShip(nodeName: string, field: untyped) =
    let nodeOpt = findShip(doc, nodeName)
    if nodeOpt.isSome:
      ctx.withNode(nodeName):
        result.field = parseShipStats(nodeOpt.get, ctx)

  parseShip("corvette", corvette)
  parseShip("frigate", frigate)
  parseShip("destroyer", destroyer)
  parseShip("lightCruiser", lightCruiser)
  parseShip("cruiser", cruiser)
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
  parseShip("planetBreaker", planetbreaker)

  ctx.withNode("salvage"):
    let salvageNode = doc.requireNode("salvage", ctx)
    result.salvage = parseSalvage(salvageNode, ctx)

  logInfo("Config", "Loaded ships configuration", "path=", configPath)
