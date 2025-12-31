## Economy Configuration Loader
##
## Loads economy mechanics from config/economy.kdl
## Allows runtime configuration for population, production, research, taxation, colonization

import std/strutils
import kdl
import kdl_helpers
import ../../common/logger
import ../types/[config, starmap]

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
  ##
  ## Expected structure:
  ## ```kdl
  ## rawMaterialEfficiency {
  ##   material "Very Poor" {
  ##     eden 0.60; lush 0.60; benign 0.55; ...
  ##   }
  ##   material "Poor" { ... }
  ## }
  ## ```
  result = RawMaterialEfficiencyConfig()

  for child in node.children:
    if child.name == "material" and child.args.len > 0:
      # Parse resource rating from string like "Very Poor" -> VeryPoor
      let materialStr = child.args[0].getString().replace(" ", "")
      let quality = parseEnum[ResourceRating](materialStr)

      # Parse all planet class values
      result.multipliers[quality][PlanetClass.Eden] =
        child.requireFloat32("eden", ctx)
      result.multipliers[quality][PlanetClass.Lush] =
        child.requireFloat32("lush", ctx)
      result.multipliers[quality][PlanetClass.Benign] =
        child.requireFloat32("benign", ctx)
      result.multipliers[quality][PlanetClass.Harsh] =
        child.requireFloat32("harsh", ctx)
      result.multipliers[quality][PlanetClass.Hostile] =
        child.requireFloat32("hostile", ctx)
      result.multipliers[quality][PlanetClass.Desolate] =
        child.requireFloat32("desolate", ctx)
      result.multipliers[quality][PlanetClass.Extreme] =
        child.requireFloat32("extreme", ctx)

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
  ##
  ## Expected structure:
  ## ```kdl
  ## taxPopulationGrowth {
  ##   tier 1 { minRate 41; maxRate 50; popMultiplier 1.0 }
  ##   tier 2 { ... }
  ## }
  ## ```
  result = TaxPopulationGrowthConfig()

  for child in node.children:
    if child.name == "tier" and child.args.len > 0:
      let tierNum = child.args[0].getInt().int32

      # Store with actual tier number as key (1-5)
      if tierNum >= 1 and tierNum <= 5:
        result.tiers[tierNum] = TaxTierData(
          minRate: child.requireInt32("minRate", ctx),
          maxRate: child.requireInt32("maxRate", ctx),
          popMultiplier: child.requireFloat32("popMultiplier", ctx)
        )

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
