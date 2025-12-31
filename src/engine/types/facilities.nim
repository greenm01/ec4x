import std/tables
import ./core

type
  FacilityClass* {.pure.} = enum
    Shipyard
    Spaceport
    Drydock
    Starbase

  FacilityStats* = object
    facilityType*: FacilityClass
    buildCost*: int32
    upkeepCost*: int32
    baseDocks*: int32
    techRequirement*: int32

  Starbase* = object
    id*: StarbaseId
    colonyId*: ColonyId
    commissionedTurn*: int32
    isCrippled*: bool

  Starbases* = object
    entities*: EntityManager[StarbaseId, Starbase]
    byColony*: Table[ColonyId, seq[StarbaseId]]

  Spaceport* = object
    id*: SpaceportId
    colonyId*: ColonyId
    commissionedTurn*: int32
    baseDocks*: int32
    effectiveDocks*: int32
    constructionQueue*: seq[ConstructionProjectId]
    activeConstructions*: seq[ConstructionProjectId]

  Spaceports* = object
    entities*: EntityManager[SpaceportId, Spaceport]
    byColony*: Table[ColonyId, seq[SpaceportId]]

  Shipyard* = object
    id*: ShipyardId
    colonyId*: ColonyId
    commissionedTurn*: int32
    baseDocks*: int32
    effectiveDocks*: int32
    isCrippled*: bool
    constructionQueue*: seq[ConstructionProjectId]
    activeConstructions*: seq[ConstructionProjectId]

  Shipyards* = object
    entities*: EntityManager[ShipyardId, Shipyard]
    byColony*: Table[ColonyId, seq[ShipyardId]]

  Drydock* = object
    id*: DrydockId
    colonyId*: ColonyId
    commissionedTurn*: int32
    baseDocks*: int32
    effectiveDocks*: int32
    isCrippled*: bool
    repairQueue*: seq[RepairProjectId]
    activeRepairs*: seq[RepairProjectId]

  Drydocks* = object
    entities*: EntityManager[DrydockId, Drydock]
    byColony*: Table[ColonyId, seq[DrydockId]]
