## Phase 2: Basileus Mediation & Budget Allocation
##
## Basileus mediates competing priorities, Treasurer allocates budgets

import std/[strformat, options, strutils, tables]
import ../../../engine/[fog_of_war, logger]
import ../controller_types
import ../../common/types as ai_types
import ../treasurer/multi_advisor
import ./utils

proc mediateAndAllocateBudget*(
  controller: var AIController,
  filtered: FilteredGameState,
  currentAct: ai_types.GameAct
  # goapBudgetEstimates: Option[Table[DomainType, int]] = none(Table[DomainType, int])  # GOAP not yet integrated
): MultiAdvisorAllocation =
  ## Phase 2: Basileus mediation and Treasurer budget allocation
  ## Returns per-advisor budgets and feedback
  ##
  ## GOAP Phase 4 Enhancement:
  ## - Uses GOAP strategic cost estimates to inform budget allocation
  ## - Prioritizes requirements that align with active GOAP plans

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} === Phase 2: Basileus Mediation & Allocation ===")

  # GOAP Phase 4: Log active strategic goals (GOAP not yet integrated)
  # if controller.goapEnabled and controller.goapActiveGoals.len > 0:
  #   logInfo(LogCategory.lcAI,
  #           &"{controller.houseId} Active GOAP goals ({controller.goapActiveGoals.len}): " &
  #           controller.goapActiveGoals[0..min(2, controller.goapActiveGoals.len-1)].join(", "))

  # Calculate available budget (projected treasury)
  let projectedTreasury = calculateProjectedTreasury(filtered)

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Projected treasury: {projectedTreasury}PP")

  # Multi-advisor allocation (hybrid: reserves + mediation)
  result = allocateBudgetMultiAdvisor(
    controller.domestikosRequirements.get(),
    controller.logotheteRequirements.get(),
    controller.drungariusRequirements.get(),
    controller.eparchRequirements.get(),
    controller.protostratorRequirements.get(),
    controller.personality,
    currentAct,
    projectedTreasury,
    controller.houseId,
    filtered  # For war status detection
    # goapBudgetEstimates omitted - GOAP not yet integrated, will use default
  )

  # Store feedback in controller for feedback loop
  controller.treasurerFeedback = some(result.treasurerFeedback)
  controller.scienceFeedback = some(result.scienceFeedback)
  controller.drungariusFeedback = some(result.drungariusFeedback)
  controller.eparchFeedback = some(result.eparchFeedback)

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Phase 2 complete: Budgets allocated across all advisors")

  return result
