## Population Transfer Types
## Tracks Space Guild civilian transport between colonies
## Source: docs/specs/economy.md Section 3.7, config/population.toml

import ../../common/types/core

type
  PopulationInTransit* = object
    ## A population transfer in progress via Space Guild Starliner
    id*: string  # Unique transfer ID
    houseId*: HouseId
    sourceSystem*: SystemId
    destSystem*: SystemId
    ptuAmount*: int  # Population Transfer Units being moved
    costPaid*: int  # PP already spent (non-refundable)
    arrivalTurn*: int  # Turn when transfer completes

  TransferStatus* {.pure.} = enum
    ## Current state of a population transfer
    InTransit,    # Currently moving between systems
    Arrived,      # Successfully delivered
    Lost,         # Destination conquered, PTUs lost
    Returned      # Destination blockaded, PTUs returned to source

  PopulationTransferConfig* = object
    ## Configuration loaded from config/population.toml
    # PTU definition
    soulsPerPtu*: int  # Number of people in 1 PTU (default 50000)
    ptuSizeMillions*: float  # PTU size in millions for colony.population field (default 0.05)

    # Transfer costs by planet class (PP per PTU)
    edenCost*: int
    lushCost*: int
    benignCost*: int
    harshCost*: int
    hostileCost*: int
    desolateCost*: int
    extremeCost*: int

    # Transfer time
    turnsPerJump*: int
    minimumTurns*: int

    # Distance cost modifier
    costIncreasePerJump*: float

    # Transfer limits
    minPtuTransfer*: int
    minSourcePuRemaining*: int
    maxConcurrentTransfers*: int

    # Risk behaviors
    sourceConqueredBehavior*: string
    destConqueredBehavior*: string
    destBlockadedBehavior*: string

    # AI strategy parameters
    minTreasuryForTransfer*: int
    minSourcePopulation*: int
    maxDestPopulation*: int
    recentColonyAgeTurns*: int
    ptuPerTransfer*: int
    minEconomicFocus*: float
    minExpansionDrive*: float

# Global config instance (loaded at startup)
var globalPopulationConfig*: PopulationTransferConfig
