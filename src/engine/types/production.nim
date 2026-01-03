import std/[tables, options]
import ./[core, ship, facilities]

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
    Ship
    Facility
    Ground
    Industrial
    Infrastructure

  BuildCommand* = object
    colonyId*: ColonyId # Use ColonyId, not SystemId
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
    # Typed facility reference
    neoriaId*: Option[NeoriaId]  # Production facility (Spaceport, Shipyard)

  ConstructionProjects* = object
    entities*: EntityManager[ConstructionProjectId, ConstructionProject] # Core storage
    byColony*: Table[ColonyId, seq[ConstructionProjectId]]
    # Index by typed ID
    byNeoria*: Table[NeoriaId, seq[ConstructionProjectId]]

  RepairTargetType* {.pure.} = enum
    Ship
    Starbase

  RepairProject* = object
    id*: RepairProjectId
    colonyId*: ColonyId
    targetType*: RepairTargetType
    facilityType*: FacilityClass  # Keep for knowing which neoria type (Drydock)
    # Typed facility reference
    neoriaId*: Option[NeoriaId]  # Repair facility (Drydock)
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
    entities*: EntityManager[RepairProjectId, RepairProject] # Core storage
    byColony*: Table[ColonyId, seq[RepairProjectId]]
    # Index by typed ID
    byNeoria*: Table[NeoriaId, seq[RepairProjectId]]

  CompletedProject* = object
    colonyId*: ColonyId
    projectType*: BuildType
    itemId*: string

  ## Reports
  ProductionReport* = object
    turn*: int32
    completedProjects*: seq[CompletedProject]
    houseUpkeep*: Table[HouseId, int32]
    repairsApplied*: seq[tuple[colonyId: ColonyId, repairAmount: float32]]
