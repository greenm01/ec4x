## Gameplay Configuration Loader
##
## Loads gameplay mechanics from config/gameplay.kdl using nimkdl
## Allows runtime configuration for core game rules
## NOTE: Starting tech levels are in config/tech.kdl (see tech_config module)

import kdl
import kdl_config_helpers
import ../../common/logger

type
  ThemeConfig* = object
    activeTheme*: string

  EliminationConfig* = object
    defensiveCollapseTurns*: int
    defensiveCollapseThreshold*: int

  AutopilotConfig* = object
    miaTurnsThreshold*: int

  AutopilotBehaviorConfig* = object
    continueStandingOrders*: bool
    patrolHomeSystems*: bool
    maintainEconomy*: bool
    defensiveConstruction*: bool
    noOffensiveOps*: bool
    maintainDiplomacy*: bool

  DefensiveCollapseBehaviorConfig* = object
    retreatToHome*: bool
    defendOnly*: bool
    noConstruction*: bool
    noDiplomacyChanges*: bool
    economyCeases*: bool
    permanentElimination*: bool

  VictoryConfig* = object
    prestigeVictoryEnabled*: bool
    lastPlayerVictoryEnabled*: bool
    autopilotCanWin*: bool
    finalConflictAutoEnemy*: bool

  GameplayConfig* = object ## Complete gameplay configuration loaded from KDL
    theme*: ThemeConfig
    elimination*: EliminationConfig
    autopilot*: AutopilotConfig
    autopilotBehavior*: AutopilotBehaviorConfig
    defensiveCollapseBehavior*: DefensiveCollapseBehaviorConfig
    victory*: VictoryConfig

proc parseTheme(node: KdlNode, ctx: var KdlConfigContext): ThemeConfig =
  result = ThemeConfig(
    activeTheme: node.requireString("activeTheme", ctx)
  )

proc parseElimination(node: KdlNode, ctx: var KdlConfigContext): EliminationConfig =
  result = EliminationConfig(
    defensiveCollapseTurns: node.requireInt("defensiveCollapseTurns", ctx),
    defensiveCollapseThreshold: node.requireInt("defensiveCollapseThreshold", ctx)
  )

proc parseAutopilot(node: KdlNode, ctx: var KdlConfigContext): AutopilotConfig =
  result = AutopilotConfig(
    miaTurnsThreshold: node.requireInt("miaTurnsThreshold", ctx)
  )

proc parseAutopilotBehavior(node: KdlNode, ctx: var KdlConfigContext): AutopilotBehaviorConfig =
  result = AutopilotBehaviorConfig(
    continueStandingOrders: node.requireBool("continueStandingOrders", ctx),
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

proc parseVictory(node: KdlNode, ctx: var KdlConfigContext): VictoryConfig =
  result = VictoryConfig(
    prestigeVictoryEnabled: node.requireBool("prestigeVictoryEnabled", ctx),
    lastPlayerVictoryEnabled: node.requireBool("lastPlayerVictoryEnabled", ctx),
    autopilotCanWin: node.requireBool("autopilotCanWin", ctx),
    finalConflictAutoEnemy: node.requireBool("finalConflictAutoEnemy", ctx)
  )

proc loadGameplayConfig*(configPath: string = "config/gameplay.kdl"): GameplayConfig =
  ## Load gameplay configuration from KDL file
  ## Uses kdl_config_helpers for type-safe parsing
  let doc = loadKdlConfig(configPath)
  var ctx = newContext(configPath)

  ctx.withNode("theme"):
    let themeNode = doc.requireNode("theme", ctx)
    result.theme = parseTheme(themeNode, ctx)

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

  ctx.withNode("victory"):
    let victoryNode = doc.requireNode("victory", ctx)
    result.victory = parseVictory(victoryNode, ctx)

  logInfo("Config", "Loaded gameplay configuration", "path=", configPath)

## Global configuration instance

var globalGameplayConfig* = loadGameplayConfig()

## Helper to reload configuration (for testing)

proc reloadGameplayConfig*() =
  ## Reload configuration from file
  globalGameplayConfig = loadGameplayConfig()
