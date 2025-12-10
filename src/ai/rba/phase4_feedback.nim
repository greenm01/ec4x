import std/[tables, options, sequtils, algorithm, sugar]
import ../../../common/types/core # For HouseId, SystemId, FleetId
import ../../../engine/[gamestate, logger]
import ../controller_types # For AIController, AdvisorRequirement, RequirementFulfillmentStatus, IntelligenceSnapshot, RequirementPriority, BuildRequirement, ResearchRequirement, EspionageRequirement, EconomicRequirement
import ../goap/core/types # For GOAPlan, WorldStateSnapshot, Action, ActionType, GoalType, TechField
import ../goap/integration/[plan_tracking, replanning] # For PlanTracker, shouldReplan, ReplanReason
import ../orders/phase1_5_goap # For createWorldStateSnapshot (aliased from goap_snapshot)
import ../treasurer/multi_advisor # For MultiAdvisorAllocation, AdvisorRequirement
import ../config # For globalRBAConfig

# Helper functions for checking actual outcomes of actions
proc getFleetCount(gs: GameState, houseId: HouseId, systemId: SystemId, shipClass: string): int =
  ## Returns the total number of ships of a given class for a house in a system from GameState.
  if systemId not in gs.systems: return 0
  let sys = gs.systems[systemId]
  if houseId not in sys.fleets: return 0
  for _, fleet in sys.fleets[houseId]:
    if $fleet.shipClass == shipClass: # Assuming shipClass can be compared as string
      result += fleet.numShips

proc getFleetCount(intel: IntelligenceSnapshot, houseId: HouseId, systemId: SystemId, shipClass: string): int =
  ## Returns the total number of ships of a given class for a house in a system from IntelligenceSnapshot.
  if systemId not in intel.knownSystems: return 0
  let sysIntel = intel.knownSystems[systemId]
  if houseId not in sysIntel.fleets: return 0
  for _, fleetIntel in sysIntel.fleets[houseId]:
    if fleetIntel.shipClass == shipClass: # Assuming FleetIntel has a string field `shipClass`
      result += fleetIntel.numShips # Assuming FleetIntel has `numShips: int`

proc getFacilityOrGroundUnitCount(gs: GameState, houseId: HouseId, systemId: SystemId, itemId: string, isFacility: bool): int =
  ## Returns the count of a facility or ground unit for a house in a system from GameState.
  if systemId not in gs.systems: return 0
  let sys = gs.systems[systemId]
  if houseId not in sys.facilities and isFacility: return 0
  if houseId not in sys.groundForces and not isFacility: return 0

  if isFacility:
    if sys.facilities[houseId].contains(itemId):
      return sys.facilities[houseId][itemId]
  else: # Ground units
    if sys.groundForces[houseId].contains(itemId):
      return sys.groundForces[houseId][itemId]
  return 0

proc getFacilityOrGroundUnitCount(intel: IntelligenceSnapshot, houseId: HouseId, systemId: SystemId, itemId: string, isFacility: bool): int =
  ## Returns the count of a facility or ground unit for a house in a system from IntelligenceSnapshot.
  if systemId not in intel.knownSystems: return 0
  let sysIntel = intel.knownSystems[systemId]
  if houseId not in sysIntel.facilities and isFacility: return 0
  if houseId not in sysIntel.groundForces and not isFacility: return 0
  
  if isFacility:
    if sysIntel.facilities[houseId].contains(itemId):
      return sysIntel.facilities[houseId][itemId]
  else: # Ground units
    if sysIntel.groundForces[houseId].contains(itemId):
      return sysIntel.groundForces[houseId][itemId]
  return 0


proc checkActualOutcome(
  houseId: HouseId,
  action: Action,
  initialGameState: GameState,
  intelSnapshot: IntelligenceSnapshot,
  currentTechLevels: Table[TechField, int] # AI's current tech levels from controller
): bool =
  ## Checks if a GOAP action had its intended effect by comparing initial game state
  ## with the intelligence snapshot after orders have been processed.
  case action.actionType
  of ActionType.BuildFleet:
    let initialCount = getFleetCount(initialGameState, houseId, action.target, action.shipClass)
    let currentCount = getFleetCount(intelSnapshot, houseId, action.target, action.shipClass)
    return currentCount > initialCount
  of ActionType.BuildFacility:
    let initialCount = getFacilityOrGroundUnitCount(initialGameState, houseId, action.target, action.itemId, true)
    let currentCount = getFacilityOrGroundUnitCount(intelSnapshot, houseId, action.target, action.itemId, true)
    return currentCount > initialCount
  of ActionType.BuildGroundForces:
    let initialCount = getFacilityOrGroundUnitCount(initialGameState, houseId, action.target, action.itemId, false)
    let currentCount = getFacilityOrGroundUnitCount(intelSnapshot, houseId, action.target, action.itemId, false)
    return currentCount > initialCount
  of ActionType.AllocateResearch:
    let initialTechLevel = initialGameState.techLevels[houseId][action.techField]
    let currentTechLevel = currentTechLevels[action.techField]
    return currentTechLevel > initialTechLevel
  # Add other actions here that need direct outcome verification.
  # For now, other actions (espionage, economic) are primarily deemed successful
  # if RBA fulfills their requirements, or if game events report success.
  else:
    # For actions not explicitly checked here, assume RBA fulfillment implies success for now.
    # More complex outcome checks (e.g., combat results, espionage success/failure events)
    # would require parsing game event logs or deeper state comparisons.
    return true # Default to true for unchecked actions, relying on RBA fulfillment.


# Helper to match a GOAP action to an RBA requirement
proc matchActionToRequirement(action: Action, requirement: AdvisorRequirement): bool =
  ## Attempts to match a GOAP action to a specific RBA requirement.
  ## This is a heuristic match based on type, target, and general intent.
  ##
  ## NOTE: This could be made more robust with unique IDs for actions/requirements
  ## or by generating a canonical string representation for comparison.
  case action.actionType
  of ActionType.BuildFleet:
    if requirement.buildReq.isSome:
      let buildReq = requirement.buildReq.get()
      return buildReq.shipClass == action.shipClass and buildReq.targetSystem == action.target
    return false
  of ActionType.BuildFacility, ActionType.BuildGroundForces:
    if requirement.buildReq.isSome:
      let buildReq = requirement.buildReq.get()
      # Match by item ID (e.g., "Starbase", "Marine") and target system
      return buildReq.itemId.isSome and buildReq.itemId.get() == action.itemId and buildReq.targetSystem == action.target
    return false
  of ActionType.AllocateResearch:
    if requirement.researchReq.isSome:
      let researchReq = requirement.researchReq.get()
      # Match by tech field and general intent
      return researchReq.techField == action.techField
    return false
  of ActionType.ConductEspionage:
    if requirement.espionageReq.isSome:
      let espionageReq = requirement.espionageReq.get()
      # Match by target house and specific operation type
      return espionageReq.targetHouse == action.targetHouse and espionageReq.operation == action.espionageAction
    return false
  of ActionType.TransferPopulation:
    if requirement.economicReq.isSome:
      let economicReq = requirement.economicReq.get()
      return economicReq.requirementType == EconomicRequirementType.PopulationTransfer and economicReq.targetColony == action.toSystem
    return false
  of ActionType.TerraformPlanet:
    if requirement.economicReq.isSome:
      let economicReq = requirement.economicReq.get()
      return economicReq.requirementType == EconomicRequirementType.Terraforming and economicReq.targetColony == action.target
    return false
  of ActionType.MoveFleet, ActionType.AttackColony, ActionType.AssembleInvasionForce,
     ActionType.EstablishDefense, ActionType.ConductScoutMission,
     ActionType.ProposeAlliance, ActionType.DeclareWar:
    # These actions typically don't have direct RBA requirements that are "fulfilled" by Treasurer
    # They are executed directly as FleetOrders or DiplomaticActions.
    # Their success/failure is usually determined by world state changes or event logs.
    # For now, we mainly focus on build/research/espionage/economic requirements.
    return false
  of ActionType.GainTreasury, ActionType.SpendTreasury:
    # Internal GOAP accounting actions, not directly mapped to RBA reqs
    return false
  
  # Add other ActionTypes as needed for mapping
  else:
    return false


proc reportGOAPProgress*(
  controller: var AIController,
  allocationResult: MultiAdvisorAllocation, # Get full allocation result for feedback
  currentTurn: int,
  intelSnapshot: IntelligenceSnapshot,
  initialGameState: GameState # For comparing changes to world state to determine action success
) =
  ## Reports RBA execution results back to the GOAP PlanTracker.
  ## This allows GOAP to update its plans, detect failures, and adapt.
  logInfo(LogCategory.lcAI, &"Phase 4 Feedback: Reporting GOAP progress for turn {currentTurn}")

  if not controller.goapEnabled:
    logDebug(LogCategory.lcAI, "GOAP is disabled, skipping progress reporting.")
    return

  # Create an updated WorldStateSnapshot for GOAP from the current RBA state and intel
  let currentWorldState = createWorldStateSnapshot(
    controller.houseId, controller.homeworld, currentTurn, controller.goapConfig, intelSnapshot)

  # Consolidate all fulfilled and unfulfilled requirements from the allocation result
  var allFulfilledReqs = newSeq[AdvisorRequirement]()
  allFulfilledReqs.add(allocationResult.treasurerFeedback.fulfilledRequirements.mapIt(
    AdvisorRequirement(advisor: AdvisorType.Domestikos, buildReq: some(it), requirementType: $it.requirementType)
  ))
  allFulfilledReqs.add(allocationResult.scienceFeedback.fulfilledRequirements.mapIt(
    AdvisorRequirement(advisor: AdvisorType.Logothete, researchReq: some(it), requirementType: "ResearchRequirement")
  ))
  allFulfilledReqs.add(allocationResult.drungariusFeedback.fulfilledRequirements.mapIt(
    AdvisorRequirement(advisor: AdvisorType.Drungarius, espionageReq: some(it), requirementType: $it.requirementType)
  ))
  allFulfilledReqs.add(allocationResult.eparchFeedback.fulfilledRequirements.mapIt(
    AdvisorRequirement(advisor: AdvisorType.Eparch, economicReq: some(it), requirementType: $it.requirementType)
  ))
  allFulfilledReqs.add(allocationResult.fulfilledRequirements.filterIt(it.advisor == AdvisorType.Protostrator))


  var allUnfulfilledReqs = newSeq[AdvisorRequirement]()
  allUnfulfilledReqs.add(allocationResult.treasurerFeedback.unfulfilledRequirements.mapIt(
    AdvisorRequirement(advisor: AdvisorType.Domestikos, buildReq: some(it), requirementType: $it.requirementType)
  ))
  allUnfulfilledReqs.add(allocationResult.scienceFeedback.unfulfilledRequirements.mapIt(
    AdvisorRequirement(advisor: AdvisorType.Logothete, researchReq: some(it), requirementType: "ResearchRequirement")
  ))
  allUnfulfilledReqs.add(allocationResult.drungariusFeedback.unfulfilledRequirements.mapIt(
    AdvisorRequirement(advisor: AdvisorType.Drungarius, espionageReq: some(it), requirementType: $it.requirementType)
  ))
  allUnfulfilledReqs.add(allocationResult.eparchFeedback.unfulfilledRequirements.mapIt(
    AdvisorRequirement(advisor: AdvisorType.Eparch, economicReq: some(it), requirementType: $it.requirementType)
  ))
  allUnfulfilledReqs.add(allocationResult.unfulfilledRequirements.filterIt(it.advisor == AdvisorType.Protostrator))


  # Iterate through active GOAP plans and attempt to match actions with RBA feedback
  for planIdx in 0 ..< controller.planTracker.activePlans.len:
    var trackedPlan = controller.planTracker.activePlans[planIdx]

    if trackedPlan.status != PlanStatus.Active:
      continue # Only process active plans

    if trackedPlan.currentActionIndex >= trackedPlan.plan.actions.len:
      # Plan has no more actions, mark as completed
      controller.planTracker.advancePlan(planIdx) # Will set status to Completed
      logInfo(LogCategory.lcAI, &"GOAP: Plan '{trackedPlan.plan.goal.name}' completed all actions.")
      continue

    let currentAction = trackedPlan.plan.actions[trackedPlan.currentActionIndex]

    # Check if the current GOAP action was fulfilled by RBA
    var actionFulfilled = false
    for fulfilledReq in allFulfilledReqs:
      if matchActionToRequirement(currentAction, fulfilledReq):
        actionFulfilled = true
        break

    if actionFulfilled:
      # RBA fulfilled the requirement, now check if the actual outcome occurred
      let outcomeSuccessful = checkActualOutcome(
        controller.houseId, currentAction, initialGameState, intelSnapshot, controller.techLevels
      )
      
      if outcomeSuccessful:
        controller.planTracker.markActionComplete(planIdx, trackedPlan.currentActionIndex)
        logInfo(LogCategory.lcAI, &"GOAP: Action '{currentAction.name}' of plan '{trackedPlan.plan.goal.name}' FULFILLED and OUTCOME SUCCESSFUL.")
      else:
        # RBA allocated resources, but the intended outcome did not materialize this turn.
        # This could indicate a problem (e.g., construction blocked, research not yet mature).
        # Mark as failed for now to trigger replanning, or potentially a "stalled" state.
        controller.planTracker.markActionFailed(planIdx, trackedPlan.currentActionIndex)
        logWarn(LogCategory.lcAI, &"GOAP: Action '{currentAction.name}' of plan '{trackedPlan.plan.goal.name}' FULFILLED by RBA, but OUTCOME FAILED. Re-evaluating plan.")
    else:
      # If action was not explicitly fulfilled by RBA, check if it was explicitly unfulfilled (especially critical ones)
      var actionFailed = false
      for unfulfilledReq in allUnfulfilledReqs:
        if matchActionToRequirement(currentAction, unfulfilledReq) and
           unfulfilledReq.priority in {RequirementPriority.Critical, RequirementPriority.High}:
          actionFailed = true
          logWarn(LogCategory.lcAI, &"GOAP: Critical/High action '{currentAction.name}' of plan '{trackedPlan.plan.goal.name}' UNFULFILLED by RBA.")
          break
      
      if actionFailed:
        controller.planTracker.markActionFailed(planIdx, trackedPlan.currentActionIndex)
      else:
        # If not fulfilled and not explicitly failed (e.g., lower priority, deferred),
        # GOAP still considers it pending. `advanceTurn` will increment `turnsInExecution`
        # and `shouldReplan` can detect stalled plans.
        logDebug(LogCategory.lcAI, &"GOAP: Action '{currentAction.name}' of plan '{trackedPlan.plan.goal.name}' not yet fulfilled by RBA (status pending).")


  # Advance the GOAP PlanTracker for the current turn with the updated world state
  # This will internally increment turnsInExecution and re-validate plans.
  controller.planTracker.advanceTurn(currentTurn, currentWorldState)

  logInfo(LogCategory.lcAI, &"Phase 4 Feedback: GOAP PlanTracker advanced to turn {currentTurn}. Active plans: {controller.planTracker.activePlans.len}")


proc checkGOAPReplanningNeeded*(
  controller: AIController,
  currentTurn: int,
  intelSnapshot: IntelligenceSnapshot
): Option[ReplanReason] =
  ## Checks if GOAP needs to replan due to changed conditions, stalled plans, or opportunities.
  ## Returns Some(ReplanReason) if replanning should be triggered, otherwise None.

  if not controller.goapEnabled:
    return none(ReplanReason)

  let currentWorldState = createWorldStateSnapshot(
    controller.houseId, controller.homeworld, currentTurn, controller.goapConfig, intelSnapshot)

  # Check each active plan for replanning triggers
  for i in 0 ..< controller.planTracker.activePlans.len:
    let plan = controller.planTracker.activePlans[i]
    if plan.status == PlanStatus.Active: # Only check active plans
      let (needed, reason) = shouldReplan(plan, currentWorldState, controller.goapConfig)
      if needed:
        logWarn(LogCategory.lcAI, &"GOAP Replanning Triggered: Plan '{plan.plan.goal.name}' needs replanning. Reason: {reason}")
        return some(reason)

  # Additionally, periodically check for new, high-priority opportunities or threats
  # not currently covered by an active plan, as per new_opportunity_scan_frequency.
  if controller.goapConfig.newOpportunityScanFrequency > 0 and
     currentTurn mod controller.goapConfig.newOpportunityScanFrequency == 0:
    let currentGoals = controller.planTracker.activePlans.mapIt(it.plan.goal)
    let newOpportunities = detectNewOpportunities(currentGoals, currentWorldState)
    if newOpportunities.len > 0:
      logInfo(LogCategory.lcAI, &"GOAP: Detected {newOpportunities.len} new strategic opportunities. Considering replanning.")
      # The integration for adding these opportunities will happen in the planning phase,
      # but detecting them here can trigger a replan to re-evaluate goals.
      return some(ReplanReason.BetterOpportunity)


  return none(ReplanReason)
