## Combat Configuration Loader
##
## Loads combat mechanics from config/combat.kdl using nimkdl
## Allows runtime configuration for combat rules, CER tables, and special mechanics

import kdl
import kdl_helpers
import ../../common/logger
import ../types/config 

proc parseCombatMechanics(node: KdlNode, ctx: var KdlConfigContext): CombatMechanicsConfig =
  result = CombatMechanicsConfig(
    criticalHitRoll: node.requireInt32("criticalHitRoll", ctx),
    retreatAfterRound: node.requireInt32("retreatAfterRound", ctx),
    starbaseCriticalReroll: node.requireBool("starbaseCriticalReroll", ctx),
    starbaseDieModifier: node.requireInt32("starbaseDieModifier", ctx)
  )

proc parseCerModifiers(node: KdlNode, ctx: var KdlConfigContext): CerModifiersConfig =
  result = CerModifiersConfig(
    scouts: node.requireInt32("scouts", ctx),
    surprise: node.requireInt32("surprise", ctx),
    ambush: node.requireInt32("ambush", ctx)
  )

proc parseCerTable(node: KdlNode, ctx: var KdlConfigContext): CerTableConfig =
  result = CerTableConfig(
    veryPoorMax: node.requireInt32("veryPoorMax", ctx),
    poorMax: node.requireInt32("poorMax", ctx),
    averageMax: node.requireInt32("averageMax", ctx),
    goodMin: node.requireInt32("goodMin", ctx)
  )

proc parseBombardment(node: KdlNode, ctx: var KdlConfigContext): BombardmentConfig =
  result = BombardmentConfig(
    maxRoundsPerTurn: node.requireInt32("maxRoundsPerTurn", ctx),
    veryPoorMax: node.requireInt32("veryPoorMax", ctx),
    poorMax: node.requireInt32("poorMax", ctx),
    goodMin: node.requireInt32("goodMin", ctx)
  )

proc parseGroundCombat(node: KdlNode, ctx: var KdlConfigContext): GroundCombatConfig =
  result = GroundCombatConfig(
    poorMax: node.requireInt32("poorMax", ctx),
    averageMax: node.requireInt32("averageMax", ctx),
    goodMax: node.requireInt32("goodMax", ctx),
    critical: node.requireInt32("critical", ctx)
  )

proc parsePlanetaryShields(node: KdlNode, ctx: var KdlConfigContext): PlanetaryShieldsConfig =
  result = PlanetaryShieldsConfig(
    sld1Chance: node.requireInt32("sld1Chance", ctx),
    sld1Roll: node.requireInt32("sld1Roll", ctx),
    sld1Block: node.requireInt32("sld1Block", ctx),
    sld2Chance: node.requireInt32("sld2Chance", ctx),
    sld2Roll: node.requireInt32("sld2Roll", ctx),
    sld2Block: node.requireInt32("sld2Block", ctx),
    sld3Chance: node.requireInt32("sld3Chance", ctx),
    sld3Roll: node.requireInt32("sld3Roll", ctx),
    sld3Block: node.requireInt32("sld3Block", ctx),
    sld4Chance: node.requireInt32("sld4Chance", ctx),
    sld4Roll: node.requireInt32("sld4Roll", ctx),
    sld4Block: node.requireInt32("sld4Block", ctx),
    sld5Chance: node.requireInt32("sld5Chance", ctx),
    sld5Roll: node.requireInt32("sld5Roll", ctx),
    sld5Block: node.requireInt32("sld5Block", ctx),
    sld6Chance: node.requireInt32("sld6Chance", ctx),
    sld6Roll: node.requireInt32("sld6Roll", ctx),
    sld6Block: node.requireInt32("sld6Block", ctx)
  )

proc parseDamageRules(node: KdlNode, ctx: var KdlConfigContext): DamageRulesConfig =
  result = DamageRulesConfig(
    crippledAsMultiplier: node.requireFloat32("crippledAsMultiplier", ctx),
    crippledMaintenanceMultiplier: node.requireFloat32("crippledMaintenanceMultiplier", ctx),
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
    blockadeProductionPenalty: node.requireFloat32("blockadeProductionPenalty", ctx),
    blockadePrestigePenalty: node.requireInt32("blockadePrestigePenalty", ctx)
  )

proc parseInvasion(node: KdlNode, ctx: var KdlConfigContext): InvasionConfig =
  result = InvasionConfig(
    invasionIuLoss: node.requireFloat32("invasionIuLoss", ctx),
    blitzIuLoss: node.requireFloat32("blitzIuLoss", ctx)
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
