## Diplomacy Configuration Loader
##
## Loads diplomacy values from config/diplomacy.kdl using nimkdl
## Allows runtime configuration for balance testing

import kdl
import kdl_helpers
import ../../common/logger
import ../types/config

proc parseEspionageEffects(node: KdlNode, ctx: var KdlConfigContext): EspionageEffectsConfig =
  result = EspionageEffectsConfig(
    techTheftSrpStolen: node.requireInt32("techTheftSrpStolen", ctx),
    lowSabotageDice: node.requireString("lowSabotageDice", ctx),
    lowSabotageIuMin: node.requireInt32("lowSabotageIuMin", ctx),
    lowSabotageIuMax: node.requireInt32("lowSabotageIuMax", ctx),
    highSabotageDice: node.requireString("highSabotageDice", ctx),
    highSabotageIuMin: node.requireInt32("highSabotageIuMin", ctx),
    highSabotageIuMax: node.requireInt32("highSabotageIuMax", ctx),
    assassinationSrpReduction: node.requireFloat32("assassinationSrpReduction", ctx),
    assassinationDurationTurns: node.requireInt32("assassinationDurationTurns", ctx),
    economicDisruptionNcvReduction: node.requireFloat32("economicDisruptionNcvReduction", ctx),
    economicDisruptionDurationTurns: node.requireInt32("economicDisruptionDurationTurns", ctx),
    propagandaTaxReduction: node.requireFloat32("propagandaTaxReduction", ctx),
    propagandaDurationTurns: node.requireInt32("propagandaDurationTurns", ctx),
    cyberAttackEffect: node.requireString("cyberAttackEffect", ctx)
  )

proc parseDetection(node: KdlNode, ctx: var KdlConfigContext): DetectionConfig =
  result = DetectionConfig(
    failedEspionagePrestigeLoss: node.requireInt32("failedEspionagePrestigeLoss", ctx)
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
