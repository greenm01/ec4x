import ../starmap  # For PlanetClass enum
export PlanetClass

type
  TransferCostsConfig* = object
    ## Guild transfer costs indexed by planet class
    ## Uses array pattern for categorical data (see data-guide.md)
    costs*: array[PlanetClass, int32]

  TransferTimeConfig* = object
    turnsPerJump*: int32
    minimumTurns*: int32

  TransferModifiersConfig* = object
    costIncreasePerJump*: float32

  TransferLimitsConfig* = object
    minPtuTransfer*: int32
    minSourcePuRemaining*: int32
    maxConcurrentTransfers*: int32

  TransferRisksConfig* = object
    sourceConqueredBehavior*: string
    destConqueredBehavior*: string
    destBlockadedBehavior*: string
    destCollapsedBehavior*: string

  AiStrategyConfig* = object
    minTreasuryForTransfer*: int32
    minSourcePopulation*: int32
    maxDestPopulation*: int32
    recentColonyAgeTurns*: int32
    ptuPerTransfer*: int32
    minEconomicFocus*: float32
    minExpansionDrive*: float32

  GuildConfig* = object ## Complete population configuration loaded from KDL
    transferCosts*: TransferCostsConfig
    transferLimits*: TransferLimitsConfig
    transferRisks*: TransferRisksConfig
    aiStrategy*: AiStrategyConfig

