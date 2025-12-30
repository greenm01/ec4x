type
  PopulationConfig* = object
    naturalGrowthRate*: float32
    growthRatePerStarbase*: float32
    maxStarbaseBonus*: float32
    ptuGrowthRate*: float32
    ptuToSouls*: int32
    puToPtuConversion*: float32
    minViableColonyPop*: int32

  PtuDefinitionConfig* = object
    soulsPerPtu*: int32
    ptuSizeMillions*: float32
    minPopulationRemaining*: int32

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

  ColonizationConfig* = object
    startingInfrastructureLevel*: int32
    startingIuPercent*: int32

  IndustrialGrowthConfig* = object
    passiveGrowthDivisor*: float32
    passiveGrowthMinimum*: float32

  StarbaseBonusesConfig* = object
    populationGrowthBonusPerStarbase*: float32
    industrialProductionBonusPerStarbase*: float32
    eliBonusPerStarbase*: int32

  ProductionModifiersConfig* = object
    blockadePenalty*: float32

  EconomyConfig* = object ## Complete economy configuration loaded from KDL
    population*: PopulationConfig
    ptuDefinition*: PtuDefinitionConfig
    rawMaterialEfficiency*: RawMaterialEfficiencyConfig
    taxMechanics*: TaxMechanicsConfig
    taxPopulationGrowth*: TaxPopulationGrowthConfig
    industrialInvestment*: IndustrialInvestmentConfig
    colonization*: ColonizationConfig
    industrialGrowth*: IndustrialGrowthConfig
    starbaseBonuses*: StarbaseBonusesConfig
    productionModifiers*: ProductionModifiersConfig

