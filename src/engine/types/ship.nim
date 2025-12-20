## Ship Type Definitions for EC4X
##
## This module contains the type definitions for individual ships, including their
## stats, cargo, and operational capabilities.
import std/[tables, options, hashes]
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
    name*: string
    class*: string
    role*: ShipRole
    attackStrength*: int32
    defenseStrength*: int32
    commandCost*: int32
    commandRating*: int32
    techLevel*: int32
    buildCost*: int32
    upkeepCost*: int32
    specialCapability*: string
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
    data: seq[Ship]
    index: Table[ShipId, int]
    bySquadron: Table[SquadronId, seq[ShipId]]
    nextId: uint32

# Note: ShipStats could be moved to a separate config/template file if the stats are loaded from config rather than computed per-ship.
