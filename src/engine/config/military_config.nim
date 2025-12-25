## Military Configuration Loader
##
## Loads military mechanics from config/military.kdl using nimkdl
## Allows runtime configuration for squadron limits and salvage

import kdl
import kdl_config_helpers
import ../../common/logger

type
  FighterMechanicsConfig* = object
    fighterCapacityIuDivisor*: int
    capacityViolationGracePeriod*: int

  SquadronLimitsConfig* = object
    squadronLimitIuDivisor*: int # IU divisor for capital squadron limit calculation
    squadronLimitMinimum*: int
    totalSquadronIuDivisor*: int # IU divisor for total squadron limit calculation
    totalSquadronMinimum*: int
    capitalShipCrThreshold*: int

  SalvageConfig* = object
    salvageValueMultiplier*: float
    emergencySalvageMultiplier*: float

  SpaceLiftCapacityConfig* = object
    etacCapacity*: int # Population Transfer Units per ETAC

  MilitaryConfig* = object ## Complete military configuration loaded from KDL
    fighterMechanics*: FighterMechanicsConfig
    squadronLimits*: SquadronLimitsConfig
    salvage*: SalvageConfig
    spaceliftCapacity*: SpaceLiftCapacityConfig

proc parseFighterMechanics(node: KdlNode, ctx: var KdlConfigContext): FighterMechanicsConfig =
  result = FighterMechanicsConfig(
    fighterCapacityIuDivisor: node.requireInt("fighterCapacityIuDivisor", ctx),
    capacityViolationGracePeriod: node.requireInt("capacityViolationGracePeriod", ctx)
  )

proc parseSquadronLimits(node: KdlNode, ctx: var KdlConfigContext): SquadronLimitsConfig =
  result = SquadronLimitsConfig(
    squadronLimitIuDivisor: node.requireInt("squadronLimitIuDivisor", ctx),
    squadronLimitMinimum: node.requireInt("squadronLimitMinimum", ctx),
    totalSquadronIuDivisor: node.requireInt("totalSquadronIuDivisor", ctx),
    totalSquadronMinimum: node.requireInt("totalSquadronMinimum", ctx),
    capitalShipCrThreshold: node.requireInt("capitalShipCrThreshold", ctx)
  )

proc parseSalvage(node: KdlNode, ctx: var KdlConfigContext): SalvageConfig =
  result = SalvageConfig(
    salvageValueMultiplier: node.requireFloat("salvageValueMultiplier", ctx),
    emergencySalvageMultiplier: node.requireFloat("emergencySalvageMultiplier", ctx)
  )

proc parseSpaceLiftCapacity(node: KdlNode, ctx: var KdlConfigContext): SpaceLiftCapacityConfig =
  result = SpaceLiftCapacityConfig(
    etacCapacity: node.requireInt("etacCapacity", ctx)
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

  ctx.withNode("salvage"):
    let salvageNode = doc.requireNode("salvage", ctx)
    result.salvage = parseSalvage(salvageNode, ctx)

  ctx.withNode("spaceliftCapacity"):
    let spaceliftNode = doc.requireNode("spaceliftCapacity", ctx)
    result.spaceliftCapacity = parseSpaceLiftCapacity(spaceliftNode, ctx)

  logInfo("Config", "Loaded military configuration", "path=", configPath)

## Global configuration instance

var globalMilitaryConfig* = loadMilitaryConfig()

## Helper to reload configuration (for testing)

proc reloadMilitaryConfig*() =
  ## Reload configuration from file
  globalMilitaryConfig = loadMilitaryConfig()
