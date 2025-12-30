## Population Configuration Loader
##
## Loads population transfer settings from config/population.kdl
## Defines PTU (Population Transfer Unit) size and Space Guild transfer rules

import kdl
import kdl_helpers
import ../../common/logger
import ../types/config

proc parseTransferCosts(node: KdlNode, ctx: var KdlConfigContext): TransferCostsConfig =
  ## Parse transferCosts with planetClass children
  ## Structure: planetClass "Eden" { cost 4 }
  var costs: array[7, int32]
  for child in node.children:
    if child.name == "planetClass" and child.args.len > 0:
      let planetClass = child.args[0].getString()
      let cost = child.requireInt32("cost", ctx)
      case planetClass
      of "Eden": costs[0] = cost
      of "Lush": costs[1] = cost
      of "Benign": costs[2] = cost
      of "Harsh": costs[3] = cost
      of "Hostile": costs[4] = cost
      of "Desolate": costs[5] = cost
      of "Extreme": costs[6] = cost
      else: discard

  result = TransferCostsConfig(
    edenCost: costs[0],
    lushCost: costs[1],
    benignCost: costs[2],
    harshCost: costs[3],
    hostileCost: costs[4],
    desolateCost: costs[5],
    extremeCost: costs[6]
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

proc loadGuildConfig*(configPath: string): GuildConfig =
  ## Load population configuration from KDL file
  ## Uses kdl_config_helpers for type-safe parsing
  let doc = loadKdlConfig(configPath)
  var ctx = newContext(configPath)

  # Parse guildMechanics parent node
  ctx.withNode("guildMechanics"):
    let guildNode = doc.requireNode("guildMechanics", ctx)
    for child in guildNode.children:
      case child.name
      of "transferCosts":
        ctx.withNode("transferCosts"):
          result.transferCosts = parseTransferCosts(child, ctx)
      of "transferLimits":
        ctx.withNode("transferLimits"):
          result.transferLimits = parseTransferLimits(child, ctx)
      of "transferRisks":
        ctx.withNode("transferRisks"):
          result.transferRisks = parseTransferRisks(child, ctx)
      else:
        discard

  # Parse aiStrategy (top-level node)
  ctx.withNode("aiStrategy"):
    let node = doc.requireNode("aiStrategy", ctx)
    result.aiStrategy = parseAiStrategy(node, ctx)

  logInfo("Config", "Loaded guild configuration", "path=", configPath)
