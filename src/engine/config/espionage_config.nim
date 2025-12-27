## Espionage Configuration Loader
##
## Loads espionage values from config/espionage.kdl using nimkdl
## Allows runtime configuration for balance testing

import kdl
import kdl_helpers
import ../../common/logger

proc parseCosts(node: KdlNode, ctx: var KdlConfigContext): EspionageCostsConfig =
  result = EspionageCostsConfig(
    ebpCostPp: node.requireInt32("ebpCostPp", ctx),
    cipCostPp: node.requireInt32("cipCostPp", ctx),
    techTheftEbp: node.requireInt32("techTheftEbp", ctx),
    sabotageLowEbp: node.requireInt32("sabotageLowEbp", ctx),
    sabotageHighEbp: node.requireInt32("sabotageHighEbp", ctx),
    assassinationEbp: node.requireInt32("assassinationEbp", ctx),
    cyberAttackEbp: node.requireInt32("cyberAttackEbp", ctx),
    economicManipulationEbp: node.requireInt32("economicManipulationEbp", ctx),
    psyopsCampaignEbp: node.requireInt32("psyopsCampaignEbp", ctx),
    counterIntelSweepEbp: node.requireInt32("counterIntelSweepEbp", ctx),
    intelligenceTheftEbp: node.requireInt32("intelligenceTheftEbp", ctx),
    plantDisinformationEbp: node.requireInt32("plantDisinformationEbp", ctx)
  )

proc parseInvestment(node: KdlNode, ctx: var KdlConfigContext): EspionageInvestmentConfig =
  result = EspionageInvestmentConfig(
    thresholdPercentage: node.requireInt32("thresholdPercentage", ctx),
    penaltyPerPercent: node.requireInt32("penaltyPerPercent", ctx)
  )

proc parseEffects(node: KdlNode, ctx: var KdlConfigContext): EspionageEffectsConfig =
  result = EspionageEffectsConfig(
    techTheftSrp: node.requireInt32("techTheftSrp", ctx),
    sabotageLowDice: node.requireInt32("sabotageLowDice", ctx),
    sabotageHighDice: node.requireInt32("sabotageHighDice", ctx),
    assassinationSrpReduction: node.requireInt32("assassinationSrpReduction", ctx),
    economicNcvReduction: node.requireInt32("economicNcvReduction", ctx),
    psyopsTaxReduction: node.requireInt32("psyopsTaxReduction", ctx),
    effectDurationTurns: node.requireInt32("effectDurationTurns", ctx),
    failedEspionagePrestige: node.requireInt32("failedEspionagePrestige", ctx),
    intelBlockDuration: node.requireInt32("intelBlockDuration", ctx),
    disinformationDuration: node.requireInt32("disinformationDuration", ctx),
    disinformationMinVariance: node.requireFloat32("disinformationMinVariance", ctx),
    disinformationMaxVariance: node.requireFloat32("disinformationMaxVariance", ctx)
  )

proc parseDetection(node: KdlNode, ctx: var KdlConfigContext): EspionageDetectionConfig =
  result = EspionageDetectionConfig(
    cipPerRoll: node.requireInt32("cipPerRoll", ctx),
    cic0Threshold: node.requireInt32("cic0Threshold", ctx),
    cic1Threshold: node.requireInt32("cic1Threshold", ctx),
    cic2Threshold: node.requireInt32("cic2Threshold", ctx),
    cic3Threshold: node.requireInt32("cic3Threshold", ctx),
    cic4Threshold: node.requireInt32("cic4Threshold", ctx),
    cic5Threshold: node.requireInt32("cic5Threshold", ctx),
    cip0Modifier: node.requireInt32("cip0Modifier", ctx),
    cip1To5Modifier: node.requireInt32("cip1To5Modifier", ctx),
    cip6To10Modifier: node.requireInt32("cip6To10Modifier", ctx),
    cip11To15Modifier: node.requireInt32("cip11To15Modifier", ctx),
    cip16To20Modifier: node.requireInt32("cip16To20Modifier", ctx),
    cip21PlusModifier: node.requireInt32("cip21PlusModifier", ctx)
  )

proc loadEspionageConfig*(
    configPath: string = "config/espionage.kdl"
): EspionageConfig =
  ## Load espionage configuration from KDL file
  ## Uses kdl_config_helpers for type-safe parsing
  let doc = loadKdlConfig(configPath)
  var ctx = newContext(configPath)

  ctx.withNode("costs"):
    let node = doc.requireNode("costs", ctx)
    result.costs = parseCosts(node, ctx)

  ctx.withNode("investment"):
    let node = doc.requireNode("investment", ctx)
    result.investment = parseInvestment(node, ctx)

  ctx.withNode("detection"):
    let node = doc.requireNode("detection", ctx)
    result.detection = parseDetection(node, ctx)

  ctx.withNode("effects"):
    let node = doc.requireNode("effects", ctx)
    result.effects = parseEffects(node, ctx)

  ctx.withNode("scoutDetection"):
    let node = doc.requireNode("scoutDetection", ctx)
    result.scoutDetection = parseScoutDetection(node, ctx)

  logInfo("Config", "Loaded espionage configuration", "path=", configPath)
