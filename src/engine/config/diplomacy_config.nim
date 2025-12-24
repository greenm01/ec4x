## Diplomacy Configuration Loader
##
## Loads diplomacy values from config/diplomacy.toml using toml_serialization
## Allows runtime configuration for balance testing

import std/[os]
import toml_serialization
import ../../common/logger

type
  PactViolationsConfig* = object
    dishonored_status_turns*: int
    dishonor_corruption_magnitude*: float
    diplomatic_isolation_turns*: int
    pact_reinstatement_cooldown*: int
    repeat_violation_window*: int

  EspionageEffectsConfig* = object
    tech_theft_srp_stolen*: int
    low_sabotage_dice*: string
    low_sabotage_iu_min*: int
    low_sabotage_iu_max*: int
    high_sabotage_dice*: string
    high_sabotage_iu_min*: int
    high_sabotage_iu_max*: int
    assassination_srp_reduction*: float
    assassination_duration_turns*: int
    economic_disruption_ncv_reduction*: float
    economic_disruption_duration_turns*: int
    propaganda_tax_reduction*: float
    propaganda_duration_turns*: int
    cyber_attack_effect*: string

  DetectionConfig* = object
    failed_espionage_prestige_loss*: int

  DiplomacyConfig* = object ## Complete diplomacy configuration loaded from TOML
    pact_violations*: PactViolationsConfig
    espionage_effects*: EspionageEffectsConfig
    detection*: DetectionConfig

proc loadDiplomacyConfig*(
    configPath: string = "config/diplomacy.toml"
): DiplomacyConfig =
  ## Load diplomacy configuration from TOML file
  ## Uses toml_serialization for type-safe parsing

  if not fileExists(configPath):
    raise newException(IOError, "Diplomacy config not found: " & configPath)

  let configContent = readFile(configPath)
  result = Toml.decode(configContent, DiplomacyConfig)

  logInfo("Config", "Loaded diplomacy configuration", "path=", configPath)

## Global configuration instance

var globalDiplomacyConfig* = loadDiplomacyConfig()

## Helper to reload configuration (for testing)

proc reloadDiplomacyConfig*() =
  ## Reload configuration from file
  globalDiplomacyConfig = loadDiplomacyConfig()
