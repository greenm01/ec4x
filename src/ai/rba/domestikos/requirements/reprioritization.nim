## Domestikos Reprioritization Module (Gap 4 Enhanced)
##
## Budget-aware requirement reprioritization logic with smart adjustments.
## Following DoD (Data-Oriented Design): Pure functions operating on requirements.
##
## Extracted from build_requirements.nim (lines 1896-2023)
## Enhanced in Phase 2.4 with:
## - Quantity adjustment (Iteration 1)
## - Substitution logic (Iteration 2-3)
## - Cost-benefit analysis

import std/[sequtils, algorithm, strformat, options]
import ../../../../common/types/units
import ../../../../engine/[logger, gamestate]
import ../../../../engine/economy/config_accessors
import ../../controller_types  # For BuildRequirements, TreasurerFeedback
import ../../config
import ../../treasurer/budget/feedback  # For getCheaperAlternatives()

# =============================================================================
# Smart Adjustment Strategies (Gap 4)
# =============================================================================

proc tryQuantityAdjustment*(
  controller: AIController,
  req: BuildRequirement,
  iteration: int
): BuildRequirement =
  ## Try to make requirement affordable by reducing quantity
  ## Strategy: Reduce by 50% on first attempt (min 1)
  ##
  ## Used in Iteration 1 before trying substitution

  if not controller.rbaConfig.reprioritization.enable_quantity_adjustment:
    return req

  if req.quantity <= 1:
    # Can't reduce further
    return req

  var adjusted = req
  let minReduction = controller.rbaConfig.reprioritization.min_quantity_reduction
  let newQuantity = max(minReduction, req.quantity div 2)  # 50% reduction

  if newQuantity < req.quantity:
    adjusted.quantity = newQuantity
    adjusted.estimatedCost = req.estimatedCost div 2  # Approximate cost reduction

    logInfo(LogCategory.lcAI,
            &"Quantity adjustment: '{req.reason}' reduced from " &
            &"{req.quantity} to {newQuantity} units " &
            &"({req.estimatedCost}PP → {adjusted.estimatedCost}PP)")

  return adjusted

proc trySubstitution*(
  controller: AIController,
  req: BuildRequirement,
  cstLevel: int
): Option[BuildRequirement] =
  ## Try to substitute with cheaper alternative ship class
  ## Only substitutes if cost reduction ≥ 40% (factor 0.6)
  ##
  ## Used in Iterations 2-3 after quantity adjustment failed

  if not controller.rbaConfig.reprioritization.enable_substitution:
    return none(BuildRequirement)

  # Only substitute ships (ground units don't have good alternatives yet)
  if req.shipClass.isNone:
    return none(BuildRequirement)

  let originalShip = req.shipClass.get()
  let originalCost = getShipConstructionCost(originalShip)

  # Find cheaper alternatives
  let alternatives = getCheaperAlternatives(originalShip, cstLevel)

  if alternatives.len == 0:
    return none(BuildRequirement)

  # Check cost reduction factor from config
  let maxCostReductionFactor = controller.rbaConfig.reprioritization
                                 .max_cost_reduction_factor

  # Find cheapest alternative that meets cost reduction threshold
  for altShip in alternatives:
    let altCost = getShipConstructionCost(altShip)
    let costRatio = float(altCost) / float(originalCost)

    if costRatio <= maxCostReductionFactor:
      # Found suitable substitute
      var substituted = req
      substituted.shipClass = some(altShip)
      substituted.estimatedCost = altCost * req.quantity

      let savings = (originalCost - altCost) * req.quantity
      let savingsPct = int((1.0 - costRatio) * 100.0)

      logInfo(LogCategory.lcAI,
              &"Substitution: '{req.reason}' changed from " &
              &"{originalShip} to {altShip} " &
              &"({originalCost}PP → {altCost}PP per unit, " &
              &"{savingsPct}% cheaper, saves {savings}PP total)")

      return some(substituted)

  # No suitable substitute found
  return none(BuildRequirement)

# =============================================================================
# Main Reprioritization Logic
# =============================================================================

proc reprioritizeRequirements*(
  controller: AIController,
  originalRequirements: BuildRequirements,
  treasurerFeedback: TreasurerFeedback,
  treasury: int,  # Treasury for budget-aware reprioritization
  cstLevel: int   # CST level for substitution logic
): BuildRequirements =
  ## Domestikos reprioritizes requirements based on Treasurer feedback
  ##
  ## Enhanced Strategy (Gap 4):
  ## 1. Iteration 1: Try quantity adjustment (reduce by 50%)
  ## 2. Iteration 2-3: Try substitution (cheaper alternatives)
  ## 3. All iterations: Downgrade priorities based on cost-effectiveness
  ##
  ## Downgrading logic:
  ## - Aggressive downgrade for very expensive requests (>50% treasury)
  ## - Moderate downgrade for expensive requests (25-50% treasury)
  ## - Normal downgrade for affordable requests (<25% treasury)

  const MAX_ITERATIONS = 3  # Prevent infinite loops

  if originalRequirements.iteration >= MAX_ITERATIONS:
    logWarn(LogCategory.lcAI,
            &"Domestikos reprioritization limit reached " &
            &"({MAX_ITERATIONS} iterations). " &
            &"Accepting unfulfilled requirements.")
    return originalRequirements

  # If everything was fulfilled OR nothing was unfulfilled, no need
  if treasurerFeedback.unfulfilledRequirements.len == 0:
    return originalRequirements

  let currentIteration = originalRequirements.iteration + 1

  logInfo(LogCategory.lcAI,
          &"Domestikos reprioritizing " &
          &"{treasurerFeedback.unfulfilledRequirements.len} unfulfilled " &
          &"requirements (iteration {currentIteration}, " &
          &"shortfall: {treasurerFeedback.totalUnfulfilledCost}PP, " &
          &"treasury={treasury}PP)")

  # Strategy: Downgrade priorities based on cost-effectiveness
  var reprioritized: seq[BuildRequirement] = @[]

  # Add all fulfilled requirements (these were already affordable)
  reprioritized.add(treasurerFeedback.fulfilledRequirements)

  # Gap 4 Enhancement: Try smart adjustments before downgrading
  var adjustedUnfulfilled: seq[BuildRequirement] = @[]

  for req in treasurerFeedback.unfulfilledRequirements:
    var adjustedReq = req

    # Iteration 1: Try quantity adjustment
    if currentIteration == 1 and req.quantity > 1:
      adjustedReq = tryQuantityAdjustment(controller, req, currentIteration)

    # Iteration 2-3: Try substitution if quantity adjustment didn't help
    elif currentIteration >= 2:
      let substitutionResult = trySubstitution(controller, adjustedReq, cstLevel)
      if substitutionResult.isSome:
        adjustedReq = substitutionResult.get()
      # else: keep existing requirement, will be downgraded below

    adjustedUnfulfilled.add(adjustedReq)

  # Reprioritize adjusted unfulfilled requirements with cost-awareness
  for req in adjustedUnfulfilled:
    var adjustedReq = req

    # Calculate cost-effectiveness ratio
    let costRatio = if treasury > 0:
                      float(req.estimatedCost) / float(treasury)
                    else:
                      1.0

    # BUDGET-AWARE: Aggressive downgrade for VERY expensive unfulfilled
    # requests (>50% treasury)
    if costRatio > 0.5:
      case req.priority
      of RequirementPriority.Critical:
        adjustedReq.priority = RequirementPriority.High  # Critical → High
      of RequirementPriority.High:
        adjustedReq.priority = RequirementPriority.Low  # High → Low (skip Medium)
      of RequirementPriority.Medium:
        adjustedReq.priority = RequirementPriority.Deferred  # Medium → Deferred
      else:
        adjustedReq.priority = RequirementPriority.Deferred

      logDebug(LogCategory.lcAI,
               &"Domestikos: '{req.reason}' too expensive " &
               &"({req.estimatedCost}PP = " &
               &"{int(costRatio*100)}% of treasury), aggressive downgrade " &
               &"{req.priority} → {adjustedReq.priority}")

    # BUDGET-AWARE: Moderate downgrade for expensive requests (25-50% treasury)
    elif costRatio > 0.25:
      case req.priority
      of RequirementPriority.Critical:
        adjustedReq.priority = RequirementPriority.High  # Critical → High
      of RequirementPriority.High:
        adjustedReq.priority = RequirementPriority.Medium  # High → Medium
      of RequirementPriority.Medium:
        adjustedReq.priority = RequirementPriority.Low  # Medium → Low
      of RequirementPriority.Low:
        adjustedReq.priority = RequirementPriority.Deferred  # Low → Deferred
      else:
        adjustedReq.priority = RequirementPriority.Deferred

      logDebug(LogCategory.lcAI,
               &"Domestikos: '{req.reason}' expensive " &
               &"({req.estimatedCost}PP = " &
               &"{int(costRatio*100)}% of treasury), moderate downgrade " &
               &"{req.priority} → {adjustedReq.priority}")

    # Normal downgrade for affordable units (<25% treasury)
    else:
      case req.priority
      of RequirementPriority.Critical:
        # Keep Critical as-is (absolute essentials)
        adjustedReq.priority = RequirementPriority.Critical
      of RequirementPriority.High:
        # Downgrade High → Medium (important but not critical)
        adjustedReq.priority = RequirementPriority.Medium
        logDebug(LogCategory.lcAI,
                 &"Domestikos: Downgrading '{req.reason}' (High → Medium)")
      of RequirementPriority.Medium:
        # Downgrade Medium → Low (nice-to-have)
        adjustedReq.priority = RequirementPriority.Low
        logDebug(LogCategory.lcAI,
                 &"Domestikos: Downgrading '{req.reason}' (Medium → Low)")
      of RequirementPriority.Low:
        # Downgrade Low → Deferred (skip this round)
        adjustedReq.priority = RequirementPriority.Deferred
        logDebug(LogCategory.lcAI,
                 &"Domestikos: Deferring '{req.reason}' (Low → Deferred)")
      of RequirementPriority.Deferred:
        # Already deferred, keep as deferred
        adjustedReq.priority = RequirementPriority.Deferred

    reprioritized.add(adjustedReq)

  # Re-sort by new priorities
  # CRITICAL FIX: Same logic as generateBuildRequirements
  # Lower ord() = higher priority
  reprioritized.sort(proc(a, b: BuildRequirement): int =
    if a.priority > b.priority: 1  # Higher ord (Low=3) comes AFTER
    elif a.priority < b.priority: -1  # Lower ord (Critical=0) comes FIRST
    else: 0
  )

  result = BuildRequirements(
    requirements: reprioritized,
    totalEstimatedCost: reprioritized.mapIt(it.estimatedCost).foldl(a + b, 0),
    criticalCount: reprioritized.countIt(
      it.priority == RequirementPriority.Critical),
    highCount: reprioritized.countIt(it.priority == RequirementPriority.High),
    generatedTurn: originalRequirements.generatedTurn,
    act: originalRequirements.act,
    iteration: originalRequirements.iteration + 1
  )

  logInfo(LogCategory.lcAI,
          &"Domestikos reprioritized requirements: " &
          &"{result.requirements.len} total " &
          &"(Critical={result.criticalCount}, High={result.highCount}, " &
          &"iteration={result.iteration})")
