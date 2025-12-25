## Diplomacy Configuration Loader
##
## Loads diplomacy values from config/diplomacy.kdl using nimkdl
## Allows runtime configuration for balance testing

import kdl
import kdl_config_helpers
import ../../common/logger

type
  EspionageEffectsConfig* = object
    techTheftSrpStolen*: int
    lowSabotageDice*: string
    lowSabotageIuMin*: int
    lowSabotageIuMax*: int
    highSabotageDice*: string
    highSabotageIuMin*: int
    highSabotageIuMax*: int
    assassinationSrpReduction*: float
    assassinationDurationTurns*: int
    economicDisruptionNcvReduction*: float
    economicDisruptionDurationTurns*: int
    propagandaTaxReduction*: float
    propagandaDurationTurns*: int
    cyberAttackEffect*: string

  DetectionConfig* = object
    failedEspionagePrestigeLoss*: int

  DiplomacyConfig* = object ## Complete diplomacy configuration loaded from KDL
    espionageEffects*: EspionageEffectsConfig
    detection*: DetectionConfig

proc parseEspionageEffects(node: KdlNode, ctx: var KdlConfigContext): EspionageEffectsConfig =
  result = EspionageEffectsConfig(
    techTheftSrpStolen: node.requireInt("techTheftSrpStolen", ctx),
    lowSabotageDice: node.requireString("lowSabotageDice", ctx),
    lowSabotageIuMin: node.requireInt("lowSabotageIuMin", ctx),
    lowSabotageIuMax: node.requireInt("lowSabotageIuMax", ctx),
    highSabotageDice: node.requireString("highSabotageDice", ctx),
    highSabotageIuMin: node.requireInt("highSabotageIuMin", ctx),
    highSabotageIuMax: node.requireInt("highSabotageIuMax", ctx),
    assassinationSrpReduction: node.requireFloat("assassinationSrpReduction", ctx),
    assassinationDurationTurns: node.requireInt("assassinationDurationTurns", ctx),
    economicDisruptionNcvReduction: node.requireFloat("economicDisruptionNcvReduction", ctx),
    economicDisruptionDurationTurns: node.requireInt("economicDisruptionDurationTurns", ctx),
    propagandaTaxReduction: node.requireFloat("propagandaTaxReduction", ctx),
    propagandaDurationTurns: node.requireInt("propagandaDurationTurns", ctx),
    cyberAttackEffect: node.requireString("cyberAttackEffect", ctx)
  )

proc parseDetection(node: KdlNode, ctx: var KdlConfigContext): DetectionConfig =
  result = DetectionConfig(
    failedEspionagePrestigeLoss: node.requireInt("failedEspionagePrestigeLoss", ctx)
  )

proc loadDiplomacyConfig*(
    configPath: string = "config/diplomacy.kdl"
): DiplomacyConfig =
  ## Load diplomacy configuration from KDL file
  ## Uses kdl_config_helpers for type-safe parsing
  let doc = loadKdlConfig(configPath)
  var ctx = newContext(configPath)

  ctx.withNode("espionageEffects"):
    let espNode = doc.requireNode("espionageEffects", ctx)
    result.espionageEffects = parseEspionageEffects(espNode, ctx)

  ctx.withNode("detection"):
    let detNode = doc.requireNode("detection", ctx)
    result.detection = parseDetection(detNode, ctx)

  logInfo("Config", "Loaded diplomacy configuration", "path=", configPath)

## Global configuration instance

var globalDiplomacyConfig* = loadDiplomacyConfig()

## Helper to reload configuration (for testing)

proc reloadDiplomacyConfig*() =
  ## Reload configuration from file
  globalDiplomacyConfig = loadDiplomacyConfig()
