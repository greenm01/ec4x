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
    ## Instance-specific ship stats (WEP-modified at construction)
    ## All other stats (role, costs, CC, CR) looked up from config via shipClass
    attackStrength*: int32      # WEP-modified AS at construction
    defenseStrength*: int32     # WEP-modified DS at construction
    weaponsTech*: int32         # WEP level at construction (permanent)

  Ship* = object
    id*: ShipId
    squadronId*: SquadronId  # Which squadron owns this ship
    shipClass*: ShipClass
    stats*: ShipStats        # Contains role, AS, DS, WEP level, etc.
    isCrippled*: bool
    name*: string
    cargo*: Option[ShipCargo]

  Ships* = object
    entities*: EntityManager[ShipId, Ship]  # Core storage
    bySquadron*: Table[SquadronId, seq[ShipId]]
    byHouse*: Table[HouseId, seq[ShipId]]  # O(1) lookup for house queries

# Note: ShipStats could be moved to a separate config/template file if the stats are loaded from config rather than computed per-ship.
