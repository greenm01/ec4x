## Ground Unit Type Definitions for EC4X
##
## This module contains the type definitions for ground units, planetary defenses,
## and other related combat types for ground and orbital combat.

import std/tables
import ./core
import ./combat  # For CombatState

type
  GroundClass* {.pure.} = enum
    Army
    Marine
    GroundBattery
    PlanetaryShield

  GroundUnitStats* = object
    unitType*: GroundClass
    attackStrength*: int32
    defenseStrength*: int32

  GroundUnitLocation* {.pure.} = enum
    OnColony, OnTransport

  GroundUnitGarrison* = object
    case locationType*: GroundUnitLocation
    of OnColony:
      colonyId*: ColonyId
    of OnTransport:
      shipId*: ShipId

  GroundUnit* = object
    id*: GroundUnitId
    houseId*: HouseId
    stats*: GroundUnitStats
    state*: CombatState  # Combat damage state (Nominal, Crippled, Destroyed)
    garrison*: GroundUnitGarrison

  GroundUnits* = object
    entities*: EntityManager[GroundUnitId, GroundUnit]
    byHouse*: Table[HouseId, seq[GroundUnitId]]
    byColony*: Table[ColonyId, seq[GroundUnitId]]
    byTransport*: Table[ShipId, seq[GroundUnitId]]
