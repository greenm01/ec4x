import std/[tables, options, hashes]
import ./core

type
  ProductionOutput* = object
    grossOutput*: int32
    netValue*: int32
    populationProduction*: int32
    industrialProduction*: int32

  IndustrialUnits* = object
    units*: int32
    investmentCost*: int32

  BuildType* {.pure.} = enum
    Ship, Facility, Ground, Industrial, Infrastructure

  FacilityType* {.pure.} = enum
    Spaceport, Shipyard, Drydock

  BuildCommand* = object
    colonyId*: ColonyId           # Use ColonyId, not SystemId
    buildType*: BuildType
    quantity*: int32
    shipClass*: Option[ShipClass]
    buildingType*: Option[string]
    industrialUnits*: int32

  ConstructionProject* = object
    id*: ConstructionProjectId
    colonyId*: ColonyId
    projectType*: BuildType
    itemId*: string
    costTotal*: int32
    costPaid*: int32
    turnsRemaining*: int32
    facilityId*: Option[uint32]
    facilityType*: Option[FacilityType]

  ConstructionProjects* = object
    data: seq[ConstructionProject]
    index: Table[ConstructionProjectId, int]
    byColony: Table[ColonyId, seq[ConstructionProjectId]]
    byFacility: Table[(FacilityType, uint32), seq[ConstructionProjectId]]
    nextId: uint32

  RepairTargetType* {.pure.} = enum
    Ship, Starbase

  RepairProject* = object
    id*: RepairProjectId
    colonyId*: ColonyId
    targetType*: RepairTargetType
    facilityType*: FacilityType
    facilityId*: Option[uint32]
    # For ship repairs
    fleetId*: Option[FleetId]
    squadronId*: Option[SquadronId]
    shipId*: Option[ShipId]
    # For starbase repairs
    starbaseId*: Option[StarbaseId]
    shipClass*: Option[ShipClass]
    cost*: int32
    turnsRemaining*: int32
    priority*: int32

  RepairProjects* = object
    data: seq[RepairProject]
    index: Table[RepairProjectId, int]
    byColony: Table[ColonyId, seq[RepairProjectId]]
    byFacility: Table[(FacilityType, uint32), seq[RepairProjectId]]
    nextId: uint32

  CompletedProject* = object
    colonyId*: ColonyId
    projectType*: ConstructionType
    itemId*: string

  ## Reports
  
  ProductionReport* = object
    turn*: int32
    completedProjects*: seq[CompletedProject]
    houseUpkeep*: Table[HouseId, int32]
    repairsApplied*: seq[tuple[colonyId: ColonyId, repairAmount: float32]]
