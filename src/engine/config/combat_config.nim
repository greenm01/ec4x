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
    starbaseCriticalReroll: false,  # Removed from new config
    starbaseDieModifier: 0'i32  # Removed from new config
  )

proc parseCerTable(node: KdlNode, ctx: var KdlConfigContext): CerTableConfig =
  ## Parse CER table with tier structure: tier 1 { maxRoll=2 multiplier=0.25 }
  var tier1, tier2, tier3: tuple[maxRoll: int32, mult: float32]
  var tier4Min: int32

  for child in node.children:
    if child.name == "tier" and child.args.len > 0:
      let tierNum = child.args[0].getInt()
      case tierNum
      of 1:
        tier1 = (child.requireInt32("maxRoll", ctx), child.requireFloat32("multiplier", ctx))
      of 2:
        tier2 = (child.requireInt32("maxRoll", ctx), child.requireFloat32("multiplier", ctx))
      of 3:
        tier3 = (child.requireInt32("maxRoll", ctx), child.requireFloat32("multiplier", ctx))
      of 4:
        tier4Min = child.requireInt32("minRoll", ctx)
      else: discard

  result = CerTableConfig(
    veryPoorMax: tier1.maxRoll,
    poorMax: tier2.maxRoll,
    averageMax: tier3.maxRoll,
    goodMin: tier4Min
  )

proc parseBombardment(node: KdlNode, ctx: var KdlConfigContext): BombardmentConfig =
  ## Parse bombardmentTable with tier structure
  var tier1, tier2, tier3: tuple[maxRoll: int32, mult: float32]

  for child in node.children:
    if child.name == "tier" and child.args.len > 0:
      let tierNum = child.args[0].getInt()
      case tierNum
      of 1:
        tier1 = (child.requireInt32("maxRoll", ctx), child.requireFloat32("multiplier", ctx))
      of 2:
        tier2 = (child.requireInt32("maxRoll", ctx), child.requireFloat32("multiplier", ctx))
      of 3:
        tier3 = (child.requireInt32("maxRoll", ctx), child.requireFloat32("multiplier", ctx))
      else: discard

  result = BombardmentConfig(
    maxRoundsPerTurn: 1,  # Default
    veryPoorMax: tier1.maxRoll,
    poorMax: tier2.maxRoll,
    goodMin: tier3.maxRoll
  )

proc parseGroundCombat(node: KdlNode, ctx: var KdlConfigContext): GroundCombatConfig =
  ## Parse groundCombatTable with tier structure
  var tier1, tier2, tier3: tuple[maxRoll: int32, mult: float32]
  var critRoll: int32

  for child in node.children:
    if child.name == "tier" and child.args.len > 0:
      let tierNum = child.args[0].getInt()
      case tierNum
      of 1:
        tier1 = (child.requireInt32("maxRoll", ctx), child.requireFloat32("multiplier", ctx))
      of 2:
        tier2 = (child.requireInt32("maxRoll", ctx), child.requireFloat32("multiplier", ctx))
      of 3:
        tier3 = (child.requireInt32("maxRoll", ctx), child.requireFloat32("multiplier", ctx))
      of 4:
        critRoll = child.requireInt32("roll", ctx)
      else: discard

  result = GroundCombatConfig(
    poorMax: tier1.maxRoll,
    averageMax: tier2.maxRoll,
    goodMax: tier3.maxRoll,
    critical: critRoll
  )

proc parseDamageRules(node: KdlNode, ctx: var KdlConfigContext): DamageRulesConfig =
  result = DamageRulesConfig(
    crippledAsMultiplier: node.requireFloat32("crippledAsMultiplier", ctx),
    crippledMaintenanceMultiplier: node.requireFloat32("crippledMaintenanceMultiplier", ctx),
    squadronFightsAsUnit: true,  # Default
    destroyAfterAllCrippled: true  # Default
  )

proc parseRetreatRules(node: KdlNode, ctx: var KdlConfigContext): RetreatRulesConfig =
  result = RetreatRulesConfig(
    fightersNeverRetreat: node.requireBool("fightersNeverRetreat", ctx),
    spaceliftDestroyedIfEscortLost: node.requireBool("spaceliftDestroyedIfEscortLost", ctx),
    retreatToNearestFriendly: node.requireBool("retreatToNearestFriendly", ctx)
  )

proc parseBlockade(node: KdlNode, ctx: var KdlConfigContext): BlockadeConfig =
  result = BlockadeConfig(
    blockadeProductionPenalty: 0.0,  # Moved to economy.kdl
    blockadePrestigePenalty: node.requireInt32("prestigePenaltyPerTurn", ctx)
  )

proc parseInvasion(node: KdlNode, ctx: var KdlConfigContext): InvasionConfig =
  result = InvasionConfig(
    invasionIuLoss: node.requireFloat32("iuLossOnConquest", ctx),
    blitzIuLoss: node.requireFloat32("iuLossOnBlitz", ctx)
  )

proc loadCombatConfig*(configPath: string): CombatConfig =
  ## Load combat configuration from KDL file
  ## Uses kdl_config_helpers for type-safe parsing
  let doc = loadKdlConfig(configPath)
  var ctx = newContext(configPath)

  # Parse combat { }
  ctx.withNode("combat"):
    result.combat = parseCombatMechanics(doc.requireNode("combat", ctx), ctx)

  # Parse cer { modifiers { } spaceCombatTable { } bombardmentTable { } groundCombatTable { } }
  ctx.withNode("cer"):
    let cerNode = doc.requireNode("cer", ctx)
    for child in cerNode.children:
      case child.name
      of "modifiers":
        ctx.withNode("modifiers"):
          result.cerModifiers = CerModifiersConfig(
            scouts: 0,  # Removed
            surprise: 0,  # Removed
            ambush: child.requireInt32("ambushBonus", ctx)
          )
      of "spaceCombatTable":
        ctx.withNode("spaceCombatTable"):
          result.cerTable = parseCerTable(child, ctx)
      of "bombardmentTable":
        ctx.withNode("bombardmentTable"):
          result.bombardment = parseBombardment(child, ctx)
      of "groundCombatTable":
        ctx.withNode("groundCombatTable"):
          result.groundCombat = parseGroundCombat(child, ctx)
      else: discard

  # Parse damage { }
  ctx.withNode("damage"):
    result.damageRules = parseDamageRules(doc.requireNode("damage", ctx), ctx)

  # Parse retreat { }
  ctx.withNode("retreat"):
    result.retreatRules = parseRetreatRules(doc.requireNode("retreat", ctx), ctx)

  # Parse blockade { }
  ctx.withNode("blockade"):
    result.blockade = parseBlockade(doc.requireNode("blockade", ctx), ctx)

  # Parse invasion { }
  ctx.withNode("invasion"):
    result.invasion = parseInvasion(doc.requireNode("invasion", ctx), ctx)

  # Planetary shields removed - now in tech.kdl
  result.planetaryShields = PlanetaryShieldsConfig()  # Empty default

  logInfo("Config", "Loaded combat configuration", "path=", configPath)
