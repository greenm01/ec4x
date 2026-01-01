import std/tables
import ../starmap  # Import PlanetClass and ResourceRating from starmap
export PlanetClass, ResourceRating  # Re-export for other config modules

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
    ## Configuration for raw material extraction efficiency multipliers
    multipliers*: array[ResourceRating, array[PlanetClass, float32]]

  TaxMechanicsConfig* = object
    taxAveragingWindowTurns*: int32

  TaxTierData* = object
    ## Data for a single tax tier (tier 1-5)
    minRate*: int32
    maxRate*: int32
    popMultiplier*: float32

  TaxPopulationGrowthConfig* = object
    ## Configuration for tax impact on population growth by tier
    tiers*: Table[int32, TaxTierData]

  IuCostScalingTier* = object
    ## Cost scaling tier for IU investment (economy.md:3.4)
    threshold*: int32  # IU percentage threshold (relative to PU)
    multiplier*: float32  # Cost multiplier applied to baseCost

  IndustrialInvestmentConfig* = object
    baseCost*: int32
    costScaling*: Table[int32, IuCostScalingTier]  # Tier 1-5

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

