import std/options
import ./[core, fleet, production, tech, diplomacy, colony, espionage]

type
  ScrapTargetType* {.pure.} = enum
    ## Target type for scrap/salvage command
    Ship          # Ship at home colony (not in transit)
    GroundUnit    # Army, Marine, GroundBattery, PlanetaryShield
    Neoria        # Spaceport, Shipyard, Drydock
    Kastra        # Starbase

  ScrapCommand* = object
    ## Administrative command to salvage an entity at a home colony
    ## Zero-turn execution: instant during Command Phase
    ## Salvage value: 50% of original production cost
    ##
    ## Warning: Scrapping a facility with queued projects will destroy
    ## all queued projects with no refund. Set acknowledgeQueueLoss=true
    ## to confirm when queue is not empty.
    colonyId*: ColonyId           # Colony where entity is located
    targetType*: ScrapTargetType
    targetId*: uint32             # ShipId, GroundUnitId, NeoriaId, or KastraId
    acknowledgeQueueLoss*: bool   # Must be true if facility has queued projects

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
    autoLoadMarines*: bool
    taxRate*: Option[int32]

  CommandPacket* = object
    houseId*: HouseId
    turn*: int32
    fleetCommands*: seq[FleetCommand]
    buildCommands*: seq[BuildCommand]
    repairCommands*: seq[RepairCommand]  # Manual repair orders
    scrapCommands*: seq[ScrapCommand]    # Salvage entities at home colonies
    researchAllocation*: ResearchAllocation
    diplomaticCommand*: seq[DiplomaticCommand]
    populationTransfers*: seq[PopulationTransferCommand]
    terraformCommands*: seq[TerraformCommand]
    colonyManagement*: seq[ColonyManagementCommand]
    espionageActions*: seq[EspionageAttempt]
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
