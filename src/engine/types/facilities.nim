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

  # Unified facility types (Neoria = production, Kastra = defense)
  NeoriaClass* {.pure.} = enum
    Spaceport
    Shipyard
    Drydock

  KastraClass* {.pure.} = enum
    Starbase

  KastraStats* = object
    ## Combat stats for defensive facilities (tech-modified at construction)
    attackStrength*: int32
    defenseStrength*: int32
    wep*: int32  # WEP tech level at construction

  Neoria* = object
    ## Production and repair facilities (Spaceport, Shipyard, Drydock)
    id*: NeoriaId
    neoriaClass*: NeoriaClass
    colonyId*: ColonyId
    commissionedTurn*: int32
    isCrippled*: bool
    baseDocks*: int32  # Base dock capacity from config (immutable)
    effectiveDocks*: int32  # CST-modified dock capacity (updated on tech changes)
    constructionQueue*: seq[ConstructionProjectId]
    activeConstructions*: seq[ConstructionProjectId]
    repairQueue*: seq[RepairProjectId]
    activeRepairs*: seq[RepairProjectId]

  Neorias* = object
    entities*: EntityManager[NeoriaId, Neoria]
    byColony*: Table[ColonyId, seq[NeoriaId]]

  Kastra* = object
    ## Defensive military installations (Starbase)
    id*: KastraId
    kastraClass*: KastraClass
    colonyId*: ColonyId
    commissionedTurn*: int32
    stats*: KastraStats
    isCrippled*: bool

  Kastras* = object
    entities*: EntityManager[KastraId, Kastra]
    byColony*: Table[ColonyId, seq[KastraId]]
