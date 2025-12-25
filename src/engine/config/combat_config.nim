## Combat Configuration Loader
##
## Loads combat mechanics from config/combat.kdl using nimkdl
## Allows runtime configuration for combat rules, CER tables, and special mechanics

import kdl
import kdl_config_helpers
import ../../common/logger

type
  CombatMechanicsConfig* = object
    criticalHitRoll*: int
    retreatAfterRound*: int
    starbaseCriticalReroll*: bool
    starbaseDieModifier*: int

  CerModifiersConfig* = object
    scouts*: int
    surprise*: int
    ambush*: int

  CerTableConfig* = object
    veryPoorMax*: int
    poorMax*: int
    averageMax*: int
    goodMin*: int

  BombardmentConfig* = object
    maxRoundsPerTurn*: int
    veryPoorMax*: int
    poorMax*: int
    goodMin*: int

  GroundCombatConfig* = object
    poorMax*: int
    averageMax*: int
    goodMax*: int
    critical*: int

  PlanetaryShieldsConfig* = object
    sld1Chance*: int
    sld1Roll*: int
    sld1Block*: int
    sld2Chance*: int
    sld2Roll*: int
    sld2Block*: int
    sld3Chance*: int
    sld3Roll*: int
    sld3Block*: int
    sld4Chance*: int
    sld4Roll*: int
    sld4Block*: int
    sld5Chance*: int
    sld5Roll*: int
    sld5Block*: int
    sld6Chance*: int
    sld6Roll*: int
    sld6Block*: int

  DamageRulesConfig* = object
    crippledAsMultiplier*: float
    crippledMaintenanceMultiplier*: float
    squadronFightsAsUnit*: bool
    destroyAfterAllCrippled*: bool

  RetreatRulesConfig* = object
    fightersNeverRetreat*: bool
    spaceliftDestroyedIfEscortLost*: bool
    retreatToNearestFriendly*: bool

  BlockadeConfig* = object
    blockadeProductionPenalty*: float
    blockadePrestigePenalty*: int

  InvasionConfig* = object
    invasionIuLoss*: float
    blitzIuLoss*: float

  CombatConfig* = object ## Complete combat configuration loaded from KDL
    combat*: CombatMechanicsConfig
    cerModifiers*: CerModifiersConfig
    cerTable*: CerTableConfig
    bombardment*: BombardmentConfig
    groundCombat*: GroundCombatConfig
    planetaryShields*: PlanetaryShieldsConfig
    damageRules*: DamageRulesConfig
    retreatRules*: RetreatRulesConfig
    blockade*: BlockadeConfig
    invasion*: InvasionConfig

proc parseCombatMechanics(node: KdlNode, ctx: var KdlConfigContext): CombatMechanicsConfig =
  result = CombatMechanicsConfig(
    criticalHitRoll: node.requireInt("criticalHitRoll", ctx),
    retreatAfterRound: node.requireInt("retreatAfterRound", ctx),
    starbaseCriticalReroll: node.requireBool("starbaseCriticalReroll", ctx),
    starbaseDieModifier: node.requireInt("starbaseDieModifier", ctx)
  )

proc parseCerModifiers(node: KdlNode, ctx: var KdlConfigContext): CerModifiersConfig =
  result = CerModifiersConfig(
    scouts: node.requireInt("scouts", ctx),
    surprise: node.requireInt("surprise", ctx),
    ambush: node.requireInt("ambush", ctx)
  )

proc parseCerTable(node: KdlNode, ctx: var KdlConfigContext): CerTableConfig =
  result = CerTableConfig(
    veryPoorMax: node.requireInt("veryPoorMax", ctx),
    poorMax: node.requireInt("poorMax", ctx),
    averageMax: node.requireInt("averageMax", ctx),
    goodMin: node.requireInt("goodMin", ctx)
  )

proc parseBombardment(node: KdlNode, ctx: var KdlConfigContext): BombardmentConfig =
  result = BombardmentConfig(
    maxRoundsPerTurn: node.requireInt("maxRoundsPerTurn", ctx),
    veryPoorMax: node.requireInt("veryPoorMax", ctx),
    poorMax: node.requireInt("poorMax", ctx),
    goodMin: node.requireInt("goodMin", ctx)
  )

proc parseGroundCombat(node: KdlNode, ctx: var KdlConfigContext): GroundCombatConfig =
  result = GroundCombatConfig(
    poorMax: node.requireInt("poorMax", ctx),
    averageMax: node.requireInt("averageMax", ctx),
    goodMax: node.requireInt("goodMax", ctx),
    critical: node.requireInt("critical", ctx)
  )

proc parsePlanetaryShields(node: KdlNode, ctx: var KdlConfigContext): PlanetaryShieldsConfig =
  result = PlanetaryShieldsConfig(
    sld1Chance: node.requireInt("sld1Chance", ctx),
    sld1Roll: node.requireInt("sld1Roll", ctx),
    sld1Block: node.requireInt("sld1Block", ctx),
    sld2Chance: node.requireInt("sld2Chance", ctx),
    sld2Roll: node.requireInt("sld2Roll", ctx),
    sld2Block: node.requireInt("sld2Block", ctx),
    sld3Chance: node.requireInt("sld3Chance", ctx),
    sld3Roll: node.requireInt("sld3Roll", ctx),
    sld3Block: node.requireInt("sld3Block", ctx),
    sld4Chance: node.requireInt("sld4Chance", ctx),
    sld4Roll: node.requireInt("sld4Roll", ctx),
    sld4Block: node.requireInt("sld4Block", ctx),
    sld5Chance: node.requireInt("sld5Chance", ctx),
    sld5Roll: node.requireInt("sld5Roll", ctx),
    sld5Block: node.requireInt("sld5Block", ctx),
    sld6Chance: node.requireInt("sld6Chance", ctx),
    sld6Roll: node.requireInt("sld6Roll", ctx),
    sld6Block: node.requireInt("sld6Block", ctx)
  )

proc parseDamageRules(node: KdlNode, ctx: var KdlConfigContext): DamageRulesConfig =
  result = DamageRulesConfig(
    crippledAsMultiplier: node.requireFloat("crippledAsMultiplier", ctx),
    crippledMaintenanceMultiplier: node.requireFloat("crippledMaintenanceMultiplier", ctx),
    squadronFightsAsUnit: node.requireBool("squadronFightsAsUnit", ctx),
    destroyAfterAllCrippled: node.requireBool("destroyAfterAllCrippled", ctx)
  )

proc parseRetreatRules(node: KdlNode, ctx: var KdlConfigContext): RetreatRulesConfig =
  result = RetreatRulesConfig(
    fightersNeverRetreat: node.requireBool("fightersNeverRetreat", ctx),
    spaceliftDestroyedIfEscortLost: node.requireBool("spaceliftDestroyedIfEscortLost", ctx),
    retreatToNearestFriendly: node.requireBool("retreatToNearestFriendly", ctx)
  )

proc parseBlockade(node: KdlNode, ctx: var KdlConfigContext): BlockadeConfig =
  result = BlockadeConfig(
    blockadeProductionPenalty: node.requireFloat("blockadeProductionPenalty", ctx),
    blockadePrestigePenalty: node.requireInt("blockadePrestigePenalty", ctx)
  )

proc parseInvasion(node: KdlNode, ctx: var KdlConfigContext): InvasionConfig =
  result = InvasionConfig(
    invasionIuLoss: node.requireFloat("invasionIuLoss", ctx),
    blitzIuLoss: node.requireFloat("blitzIuLoss", ctx)
  )

proc loadCombatConfig*(configPath: string = "config/combat.kdl"): CombatConfig =
  ## Load combat configuration from KDL file
  ## Uses kdl_config_helpers for type-safe parsing
  let doc = loadKdlConfig(configPath)
  var ctx = newContext(configPath)

  # Parse each section
  ctx.withNode("combat"):
    let combatNode = doc.requireNode("combat", ctx)
    result.combat = parseCombatMechanics(combatNode, ctx)

  ctx.withNode("cerModifiers"):
    let cerModNode = doc.requireNode("cerModifiers", ctx)
    result.cerModifiers = parseCerModifiers(cerModNode, ctx)

  ctx.withNode("cerTable"):
    let cerTableNode = doc.requireNode("cerTable", ctx)
    result.cerTable = parseCerTable(cerTableNode, ctx)

  ctx.withNode("bombardment"):
    let bombNode = doc.requireNode("bombardment", ctx)
    result.bombardment = parseBombardment(bombNode, ctx)

  ctx.withNode("groundCombat"):
    let groundNode = doc.requireNode("groundCombat", ctx)
    result.groundCombat = parseGroundCombat(groundNode, ctx)

  ctx.withNode("planetaryShields"):
    let shieldsNode = doc.requireNode("planetaryShields", ctx)
    result.planetaryShields = parsePlanetaryShields(shieldsNode, ctx)

  ctx.withNode("damageRules"):
    let damageNode = doc.requireNode("damageRules", ctx)
    result.damageRules = parseDamageRules(damageNode, ctx)

  ctx.withNode("retreatRules"):
    let retreatNode = doc.requireNode("retreatRules", ctx)
    result.retreatRules = parseRetreatRules(retreatNode, ctx)

  ctx.withNode("blockade"):
    let blockadeNode = doc.requireNode("blockade", ctx)
    result.blockade = parseBlockade(blockadeNode, ctx)

  ctx.withNode("invasion"):
    let invasionNode = doc.requireNode("invasion", ctx)
    result.invasion = parseInvasion(invasionNode, ctx)

  logInfo("Config", "Loaded combat configuration", "path=", configPath)

## Global configuration instance

var globalCombatConfig* = loadCombatConfig()

## Helper to reload configuration (for testing)

proc reloadCombatConfig*() =
  ## Reload configuration from file
  globalCombatConfig = loadCombatConfig()
