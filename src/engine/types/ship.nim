## Ship Type Definitions for EC4X
##
## This module contains the type definitions for individual ships, including their
## stats, cargo, and operational capabilities.
import std/[tables, options]
import ./core

type
  ShipClass* {.pure.} = enum
    Corvette
    Frigate
    Destroyer
    LightCruiser
    Cruiser
    Battlecruiser
    Battleship
    Dreadnought
    SuperDreadnought
    Carrier
    SuperCarrier
    Raider
    Scout
    ETAC
    TroopTransport
    Fighter
    PlanetBreaker

  # Generic roles for future ship expansion
  ShipRole* {.pure.} = enum
    Escort         # Default squadron escorts
    Capital        # Default squadron flagships
    SpecialWeapon  # Planet breaker
    Fighter        # Fighter Squadrons
    Auxiliary      # Screened during space/orbital combat
    Intel          # Intelligence gathering (non-combat) 

  CargoClass* {.pure.} = enum
    None
    Marines
    Colonists

  ShipCargo* = object
    cargoType*: CargoClass
    quantity*: int32
    capacity*: int32

  ShipStats* = object
    ## Instance-specific ship stats (WEP-modified at construction)
    ## All other stats (role, costs, CC, CR) looked up from config via shipClass
    attackStrength*: int32 # WEP-modified AS at construction
    defenseStrength*: int32 # WEP-modified DS at construction
    weaponsTech*: int32 # WEP level at construction (permanent)

  Ship* = object
    id*: ShipId
    houseId*: HouseId
    squadronId*: SquadronId
    shipClass*: ShipClass
    stats*: ShipStats
    isCrippled*: bool
    cargo*: Option[ShipCargo]

  Ships* = object
    entities*: EntityManager[ShipId, Ship] # Core storage
    byHouse*: Table[HouseId, seq[ShipId]] # O(1) lookup for house queries
    bySquadron*: Table[SquadronId, seq[ShipId]]

export Ships

const ShipClassRoles*: array[ShipClass, ShipRole] = [
  Corvette: ShipRole.Escort,
  Frigate: ShipRole.Escort,
  Destroyer: ShipRole.Escort,
  LightCruiser: ShipRole.Capital,
  Cruiser: ShipRole.Capital,
  Battlecruiser: ShipRole.Capital,
  Battleship: ShipRole.Capital,
  Dreadnought: ShipRole.Capital,
  SuperDreadnought: ShipRole.Capital,
  Carrier: ShipRole.Capital,
  SuperCarrier: ShipRole.Capital,
  Raider: ShipRole.Capital,
  Scout: ShipRole.Intel,
  ETAC: ShipRole.Auxiliary,
  TroopTransport: ShipRole.Auxiliary,
  Fighter: ShipRole.Fighter,
  PlanetBreaker: ShipRole.SpecialWeapon,
]

