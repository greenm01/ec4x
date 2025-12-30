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

proc parseRawMaterialEfficiency(
  node: KdlNode,
  ctx: var KdlConfigContext
): RawMaterialEfficiencyConfig =
  ## Parse rawMaterialEfficiency with hierarchical material nodes
  ## Structure: material "Very Poor" { eden 0.60; lush 0.60; ... }
  result = RawMaterialEfficiencyConfig()

  for child in node.children:
    if child.name == "material" and child.args.len > 0:
      let materialType = child.args[0].getString()
      let eden = child.requireFloat32("eden", ctx)
      let lush = child.requireFloat32("lush", ctx)
      let benign = child.requireFloat32("benign", ctx)
      let harsh = child.requireFloat32("harsh", ctx)
      let hostile = child.requireFloat32("hostile", ctx)
      let desolate = child.requireFloat32("desolate", ctx)
      let extreme = child.requireFloat32("extreme", ctx)

      case materialType
      of "Very Poor":
        result.veryPoorEden = eden
        result.veryPoorLush = lush
        result.veryPoorBenign = benign
        result.veryPoorHarsh = harsh
        result.veryPoorHostile = hostile
        result.veryPoorDesolate = desolate
        result.veryPoorExtreme = extreme
      of "Poor":
        result.poorEden = eden
        result.poorLush = lush
        result.poorBenign = benign
        result.poorHarsh = harsh
        result.poorHostile = hostile
        result.poorDesolate = desolate
        result.poorExtreme = extreme
      of "Abundant":
        result.abundantEden = eden
        result.abundantLush = lush
        result.abundantBenign = benign
        result.abundantHarsh = harsh
        result.abundantHostile = hostile
        result.abundantDesolate = desolate
        result.abundantExtreme = extreme
      of "Rich":
        result.richEden = eden
        result.richLush = lush
        result.richBenign = benign
        result.richHarsh = harsh
        result.richHostile = hostile
        result.richDesolate = desolate
        result.richExtreme = extreme
      of "Very Rich":
        result.veryRichEden = eden
        result.veryRichLush = lush
        result.veryRichBenign = benign
        result.veryRichHarsh = harsh
        result.veryRichHostile = hostile
        result.veryRichDesolate = desolate
        result.veryRichExtreme = extreme
      else: discard

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
  ## Parse taxPopulationGrowth with hierarchical tier nodes
  ## Structure: tier 1 { minRate 41; maxRate 50; popMultiplier 1.0 }
  result = TaxPopulationGrowthConfig()

  for child in node.children:
    if child.name == "tier" and child.args.len > 0:
      let tierNum = child.args[0].getInt()
      let minRate = child.requireInt32("minRate", ctx)
      let maxRate = child.requireInt32("maxRate", ctx)
      let popMult = child.requireFloat32("popMultiplier", ctx)

      case tierNum
      of 1:
        result.tier1Min = minRate
        result.tier1Max = maxRate
        result.tier1PopMultiplier = popMult
      of 2:
        result.tier2Min = minRate
        result.tier2Max = maxRate
        result.tier2PopMultiplier = popMult
      of 3:
        result.tier3Min = minRate
        result.tier3Max = maxRate
        result.tier3PopMultiplier = popMult
      of 4:
        result.tier4Min = minRate
        result.tier4Max = maxRate
        result.tier4PopMultiplier = popMult
      of 5:
        result.tier5Min = minRate
        result.tier5Max = maxRate
        result.tier5PopMultiplier = popMult
      else: discard

proc parseIndustrialInvestment(
  node: KdlNode,
  ctx: var KdlConfigContext
): IndustrialInvestmentConfig =
  result = IndustrialInvestmentConfig(
    baseCost: node.requireInt32("baseCost", ctx)
  )

proc parseColonization(
  node: KdlNode,
  ctx: var KdlConfigContext
): ColonizationConfig =
  result = ColonizationConfig(
    startingInfrastructureLevel:
      node.requireInt32("startingInfrastructureLevel", ctx),
    startingIuPercent: node.requireInt32("startingIuPercent", ctx)
  )

proc parseIndustrialGrowth(
  node: KdlNode,
  ctx: var KdlConfigContext
): IndustrialGrowthConfig =
  result = IndustrialGrowthConfig(
    passiveGrowthDivisor:
      node.requireFloat32("passiveGrowthDivisor", ctx),
    passiveGrowthMinimum:
      node.requireFloat32("passiveGrowthMinimum", ctx)
  )

proc parseStarbaseBonuses(
  node: KdlNode,
  ctx: var KdlConfigContext
): StarbaseBonusesConfig =
  result = StarbaseBonusesConfig(
    populationGrowthBonusPerStarbase:
      node.requireFloat32("populationGrowthBonusPerStarbase", ctx),
    industrialProductionBonusPerStarbase:
      node.requireFloat32("industrialProductionBonusPerStarbase", ctx),
    eliBonusPerStarbase: node.requireInt32("eliBonusPerStarbase", ctx)
  )

proc parseProductionModifiers(
  node: KdlNode,
  ctx: var KdlConfigContext
): ProductionModifiersConfig =
  result = ProductionModifiersConfig(
    blockadePenalty: node.requireFloat32("blockadePenalty", ctx)
  )

proc loadEconomyConfig*(configPath: string): EconomyConfig =
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

  ctx.withNode("productionModifiers"):
    let node = doc.requireNode("productionModifiers", ctx)
    result.productionModifiers = parseProductionModifiers(node, ctx)

  logInfo("Config", "Loaded economy configuration", "path=", configPath)
