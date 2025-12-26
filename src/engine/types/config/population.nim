type
  PtuDefinitionConfig* = object
    soulsPerPtu*: int32
    ptuSizeMillions*: float32
    minPopulationRemaining*: int32

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

  RecruitmentConfig* = object
    minViablePopulation*: int32

  AiStrategyConfig* = object
    minTreasuryForTransfer*: int32
    minSourcePopulation*: int32
    maxDestPopulation*: int32
    recentColonyAgeTurns*: int32
    ptuPerTransfer*: int32
    minEconomicFocus*: float32
    minExpansionDrive*: float32

  PopulationConfig* = object ## Complete population configuration loaded from KDL
    ptuDefinition*: PtuDefinitionConfig
    transferCosts*: TransferCostsConfig
    transferTime*: TransferTimeConfig
    transferModifiers*: TransferModifiersConfig
    transferLimits*: TransferLimitsConfig
    transferRisks*: TransferRisksConfig
    recruitment*: RecruitmentConfig
    aiStrategy*: AiStrategyConfig

