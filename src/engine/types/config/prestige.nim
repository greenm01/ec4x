type
  VictoryConfig* = object
    ## Victory config (prestige_victory removed - now in scenarios/*.kdl)
    startingPrestige*: int32
    defeatThreshold*: int32
    defeatConsecutiveTurns*: int32

  DynamicPrestigeConfig* = object
    enabled*: bool
    baseMultiplier*: float32
    baselineTurns*: int32
    baselineSystemsPerPlayer*: int32
    turnScalingFactor*: float32
    minMultiplier*: float32
    maxMultiplier*: float32

  MoraleConfig* = object
    crisisMax*: int32
    lowMax*: int32
    averageMax*: int32
    goodMax*: int32
    highMax*: int32

  EconomicPrestigeConfig* = object
    techAdvancement*: int32
    establishColony*: int32
    maxPopulation*: int32
    iuMilestone50*: int32
    iuMilestone75*: int32
    iuMilestone100*: int32
    iuMilestone150*: int32
    terraformPlanet*: int32

  MilitaryPrestigeConfig* = object
    destroySquadron*: int32
    destroyStarbase*: int32
    fleetVictory*: int32
    invadePlanet*: int32
    eliminateHouse*: int32
    systemCapture*: int32
    losePlanet*: int32
    loseStarbase*: int32
    ambushedByCloak*: int32
    forceRetreat*: int32
    forcedToRetreat*: int32
    scoutDestroyed*: int32
    undefendedColonyPenaltyMultiplier*: float32

  EspionagePrestigeConfig* = object
    techTheft*: int32
    lowImpactSabotage*: int32
    highImpactSabotage*: int32
    assassination*: int32
    cyberAttack*: int32
    economicManipulation*: int32
    psyopsCampaign*: int32
    counterIntelSweep*: int32
    intelligenceTheft*: int32
    plantDisinformation*: int32
    failedEspionage*: int32

  EspionageVictimPrestigeConfig* = object
    techTheftVictim*: int32
    lowImpactSabotageVictim*: int32
    highImpactSabotageVictim*: int32
    assassinationVictim*: int32
    cyberAttackVictim*: int32
    economicManipulationVictim*: int32
    psyopsCampaignVictim*: int32
    counterIntelSweepVictim*: int32
    intelligenceTheftVictim*: int32
    plantDisinformationVictim*: int32

  ScoutPrestigeConfig* = object
    spyOnPlanet*: int32
    hackStarbase*: int32
    spyOnSystem*: int32

  DiplomacyPrestigeConfig* = object
    declareWar*: int32
    makePeace*: int32

  VictoryAchievementConfig* = object
    victoryAchieved*: int32

  PenaltiesPrestigeConfig* = object
    highTaxThreshold*: int32
    highTaxPenalty*: int32
    highTaxFrequency*: int32
    veryHighTaxThreshold*: int32
    veryHighTaxPenalty*: int32
    veryHighTaxFrequency*: int32
    maintenanceShortfallBase*: int32
    maintenanceShortfallIncrement*: int32
    blockadePenalty*: int32
    overInvestEspionage*: int32
    overInvestCounterIntel*: int32

  TaxPenaltiesTier* = object
    tier1Min*: int32
    tier1Max*: int32
    tier1Penalty*: int32
    tier2Min*: int32
    tier2Max*: int32
    tier2Penalty*: int32
    tier3Min*: int32
    tier3Max*: int32
    tier3Penalty*: int32
    tier4Min*: int32
    tier4Max*: int32
    tier4Penalty*: int32
    tier5Min*: int32
    tier5Max*: int32
    tier5Penalty*: int32
    tier6Min*: int32
    tier6Max*: int32
    tier6Penalty*: int32

  TaxIncentivesTier* = object
    tier1Min*: int32
    tier1Max*: int32
    tier1Prestige*: int32
    tier2Min*: int32
    tier2Max*: int32
    tier2Prestige*: int32
    tier3Min*: int32
    tier3Max*: int32
    tier3Prestige*: int32
    tier4Min*: int32
    tier4Max*: int32
    tier4Prestige*: int32
    tier5Min*: int32
    tier5Max*: int32
    tier5Prestige*: int32

  PrestigeConfig* = object ## Complete prestige configuration loaded from KDL
    victory*: VictoryConfig
    dynamicScaling*: DynamicPrestigeConfig
    morale*: MoraleConfig
    economic*: EconomicPrestigeConfig
    military*: MilitaryPrestigeConfig
    espionage*: EspionagePrestigeConfig
    espionageVictim*: EspionageVictimPrestigeConfig
    scout*: ScoutPrestigeConfig
    diplomacy*: DiplomacyPrestigeConfig
    victoryAchievement*: VictoryAchievementConfig
    penalties*: PenaltiesPrestigeConfig
    taxPenalties*: TaxPenaltiesTier
    taxIncentives*: TaxIncentivesTier

