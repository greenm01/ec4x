## Ships Configuration Loader (KDL Version)
##
## Loads ship statistics from config/ships.kdl using nimkdl
## Demonstrates use of kdl_config_helpers for type-safe parsing

import std/[options]
import kdl
import kdl_config_helpers
import ../../common/logger
import ../types/ship

export ShipClass

type
  ShipStatsConfig* = object
    attackStrength*: int32
    defenseStrength*: int32
    commandCost*: int32
    commandRating*: int32
    carryLimit*: int32
    minCST*: int32
    productionCost*: int32
    maintenanceCost*: int32

  ShipsConfig* = object
    corvette*: ShipStatsConfig
    frigate*: ShipStatsConfig
    destroyer*: ShipStatsConfig
    lightCruiser*: ShipStatsConfig
    heavyCruiser*: ShipStatsConfig
    battlecruiser*: ShipStatsConfig
    battleship*: ShipStatsConfig
    dreadnought*: ShipStatsConfig
    superDreadnought*: ShipStatsConfig
    planetbreaker*: ShipStatsConfig
    carrier*: ShipStatsConfig
    supercarrier*: ShipStatsConfig
    fighter*: ShipStatsConfig
    raider*: ShipStatsConfig
    scout*: ShipStatsConfig
    etac*: ShipStatsConfig
    troopTransport*: ShipStatsConfig

proc parseShipStats(node: KdlNode, ctx: var KdlConfigContext): ShipStatsConfig =
  ## Parse ship stats from KDL node with validation
  result = ShipStatsConfig(
    attackStrength: node.requireNonNegativeInt("attackStrength", ctx).int32,
    defenseStrength: node.requireNonNegativeInt("defenseStrength", ctx).int32,
    commandCost: node.requireNonNegativeInt("commandCost", ctx).int32,
    commandRating: node.requireNonNegativeInt("commandRating", ctx).int32,
    minCST: node.requireRangeInt("minCST", 1, 10, ctx).int32,
    productionCost: node.requirePositiveInt("productionCost", ctx).int32,
    maintenanceCost: node.requireNonNegativeInt("maintenanceCost", ctx).int32,
    carryLimit: node.requireNonNegativeInt("carryLimit", ctx).int32
  )

proc loadShipsConfig*(configPath: string = "config/ships.kdl"): ShipsConfig =
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
  
  logInfo("Config", "Loaded ships configuration", "path=", configPath)

## Global configuration instance
var globalShipsConfig* = loadShipsConfig()

proc reloadShipsConfig*() =
  ## Reload configuration from file
  globalShipsConfig = loadShipsConfig()

proc getShipConfig*(shipClass: ShipClass): ShipStatsConfig =
  ## Get configuration for a ship class
  case shipClass
  of ShipClass.Fighter: globalShipsConfig.fighter
  of ShipClass.Corvette: globalShipsConfig.corvette
  of ShipClass.Frigate: globalShipsConfig.frigate
  of ShipClass.Scout: globalShipsConfig.scout
  of ShipClass.Raider: globalShipsConfig.raider
  of ShipClass.Destroyer: globalShipsConfig.destroyer
  of ShipClass.LightCruiser: globalShipsConfig.lightCruiser
  of ShipClass.HeavyCruiser: globalShipsConfig.heavyCruiser
  of ShipClass.Battlecruiser: globalShipsConfig.battlecruiser
  of ShipClass.Battleship: globalShipsConfig.battleship
  of ShipClass.Dreadnought: globalShipsConfig.dreadnought
  of ShipClass.SuperDreadnought: globalShipsConfig.superDreadnought
  of ShipClass.Carrier: globalShipsConfig.carrier
  of ShipClass.SuperCarrier: globalShipsConfig.supercarrier
  of ShipClass.ETAC: globalShipsConfig.etac
  of ShipClass.TroopTransport: globalShipsConfig.troopTransport
  of ShipClass.PlanetBreaker: globalShipsConfig.planetbreaker
