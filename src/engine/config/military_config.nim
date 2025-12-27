## Military Configuration Loader
##
## Loads military mechanics from config/military.kdl using nimkdl
## Allows runtime configuration for squadron limits and salvage

import kdl
import kdl_helpers
import ../../common/logger
import ../types/config

proc parseFighterMechanics(node: KdlNode, ctx: var KdlConfigContext): FighterMechanicsConfig =
  result = FighterMechanicsConfig(
    fighterCapacityIuDivisor: node.requireInt32("fighterCapacityIuDivisor", ctx),
    capacityViolationGracePeriod: node.requireInt32("capacityViolationGracePeriod", ctx)
  )

proc parseSquadronLimits(node: KdlNode, ctx: var KdlConfigContext): SquadronLimitsConfig =
  result = SquadronLimitsConfig(
    squadronLimitIuDivisor: node.requireInt32("squadronLimitIuDivisor", ctx),
    squadronLimitMinimum: node.requireInt32("squadronLimitMinimum", ctx),
    totalSquadronIuDivisor: node.requireInt32("totalSquadronIuDivisor", ctx),
    totalSquadronMinimum: node.requireInt32("totalSquadronMinimum", ctx),
    capitalShipCrThreshold: node.requireInt32("capitalShipCrThreshold", ctx)
  )

proc parseSpaceLiftCapacity(node: KdlNode, ctx: var KdlConfigContext): SpaceLiftCapacityConfig =
  result = SpaceLiftCapacityConfig(
    etacCapacity: node.requireInt32("etacCapacity", ctx)
  )

proc loadMilitaryConfig*(configPath: string = "config/military.kdl"): MilitaryConfig =
  ## Load military configuration from KDL file
  ## Uses kdl_config_helpers for type-safe parsing
  let doc = loadKdlConfig(configPath)
  var ctx = newContext(configPath)

  ctx.withNode("fighterMechanics"):
    let fighterNode = doc.requireNode("fighterMechanics", ctx)
    result.fighterMechanics = parseFighterMechanics(fighterNode, ctx)

  ctx.withNode("squadronLimits"):
    let squadronNode = doc.requireNode("squadronLimits", ctx)
    result.squadronLimits = parseSquadronLimits(squadronNode, ctx)

  ctx.withNode("spaceliftCapacity"):
    let spaceliftNode = doc.requireNode("spaceliftCapacity", ctx)
    result.spaceliftCapacity = parseSpaceLiftCapacity(spaceliftNode, ctx)

  logInfo("Config", "Loaded military configuration", "path=", configPath)
