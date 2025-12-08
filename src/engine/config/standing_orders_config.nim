## Standing Orders Configuration Loader
## Loads standing order behavior settings from config/standing_orders.toml

import std/[os]
import toml_serialization
import ../../common/logger

type
  ActivationConfig* = object
    global_enabled*: bool
    default_activation_delay_turns*: int
    enabled_by_default*: bool

  BehaviorConfig* = object
    auto_hold_on_completion*: bool
    respect_diplomatic_changes*: bool

  UIHintsConfig* = object
    warn_before_activation*: bool
    warn_turns_before*: int

  StandingOrdersConfig* = object
    ## Complete standing orders configuration loaded from TOML
    activation*: ActivationConfig
    behavior*: BehaviorConfig
    ui_hints*: UIHintsConfig

proc loadStandingOrdersConfig*(configPath: string = "config/standing_orders.toml"): StandingOrdersConfig =
  ## Load standing orders configuration from TOML file
  ## Uses toml_serialization for type-safe parsing

  if not fileExists(configPath):
    raise newException(IOError, "Standing orders config not found: " & configPath)

  let configContent = readFile(configPath)
  result = Toml.decode(configContent, StandingOrdersConfig)

  logInfo("Config", "Loaded standing orders configuration", "path=", configPath)

## Global configuration instance

var globalStandingOrdersConfig* = loadStandingOrdersConfig()

## Helper to reload configuration (for testing)

proc reloadStandingOrdersConfig*() =
  ## Reload configuration from file
  globalStandingOrdersConfig = loadStandingOrdersConfig()
