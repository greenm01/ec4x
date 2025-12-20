## Espionage Engine
##
## Espionage operations and detection per diplomacy.md:8.2
##
## REFACTORED (Phase 9): Data-Oriented Design
## - Eliminated 93% code duplication (448 lines → ~30 lines)
## - All action-specific data in action_descriptors.nim
## - Single generic executor in executor.nim
## - This module now only handles detection and re-exports

import std/random
import ../../types/espionage as types
import action_descriptors, executor

export types, action_descriptors, executor

proc getActionCost*(action: EspionageAction): int =
  ## Get EBP cost for action (from config)
  let config = globalEspionageConfig
  case action
  of EspionageAction.TechTheft: config.costs.tech_theft_ebp
  of EspionageAction.SabotageLow: config.costs.sabotage_low_ebp
  of EspionageAction.SabotageHigh: config.costs.sabotage_high_ebp
  of EspionageAction.Assassination: config.costs.assassination_ebp
  of EspionageAction.CyberAttack: config.costs.cyber_attack_ebp
  of EspionageAction.EconomicManipulation: config.costs.economic_manipulation_ebp
  of EspionageAction.PsyopsCampaign: config.costs.psyops_campaign_ebp
  of EspionageAction.CounterIntelSweep: config.costs.counter_intel_sweep_ebp
  of EspionageAction.IntelligenceTheft: config.costs.intelligence_theft_ebp
  of EspionageAction.PlantDisinformation: config.costs.plant_disinformation_ebp

proc getDetectionThreshold*(cicLevel: CICLevel): int =
  ## Get detection roll threshold for CIC level (from config)
  ## Per diplomacy.md:8.3 - roll must meet or exceed threshold
  let config = globalEspionageConfig
  case cicLevel
  of CICLevel.CIC0: config.detection.cic0_threshold
  of CICLevel.CIC1: config.detection.cic1_threshold
  of CICLevel.CIC2: config.detection.cic2_threshold
  of CICLevel.CIC3: config.detection.cic3_threshold
  of CICLevel.CIC4: config.detection.cic4_threshold
  of CICLevel.CIC5: config.detection.cic5_threshold

proc getCIPModifier*(cipPoints: int): int =
  ## Get detection modifier based on CIP points (from config)
  ## Per diplomacy.md:8.3
  let config = globalEspionageConfig
  if cipPoints == 0: config.detection.cip_0_modifier
  elif cipPoints <= 5: config.detection.cip_1_5_modifier
  elif cipPoints <= 10: config.detection.cip_6_10_modifier
  elif cipPoints <= 15: config.detection.cip_11_15_modifier
  elif cipPoints <= 20: config.detection.cip_16_20_modifier
  else: config.detection.cip_21_plus_modifier

proc initEspionageBudget*(): EspionageBudget =
  ## Initialize empty espionage budget
  result = EspionageBudget(
    ebpPoints: 0,
    cipPoints: 0,
    ebpInvested: 0,
    cipInvested: 0,
    turnBudget: 0
  )

proc calculateOverInvestmentPenalty*(invested: int, turnBudget: int): int =
  ## Calculate prestige penalty for over-investment
  ## Per diplomacy.md:8.2: -1 prestige per 1% over 5% threshold
  if turnBudget == 0:
    return 0

  let percentage = int((float(invested) / float(turnBudget)) * 100.0)
  if percentage <= INVESTMENT_THRESHOLD:
    return 0

  let excessPercentage = percentage - INVESTMENT_THRESHOLD
  return INVESTMENT_PENALTY * excessPercentage

## Detection System

proc attemptDetection*(attempt: DetectionAttempt, rng: var Rand): DetectionResult =
  ## Attempt to detect espionage action
  ## Per diplomacy.md:8.3

  # CIC0 = no counter-intelligence, auto-fail detection
  if attempt.cicLevel == CICLevel.CIC0:
    return DetectionResult(
      detected: false,
      roll: 0,
      threshold: 21,
      modifier: 0
    )

  # Get threshold and modifier
  let threshold = getDetectionThreshold(attempt.cicLevel)
  let modifier = getCIPModifier(attempt.cipPoints)

  # Roll d20
  let roll = rng.rand(1..20)

  # Check if detected (roll + modifier >= threshold)
  let detected = (roll + modifier) >= threshold

  return DetectionResult(
    detected: detected,
    roll: roll,
    threshold: threshold,
    modifier: modifier
  )

## Detection and execution now handled by executor.nim
## (All duplicate execute* functions eliminated - 448 lines removed!)

## Budget Management

proc purchaseEBP*(budget: var EspionageBudget, ppSpent: int): int =
  ## Purchase EBP with PP
  ## Returns number of EBP purchased
  let ebpPurchased = ppSpent div EBP_COST_PP
  budget.ebpPoints += ebpPurchased
  budget.ebpInvested += ppSpent
  return ebpPurchased

proc purchaseCIP*(budget: var EspionageBudget, ppSpent: int): int =
  ## Purchase CIP with PP
  ## Returns number of CIP purchased
  let cipPurchased = ppSpent div CIP_COST_PP
  budget.cipPoints += cipPurchased
  budget.cipInvested += ppSpent
  return cipPurchased

proc canAffordAction*(budget: EspionageBudget, action: EspionageAction): bool =
  ## Check if have enough EBP for action
  return budget.ebpPoints >= getActionCost(action)

proc spendEBP*(budget: var EspionageBudget, action: EspionageAction): bool =
  ## Spend EBP on action
  ## Returns true if successful
  let cost = getActionCost(action)
  if budget.ebpPoints >= cost:
    budget.ebpPoints -= cost
    return true
  return false

proc spendCIP*(budget: var EspionageBudget, amount: int = CIP_DEDUCTION_PER_ROLL): bool =
  ## Spend CIP on detection attempt
  ## Returns true if successful
  if budget.cipPoints >= amount:
    budget.cipPoints -= amount
    return true
  return false
