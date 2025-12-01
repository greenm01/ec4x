## Domestikos Consultation Logic - Requirements-Driven Budget Allocation
##
## This module adjusts budget allocation based on Domestikos's tactical requirements.
## Implements Strategic Triage when requirements exceed available budget.
##
## Design Philosophy:
## - Domestikos identifies WHAT is needed (requirements)
## - Treasurer determines HOW MUCH budget to allocate (percentages)
## - Consultation bridges strategic needs with fiscal reality

import std/[tables, strformat, sequtils]
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
  requiredPP: Table[BuildObjective, int],
  availableBudget: int
) =
  ## Emergency allocation when urgent requirements exceed available budget
  ##
  ## Strategy: Allocate to urgent needs (Defense/Military/Recon/SpecialUnits)
  ## while maintaining minimum reserves for strategic awareness (expansion).
  ##
  ## SpecialUnits (carriers, starbases) are included as urgent because they're
  ## strategic force multipliers that Domestikos prioritized at Medium priority.
  ## Without this, feedback loop downgrades them indefinitely.

  let cfg = globalRBAConfig.domestikos
  let minRecon = int(float(availableBudget) * cfg.min_recon_budget_percent)
  let minExpansion = int(float(availableBudget) * cfg.min_expansion_budget_percent)
  let minReserves = minRecon + minExpansion

  # Calculate budget available for urgent requirements after reserves
  let budgetForUrgent = availableBudget - minReserves

  # Total urgent PP requested: Defense + Military + Recon + SpecialUnits
  # SpecialUnits included because Medium-priority carriers are strategic investments
  let totalUrgent = requiredPP[BuildObjective.Defense] + requiredPP[BuildObjective.Military] +
                    requiredPP[BuildObjective.Reconnaissance] + requiredPP[BuildObjective.SpecialUnits]

  if totalUrgent > 0:
    # Allocate proportionally to urgent needs
    let defenseRatio = float(requiredPP[BuildObjective.Defense]) / float(totalUrgent)
    let militaryRatio = float(requiredPP[BuildObjective.Military]) / float(totalUrgent)
    let reconRatio = float(requiredPP[BuildObjective.Reconnaissance]) / float(totalUrgent)
    let specialRatio = float(requiredPP[BuildObjective.SpecialUnits]) / float(totalUrgent)

    allocation[BuildObjective.Defense] = (defenseRatio * float(budgetForUrgent)) / float(availableBudget)
    allocation[BuildObjective.Military] = (militaryRatio * float(budgetForUrgent)) / float(availableBudget)
    allocation[BuildObjective.SpecialUnits] = (specialRatio * float(budgetForUrgent)) / float(availableBudget)

    # Recon gets larger of: proportional urgent OR minimum reserve
    let reconFromUrgent = reconRatio * float(budgetForUrgent)
    allocation[BuildObjective.Reconnaissance] = max(reconFromUrgent, float(minRecon)) / float(availableBudget)
  else:
    # No urgent requirements - use minimum for Defense/Military
    allocation[BuildObjective.Defense] = 0.10  # Maintain small reserve
    allocation[BuildObjective.Military] = 0.10
    allocation[BuildObjective.Reconnaissance] = float(minRecon) / float(availableBudget)
    allocation[BuildObjective.SpecialUnits] = 0.05  # Small reserve for strategic assets

  # Guarantee minimum reserves
  allocation[BuildObjective.Expansion] = max(allocation[BuildObjective.Expansion], float(minExpansion) / float(availableBudget))

  # Remaining budget to Technology
  let remainingPercent = 1.0 - (allocation[BuildObjective.Defense] + allocation[BuildObjective.Military] +
                                allocation[BuildObjective.Reconnaissance] + allocation[BuildObjective.Expansion] +
                                allocation[BuildObjective.SpecialUnits])
  allocation[BuildObjective.Technology] = remainingPercent

  logInfo(LogCategory.lcAI,
          &"Strategic Triage: Total urgent={totalUrgent}PP (Defense={requiredPP[BuildObjective.Defense]}, " &
          &"Military={requiredPP[BuildObjective.Military]}, Recon={requiredPP[BuildObjective.Reconnaissance]}, " &
          &"Special={requiredPP[BuildObjective.SpecialUnits]}), budget={availableBudget}PP. " &
          &"Allocated: Defense={int(allocation[BuildObjective.Defense]*100)}%, Military={int(allocation[BuildObjective.Military]*100)}%, " &
          &"Recon={int(allocation[BuildObjective.Reconnaissance]*100)}%, Special={int(allocation[BuildObjective.SpecialUnits]*100)}%")

proc blendRequirementsWithBaseline*(
  allocation: var BudgetAllocation,
  requiredPP: Table[BuildObjective, int],
  availableBudget: int
) =
  ## Normal case: Blend Domestikos requirements with baseline config allocation
  ##
  ## Strategy: 70% driven by requirements, 30% by baseline config
  ## This maintains strategic diversity while fulfilling tactical needs.
  ##
  ## Example:
  ## - Domestikos needs 160PP Defense (53% of 300PP budget)
  ## - Baseline config says 15% Defense
  ## - Blended result: (53% * 0.7) + (15% * 0.3) = 37% + 4.5% = 41.5% Defense

  let cfg = globalRBAConfig.domestikos

  # Adjust Defense, Military, Reconnaissance, SpecialUnits based on requirements
  for objective in [BuildObjective.Defense, BuildObjective.Military, BuildObjective.Reconnaissance, BuildObjective.SpecialUnits]:
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

  logDebug(LogCategory.lcAI,
           &"Requirements Blend: Defense={int(allocation[BuildObjective.Defense]*100)}%, " &
           &"Military={int(allocation[BuildObjective.Military]*100)}%, Recon={int(allocation[BuildObjective.Reconnaissance]*100)}%, " &
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
    # Strategic Triage: Oversubscribed
    applyStrategicTriage(allocation, requiredPP, availableBudget)
  else:
    # Normal case: Blend requirements with baseline
    blendRequirementsWithBaseline(allocation, requiredPP, availableBudget)
