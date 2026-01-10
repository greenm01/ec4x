import std/[tables, options]
import ./[core, ship, facilities, ground_unit]

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
    facilityClass*: Option[FacilityClass]  # Use enum, not string
    groundClass*: Option[GroundClass]      # For ground units (Army, Marine, etc.)
    industrialUnits*: int32

  ConstructionProject* = object
    id*: ConstructionProjectId
    colonyId*: ColonyId
    projectType*: BuildType
    shipClass*: Option[ShipClass]
    facilityClass*: Option[FacilityClass]
    groundClass*: Option[GroundClass]
    industrialUnits*: int32  # For Industrial/Infrastructure projects
    costTotal*: int32
    costPaid*: int32
    turnsRemaining*: int32
    neoriaId*: Option[NeoriaId]  # Production facility (Spaceport, Shipyard)

  ConstructionProjects* = object
    entities*: EntityManager[ConstructionProjectId, ConstructionProject] # Core storage
    byColony*: Table[ColonyId, seq[ConstructionProjectId]]
    # Index by typed ID
    byNeoria*: Table[NeoriaId, seq[ConstructionProjectId]]

  RepairTargetType* {.pure.} = enum
    Ship
    Starbase
    GroundUnit
    Facility

  RepairProject* = object
    id*: RepairProjectId
    colonyId*: ColonyId
    targetType*: RepairTargetType
    facilityType*: FacilityClass  # Keep for knowing which neoria type (Drydock)
    # Typed facility reference
    neoriaId*: Option[NeoriaId]  # Repair facility (Drydock)
    # For ship repairs
    fleetId*: Option[FleetId]
    shipId*: Option[ShipId]
    # For kastra (defensive facility) repairs
    kastraId*: Option[KastraId]
    # For ground unit repairs
    groundUnitId*: Option[GroundUnitId]
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
    shipClass*: Option[ShipClass]
    facilityClass*: Option[FacilityClass]
    groundClass*: Option[GroundClass]
    industrialUnits*: int32  # For Industrial/Infrastructure projects
    neoriaId*: Option[NeoriaId]  # Facility where it was built (for vulnerability checking)

  ## Reports
  ProductionReport* = object
    turn*: int32
    completedProjects*: seq[CompletedProject]
    houseUpkeep*: Table[HouseId, int32]
    repairsApplied*: seq[tuple[colonyId: ColonyId, repairAmount: float32]]
