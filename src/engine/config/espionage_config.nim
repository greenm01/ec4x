## Espionage Configuration Loader
##
## Loads espionage mechanics from config/espionage.toml
## Allows runtime configuration for balance testing

import std/[strutils]

type
  EspionageConfig* = object
    ## All espionage values loaded from TOML

    # Costs
    ebpCostPP*: int
    cipCostPP*: int
    techTheftEBP*: int
    sabotageLowEBP*: int
    sabotageHighEBP*: int
    assassinationEBP*: int
    cyberAttackEBP*: int
    economicManipulationEBP*: int
    psyopsCampaignEBP*: int

    # Investment
    thresholdPercentage*: int
    penaltyPerPercent*: int

    # Detection
    cipPerRoll*: int
    cic0Threshold*: int
    cic1Threshold*: int
    cic2Threshold*: int
    cic3Threshold*: int
    cic4Threshold*: int
    cic5Threshold*: int
    cip0Modifier*: int
    cip15Modifier*: int
    cip610Modifier*: int
    cip1115Modifier*: int
    cip1620Modifier*: int
    cip21PlusModifier*: int

    # Effects
    techTheftSRP*: int
    sabotageLowDice*: int
    sabotageHighDice*: int
    assassinationSRPReduction*: int
    economicNCVReduction*: int
    psyopsTaxReduction*: int
    effectDurationTurns*: int
    failedEspionagePrestige*: int

## Default Configuration

proc defaultEspionageConfig*(): EspionageConfig =
  ## Return default espionage values from diplomacy.md:8.2
  result = EspionageConfig(
    # Costs
    ebpCostPP: 40,
    cipCostPP: 40,
    techTheftEBP: 5,
    sabotageLowEBP: 2,
    sabotageHighEBP: 7,
    assassinationEBP: 10,
    cyberAttackEBP: 6,
    economicManipulationEBP: 6,
    psyopsCampaignEBP: 3,

    # Investment
    thresholdPercentage: 5,
    penaltyPerPercent: -1,

    # Detection
    cipPerRoll: 1,
    cic0Threshold: 21,
    cic1Threshold: 15,
    cic2Threshold: 12,
    cic3Threshold: 10,
    cic4Threshold: 7,
    cic5Threshold: 4,
    cip0Modifier: 0,
    cip15Modifier: 1,
    cip610Modifier: 2,
    cip1115Modifier: 3,
    cip1620Modifier: 4,
    cip21PlusModifier: 5,

    # Effects
    techTheftSRP: 10,
    sabotageLowDice: 6,
    sabotageHighDice: 20,
    assassinationSRPReduction: 50,
    economicNCVReduction: 50,
    psyopsTaxReduction: 25,
    effectDurationTurns: 1,
    failedEspionagePrestige: -2
  )

## Simple TOML Parser

proc parseTOMLValue(line: string): int =
  ## Extract integer value from "key = value" line
  let parts = line.split('=')
  if parts.len >= 2:
    return parseInt(parts[1].strip())
  return 0

proc loadEspionageConfig*(configPath: string = "config/espionage.toml"): EspionageConfig =
  ## Load espionage configuration from TOML file
  ## Falls back to defaults if file not found or parse error

  result = defaultEspionageConfig()

  try:
    let file = open(configPath)
    defer: file.close()

    var currentSection = ""
    for line in file.lines:
      let trimmed = line.strip()

      # Skip empty lines and comments
      if trimmed.len == 0 or trimmed[0] == '#':
        continue

      # Section headers
      if trimmed[0] == '[' and trimmed[^1] == ']':
        currentSection = trimmed[1..^2]
        continue

      # Parse key-value pairs based on section
      case currentSection
      of "costs":
        if "ebp_cost_pp" in trimmed:
          result.ebpCostPP = parseTOMLValue(trimmed)
        elif "cip_cost_pp" in trimmed:
          result.cipCostPP = parseTOMLValue(trimmed)
        elif "tech_theft_ebp" in trimmed:
          result.techTheftEBP = parseTOMLValue(trimmed)
        elif "sabotage_low_ebp" in trimmed:
          result.sabotageLowEBP = parseTOMLValue(trimmed)
        elif "sabotage_high_ebp" in trimmed:
          result.sabotageHighEBP = parseTOMLValue(trimmed)
        elif "assassination_ebp" in trimmed:
          result.assassinationEBP = parseTOMLValue(trimmed)
        elif "cyber_attack_ebp" in trimmed:
          result.cyberAttackEBP = parseTOMLValue(trimmed)
        elif "economic_manipulation_ebp" in trimmed:
          result.economicManipulationEBP = parseTOMLValue(trimmed)
        elif "psyops_campaign_ebp" in trimmed:
          result.psyopsCampaignEBP = parseTOMLValue(trimmed)

      of "investment":
        if "threshold_percentage" in trimmed:
          result.thresholdPercentage = parseTOMLValue(trimmed)
        elif "penalty_per_percent" in trimmed:
          result.penaltyPerPercent = parseTOMLValue(trimmed)

      of "detection":
        if "cip_per_roll" in trimmed:
          result.cipPerRoll = parseTOMLValue(trimmed)
        elif "cic0_threshold" in trimmed:
          result.cic0Threshold = parseTOMLValue(trimmed)
        elif "cic1_threshold" in trimmed:
          result.cic1Threshold = parseTOMLValue(trimmed)
        elif "cic2_threshold" in trimmed:
          result.cic2Threshold = parseTOMLValue(trimmed)
        elif "cic3_threshold" in trimmed:
          result.cic3Threshold = parseTOMLValue(trimmed)
        elif "cic4_threshold" in trimmed:
          result.cic4Threshold = parseTOMLValue(trimmed)
        elif "cic5_threshold" in trimmed:
          result.cic5Threshold = parseTOMLValue(trimmed)
        elif "cip_0_modifier" in trimmed:
          result.cip0Modifier = parseTOMLValue(trimmed)
        elif "cip_1_5_modifier" in trimmed:
          result.cip15Modifier = parseTOMLValue(trimmed)
        elif "cip_6_10_modifier" in trimmed:
          result.cip610Modifier = parseTOMLValue(trimmed)
        elif "cip_11_15_modifier" in trimmed:
          result.cip1115Modifier = parseTOMLValue(trimmed)
        elif "cip_16_20_modifier" in trimmed:
          result.cip1620Modifier = parseTOMLValue(trimmed)
        elif "cip_21_plus_modifier" in trimmed:
          result.cip21PlusModifier = parseTOMLValue(trimmed)

      of "effects":
        if "tech_theft_srp" in trimmed:
          result.techTheftSRP = parseTOMLValue(trimmed)
        elif "sabotage_low_dice" in trimmed:
          result.sabotageLowDice = parseTOMLValue(trimmed)
        elif "sabotage_high_dice" in trimmed:
          result.sabotageHighDice = parseTOMLValue(trimmed)
        elif "assassination_srp_reduction" in trimmed:
          result.assassinationSRPReduction = parseTOMLValue(trimmed)
        elif "economic_ncv_reduction" in trimmed:
          result.economicNCVReduction = parseTOMLValue(trimmed)
        elif "psyops_tax_reduction" in trimmed:
          result.psyopsTaxReduction = parseTOMLValue(trimmed)
        elif "effect_duration_turns" in trimmed:
          result.effectDurationTurns = parseTOMLValue(trimmed)
        elif "failed_espionage_prestige" in trimmed:
          result.failedEspionagePrestige = parseTOMLValue(trimmed)

      else:
        discard

    echo "[Config] Loaded espionage configuration from ", configPath

  except IOError:
    echo "[Config] Could not read ", configPath, " - using defaults"
  except:
    echo "[Config] Error parsing ", configPath, " - using defaults"

## Global configuration instance

var globalEspionageConfig* = loadEspionageConfig()

## Helper to reload configuration

proc reloadEspionageConfig*() =
  ## Reload configuration from file
  globalEspionageConfig = loadEspionageConfig()
