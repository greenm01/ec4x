## Combat Configuration Loader
##
## Loads combat mechanics from config/combat.toml using toml_serialization
## Allows runtime configuration for combat rules, CER tables, and special mechanics

import std/[os]
import toml_serialization
import ../../common/logger

type
  CombatMechanicsConfig* = object
    critical_hit_roll*: int
    retreat_after_round*: int
    starbase_critical_reroll*: bool
    starbase_die_modifier*: int

  CerModifiersConfig* = object
    scouts*: int
    surprise*: int
    ambush*: int

  CerTableConfig* = object
    very_poor_max*: int
    poor_max*: int
    average_max*: int
    good_min*: int

  BombardmentConfig* = object
    max_rounds_per_turn*: int
    very_poor_max*: int
    poor_max*: int
    good_min*: int

  GroundCombatConfig* = object
    poor_max*: int
    average_max*: int
    good_max*: int
    critical*: int

  PlanetaryShieldsConfig* = object
    sld1_chance*: int
    sld1_roll*: int
    sld1_block*: int
    sld2_chance*: int
    sld2_roll*: int
    sld2_block*: int
    sld3_chance*: int
    sld3_roll*: int
    sld3_block*: int
    sld4_chance*: int
    sld4_roll*: int
    sld4_block*: int
    sld5_chance*: int
    sld5_roll*: int
    sld5_block*: int
    sld6_chance*: int
    sld6_roll*: int
    sld6_block*: int

  DamageRulesConfig* = object
    crippled_as_multiplier*: float
    crippled_maintenance_multiplier*: float
    squadron_fights_as_unit*: bool
    destroy_after_all_crippled*: bool

  RetreatRulesConfig* = object
    fighters_never_retreat*: bool
    spacelift_destroyed_if_escort_lost*: bool
    retreat_to_nearest_friendly*: bool

  BlockadeConfig* = object
    blockade_production_penalty*: float
    blockade_prestige_penalty*: int

  InvasionConfig* = object
    invasion_iu_loss*: float
    blitz_iu_loss*: float

  CombatConfig* = object ## Complete combat configuration loaded from TOML
    combat*: CombatMechanicsConfig
    cer_modifiers*: CerModifiersConfig
    cer_table*: CerTableConfig
    bombardment*: BombardmentConfig
    ground_combat*: GroundCombatConfig
    planetary_shields*: PlanetaryShieldsConfig
    damage_rules*: DamageRulesConfig
    retreat_rules*: RetreatRulesConfig
    blockade*: BlockadeConfig
    invasion*: InvasionConfig

proc loadCombatConfig*(configPath: string = "config/combat.toml"): CombatConfig =
  ## Load combat configuration from TOML file
  ## Uses toml_serialization for type-safe parsing

  if not fileExists(configPath):
    raise newException(IOError, "Combat config not found: " & configPath)

  let configContent = readFile(configPath)
  result = Toml.decode(configContent, CombatConfig)

  logInfo("Config", "Loaded combat configuration", "path=", configPath)

## Global configuration instance

var globalCombatConfig* = loadCombatConfig()

## Helper to reload configuration (for testing)

proc reloadCombatConfig*() =
  ## Reload configuration from file
  globalCombatConfig = loadCombatConfig()
