## Technology Configuration Loader
##
## Loads technology research costs and effects from config/tech.toml
## Allows runtime configuration for all tech trees

import std/[os]
import toml_serialization
import ../../common/logger
import ../types/tech

type
  StartingTechConfig* = object
    ## Starting tech levels per economy.md:4.0
    ## CRITICAL: ALL tech starts at level 1, not 0!
    economic_level*: int32          # EL1
    science_level*: int32             # SL1
    construction_tech*: int32         # CST1
    weapons_tech*: int32              # WEP1
    terraforming_tech*: int32         # TER1
    electronic_intelligence*: int32   # ELI1
    cloaking_tech*: int32             # CLK1
    shield_tech*: int32               # SLD1 (Planetary Shields)
    counter_intelligence*: int32      # CIC1
    fighter_doctrine*: int32          # FD I (starts at 1)
    advanced_carrier_ops*: int32      # ACO I (starts at 1)

  ## Level-specific tech configurations loaded from config/tech.toml
  ## Each tech field has explicit level definitions for type safety

  EconomicLevelConfig* = object
    ## Economic Level advancement costs (11 levels, uses ERP)
    level_1_erp*: int32
    level_1_mod*: float32
    level_2_erp*: int32
    level_2_mod*: float32
    level_3_erp*: int32
    level_3_mod*: float32
    level_4_erp*: int32
    level_4_mod*: float32
    level_5_erp*: int32
    level_5_mod*: float32
    level_6_erp*: int32
    level_6_mod*: float32
    level_7_erp*: int32
    level_7_mod*: float32
    level_8_erp*: int32
    level_8_mod*: float32
    level_9_erp*: int32
    level_9_mod*: float32
    level_10_erp*: int32
    level_10_mod*: float32
    level_11_erp*: int32
    level_11_mod*: float32

  ScienceLevelConfig* = object
    ## Science Level advancement costs (8 levels, uses SRP)
    level_1_srp*: int32
    level_2_srp*: int32
    level_3_srp*: int32
    level_4_srp*: int32
    level_5_srp*: int32
    level_6_srp*: int32
    level_7_srp*: int32
    level_8_srp*: int32

  StandardTechLevelConfig* = object
    ## Standard tech fields (15 levels, uses TRP)
    ## Used by: CST, ELI, CLK, SLD, CIC
    capacity_multiplier_per_level*: Option[float32]  # Optional: for CST dock capacity scaling
    level_1_sl*: int32
    level_1_trp*: int32
    level_2_sl*: int32
    level_2_trp*: int32
    level_3_sl*: int32
    level_3_trp*: int32
    level_4_sl*: int32
    level_4_trp*: int32
    level_5_sl*: int32
    level_5_trp*: int32
    level_6_sl*: int32
    level_6_trp*: int32
    level_7_sl*: int32
    level_7_trp*: int32
    level_8_sl*: int32
    level_8_trp*: int32
    level_9_sl*: int32
    level_9_trp*: int32
    level_10_sl*: int32
    level_10_trp*: int32
    level_11_sl*: int32
    level_11_trp*: int32
    level_12_sl*: int32
    level_12_trp*: int32
    level_13_sl*: int32
    level_13_trp*: int32
    level_14_sl*: int32
    level_14_trp*: int32
    level_15_sl*: int32
    level_15_trp*: int32

  WeaponsTechConfig* = object
    ## Weapons tech with stat/cost modifiers (15 levels, uses TRP)
    weapons_stat_increase_per_level*: float32
    weapons_cost_increase_per_level*: float32
    level_1_sl*: int32
    level_1_trp*: int32
    level_2_sl*: int32
    level_2_trp*: int32
    level_3_sl*: int32
    level_3_trp*: int32
    level_4_sl*: int32
    level_4_trp*: int32
    level_5_sl*: int32
    level_5_trp*: int32
    level_6_sl*: int32
    level_6_trp*: int32
    level_7_sl*: int32
    level_7_trp*: int32
    level_8_sl*: int32
    level_8_trp*: int32
    level_9_sl*: int32
    level_9_trp*: int32
    level_10_sl*: int32
    level_10_trp*: int32
    level_11_sl*: int32
    level_11_trp*: int32
    level_12_sl*: int32
    level_12_trp*: int32
    level_13_sl*: int32
    level_13_trp*: int32
    level_14_sl*: int32
    level_14_trp*: int32
    level_15_sl*: int32
    level_15_trp*: int32

  TerraformingTechConfig* = object
    ## Terraforming tech with planet class requirements (7 levels, uses TRP)
    level_1_sl*: int32
    level_1_trp*: int32
    level_1_planet_class*: string
    level_2_sl*: int32
    level_2_trp*: int32
    level_2_planet_class*: string
    level_3_sl*: int32
    level_3_trp*: int32
    level_3_planet_class*: string
    level_4_sl*: int32
    level_4_trp*: int32
    level_4_planet_class*: string
    level_5_sl*: int32
    level_5_trp*: int32
    level_5_planet_class*: string
    level_6_sl*: int32
    level_6_trp*: int32
    level_6_planet_class*: string
    level_7_sl*: int32
    level_7_trp*: int32
    level_7_planet_class*: string

  FighterDoctrineConfig* = object
    ## Fighter Doctrine with capacity multipliers (3 levels, uses TRP)
    level_1_sl*: int32
    level_1_trp*: int32
    level_1_capacity_multiplier*: float32
    level_1_description*: string
    level_2_sl*: int32
    level_2_trp*: int32
    level_2_capacity_multiplier*: float32
    level_2_description*: string
    level_3_sl*: int32
    level_3_trp*: int32
    level_3_capacity_multiplier*: float32
    level_3_description*: string

  AdvancedCarrierOpsConfig* = object
    ## Advanced Carrier Ops with carrier capacities (3 levels, uses TRP)
    level_1_sl*: int32
    level_1_trp*: int32
    level_1_cv_capacity*: int32
    level_1_cx_capacity*: int32
    level_1_description*: string
    level_2_sl*: int32
    level_2_trp*: int32
    level_2_cv_capacity*: int32
    level_2_cx_capacity*: int32
    level_2_description*: string
    level_3_sl*: int32
    level_3_trp*: int32
    level_3_cv_capacity*: int32
    level_3_cx_capacity*: int32
    level_3_description*: string

  TerraformingUpgradeCostsConfig* = object
    ## Terraforming upgrade costs for planet classes
    extreme_ter*: int32
    extreme_pu_min*: int32
    extreme_pu_max*: int32
    extreme_pp*: int32
    desolate_ter*: int32
    desolate_pu_min*: int32
    desolate_pu_max*: int32
    desolate_pp*: int32
    hostile_ter*: int32
    hostile_pu_min*: int32
    hostile_pu_max*: int32
    hostile_pp*: int32
    harsh_ter*: int32
    harsh_pu_min*: int32
    harsh_pu_max*: int32
    harsh_pp*: int32
    benign_ter*: int32
    benign_pu_min*: int32
    benign_pu_max*: int32
    benign_pp*: int32
    lush_ter*: int32
    lush_pu_min*: int32
    lush_pu_max*: int32
    lush_pp*: int32
    eden_ter*: int32
    eden_pu_min*: int32
    eden_pu_max*: int32
    eden_pp*: int32

  TechConfig* = object
    ## Technology configuration from tech.toml
    starting_tech*: StartingTechConfig
    economic_level*: EconomicLevelConfig
    science_level*: ScienceLevelConfig
    construction_tech*: StandardTechLevelConfig
    weapons_tech*: WeaponsTechConfig
    terraforming_tech*: TerraformingTechConfig
    terraforming_upgrade_costs*: TerraformingUpgradeCostsConfig
    electronic_intelligence*: StandardTechLevelConfig
    cloaking_tech*: StandardTechLevelConfig
    shield_tech*: StandardTechLevelConfig
    counter_intelligence_tech*: StandardTechLevelConfig
    fighter_doctrine*: FighterDoctrineConfig
    advanced_carrier_operations*: AdvancedCarrierOpsConfig

proc loadTechConfig*(configPath: string = "config/tech.toml"): TechConfig =
  ## Load technology configuration from TOML file
  ## Uses toml_serialization for type-safe parsing

  if not fileExists(configPath):
    raise newException(IOError, "Tech config not found: " & configPath)

  let configContent = readFile(configPath)
  result = Toml.decode(configContent, TechConfig)

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
  ## Uses loaded config data from tech.toml
  let cfg = globalTechConfig.economic_level

  case level
  of 1: return cfg.level_1_erp
  of 2: return cfg.level_2_erp
  of 3: return cfg.level_3_erp
  of 4: return cfg.level_4_erp
  of 5: return cfg.level_5_erp
  of 6: return cfg.level_6_erp
  of 7: return cfg.level_7_erp
  of 8: return cfg.level_8_erp
  of 9: return cfg.level_9_erp
  of 10: return cfg.level_10_erp
  of 11: return cfg.level_11_erp
  else:
    raise newException(ValueError, "Invalid EL level: " & $level & " (max is 11)")

proc getSLUpgradeCostFromConfig*(level: int32): int32 =
  ## Get SRP cost for advancing from level N to N+1
  let cfg = globalTechConfig.science_level

  case level
  of 1: return cfg.level_1_srp
  of 2: return cfg.level_2_srp
  of 3: return cfg.level_3_srp
  of 4: return cfg.level_4_srp
  of 5: return cfg.level_5_srp
  of 6: return cfg.level_6_srp
  of 7: return cfg.level_7_srp
  of 8: return cfg.level_8_srp
  else:
    raise newException(ValueError, "Invalid SL level: " & $level & " (max is 8)")

proc getTechUpgradeCostFromConfig*(techField: TechField, level: int32): int32 =
  ## Get TRP cost for advancing from level N to N+1
  ## Looks up cost from globalTechConfig based on field and level

  case techField
  of TechField.ConstructionTech:
    let cfg = globalTechConfig.construction_tech
    case level
    of 1: return cfg.level_1_trp
    of 2: return cfg.level_2_trp
    of 3: return cfg.level_3_trp
    of 4: return cfg.level_4_trp
    of 5: return cfg.level_5_trp
    of 6: return cfg.level_6_trp
    of 7: return cfg.level_7_trp
    of 8: return cfg.level_8_trp
    of 9: return cfg.level_9_trp
    of 10: return cfg.level_10_trp
    of 11: return cfg.level_11_trp
    of 12: return cfg.level_12_trp
    of 13: return cfg.level_13_trp
    of 14: return cfg.level_14_trp
    of 15: return cfg.level_15_trp
    else:
      raise newException(ValueError,
        "Invalid CST level: " & $level & " (max is 15)")

  of TechField.WeaponsTech:
    let cfg = globalTechConfig.weapons_tech
    case level
    of 1: return cfg.level_1_trp
    of 2: return cfg.level_2_trp
    of 3: return cfg.level_3_trp
    of 4: return cfg.level_4_trp
    of 5: return cfg.level_5_trp
    of 6: return cfg.level_6_trp
    of 7: return cfg.level_7_trp
    of 8: return cfg.level_8_trp
    of 9: return cfg.level_9_trp
    of 10: return cfg.level_10_trp
    of 11: return cfg.level_11_trp
    of 12: return cfg.level_12_trp
    of 13: return cfg.level_13_trp
    of 14: return cfg.level_14_trp
    of 15: return cfg.level_15_trp
    else:
      raise newException(ValueError,
        "Invalid WEP level: " & $level & " (max is 15)")

  of TechField.TerraformingTech:
    let cfg = globalTechConfig.terraforming_tech
    case level
    of 1: return cfg.level_1_trp
    of 2: return cfg.level_2_trp
    of 3: return cfg.level_3_trp
    of 4: return cfg.level_4_trp
    of 5: return cfg.level_5_trp
    of 6: return cfg.level_6_trp
    of 7: return cfg.level_7_trp
    else: return 30 + (level - 7) * 5  # Level 8+

  of TechField.ElectronicIntelligence:
    let cfg = globalTechConfig.electronic_intelligence
    case level
    of 1: return cfg.level_1_trp
    of 2: return cfg.level_2_trp
    of 3: return cfg.level_3_trp
    of 4: return cfg.level_4_trp
    of 5: return cfg.level_5_trp
    of 6: return cfg.level_6_trp
    of 7: return cfg.level_7_trp
    of 8: return cfg.level_8_trp
    of 9: return cfg.level_9_trp
    of 10: return cfg.level_10_trp
    of 11: return cfg.level_11_trp
    of 12: return cfg.level_12_trp
    of 13: return cfg.level_13_trp
    of 14: return cfg.level_14_trp
    of 15: return cfg.level_15_trp
    else:
      raise newException(ValueError,
        "Invalid ELI level: " & $level & " (max is 15)")

  of TechField.CloakingTech:
    let cfg = globalTechConfig.cloaking_tech
    case level
    of 1: return cfg.level_1_trp
    of 2: return cfg.level_2_trp
    of 3: return cfg.level_3_trp
    of 4: return cfg.level_4_trp
    of 5: return cfg.level_5_trp
    of 6: return cfg.level_6_trp
    of 7: return cfg.level_7_trp
    of 8: return cfg.level_8_trp
    of 9: return cfg.level_9_trp
    of 10: return cfg.level_10_trp
    of 11: return cfg.level_11_trp
    of 12: return cfg.level_12_trp
    of 13: return cfg.level_13_trp
    of 14: return cfg.level_14_trp
    of 15: return cfg.level_15_trp
    else:
      raise newException(ValueError,
        "Invalid CLK level: " & $level & " (max is 15)")

  of TechField.ShieldTech:
    let cfg = globalTechConfig.shield_tech
    case level
    of 1: return cfg.level_1_trp
    of 2: return cfg.level_2_trp
    of 3: return cfg.level_3_trp
    of 4: return cfg.level_4_trp
    of 5: return cfg.level_5_trp
    of 6: return cfg.level_6_trp
    of 7: return cfg.level_7_trp
    of 8: return cfg.level_8_trp
    of 9: return cfg.level_9_trp
    of 10: return cfg.level_10_trp
    of 11: return cfg.level_11_trp
    of 12: return cfg.level_12_trp
    of 13: return cfg.level_13_trp
    of 14: return cfg.level_14_trp
    of 15: return cfg.level_15_trp
    else:
      raise newException(ValueError,
        "Invalid SLD level: " & $level & " (max is 15)")

  of TechField.CounterIntelligence:
    let cfg = globalTechConfig.counter_intelligence_tech
    case level
    of 1: return cfg.level_1_trp
    of 2: return cfg.level_2_trp
    of 3: return cfg.level_3_trp
    of 4: return cfg.level_4_trp
    of 5: return cfg.level_5_trp
    of 6: return cfg.level_6_trp
    of 7: return cfg.level_7_trp
    of 8: return cfg.level_8_trp
    of 9: return cfg.level_9_trp
    of 10: return cfg.level_10_trp
    of 11: return cfg.level_11_trp
    of 12: return cfg.level_12_trp
    of 13: return cfg.level_13_trp
    of 14: return cfg.level_14_trp
    of 15: return cfg.level_15_trp
    else:
      raise newException(ValueError,
        "Invalid CIC level: " & $level & " (max is 15)")

  of TechField.FighterDoctrine:
    let cfg = globalTechConfig.fighter_doctrine
    case level
    of 1: return cfg.level_1_trp
    of 2: return cfg.level_2_trp
    of 3: return cfg.level_3_trp
    else:
      raise newException(ValueError, "Invalid FD level: " & $level & " (max is 3)")

  of TechField.AdvancedCarrierOps:
    let cfg = globalTechConfig.advanced_carrier_operations
    case level
    of 1: return cfg.level_1_trp
    of 2: return cfg.level_2_trp
    of 3: return cfg.level_3_trp
    else:
      raise newException(ValueError, "Invalid ACO level: " & $level & " (max is 3)")
