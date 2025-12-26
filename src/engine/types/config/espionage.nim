type
  EspionageEffectsConfig* = object
    techTheftSrpStolen*: int32
    lowSabotageDice*: string
    lowSabotageIuMin*: int32
    lowSabotageIuMax*: int32
    highSabotageDice*: string
    highSabotageIuMin*: int32
    highSabotageIuMax*: int32
    assassinationSrpReduction*: float32
    assassinationDurationTurns*: int32
    economicDisruptionNcvReduction*: float32
    economicDisruptionDurationTurns*: int32
    propagandaTaxReduction*: float32
    propagandaDurationTurns*: int32
    cyberAttackEffect*: string

  DetectionConfig* = object
    failedEspionagePrestigeLoss*: int32

  DiplomacyConfig* = object ## Complete diplomacy configuration loaded from KDL
    espionageEffects*: EspionageEffectsConfig
    detection*: DetectionConfig

