## Technology Configuration Loader
##
## Loads technology research costs and effects from config/tech.kdl
## Allows runtime configuration for all tech trees

import kdl
import kdl_helpers
import ../../common/logger
import ../types/config

proc parseStartingTech(node: KdlNode, ctx: var KdlConfigContext): StartingTechConfig =
  result = StartingTechConfig(
    economicLevel: node.requireInt32("economicLevel", ctx),
    scienceLevel: node.requireInt32("scienceLevel", ctx),
    constructionTech: node.requireInt32("constructionTech", ctx),
    weaponsTech: node.requireInt32("weaponsTech", ctx),
    terraformingTech: node.requireInt32("terraformingTech", ctx),
    electronicIntelligence: node.requireInt32("electronicIntelligence", ctx),
    cloakingTech: node.requireInt32("cloakingTech", ctx),
    shieldTech: node.requireInt32("shieldTech", ctx),
    counterIntelligence: node.requireInt32("counterIntelligence", ctx),
    fighterDoctrine: node.requireInt32("fighterDoctrine", ctx),
    advancedCarrierOps: node.requireInt32("advancedCarrierOps", ctx)
  )

proc parseEconomicLevel(node: KdlNode, ctx: var KdlConfigContext): EconomicLevelConfig =
  result = EconomicLevelConfig(
    level1Erp: node.requireInt32("level1Erp", ctx),
    level1Mod: node.requireFloat32("level1Mod", ctx),
    level2Erp: node.requireInt32("level2Erp", ctx),
    level2Mod: node.requireFloat32("level2Mod", ctx),
    level3Erp: node.requireInt32("level3Erp", ctx),
    level3Mod: node.requireFloat32("level3Mod", ctx),
    level4Erp: node.requireInt32("level4Erp", ctx),
    level4Mod: node.requireFloat32("level4Mod", ctx),
    level5Erp: node.requireInt32("level5Erp", ctx),
    level5Mod: node.requireFloat32("level5Mod", ctx),
    level6Erp: node.requireInt32("level6Erp", ctx),
    level6Mod: node.requireFloat32("level6Mod", ctx),
    level7Erp: node.requireInt32("level7Erp", ctx),
    level7Mod: node.requireFloat32("level7Mod", ctx),
    level8Erp: node.requireInt32("level8Erp", ctx),
    level8Mod: node.requireFloat32("level8Mod", ctx),
    level9Erp: node.requireInt32("level9Erp", ctx),
    level9Mod: node.requireFloat32("level9Mod", ctx),
    level10Erp: node.requireInt32("level10Erp", ctx),
    level10Mod: node.requireFloat32("level10Mod", ctx),
    level11Erp: node.requireInt32("level11Erp", ctx),
    level11Mod: node.requireFloat32("level11Mod", ctx)
  )

proc parseScienceLevel(node: KdlNode, ctx: var KdlConfigContext): ScienceLevelConfig =
  result = ScienceLevelConfig(
    level1Srp: node.requireInt32("level1Srp", ctx),
    level2Srp: node.requireInt32("level2Srp", ctx),
    level3Srp: node.requireInt32("level3Srp", ctx),
    level4Srp: node.requireInt32("level4Srp", ctx),
    level5Srp: node.requireInt32("level5Srp", ctx),
    level6Srp: node.requireInt32("level6Srp", ctx),
    level7Srp: node.requireInt32("level7Srp", ctx),
    level8Srp: node.requireInt32("level8Srp", ctx)
  )

proc parseStandardTechLevel(
  node: KdlNode,
  ctx: var KdlConfigContext,
  hasCapacityMultiplier: bool = false
): StandardTechLevelConfig =
  result = StandardTechLevelConfig(
    capacityMultiplierPerLevel:
      if hasCapacityMultiplier:
        node.requireFloat32("capacityMultiplierPerLevel", ctx)
      else: 0.0'f32,
    level1Sl: node.requireInt32("level1Sl", ctx),
    level1Trp: node.requireInt32("level1Trp", ctx),
    level2Sl: node.requireInt32("level2Sl", ctx),
    level2Trp: node.requireInt32("level2Trp", ctx),
    level3Sl: node.requireInt32("level3Sl", ctx),
    level3Trp: node.requireInt32("level3Trp", ctx),
    level4Sl: node.requireInt32("level4Sl", ctx),
    level4Trp: node.requireInt32("level4Trp", ctx),
    level5Sl: node.requireInt32("level5Sl", ctx),
    level5Trp: node.requireInt32("level5Trp", ctx),
    level6Sl: node.requireInt32("level6Sl", ctx),
    level6Trp: node.requireInt32("level6Trp", ctx),
    level7Sl: node.requireInt32("level7Sl", ctx),
    level7Trp: node.requireInt32("level7Trp", ctx),
    level8Sl: node.requireInt32("level8Sl", ctx),
    level8Trp: node.requireInt32("level8Trp", ctx),
    level9Sl: node.requireInt32("level9Sl", ctx),
    level9Trp: node.requireInt32("level9Trp", ctx),
    level10Sl: node.requireInt32("level10Sl", ctx),
    level10Trp: node.requireInt32("level10Trp", ctx),
    level11Sl: node.requireInt32("level11Sl", ctx),
    level11Trp: node.requireInt32("level11Trp", ctx),
    level12Sl: node.requireInt32("level12Sl", ctx),
    level12Trp: node.requireInt32("level12Trp", ctx),
    level13Sl: node.requireInt32("level13Sl", ctx),
    level13Trp: node.requireInt32("level13Trp", ctx),
    level14Sl: node.requireInt32("level14Sl", ctx),
    level14Trp: node.requireInt32("level14Trp", ctx),
    level15Sl: node.requireInt32("level15Sl", ctx),
    level15Trp: node.requireInt32("level15Trp", ctx)
  )

proc parseWeaponsTech(node: KdlNode, ctx: var KdlConfigContext): WeaponsTechConfig =
  result = WeaponsTechConfig(
    weaponsStatIncreasePerLevel:
      node.requireFloat32("weaponsStatIncreasePerLevel", ctx),
    weaponsCostIncreasePerLevel:
      node.requireFloat32("weaponsCostIncreasePerLevel", ctx),
    level1Sl: node.requireInt32("level1Sl", ctx),
    level1Trp: node.requireInt32("level1Trp", ctx),
    level2Sl: node.requireInt32("level2Sl", ctx),
    level2Trp: node.requireInt32("level2Trp", ctx),
    level3Sl: node.requireInt32("level3Sl", ctx),
    level3Trp: node.requireInt32("level3Trp", ctx),
    level4Sl: node.requireInt32("level4Sl", ctx),
    level4Trp: node.requireInt32("level4Trp", ctx),
    level5Sl: node.requireInt32("level5Sl", ctx),
    level5Trp: node.requireInt32("level5Trp", ctx),
    level6Sl: node.requireInt32("level6Sl", ctx),
    level6Trp: node.requireInt32("level6Trp", ctx),
    level7Sl: node.requireInt32("level7Sl", ctx),
    level7Trp: node.requireInt32("level7Trp", ctx),
    level8Sl: node.requireInt32("level8Sl", ctx),
    level8Trp: node.requireInt32("level8Trp", ctx),
    level9Sl: node.requireInt32("level9Sl", ctx),
    level9Trp: node.requireInt32("level9Trp", ctx),
    level10Sl: node.requireInt32("level10Sl", ctx),
    level10Trp: node.requireInt32("level10Trp", ctx),
    level11Sl: node.requireInt32("level11Sl", ctx),
    level11Trp: node.requireInt32("level11Trp", ctx),
    level12Sl: node.requireInt32("level12Sl", ctx),
    level12Trp: node.requireInt32("level12Trp", ctx),
    level13Sl: node.requireInt32("level13Sl", ctx),
    level13Trp: node.requireInt32("level13Trp", ctx),
    level14Sl: node.requireInt32("level14Sl", ctx),
    level14Trp: node.requireInt32("level14Trp", ctx),
    level15Sl: node.requireInt32("level15Sl", ctx),
    level15Trp: node.requireInt32("level15Trp", ctx)
  )

proc parseTerraformingTech(
  node: KdlNode,
  ctx: var KdlConfigContext
): TerraformingTechConfig =
  result = TerraformingTechConfig(
    level1Sl: node.requireInt32("level1Sl", ctx),
    level1Trp: node.requireInt32("level1Trp", ctx),
    level1PlanetClass: node.requireString("level1PlanetClass", ctx),
    level2Sl: node.requireInt32("level2Sl", ctx),
    level2Trp: node.requireInt32("level2Trp", ctx),
    level2PlanetClass: node.requireString("level2PlanetClass", ctx),
    level3Sl: node.requireInt32("level3Sl", ctx),
    level3Trp: node.requireInt32("level3Trp", ctx),
    level3PlanetClass: node.requireString("level3PlanetClass", ctx),
    level4Sl: node.requireInt32("level4Sl", ctx),
    level4Trp: node.requireInt32("level4Trp", ctx),
    level4PlanetClass: node.requireString("level4PlanetClass", ctx),
    level5Sl: node.requireInt32("level5Sl", ctx),
    level5Trp: node.requireInt32("level5Trp", ctx),
    level5PlanetClass: node.requireString("level5PlanetClass", ctx),
    level6Sl: node.requireInt32("level6Sl", ctx),
    level6Trp: node.requireInt32("level6Trp", ctx),
    level6PlanetClass: node.requireString("level6PlanetClass", ctx),
    level7Sl: node.requireInt32("level7Sl", ctx),
    level7Trp: node.requireInt32("level7Trp", ctx),
    level7PlanetClass: node.requireString("level7PlanetClass", ctx)
  )

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

proc parseFighterDoctrine(
  node: KdlNode,
  ctx: var KdlConfigContext
): FighterDoctrineConfig =
  result = FighterDoctrineConfig(
    level1Sl: node.requireInt32("level1Sl", ctx),
    level1Trp: node.requireInt32("level1Trp", ctx),
    level1CapacityMultiplier:
      node.requireFloat32("level1CapacityMultiplier", ctx),
    level1Description: node.requireString("level1Description", ctx),
    level2Sl: node.requireInt32("level2Sl", ctx),
    level2Trp: node.requireInt32("level2Trp", ctx),
    level2CapacityMultiplier:
      node.requireFloat32("level2CapacityMultiplier", ctx),
    level2Description: node.requireString("level2Description", ctx),
    level3Sl: node.requireInt32("level3Sl", ctx),
    level3Trp: node.requireInt32("level3Trp", ctx),
    level3CapacityMultiplier:
      node.requireFloat32("level3CapacityMultiplier", ctx),
    level3Description: node.requireString("level3Description", ctx)
  )

proc parseAdvancedCarrierOps(
  node: KdlNode,
  ctx: var KdlConfigContext
): AdvancedCarrierOpsConfig =
  result = AdvancedCarrierOpsConfig(
    capacityMultiplierPerLevel:
      node.requireFloat32("capacityMultiplierPerLevel", ctx),
    level1Sl: node.requireInt32("level1Sl", ctx),
    level1Trp: node.requireInt32("level1Trp", ctx),
    level1CvCapacity: node.requireInt32("level1CvCapacity", ctx),
    level1CxCapacity: node.requireInt32("level1CxCapacity", ctx),
    level1Description: node.requireString("level1Description", ctx),
    level2Sl: node.requireInt32("level2Sl", ctx),
    level2Trp: node.requireInt32("level2Trp", ctx),
    level2CvCapacity: node.requireInt32("level2CvCapacity", ctx),
    level2CxCapacity: node.requireInt32("level2CxCapacity", ctx),
    level2Description: node.requireString("level2Description", ctx),
    level3Sl: node.requireInt32("level3Sl", ctx),
    level3Trp: node.requireInt32("level3Trp", ctx),
    level3CvCapacity: node.requireInt32("level3CvCapacity", ctx),
    level3CxCapacity: node.requireInt32("level3CxCapacity", ctx),
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
