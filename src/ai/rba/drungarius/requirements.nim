## Drungarius Espionage Requirements Module
##
## Byzantine Imperial Drungarius - Espionage Requirements Generation
##
## Generates espionage requirements with priorities for Basileus mediation
## Includes EBP/CIP investment and operation requirements

import std/[options, strformat, tables]
import ../../../common/types/core
import ../../../engine/[gamestate, fog_of_war, logger]
import ../../../engine/resolution/types as event_types # For EspionageAction
import ../../../common/types/diplomacy as dip_types # For DiplomaticState
import ../controller_types
import ../shared/intelligence_types  # For IntelligenceSnapshot
import ../../common/types as ai_types
import ../goap/core/types # For GoalType
import ../goap/integration/plan_tracking # For PlanTracker, PlanStatus

proc generateEspionageRequirements*(
  controller: AIController,
  filtered: FilteredGameState,
  intelSnapshot: IntelligenceSnapshot,
  currentAct: GameAct,
  availableBudget: int # Total PP available to house for this turn
): EspionageRequirements =
  ## Generate espionage requirements with intelligence-driven priorities.
  ## Also factors in "MaintainPrestige" GOAP goal to avoid over-investment penalties.
  ##
  ## Priority tiers:
  ## - Critical: EBP/CIP investment in early game (Act 1-2)
  ## - High: Operations against enemies, high-value sabotage
  ## - Medium: EBP/CIP growth, intelligence theft
  ## - Low: Opportunistic operations, disinformation
  ## - Deferred: Luxury operations (assassination, etc.)

  result.requirements = @[]
  result.totalEstimatedCost = 0
  result.generatedTurn = filtered.turn
  result.iteration = 0

  let p = controller.personality
  let currentEBP = filtered.ownHouse.espionageBudget.ebpPoints
  let currentCIP = filtered.ownHouse.espionageBudget.cipPoints

  # Check if "MaintainPrestige" GOAP goal is active (Gap 6)
  let isMaintainPrestigeActive = controller.goapPlanTracker.activePlans.anyIt(
    it.status == PlanStatus.Active and it.plan.goal.goalType == GoalType.MaintainPrestige
  )
  let prestigePenaltyThresholdRatio = 0.05 # 5% of budget as per docs/specs/diplomacy.md
  let ppPerEBP_CIP = 40 # As per docs/specs/diplomacy.md

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Drungarius: Generating espionage requirements " &
          &"(EBP={currentEBP}, CIP={currentCIP}, Act={currentAct}, MaintainPrestigeActive={isMaintainPrestigeActive})")

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Drungarius: Generating espionage requirements " &
          &"(EBP={currentEBP}, CIP={currentCIP}, Act={currentAct})")

  # === EBP/CIP Investment Target Levels by Act ===
  let targetEBP = case currentAct
    of ai_types.GameAct.Act1_LandGrab: 5
    of ai_types.GameAct.Act2_RisingTensions: 10
    of ai_types.GameAct.Act3_TotalWar: 15
    of ai_types.GameAct.Act4_Endgame: 20

  var targetCIP = case currentAct # Use var for modification
    of ai_types.GameAct.Act1_LandGrab: 3
    of ai_types.GameAct.Act2_RisingTensions: 7
    of ai_types.GameAct.Act3_TotalWar: 12
    of ai_types.GameAct.Act4_Endgame: 15

  # === PRESTIGE AWARENESS (Gap 6): Adjust target EBP/CIP if MaintainPrestige is active ===
  var adjustedTargetEBP = targetEBP
  var adjustedTargetCIP = targetCIP

  if isMaintainPrestigeActive:
    # Estimate total PP to reach targets
    let estimatedEBP_PP_cost = (targetEBP - currentEBP) * ppPerEBP_CIP
    let estimatedCIP_PP_cost = (targetCIP - currentCIP) * ppPerEBP_CIP
    let totalEstimatedInvestment_PP = estimatedEBP_PP_cost + estimatedCIP_PP_cost

    let prestigePenaltyThreshold_PP = int(float(availableBudget) * prestigePenaltyThresholdRatio)

    if totalEstimatedInvestment_PP > prestigePenaltyThreshold_PP:
      logInfo(LogCategory.lcAI, &"{controller.houseId} Drungarius: MaintainPrestige active and EBP/CIP over-investment risk. " &
                               &"Estimated cost {totalEstimatedInvestment_PP}PP > threshold {prestigePenaltyThreshold_PP}PP. Reducing targets.")
      
      # Reduce targets to avoid penalties. Prioritize CIP over EBP for defense.
      if estimatedEBP_PP_cost > 0:
        # Reduce EBP target first if it's the larger contributor to overspending
        # Simple heuristic: scale down EBP target to fit within threshold
        let newEBP_PP_cost = max(0, prestigePenaltyThreshold_PP - estimatedCIP_PP_cost) # remaining budget for EBP
        adjustedTargetEBP = currentEBP + (newEBP_PP_cost div ppPerEBP_CIP)
        adjustedTargetEBP = min(adjustedTargetEBP, targetEBP) # Don't go above original target

      if estimatedCIP_PP_cost > 0 and adjustedTargetEBP < targetEBP: # Only adjust CIP if EBP was reduced
        # If still over after EBP adjustment, reduce CIP too
        let newTotalEstimated_PP = (adjustedTargetEBP - currentEBP) * ppPerEBP_CIP + estimatedCIP_PP_cost
        if newTotalEstimated_PP > prestigePenaltyThreshold_PP:
            let newCIP_PP_cost = max(0, prestigePenaltyThreshold_PP - (adjustedTargetEBP - currentEBP) * ppPerEBP_CIP)
            adjustedTargetCIP = currentCIP + (newCIP_PP_cost div ppPerEBP_CIP)
            adjustedTargetCIP = min(adjustedTargetCIP, targetCIP) # Don't go above original target

      logInfo(LogCategory.lcAI, &"{controller.houseId} Drungarius: Adjusted targets - EBP: {targetEBP}→{adjustedTargetEBP}, CIP: {targetCIP}→{adjustedTargetCIP}.")
    else:
      logDebug(LogCategory.lcAI, &"{controller.houseId} Drungarius: MaintainPrestige active, but EBP/CIP investment within safe limits.")

  # Use adjusted targets for requirement generation
  targetEBP = adjustedTargetEBP
  targetCIP = adjustedTargetCIP


  # === CRITICAL/HIGH: EBP Investment (early game) ===
  if currentEBP < targetEBP:
    let ebpGap = targetEBP - currentEBP
    let priority = if currentEBP < 3:
      RequirementPriority.Critical  # Very low EBP = critical
    elif ebpGap >= 5:
      RequirementPriority.High  # Significant gap
    else:
      RequirementPriority.Medium

    let investmentCost = ebpGap * ppPerEBP_CIP # Actual cost: 40 PP per EBP point

    result.requirements.add(EspionageRequirement(
      requirementType: EspionageRequirementType.EBPInvestment,
      priority: priority,
      targetHouse: none(HouseId),
      operation: none(esp_types.EspionageAction),
      estimatedCost: investmentCost,
      reason: &"EBP investment (current: {currentEBP}, target: {targetEBP} for {currentAct})"
    ))
    result.totalEstimatedCost += investmentCost

  # === MEDIUM: CIP Investment (defensive espionage) ===
  if currentCIP < targetCIP:
    let cipGap = targetCIP - currentCIP
    let priority = if cipGap >= 5:
      RequirementPriority.High  # Significant gap
    else:
      RequirementPriority.Medium

    let investmentCost = cipGap * ppPerEBP_CIP # Actual cost: 40 PP per CIP point

    result.requirements.add(EspionageRequirement(
      requirementType: EspionageRequirementType.CIPInvestment,
      priority: priority,
      targetHouse: none(HouseId),
      operation: none(esp_types.EspionageAction),
      estimatedCost: investmentCost,
      reason: &"CIP investment (current: {currentCIP}, target: {targetCIP} for {currentAct})"
    ))
    result.totalEstimatedCost += investmentCost

  # === HIGH: Operations against high-value targets ===
  # Prioritize sabotage of undefended high-industry colonies
  # === MEDIUM/HIGH: Counter-Intelligence Sweep (defensive) ===
  # Prioritize defensive sweeps if CIP is low or personality is risk-averse
  if currentCIP < targetCIP: # Only if CIP is below target (i.e. we need more defense)
    let priority = if currentCIP < 5: RequirementPriority.High else: RequirementPriority.Medium
    let cost = 4 # Fixed cost for Counter-Intelligence Sweep

    result.requirements.add(EspionageRequirement(
      requirementType: EspionageRequirementType.Operation,
      priority: priority,
      targetHouse: none(HouseId), # Counter-Intelligence Sweep is self-focused
      operation: some(esp_types.EspionageAction.CounterIntelligenceSweep),
      estimatedCost: cost,
      reason: &"Defensive Counter-Intelligence Sweep (CIP: {currentCIP}/{targetCIP})"
    ))
    result.totalEstimatedCost += cost
  else:
    # If CIP is sufficient, still consider sweeps based on risk tolerance or perceived threat
    if p.riskTolerance < 0.4 and currentCIP < 10: # Risk-averse, maintain good CIP
      let cost = 4
      result.requirements.add(EspionageRequirement(
        requirementType: EspionageRequirementType.Operation,
        priority: RequirementPriority.Medium,
        targetHouse: none(HouseId),
        operation: some(esp_types.EspionageAction.CounterIntelligenceSweep),
        estimatedCost: cost,
        reason: &"Maintain Counter-Intelligence posture (risk tolerance: {p.riskTolerance:.2f})"
      ))
      result.totalEstimatedCost += cost

  # === HIGH: Operations against high-value targets ===
  # Prioritize sabotage of undefended high-industry colonies
  if currentEBP >= 7 and intelSnapshot.highValueTargets.len > 0:
    # Target the first high-value target (already sorted by priority in intelligence report)
    let targetSystem = intelSnapshot.highValueTargets[0]

    # Find the owner from intelligence
    var targetOwner: HouseId = HouseId("")
    for (systemId, owner) in intelSnapshot.knownEnemyColonies:
      if systemId == targetSystem:
        targetOwner = owner
        break

    if targetOwner != HouseId(""):
      result.requirements.add(EspionageRequirement(
        requirementType: EspionageRequirementType.Operation,
        priority: RequirementPriority.High,
        targetHouse: some(targetOwner),
        operation: some(esp_types.EspionageAction.SabotageHigh),
        targetSystem: some(targetSystem), # Set target system for system-specific operation
        estimatedCost: 50,  # High sabotage operation cost estimate
        reason: &"High-value sabotage target - system {targetSystem} (undefended, high industry)"
      ))
      result.totalEstimatedCost += 50

  # === HIGH: Operations against enemies ===
  # Phase E: Prioritize based on espionage intelligence (detection risk, coverage gaps)
  if currentEBP >= 8 and intelSnapshot.espionageOpportunities.len > 0:
    # Target first espionage opportunity, but check detection risk
    let targetHouse = intelSnapshot.espionageOpportunities[0]

    # Phase E: Check detection risk from counter-intelligence analysis
    var detectionRiskNote = ""
    var adjustedPriority = RequirementPriority.High
    if intelSnapshot.espionage.detectionRisks.hasKey(targetHouse):
      let risk = intelSnapshot.espionage.detectionRisks[targetHouse]
      case risk
      of DetectionRiskLevel.High:
        adjustedPriority = RequirementPriority.Medium  # Downgrade priority due to risk
        detectionRiskNote = " [HIGH DETECTION RISK - proceed cautiously]"
      of DetectionRiskLevel.Moderate:
        detectionRiskNote = " [Moderate detection risk]"
      else:
        discard

    result.requirements.add(EspionageRequirement(
      requirementType: EspionageRequirementType.Operation,
      priority: adjustedPriority,
      targetHouse: some(targetHouse),
      operation: some(esp_types.EspionageAction.IntelligenceTheft),
      estimatedCost: 40,  # Intelligence theft cost estimate
      reason: &"Intelligence theft from enemy {targetHouse} (espionage opportunity identified){detectionRiskNote}"
    ))
    result.totalEstimatedCost += 40

  # === MEDIUM: Disinformation operations ===
  if currentEBP >= 6 and p.aggression > 0.6:
    # Aggressive AIs use disinformation to confuse enemies
    if intelSnapshot.espionageOpportunities.len > 0:
      let targetHouse = intelSnapshot.espionageOpportunities[0]

      result.requirements.add(EspionageRequirement(
        requirementType: EspionageRequirementType.Operation,
        priority: RequirementPriority.Medium,
        targetHouse: some(targetHouse),
        operation: some(esp_types.EspionageAction.PlantDisinformation),
        estimatedCost: 35,  # Disinformation cost estimate
        reason: &"Plant disinformation against {targetHouse} (aggression={p.aggression:.2f})"
      ))
      result.totalEstimatedCost += 35

  # === MEDIUM: Economic manipulation ===
  if currentEBP >= 6 and p.economicFocus > 0.6:
    # Economic-focused AIs target enemy economies
    if intelSnapshot.espionageOpportunities.len > 0:
      let targetHouse = intelSnapshot.espionageOpportunities[0]

      result.requirements.add(EspionageRequirement(
        requirementType: EspionageRequirementType.Operation,
        priority: RequirementPriority.Medium,
        targetHouse: some(targetHouse),
        operation: some(esp_types.EspionageAction.EconomicManipulation),
        estimatedCost: 35,  # Economic manipulation cost estimate
        reason: &"Economic manipulation against {targetHouse} (economicFocus={p.economicFocus:.2f})"
      ))
      result.totalEstimatedCost += 35

  # === LOW: Cyber attacks ===
  if currentEBP >= 5:
    if intelSnapshot.highValueTargets.len > 0:
      let targetSystem = intelSnapshot.highValueTargets[0]
      var targetOwner: HouseId = HouseId("")
      for (systemId, owner) in intelSnapshot.knownEnemyColonies:
        if systemId == targetSystem:
          targetOwner = owner
          break

      if targetOwner != HouseId(""):
        result.requirements.add(EspionageRequirement(
          requirementType: EspionageRequirementType.Operation,
          priority: RequirementPriority.Low,
          targetHouse: some(targetOwner),
          operation: some(esp_types.EspionageAction.CyberAttack),
          targetSystem: some(targetSystem), # Set target system for system-specific operation
          estimatedCost: 30,  # Cyber attack cost estimate
          reason: &"Cyber attack on {targetOwner} system {targetSystem}"
        ))
        result.totalEstimatedCost += 30

  # === DEFERRED: Assassination (luxury operation) ===
  if currentEBP >= 10 and p.aggression > 0.8:
    # Only very aggressive AIs with high EBP attempt assassination
    if intelSnapshot.espionageOpportunities.len > 0:
      let targetHouse = intelSnapshot.espionageOpportunities[0]

      result.requirements.add(EspionageRequirement(
        requirementType: EspionageRequirementType.Operation,
        priority: RequirementPriority.Deferred,
        targetHouse: some(targetHouse),
        operation: some(esp_types.EspionageAction.Assassination),
        estimatedCost: 60,  # Assassination cost estimate (expensive)
        reason: &"Assassination attempt on {targetHouse} (luxury operation, aggression={p.aggression:.2f})"
      ))
      result.totalEstimatedCost += 60

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Drungarius: Generated {result.requirements.len} espionage requirements " &
          &"(total cost estimate: {result.totalEstimatedCost}PP)")

  return result

proc reprioritizeEspionageRequirements*(
  originalRequirements: EspionageRequirements,
  feedback: DrungariusFeedback
): EspionageRequirements =
  ## Reprioritize unfulfilled espionage requirements based on Treasurer feedback
  ## Pattern: Critical stays, High→Medium, Medium→Low, drop Low/Deferred

  result = EspionageRequirements(
    requirements: @[],
    totalEstimatedCost: 0,
    generatedTurn: originalRequirements.generatedTurn,
    iteration: originalRequirements.iteration + 1
  )

  if feedback.unfulfilledRequirements.len == 0:
    # All requirements fulfilled
    result.requirements = originalRequirements.requirements
    result.totalEstimatedCost = originalRequirements.totalEstimatedCost
    return result

  logInfo(LogCategory.lcAI,
          &"Drungarius: Reprioritizing {feedback.unfulfilledRequirements.len} unfulfilled espionage requirements")

  # Keep fulfilled requirements unchanged
  for req in feedback.fulfilledRequirements:
    result.requirements.add(req)
    result.totalEstimatedCost += req.estimatedCost

  # Reprioritize unfulfilled requirements
  for req in feedback.unfulfilledRequirements:
    var adjustedReq = req
    case req.priority
    of RequirementPriority.Critical:
      # Keep Critical (EBP/CIP investment is critical early game)
      adjustedReq.priority = RequirementPriority.Critical
      adjustedReq.reason &= " [CRITICAL: Budget insufficient]"
    of RequirementPriority.High:
      adjustedReq.priority = RequirementPriority.Medium
      adjustedReq.reason &= " [Downgraded from High]"
    of RequirementPriority.Medium:
      adjustedReq.priority = RequirementPriority.Low
      adjustedReq.reason &= " [Downgraded from Medium]"
    of RequirementPriority.Low:
      # Drop Low operations
      logDebug(LogCategory.lcAI, &"Drungarius: Dropping Low priority operation: {req.reason}")
      continue
    of RequirementPriority.Deferred:
      # Already deferred, drop
      continue

    result.requirements.add(adjustedReq)
    result.totalEstimatedCost += adjustedReq.estimatedCost

  logInfo(LogCategory.lcAI,
          &"Drungarius: Reprioritized to {result.requirements.len} requirements " &
          &"(iteration {result.iteration})")

  return result
