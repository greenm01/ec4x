import std/[tables, options, strformat]
import ../../../engine/[logger, gamestate]
import ../../../engine/economy/maintenance  # For calculateHouseMaintenanceCost
import ../controller_types # For AIController, all requirements and feedback types
import ../../common/types as ai_types # For GameAct
import ../basileus/mediation # For mediateRequirements
import ../treasurer/multi_advisor # For allocateBudgetMultiAdvisor, MultiAdvisorAllocation
import ../goap/integration/conversion # Fixed path
import ../goap/integration/snapshot # Fixed path

proc mediateAndAllocateBudget*(
  controller: var AIController,
  filtered: FilteredGameState,
  rng: var Rand # For future random elements in mediation (e.g. tie-breaking)
): MultiAdvisorAllocation =
  ## Main entry point for Treasurer's budget allocation (Phase 2).
  ## This function orchestrates the mediation process by:
  ## 1. Retrieving requirements from all advisors stored in the AIController.
  ## 2. Calling the multi-advisor allocation logic.
  ## 3. Storing the feedback from the allocation back into the AIController.
  ## 4. Returning the final budget allocations for each advisor.

  logInfo(LogCategory.lcAI, &"{controller.houseId} Treasurer: Starting Phase 2 - Budget Mediation and Allocation.")

  # Retrieve requirements from controller.
  # Ensure all advisors have generated requirements; if not, use empty ones.
  let domestikosReqs = controller.domestikosRequirements.getOrDefault(BuildRequirements())
  let logotheteReqs = controller.logotheteRequirements.getOrDefault(ResearchRequirements())
  let drungariusReqs = controller.drungariusRequirements.getOrDefault(EspionageRequirements())
  let eparchReqs = controller.eparchRequirements.getOrDefault(EconomicRequirements())
  let protostratorReqs = controller.protostratorRequirements.getOrDefault(DiplomaticRequirements())

  # Get GOAP budget estimates from the controller, which were generated in Phase 1.5
  let goapEstimates = controller.goapBudgetEstimates # Directly use the stored estimates
  let goapReservedAmount = controller.goapReservedBudget # Use the GOAP reserved amount

  # CRITICAL: Calculate maintenance costs and reserve from treasury
  # The AI MUST account for maintenance before allocating to construction
  # Otherwise it enters a maintenance death spiral (spending all PP, losing ships)
  let maintenanceCost = calculateHouseMaintenanceCost(filtered.state, controller.houseId)
  let availableBudget = max(0, filtered.ownHouse.treasury - maintenanceCost)

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Treasurer: Treasury={filtered.ownHouse.treasury} PP, " &
          &"Maintenance={maintenanceCost} PP, Available={availableBudget} PP")

  # Perform multi-advisor allocation
  result = allocateBudgetMultiAdvisor(
    domestikosReqs,
    logotheteReqs,
    drungariusReqs,
    eparchReqs,
    protostratorReqs,
    controller.personality,
    filtered.currentAct,
    availableBudget,  # Use treasury AFTER maintenance reserve
    controller.houseId,
    filtered,
    goapEstimates, # Pass GOAP estimates to the allocator
    goapReservedAmount # Pass GOAP reserved amount
  )

  # Store feedback in the controller for subsequent phases (Phase 3 and 4)
  controller.treasurerFeedback = some(result.treasurerFeedback)
  controller.scienceFeedback = some(result.scienceFeedback)
  controller.drungariusFeedback = some(result.drungariusFeedback)
  controller.eparchFeedback = some(result.eparchFeedback)
  controller.lastTurnAllocationResult = some(result) # Store the full allocation result
  # Protostrator doesn't have direct budget feedback from Treasurer as diplomacy costs 0

  logInfo(LogCategory.lcAI, &"{controller.houseId} Treasurer: Phase 2 complete. Allocated budget to advisors.")

  return result
