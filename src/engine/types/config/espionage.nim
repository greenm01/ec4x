import std/tables

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

  CIPTierData* = object
    ## Data for a CIP (Counter-Intel Points) tier
    maxPoints*: int32  # Max CIP in this tier
    modifier*: int32   # Detection roll modifier

  EspionageDetectionConfig* = object
    ## Espionage detection configuration
    ## Uses Table for CIC thresholds, seq for ordered CIP tiers (see data-guide.md)
    cipPerRoll*: int32
    cicThresholds*: Table[int32, int32]  # CIC level → detection threshold
    cipTiers*: seq[CIPTierData]  # Ordered tiers for CIP modifiers

  EspionageConfig* = object ## Complete espionage configuration loaded from KDL
    costs*: EspionageCostsConfig
    effects*: EspionageEffectsConfig
    detection*: EspionageDetectionConfig
