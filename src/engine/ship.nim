## Ship types and operations for EC4X
##
## Individual ships with stats, cargo, and operational capabilities.
## Ships are organized into Squadrons (see squadron.nim).
##
## This module defines ship types, cargo handling, and ship construction
## with technology-modified stats from config/ships.toml.

import std/[options, math, strformat]
import ../common/types/units
import ./config/ships_config
import ./config  # For parseShipRole

export ShipClass, ShipType, ShipStats, ShipRole

type
  CargoType* {.pure.} = enum
    ## Type of cargo loaded on transport ships
    None,
    Marines,      # Marine Division (MD) - TroopTransport
    Colonists,    # Population Transfer Unit (PTU) - ETAC
    Supplies      # Generic cargo (future use)

  ShipCargo* = object
    ## Cargo loaded on transport ships (ETAC/TT)
    cargoType*: CargoType
    quantity*: int          # Number of units loaded (0 = empty)
    capacity*: int          # Maximum capacity (CL = Carry Limit)

  Ship* = object
    ## Ship representation with full combat and operational stats
    ## Used for all ship types: combat, intel, expansion, auxiliary,
    ## fighter
    shipClass*: ShipClass
    shipType*: ShipType      # Military or Spacelift (transport)
    stats*: ShipStats
    isCrippled*: bool
    name*: string            # Optional ship name
    cargo*: Option[ShipCargo]  # Cargo for ETAC/TT (Some), None for
                               # combat ships

## Ship class statistics
## Based on EC4X specifications

proc getShipStatsFromConfig(shipClass: ShipClass): ShipStats =
  ## Get base ship stats from config/ships.toml
  ## Uses globalShipsConfig loaded at module initialization

  let cfg = globalShipsConfig

  # Map ShipClass enum to config struct field
  # Note: Starbases are facilities (not in ShipClass, use facilities.toml)
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

  # Convert config format to ShipStats format
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
                   configPath: string = ""): ShipStats =
  ## Get stats for a ship class from config
  ## Stats may be modified by tech level (WEP)
  ##
  ## Uses config/ships.toml loaded at module initialization
  ## configPath parameter ignored (kept for API compatibility)
  ##
  ## Per economy.md Section 4.6: "Upgrades improve the Attack Strength
  ## (AS) and Defense Strength (DS) of combat ships by 10% for each
  ## Weapons level (rounded down)."

  # Get base stats from config
  result = getShipStatsFromConfig(shipClass)

  # Apply WEP tech level modifiers (AS and DS only)
  # Base tech is WEP1 (techLevel = 1), each upgrade adds 10%
  # Formula: stat × (1.10 ^ (techLevel - 1)), rounded down
  if techLevel > 1:
    let weaponsMultiplier = pow(1.10, float(techLevel - 1))
    result.attackStrength =
      int(float(result.attackStrength) * weaponsMultiplier)
    result.defenseStrength =
      int(float(result.defenseStrength) * weaponsMultiplier)

## Ship construction

proc newShip*(shipClass: ShipClass, techLevel: int = 0,
              name: string = ""): Ship =
  ## Create a new ship with stats
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
  ## String representation of ship
  let status = if ship.isCrippled: " (crippled)" else: ""
  let name = if ship.name.len > 0: " \"" & ship.name & "\"" else: ""
  $ship.shipClass & name & status
