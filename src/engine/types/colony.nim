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
    activeTerraforming*: Option[TerraformProject]
    fighterIds*: seq[ShipId]  # Colony-assigned fighters (not in fleets)
    capacityViolation*: CapacityViolation
    # Entity references (bucket-level tracking)
    groundUnitIds*: seq[GroundUnitId]  # All ground units (batteries, armies, marines, shields)
    neoriaIds*: seq[NeoriaId]          # Production facilities (spaceport, shipyard, drydock)
    kastraIds*: seq[KastraId]          # Defensive facilities (starbase)
    blockaded*: bool
    blockadedBy*: seq[HouseId]
    blockadeTurns*: int32
    # Automatic actions
    autoRepair*: bool
    autoLoadMarines*: bool
    autoLoadFighters*: bool
    autoJoinFleets*: bool

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

  ColonizationIntent* = object
    ## Intent to colonize a system (collected during conflict phase)
    houseId*: HouseId
    fleetId*: FleetId
    targetSystem*: SystemId
    fleetStrength*: int32 # AS value for conflict resolution

  ColonizationConflict* = object
    ## Multiple houses attempting to colonize the same system
    targetSystem*: SystemId
    intents*: seq[ColonizationIntent]

  ColonizationOutcome* {.pure.} = enum
    ## Result of colonization attempt
    Success # Colony established successfully
    ConflictLost # Lost colonization race to another house
    SystemOccupied # System already has a colony
    InsufficientResources # No ETAC with colonists in fleet

  ColonizationResult* = object
    ## Result of colonization resolution for a single fleet
    houseId*: HouseId
    fleetId*: FleetId
    targetSystem*: SystemId
    outcome*: ColonizationOutcome
    colonyId*: Option[ColonyId] # Set if outcome == Success
    prestigeAwarded*: int32


