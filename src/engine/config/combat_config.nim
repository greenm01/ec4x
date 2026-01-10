## Combat Configuration Loader
##
## Loads combat mechanics from config/combat.kdl using nimkdl
## Allows runtime configuration for combat rules, CER tables, and special mechanics

import kdl
import kdl_helpers
import ../../common/logger
import ../types/config
import ../types/combat

proc parseCombatMechanics(node: KdlNode, ctx: var KdlConfigContext): CombatMechanicsConfig =
  result = CombatMechanicsConfig(
    criticalHitRoll: node.requireInt32("criticalHitRoll", ctx),
    retreatAfterRound: node.requireInt32("retreatAfterRound", ctx),
    maxCombatRounds: node.requireInt32("maxCombatRounds", ctx),
    desperationRoundTrigger: node.requireInt32("desperationRoundTrigger", ctx)
  )

proc parseCerTable(node: KdlNode, ctx: var KdlConfigContext): CerTableConfig =
  ## Parse CER table with tier structure: tier 1 { maxRoll=2 multiplier=0.25 }
  var tier1, tier2, tier3, tier4: tuple[maxRoll: int32, mult: float32]

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
        tier4 = (child.requireInt32("minRoll", ctx), child.requireFloat32("multiplier", ctx))
      else: discard

  result = CerTableConfig(
    veryPoorMax: tier1.maxRoll,
    veryPoorMultiplier: tier1.mult,
    poorMax: tier2.maxRoll,
    poorMultiplier: tier2.mult,
    averageMax: tier3.maxRoll,
    averageMultiplier: tier3.mult,
    goodMin: tier4.maxRoll,
    goodMultiplier: tier4.mult
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
    crippledTargetingWeight: node.requireFloat32("crippledTargetingWeight", ctx),
    squadronFightsAsUnit: true,  # Default
    destroyAfterAllCrippled: true  # Default
  )

proc parseRetreatRules(node: KdlNode, ctx: var KdlConfigContext): RetreatRulesConfig =
  # Find moraleRoeModifiers child node
  var moraleModifiers: MoraleRoeModifiersConfig
  
  for child in node.children:
    if child.name == "moraleRoeModifiers":
      ctx.withNode("moraleRoeModifiers"):
        # Parse each tier from children
        for tier in child.children:
          case tier.name
          of "crisis":
            moraleModifiers.crisis = MoraleTierThreshold(
              maxPercent: tier.requireInt32("maxPercent", ctx),
              roeModifier: tier.requireInt32("roeModifier", ctx)
            )
          of "veryLow":
            moraleModifiers.veryLow = MoraleTierThreshold(
              maxPercent: tier.requireInt32("maxPercent", ctx),
              roeModifier: tier.requireInt32("roeModifier", ctx)
            )
          of "low":
            moraleModifiers.low = MoraleTierThreshold(
              maxPercent: tier.requireInt32("maxPercent", ctx),
              roeModifier: tier.requireInt32("roeModifier", ctx)
            )
          of "average":
            moraleModifiers.average = MoraleTierThreshold(
              maxPercent: tier.requireInt32("maxPercent", ctx),
              roeModifier: tier.requireInt32("roeModifier", ctx)
            )
          of "good":
            moraleModifiers.good = MoraleTierThreshold(
              maxPercent: tier.requireInt32("maxPercent", ctx),
              roeModifier: tier.requireInt32("roeModifier", ctx)
            )
          of "high":
            moraleModifiers.high = MoraleTierThreshold(
              maxPercent: tier.requireInt32("maxPercent", ctx),
              roeModifier: tier.requireInt32("roeModifier", ctx)
            )
          of "veryHigh":
            moraleModifiers.veryHigh = MoraleTierThreshold(
              maxPercent: 100'i32,  # No maxPercent for highest tier
              roeModifier: tier.requireInt32("roeModifier", ctx)
            )
          else: discard
  
  result = RetreatRulesConfig(
    fightersNeverRetreat: node.requireBool("fightersNeverRetreat", ctx),
    spaceliftDestroyedIfEscortLost: node.requireBool("spaceliftDestroyedIfEscortLost", ctx),
    retreatToNearestFriendly: node.requireBool("retreatToNearestFriendly", ctx),
    moraleRoeModifiers: moraleModifiers
  )

proc parseBlockade(node: KdlNode, ctx: var KdlConfigContext): BlockadeConfig =
  result = BlockadeConfig(
    blockadePrestigePenalty: node.requireInt32("prestigePenaltyPerTurn", ctx),
    blockadeProductionPenalty: 0.0  # Loaded from economy.kdl productionModifiers
  )

proc parseStarbase(node: KdlNode, ctx: var KdlConfigContext): StarbaseConfig =
  result = StarbaseConfig(
    starbaseDetectionBonus: node.requireInt32("detectionBonus", ctx),
    starbaseCriticalReroll: node.requireBool("criticalReroll", ctx),
    starbaseDieModifier: node.requireInt32("dieModifier", ctx)
  )

proc parseInvasion(node: KdlNode, ctx: var KdlConfigContext): InvasionConfig =
  result = InvasionConfig(
    invasionIuLoss: node.requireFloat32("iuLossOnConquest", ctx),
    blitzIuLoss: node.requireFloat32("iuLossOnBlitz", ctx),
    blitzMarinePenalty: node.requireFloat32("blitzMarinePenalty", ctx)
  )

proc parseTargeting(node: KdlNode, ctx: var KdlConfigContext): TargetingConfig =
  result = TargetingConfig(
    raiderWeight: node.requireFloat32("raiderWeight", ctx),
    capitalWeight: node.requireFloat32("capitalWeight", ctx),
    escortWeight: node.requireFloat32("escortWeight", ctx),
    fighterWeight: node.requireFloat32("fighterWeight", ctx),
    starbaseWeight: node.requireFloat32("starbaseWeight", ctx)
  )

proc parseMoraleEffectTarget(value: string): MoraleEffectTarget =
  ## Convert string to MoraleEffectTarget enum
  case value
  of "none": MoraleEffectTarget.None
  of "random": MoraleEffectTarget.Random
  of "all": MoraleEffectTarget.All
  else: MoraleEffectTarget.None

proc parseMoraleTier(node: KdlNode, ctx: var KdlConfigContext): MoraleTierConfig =
  ## Parse a single morale tier configuration
  let appliesTo = node.requireString("appliesTo", ctx)

  # Handle both cerBonus and cerPenalty
  # Config uses cerPenalty with negative value (e.g., cerPenalty -1)
  var cerBonus: int32
  if node.hasChild("cerBonus"):
    cerBonus = node.requireInt32("cerBonus", ctx)
  elif node.hasChild("cerPenalty"):
    cerBonus = node.requireInt32("cerPenalty", ctx)  # Already negative in config
  else:
    cerBonus = 0

  result = MoraleTierConfig(
    threshold: node.requireInt32("threshold", ctx),
    cerBonus: cerBonus,
    appliesTo: parseMoraleEffectTarget(appliesTo),
    criticalAutoSuccess: node.getBool("criticalAutoSuccess", false)
  )

proc parseMoraleChecks(node: KdlNode, ctx: var KdlConfigContext): MoraleChecksConfig =
  ## Parse moraleChecks { } with tier structure
  for child in node.children:
    let tier = case child.name
      of "collapsing": MoraleTier.Collapsing
      of "veryLow": MoraleTier.VeryLow
      of "low": MoraleTier.Low
      of "normal": MoraleTier.Normal
      of "high": MoraleTier.High
      of "veryHigh": MoraleTier.VeryHigh
      else: continue

    ctx.withNode(child.name):
      result[tier] = parseMoraleTier(child, ctx)

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

  # Parse starbase { }
  ctx.withNode("starbase"):
    result.starbase = parseStarbase(doc.requireNode("starbase", ctx), ctx)

  # Parse invasion { }
  ctx.withNode("invasion"):
    result.invasion = parseInvasion(doc.requireNode("invasion", ctx), ctx)

  # Parse targeting { }
  ctx.withNode("targeting"):
    result.targeting = parseTargeting(doc.requireNode("targeting", ctx), ctx)

  # Parse moraleChecks { }
  ctx.withNode("moraleChecks"):
    result.moraleChecks = parseMoraleChecks(doc.requireNode("moraleChecks", ctx), ctx)

  logInfo("Config", "Loaded combat configuration", "path=", configPath)
