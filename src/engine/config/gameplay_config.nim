## Gameplay Configuration Loader
##
## Loads gameplay mechanics from config/gameplay.kdl using nimkdl
## Allows runtime configuration for core game rules
## NOTE: Starting tech levels are in config/tech.kdl (see tech_config module)

import kdl
import kdl_helpers
import ../../common/logger
import ../types/config

proc parseElimination(node: KdlNode, ctx: var KdlConfigContext): EliminationConfig =
  result = EliminationConfig(
    defensiveCollapseTurns: node.requireInt32("defensiveCollapseTurns", ctx),
    defensiveCollapseThreshold: node.requireInt32("defensiveCollapseThreshold", ctx)
  )

proc parseAutopilot(node: KdlNode, ctx: var KdlConfigContext): AutopilotConfig =
  result = AutopilotConfig(
    miaTurnsThreshold: node.requireInt32("miaTurnsThreshold", ctx)
  )

proc parseAutopilotBehavior(node: KdlNode, ctx: var KdlConfigContext): AutopilotBehaviorConfig =
  result = AutopilotBehaviorConfig(
    patrolHomeSystems: node.requireBool("patrolHomeSystems", ctx),
    maintainEconomy: node.requireBool("maintainEconomy", ctx),
    defensiveConstruction: node.requireBool("defensiveConstruction", ctx),
    noOffensiveOps: node.requireBool("noOffensiveOps", ctx),
    maintainDiplomacy: node.requireBool("maintainDiplomacy", ctx)
  )

proc parseDefensiveCollapseBehavior(node: KdlNode, ctx: var KdlConfigContext): DefensiveCollapseBehaviorConfig =
  result = DefensiveCollapseBehaviorConfig(
    retreatToHome: node.requireBool("retreatToHome", ctx),
    defendOnly: node.requireBool("defendOnly", ctx),
    noConstruction: node.requireBool("noConstruction", ctx),
    noDiplomacyChanges: node.requireBool("noDiplomacyChanges", ctx),
    economyCeases: node.requireBool("economyCeases", ctx),
    permanentElimination: node.requireBool("permanentElimination", ctx)
  )

proc parseColonization(node: KdlNode, ctx: var KdlConfigContext): ColonizationConfig =
  result = ColonizationConfig(
    strengthWeight: node.requireInt32("strengthWeight", ctx)
  )

proc loadGameplayConfig*(configPath: string): GameplayConfig =
  ## Load gameplay configuration from KDL file
  ## Uses kdl_config_helpers for type-safe parsing
  let doc = loadKdlConfig(configPath)
  var ctx = newContext(configPath)

  ctx.withNode("elimination"):
    let elimNode = doc.requireNode("elimination", ctx)
    result.elimination = parseElimination(elimNode, ctx)

  ctx.withNode("autopilot"):
    let autopilotNode = doc.requireNode("autopilot", ctx)
    result.autopilot = parseAutopilot(autopilotNode, ctx)

  ctx.withNode("autopilotBehavior"):
    let autoBehavNode = doc.requireNode("autopilotBehavior", ctx)
    result.autopilotBehavior = parseAutopilotBehavior(autoBehavNode, ctx)

  ctx.withNode("defensiveCollapseBehavior"):
    let defCollapseNode = doc.requireNode("defensiveCollapseBehavior", ctx)
    result.defensiveCollapseBehavior = parseDefensiveCollapseBehavior(defCollapseNode, ctx)

  ctx.withNode("colonization"):
    let colonizationNode = doc.requireNode("colonization", ctx)
    result.colonization = parseColonization(colonizationNode, ctx)

  logInfo("Config", "Loaded gameplay configuration", "path=", configPath)
