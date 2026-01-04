import std/[tables, options]
import ./[core, production, capacity, prestige]

type
  Colony* = object
    id*: ColonyId
    systemId*: SystemId
    owner*: HouseId
    population*: int32
    souls*: int32
    populationUnits*: int32
    populationTransferUnits*: int32
    infrastructure*: int32
    industrial*: IndustrialUnits
    production*: int32
    grossOutput*: int32
    taxRate*: int32
    infrastructureDamage*: float32
    underConstruction*: Option[ConstructionProjectId]
    constructionQueue*: seq[ConstructionProjectId]
    repairQueue*: seq[RepairProjectId]
    autoRepairEnabled*: bool
    autoLoadingEnabled*: bool
    autoReloadETACs*: bool
    activeTerraforming*: Option[TerraformProject]
    unassignedSquadronIds*: seq[SquadronId]
    fighterSquadronIds*: seq[SquadronId]
    capacityViolation*: CapacityViolation
    # Entity references (bucket-level tracking)
    groundUnitIds*: seq[GroundUnitId]  # All ground units (batteries, armies, marines, shields)
    neoriaIds*: seq[NeoriaId]          # Production facilities (spaceport, shipyard, drydock)
    kastraIds*: seq[KastraId]          # Defensive facilities (starbase)
    blockaded*: bool
    blockadedBy*: seq[HouseId]
    blockadeTurns*: int32

  Colonies* = object
    entities*: EntityManager[ColonyId, Colony]
    bySystem*: Table[SystemId, ColonyId]
    byOwner*: Table[HouseId, seq[ColonyId]]

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

  ColonizationAttempt* = object ## Attempt to colonize a planet
    houseId*: HouseId
    systemId*: SystemId
    fleetId*: FleetId
    ptuUsed*: int

  ColonizationResult* = object ## Result of colonization attempt
    success*: bool
    reason*: string
    newColony*: Option[Colony] # Now uses unified Colony from gamestate
    prestigeEvent*: Option[PrestigeEvent]
