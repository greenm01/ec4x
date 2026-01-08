import std/options
import ./[core, fleet, production, tech, diplomacy, colony, espionage, ground_unit, facilities]

type
  RepairCommand* = object
    ## Manual repair command submitted by player
    ## Used when colony.autoRepair = false
    ## Queued during Command Phase Part B, executed in Production Phase Step 2c
    colonyId*: ColonyId
    targetType*: RepairTargetType  # Ship, GroundUnit, Facility, Starbase
    targetId*: uint32  # Polymorphic ID (ShipId, GroundUnitId, NeoriaId, or KastraId)
    priority*: int32   # Player-specified priority (optional, default by type)

  ColonyManagementCommand* = object
    colonyId*: ColonyId
    autoRepair*: bool
    autoLoadFighters*: bool
    autoLoadMarines*:bool
    autoJoinFleets*: bool
    taxRate*: Option[int32]

  CommandPacket* = object
    houseId*: HouseId
    turn*: int32
    treasury*: int32
    fleetCommands*: seq[FleetCommand]
    buildCommands*: seq[BuildCommand]
    repairCommands*: seq[RepairCommand]  # Manual repair orders
    researchAllocation*: ResearchAllocation
    diplomaticCommand*: seq[DiplomaticCommand]
    populationTransfers*: seq[PopulationTransferCommand]
    terraformCommands*: seq[TerraformCommand]
    colonyManagement*: seq[ColonyManagementCommand]
    espionageAction*: Option[EspionageAttempt]
    ebpInvestment*: int32
    cipInvestment*: int32

  ValidationResult* = object
    valid*: bool
    error*: string

  CommandValidationContext* = object
    availableTreasury*: int32
    committedSpending*: int32
    rejectedCommands*: int32

  CommandCostSummary* = object
    buildCosts*: int32
    researchCosts*: int32
    espionageCosts*: int32
    totalCost*: int32
    canAfford*: bool
    errors*: seq[string]
    warnings*: seq[string]
