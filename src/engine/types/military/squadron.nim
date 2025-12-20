## Squadron Type Definitions for EC4X
##
## This module contains the type definitions for squadrons, which are tactical
## groupings of ships under a flagship's command.

import std/[sequtils]
import ../../../common/types/[core, units]
import ./ship_types
import ../../../common/types/core

export HouseId, FleetId, SystemId, SquadronId
export Ship, ShipClass, ShipStats, CargoType, ShipCargo

type
  SquadronType* {.pure.} = enum
    ## Strategic role classification for squadrons
    ## Determines fleet composition rules and combat participation
    Combat      # Combat squadrons (capital ships + escorts)
    Intel       # Intelligence squadrons (scouts, future intel assets)
    Auxiliary   # Combat support (TT - planetary invasions)
    Expansion   # Expansion operations (ETAC - colonization)
    Fighter     # Fighter squadrons (planetary defense, carrier-based)

  Squadron* = object
    ## A tactical unit of ships under flagship command
    id*: SquadronId
    flagship*: Ship  # Renamed from Ship
    ships*: seq[Ship]  # Ships under flagship command (excludes flagship)
    owner*: HouseId
    location*: SystemId
    destroyed*: bool = false  # Set to true when squadron is destroyed in combat
    squadronType*: SquadronType  # Strategic role classification (NEW)

    # Carrier fighter operations (assets.md:2.4.1.1)
    embarkedFighters*: seq[Squadron]  # Embarked fighter squadrons (Squadron.Fighter type)

  SquadronFormation* {.pure.} = enum
    ## Formation roles for squadrons in fleet
    Vanguard,   # Front line, first to engage
    MainLine,   # Main battle line
    Reserve,    # Held in reserve
    Screen,     # Screening/picket duty
    RearGuard   # Rear guard, last to engage
