## Population Configuration Loader
##
## Loads population transfer settings from config/population.kdl
## Defines PTU (Population Transfer Unit) size and Space Guild transfer rules

import kdl
import kdl_config_helpers
import ../../common/logger

type
  PtuDefinitionConfig* = object
    soulsPerPtu*: int32
    ptuSizeMillions*: float32
    minPopulationRemaining*: int32

  TransferCostsConfig* = object
    edenCost*: int32
    lushCost*: int32
    benignCost*: int32
    harshCost*: int32
    hostileCost*: int32
    desolateCost*: int32
    extremeCost*: int32

  TransferTimeConfig* = object
    turnsPerJump*: int32
    minimumTurns*: int32

  TransferModifiersConfig* = object
    costIncreasePerJump*: float32

  TransferLimitsConfig* = object
    minPtuTransfer*: int32
    minSourcePuRemaining*: int32
    maxConcurrentTransfers*: int32

  TransferRisksConfig* = object
    sourceConqueredBehavior*: string
    destConqueredBehavior*: string
    destBlockadedBehavior*: string
    destCollapsedBehavior*: string

  RecruitmentConfig* = object
    minViablePopulation*: int32

  AiStrategyConfig* = object
    minTreasuryForTransfer*: int32
    minSourcePopulation*: int32
    maxDestPopulation*: int32
    recentColonyAgeTurns*: int32
    ptuPerTransfer*: int32
    minEconomicFocus*: float32
    minExpansionDrive*: float32

  PopulationConfig* = object ## Complete population configuration loaded from KDL
    ptuDefinition*: PtuDefinitionConfig
    transferCosts*: TransferCostsConfig
    transferTime*: TransferTimeConfig
    transferModifiers*: TransferModifiersConfig
    transferLimits*: TransferLimitsConfig
    transferRisks*: TransferRisksConfig
    recruitment*: RecruitmentConfig
    aiStrategy*: AiStrategyConfig

proc parsePtuDefinition(node: KdlNode, ctx: var KdlConfigContext): PtuDefinitionConfig =
  result = PtuDefinitionConfig(
    soulsPerPtu: node.requireInt("soulsPerPtu", ctx).int32,
    ptuSizeMillions: node.requireFloat("ptuSizeMillions", ctx).float32,
    minPopulationRemaining: node.requireInt("minPopulationRemaining", ctx).int32
  )

proc parseTransferCosts(node: KdlNode, ctx: var KdlConfigContext): TransferCostsConfig =
  result = TransferCostsConfig(
    edenCost: node.requireInt("edenCost", ctx).int32,
    lushCost: node.requireInt("lushCost", ctx).int32,
    benignCost: node.requireInt("benignCost", ctx).int32,
    harshCost: node.requireInt("harshCost", ctx).int32,
    hostileCost: node.requireInt("hostileCost", ctx).int32,
    desolateCost: node.requireInt("desolateCost", ctx).int32,
    extremeCost: node.requireInt("extremeCost", ctx).int32
  )

proc parseTransferTime(node: KdlNode, ctx: var KdlConfigContext): TransferTimeConfig =
  result = TransferTimeConfig(
    turnsPerJump: node.requireInt("turnsPerJump", ctx).int32,
    minimumTurns: node.requireInt("minimumTurns", ctx).int32
  )

proc parseTransferModifiers(node: KdlNode, ctx: var KdlConfigContext): TransferModifiersConfig =
  result = TransferModifiersConfig(
    costIncreasePerJump: node.requireFloat("costIncreasePerJump", ctx).float32
  )

proc parseTransferLimits(node: KdlNode, ctx: var KdlConfigContext): TransferLimitsConfig =
  result = TransferLimitsConfig(
    minPtuTransfer: node.requireInt("minPtuTransfer", ctx).int32,
    minSourcePuRemaining: node.requireInt("minSourcePuRemaining", ctx).int32,
    maxConcurrentTransfers: node.requireInt("maxConcurrentTransfers", ctx).int32
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
    minViablePopulation: node.requireInt("minViablePopulation", ctx).int32
  )

proc parseAiStrategy(node: KdlNode, ctx: var KdlConfigContext): AiStrategyConfig =
  result = AiStrategyConfig(
    minTreasuryForTransfer: node.requireInt("minTreasuryForTransfer", ctx).int32,
    minSourcePopulation: node.requireInt("minSourcePopulation", ctx).int32,
    maxDestPopulation: node.requireInt("maxDestPopulation", ctx).int32,
    recentColonyAgeTurns: node.requireInt("recentColonyAgeTurns", ctx).int32,
    ptuPerTransfer: node.requireInt("ptuPerTransfer", ctx).int32,
    minEconomicFocus: node.requireFloat("minEconomicFocus", ctx).float32,
    minExpansionDrive: node.requireFloat("minExpansionDrive", ctx).float32
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

## Initialize legacy global config (population/types.nim)
## TODO: Refactor to use new config structure throughout codebase

import ../types/population as pop_types

pop_types.globalPopulationConfig = pop_types.PopulationTransferConfig(
  soulsPerPtu: config.ptuDefinition.soulsPerPtu,
  ptuSizeMillions: config.ptuDefinition.ptuSizeMillions,
  edenCost: config.transferCosts.edenCost,
  lushCost: config.transferCosts.lushCost,
  benignCost: config.transferCosts.benignCost,
  harshCost: config.transferCosts.harshCost,
  hostileCost: config.transferCosts.hostileCost,
  desolateCost: config.transferCosts.desolateCost,
  extremeCost: config.transferCosts.extremeCost,
  turnsPerJump: config.transferTime.turnsPerJump,
  minimumTurns: config.transferTime.minimumTurns,
  costIncreasePerJump: config.transferModifiers.costIncreasePerJump,
  minPtuTransfer: config.transferLimits.minPtuTransfer,
  minSourcePuRemaining: config.transferLimits.minSourcePuRemaining,
  maxConcurrentTransfers: config.transferLimits.maxConcurrentTransfers,
  sourceConqueredBehavior: config.transferRisks.sourceConqueredBehavior,
  destConqueredBehavior: config.transferRisks.destConqueredBehavior,
  destBlockadedBehavior: config.transferRisks.destBlockadedBehavior,
  minTreasuryForTransfer: config.aiStrategy.minTreasuryForTransfer,
  minSourcePopulation: config.aiStrategy.minSourcePopulation,
  maxDestPopulation: config.aiStrategy.maxDestPopulation,
  recentColonyAgeTurns: config.aiStrategy.recentColonyAgeTurns,
  ptuPerTransfer: config.aiStrategy.ptuPerTransfer,
  minEconomicFocus: config.aiStrategy.minEconomicFocus,
  minExpansionDrive: config.aiStrategy.minExpansionDrive,
)
