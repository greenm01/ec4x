## Squadron Type Definitions for EC4X
##
## This module contains the type definitions for squadrons, which are tactical
## groupings of ships under a flagship's command.

import std/tables
import ./[core, ship]

export HouseId, FleetId, SystemId, SquadronId
export Ship, ShipClass, ShipStats, CargoClass, ShipCargo

type
  SquadronClass* {.pure.} = enum
    ## Strategic role classification for squadrons
    ## Determines fleet composition rules and combat participation
    Combat # Combat squadrons (capital ships + escorts)
    Intel # Intelligence squadrons (scouts, future intel assets)
    Auxiliary # Auxiliary squadrons (TroopTransport - planetary invasions)
    Expansion # Expansion operations (ETAC - colonization)
    Fighter # Fighter squadrons (planetary defense, carrier-based)

  Squadron* = object ## A tactical unit of ships under flagship command
    id*: SquadronId
    flagshipId*: ShipId # DoD: Reference to flagship ship
    ships*: seq[ShipId]
      # DoD: References to ships under flagship command (excludes flagship)
    houseId*: HouseId
    location*: SystemId
    destroyed*: bool = false # Set to true when squadron is destroyed in combat
    squadronType*: SquadronClass # Strategic role classification

    # Carrier fighter operations (assets.md:2.4.1.1)
    embarkedFighters*: seq[SquadronId] # DoD: Embarked fighter squadron IDs

type Squadrons* = ref object
  entities*: EntityManager[SquadronId, Squadron]
  byFleet*: Table[FleetId, seq[SquadronId]]
  byHouse*: Table[HouseId, seq[SquadronId]] # O(1) lookup for house queries

export SquadronClass, Squadron, Squadrons

# Generate convenience entity() accessor: state.squadrons.entity(id)
import ../state/entity_manager
defineEntityAccessor(Squadrons, SquadronId, Squadron)
