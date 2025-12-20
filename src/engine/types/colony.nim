import std/[tables, options]
import ./core

type
  Colony* = object
    id*: ColonyId
    systemId*: SystemId
    houseId*: HouseId
    population*: int32
    souls*: int32
    populationUnits*: int32
    populationTransferUnits*: int32
    infrastructure*: int32
    industrial*: econ_types.IndustrialUnits
    production*: int32
    grossOutput*: int32
    taxRate*: int32
    infrastructureDamage*: float32
    underConstruction*: Option[ConstructionProject]
    constructionQueue*: seq[ConstructionProject]
    repairQueue*: seq[RepairProject]
    autoRepairEnabled*: bool
    autoLoadingEnabled*: bool
    autoReloadETACs*: bool
    activeTerraforming*: Option[TerraformProject]
    unassignedSquadronIds*: seq[SquadronId]
    fighterSquadronIds*: seq[SquadronId]
    capacityViolation*: CapacityViolation
    planetClass*: planets.PlanetClass
    resources*: planets.ResourceRating
    planetaryShieldLevel*: int32
    groundBatteryIds*: seq[GroundUnitId]
    armyIds*: seq[GroundUnitId]
    marineIds*: seq[GroundUnitId]
    # Facility references
    starbaseIds*: seq[StarbaseId]
    spaceportIds*: seq[SpaceportId]
    shipyardIds*: seq[ShipyardId]
    drydockIds*: seq[DrydockId]
    blockaded*: bool
    blockadedBy*: seq[HouseId]
    blockadeTurns*: int32

  Colonies* = object
    data: seq[Colony]
    index: Table[ColonyId, int]
    bySystem: Table[SystemId, ColonyId]
    byOwner: Table[HouseId, seq[ColonyId]]
    nextId: uint32

  TerraformProject* = object
    startTurn*: int32
    turnsRemaining*: int32
    targetClass*: int32
    ppCost*: int32
    ppPaid*: int32

  TerraformCommand* = object
    houseId*: HouseId
    colonyId*: ColonyId          
    startTurn*: int32
    turnsRemaining*: int32
    ppCost*: int32
    targetClass*: int32

  PopulationTransferCommand* = object
    houseId*: HouseId
    sourceColony*: ColonyId  
    destColony*: ColonyId
    ptuAmount*: int32

  ColonyIncomeReport* = object
    colonyId*: ColonyId
    houseId*: HouseId
    populationUnits*: int32
    grossOutput*: int32
    taxRate*: int32
    netValue*: int32
    populationGrowth*: float32
    prestigeBonus*: int32

