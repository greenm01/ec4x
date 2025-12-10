import std/[tables, options, strformat, algorithm, sequtils]
import ../../../common/types/core
import ../../../engine/[gamestate, logger]
import ../../../engine/espionage/types as esp_types
import ../controller_types # For AIController, AdvisorType, EspionageRequirements, MultiAdvisorAllocation
import ../config # For globalRBAConfig

proc executeEspionageAction*(
  controller: var AIController,
  filtered: FilteredGameState,
  allocation: MultiAdvisorAllocation,
  rng: var Rand
): Option[esp_types.EspionageAttempt] =
  ## Executes the highest priority espionage operation that can be afforded.
  ##
  ## Prioritizes operations based on the Drungarius's requirements and allocated budget.
  ## Also sets EBP/CIP investment for the turn.

  result = none(esp_types.EspionageAttempt)

  let drungariusFeedback = allocation.drungariusFeedback # Get feedback, which contains fulfilled/unfulfilled reqs
  let espionageBudget = allocation.budgets.getOrDefault(AdvisorType.Drungarius, 0)
  
  if drungariusFeedback.isNone:
    logWarn(LogCategory.lcAI, &"{controller.houseId} Drungarius: No feedback from Treasurer, skipping espionage execution.")
    return

  let feedback = drungariusFeedback.get()

  # 1. Separate EBP/CIP investments from operations
  var operationReqs: seq[EspionageRequirement] = @[]
  var ebpInvestment = 0
  var cipInvestment = 0

  for req in feedback.fulfilledRequirements:
    case req.requirementType
    of EspionageRequirementType.EBPInvestment:
      ebpInvestment += req.estimatedCost
    of EspionageRequirementType.CIPInvestment:
      cipInvestment += req.estimatedCost
    of EspionageRequirementType.Operation:
      operationReqs.add(req)

  # Only one espionage operation can be executed per turn.
  # Select the highest priority fulfilled operation.
  if operationReqs.len > 0:
    # Sort fulfilled operations by priority (highest first)
    operationReqs.sort(proc(a, b: EspionageRequirement): int = cmp(b.priority, a.priority))

    let bestOperation = operationReqs[0]

    if bestOperation.operation.isSome and bestOperation.targetHouse.isSome:
      let opType = bestOperation.operation.get()
      let targetHouse = bestOperation.targetHouse.get()
      let targetSystem = bestOperation.targetSystem # Can be none for house-wide ops

      # Check if this operation requires EBP/CIP.
      # The cost is already reflected in req.estimatedCost.
      # The actual cost is paid by the game engine, here we just form the order.

      result = some(esp_types.EspionageAttempt(
        sourceHouseId: controller.houseId,
        targetHouseId: targetHouse,
        targetSystemId: targetSystem, # Can be none
        operationType: opType,
        # The success/failure/detection will be handled by the game engine,
        # and reported back via GameEvents (Phase 4 Feedback).
      ))
      logInfo(LogCategory.lcAI, &"{controller.houseId} Drungarius: Executing espionage operation '{opType}' " &
                               &"against {targetHouse} (Target System: {targetSystem.getOrDefault(0.SystemId)})")
    else:
      logWarn(LogCategory.lcAI, &"{controller.houseId} Drungarius: Fulfilled operation requirement " &
                               &"but missing operation type or target house. Skipping.")

  # Store EBP/CIP investments directly in the OrderPacket (handled in orders.nim)
  # For now, this procedure focuses on returning the ONE operation.
  # The total EBP/CIP investment for the turn is set directly in orders.nim from controller.drungariusRequirements

  logDebug(LogCategory.lcAI, &"{controller.houseId} Drungarius: Espionage execution completed. EBP investment: {ebpInvestment} PP, CIP investment: {cipInvestment} PP")

  return result
