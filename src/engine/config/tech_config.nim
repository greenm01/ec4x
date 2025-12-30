## Technology Configuration Loader
##
## Loads technology research costs and effects from config/tech.kdl
## Allows runtime configuration for all tech trees

import kdl
import kdl_helpers
import ../../common/logger
import ../types/config

proc parseEconomicLevel(node: KdlNode, ctx: var KdlConfigContext): EconomicLevelConfig =
  ## Parse economicLevel with hierarchical level nodes
  ## Structure: level 2 { slRequired 2; erpCost 10; multiplier 1.5 }
  result = EconomicLevelConfig()

  for child in node.children:
    if child.name == "level" and child.args.len > 0:
      let levelNum = child.args[0].getInt()
      let erpCost = child.requireInt32("erpCost", ctx)
      let multiplier = child.requireFloat32("multiplier", ctx)

      case levelNum
      of 2:
        result.level1Erp = erpCost
        result.level1Mod = multiplier
      of 3:
        result.level2Erp = erpCost
        result.level2Mod = multiplier
      of 4:
        result.level3Erp = erpCost
        result.level3Mod = multiplier
      of 5:
        result.level4Erp = erpCost
        result.level4Mod = multiplier
      of 6:
        result.level5Erp = erpCost
        result.level5Mod = multiplier
      of 7:
        result.level6Erp = erpCost
        result.level6Mod = multiplier
      of 8:
        result.level7Erp = erpCost
        result.level7Mod = multiplier
      of 9:
        result.level8Erp = erpCost
        result.level8Mod = multiplier
      of 10:
        result.level9Erp = erpCost
        result.level9Mod = multiplier
      of 11:
        result.level10Erp = erpCost
        result.level10Mod = multiplier
      of 12:
        result.level11Erp = erpCost
        result.level11Mod = multiplier
      else:
        discard

proc parseScienceLevel(node: KdlNode, ctx: var KdlConfigContext): ScienceLevelConfig =
  ## Parse scienceLevel with hierarchical level nodes
  ## Structure: level 2 { erpRequired 10; srpRequired 10 }
  result = ScienceLevelConfig()

  for child in node.children:
    if child.name == "level" and child.args.len > 0:
      let levelNum = child.args[0].getInt()
      let srpRequired = child.requireInt32("srpRequired", ctx)

      case levelNum
      of 2: result.level1Srp = srpRequired
      of 3: result.level2Srp = srpRequired
      of 4: result.level3Srp = srpRequired
      of 5: result.level4Srp = srpRequired
      of 6: result.level5Srp = srpRequired
      of 7: result.level6Srp = srpRequired
      of 8: result.level7Srp = srpRequired
      of 9: result.level8Srp = srpRequired
      else: discard

proc parseStandardTechLevel(
  node: KdlNode,
  ctx: var KdlConfigContext,
  hasCapacityMultiplier: bool = false
): StandardTechLevelConfig =
  ## Parse standard tech with hierarchical level nodes
  ## Structure: level 2 { slRequired 2; trpCost 10 } or { slRequired 2; srpCost 10 }
  result = StandardTechLevelConfig()

  # Parse base-level fields if present
  if hasCapacityMultiplier:
    # Try to get capacityMultiplierPerLevel if it exists
    try:
      result.capacityMultiplierPerLevel = node.requireFloat32("capacityMultiplierPerLevel", ctx)
    except ConfigError:
      result.capacityMultiplierPerLevel = 0.0

  # Parse level nodes
  for child in node.children:
    if child.name == "level" and child.args.len > 0:
      let levelNum = child.args[0].getInt()
      let slRequired = child.requireInt32("slRequired", ctx)
      # Try trpCost first, fall back to srpCost for science-based techs
      var trpCost: int32
      try:
        trpCost = child.requireInt32("trpCost", ctx)
      except ConfigError:
        trpCost = child.requireInt32("srpCost", ctx)

      case levelNum
      of 2:
        result.level1Sl = slRequired
        result.level1Trp = trpCost
      of 3:
        result.level2Sl = slRequired
        result.level2Trp = trpCost
      of 4:
        result.level3Sl = slRequired
        result.level3Trp = trpCost
      of 5:
        result.level4Sl = slRequired
        result.level4Trp = trpCost
      of 6:
        result.level5Sl = slRequired
        result.level5Trp = trpCost
      of 7:
        result.level6Sl = slRequired
        result.level6Trp = trpCost
      of 8:
        result.level7Sl = slRequired
        result.level7Trp = trpCost
      of 9:
        result.level8Sl = slRequired
        result.level8Trp = trpCost
      of 10:
        result.level9Sl = slRequired
        result.level9Trp = trpCost
      of 11:
        result.level10Sl = slRequired
        result.level10Trp = trpCost
      of 12:
        result.level11Sl = slRequired
        result.level11Trp = trpCost
      of 13:
        result.level12Sl = slRequired
        result.level12Trp = trpCost
      of 14:
        result.level13Sl = slRequired
        result.level13Trp = trpCost
      of 15:
        result.level14Sl = slRequired
        result.level14Trp = trpCost
      of 16:
        result.level15Sl = slRequired
        result.level15Trp = trpCost
      else: discard

proc parseWeaponsTech(node: KdlNode, ctx: var KdlConfigContext): WeaponsTechConfig =
  ## Parse weaponsTech with hierarchical level nodes
  ## Structure: baseMultiplier 1.10; level 2 { slRequired 2; trpCost 10 }
  result = WeaponsTechConfig()

  # Parse base-level fields
  result.weaponsStatIncreasePerLevel = node.requireFloat32("baseMultiplier", ctx)
  result.weaponsCostIncreasePerLevel = 0.0  # Not in current KDL

  # Parse level nodes
  for child in node.children:
    if child.name == "level" and child.args.len > 0:
      let levelNum = child.args[0].getInt()
      let slRequired = child.requireInt32("slRequired", ctx)
      let trpCost = child.requireInt32("trpCost", ctx)

      case levelNum
      of 2:
        result.level1Sl = slRequired
        result.level1Trp = trpCost
      of 3:
        result.level2Sl = slRequired
        result.level2Trp = trpCost
      of 4:
        result.level3Sl = slRequired
        result.level3Trp = trpCost
      of 5:
        result.level4Sl = slRequired
        result.level4Trp = trpCost
      of 6:
        result.level5Sl = slRequired
        result.level5Trp = trpCost
      of 7:
        result.level6Sl = slRequired
        result.level6Trp = trpCost
      of 8:
        result.level7Sl = slRequired
        result.level7Trp = trpCost
      of 9:
        result.level8Sl = slRequired
        result.level8Trp = trpCost
      of 10:
        result.level9Sl = slRequired
        result.level9Trp = trpCost
      of 11:
        result.level10Sl = slRequired
        result.level10Trp = trpCost
      of 12:
        result.level11Sl = slRequired
        result.level11Trp = trpCost
      of 13:
        result.level12Sl = slRequired
        result.level12Trp = trpCost
      of 14:
        result.level13Sl = slRequired
        result.level13Trp = trpCost
      of 15:
        result.level14Sl = slRequired
        result.level14Trp = trpCost
      of 16:
        result.level15Sl = slRequired
        result.level15Trp = trpCost
      else: discard

proc parseTerraformingTech(
  node: KdlNode,
  ctx: var KdlConfigContext
): TerraformingTechConfig =
  ## Parse terraformingTech with hierarchical level nodes
  ## Structure: level 1 { slRequired 4; srpCost 16; upgrades "From" to "To" }
  result = TerraformingTechConfig()

  for child in node.children:
    if child.name == "level" and child.args.len > 0:
      let levelNum = child.args[0].getInt()
      let slRequired = child.requireInt32("slRequired", ctx)
      let srpCost = child.requireInt32("srpCost", ctx)

      # Get target planet class from "upgrades" child
      # Format: upgrades "Extreme" to "Desolate"
      var planetClass = ""
      for upgradeChild in child.children:
        if upgradeChild.name == "upgrades" and upgradeChild.args.len >= 3:
          # args[2] is the target class (after "to")
          planetClass = upgradeChild.args[2].getString()
          break

      case levelNum
      of 1:
        result.level1Sl = slRequired
        result.level1Trp = srpCost
        result.level1PlanetClass = planetClass
      of 2:
        result.level2Sl = slRequired
        result.level2Trp = srpCost
        result.level2PlanetClass = planetClass
      of 3:
        result.level3Sl = slRequired
        result.level3Trp = srpCost
        result.level3PlanetClass = planetClass
      of 4:
        result.level4Sl = slRequired
        result.level4Trp = srpCost
        result.level4PlanetClass = planetClass
      of 5:
        result.level5Sl = slRequired
        result.level5Trp = srpCost
        result.level5PlanetClass = planetClass
      of 6:
        result.level6Sl = slRequired
        result.level6Trp = srpCost
        result.level6PlanetClass = planetClass
      of 7:
        result.level7Sl = slRequired
        result.level7Trp = srpCost
        result.level7PlanetClass = planetClass
      else: discard

proc parseTerraformingUpgradeCosts(
  node: KdlNode,
  ctx: var KdlConfigContext
): TerraformingUpgradeCostsConfig =
  result = TerraformingUpgradeCostsConfig(
    extremeTer: node.requireInt32("extremeTer", ctx),
    extremePuMin: node.requireInt32("extremePuMin", ctx),
    extremePuMax: node.requireInt32("extremePuMax", ctx),
    extremePp: node.requireInt32("extremePp", ctx),
    desolateTer: node.requireInt32("desolateTer", ctx),
    desolatePuMin: node.requireInt32("desolatePuMin", ctx),
    desolatePuMax: node.requireInt32("desolatePuMax", ctx),
    desolatePp: node.requireInt32("desolatePp", ctx),
    hostileTer: node.requireInt32("hostileTer", ctx),
    hostilePuMin: node.requireInt32("hostilePuMin", ctx),
    hostilePuMax: node.requireInt32("hostilePuMax", ctx),
    hostilePp: node.requireInt32("hostilePp", ctx),
    harshTer: node.requireInt32("harshTer", ctx),
    harshPuMin: node.requireInt32("harshPuMin", ctx),
    harshPuMax: node.requireInt32("harshPuMax", ctx),
    harshPp: node.requireInt32("harshPp", ctx),
    benignTer: node.requireInt32("benignTer", ctx),
    benignPuMin: node.requireInt32("benignPuMin", ctx),
    benignPuMax: node.requireInt32("benignPuMax", ctx),
    benignPp: node.requireInt32("benignPp", ctx),
    lushTer: node.requireInt32("lushTer", ctx),
    lushPuMin: node.requireInt32("lushPuMin", ctx),
    lushPuMax: node.requireInt32("lushPuMax", ctx),
    lushPp: node.requireInt32("lushPp", ctx),
    edenTer: node.requireInt32("edenTer", ctx),
    edenPuMin: node.requireInt32("edenPuMin", ctx),
    edenPuMax: node.requireInt32("edenPuMax", ctx),
    edenPp: node.requireInt32("edenPp", ctx)
  )

proc parseFlagshipCommand(
  node: KdlNode,
  ctx: var KdlConfigContext
): FlagshipCommandConfig =
  ## Structure: level 2 { slRequired 2; trpCost 12; crBonus 1 }
  result = FlagshipCommandConfig()

  for child in node.children:
    if child.name == "level" and child.args.len > 0:
      let levelNum = child.args[0].getInt()
      let slRequired = child.requireInt32("slRequired", ctx)
      let trpCost = child.requireInt32("trpCost", ctx)
      let crBonus = child.requireInt32("crBonus", ctx)

      case levelNum
      of 2:
        result.level2Sl = slRequired
        result.level2Trp = trpCost
        result.level2CrBonus = crBonus
      of 3:
        result.level3Sl = slRequired
        result.level3Trp = trpCost
        result.level3CrBonus = crBonus
      of 4:
        result.level4Sl = slRequired
        result.level4Trp = trpCost
        result.level4CrBonus = crBonus
      of 5:
        result.level5Sl = slRequired
        result.level5Trp = trpCost
        result.level5CrBonus = crBonus
      of 6:
        result.level6Sl = slRequired
        result.level6Trp = trpCost
        result.level6CrBonus = crBonus
      else:
        discard

proc parseStrategicCommand(
  node: KdlNode,
  ctx: var KdlConfigContext
): StrategicCommandConfig =
  ## Structure: level 1 { slRequired 2; trpCost 15; c2Bonus 50 }
  result = StrategicCommandConfig()

  for child in node.children:
    if child.name == "level" and child.args.len > 0:
      let levelNum = child.args[0].getInt()
      let slRequired = child.requireInt32("slRequired", ctx)
      let trpCost = child.requireInt32("trpCost", ctx)
      let c2Bonus = child.requireInt32("c2Bonus", ctx)

      case levelNum
      of 1:
        result.level1Sl = slRequired
        result.level1Trp = trpCost
        result.level1C2Bonus = c2Bonus
      of 2:
        result.level2Sl = slRequired
        result.level2Trp = trpCost
        result.level2C2Bonus = c2Bonus
      of 3:
        result.level3Sl = slRequired
        result.level3Trp = trpCost
        result.level3C2Bonus = c2Bonus
      of 4:
        result.level4Sl = slRequired
        result.level4Trp = trpCost
        result.level4C2Bonus = c2Bonus
      of 5:
        result.level5Sl = slRequired
        result.level5Trp = trpCost
        result.level5C2Bonus = c2Bonus
      else:
        discard

proc parseFighterDoctrine(
  node: KdlNode,
  ctx: var KdlConfigContext
): FighterDoctrineConfig =
  ## Structure: level 2 { slRequired 2; trpCost 15; multiplier 1.5 }
  result = FighterDoctrineConfig()

  for child in node.children:
    if child.name == "level" and child.args.len > 0:
      let levelNum = child.args[0].getInt()
      let slRequired = child.requireInt32("slRequired", ctx)
      let trpCost = child.requireInt32("trpCost", ctx)
      let multiplier = child.requireFloat32("multiplier", ctx)

      # Optional description field
      var description = ""
      try:
        description = child.requireString("description", ctx)
      except ConfigError:
        description = ""

      case levelNum
      of 1:
        result.level1Sl = slRequired
        result.level1Trp = trpCost
        result.level1CapacityMultiplier = multiplier
        result.level1Description = description
      of 2:
        result.level2Sl = slRequired
        result.level2Trp = trpCost
        result.level2CapacityMultiplier = multiplier
        result.level2Description = description
      of 3:
        result.level3Sl = slRequired
        result.level3Trp = trpCost
        result.level3CapacityMultiplier = multiplier
        result.level3Description = description
      else:
        discard

proc parseAdvancedCarrierOps(
  node: KdlNode,
  ctx: var KdlConfigContext
): AdvancedCarrierOpsConfig =
  ## Structure: level 1 { slRequired 1; trpCost 0; cvCapacity 3; cxCapacity 5; description "..." }
  result = AdvancedCarrierOpsConfig(
    capacityMultiplierPerLevel:
      node.requireFloat32("capacityMultiplierPerLevel", ctx)
  )

  for child in node.children:
    if child.name == "level" and child.args.len > 0:
      let levelNum = child.args[0].getInt()
      let slRequired = child.requireInt32("slRequired", ctx)
      let trpCost = child.requireInt32("trpCost", ctx)
      let cvCapacity = child.requireInt32("cvCapacity", ctx)
      let cxCapacity = child.requireInt32("cxCapacity", ctx)

      # Optional description field
      var description = ""
      try:
        description = child.requireString("description", ctx)
      except ConfigError:
        description = ""

      case levelNum
      of 1:
        result.level1Sl = slRequired
        result.level1Trp = trpCost
        result.level1CvCapacity = cvCapacity
        result.level1CxCapacity = cxCapacity
        result.level1Description = description
      of 2:
        result.level2Sl = slRequired
        result.level2Trp = trpCost
        result.level2CvCapacity = cvCapacity
        result.level2CxCapacity = cxCapacity
        result.level2Description = description
      of 3:
        result.level3Sl = slRequired
        result.level3Trp = trpCost
        result.level3CvCapacity = cvCapacity
        result.level3CxCapacity = cxCapacity
        result.level3Description = description
      else:
        discard

proc loadTechConfig*(configPath: string): TechConfig =
  ## Load technology configuration from KDL file
  ## Uses kdl_config_helpers for type-safe parsing
  let doc = loadKdlConfig(configPath)
  var ctx = newContext(configPath)

  ctx.withNode("economicLevel"):
    let node = doc.requireNode("economicLevel", ctx)
    result.economicLevel = parseEconomicLevel(node, ctx)

  ctx.withNode("scienceLevel"):
    let node = doc.requireNode("scienceLevel", ctx)
    result.scienceLevel = parseScienceLevel(node, ctx)

  ctx.withNode("construction"):
    let node = doc.requireNode("construction", ctx)
    result.constructionTech = parseStandardTechLevel(node, ctx, true)

  ctx.withNode("weapons"):
    let node = doc.requireNode("weapons", ctx)
    result.weaponsTech = parseWeaponsTech(node, ctx)

  ctx.withNode("terraforming"):
    let node = doc.requireNode("terraforming", ctx)
    result.terraformingTech = parseTerraformingTech(node, ctx)

  ctx.withNode("terraformingUpgradeCosts"):
    let node = doc.requireNode("terraformingUpgradeCosts", ctx)
    result.terraformingUpgradeCosts = parseTerraformingUpgradeCosts(node, ctx)

  ctx.withNode("electronicIntelligence"):
    let node = doc.requireNode("electronicIntelligence", ctx)
    result.electronicIntelligence = parseStandardTechLevel(node, ctx, false)

  ctx.withNode("cloaking"):
    let node = doc.requireNode("cloaking", ctx)
    result.cloakingTech = parseStandardTechLevel(node, ctx, false)

  ctx.withNode("shields"):
    let node = doc.requireNode("shields", ctx)
    result.shieldTech = parseStandardTechLevel(node, ctx, false)

  ctx.withNode("counterIntelligence"):
    let node = doc.requireNode("counterIntelligence", ctx)
    result.counterIntelligenceTech = parseStandardTechLevel(node, ctx, false)

  ctx.withNode("strategicLift"):
    let node = doc.requireNode("strategicLift", ctx)
    result.strategicLiftTech = parseStandardTechLevel(node, ctx, false)

  ctx.withNode("flagshipCommand"):
    let node = doc.requireNode("flagshipCommand", ctx)
    result.flagshipCommand = parseFlagshipCommand(node, ctx)

  ctx.withNode("strategicCommand"):
    let node = doc.requireNode("strategicCommand", ctx)
    result.strategicCommand = parseStrategicCommand(node, ctx)

  ctx.withNode("fighterDoctrine"):
    let node = doc.requireNode("fighterDoctrine", ctx)
    result.fighterDoctrine = parseFighterDoctrine(node, ctx)

  ctx.withNode("advancedCarrierOperations"):
    let node = doc.requireNode("advancedCarrierOperations", ctx)
    result.advancedCarrierOperations = parseAdvancedCarrierOps(node, ctx)

  logInfo("Config", "Loaded technology configuration", "path=", configPath)
