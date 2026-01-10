import std/tables

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
    ## Placeholder for future morale-related configuration
    ## Morale tier thresholds are now relative to leader (see combat.kdl)
    placeholder*: bool  # Keep struct non-empty for config parsing

  IuMilestoneData* = object
    ## Prestige reward for reaching an IU milestone
    prestige*: int32

  EconomicPrestigeConfig* = object
    techAdvancement*: int32
    establishColony*: int32
    maxPopulation*: int32
    ## Per types-guide.md: Use Table[int32, T] for numbered sequences
    iuMilestones*: Table[int32, IuMilestoneData]  # Keys: 50, 75, 100, 150
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

  TaxPenaltyTierData* = object
    ## Data for a single tax penalty tier
    minRate*: int32
    maxRate*: int32
    penalty*: int32

  TaxPenaltiesTier* = object
    ## Tax penalties configuration
    ## Uses Table pattern for numbered tiers (see types-guide.md)
    tiers*: Table[int32, TaxPenaltyTierData]

  TaxIncentiveTierData* = object
    ## Data for a single tax incentive tier
    minRate*: int32
    maxRate*: int32
    prestige*: int32

  TaxIncentivesTier* = object
    ## Tax incentives configuration
    ## Uses Table pattern for numbered tiers (see types-guide.md)
    tiers*: Table[int32, TaxIncentiveTierData]

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

