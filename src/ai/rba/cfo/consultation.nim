## Admiral Consultation Logic - Requirements-Driven Budget Allocation
##
## This module adjusts budget allocation based on Admiral's tactical requirements.
## Implements Strategic Triage when requirements exceed available budget.
##
## Design Philosophy:
## - Admiral identifies WHAT is needed (requirements)
## - CFO determines HOW MUCH budget to allocate (percentages)
## - Consultation bridges strategic needs with fiscal reality

import std/[tables, strformat, sequtils]
import ../../common/types
import ../../../engine/logger
import ../config
import ../controller_types  # For BuildRequirements type

proc calculateRequiredPP*(
  requirements: BuildRequirements
): Table[BuildObjective, int] =
  ## Sum estimated costs per objective for Critical+High priority requirements
  ##
  ## Only considers urgent requirements (Critical+High) since lower priorities
  ## can be deferred if budget is tight.

  result = initTable[BuildObjective, int]()

  # Initialize all objectives to zero
  for objective in BuildObjective:
    result[objective] = 0

  # Sum costs for urgent requirements
  for req in requirements.requirements:
    if req.priority in {RequirementPriority.Critical, RequirementPriority.High}:
      result[req.buildObjective] += req.estimatedCost

proc applyStrategicTriage*(
  allocation: var BudgetAllocation,
  requiredPP: Table[BuildObjective, int],
  availableBudget: int
) =
  ## Emergency allocation when urgent requirements exceed available budget
  ##
  ## Strategy: Allocate to urgent needs while maintaining minimum reserves
  ## for strategic awareness (recon + expansion).
  ##
  ## This prevents strategic blindness where AI builds only defenders
  ## but can't see threats or expand economy.

  let cfg = globalRBAConfig.admiral
  let minRecon = int(float(availableBudget) * cfg.min_recon_budget_percent)
  let minExpansion = int(float(availableBudget) * cfg.min_expansion_budget_percent)
  let minReserves = minRecon + minExpansion

  # Calculate budget available for urgent requirements after reserves
  let budgetForUrgent = availableBudget - minReserves

  # Total urgent PP requested
  let totalUrgent = requiredPP[BuildObjective.Defense] + requiredPP[BuildObjective.Military] + requiredPP[BuildObjective.Reconnaissance]

  if totalUrgent > 0:
    # Allocate proportionally to urgent needs
    let defenseRatio = float(requiredPP[BuildObjective.Defense]) / float(totalUrgent)
    let militaryRatio = float(requiredPP[BuildObjective.Military]) / float(totalUrgent)
    let reconRatio = float(requiredPP[BuildObjective.Reconnaissance]) / float(totalUrgent)

    allocation[BuildObjective.Defense] = (defenseRatio * float(budgetForUrgent) + 0.0) / float(availableBudget)
    allocation[BuildObjective.Military] = (militaryRatio * float(budgetForUrgent) + 0.0) / float(availableBudget)

    # Recon gets larger of: proportional urgent OR minimum reserve
    let reconFromUrgent = reconRatio * float(budgetForUrgent)
    allocation[BuildObjective.Reconnaissance] = max(reconFromUrgent, float(minRecon)) / float(availableBudget)
  else:
    # No urgent requirements - use minimum for Defense/Military
    allocation[BuildObjective.Defense] = 0.10  # Maintain small reserve
    allocation[BuildObjective.Military] = 0.10
    allocation[BuildObjective.Reconnaissance] = float(minRecon) / float(availableBudget)

  # Guarantee minimum reserves
  allocation[BuildObjective.Expansion] = max(allocation[BuildObjective.Expansion], float(minExpansion) / float(availableBudget))

  # Remaining budget to SpecialUnits and Technology
  let remainingPercent = 1.0 - (allocation[BuildObjective.Defense] + allocation[BuildObjective.Military] +
                                allocation[BuildObjective.Reconnaissance] + allocation[BuildObjective.Expansion])
  allocation[BuildObjective.SpecialUnits] = remainingPercent * 0.6  # 60% of remainder
  allocation[BuildObjective.Technology] = remainingPercent * 0.4    # 40% of remainder

  logInfo(LogCategory.lcAI,
          &"Strategic Triage: Total urgent={totalUrgent}PP, budget={availableBudget}PP. " &
          &"Defense={int(allocation[BuildObjective.Defense]*100)}%, Military={int(allocation[BuildObjective.Military]*100)}%, " &
          &"Recon={int(allocation[BuildObjective.Reconnaissance]*100)}% (min reserves: {minRecon}PP recon, {minExpansion}PP expansion)")

proc blendRequirementsWithBaseline*(
  allocation: var BudgetAllocation,
  requiredPP: Table[BuildObjective, int],
  availableBudget: int
) =
  ## Normal case: Blend Admiral requirements with baseline config allocation
  ##
  ## Strategy: 70% driven by requirements, 30% by baseline config
  ## This maintains strategic diversity while fulfilling tactical needs.
  ##
  ## Example:
  ## - Admiral needs 160PP Defense (53% of 300PP budget)
  ## - Baseline config says 15% Defense
  ## - Blended result: (53% * 0.7) + (15% * 0.3) = 37% + 4.5% = 41.5% Defense

  let cfg = globalRBAConfig.admiral

  # Adjust Defense, Military, Reconnaissance based on requirements
  for objective in [BuildObjective.Defense, BuildObjective.Military, BuildObjective.Reconnaissance]:
    if requiredPP[objective] > 0:
      let targetPercent = float(requiredPP[objective]) / float(availableBudget)
      # Blend: 70% requirement-driven, 30% baseline
      allocation[objective] = (targetPercent * 0.7) + (allocation[objective] * 0.3)

  # Ensure minimum reserves for expansion (never below 5%)
  allocation[BuildObjective.Expansion] = max(allocation[BuildObjective.Expansion], cfg.min_expansion_budget_percent)

  logDebug(LogCategory.lcAI,
           &"Requirements Blend: Defense={int(allocation[BuildObjective.Defense]*100)}%, " &
           &"Military={int(allocation[BuildObjective.Military]*100)}%, Recon={int(allocation[BuildObjective.Reconnaissance]*100)}%")

proc consultAdmiralRequirements*(
  allocation: var BudgetAllocation,
  requirements: BuildRequirements,
  availableBudget: int
) =
  ## Main entry point: Adjust allocation based on Admiral's requirements
  ##
  ## Implements two strategies:
  ## 1. Strategic Triage: When urgent requirements exceed budget
  ## 2. Requirements Blending: When budget sufficient for urgent needs

  # Calculate PP needed per objective
  let requiredPP = calculateRequiredPP(requirements)

  # Sum only Defense, Military, Reconnaissance (the urgent objectives)
  let totalUrgent = requiredPP[BuildObjective.Defense] + requiredPP[BuildObjective.Military] + requiredPP[BuildObjective.Reconnaissance]

  # Decide strategy based on budget availability
  if totalUrgent > availableBudget:
    # Strategic Triage: Oversubscribed
    applyStrategicTriage(allocation, requiredPP, availableBudget)
  else:
    # Normal case: Blend requirements with baseline
    blendRequirementsWithBaseline(allocation, requiredPP, availableBudget)
