## Phase 3: Requirement Execution
##
## Execute advisor requirements using allocated budgets

import std/[strformat, options, random, tables]
import ../../../engine/[fog_of_war, logger, orders]
import ../../../engine/research/types as res_types
import ../../../engine/espionage/types as esp_types
import ../controller_types
import ../treasurer/multi_advisor
import ../logothete/allocation
import ../drungarius
import ../eparch
import ../basileus/execution as basileus_exec

proc executeResearchAllocation*(
  controller: AIController,
  filtered: FilteredGameState,
  allocation: MultiAdvisorAllocation
): res_types.ResearchAllocation =
  ## Execute Logothete research requirements with allocated budget

  let researchBudget = allocation.budgets.getOrDefault(controller_types.AdvisorType.Logothete, 0)

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Executing research allocation " &
          &"(budget={researchBudget}PP)")

  # Use Logothete allocation module
  result = allocateResearch(
    controller,
    filtered,
    researchBudget
  )

  return result

proc executeEspionageAction*(
  controller: AIController,
  filtered: FilteredGameState,
  allocation: MultiAdvisorAllocation,
  rng: var Rand
): Option[EspionageAttempt] =
  ## Execute Drungarius espionage requirements with allocated budget

  let espionageBudget = allocation.budgets.getOrDefault(controller_types.AdvisorType.Drungarius, 0)

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Executing espionage action " &
          &"(budget={espionageBudget}PP)")

  # Use Drungarius module to generate espionage action
  # For now pass 0 for EBP/CIP (TODO: Calculate from budget)
  result = generateEspionageAction(controller, filtered, 0, 0, rng)

  return result

proc executeTerraformOrders*(
  controller: AIController,
  filtered: FilteredGameState,
  allocation: MultiAdvisorAllocation,
  rng: var Rand
): seq[TerraformOrder] =
  ## Execute Eparch economic requirements with allocated budget

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Executing terraform orders " &
          &"(budget={allocation.budgets.getOrDefault(AdvisorType.Eparch, 0)}PP)")

  # Use Eparch module to generate terraform orders
  result = generateTerraformOrders(controller, filtered, rng)

  return result

proc executeDiplomaticActions*(
  controller: AIController,
  filtered: FilteredGameState
): seq[DiplomaticAction] {.deprecated: "Use basileus/execution.executeDiplomaticActions".} =
  ## DEPRECATED: Use basileus/execution.executeDiplomaticActions instead
  ## Execute Protostrator diplomatic requirements (costs 0 PP)
  ##
  ## This function now redirects to the centralized Basileus execution module
  ## for cleaner separation of concerns (advisors recommend, Basileus executes)

  # Redirect to Basileus centralized execution
  return basileus_exec.executeDiplomaticActions(controller, filtered)
