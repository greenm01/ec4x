## Standing Orders Configuration Loader
## Loads standing command behavior settings from config/standing_orders.kdl

import kdl
import kdl_config_helpers
import ../../common/logger

type
  ActivationConfig* = object
    globalEnabled*: bool
    defaultActivationDelayTurns*: int
    enabledByDefault*: bool

  BehaviorConfig* = object
    autoHoldOnCompletion*: bool
    respectDiplomaticChanges*: bool

  UIHintsConfig* = object
    warnBeforeActivation*: bool
    warnTurnsBefore*: int

  StandingOrdersConfig* = object
    ## Complete standing commands configuration loaded from KDL
    activation*: ActivationConfig
    behavior*: BehaviorConfig
    uiHints*: UIHintsConfig

proc parseActivation(node: KdlNode, ctx: var KdlConfigContext): ActivationConfig =
  result = ActivationConfig(
    globalEnabled: node.requireBool("globalEnabled", ctx),
    defaultActivationDelayTurns: node.requireInt("defaultActivationDelayTurns", ctx),
    enabledByDefault: node.requireBool("enabledByDefault", ctx)
  )

proc parseBehavior(node: KdlNode, ctx: var KdlConfigContext): BehaviorConfig =
  result = BehaviorConfig(
    autoHoldOnCompletion: node.requireBool("autoHoldOnCompletion", ctx),
    respectDiplomaticChanges: node.requireBool("respectDiplomaticChanges", ctx)
  )

proc parseUIHints(node: KdlNode, ctx: var KdlConfigContext): UIHintsConfig =
  result = UIHintsConfig(
    warnBeforeActivation: node.requireBool("warnBeforeActivation", ctx),
    warnTurnsBefore: node.requireInt("warnTurnsBefore", ctx)
  )

proc loadStandingOrdersConfig*(
    configPath: string = "config/standing_orders.kdl"
): StandingOrdersConfig =
  ## Load standing commands configuration from KDL file
  ## Uses kdl_config_helpers for type-safe parsing
  let doc = loadKdlConfig(configPath)
  var ctx = newContext(configPath)

  ctx.withNode("activation"):
    let activationNode = doc.requireNode("activation", ctx)
    result.activation = parseActivation(activationNode, ctx)

  ctx.withNode("behavior"):
    let behaviorNode = doc.requireNode("behavior", ctx)
    result.behavior = parseBehavior(behaviorNode, ctx)

  ctx.withNode("uiHints"):
    let uiHintsNode = doc.requireNode("uiHints", ctx)
    result.uiHints = parseUIHints(uiHintsNode, ctx)

  logInfo("Config", "Loaded standing commands configuration", "path=", configPath)

## Global configuration instance

var globalStandingOrdersConfig* = loadStandingOrdersConfig()

## Helper to reload configuration (for testing)

proc reloadStandingOrdersConfig*() =
  ## Reload configuration from file
  globalStandingOrdersConfig = loadStandingOrdersConfig()
