## Population Transfer Types
## Tracks Space Guild civilian transport between colonies
## Source: docs/specs/economy.md Section 3.7, config/population.toml
import std/[tables]
import ./core

type
  TransferStatus* {.pure.} = enum
    InTransit, Arrived, Lost, Returned

  PopulationInTransit* = object
    id*: PopulationTransferId
    houseId*: HouseId
    sourceColony*: ColonyId  # Use ColonyId, not SystemId
    destColony*: ColonyId
    ptuAmount*: int32
    costPaid*: int32
    arrivalTurn*: int32
    status*: TransferStatus

  PopulationTransfers* = object
    entities*: EntityManager[PopulationTransferId, PopulationInTransit]  # Core storage
    byHouse*: Table[HouseId, seq[PopulationTransferId]]
    inTransit*: seq[PopulationTransferId]  # Quick filter for active transfers

  PopulationTransferConfig* = object
    # PTU definition
    soulsPerPtu*: int32
    ptuSizeMillions*: float32
    
    # Transfer costs by planet class (PP per PTU)
    edenCost*: int32
    lushCost*: int32
    benignCost*: int32
    harshCost*: int32
    hostileCost*: int32
    desolateCost*: int32
    extremeCost*: int32
    
    # Transfer time
    turnsPerJump*: int32
    minimumTurns*: int32
    
    # Distance cost modifier
    costIncreasePerJump*: float32
    
    # Transfer limits
    minPtuTransfer*: int32
    minSourcePuRemaining*: int32
    maxConcurrentTransfers*: int32
    
    # Risk behaviors
    sourceConqueredBehavior*: string
    destConqueredBehavior*: string
    destBlockadedBehavior*: string
    
    # AI strategy parameters
    minTreasuryForTransfer*: int32
    minSourcePopulation*: int32
    maxDestPopulation*: int32
    recentColonyAgeTurns*: int32
    ptuPerTransfer*: int32
    minEconomicFocus*: float32
    minExpansionDrive*: float32

# Global config instance (loaded at startup)
var globalPopulationConfig*: PopulationTransferConfig
