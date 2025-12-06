## Domestikos Consultation Logic - Requirements-Driven Budget Allocation
##
## This module adjusts budget allocation based on Domestikos's tactical requirements.
## Implements Strategic Triage when requirements exceed available budget.
##
## Design Philosophy:
## - Domestikos identifies WHAT is needed (requirements)
## - Treasurer determines HOW MUCH budget to allocate (percentages)
## - Consultation bridges strategic needs with fiscal reality

import std/[tables, strformat]
import ../../common/types
import ../../../engine/logger
import ../config
import ../controller_types  # For BuildRequirements type

proc calculateRequiredPP*(
  requirements: BuildRequirements
): Table[BuildObjective, int] =
  ## Sum estimated costs per objective across all non-Deferred requirements
  ##
  ## Includes Medium priority for SpecialUnits to support carriers/fighters.
  ## Critical/High priorities are urgent tactical needs (Defense/Military/Recon).
  ## Medium priorities are strategic investments (Carriers, Starbases).
  ## Low priorities are supporting assets (Fighters for carriers).

  result = initTable[BuildObjective, int]()

  # Initialize all objectives to zero
  for objective in BuildObjective:
    result[objective] = 0

  # Sum costs for Critical+High+Medium priorities
  # Exclude Low and Deferred to avoid over-allocating to non-urgent needs
  # This ensures budget consultation focuses on actionable requirements
  for req in requirements.requirements:
    if req.priority in {RequirementPriority.Critical, RequirementPriority.High, RequirementPriority.Medium}:
      result[req.buildObjective] += req.estimatedCost

  # Debug: Log what we calculated
  logDebug(LogCategory.lcAI,
           &"Calculated requiredPP: Defense={result[BuildObjective.Defense]}PP, " &
           &"Military={result[BuildObjective.Military]}PP, " &
           &"Recon={result[BuildObjective.Reconnaissance]}PP, " &
           &"SpecialUnits={result[BuildObjective.SpecialUnits]}PP")

proc applyStrategicTriage*(
  allocation: var BudgetAllocation,
  requirements: BuildRequirements,
  availableBudget: int
) =
  ## Priority-aware emergency allocation when requirements exceed budget
  ##
  ## Strategy: Allocate budget by priority level (Critical > High > Medium)
  ## Within each priority level, allocate proportionally to needs.
  ## Maintains minimum reserves for strategic awareness (expansion/recon).
  ##
  ## This ensures high-priority capital ships (Military) get budget before
  ## competing with high-priority defense needs (Defense) proportionally,
  ## rather than being starved by larger Defense cost totals.

  let cfg = globalRBAConfig.domestikos
  let minRecon = int(float(availableBudget) * cfg.min_recon_budget_percent)
  let minExpansion = int(float(availableBudget) * cfg.min_expansion_budget_percent)
  let minReserves = minRecon + minExpansion

  # Separate requirements by priority level
  var criticalReqs = initTable[BuildObjective, int]()
  var highReqs = initTable[BuildObjective, int]()
  var mediumReqs = initTable[BuildObjective, int]()

  for objective in BuildObjective:
    criticalReqs[objective] = 0
    highReqs[objective] = 0
    mediumReqs[objective] = 0

  for req in requirements.requirements:
    case req.priority
    of RequirementPriority.Critical:
      criticalReqs[req.buildObjective] += req.estimatedCost
    of RequirementPriority.High:
      highReqs[req.buildObjective] += req.estimatedCost
    of RequirementPriority.Medium:
      mediumReqs[req.buildObjective] += req.estimatedCost
    else:
      discard  # Skip Low and Deferred

  # Calculate total cost per priority level
  var totalCritical = 0
  var totalHigh = 0
  var totalMedium = 0
  for objective in BuildObjective:
    totalCritical += criticalReqs[objective]
    totalHigh += highReqs[objective]
    totalMedium += mediumReqs[objective]

  # Budget available after minimum reserves
  var budgetRemaining = availableBudget - minReserves

  # Allocate in priority order: Critical > High > Medium

  # 1. Critical requirements (highest priority - fund first)
  if totalCritical > 0 and budgetRemaining > 0:
    let criticalBudget = min(budgetRemaining, totalCritical)
    for objective in BuildObjective:
      if criticalReqs[objective] > 0:
        let ratio = float(criticalReqs[objective]) / float(totalCritical)
        let allocated = ratio * float(criticalBudget)
        allocation[objective] += allocated / float(availableBudget)
    budgetRemaining -= criticalBudget
    logDebug(LogCategory.lcAI,
             &"Strategic Triage Critical: {criticalBudget}/{totalCritical}PP allocated")

  # 2. High requirements (second priority - fund with remaining)
  if totalHigh > 0 and budgetRemaining > 0:
    let highBudget = min(budgetRemaining, totalHigh)
    for objective in BuildObjective:
      if highReqs[objective] > 0:
        let ratio = float(highReqs[objective]) / float(totalHigh)
        let allocated = ratio * float(highBudget)
        allocation[objective] += allocated / float(availableBudget)
    budgetRemaining -= highBudget
    logDebug(LogCategory.lcAI,
             &"Strategic Triage High: {highBudget}/{totalHigh}PP allocated " &
             &"(Defense={int(highReqs[BuildObjective.Defense])}PP, " &
             &"Military={int(highReqs[BuildObjective.Military])}PP)")

  # 3. Medium requirements (third priority - fund with leftovers)
  if totalMedium > 0 and budgetRemaining > 0:
    let mediumBudget = min(budgetRemaining, totalMedium)
    for objective in BuildObjective:
      if mediumReqs[objective] > 0:
        let ratio = float(mediumReqs[objective]) / float(totalMedium)
        let allocated = ratio * float(mediumBudget)
        allocation[objective] += allocated / float(availableBudget)
    budgetRemaining -= mediumBudget
    logDebug(LogCategory.lcAI,
             &"Strategic Triage Medium: {mediumBudget}/{totalMedium}PP allocated")

  # Guarantee minimum reserves
  allocation[BuildObjective.Expansion] = max(allocation[BuildObjective.Expansion], float(minExpansion) / float(availableBudget))
  allocation[BuildObjective.Reconnaissance] = max(allocation[BuildObjective.Reconnaissance], float(minRecon) / float(availableBudget))

  # Remaining budget to Technology
  let remainingPercent = 1.0 - (allocation[BuildObjective.Defense] + allocation[BuildObjective.Military] +
                                allocation[BuildObjective.Reconnaissance] + allocation[BuildObjective.Expansion] +
                                allocation[BuildObjective.SpecialUnits])
  allocation[BuildObjective.Technology] = remainingPercent

  let totalUrgent = totalCritical + totalHigh + totalMedium
  logInfo(LogCategory.lcAI,
          &"Strategic Triage (Priority-Aware): Total={totalUrgent}PP (Critical={totalCritical}, High={totalHigh}, Medium={totalMedium}), " &
          &"budget={availableBudget}PP. Allocated: Defense={int(allocation[BuildObjective.Defense]*100)}%, " &
          &"Military={int(allocation[BuildObjective.Military]*100)}%, Recon={int(allocation[BuildObjective.Reconnaissance]*100)}%, " &
          &"Special={int(allocation[BuildObjective.SpecialUnits]*100)}%")

proc blendRequirementsWithBaseline*(
  allocation: var BudgetAllocation,
  requiredPP: Table[BuildObjective, int],
  availableBudget: int
) =
  ## Normal case: Allocate based on Domestikos tactical requirements
  ##
  ## Strategy: 100% tactical for Defense/Military (urgent needs), blend others
  ## Defense and Military are immediate tactical needs - allocate exactly what's requested.
  ## Reconnaissance and SpecialUnits blend 70/30 to maintain strategic balance.
  ##
  ## Example:
  ## - Domestikos needs 160PP Defense (53% of 300PP budget)
  ## - Allocate exactly 53% to Defense (100% of requirement)
  ## - SpecialUnits: blend 70% requirement + 30% baseline

  let cfg = globalRBAConfig.domestikos

  # Defense and Military: 100% requirements-driven (pure tactical allocation)
  for objective in [BuildObjective.Defense, BuildObjective.Military]:
    if requiredPP[objective] > 0:
      let targetPercent = float(requiredPP[objective]) / float(availableBudget)
      allocation[objective] = min(targetPercent, 0.85)  # Cap at 85% to leave room for other objectives

  # Reconnaissance and SpecialUnits: Blend 70/30 (strategic flexibility)
  for objective in [BuildObjective.Reconnaissance, BuildObjective.SpecialUnits]:
    if requiredPP[objective] > 0:
      let targetPercent = float(requiredPP[objective]) / float(availableBudget)
      let oldPercent = allocation[objective]
      # Blend: 70% requirement-driven, 30% baseline
      allocation[objective] = (targetPercent * 0.7) + (allocation[objective] * 0.3)

      if objective == BuildObjective.SpecialUnits:
        logDebug(LogCategory.lcAI,
                 &"SpecialUnits blend: required={requiredPP[objective]}PP, " &
                 &"targetPercent={int(targetPercent*100)}%, baseline={int(oldPercent*100)}%, " &
                 &"blended={int(allocation[objective]*100)}%")

  # Ensure minimum reserves for expansion (never below 5%)
  allocation[BuildObjective.Expansion] = max(allocation[BuildObjective.Expansion], cfg.min_expansion_budget_percent)

  logInfo(LogCategory.lcAI,
           &"Tactical Budget Allocation: Defense={int(allocation[BuildObjective.Defense]*100)}% ({requiredPP[BuildObjective.Defense]}PP requested), " &
           &"Military={int(allocation[BuildObjective.Military]*100)}% ({requiredPP[BuildObjective.Military]}PP requested), " &
           &"Recon={int(allocation[BuildObjective.Reconnaissance]*100)}%, " &
           &"SpecialUnits={int(allocation[BuildObjective.SpecialUnits]*100)}%")

proc consultDomestikosRequirements*(
  allocation: var BudgetAllocation,
  requirements: BuildRequirements,
  availableBudget: int
) =
  ## Main entry point: Adjust allocation based on Domestikos's requirements
  ##
  ## Implements two strategies:
  ## 1. Strategic Triage: When urgent requirements exceed budget
  ## 2. Requirements Blending: When budget sufficient for urgent needs

  # Calculate PP needed per objective
  let requiredPP = calculateRequiredPP(requirements)

  # Sum urgent objectives: Defense + Military + Recon + SpecialUnits
  # SpecialUnits included because Medium-priority carriers are strategic investments
  let totalUrgent = requiredPP[BuildObjective.Defense] + requiredPP[BuildObjective.Military] +
                    requiredPP[BuildObjective.Reconnaissance] + requiredPP[BuildObjective.SpecialUnits]

  # Decide strategy based on budget availability
  if totalUrgent > availableBudget:
    # Strategic Triage: Oversubscribed - use priority-aware allocation
    applyStrategicTriage(allocation, requirements, availableBudget)
  else:
    # Normal case: Blend requirements with baseline
    blendRequirementsWithBaseline(allocation, requiredPP, availableBudget)
