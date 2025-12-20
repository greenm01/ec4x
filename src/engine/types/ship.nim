## Ship Type Definitions for EC4X
##
## This module contains the type definitions for individual ships, including their
## stats, cargo, and operational capabilities.

import std/[options]
import ../../../common/types/units

export ShipClass, ShipType, ShipStats, ShipRole

type

  Ship* = object
    ## Ship representation with full combat and operational stats
    ## Used for all ship types: combat, intel, expansion, auxiliary,
    ## fighter
    shipClass*: ShipClass
    shipRole*: ShipRole      # Military or Spacelift (transport)
    stats*: ShipStats
    isCrippled*: bool
    name*: string            # Optional ship name
    cargo*: Option[ShipCargo]  # Cargo for ETAC/TT (Some), None for

  ShipClass* {.pure.} = enum
    ## 18 ship types total 
    Fighter
    Corvette
    Frigate
    Scout
    Raider
    Destroyer
    Cruiser
    LightCruiser
    HeavyCruiser
    Battlecruiser
    Battleship
    Dreadnought
    SuperDreadnought
    Carrier
    SuperCarrier
    ETAC
    TroopTransport
    PlanetBreaker

  ShipRole* {.pure.} = enum
    ## Ship operational role classification
    ## Determines capacity limits and strategic usage
    Escort         # Combat-capable, CR < 7, not capacity-limited
    Capital        # Flagship-capable, CR >= 7, subject to capital squadron limits
    Auxiliary      # Non-combat support (ETAC, TroopTransport)
    SpecialWeapon  # Unique strategic units (PlanetBreaker)
    Fighter        # Embarked strike craft, special capacity rules

  ShipStats* = object
    ## Combat and operational statistics for a ship
    name*: string
    class*: string
    role*: ShipRole          # Operational role classification
    attackStrength*: int     # AS - offensive firepower
    defenseStrength*: int    # DS - defensive shielding
    commandCost*: int        # CC - cost to assign to squadron
    commandRating*: int      # CR - for flagships, capacity to lead
    techLevel*: int          # Minimum tech level to build
    buildCost*: int          # Production cost to construct
    upkeepCost*: int         # Per-turn maintenance cost
    specialCapability*: string  # ELI, CLK, or empty
    carryLimit*: int         # For carriers, transports (0 if N/A)
                               # combat ships
  CargoType* {.pure.} = enum
    ## Type of cargo loaded on transport ships
    None,
    Marines,      # Marine Division (MD) - TroopTransport
    Colonists     # Population Transfer Unit (PTU) - ETAC

  ShipCargo* = object
    ## Cargo loaded on transport ships (ETAC/TT)
    cargoType*: CargoType
    quantity*: int          # Number of units loaded (0 = empty)
    capacity*: int          # Maximum capacity (CL = Carry Limit)
