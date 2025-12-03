## Balance Test Configuration Loader
##
## Loads balance test scenarios from config/balance_tests.toml
## Enables test parameter changes without recompilation

import std/[os, strformat]
import toml_serialization
import ../../ai/common/types  # For AIStrategy type

# ==============================================================================
# Configuration Types
# ==============================================================================

type
  BalanceTestScenario* = object
    ## Single test scenario definition
    name*: string
    description*: string
    strategies*: seq[string]  # Strategy names (converted to AIStrategy)
    turns*: int
    map_rings*: int
    num_games*: int

  BalanceTestMetadata* = object
    ## Metadata about the configuration file
    version*: string
    description*: string

  BalanceTestConfig* = object
    ## Complete balance test configuration
    metadata*: BalanceTestMetadata
    scenarios*: seq[BalanceTestScenario]

# ==============================================================================
# Config Loading
# ==============================================================================

proc loadBalanceTestConfig*(configPath: string = "config/balance_tests.toml"): BalanceTestConfig =
  ## Load balance test configuration from TOML file
  if not fileExists(configPath):
    raise newException(IOError, "Balance test config not found: " & configPath)

  let configContent = readFile(configPath)
  result = Toml.decode(configContent, BalanceTestConfig)

  echo "[Config] Loaded balance test configuration from ", configPath

## Global configuration instance
var globalBalanceTestConfig* = loadBalanceTestConfig()

## Helper to get a scenario by name
proc getScenario*(name: string): BalanceTestScenario =
  ## Get a test scenario by name
  for scenario in globalBalanceTestConfig.scenarios:
    if scenario.name == name:
      return scenario

  raise newException(ValueError, "Balance test scenario not found: " & name)

## Helper to convert strategy strings to AIStrategy enum
proc parseStrategy*(strategyName: string): AIStrategy =
  ## Convert strategy name string to AIStrategy enum
  ## Only includes strategies actually defined in AIStrategy enum
  case strategyName:
    of "Aggressive": AIStrategy.Aggressive
    of "Economic": AIStrategy.Economic
    of "Espionage": AIStrategy.Espionage
    of "Diplomatic": AIStrategy.Diplomatic
    of "Balanced": AIStrategy.Balanced
    of "Turtle": AIStrategy.Turtle
    of "Expansionist": AIStrategy.Expansionist
    of "TechRush": AIStrategy.TechRush
    of "Raider": AIStrategy.Raider
    of "MilitaryIndustrial": AIStrategy.MilitaryIndustrial
    of "Opportunistic": AIStrategy.Opportunistic
    of "Isolationist": AIStrategy.Isolationist
    else:
      raise newException(ValueError, "Unknown strategy: " & strategyName)

proc getStrategies*(scenario: BalanceTestScenario): seq[AIStrategy] =
  ## Convert scenario's strategy strings to AIStrategy enums
  result = @[]
  for strategyName in scenario.strategies:
    result.add(parseStrategy(strategyName))
