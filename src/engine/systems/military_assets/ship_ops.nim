## Ship Operations for EC4X
##
## This module contains logic related to individual ships, such as retrieving
## stats and creating new ship instances.

import std/[options, math, strformat]
import ../../config/ships_config
import ../../config  # For parseShipRole
import ../../types/military/ship_types
import ../../../common/types/units

proc getShipStatsFromConfig(shipClass: ShipClass): ShipStats =
  let cfg = globalShipsConfig
  let configStats = case shipClass
    of ShipClass.Fighter: cfg.fighter
    of ShipClass.Corvette: cfg.corvette
    of ShipClass.Frigate: cfg.frigate
    of ShipClass.Scout: cfg.scout
    of ShipClass.Raider: cfg.raider
    of ShipClass.Destroyer: cfg.destroyer
    of ShipClass.Cruiser: cfg.cruiser
    of ShipClass.LightCruiser: cfg.light_cruiser
    of ShipClass.HeavyCruiser: cfg.heavy_cruiser
    of ShipClass.Battlecruiser: cfg.battlecruiser
    of ShipClass.Battleship: cfg.battleship
    of ShipClass.Dreadnought: cfg.dreadnought
    of ShipClass.SuperDreadnought: cfg.super_dreadnought
    of ShipClass.Carrier: cfg.carrier
    of ShipClass.SuperCarrier: cfg.supercarrier
    of ShipClass.ETAC: cfg.etac
    of ShipClass.TroopTransport: cfg.troop_transport
    of ShipClass.PlanetBreaker: cfg.planetbreaker
  result = ShipStats(
    name: configStats.name,
    class: configStats.class,
    role: parseShipRole(configStats.ship_role),
    attackStrength: configStats.attack_strength,
    defenseStrength: configStats.defense_strength,
    commandCost: configStats.command_cost,
    commandRating: configStats.command_rating,
    techLevel: configStats.tech_level,
    buildCost: configStats.build_cost,
    upkeepCost: configStats.upkeep_cost,
    specialCapability: configStats.special_capability,
    carryLimit:
      if configStats.carry_limit.isSome:
        configStats.carry_limit.get
      else:
        0
  )

proc getShipStats*(shipClass: ShipClass, techLevel: int = 0,
                   configPath: string = "") : ShipStats =
  result = getShipStatsFromConfig(shipClass)
  if techLevel > 1:
    let weaponsMultiplier = pow(1.10, float(techLevel - 1))
    result.attackStrength =
      int(float(result.attackStrength) * weaponsMultiplier)
    result.defenseStrength =
      int(float(result.defenseStrength) * weaponsMultiplier)

proc newShip*(shipClass: ShipClass, techLevel: int = 0,
              name: string = "") : Ship =
  let stats = getShipStats(shipClass, techLevel)
  let shipType = case shipClass
    of ShipClass.ETAC, ShipClass.TroopTransport:
      ShipType.Spacelift
    else:
      ShipType.Military
  Ship(
    shipClass: shipClass,
    shipType: shipType,
    stats: stats,
    isCrippled: false,
    name: name
  )

proc `$`*(ship: Ship): string =
  let status = if ship.isCrippled: " (crippled)" else: ""
  let name = if ship.name.len > 0: " \"" & ship.name & "\"" else: ""
  $ship.shipClass & name & status
