## Espionage Configuration Loader
##
## Loads espionage values from config/espionage.kdl using nimkdl
## Allows runtime configuration for balance testing

import kdl
import kdl_config_helpers
import ../../common/logger

type
  EspionageCostsConfig* = object
    ebpCostPp*: int
    cipCostPp*: int
    techTheftEbp*: int
    sabotageLowEbp*: int
    sabotageHighEbp*: int
    assassinationEbp*: int
    cyberAttackEbp*: int
    economicManipulationEbp*: int
    psyopsCampaignEbp*: int
    counterIntelSweepEbp*: int
    intelligenceTheftEbp*: int
    plantDisinformationEbp*: int

  EspionageInvestmentConfig* = object
    thresholdPercentage*: int
    penaltyPerPercent*: int

  EspionageDetectionConfig* = object
    cipPerRoll*: int
    cic0Threshold*: int
    cic1Threshold*: int
    cic2Threshold*: int
    cic3Threshold*: int
    cic4Threshold*: int
    cic5Threshold*: int
    cip0Modifier*: int
    cip1To5Modifier*: int
    cip6To10Modifier*: int
    cip11To15Modifier*: int
    cip16To20Modifier*: int
    cip21PlusModifier*: int

  EspionageEffectsConfig* = object
    techTheftSrp*: int
    sabotageLowDice*: int
    sabotageHighDice*: int
    assassinationSrpReduction*: int
    economicNcvReduction*: int
    psyopsTaxReduction*: int
    effectDurationTurns*: int
    failedEspionagePrestige*: int
    intelBlockDuration*: int
    disinformationDuration*: int
    disinformationMinVariance*: float
    disinformationMaxVariance*: float

  ScoutDetectionConfig* = object
    mesh2To3Scouts*: int
    mesh4To5Scouts*: int
    mesh6PlusScouts*: int
    starbaseEliBonus*: int
    dominantTechThreshold*: float
    maxEliLevel*: int

  EspionageConfig* = object ## Complete espionage configuration loaded from KDL
    costs*: EspionageCostsConfig
    investment*: EspionageInvestmentConfig
    detection*: EspionageDetectionConfig
    effects*: EspionageEffectsConfig
    scoutDetection*: ScoutDetectionConfig

proc parseCosts(node: KdlNode, ctx: var KdlConfigContext): EspionageCostsConfig =
  result = EspionageCostsConfig(
    ebpCostPp: node.requireInt("ebpCostPp", ctx),
    cipCostPp: node.requireInt("cipCostPp", ctx),
    techTheftEbp: node.requireInt("techTheftEbp", ctx),
    sabotageLowEbp: node.requireInt("sabotageLowEbp", ctx),
    sabotageHighEbp: node.requireInt("sabotageHighEbp", ctx),
    assassinationEbp: node.requireInt("assassinationEbp", ctx),
    cyberAttackEbp: node.requireInt("cyberAttackEbp", ctx),
    economicManipulationEbp: node.requireInt("economicManipulationEbp", ctx),
    psyopsCampaignEbp: node.requireInt("psyopsCampaignEbp", ctx),
    counterIntelSweepEbp: node.requireInt("counterIntelSweepEbp", ctx),
    intelligenceTheftEbp: node.requireInt("intelligenceTheftEbp", ctx),
    plantDisinformationEbp: node.requireInt("plantDisinformationEbp", ctx)
  )

proc parseInvestment(node: KdlNode, ctx: var KdlConfigContext): EspionageInvestmentConfig =
  result = EspionageInvestmentConfig(
    thresholdPercentage: node.requireInt("thresholdPercentage", ctx),
    penaltyPerPercent: node.requireInt("penaltyPerPercent", ctx)
  )

proc parseDetection(node: KdlNode, ctx: var KdlConfigContext): EspionageDetectionConfig =
  result = EspionageDetectionConfig(
    cipPerRoll: node.requireInt("cipPerRoll", ctx),
    cic0Threshold: node.requireInt("cic0Threshold", ctx),
    cic1Threshold: node.requireInt("cic1Threshold", ctx),
    cic2Threshold: node.requireInt("cic2Threshold", ctx),
    cic3Threshold: node.requireInt("cic3Threshold", ctx),
    cic4Threshold: node.requireInt("cic4Threshold", ctx),
    cic5Threshold: node.requireInt("cic5Threshold", ctx),
    cip0Modifier: node.requireInt("cip0Modifier", ctx),
    cip1To5Modifier: node.requireInt("cip1To5Modifier", ctx),
    cip6To10Modifier: node.requireInt("cip6To10Modifier", ctx),
    cip11To15Modifier: node.requireInt("cip11To15Modifier", ctx),
    cip16To20Modifier: node.requireInt("cip16To20Modifier", ctx),
    cip21PlusModifier: node.requireInt("cip21PlusModifier", ctx)
  )

proc parseEffects(node: KdlNode, ctx: var KdlConfigContext): EspionageEffectsConfig =
  result = EspionageEffectsConfig(
    techTheftSrp: node.requireInt("techTheftSrp", ctx),
    sabotageLowDice: node.requireInt("sabotageLowDice", ctx),
    sabotageHighDice: node.requireInt("sabotageHighDice", ctx),
    assassinationSrpReduction: node.requireInt("assassinationSrpReduction", ctx),
    economicNcvReduction: node.requireInt("economicNcvReduction", ctx),
    psyopsTaxReduction: node.requireInt("psyopsTaxReduction", ctx),
    effectDurationTurns: node.requireInt("effectDurationTurns", ctx),
    failedEspionagePrestige: node.requireInt("failedEspionagePrestige", ctx),
    intelBlockDuration: node.requireInt("intelBlockDuration", ctx),
    disinformationDuration: node.requireInt("disinformationDuration", ctx),
    disinformationMinVariance: node.requireFloat("disinformationMinVariance", ctx),
    disinformationMaxVariance: node.requireFloat("disinformationMaxVariance", ctx)
  )

proc parseScoutDetection(node: KdlNode, ctx: var KdlConfigContext): ScoutDetectionConfig =
  result = ScoutDetectionConfig(
    mesh2To3Scouts: node.requireInt("mesh2To3Scouts", ctx),
    mesh4To5Scouts: node.requireInt("mesh4To5Scouts", ctx),
    mesh6PlusScouts: node.requireInt("mesh6PlusScouts", ctx),
    starbaseEliBonus: node.requireInt("starbaseEliBonus", ctx),
    dominantTechThreshold: node.requireFloat("dominantTechThreshold", ctx),
    maxEliLevel: node.requireInt("maxEliLevel", ctx)
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

## Global configuration instance

var globalEspionageConfig* = loadEspionageConfig()

## Helper to reload configuration (for testing)

proc reloadEspionageConfig*() =
  ## Reload configuration from file
  globalEspionageConfig = loadEspionageConfig()
