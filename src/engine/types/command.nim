import std/options
import ./[core, fleet, production, tech, diplomacy, colony, espionage]

type
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
