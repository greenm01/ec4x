## Economy Configuration Loader
##
## Loads economy mechanics from config/economy.kdl
## Allows runtime configuration for population, production, research, taxation, colonization

import kdl
import kdl_helpers
import ../../common/logger
import ../types/config

proc parsePopulation(node: KdlNode, ctx: var KdlConfigContext): PopulationConfig =
  result = PopulationConfig(
    naturalGrowthRate: node.requireFloat32("naturalGrowthRate", ctx),
    growthRatePerStarbase:
      node.requireFloat32("growthRatePerStarbase", ctx),
    maxStarbaseBonus: node.requireFloat32("maxStarbaseBonus", ctx),
    ptuGrowthRate: node.requireFloat32("ptuGrowthRate", ctx),
    ptuToSouls: node.requireInt32("ptuToSouls", ctx),
    puToPtuConversion: node.requireFloat32("puToPtuConversion", ctx),
    minViableColonyPop: node.requireInt32("minViableColonyPop", ctx)
  )

proc parsePtuDefinition(node: KdlNode, ctx: var KdlConfigContext): PtuDefinitionConfig =
  result = PtuDefinitionConfig(
    soulsPerPtu: node.requireInt32("soulsPerPtu", ctx),
    ptuSizeMillions: node.requireFloat32("ptuSizeMillions", ctx),
    minPopulationRemaining: node.requireInt32("minPopulationRemaining", ctx)
  )

proc parseProduction(node: KdlNode, ctx: var KdlConfigContext): ProductionConfig =
  result = ProductionConfig(
    productionPer10Population:
      node.requireInt32("productionPer10Population", ctx),
    productionSplitCredits:
      node.requireFloat32("productionSplitCredits", ctx),
    productionSplitProduction:
      node.requireFloat32("productionSplitProduction", ctx),
    productionSplitResearch:
      node.requireFloat32("productionSplitResearch", ctx)
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
    extremePuMin: node.requireInt32("extremePuMin", ctx),
    extremePuMax: node.requireInt32("extremePuMax", ctx),
    desolatePuMin: node.requireInt32("desolatePuMin", ctx),
    desolatePuMax: node.requireInt32("desolatePuMax", ctx),
    hostilePuMin: node.requireInt32("hostilePuMin", ctx),
    hostilePuMax: node.requireInt32("hostilePuMax", ctx),
    harshPuMin: node.requireInt32("harshPuMin", ctx),
    harshPuMax: node.requireInt32("harshPuMax", ctx),
    benignPuMin: node.requireInt32("benignPuMin", ctx),
    benignPuMax: node.requireInt32("benignPuMax", ctx),
    lushPuMin: node.requireInt32("lushPuMin", ctx),
    lushPuMax: node.requireInt32("lushPuMax", ctx),
    edenPuMin: node.requireInt32("edenPuMin", ctx)
  )

proc parseResearch(node: KdlNode, ctx: var KdlConfigContext): ResearchConfig =
  result = ResearchConfig(
    researchCostBase: node.requireInt32("researchCostBase", ctx),
    researchCostExponent: node.requireInt32("researchCostExponent", ctx),
    researchBreakthroughBaseChance:
      node.requireFloat32("researchBreakthroughBaseChance", ctx),
    researchBreakthroughRpPerPercent:
      node.requireInt32("researchBreakthroughRpPerPercent", ctx),
    minorBreakthroughBonus:
      node.requireInt32("minorBreakthroughBonus", ctx),
    moderateBreakthroughDiscount:
      node.requireFloat32("moderateBreakthroughDiscount", ctx),
    revolutionaryQuantumComputingElModBonus:
      node.requireFloat32("revolutionaryQuantumComputingElModBonus", ctx),
    revolutionaryStealthDetectionBonus:
      node.requireInt32("revolutionaryStealthDetectionBonus", ctx),
    revolutionaryTerraformingGrowthBonus:
      node.requireFloat32("revolutionaryTerraformingGrowthBonus", ctx),
    erpBaseCost: node.requireInt32("erpBaseCost", ctx),
    elEarlyBase: node.requireInt32("elEarlyBase", ctx),
    elEarlyIncrement: node.requireInt32("elEarlyIncrement", ctx),
    elLateIncrement: node.requireInt32("elLateIncrement", ctx),
    srpBaseCost: node.requireInt32("srpBaseCost", ctx),
    srpSlMultiplier: node.requireFloat32("srpSlMultiplier", ctx),
    slEarlyBase: node.requireInt32("slEarlyBase", ctx),
    slEarlyIncrement: node.requireInt32("slEarlyIncrement", ctx),
    slLateIncrement: node.requireInt32("slLateIncrement", ctx),
    trpFirstLevelCost: node.requireInt32("trpFirstLevelCost", ctx),
    trpLevelIncrement: node.requireInt32("trpLevelIncrement", ctx)
  )

proc parseEspionage(node: KdlNode, ctx: var KdlConfigContext): EspionageConfig =
  result = EspionageConfig(
    ebpCostPerPoint: node.requireInt32("ebpCostPerPoint", ctx),
    cipCostPerPoint: node.requireInt32("cipCostPerPoint", ctx),
    maxActionsPerTurn: node.requireInt32("maxActionsPerTurn", ctx),
    budgetThresholdPercent:
      node.requireInt32("budgetThresholdPercent", ctx),
    prestigeLossPerPercentOver:
      node.requireInt32("prestigeLossPerPercentOver", ctx),
    techTheftCost: node.requireInt32("techTheftCost", ctx),
    sabotageLowCost: node.requireInt32("sabotageLowCost", ctx),
    sabotageHighCost: node.requireInt32("sabotageHighCost", ctx),
    assassinationCost: node.requireInt32("assassinationCost", ctx),
    cyberAttackCost: node.requireInt32("cyberAttackCost", ctx),
    economicManipulationCost:
      node.requireInt32("economicManipulationCost", ctx),
    psyopsCampaignCost: node.requireInt32("psyopsCampaignCost", ctx),
    detectionRollCost: node.requireInt32("detectionRollCost", ctx)
  )

proc parseRawMaterialEfficiency(
  node: KdlNode,
  ctx: var KdlConfigContext
): RawMaterialEfficiencyConfig =
  result = RawMaterialEfficiencyConfig(
    veryPoorEden: node.requireFloat32("veryPoorEden", ctx),
    veryPoorLush: node.requireFloat32("veryPoorLush", ctx),
    veryPoorBenign: node.requireFloat32("veryPoorBenign", ctx),
    veryPoorHarsh: node.requireFloat32("veryPoorHarsh", ctx),
    veryPoorHostile: node.requireFloat32("veryPoorHostile", ctx),
    veryPoorDesolate: node.requireFloat32("veryPoorDesolate", ctx),
    veryPoorExtreme: node.requireFloat32("veryPoorExtreme", ctx),
    poorEden: node.requireFloat32("poorEden", ctx),
    poorLush: node.requireFloat32("poorLush", ctx),
    poorBenign: node.requireFloat32("poorBenign", ctx),
    poorHarsh: node.requireFloat32("poorHarsh", ctx),
    poorHostile: node.requireFloat32("poorHostile", ctx),
    poorDesolate: node.requireFloat32("poorDesolate", ctx),
    poorExtreme: node.requireFloat32("poorExtreme", ctx),
    abundantEden: node.requireFloat32("abundantEden", ctx),
    abundantLush: node.requireFloat32("abundantLush", ctx),
    abundantBenign: node.requireFloat32("abundantBenign", ctx),
    abundantHarsh: node.requireFloat32("abundantHarsh", ctx),
    abundantHostile: node.requireFloat32("abundantHostile", ctx),
    abundantDesolate: node.requireFloat32("abundantDesolate", ctx),
    abundantExtreme: node.requireFloat32("abundantExtreme", ctx),
    richEden: node.requireFloat32("richEden", ctx),
    richLush: node.requireFloat32("richLush", ctx),
    richBenign: node.requireFloat32("richBenign", ctx),
    richHarsh: node.requireFloat32("richHarsh", ctx),
    richHostile: node.requireFloat32("richHostile", ctx),
    richDesolate: node.requireFloat32("richDesolate", ctx),
    richExtreme: node.requireFloat32("richExtreme", ctx),
    veryRichEden: node.requireFloat32("veryRichEden", ctx),
    veryRichLush: node.requireFloat32("veryRichLush", ctx),
    veryRichBenign: node.requireFloat32("veryRichBenign", ctx),
    veryRichHarsh: node.requireFloat32("veryRichHarsh", ctx),
    veryRichHostile: node.requireFloat32("veryRichHostile", ctx),
    veryRichDesolate: node.requireFloat32("veryRichDesolate", ctx),
    veryRichExtreme: node.requireFloat32("veryRichExtreme", ctx)
  )

proc parseTaxMechanics(
  node: KdlNode,
  ctx: var KdlConfigContext
): TaxMechanicsConfig =
  result = TaxMechanicsConfig(
    taxAveragingWindowTurns:
      node.requireInt32("taxAveragingWindowTurns", ctx)
  )

proc parseTaxPopulationGrowth(
  node: KdlNode,
  ctx: var KdlConfigContext
): TaxPopulationGrowthConfig =
  result = TaxPopulationGrowthConfig(
    tier1Min: node.requireInt32("tier1Min", ctx),
    tier1Max: node.requireInt32("tier1Max", ctx),
    tier1PopMultiplier: node.requireFloat32("tier1PopMultiplier", ctx),
    tier2Min: node.requireInt32("tier2Min", ctx),
    tier2Max: node.requireInt32("tier2Max", ctx),
    tier2PopMultiplier: node.requireFloat32("tier2PopMultiplier", ctx),
    tier3Min: node.requireInt32("tier3Min", ctx),
    tier3Max: node.requireInt32("tier3Max", ctx),
    tier3PopMultiplier: node.requireFloat32("tier3PopMultiplier", ctx),
    tier4Min: node.requireInt32("tier4Min", ctx),
    tier4Max: node.requireInt32("tier4Max", ctx),
    tier4PopMultiplier: node.requireFloat32("tier4PopMultiplier", ctx),
    tier5Min: node.requireInt32("tier5Min", ctx),
    tier5Max: node.requireInt32("tier5Max", ctx),
    tier5PopMultiplier: node.requireFloat32("tier5PopMultiplier", ctx)
  )

proc parseIndustrialInvestment(
  node: KdlNode,
  ctx: var KdlConfigContext
): IndustrialInvestmentConfig =
  result = IndustrialInvestmentConfig(
    baseCost: node.requireInt32("baseCost", ctx),
    tier1MaxPercent: node.requireInt32("tier1MaxPercent", ctx),
    tier1Multiplier: node.requireFloat32("tier1Multiplier", ctx),
    tier1Pp: node.requireInt32("tier1Pp", ctx),
    tier2MinPercent: node.requireInt32("tier2MinPercent", ctx),
    tier2MaxPercent: node.requireInt32("tier2MaxPercent", ctx),
    tier2Multiplier: node.requireFloat32("tier2Multiplier", ctx),
    tier2Pp: node.requireInt32("tier2Pp", ctx),
    tier3MinPercent: node.requireInt32("tier3MinPercent", ctx),
    tier3MaxPercent: node.requireInt32("tier3MaxPercent", ctx),
    tier3Multiplier: node.requireFloat32("tier3Multiplier", ctx),
    tier3Pp: node.requireInt32("tier3Pp", ctx),
    tier4MinPercent: node.requireInt32("tier4MinPercent", ctx),
    tier4MaxPercent: node.requireInt32("tier4MaxPercent", ctx),
    tier4Multiplier: node.requireFloat32("tier4Multiplier", ctx),
    tier4Pp: node.requireInt32("tier4Pp", ctx),
    tier5MinPercent: node.requireInt32("tier5MinPercent", ctx),
    tier5Multiplier: node.requireFloat32("tier5Multiplier", ctx),
    tier5Pp: node.requireInt32("tier5Pp", ctx)
  )

proc parseColonization(
  node: KdlNode,
  ctx: var KdlConfigContext
): ColonizationConfig =
  result = ColonizationConfig(
    startingInfrastructureLevel:
      node.requireInt32("startingInfrastructureLevel", ctx),
    startingIuPercent: node.requireInt32("startingIuPercent", ctx),
    edenPpPerPtu: node.requireInt32("edenPpPerPtu", ctx),
    lushPpPerPtu: node.requireInt32("lushPpPerPtu", ctx),
    benignPpPerPtu: node.requireInt32("benignPpPerPtu", ctx),
    harshPpPerPtu: node.requireInt32("harshPpPerPtu", ctx),
    hostilePpPerPtu: node.requireInt32("hostilePpPerPtu", ctx),
    desolatePpPerPtu: node.requireInt32("desolatePpPerPtu", ctx),
    extremePpPerPtu: node.requireInt32("extremePpPerPtu", ctx)
  )

proc parseIndustrialGrowth(
  node: KdlNode,
  ctx: var KdlConfigContext
): IndustrialGrowthConfig =
  result = IndustrialGrowthConfig(
    passiveGrowthDivisor:
      node.requireFloat32("passiveGrowthDivisor", ctx),
    passiveGrowthMinimum:
      node.requireFloat32("passiveGrowthMinimum", ctx),
    appliesModifiers: node.requireBool("appliesModifiers", ctx)
  )

proc parseStarbaseBonuses(
  node: KdlNode,
  ctx: var KdlConfigContext
): StarbaseBonusesConfig =
  result = StarbaseBonusesConfig(
    growthBonusPerStarbase:
      node.requireFloat32("growthBonusPerStarbase", ctx),
    maxStarbasesForBonus: node.requireInt32("maxStarbasesForBonus", ctx),
    eliBonusPerStarbase: node.requireInt32("eliBonusPerStarbase", ctx)
  )

proc parseSquadronCapacity(
  node: KdlNode,
  ctx: var KdlConfigContext
): SquadronCapacityConfig =
  result = SquadronCapacityConfig(
    capitalSquadronIuDivisor:
      node.requireInt32("capitalSquadronIuDivisor", ctx),
    capitalSquadronMultiplier:
      node.requireInt32("capitalSquadronMultiplier", ctx),
    capitalSquadronMinimum:
      node.requireInt32("capitalSquadronMinimum", ctx)
  )

proc parseProductionModifiers(
  node: KdlNode,
  ctx: var KdlConfigContext
): ProductionModifiersConfig =
  result = ProductionModifiersConfig(
    elBonusPerLevel: node.requireFloat32("elBonusPerLevel", ctx),
    cstBonusPerLevel: node.requireFloat32("cstBonusPerLevel", ctx),
    blockadePenalty: node.requireFloat32("blockadePenalty", ctx),
    prodGrowthNumerator: node.requireFloat32("prodGrowthNumerator", ctx),
    prodGrowthDenominator:
      node.requireFloat32("prodGrowthDenominator", ctx)
  )

proc loadEconomyConfig*(configPath: string = "config/economy.kdl"): EconomyConfig =
  ## Load economy configuration from KDL file
  ## Uses kdl_config_helpers for type-safe parsing
  let doc = loadKdlConfig(configPath)
  var ctx = newContext(configPath)

  ctx.withNode("population"):
    let node = doc.requireNode("population", ctx)
    result.population = parsePopulation(node, ctx)

  ctx.withNode("ptuDefinition"):
    let node = doc.requireNode("ptuDefinition", ctx)
    result.ptuDefinition = parsePtuDefinition(node, ctx)

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
