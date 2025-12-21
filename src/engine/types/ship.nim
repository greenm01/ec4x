## Ship Type Definitions for EC4X
##
## This module contains the type definitions for individual ships, including their
## stats, cargo, and operational capabilities.
import std/[tables, options]
import ./core

type
  ShipClass* {.pure.} = enum
    Fighter, Corvette, Frigate, Scout, Raider,
    Destroyer, Cruiser, LightCruiser, HeavyCruiser,
    Battlecruiser, Battleship, Dreadnought, SuperDreadnought,
    Carrier, SuperCarrier, ETAC, TroopTransport, PlanetBreaker

  ShipRole* {.pure.} = enum
    Escort, Capital, Auxiliary, SpecialWeapon, Fighter

  CargoType* {.pure.} = enum
    None, Marines, Colonists

  ShipCargo* = object
    cargoType*: CargoType
    quantity*: int32
    capacity*: int32

  ShipStats* = object
    role*: ShipRole
    attackStrength*: int32
    defenseStrength*: int32
    commandCost*: int32
    commandRating*: int32
    techLevel*: int32
    buildCost*: int32
    upkeepCost*: int32
    carryLimit*: int32

  Ship* = object
    id*: ShipId
    squadronId*: SquadronId  # Which squadron owns this ship
    shipClass*: ShipClass
    shipRole*: ShipRole
    stats*: ShipStats
    isCrippled*: bool
    name*: string
    cargo*: Option[ShipCargo]

  Ships* = object
    entities*: EntityManager[ShipId, Ship]  # Core storage
    bySquadron: Table[SquadronId, seq[ShipId]]

# Note: ShipStats could be moved to a separate config/template file if the stats are loaded from config rather than computed per-ship.
