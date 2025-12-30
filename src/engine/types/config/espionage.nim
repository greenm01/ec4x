type
  EspionageCostsConfig* = object
    ebpCostPp*: int32
    cipCostPp*: int32
    techTheftEbp*: int32
    sabotageLowEbp*: int32
    sabotageHighEbp*: int32
    assassinationEbp*: int32
    cyberAttackEbp*: int32
    economicManipulationEbp*: int32
    psyopsCampaignEbp*: int32
    counterIntelSweepEbp*: int32
    intelligenceTheftEbp*: int32
    plantDisinformationEbp*: int32

  EspionageEffectsConfig* = object
    techTheftSrp*: int32
    sabotageLowDice*: int32
    sabotageHighDice*: int32
    assassinationSrpReduction*: int32
    economicNcvReduction*: int32
    psyopsTaxReduction*: int32
    effectDurationTurns*: int32
    failedEspionagePrestige*: int32
    intelBlockDuration*: int32
    disinformationDuration*: int32
    disinformationMinVariance*: float32
    disinformationMaxVariance*: float32

  EspionageDetectionConfig* = object
    cipPerRoll*: int32
    cic0Threshold*: int32
    cic1Threshold*: int32
    cic2Threshold*: int32
    cic3Threshold*: int32
    cic4Threshold*: int32
    cic5Threshold*: int32
    cip0Modifier*: int32
    cip1To5Modifier*: int32
    cip6To10Modifier*: int32
    cip11To15Modifier*: int32
    cip16To20Modifier*: int32
    cip21PlusModifier*: int32

  EspionageConfig* = object ## Complete espionage configuration loaded from KDL
    costs*: EspionageCostsConfig
    effects*: EspionageEffectsConfig
    detection*: EspionageDetectionConfig
