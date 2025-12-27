type
  EconomyPopulationConfig* = object
    naturalGrowthRate*: float32
    growthRatePerStarbase*: float32
    maxStarbaseBonus*: float32
    ptuGrowthRate*: float32
    ptuToSouls*: int32
    puToPtuConversion*: float32

  ProductionConfig* = object
    productionPer10Population*: int32
    productionSplitCredits*: float32
    productionSplitProduction*: float32
    productionSplitResearch*: float32

  InfrastructureConfig* = object

  PlanetClassesConfig* = object
    extremePuMin*: int32
    extremePuMax*: int32
    desolatePuMin*: int32
    desolatePuMax*: int32
    hostilePuMin*: int32
    hostilePuMax*: int32
    harshPuMin*: int32
    harshPuMax*: int32
    benignPuMin*: int32
    benignPuMax*: int32
    lushPuMin*: int32
    lushPuMax*: int32
    edenPuMin*: int32

  ResearchConfig* = object
    researchCostBase*: int32
    researchCostExponent*: int32
    researchBreakthroughBaseChance*: float32
    researchBreakthroughRpPerPercent*: int32
    minorBreakthroughBonus*: int32
    moderateBreakthroughDiscount*: float32
    revolutionaryQuantumComputingElModBonus*: float32
    revolutionaryStealthDetectionBonus*: int32
    revolutionaryTerraformingGrowthBonus*: float32
    erpBaseCost*: int32
    elEarlyBase*: int32
    elEarlyIncrement*: int32
    elLateIncrement*: int32
    srpBaseCost*: int32
    srpSlMultiplier*: float32
    slEarlyBase*: int32
    slEarlyIncrement*: int32
    slLateIncrement*: int32
    trpFirstLevelCost*: int32
    trpLevelIncrement*: int32

  EspionageConfig* = object
    ebpCostPerPoint*: int32
    cipCostPerPoint*: int32
    maxActionsPerTurn*: int32
    budgetThresholdPercent*: int32
    prestigeLossPerPercentOver*: int32
    techTheftCost*: int32
    sabotageLowCost*: int32
    sabotageHighCost*: int32
    assassinationCost*: int32
    cyberAttackCost*: int32
    economicManipulationCost*: int32
    psyopsCampaignCost*: int32
    detectionRollCost*: int32

  RawMaterialEfficiencyConfig* = object
    veryPoorEden*: float32
    veryPoorLush*: float32
    veryPoorBenign*: float32
    veryPoorHarsh*: float32
    veryPoorHostile*: float32
    veryPoorDesolate*: float32
    veryPoorExtreme*: float32
    poorEden*: float32
    poorLush*: float32
    poorBenign*: float32
    poorHarsh*: float32
    poorHostile*: float32
    poorDesolate*: float32
    poorExtreme*: float32
    abundantEden*: float32
    abundantLush*: float32
    abundantBenign*: float32
    abundantHarsh*: float32
    abundantHostile*: float32
    abundantDesolate*: float32
    abundantExtreme*: float32
    richEden*: float32
    richLush*: float32
    richBenign*: float32
    richHarsh*: float32
    richHostile*: float32
    richDesolate*: float32
    richExtreme*: float32
    veryRichEden*: float32
    veryRichLush*: float32
    veryRichBenign*: float32
    veryRichHarsh*: float32
    veryRichHostile*: float32
    veryRichDesolate*: float32
    veryRichExtreme*: float32

  TaxMechanicsConfig* = object
    taxAveragingWindowTurns*: int32

  TaxPopulationGrowthConfig* = object
    tier1Min*: int32
    tier1Max*: int32
    tier1PopMultiplier*: float32
    tier2Min*: int32
    tier2Max*: int32
    tier2PopMultiplier*: float32
    tier3Min*: int32
    tier3Max*: int32
    tier3PopMultiplier*: float32
    tier4Min*: int32
    tier4Max*: int32
    tier4PopMultiplier*: float32
    tier5Min*: int32
    tier5Max*: int32
    tier5PopMultiplier*: float32

  IndustrialInvestmentConfig* = object
    baseCost*: int32
    tier1MaxPercent*: int32
    tier1Multiplier*: float32
    tier1Pp*: int32
    tier2MinPercent*: int32
    tier2MaxPercent*: int32
    tier2Multiplier*: float32
    tier2Pp*: int32
    tier3MinPercent*: int32
    tier3MaxPercent*: int32
    tier3Multiplier*: float32
    tier3Pp*: int32
    tier4MinPercent*: int32
    tier4MaxPercent*: int32
    tier4Multiplier*: float32
    tier4Pp*: int32
    tier5MinPercent*: int32
    tier5Multiplier*: float32
    tier5Pp*: int32

  ColonizationConfig* = object
    startingInfrastructureLevel*: int32
    startingIuPercent*: int32
    edenPpPerPtu*: int32
    lushPpPerPtu*: int32
    benignPpPerPtu*: int32
    harshPpPerPtu*: int32
    hostilePpPerPtu*: int32
    desolatePpPerPtu*: int32
    extremePpPerPtu*: int32

  IndustrialGrowthConfig* = object
    passiveGrowthDivisor*: float32
    passiveGrowthMinimum*: float32
    appliesModifiers*: bool

  StarbaseBonusesConfig* = object
    growthBonusPerStarbase*: float32
    maxStarbasesForBonus*: int32
    eliBonusPerStarbase*: int32

  SquadronCapacityConfig* = object
    capitalSquadronIuDivisor*: int32
    capitalSquadronMultiplier*: int32
    capitalSquadronMinimum*: int32

  ProductionModifiersConfig* = object
    elBonusPerLevel*: float32
    cstBonusPerLevel*: float32
    blockadePenalty*: float32
    prodGrowthNumerator*: float32
    prodGrowthDenominator*: float32

  EconomyConfig* = object ## Complete economy configuration loaded from KDL
    population*: EconomyPopulationConfig
    production*: ProductionConfig
    infrastructure*: InfrastructureConfig
    planetClasses*: PlanetClassesConfig
    research*: ResearchConfig
    espionage*: EspionageConfig
    rawMaterialEfficiency*: RawMaterialEfficiencyConfig
    taxMechanics*: TaxMechanicsConfig
    taxPopulationGrowth*: TaxPopulationGrowthConfig
    industrialInvestment*: IndustrialInvestmentConfig
    colonization*: ColonizationConfig
    industrialGrowth*: IndustrialGrowthConfig
    starbaseBonuses*: StarbaseBonusesConfig
    squadronCapacity*: SquadronCapacityConfig
    productionModifiers*: ProductionModifiersConfig

