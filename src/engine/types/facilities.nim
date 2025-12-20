import std/tables
import ./economy as econ_types
import ./core 

type

  FacilityType* {.pure.} = enum
    Shipyard, Spaceport, Drydock

  Starbase* = object
    id*: StarbaseId
    colonyId*: ColonyId
    commissionedTurn*: int32
    isCrippled*: bool

  Starbases* = object
    data: seq[Starbase]
    index: Table[StarbaseId, int]
    byColony: Table[ColonyId, seq[StarbaseId]]
    nextId: uint32

  Spaceport* = object
    id*: SpaceportId
    colonyId*: ColonyId
    commissionedTurn*: int32
    baseDocks*: int32
    effectiveDocks*: int32
    constructionQueue*: seq[econ_types.ConstructionProject]
    activeConstructions*: seq[econ_types.ConstructionProject]

  Spaceports* = object
    data: seq[Spaceport]
    index: Table[SpaceportId, int]
    byColony: Table[ColonyId, seq[SpaceportId]]
    nextId: uint32

  Shipyard* = object
    id*: ShipyardId
    colonyId*: ColonyId
    commissionedTurn*: int32
    baseDocks*: int32
    effectiveDocks*: int32
    isCrippled*: bool
    constructionQueue*: seq[econ_types.ConstructionProject]
    activeConstructions*: seq[econ_types.ConstructionProject]

  Shipyards* = object
    data: seq[Shipyard]
    index: Table[ShipyardId, int]
    byColony: Table[ColonyId, seq[ShipyardId]]
    nextId: uint32

  Drydock* = object
    id*: DrydockId
    colonyId*: ColonyId
    commissionedTurn*: int32
    baseDocks*: int32
    effectiveDocks*: int32
    isCrippled*: bool
    repairQueue*: seq[econ_types.RepairProject]
    activeRepairs*: seq[econ_types.RepairProject]

  Drydocks* = object
    data: seq[Drydock]
    index: Table[DrydockId, int]
    byColony: Table[ColonyId, seq[DrydockId]]
    nextId: uint32
