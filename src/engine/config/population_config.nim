## Population Configuration Loader
##
## Loads population transfer settings from config/population.kdl
## Defines PTU (Population Transfer Unit) size and Space Guild transfer rules

import kdl
import kdl_config_helpers
import ../../common/logger
import ../types/config

proc parsePtuDefinition(node: KdlNode, ctx: var KdlConfigContext): PtuDefinitionConfig =
  result = PtuDefinitionConfig(
    soulsPerPtu: node.requireInt32("soulsPerPtu", ctx),
    ptuSizeMillions: node.requireFloat32("ptuSizeMillions", ctx),
    minPopulationRemaining: node.requireInt32("minPopulationRemaining", ctx)
  )

proc parseTransferCosts(node: KdlNode, ctx: var KdlConfigContext): TransferCostsConfig =
  result = TransferCostsConfig(
    edenCost: node.requireInt32("edenCost", ctx),
    lushCost: node.requireInt32("lushCost", ctx),
    benignCost: node.requireInt32("benignCost", ctx),
    harshCost: node.requireInt32("harshCost", ctx),
    hostileCost: node.requireInt32("hostileCost", ctx),
    desolateCost: node.requireInt32("desolateCost", ctx),
    extremeCost: node.requireInt32("extremeCost", ctx)
  )

proc parseTransferTime(node: KdlNode, ctx: var KdlConfigContext): TransferTimeConfig =
  result = TransferTimeConfig(
    turnsPerJump: node.requireInt32("turnsPerJump", ctx),
    minimumTurns: node.requireInt32("minimumTurns", ctx)
  )

proc parseTransferModifiers(node: KdlNode, ctx: var KdlConfigContext): TransferModifiersConfig =
  result = TransferModifiersConfig(
    costIncreasePerJump: node.requireFloat32("costIncreasePerJump", ctx)
  )

proc parseTransferLimits(node: KdlNode, ctx: var KdlConfigContext): TransferLimitsConfig =
  result = TransferLimitsConfig(
    minPtuTransfer: node.requireInt32("minPtuTransfer", ctx),
    minSourcePuRemaining: node.requireInt32("minSourcePuRemaining", ctx),
    maxConcurrentTransfers: node.requireInt32("maxConcurrentTransfers", ctx)
  )

proc parseTransferRisks(node: KdlNode, ctx: var KdlConfigContext): TransferRisksConfig =
  result = TransferRisksConfig(
    sourceConqueredBehavior: node.requireString("sourceConqueredBehavior", ctx),
    destConqueredBehavior: node.requireString("destConqueredBehavior", ctx),
    destBlockadedBehavior: node.requireString("destBlockadedBehavior", ctx),
    destCollapsedBehavior: node.requireString("destCollapsedBehavior", ctx)
  )

proc parseRecruitment(node: KdlNode, ctx: var KdlConfigContext): RecruitmentConfig =
  result = RecruitmentConfig(
    minViablePopulation: node.requireInt32("minViablePopulation", ctx)
  )

proc parseAiStrategy(node: KdlNode, ctx: var KdlConfigContext): AiStrategyConfig =
  result = AiStrategyConfig(
    minTreasuryForTransfer: node.requireInt32("minTreasuryForTransfer", ctx),
    minSourcePopulation: node.requireInt32("minSourcePopulation", ctx),
    maxDestPopulation: node.requireInt32("maxDestPopulation", ctx),
    recentColonyAgeTurns: node.requireInt32("recentColonyAgeTurns", ctx),
    ptuPerTransfer: node.requireInt32("ptuPerTransfer", ctx),
    minEconomicFocus: node.requireFloat32("minEconomicFocus", ctx),
    minExpansionDrive: node.requireFloat32("minExpansionDrive", ctx)
  )

proc loadPopulationConfig*(
    configPath: string = "config/population.kdl"
): PopulationConfig =
  ## Load population configuration from KDL file
  ## Uses kdl_config_helpers for type-safe parsing
  let doc = loadKdlConfig(configPath)
  var ctx = newContext(configPath)

  ctx.withNode("ptuDefinition"):
    let node = doc.requireNode("ptuDefinition", ctx)
    result.ptuDefinition = parsePtuDefinition(node, ctx)

  ctx.withNode("transferCosts"):
    let node = doc.requireNode("transferCosts", ctx)
    result.transferCosts = parseTransferCosts(node, ctx)

  ctx.withNode("transferTime"):
    let node = doc.requireNode("transferTime", ctx)
    result.transferTime = parseTransferTime(node, ctx)

  ctx.withNode("transferModifiers"):
    let node = doc.requireNode("transferModifiers", ctx)
    result.transferModifiers = parseTransferModifiers(node, ctx)

  ctx.withNode("transferLimits"):
    let node = doc.requireNode("transferLimits", ctx)
    result.transferLimits = parseTransferLimits(node, ctx)

  ctx.withNode("transferRisks"):
    let node = doc.requireNode("transferRisks", ctx)
    result.transferRisks = parseTransferRisks(node, ctx)

  ctx.withNode("recruitment"):
    let node = doc.requireNode("recruitment", ctx)
    result.recruitment = parseRecruitment(node, ctx)

  ctx.withNode("aiStrategy"):
    let node = doc.requireNode("aiStrategy", ctx)
    result.aiStrategy = parseAiStrategy(node, ctx)

  logInfo("Config", "Loaded population configuration", "path=", configPath)

## Global configuration instance

var config: PopulationConfig = loadPopulationConfig()

## Accessors for commonly-used values

proc soulsPerPtu*(): int32 =
  config.ptuDefinition.soulsPerPtu

proc ptuSizeMillions*(): float32 =
  config.ptuDefinition.ptuSizeMillions

proc minViablePopulation*(): int32 =
  config.recruitment.minViablePopulation

## Helper to reload configuration (for testing)

proc reloadPopulationConfig*() =
  ## Reload configuration from file
  config = loadPopulationConfig()
