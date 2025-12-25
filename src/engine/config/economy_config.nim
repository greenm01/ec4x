## Economy Configuration Loader
##
## Loads economy mechanics from config/economy.kdl
## Allows runtime configuration for population, production, research, taxation, colonization

import kdl
import kdl_config_helpers
import ../../common/logger

type
  PopulationConfig* = object
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
    population*: PopulationConfig
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

proc parsePopulation(node: KdlNode, ctx: var KdlConfigContext): PopulationConfig =
  result = PopulationConfig(
    naturalGrowthRate: node.requireFloat("naturalGrowthRate", ctx).float32,
    growthRatePerStarbase:
      node.requireFloat("growthRatePerStarbase", ctx).float32,
    maxStarbaseBonus: node.requireFloat("maxStarbaseBonus", ctx).float32,
    ptuGrowthRate: node.requireFloat("ptuGrowthRate", ctx).float32,
    ptuToSouls: node.requireInt("ptuToSouls", ctx).int32,
    puToPtuConversion: node.requireFloat("puToPtuConversion", ctx).float32
  )

proc parseProduction(node: KdlNode, ctx: var KdlConfigContext): ProductionConfig =
  result = ProductionConfig(
    productionPer10Population:
      node.requireInt("productionPer10Population", ctx).int32,
    productionSplitCredits:
      node.requireFloat("productionSplitCredits", ctx).float32,
    productionSplitProduction:
      node.requireFloat("productionSplitProduction", ctx).float32,
    productionSplitResearch:
      node.requireFloat("productionSplitResearch", ctx).float32
  )

proc parseInfrastructure(
  node: KdlNode,
  ctx: var KdlConfigContext
): InfrastructureConfig =
  result = InfrastructureConfig()

proc parsePlanetClasses(
  node: KdlNode,
  ctx: var KdlConfigContext
): PlanetClassesConfig =
  result = PlanetClassesConfig(
    extremePuMin: node.requireInt("extremePuMin", ctx).int32,
    extremePuMax: node.requireInt("extremePuMax", ctx).int32,
    desolatePuMin: node.requireInt("desolatePuMin", ctx).int32,
    desolatePuMax: node.requireInt("desolatePuMax", ctx).int32,
    hostilePuMin: node.requireInt("hostilePuMin", ctx).int32,
    hostilePuMax: node.requireInt("hostilePuMax", ctx).int32,
    harshPuMin: node.requireInt("harshPuMin", ctx).int32,
    harshPuMax: node.requireInt("harshPuMax", ctx).int32,
    benignPuMin: node.requireInt("benignPuMin", ctx).int32,
    benignPuMax: node.requireInt("benignPuMax", ctx).int32,
    lushPuMin: node.requireInt("lushPuMin", ctx).int32,
    lushPuMax: node.requireInt("lushPuMax", ctx).int32,
    edenPuMin: node.requireInt("edenPuMin", ctx).int32
  )

proc parseResearch(node: KdlNode, ctx: var KdlConfigContext): ResearchConfig =
  result = ResearchConfig(
    researchCostBase: node.requireInt("researchCostBase", ctx).int32,
    researchCostExponent: node.requireInt("researchCostExponent", ctx).int32,
    researchBreakthroughBaseChance:
      node.requireFloat("researchBreakthroughBaseChance", ctx).float32,
    researchBreakthroughRpPerPercent:
      node.requireInt("researchBreakthroughRpPerPercent", ctx).int32,
    minorBreakthroughBonus:
      node.requireInt("minorBreakthroughBonus", ctx).int32,
    moderateBreakthroughDiscount:
      node.requireFloat("moderateBreakthroughDiscount", ctx).float32,
    revolutionaryQuantumComputingElModBonus:
      node.requireFloat("revolutionaryQuantumComputingElModBonus", ctx).float32,
    revolutionaryStealthDetectionBonus:
      node.requireInt("revolutionaryStealthDetectionBonus", ctx).int32,
    revolutionaryTerraformingGrowthBonus:
      node.requireFloat("revolutionaryTerraformingGrowthBonus", ctx).float32,
    erpBaseCost: node.requireInt("erpBaseCost", ctx).int32,
    elEarlyBase: node.requireInt("elEarlyBase", ctx).int32,
    elEarlyIncrement: node.requireInt("elEarlyIncrement", ctx).int32,
    elLateIncrement: node.requireInt("elLateIncrement", ctx).int32,
    srpBaseCost: node.requireInt("srpBaseCost", ctx).int32,
    srpSlMultiplier: node.requireFloat("srpSlMultiplier", ctx).float32,
    slEarlyBase: node.requireInt("slEarlyBase", ctx).int32,
    slEarlyIncrement: node.requireInt("slEarlyIncrement", ctx).int32,
    slLateIncrement: node.requireInt("slLateIncrement", ctx).int32,
    trpFirstLevelCost: node.requireInt("trpFirstLevelCost", ctx).int32,
    trpLevelIncrement: node.requireInt("trpLevelIncrement", ctx).int32
  )

proc parseEspionage(node: KdlNode, ctx: var KdlConfigContext): EspionageConfig =
  result = EspionageConfig(
    ebpCostPerPoint: node.requireInt("ebpCostPerPoint", ctx).int32,
    cipCostPerPoint: node.requireInt("cipCostPerPoint", ctx).int32,
    maxActionsPerTurn: node.requireInt("maxActionsPerTurn", ctx).int32,
    budgetThresholdPercent:
      node.requireInt("budgetThresholdPercent", ctx).int32,
    prestigeLossPerPercentOver:
      node.requireInt("prestigeLossPerPercentOver", ctx).int32,
    techTheftCost: node.requireInt("techTheftCost", ctx).int32,
    sabotageLowCost: node.requireInt("sabotageLowCost", ctx).int32,
    sabotageHighCost: node.requireInt("sabotageHighCost", ctx).int32,
    assassinationCost: node.requireInt("assassinationCost", ctx).int32,
    cyberAttackCost: node.requireInt("cyberAttackCost", ctx).int32,
    economicManipulationCost:
      node.requireInt("economicManipulationCost", ctx).int32,
    psyopsCampaignCost: node.requireInt("psyopsCampaignCost", ctx).int32,
    detectionRollCost: node.requireInt("detectionRollCost", ctx).int32
  )

proc parseRawMaterialEfficiency(
  node: KdlNode,
  ctx: var KdlConfigContext
): RawMaterialEfficiencyConfig =
  result = RawMaterialEfficiencyConfig(
    veryPoorEden: node.requireFloat("veryPoorEden", ctx).float32,
    veryPoorLush: node.requireFloat("veryPoorLush", ctx).float32,
    veryPoorBenign: node.requireFloat("veryPoorBenign", ctx).float32,
    veryPoorHarsh: node.requireFloat("veryPoorHarsh", ctx).float32,
    veryPoorHostile: node.requireFloat("veryPoorHostile", ctx).float32,
    veryPoorDesolate: node.requireFloat("veryPoorDesolate", ctx).float32,
    veryPoorExtreme: node.requireFloat("veryPoorExtreme", ctx).float32,
    poorEden: node.requireFloat("poorEden", ctx).float32,
    poorLush: node.requireFloat("poorLush", ctx).float32,
    poorBenign: node.requireFloat("poorBenign", ctx).float32,
    poorHarsh: node.requireFloat("poorHarsh", ctx).float32,
    poorHostile: node.requireFloat("poorHostile", ctx).float32,
    poorDesolate: node.requireFloat("poorDesolate", ctx).float32,
    poorExtreme: node.requireFloat("poorExtreme", ctx).float32,
    abundantEden: node.requireFloat("abundantEden", ctx).float32,
    abundantLush: node.requireFloat("abundantLush", ctx).float32,
    abundantBenign: node.requireFloat("abundantBenign", ctx).float32,
    abundantHarsh: node.requireFloat("abundantHarsh", ctx).float32,
    abundantHostile: node.requireFloat("abundantHostile", ctx).float32,
    abundantDesolate: node.requireFloat("abundantDesolate", ctx).float32,
    abundantExtreme: node.requireFloat("abundantExtreme", ctx).float32,
    richEden: node.requireFloat("richEden", ctx).float32,
    richLush: node.requireFloat("richLush", ctx).float32,
    richBenign: node.requireFloat("richBenign", ctx).float32,
    richHarsh: node.requireFloat("richHarsh", ctx).float32,
    richHostile: node.requireFloat("richHostile", ctx).float32,
    richDesolate: node.requireFloat("richDesolate", ctx).float32,
    richExtreme: node.requireFloat("richExtreme", ctx).float32,
    veryRichEden: node.requireFloat("veryRichEden", ctx).float32,
    veryRichLush: node.requireFloat("veryRichLush", ctx).float32,
    veryRichBenign: node.requireFloat("veryRichBenign", ctx).float32,
    veryRichHarsh: node.requireFloat("veryRichHarsh", ctx).float32,
    veryRichHostile: node.requireFloat("veryRichHostile", ctx).float32,
    veryRichDesolate: node.requireFloat("veryRichDesolate", ctx).float32,
    veryRichExtreme: node.requireFloat("veryRichExtreme", ctx).float32
  )

proc parseTaxMechanics(
  node: KdlNode,
  ctx: var KdlConfigContext
): TaxMechanicsConfig =
  result = TaxMechanicsConfig(
    taxAveragingWindowTurns:
      node.requireInt("taxAveragingWindowTurns", ctx).int32
  )

proc parseTaxPopulationGrowth(
  node: KdlNode,
  ctx: var KdlConfigContext
): TaxPopulationGrowthConfig =
  result = TaxPopulationGrowthConfig(
    tier1Min: node.requireInt("tier1Min", ctx).int32,
    tier1Max: node.requireInt("tier1Max", ctx).int32,
    tier1PopMultiplier: node.requireFloat("tier1PopMultiplier", ctx).float32,
    tier2Min: node.requireInt("tier2Min", ctx).int32,
    tier2Max: node.requireInt("tier2Max", ctx).int32,
    tier2PopMultiplier: node.requireFloat("tier2PopMultiplier", ctx).float32,
    tier3Min: node.requireInt("tier3Min", ctx).int32,
    tier3Max: node.requireInt("tier3Max", ctx).int32,
    tier3PopMultiplier: node.requireFloat("tier3PopMultiplier", ctx).float32,
    tier4Min: node.requireInt("tier4Min", ctx).int32,
    tier4Max: node.requireInt("tier4Max", ctx).int32,
    tier4PopMultiplier: node.requireFloat("tier4PopMultiplier", ctx).float32,
    tier5Min: node.requireInt("tier5Min", ctx).int32,
    tier5Max: node.requireInt("tier5Max", ctx).int32,
    tier5PopMultiplier: node.requireFloat("tier5PopMultiplier", ctx).float32
  )

proc parseIndustrialInvestment(
  node: KdlNode,
  ctx: var KdlConfigContext
): IndustrialInvestmentConfig =
  result = IndustrialInvestmentConfig(
    baseCost: node.requireInt("baseCost", ctx).int32,
    tier1MaxPercent: node.requireInt("tier1MaxPercent", ctx).int32,
    tier1Multiplier: node.requireFloat("tier1Multiplier", ctx).float32,
    tier1Pp: node.requireInt("tier1Pp", ctx).int32,
    tier2MinPercent: node.requireInt("tier2MinPercent", ctx).int32,
    tier2MaxPercent: node.requireInt("tier2MaxPercent", ctx).int32,
    tier2Multiplier: node.requireFloat("tier2Multiplier", ctx).float32,
    tier2Pp: node.requireInt("tier2Pp", ctx).int32,
    tier3MinPercent: node.requireInt("tier3MinPercent", ctx).int32,
    tier3MaxPercent: node.requireInt("tier3MaxPercent", ctx).int32,
    tier3Multiplier: node.requireFloat("tier3Multiplier", ctx).float32,
    tier3Pp: node.requireInt("tier3Pp", ctx).int32,
    tier4MinPercent: node.requireInt("tier4MinPercent", ctx).int32,
    tier4MaxPercent: node.requireInt("tier4MaxPercent", ctx).int32,
    tier4Multiplier: node.requireFloat("tier4Multiplier", ctx).float32,
    tier4Pp: node.requireInt("tier4Pp", ctx).int32,
    tier5MinPercent: node.requireInt("tier5MinPercent", ctx).int32,
    tier5Multiplier: node.requireFloat("tier5Multiplier", ctx).float32,
    tier5Pp: node.requireInt("tier5Pp", ctx).int32
  )

proc parseColonization(
  node: KdlNode,
  ctx: var KdlConfigContext
): ColonizationConfig =
  result = ColonizationConfig(
    startingInfrastructureLevel:
      node.requireInt("startingInfrastructureLevel", ctx).int32,
    startingIuPercent: node.requireInt("startingIuPercent", ctx).int32,
    edenPpPerPtu: node.requireInt("edenPpPerPtu", ctx).int32,
    lushPpPerPtu: node.requireInt("lushPpPerPtu", ctx).int32,
    benignPpPerPtu: node.requireInt("benignPpPerPtu", ctx).int32,
    harshPpPerPtu: node.requireInt("harshPpPerPtu", ctx).int32,
    hostilePpPerPtu: node.requireInt("hostilePpPerPtu", ctx).int32,
    desolatePpPerPtu: node.requireInt("desolatePpPerPtu", ctx).int32,
    extremePpPerPtu: node.requireInt("extremePpPerPtu", ctx).int32
  )

proc parseIndustrialGrowth(
  node: KdlNode,
  ctx: var KdlConfigContext
): IndustrialGrowthConfig =
  result = IndustrialGrowthConfig(
    passiveGrowthDivisor:
      node.requireFloat("passiveGrowthDivisor", ctx).float32,
    passiveGrowthMinimum:
      node.requireFloat("passiveGrowthMinimum", ctx).float32,
    appliesModifiers: node.requireBool("appliesModifiers", ctx)
  )

proc parseStarbaseBonuses(
  node: KdlNode,
  ctx: var KdlConfigContext
): StarbaseBonusesConfig =
  result = StarbaseBonusesConfig(
    growthBonusPerStarbase:
      node.requireFloat("growthBonusPerStarbase", ctx).float32,
    maxStarbasesForBonus: node.requireInt("maxStarbasesForBonus", ctx).int32,
    eliBonusPerStarbase: node.requireInt("eliBonusPerStarbase", ctx).int32
  )

proc parseSquadronCapacity(
  node: KdlNode,
  ctx: var KdlConfigContext
): SquadronCapacityConfig =
  result = SquadronCapacityConfig(
    capitalSquadronIuDivisor:
      node.requireInt("capitalSquadronIuDivisor", ctx).int32,
    capitalSquadronMultiplier:
      node.requireInt("capitalSquadronMultiplier", ctx).int32,
    capitalSquadronMinimum:
      node.requireInt("capitalSquadronMinimum", ctx).int32
  )

proc parseProductionModifiers(
  node: KdlNode,
  ctx: var KdlConfigContext
): ProductionModifiersConfig =
  result = ProductionModifiersConfig(
    elBonusPerLevel: node.requireFloat("elBonusPerLevel", ctx).float32,
    cstBonusPerLevel: node.requireFloat("cstBonusPerLevel", ctx).float32,
    blockadePenalty: node.requireFloat("blockadePenalty", ctx).float32,
    prodGrowthNumerator: node.requireFloat("prodGrowthNumerator", ctx).float32,
    prodGrowthDenominator:
      node.requireFloat("prodGrowthDenominator", ctx).float32
  )

proc loadEconomyConfig*(configPath: string = "config/economy.kdl"): EconomyConfig =
  ## Load economy configuration from KDL file
  ## Uses kdl_config_helpers for type-safe parsing
  let doc = loadKdlConfig(configPath)
  var ctx = newContext(configPath)

  ctx.withNode("population"):
    let node = doc.requireNode("population", ctx)
    result.population = parsePopulation(node, ctx)

  ctx.withNode("production"):
    let node = doc.requireNode("production", ctx)
    result.production = parseProduction(node, ctx)

  ctx.withNode("infrastructure"):
    let node = doc.requireNode("infrastructure", ctx)
    result.infrastructure = parseInfrastructure(node, ctx)

  ctx.withNode("planetClasses"):
    let node = doc.requireNode("planetClasses", ctx)
    result.planetClasses = parsePlanetClasses(node, ctx)

  ctx.withNode("research"):
    let node = doc.requireNode("research", ctx)
    result.research = parseResearch(node, ctx)

  ctx.withNode("espionage"):
    let node = doc.requireNode("espionage", ctx)
    result.espionage = parseEspionage(node, ctx)

  ctx.withNode("rawMaterialEfficiency"):
    let node = doc.requireNode("rawMaterialEfficiency", ctx)
    result.rawMaterialEfficiency = parseRawMaterialEfficiency(node, ctx)

  ctx.withNode("taxMechanics"):
    let node = doc.requireNode("taxMechanics", ctx)
    result.taxMechanics = parseTaxMechanics(node, ctx)

  ctx.withNode("taxPopulationGrowth"):
    let node = doc.requireNode("taxPopulationGrowth", ctx)
    result.taxPopulationGrowth = parseTaxPopulationGrowth(node, ctx)

  ctx.withNode("industrialInvestment"):
    let node = doc.requireNode("industrialInvestment", ctx)
    result.industrialInvestment = parseIndustrialInvestment(node, ctx)

  ctx.withNode("colonization"):
    let node = doc.requireNode("colonization", ctx)
    result.colonization = parseColonization(node, ctx)

  ctx.withNode("industrialGrowth"):
    let node = doc.requireNode("industrialGrowth", ctx)
    result.industrialGrowth = parseIndustrialGrowth(node, ctx)

  ctx.withNode("starbaseBonuses"):
    let node = doc.requireNode("starbaseBonuses", ctx)
    result.starbaseBonuses = parseStarbaseBonuses(node, ctx)

  ctx.withNode("squadronCapacity"):
    let node = doc.requireNode("squadronCapacity", ctx)
    result.squadronCapacity = parseSquadronCapacity(node, ctx)

  ctx.withNode("productionModifiers"):
    let node = doc.requireNode("productionModifiers", ctx)
    result.productionModifiers = parseProductionModifiers(node, ctx)

  logInfo("Config", "Loaded economy configuration", "path=", configPath)

## Global configuration instance

var globalEconomyConfig* = loadEconomyConfig()

## Helper to reload configuration (for testing)

proc reloadEconomyConfig*() =
  ## Reload configuration from file
  globalEconomyConfig = loadEconomyConfig()
