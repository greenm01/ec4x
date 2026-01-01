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
import ../../types/espionage
import ../../globals
import action_descriptors, executor

export espionage, action_descriptors, executor

## Detection System

proc attemptDetection*(attempt: DetectionAttempt, rng: var Rand): DetectionResult =
  ## Attempt to detect espionage action
  ## Per diplomacy.md:8.3

  # CIC0 = no counter-intelligence, auto-fail detection
  if attempt.cicLevel == CICLevel.CIC0:
    return DetectionResult(detected: false, roll: 0, threshold: 21, modifier: 0)

  # Get threshold and modifier
  let threshold = getDetectionThreshold(attempt.cicLevel)
  let modifier = getCIPModifier(attempt.cipPoints)

  # Roll d20
  let roll = rng.rand(1 .. 20)

  # Check if detected (roll + modifier >= threshold)
  let detected = (roll + modifier) >= threshold

  return DetectionResult(
    detected: detected,
    roll: int32(roll),
    threshold: int32(threshold),
    modifier: int32(modifier),
  )

## Detection and execution now handled by executor.nim
## (All duplicate execute* functions eliminated - 448 lines removed!)

## Action Cost Lookup

proc getActionCost*(action: EspionageAction): int =
  ## Get EBP cost for action from config
  let config = gameConfig.espionage.costs
  case action
  of EspionageAction.TechTheft: config.techTheftEbp
  of EspionageAction.SabotageLow: config.sabotageLowEbp
  of EspionageAction.SabotageHigh: config.sabotageHighEbp
  of EspionageAction.Assassination: config.assassinationEbp
  of EspionageAction.CyberAttack: config.cyberAttackEbp
  of EspionageAction.EconomicManipulation: config.economicManipulationEbp
  of EspionageAction.PsyopsCampaign: config.psyopsCampaignEbp
  of EspionageAction.CounterIntelSweep: config.counterIntelSweepEbp
  of EspionageAction.IntelligenceTheft: config.intelligenceTheftEbp
  of EspionageAction.PlantDisinformation: config.plantDisinformationEbp

## Budget Management

proc purchaseEBP*(budget: var EspionageBudget, ppSpent: int): int =
  ## Purchase EBP with PP from config
  ## Returns number of EBP purchased
  let ebpPurchased = ppSpent div gameConfig.espionage.costs.ebpCostPp
  budget.ebpPoints += int32(ebpPurchased)
  budget.ebpInvested += int32(ppSpent)
  return ebpPurchased

proc purchaseCIP*(budget: var EspionageBudget, ppSpent: int): int =
  ## Purchase CIP with PP from config
  ## Returns number of CIP purchased
  let cipPurchased = ppSpent div gameConfig.espionage.costs.cipCostPp
  budget.cipPoints += int32(cipPurchased)
  budget.cipInvested += int32(ppSpent)
  return cipPurchased

proc canAffordAction*(budget: EspionageBudget, action: EspionageAction): bool =
  ## Check if have enough EBP for action
  return budget.ebpPoints >= int32(getActionCost(action))

proc spendEBP*(budget: var EspionageBudget, action: EspionageAction): bool =
  ## Spend EBP on action
  ## Returns true if successful
  let cost = getActionCost(action)
  if budget.ebpPoints >= int32(cost):
    budget.ebpPoints -= int32(cost)
    return true
  return false

proc spendCIP*(budget: var EspionageBudget, amount: int = 0): bool =
  ## Spend CIP on detection attempt (uses config default if amount=0)
  ## Returns true if successful
  let actualAmount =
    if amount == 0: int(gameConfig.espionage.detection.cipPerRoll) else: amount
  if budget.cipPoints >= int32(actualAmount):
    budget.cipPoints -= int32(actualAmount)
    return true
  return false
