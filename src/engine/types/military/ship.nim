## Ship Type Definitions for EC4X
##
## This module contains the type definitions for individual ships, including their
## stats, cargo, and operational capabilities.

import std/[options]
import ../../../common/types/units

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
