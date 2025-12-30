## Espionage Configuration Loader
##
## Loads espionage values from config/espionage.kdl using nimkdl
## Allows runtime configuration for balance testing

import kdl
import kdl_helpers
import ../../common/logger
import ../types/config

proc loadEspionageConfig*(configPath: string): EspionageConfig =
  ## Load espionage configuration from KDL file
  ## Uses kdl_config_helpers for type-safe parsing
  let doc = loadKdlConfig(configPath)
  var ctx = newContext(configPath)

  # Parse pointCosts (base costs)
  var costs: EspionageCostsConfig
  ctx.withNode("pointCosts"):
    let pointNode = doc.requireNode("pointCosts", ctx)
    costs.ebpCostPp = pointNode.requireInt32("ebpCostPp", ctx)
    costs.cipCostPp = pointNode.requireInt32("cipCostPp", ctx)

  # Parse actions (costs + effects combined)
  var effects: EspionageEffectsConfig
  ctx.withNode("actions"):
    let actionsNode = doc.requireNode("actions", ctx)
    for child in actionsNode.children:
      case child.name
      of "techTheft":
        costs.techTheftEbp = child.requireInt32("ebpCost", ctx)
        effects.techTheftSrp = child.requireInt32("srpStolen", ctx)
      of "sabotageLowImpact":
        costs.sabotageLowEbp = child.requireInt32("ebpCost", ctx)
        effects.sabotageLowDice = 6  # 1d6
      of "sabotageHighImpact":
        costs.sabotageHighEbp = child.requireInt32("ebpCost", ctx)
        effects.sabotageHighDice = 20  # 1d20
      of "assassination":
        costs.assassinationEbp = child.requireInt32("ebpCost", ctx)
        effects.assassinationSrpReduction = 50  # 50% reduction
      of "cyberAttack":
        costs.cyberAttackEbp = child.requireInt32("ebpCost", ctx)
      of "economicManipulation":
        costs.economicManipulationEbp = child.requireInt32("ebpCost", ctx)
        effects.economicNcvReduction = 50  # 50% reduction
      of "psyopsCampaign":
        costs.psyopsCampaignEbp = child.requireInt32("ebpCost", ctx)
        effects.psyopsTaxReduction = 25  # 25% reduction
      of "counterIntelligenceSweep":
        costs.counterIntelSweepEbp = child.requireInt32("ebpCost", ctx)
        effects.intelBlockDuration = child.requireInt32("intelBlockDurationTurns", ctx)
      of "intelligenceTheft":
        costs.intelligenceTheftEbp = child.requireInt32("ebpCost", ctx)
      of "plantDisinformation":
        costs.plantDisinformationEbp = child.requireInt32("ebpCost", ctx)
        effects.disinformationDuration = child.requireInt32("disinformationDurationTurns", ctx)
        effects.disinformationMinVariance = child.requireFloat32("minVariance", ctx)
        effects.disinformationMaxVariance = child.requireFloat32("maxVariance", ctx)
      else:
        discard

  effects.effectDurationTurns = 1  # Default
  effects.failedEspionagePrestige = -5  # Default penalty
  result.costs = costs
  result.effects = effects

  # Parse detection with hierarchical thresholds and modifiers
  var detection: EspionageDetectionConfig
  ctx.withNode("detection"):
    let detNode = doc.requireNode("detection", ctx)
    detection.cipPerRoll = detNode.requireInt32("cipConsumedPerRoll", ctx)

    # Parse thresholds child node
    for child in detNode.children:
      if child.name == "thresholds":
        detection.cic0Threshold = 20  # Default max
        detection.cic1Threshold = child.requireInt32("cic1", ctx)
        detection.cic2Threshold = child.requireInt32("cic2", ctx)
        detection.cic3Threshold = child.requireInt32("cic3", ctx)
        detection.cic4Threshold = child.requireInt32("cic4", ctx)
        detection.cic5Threshold = child.requireInt32("cic5", ctx)
      elif child.name == "modifiers":
        # Parse tier children
        for tier in child.children:
          if tier.name == "tier" and tier.args.len > 0:
            let tierName = tier.args[0].getString()
            let modifier = tier.requireInt32("modifier", ctx)
            case tierName
            of "1-5": detection.cip1To5Modifier = modifier
            of "6-10": detection.cip6To10Modifier = modifier
            of "11-15": detection.cip11To15Modifier = modifier
            of "16-20": detection.cip16To20Modifier = modifier
            of "21+": detection.cip21PlusModifier = modifier
            else: discard
        detection.cip0Modifier = 0  # Default for 0 CIP

  result.detection = detection

  logInfo("Config", "Loaded espionage configuration", "path=", configPath)
