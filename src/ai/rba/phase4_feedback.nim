import std/[tables, options, sequtils, algorithm]
import ../../common/types/core # For HouseId, SystemId, FleetId
import ../../../engine/[gamestate, logger]
import ../controller_types # For AIController, AdvisorRequirement, RequirementFulfillmentStatus, IntelligenceSnapshot, RequirementPriority
import ../goap/core/types # For GOAPlan, WorldStateSnapshot
import ../goap/integration/[plan_tracking, replanning] # For PlanTracker, shouldReplan, ReplanReason
import ../orders/phase1_5_goap # For createWorldStateSnapshot (aliased from goap_snapshot)
import ../config # For globalRBAConfig

proc reportGOAPProgress*(
  controller: var AIController,
  totalAllocated: int,
  unfulfilledRequirements: seq[AdvisorRequirement],
  currentTurn: int,
  intelSnapshot: IntelligenceSnapshot
) =
  ## Reports RBA execution results back to the GOAP PlanTracker.
  ## This allows GOAP to update its plans, detect failures, and adapt.
  logInfo(LogCategory.lcAI, &"Phase 4 Feedback: Reporting GOAP progress for turn {currentTurn}")

  if not controller.goapConfig.enabled:
    logDebug(LogCategory.lcAI, "GOAP is disabled, skipping progress reporting.")
    return

  # Create an updated WorldStateSnapshot for GOAP from the current RBA state and intel
  let currentWorldState = createWorldStateSnapshot(
    controller.houseId, controller.homeworld, currentTurn, controller.goapConfig, intelSnapshot)

  # Iterate through unfulfilled requirements and potentially mark GOAP actions as failed/stalled
  for req in unfulfilledRequirements:
    if req.priority in {RequirementPriority.Critical, RequirementPriority.High}:
      logWarn(LogCategory.lcAI, &"GOAP Feedback: Critical/High requirement unfulfilled: {req.description}. This may signal a problem for active GOAP plans.")
      # In a more advanced system, we would attempt to map this RBA requirement
      # back to a specific GOAP action and mark that action as failed or stalled in the PlanTracker.
      # For now, the generic advanceTurn and shouldReplan logic will handle broader plan status.

  # Advance the GOAP PlanTracker for the current turn with the updated world state
  # This will internally check for completed actions and advance plan steps.
  controller.goapPlanTracker.advanceTurn(currentTurn, currentWorldState)

  logInfo(LogCategory.lcAI, &"Phase 4 Feedback: GOAP PlanTracker advanced to turn {currentTurn}. Active plans: {controller.goapPlanTracker.activePlans.len}")

proc checkGOAPReplanningNeeded*(
  controller: AIController,
  currentTurn: int,
  intelSnapshot: IntelligenceSnapshot
): Option[ReplanReason] =
  ## Checks if GOAP needs to replan due to changed conditions, stalled plans, or opportunities.
  ## Returns Some(ReplanReason) if replanning should be triggered, otherwise None.

  if not controller.goapConfig.enabled:
    return none(ReplanReason)

  let currentWorldState = createWorldStateSnapshot(
    controller.houseId, controller.homeworld, currentTurn, controller.goapConfig, intelSnapshot)

  # Check each active plan for replanning triggers
  for i in 0 ..< controller.goapPlanTracker.activePlans.len:
    let plan = controller.goapPlanTracker.activePlans[i]
    if plan.status == PlanStatus.Active: # Only check active plans
      let (needed, reason) = shouldReplan(plan, currentWorldState, controller.goapConfig)
      if needed:
        logWarn(LogCategory.lcAI, &"GOAP Replanning Triggered: Plan '{plan.plan.goal.description}' needs replanning. Reason: {reason}")
        return some(reason)

  # Additionally, periodically check for new, high-priority opportunities or threats
  # not currently covered by an active plan, as per new_opportunity_scan_frequency.
  if controller.goapConfig.newOpportunityScanFrequency > 0 and
     currentTurn mod controller.goapConfig.newOpportunityScanFrequency == 0:
    let currentGoals = controller.goapPlanTracker.activePlans.mapIt(it.plan.goal)
    let newOpportunities = detectNewOpportunities(currentGoals, currentWorldState)
    if newOpportunities.len > 0:
      logInfo(LogCategory.lcAI, &"GOAP: Detected {newOpportunities.len} new strategic opportunities. Considering replanning.")
      # The integration for adding these opportunities will happen in the planning phase,
      # but detecting them here can trigger a replan to re-evaluate goals.
      return some(ReplanReason.BetterOpportunity)


  return none(ReplanReason)
import std/[tables, options, sequtils, algorithm]
import ../../common/types/core # For HouseId, SystemId, FleetId
import ../../../engine/[gamestate, logger]
import ../controller_types # For AIController, AdvisorRequirement, RequirementFulfillmentStatus, IntelligenceSnapshot, RequirementPriority
import ../goap/core/types # For GOAPlan, WorldStateSnapshot
import ../goap/integration/[plan_tracking, replanning] # For PlanTracker, shouldReplan, ReplanReason
import ../orders/phase1_5_goap # For createWorldStateSnapshot (aliased from goap_snapshot)
import ../config # For globalRBAConfig

proc reportGOAPProgress*(
  controller: var AIController,
  totalAllocated: int,
  unfulfilledRequirements: seq[AdvisorRequirement],
  currentTurn: int,
  intelSnapshot: IntelligenceSnapshot
) =
  ## Reports RBA execution results back to the GOAP PlanTracker.
  ## This allows GOAP to update its plans, detect failures, and adapt.
  logInfo(LogCategory.lcAI, &"Phase 4 Feedback: Reporting GOAP progress for turn {currentTurn}")

  if not controller.goapConfig.enabled:
    logDebug(LogCategory.lcAI, "GOAP is disabled, skipping progress reporting.")
    return

  # Create an updated WorldStateSnapshot for GOAP from the current RBA state and intel
  let currentWorldState = createWorldStateSnapshot(
    controller.houseId, controller.homeworld, currentTurn, controller.goapConfig, intelSnapshot)

  # Iterate through unfulfilled requirements and potentially mark GOAP actions as failed/stalled
  for req in unfulfilledRequirements:
    if req.priority in {RequirementPriority.Critical, RequirementPriority.High}:
      logWarn(LogCategory.lcAI, &"GOAP Feedback: Critical/High requirement unfulfilled: {req.description}. This may signal a problem for active GOAP plans.")
      # In a more advanced system, we would attempt to map this RBA requirement
      # back to a specific GOAP action and mark that action as failed or stalled in the PlanTracker.
      # For now, the generic advanceTurn and shouldReplan logic will handle broader plan status.

  # Advance the GOAP PlanTracker for the current turn with the updated world state
  # This will internally check for completed actions and advance plan steps.
  controller.goapPlanTracker.advanceTurn(currentTurn, currentWorldState)

  logInfo(LogCategory.lcAI, &"Phase 4 Feedback: GOAP PlanTracker advanced to turn {currentTurn}. Active plans: {controller.goapPlanTracker.activePlans.len}")

proc checkGOAPReplanningNeeded*(
  controller: AIController,
  currentTurn: int,
  intelSnapshot: IntelligenceSnapshot
): Option[ReplanReason] =
  ## Checks if GOAP needs to replan due to changed conditions, stalled plans, or opportunities.
  ## Returns Some(ReplanReason) if replanning should be triggered, otherwise None.

  if not controller.goapConfig.enabled:
    return none(ReplanReason)

  let currentWorldState = createWorldStateSnapshot(
    controller.houseId, controller.homeworld, currentTurn, controller.goapConfig, intelSnapshot)

  # Check each active plan for replanning triggers
  for i in 0 ..< controller.goapPlanTracker.activePlans.len:
    let plan = controller.goapPlanTracker.activePlans[i]
    if plan.status == PlanStatus.Active: # Only check active plans
      let (needed, reason) = shouldReplan(plan, currentWorldState, controller.goapConfig)
      if needed:
        logWarn(LogCategory.lcAI, &"GOAP Replanning Triggered: Plan '{plan.plan.goal.description}' needs replanning. Reason: {reason}")
        return some(reason)

  # Additionally, periodically check for new, high-priority opportunities or threats
  # not currently covered by an active plan, as per new_opportunity_scan_frequency.
  if controller.goapConfig.newOpportunityScanFrequency > 0 and
     currentTurn mod controller.goapConfig.newOpportunityScanFrequency == 0:
    let currentGoals = controller.goapPlanTracker.activePlans.mapIt(it.plan.goal)
    let newOpportunities = detectNewOpportunities(currentGoals, currentWorldState)
    if newOpportunities.len > 0:
      logInfo(LogCategory.lcAI, &"GOAP: Detected {newOpportunities.len} new strategic opportunities. Considering replanning.")
      # The integration for adding these opportunities will happen in the planning phase,
      # but detecting them here can trigger a replan to re-evaluate goals.
      return some(ReplanReason.BetterOpportunity)


  return none(ReplanReason)
