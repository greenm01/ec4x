type
  TransferCostsConfig* = object
    edenCost*: int32
    lushCost*: int32
    benignCost*: int32
    harshCost*: int32
    hostileCost*: int32
    desolateCost*: int32
    extremeCost*: int32

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

