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
import types, action_descriptors, executor

export types, action_descriptors, executor

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
