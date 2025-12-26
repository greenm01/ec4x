## Technology Configuration Loader
##
## Loads technology research costs and effects from config/tech.kdl
## Allows runtime configuration for all tech trees

import kdl
import kdl_config_helpers
import ../../common/logger
import ../types/config

proc parseStartingTech(node: KdlNode, ctx: var KdlConfigContext): StartingTechConfig =
  result = StartingTechConfig(
    economicLevel: node.requireInt("economicLevel", ctx).int32,
    scienceLevel: node.requireInt("scienceLevel", ctx).int32,
    constructionTech: node.requireInt("constructionTech", ctx).int32,
    weaponsTech: node.requireInt("weaponsTech", ctx).int32,
    terraformingTech: node.requireInt("terraformingTech", ctx).int32,
    electronicIntelligence: node.requireInt("electronicIntelligence", ctx).int32,
    cloakingTech: node.requireInt("cloakingTech", ctx).int32,
    shieldTech: node.requireInt("shieldTech", ctx).int32,
    counterIntelligence: node.requireInt("counterIntelligence", ctx).int32,
    fighterDoctrine: node.requireInt("fighterDoctrine", ctx).int32,
    advancedCarrierOps: node.requireInt("advancedCarrierOps", ctx).int32
  )

proc parseEconomicLevel(node: KdlNode, ctx: var KdlConfigContext): EconomicLevelConfig =
  result = EconomicLevelConfig(
    level1Erp: node.requireInt("level1Erp", ctx).int32,
    level1Mod: node.requireFloat("level1Mod", ctx).float32,
    level2Erp: node.requireInt("level2Erp", ctx).int32,
    level2Mod: node.requireFloat("level2Mod", ctx).float32,
    level3Erp: node.requireInt("level3Erp", ctx).int32,
    level3Mod: node.requireFloat("level3Mod", ctx).float32,
    level4Erp: node.requireInt("level4Erp", ctx).int32,
    level4Mod: node.requireFloat("level4Mod", ctx).float32,
    level5Erp: node.requireInt("level5Erp", ctx).int32,
    level5Mod: node.requireFloat("level5Mod", ctx).float32,
    level6Erp: node.requireInt("level6Erp", ctx).int32,
    level6Mod: node.requireFloat("level6Mod", ctx).float32,
    level7Erp: node.requireInt("level7Erp", ctx).int32,
    level7Mod: node.requireFloat("level7Mod", ctx).float32,
    level8Erp: node.requireInt("level8Erp", ctx).int32,
    level8Mod: node.requireFloat("level8Mod", ctx).float32,
    level9Erp: node.requireInt("level9Erp", ctx).int32,
    level9Mod: node.requireFloat("level9Mod", ctx).float32,
    level10Erp: node.requireInt("level10Erp", ctx).int32,
    level10Mod: node.requireFloat("level10Mod", ctx).float32,
    level11Erp: node.requireInt("level11Erp", ctx).int32,
    level11Mod: node.requireFloat("level11Mod", ctx).float32
  )

proc parseScienceLevel(node: KdlNode, ctx: var KdlConfigContext): ScienceLevelConfig =
  result = ScienceLevelConfig(
    level1Srp: node.requireInt("level1Srp", ctx).int32,
    level2Srp: node.requireInt("level2Srp", ctx).int32,
    level3Srp: node.requireInt("level3Srp", ctx).int32,
    level4Srp: node.requireInt("level4Srp", ctx).int32,
    level5Srp: node.requireInt("level5Srp", ctx).int32,
    level6Srp: node.requireInt("level6Srp", ctx).int32,
    level7Srp: node.requireInt("level7Srp", ctx).int32,
    level8Srp: node.requireInt("level8Srp", ctx).int32
  )

proc parseStandardTechLevel(
  node: KdlNode,
  ctx: var KdlConfigContext,
  hasCapacityMultiplier: bool = false
): StandardTechLevelConfig =
  result = StandardTechLevelConfig(
    capacityMultiplierPerLevel:
      if hasCapacityMultiplier:
        node.requireFloat("capacityMultiplierPerLevel", ctx).float32
      else: 0.0'f32,
    level1Sl: node.requireInt("level1Sl", ctx).int32,
    level1Trp: node.requireInt("level1Trp", ctx).int32,
    level2Sl: node.requireInt("level2Sl", ctx).int32,
    level2Trp: node.requireInt("level2Trp", ctx).int32,
    level3Sl: node.requireInt("level3Sl", ctx).int32,
    level3Trp: node.requireInt("level3Trp", ctx).int32,
    level4Sl: node.requireInt("level4Sl", ctx).int32,
    level4Trp: node.requireInt("level4Trp", ctx).int32,
    level5Sl: node.requireInt("level5Sl", ctx).int32,
    level5Trp: node.requireInt("level5Trp", ctx).int32,
    level6Sl: node.requireInt("level6Sl", ctx).int32,
    level6Trp: node.requireInt("level6Trp", ctx).int32,
    level7Sl: node.requireInt("level7Sl", ctx).int32,
    level7Trp: node.requireInt("level7Trp", ctx).int32,
    level8Sl: node.requireInt("level8Sl", ctx).int32,
    level8Trp: node.requireInt("level8Trp", ctx).int32,
    level9Sl: node.requireInt("level9Sl", ctx).int32,
    level9Trp: node.requireInt("level9Trp", ctx).int32,
    level10Sl: node.requireInt("level10Sl", ctx).int32,
    level10Trp: node.requireInt("level10Trp", ctx).int32,
    level11Sl: node.requireInt("level11Sl", ctx).int32,
    level11Trp: node.requireInt("level11Trp", ctx).int32,
    level12Sl: node.requireInt("level12Sl", ctx).int32,
    level12Trp: node.requireInt("level12Trp", ctx).int32,
    level13Sl: node.requireInt("level13Sl", ctx).int32,
    level13Trp: node.requireInt("level13Trp", ctx).int32,
    level14Sl: node.requireInt("level14Sl", ctx).int32,
    level14Trp: node.requireInt("level14Trp", ctx).int32,
    level15Sl: node.requireInt("level15Sl", ctx).int32,
    level15Trp: node.requireInt("level15Trp", ctx).int32
  )

proc parseWeaponsTech(node: KdlNode, ctx: var KdlConfigContext): WeaponsTechConfig =
  result = WeaponsTechConfig(
    weaponsStatIncreasePerLevel:
      node.requireFloat("weaponsStatIncreasePerLevel", ctx).float32,
    weaponsCostIncreasePerLevel:
      node.requireFloat("weaponsCostIncreasePerLevel", ctx).float32,
    level1Sl: node.requireInt("level1Sl", ctx).int32,
    level1Trp: node.requireInt("level1Trp", ctx).int32,
    level2Sl: node.requireInt("level2Sl", ctx).int32,
    level2Trp: node.requireInt("level2Trp", ctx).int32,
    level3Sl: node.requireInt("level3Sl", ctx).int32,
    level3Trp: node.requireInt("level3Trp", ctx).int32,
    level4Sl: node.requireInt("level4Sl", ctx).int32,
    level4Trp: node.requireInt("level4Trp", ctx).int32,
    level5Sl: node.requireInt("level5Sl", ctx).int32,
    level5Trp: node.requireInt("level5Trp", ctx).int32,
    level6Sl: node.requireInt("level6Sl", ctx).int32,
    level6Trp: node.requireInt("level6Trp", ctx).int32,
    level7Sl: node.requireInt("level7Sl", ctx).int32,
    level7Trp: node.requireInt("level7Trp", ctx).int32,
    level8Sl: node.requireInt("level8Sl", ctx).int32,
    level8Trp: node.requireInt("level8Trp", ctx).int32,
    level9Sl: node.requireInt("level9Sl", ctx).int32,
    level9Trp: node.requireInt("level9Trp", ctx).int32,
    level10Sl: node.requireInt("level10Sl", ctx).int32,
    level10Trp: node.requireInt("level10Trp", ctx).int32,
    level11Sl: node.requireInt("level11Sl", ctx).int32,
    level11Trp: node.requireInt("level11Trp", ctx).int32,
    level12Sl: node.requireInt("level12Sl", ctx).int32,
    level12Trp: node.requireInt("level12Trp", ctx).int32,
    level13Sl: node.requireInt("level13Sl", ctx).int32,
    level13Trp: node.requireInt("level13Trp", ctx).int32,
    level14Sl: node.requireInt("level14Sl", ctx).int32,
    level14Trp: node.requireInt("level14Trp", ctx).int32,
    level15Sl: node.requireInt("level15Sl", ctx).int32,
    level15Trp: node.requireInt("level15Trp", ctx).int32
  )

proc parseTerraformingTech(
  node: KdlNode,
  ctx: var KdlConfigContext
): TerraformingTechConfig =
  result = TerraformingTechConfig(
    level1Sl: node.requireInt("level1Sl", ctx).int32,
    level1Trp: node.requireInt("level1Trp", ctx).int32,
    level1PlanetClass: node.requireString("level1PlanetClass", ctx),
    level2Sl: node.requireInt("level2Sl", ctx).int32,
    level2Trp: node.requireInt("level2Trp", ctx).int32,
    level2PlanetClass: node.requireString("level2PlanetClass", ctx),
    level3Sl: node.requireInt("level3Sl", ctx).int32,
    level3Trp: node.requireInt("level3Trp", ctx).int32,
    level3PlanetClass: node.requireString("level3PlanetClass", ctx),
    level4Sl: node.requireInt("level4Sl", ctx).int32,
    level4Trp: node.requireInt("level4Trp", ctx).int32,
    level4PlanetClass: node.requireString("level4PlanetClass", ctx),
    level5Sl: node.requireInt("level5Sl", ctx).int32,
    level5Trp: node.requireInt("level5Trp", ctx).int32,
    level5PlanetClass: node.requireString("level5PlanetClass", ctx),
    level6Sl: node.requireInt("level6Sl", ctx).int32,
    level6Trp: node.requireInt("level6Trp", ctx).int32,
    level6PlanetClass: node.requireString("level6PlanetClass", ctx),
    level7Sl: node.requireInt("level7Sl", ctx).int32,
    level7Trp: node.requireInt("level7Trp", ctx).int32,
    level7PlanetClass: node.requireString("level7PlanetClass", ctx)
  )

proc parseTerraformingUpgradeCosts(
  node: KdlNode,
  ctx: var KdlConfigContext
): TerraformingUpgradeCostsConfig =
  result = TerraformingUpgradeCostsConfig(
    extremeTer: node.requireInt("extremeTer", ctx).int32,
    extremePuMin: node.requireInt("extremePuMin", ctx).int32,
    extremePuMax: node.requireInt("extremePuMax", ctx).int32,
    extremePp: node.requireInt("extremePp", ctx).int32,
    desolateTer: node.requireInt("desolateTer", ctx).int32,
    desolatePuMin: node.requireInt("desolatePuMin", ctx).int32,
    desolatePuMax: node.requireInt("desolatePuMax", ctx).int32,
    desolatePp: node.requireInt("desolatePp", ctx).int32,
    hostileTer: node.requireInt("hostileTer", ctx).int32,
    hostilePuMin: node.requireInt("hostilePuMin", ctx).int32,
    hostilePuMax: node.requireInt("hostilePuMax", ctx).int32,
    hostilePp: node.requireInt("hostilePp", ctx).int32,
    harshTer: node.requireInt("harshTer", ctx).int32,
    harshPuMin: node.requireInt("harshPuMin", ctx).int32,
    harshPuMax: node.requireInt("harshPuMax", ctx).int32,
    harshPp: node.requireInt("harshPp", ctx).int32,
    benignTer: node.requireInt("benignTer", ctx).int32,
    benignPuMin: node.requireInt("benignPuMin", ctx).int32,
    benignPuMax: node.requireInt("benignPuMax", ctx).int32,
    benignPp: node.requireInt("benignPp", ctx).int32,
    lushTer: node.requireInt("lushTer", ctx).int32,
    lushPuMin: node.requireInt("lushPuMin", ctx).int32,
    lushPuMax: node.requireInt("lushPuMax", ctx).int32,
    lushPp: node.requireInt("lushPp", ctx).int32,
    edenTer: node.requireInt("edenTer", ctx).int32,
    edenPuMin: node.requireInt("edenPuMin", ctx).int32,
    edenPuMax: node.requireInt("edenPuMax", ctx).int32,
    edenPp: node.requireInt("edenPp", ctx).int32
  )

proc parseFighterDoctrine(
  node: KdlNode,
  ctx: var KdlConfigContext
): FighterDoctrineConfig =
  result = FighterDoctrineConfig(
    level1Sl: node.requireInt("level1Sl", ctx).int32,
    level1Trp: node.requireInt("level1Trp", ctx).int32,
    level1CapacityMultiplier:
      node.requireFloat("level1CapacityMultiplier", ctx).float32,
    level1Description: node.requireString("level1Description", ctx),
    level2Sl: node.requireInt("level2Sl", ctx).int32,
    level2Trp: node.requireInt("level2Trp", ctx).int32,
    level2CapacityMultiplier:
      node.requireFloat("level2CapacityMultiplier", ctx).float32,
    level2Description: node.requireString("level2Description", ctx),
    level3Sl: node.requireInt("level3Sl", ctx).int32,
    level3Trp: node.requireInt("level3Trp", ctx).int32,
    level3CapacityMultiplier:
      node.requireFloat("level3CapacityMultiplier", ctx).float32,
    level3Description: node.requireString("level3Description", ctx)
  )

proc parseAdvancedCarrierOps(
  node: KdlNode,
  ctx: var KdlConfigContext
): AdvancedCarrierOpsConfig =
  result = AdvancedCarrierOpsConfig(
    capacityMultiplierPerLevel:
      node.requireFloat("capacityMultiplierPerLevel", ctx).float32,
    level1Sl: node.requireInt("level1Sl", ctx).int32,
    level1Trp: node.requireInt("level1Trp", ctx).int32,
    level1CvCapacity: node.requireInt("level1CvCapacity", ctx).int32,
    level1CxCapacity: node.requireInt("level1CxCapacity", ctx).int32,
    level1Description: node.requireString("level1Description", ctx),
    level2Sl: node.requireInt("level2Sl", ctx).int32,
    level2Trp: node.requireInt("level2Trp", ctx).int32,
    level2CvCapacity: node.requireInt("level2CvCapacity", ctx).int32,
    level2CxCapacity: node.requireInt("level2CxCapacity", ctx).int32,
    level2Description: node.requireString("level2Description", ctx),
    level3Sl: node.requireInt("level3Sl", ctx).int32,
    level3Trp: node.requireInt("level3Trp", ctx).int32,
    level3CvCapacity: node.requireInt("level3CvCapacity", ctx).int32,
    level3CxCapacity: node.requireInt("level3CxCapacity", ctx).int32,
    level3Description: node.requireString("level3Description", ctx)
  )

proc loadTechConfig*(configPath: string = "config/tech.kdl"): TechConfig =
  ## Load technology configuration from KDL file
  ## Uses kdl_config_helpers for type-safe parsing
  let doc = loadKdlConfig(configPath)
  var ctx = newContext(configPath)

  ctx.withNode("startingTech"):
    let node = doc.requireNode("startingTech", ctx)
    result.startingTech = parseStartingTech(node, ctx)

  ctx.withNode("economicLevel"):
    let node = doc.requireNode("economicLevel", ctx)
    result.economicLevel = parseEconomicLevel(node, ctx)

  ctx.withNode("scienceLevel"):
    let node = doc.requireNode("scienceLevel", ctx)
    result.scienceLevel = parseScienceLevel(node, ctx)

  ctx.withNode("constructionTech"):
    let node = doc.requireNode("constructionTech", ctx)
    result.constructionTech = parseStandardTechLevel(node, ctx, true)

  ctx.withNode("weaponsTech"):
    let node = doc.requireNode("weaponsTech", ctx)
    result.weaponsTech = parseWeaponsTech(node, ctx)

  ctx.withNode("terraformingTech"):
    let node = doc.requireNode("terraformingTech", ctx)
    result.terraformingTech = parseTerraformingTech(node, ctx)

  ctx.withNode("terraformingUpgradeCosts"):
    let node = doc.requireNode("terraformingUpgradeCosts", ctx)
    result.terraformingUpgradeCosts = parseTerraformingUpgradeCosts(node, ctx)

  ctx.withNode("electronicIntelligence"):
    let node = doc.requireNode("electronicIntelligence", ctx)
    result.electronicIntelligence = parseStandardTechLevel(node, ctx, false)

  ctx.withNode("cloakingTech"):
    let node = doc.requireNode("cloakingTech", ctx)
    result.cloakingTech = parseStandardTechLevel(node, ctx, false)

  ctx.withNode("shieldTech"):
    let node = doc.requireNode("shieldTech", ctx)
    result.shieldTech = parseStandardTechLevel(node, ctx, false)

  ctx.withNode("counterIntelligenceTech"):
    let node = doc.requireNode("counterIntelligenceTech", ctx)
    result.counterIntelligenceTech = parseStandardTechLevel(node, ctx, false)

  ctx.withNode("fighterDoctrine"):
    let node = doc.requireNode("fighterDoctrine", ctx)
    result.fighterDoctrine = parseFighterDoctrine(node, ctx)

  ctx.withNode("advancedCarrierOperations"):
    let node = doc.requireNode("advancedCarrierOperations", ctx)
    result.advancedCarrierOperations = parseAdvancedCarrierOps(node, ctx)

  logInfo("Config", "Loaded technology configuration", "path=", configPath)

## Global configuration instance

var globalTechConfig* = loadTechConfig()

## Helper to reload configuration (for testing)

proc reloadTechConfig*() =
  ## Reload configuration from file
  globalTechConfig = loadTechConfig()

## ============================================================================
## Cost Lookup Helpers
## ============================================================================
## These functions provide runtime access to tech advancement costs from config
## Used by src/engine/research/costs.nim for tech progression

proc getELUpgradeCostFromConfig*(level: int32): int32 =
  ## Get ERP cost for advancing from level N to N+1
  ## Uses loaded config data from tech.kdl
  let cfg = globalTechConfig.economicLevel

  case level
  of 1: return cfg.level1Erp
  of 2: return cfg.level2Erp
  of 3: return cfg.level3Erp
  of 4: return cfg.level4Erp
  of 5: return cfg.level5Erp
  of 6: return cfg.level6Erp
  of 7: return cfg.level7Erp
  of 8: return cfg.level8Erp
  of 9: return cfg.level9Erp
  of 10: return cfg.level10Erp
  of 11: return cfg.level11Erp
  else:
    raise newException(
      ValueError,
      "Invalid EL level: " & $level & " (max is 11)"
    )

proc getSLUpgradeCostFromConfig*(level: int32): int32 =
  ## Get SRP cost for advancing from level N to N+1
  let cfg = globalTechConfig.scienceLevel

  case level
  of 1: return cfg.level1Srp
  of 2: return cfg.level2Srp
  of 3: return cfg.level3Srp
  of 4: return cfg.level4Srp
  of 5: return cfg.level5Srp
  of 6: return cfg.level6Srp
  of 7: return cfg.level7Srp
  of 8: return cfg.level8Srp
  else:
    raise newException(
      ValueError,
      "Invalid SL level: " & $level & " (max is 8)"
    )

proc getTechUpgradeCostFromConfig*(techField: TechField, level: int32): int32 =
  ## Get TRP cost for advancing from level N to N+1
  ## Looks up cost from globalTechConfig based on field and level

  case techField
  of TechField.ConstructionTech:
    let cfg = globalTechConfig.constructionTech
    case level
    of 1: return cfg.level1Trp
    of 2: return cfg.level2Trp
    of 3: return cfg.level3Trp
    of 4: return cfg.level4Trp
    of 5: return cfg.level5Trp
    of 6: return cfg.level6Trp
    of 7: return cfg.level7Trp
    of 8: return cfg.level8Trp
    of 9: return cfg.level9Trp
    of 10: return cfg.level10Trp
    of 11: return cfg.level11Trp
    of 12: return cfg.level12Trp
    of 13: return cfg.level13Trp
    of 14: return cfg.level14Trp
    of 15: return cfg.level15Trp
    else:
      raise newException(
        ValueError,
        "Invalid CST level: " & $level & " (max is 15)"
      )
  of TechField.WeaponsTech:
    let cfg = globalTechConfig.weaponsTech
    case level
    of 1: return cfg.level1Trp
    of 2: return cfg.level2Trp
    of 3: return cfg.level3Trp
    of 4: return cfg.level4Trp
    of 5: return cfg.level5Trp
    of 6: return cfg.level6Trp
    of 7: return cfg.level7Trp
    of 8: return cfg.level8Trp
    of 9: return cfg.level9Trp
    of 10: return cfg.level10Trp
    of 11: return cfg.level11Trp
    of 12: return cfg.level12Trp
    of 13: return cfg.level13Trp
    of 14: return cfg.level14Trp
    of 15: return cfg.level15Trp
    else:
      raise newException(
        ValueError,
        "Invalid WEP level: " & $level & " (max is 15)"
      )
  of TechField.TerraformingTech:
    let cfg = globalTechConfig.terraformingTech
    case level
    of 1: return cfg.level1Trp
    of 2: return cfg.level2Trp
    of 3: return cfg.level3Trp
    of 4: return cfg.level4Trp
    of 5: return cfg.level5Trp
    of 6: return cfg.level6Trp
    of 7: return cfg.level7Trp
    else: return 30 + (level - 7) * 5 # Level 8+
  of TechField.ElectronicIntelligence:
    let cfg = globalTechConfig.electronicIntelligence
    case level
    of 1: return cfg.level1Trp
    of 2: return cfg.level2Trp
    of 3: return cfg.level3Trp
    of 4: return cfg.level4Trp
    of 5: return cfg.level5Trp
    of 6: return cfg.level6Trp
    of 7: return cfg.level7Trp
    of 8: return cfg.level8Trp
    of 9: return cfg.level9Trp
    of 10: return cfg.level10Trp
    of 11: return cfg.level11Trp
    of 12: return cfg.level12Trp
    of 13: return cfg.level13Trp
    of 14: return cfg.level14Trp
    of 15: return cfg.level15Trp
    else:
      raise newException(
        ValueError,
        "Invalid ELI level: " & $level & " (max is 15)"
      )
  of TechField.CloakingTech:
    let cfg = globalTechConfig.cloakingTech
    case level
    of 1: return cfg.level1Trp
    of 2: return cfg.level2Trp
    of 3: return cfg.level3Trp
    of 4: return cfg.level4Trp
    of 5: return cfg.level5Trp
    of 6: return cfg.level6Trp
    of 7: return cfg.level7Trp
    of 8: return cfg.level8Trp
    of 9: return cfg.level9Trp
    of 10: return cfg.level10Trp
    of 11: return cfg.level11Trp
    of 12: return cfg.level12Trp
    of 13: return cfg.level13Trp
    of 14: return cfg.level14Trp
    of 15: return cfg.level15Trp
    else:
      raise newException(
        ValueError,
        "Invalid CLK level: " & $level & " (max is 15)"
      )
  of TechField.ShieldTech:
    let cfg = globalTechConfig.shieldTech
    case level
    of 1: return cfg.level1Trp
    of 2: return cfg.level2Trp
    of 3: return cfg.level3Trp
    of 4: return cfg.level4Trp
    of 5: return cfg.level5Trp
    of 6: return cfg.level6Trp
    of 7: return cfg.level7Trp
    of 8: return cfg.level8Trp
    of 9: return cfg.level9Trp
    of 10: return cfg.level10Trp
    of 11: return cfg.level11Trp
    of 12: return cfg.level12Trp
    of 13: return cfg.level13Trp
    of 14: return cfg.level14Trp
    of 15: return cfg.level15Trp
    else:
      raise newException(
        ValueError,
        "Invalid SLD level: " & $level & " (max is 15)"
      )
  of TechField.CounterIntelligence:
    let cfg = globalTechConfig.counterIntelligenceTech
    case level
    of 1: return cfg.level1Trp
    of 2: return cfg.level2Trp
    of 3: return cfg.level3Trp
    of 4: return cfg.level4Trp
    of 5: return cfg.level5Trp
    of 6: return cfg.level6Trp
    of 7: return cfg.level7Trp
    of 8: return cfg.level8Trp
    of 9: return cfg.level9Trp
    of 10: return cfg.level10Trp
    of 11: return cfg.level11Trp
    of 12: return cfg.level12Trp
    of 13: return cfg.level13Trp
    of 14: return cfg.level14Trp
    of 15: return cfg.level15Trp
    else:
      raise newException(
        ValueError,
        "Invalid CIC level: " & $level & " (max is 15)"
      )
  of TechField.FighterDoctrine:
    let cfg = globalTechConfig.fighterDoctrine
    case level
    of 1: return cfg.level1Trp
    of 2: return cfg.level2Trp
    of 3: return cfg.level3Trp
    else:
      raise newException(
        ValueError,
        "Invalid FD level: " & $level & " (max is 3)"
      )
  of TechField.AdvancedCarrierOps:
    let cfg = globalTechConfig.advancedCarrierOperations
    case level
    of 1: return cfg.level1Trp
    of 2: return cfg.level2Trp
    of 3: return cfg.level3Trp
    else:
      raise newException(
        ValueError,
        "Invalid ACO level: " & $level & " (max is 3)"
      )
