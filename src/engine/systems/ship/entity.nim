## Ship Entity - Business logic for individual ships
##
## Individual ships with stats, cargo, and operational capabilities.
## Ships are organized into Squadrons (see ../squadron/entity.nim).
##
## This module provides ship business logic including:
## - Config-based stat loading with tech modifiers
## - Ship construction and initialization
## - Cargo management for transport ships (ETAC/TroopTransport)
## - Ship capability queries
##
## ARCHITECTURE:
## - Pure business logic (no index management)
## - Reads from config/ships.toml via globalShipsConfig
## - Used by squadron/entity and production/commissioning

import std/[options, math, strutils]
import ../../types/[core, ship, config]
import ../../globals

export ShipClass, ShipRole, ShipStats, Ship, ShipCargo, CargoClass, ShipId

## Config Data Access (non-WEP stats)

proc getShipConfigStats(shipClass: ShipClass): ShipStatsConfig =
  ## Get full config stats for a ship class from config/ships.kdl
  ## Used for looking up non-WEP stats (role, costs, CC, CR, carry limit)
  ## Direct array access - O(1) lookup
  gameConfig.ships.ships[shipClass]

proc getShipStats*(shipClass: ShipClass, weaponsTech: int32 = 1): ShipStats =
  ## Calculate WEP-modified stats for a ship class
  ## Returns instance-specific stats (AS, DS, WEP level)
  ## All other stats looked up via getShipConfigStats()
  ##
  ## Per docs/specs/04-research_development.md Section 4.3:
  ## "Each WEP tier increases AS and DS by 10% per level"
  ## Formula: stat × (1.10 ^ (WEP_level - 1)), rounded down
  ##
  ## WEP I (level 1) = base stats (no multiplier)
  ## WEP II (level 2) = +10%
  ## WEP III (level 3) = +21% (compound)
  ## etc.

  let configStats = getShipConfigStats(shipClass)
  let baseAS = configStats.attackStrength
  let baseDS = configStats.defenseStrength

  # Apply WEP multiplier (compound 10% per level above WEP I)
  let modifiedAS =
    if weaponsTech > 1:
      int32(float(baseAS) * pow(1.10, float(weaponsTech - 1)))
    else:
      baseAS

  let modifiedDS =
    if weaponsTech > 1:
      int32(float(baseDS) * pow(1.10, float(weaponsTech - 1)))
    else:
      baseDS

  ShipStats(
    attackStrength: modifiedAS, defenseStrength: modifiedDS, wep: weaponsTech
  )

## Ship Construction

proc newShip*(
    shipClass: ShipClass,
    weaponsTech: int32 = 1,
    id: ShipId = ShipId(0),
    squadronId: SquadronId = SquadronId(0),
    houseId: HouseId = HouseId(0),
): Ship =
  ## Create a new ship with WEP-modified stats
  ## weaponsTech defaults to 1 (WEP I - starting level per gameplay.md:1.2)
  ##
  ## Stats (AS, DS, WEP) are calculated once at construction and never change
  ## Config values (role, costs, CC, CR) looked up via shipClass
  ## Cargo is initialized as None (use initCargo to add cargo)
  let stats = getShipStats(shipClass, weaponsTech)

  Ship(
    id: id,
    houseId: houseId,
    squadronId: squadronId,
    shipClass: shipClass,
    stats: stats,
    isCrippled: false,
    cargo: none(ShipCargo),
  )

proc `$`*(ship: Ship): string =
  ## String representation of ship
  let status = if ship.isCrippled: " (crippled)" else: ""
  $ship.shipClass & status

## Config Lookups (non-WEP stats from config/ships.kdl)

proc role*(ship: Ship): ShipRole =
  ## Get ship's role from ShipClassRoles constant (Escort, Capital, Auxiliary, etc.)
  ShipClassRoles[ship.shipClass]

proc commandCost*(ship: Ship): int32 =
  ## Get command cost (CC) from config
  getShipConfigStats(ship.shipClass).commandCost

proc commandRating*(ship: Ship): int32 =
  ## Get command rating (CR) from config
  getShipConfigStats(ship.shipClass).commandRating

proc buildCost*(ship: Ship): int32 =
  ## Get build cost (PC) from config
  getShipConfigStats(ship.shipClass).productionCost

proc upkeepCost*(ship: Ship): int32 =
  ## Get maintenance cost (MC) from config
  getShipConfigStats(ship.shipClass).maintenanceCost

proc baseCarryLimit*(ship: Ship): int32 =
  ## Get base carry limit from config (for carriers/transports)
  ## Modified at runtime by ACO/STL tech levels
  getShipConfigStats(ship.shipClass).carryLimit

## Ship Capability Queries

proc isTransport*(ship: Ship): bool =
  ## Check if ship is a transport (Expansion/Auxiliary squadron type)
  ## Per unified architecture: ETAC = Expansion, TroopTransport = Auxiliary
  ship.shipClass in {ShipClass.ETAC, ShipClass.TroopTransport}

proc isCombatShip*(ship: Ship): bool =
  ## Check if ship has combat capability (non-zero attack strength)
  ship.stats.attackStrength > 0 and not ship.isCrippled

proc isScout*(ship: Ship): bool =
  ## Check if ship can leverage ELI (Electronic Intelligence) tech
  ## Scouts provide intelligence gathering capabilities scaled by house ELI level
  ship.shipClass == ShipClass.Scout

proc isRaider*(ship: Ship): bool =
  ## Check if ship can leverage CLK (Cloaking) tech
  ## Raiders provide fleet cloaking scaled by house CLK level
  ship.shipClass == ShipClass.Raider

proc isFighter*(ship: Ship): bool =
  ## Check if ship is a fighter (carried by carriers)
  ship.shipClass == ShipClass.Fighter

proc isCarrier*(ship: Ship): bool =
  ## Check if ship is a carrier (CV or CX)
  ship.shipClass in {ShipClass.Carrier, ShipClass.SuperCarrier}

proc canCommand*(ship: Ship): bool =
  ## Check if ship can serve as squadron flagship (has command rating)
  ship.commandRating() > 0

proc effectiveAttackStrength*(ship: Ship): int32 =
  ## Get effective attack strength (halved if crippled)
  ## Per combat rules: crippled ships have AS reduced by half
  if ship.isCrippled:
    ship.stats.attackStrength div 2
  else:
    ship.stats.attackStrength

proc effectiveDefenseStrength*(ship: Ship): int32 =
  ## Get effective defense strength (unchanged when crippled)
  ship.stats.defenseStrength

## Cargo Management for Transport Ships

proc initCargo*(ship: var Ship, cargoType: CargoClass, capacity: int32) =
  ## Initialize cargo hold for transport ships
  ## Used for ETAC (colonists) and TroopTransport (marines)
  if not ship.isTransport():
    raise newException(
      ValueError, "Cannot init cargo on non-transport ship: " & $ship.shipClass
    )

  ship.cargo = some(ShipCargo(cargoType: cargoType, quantity: 0, capacity: capacity))

proc loadCargo*(ship: var Ship, amount: int32): bool =
  ## Load cargo into transport ship
  ## Returns true if successful, false if capacity exceeded
  if ship.cargo.isNone:
    return false

  var cargo = ship.cargo.get
  if cargo.quantity + amount > cargo.capacity:
    return false

  cargo.quantity += amount
  ship.cargo = some(cargo)
  return true

proc unloadCargo*(ship: var Ship, amount: int32): bool =
  ## Unload cargo from transport ship
  ## Returns true if successful, false if insufficient cargo
  if ship.cargo.isNone:
    return false

  var cargo = ship.cargo.get
  if cargo.quantity < amount:
    return false

  cargo.quantity -= amount
  ship.cargo = some(cargo)
  return true

proc availableCargoCapacity*(ship: Ship): int32 =
  ## Get available cargo capacity
  ## Returns 0 if ship has no cargo hold
  if ship.cargo.isNone:
    return 0'i32

  let cargo = ship.cargo.get
  return cargo.capacity - cargo.quantity

proc isCargoEmpty*(ship: Ship): bool =
  ## Check if cargo hold is empty
  ## Returns true if no cargo hold or quantity is 0
  if ship.cargo.isNone:
    return true

  return ship.cargo.get.quantity == 0

proc isCargoFull*(ship: Ship): bool =
  ## Check if cargo hold is full
  ## Returns false if no cargo hold
  if ship.cargo.isNone:
    return false

  let cargo = ship.cargo.get
  return cargo.quantity >= cargo.capacity
