## Phase 2: Basileus Mediation & Budget Allocation
##
## Basileus mediates competing priorities, Treasurer allocates budgets

import std/[strformat, options]
import ../../../common/types/core
import ../../../engine/[gamestate, fog_of_war, logger]
import ../controller_types
import ../../common/types as ai_types
import ../treasurer/multi_advisor
import ./utils

proc mediateAndAllocateBudget*(
  controller: var AIController,
  filtered: FilteredGameState,
  currentAct: ai_types.GameAct
): MultiAdvisorAllocation =
  ## Phase 2: Basileus mediation and Treasurer budget allocation
  ## Returns per-advisor budgets and feedback

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} === Phase 2: Basileus Mediation & Allocation ===")

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
    filtered  # NEW: for war status detection
  )

  # Store feedback in controller for feedback loop
  controller.treasurerFeedback = some(result.treasurerFeedback)
  controller.scienceFeedback = some(result.scienceFeedback)
  controller.drungariusFeedback = some(result.drungariusFeedback)
  controller.eparchFeedback = some(result.eparchFeedback)

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Phase 2 complete: Budgets allocated across all advisors")

  return result
