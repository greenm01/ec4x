## Drungarius Espionage Requirements Module
##
## Byzantine Imperial Drungarius - Espionage Requirements Generation
##
## Generates espionage requirements with priorities for Basileus mediation
## Includes EBP/CIP investment and operation requirements

import std/[options, strformat, tables, algorithm, sets]
import ../../../common/types/core
import ../../../engine/[gamestate, fog_of_war, logger]
import ../../../engine/espionage/types as esp_types # For EspionageAction
import ../../../common/types/diplomacy as dip_types # For DiplomaticState
import ../controller_types
import ../shared/intelligence_types  # For IntelligenceSnapshot
import ../../common/types as ai_types
import ../goap/core/types # For GoalType
import ../goap/integration/plan_tracking # For PlanTracker, PlanStatus
import ../config  # For globalRBAConfig
import ./reconnaissance/[requirements as recon_req, deployment as recon_deploy]

# =============================================================================
# Phase 5.1: Multi-Factor Espionage Target Scoring
# =============================================================================

type
  EspionageTargetScore = object
    ## Scored espionage target with multi-factor analysis
    houseId: HouseId
    score: float
    techValue: float      # Steal research from tech leaders
    economicValue: float  # Sabotage high producers
    militaryThreat: float # Gather intel on strong enemies
    ciWeakness: float     # Target houses with low counter-intel
    diplomaticWeight: float # Prioritize enemies over neutrals

proc scoreEspionageTarget*(
  controller: AIController,
  targetHouse: HouseId,
  ownHouse: HouseId,
  intelSnapshot: IntelligenceSnapshot,
  filtered: FilteredGameState,
  personality: ai_types.AIPersonality,
  currentAct: GameAct
): EspionageTargetScore =
  ## Phase 5.1: Score espionage target based on multiple strategic factors
  ## Higher score = more valuable target for espionage operations

  result.houseId = targetHouse
  result.score = 0.0
  let cfg = controller.rbaConfig.drungarius_requirements

  # 1. Tech Value: Target houses ahead in tech (steal research)
  result.techValue = 0.0
  if intelSnapshot.research.enemyTechLevels.hasKey(targetHouse):
    let enemyTech = intelSnapshot.research.enemyTechLevels[targetHouse]
    # Sum tech levels across all fields
    var totalEnemyTech = 0
    for field, level in enemyTech.techLevels:
      totalEnemyTech += level

    # Compare to our tech (rough proxy: assume we're around Act-appropriate level)
    # Configuration from config/rba.toml [drungarius]
    let ourTechEstimate = case currentAct
      of ai_types.GameAct.Act1_LandGrab: controller.rbaConfig.drungarius.research_budget_act1 * 5  # ~15 (3 per field)
      of ai_types.GameAct.Act2_RisingTensions: controller.rbaConfig.drungarius.research_budget_act2 * 3 + 4  # ~25 (5 per field)
      of ai_types.GameAct.Act3_TotalWar: controller.rbaConfig.drungarius.research_budget_act3 * 3 + 5  # ~35 (7 per field)
      of ai_types.GameAct.Act4_Endgame: controller.rbaConfig.drungarius.research_budget_act4 * 3  # ~45 (9 per field)

    if totalEnemyTech > ourTechEstimate:
      result.techValue = float(totalEnemyTech - ourTechEstimate) / cfg.tech_value_divisor

  # 2. Economic Value: Target high producers (sabotage priority)
  result.economicValue = 0.0
  if intelSnapshot.economic.enemyEconomicStrength.hasKey(targetHouse):
    let enemyEcon = intelSnapshot.economic.enemyEconomicStrength[targetHouse]
    result.economicValue = float(enemyEcon.estimatedTotalProduction) / cfg.economic_value_divisor

  # 3. Military Threat: Target strong militaries (need intel)
  result.militaryThreat = 0.0
  var enemyFleetCount = 0
  var enemyTotalStrength = 0
  for fleet in intelSnapshot.military.knownEnemyFleets:
    if fleet.owner == targetHouse:
      enemyFleetCount += 1
      enemyTotalStrength += fleet.estimatedStrength

  result.militaryThreat = float(enemyTotalStrength) / cfg.military_threat_divisor

  # 4. CI Weakness: Target houses with low counter-intel (easier operations)
  result.ciWeakness = 0.0
  if intelSnapshot.espionage.detectionRisks.hasKey(targetHouse):
    let risk = intelSnapshot.espionage.detectionRisks[targetHouse]
    case risk
    of DetectionRiskLevel.Unknown:
      result.ciWeakness = cfg.ci_weakness_unknown
    of DetectionRiskLevel.Low:
      result.ciWeakness = cfg.ci_weakness_low
    of DetectionRiskLevel.Moderate:
      result.ciWeakness = cfg.ci_weakness_moderate
    of DetectionRiskLevel.High:
      result.ciWeakness = cfg.ci_weakness_high
    of DetectionRiskLevel.Critical:
      result.ciWeakness = cfg.ci_weakness_critical
  else:
    result.ciWeakness = cfg.ci_weakness_default

  # 5. Diplomatic Weight: Prioritize enemies over neutrals
  result.diplomaticWeight = cfg.diplomatic_weight_neutral  # Base weight
  let dipKey = (ownHouse, targetHouse)
  if filtered.houseDiplomacy.hasKey(dipKey):
    let dipState = filtered.houseDiplomacy[dipKey]
    case dipState
    of dip_types.DiplomaticState.Enemy:
      result.diplomaticWeight = cfg.diplomatic_weight_enemy
    of dip_types.DiplomaticState.Hostile:
      result.diplomaticWeight = cfg.diplomatic_weight_hostile
    of dip_types.DiplomaticState.Neutral:
      result.diplomaticWeight = cfg.diplomatic_weight_neutral

  # Calculate weighted score based on personality
  # Aggressive personalities weight military threat higher
  # Economic personalities weight economic value higher
  # Risk-averse personalities weight CI weakness higher

  let aggressionWeight = personality.aggression
  let economicWeight = personality.economicFocus
  let riskWeight = 1.0 - personality.riskTolerance  # Low risk = prefer easy targets

  result.score =
    (result.techValue * cfg.score_weight_tech) +
    (result.economicValue * economicWeight * cfg.score_weight_economic) +
    (result.militaryThreat * aggressionWeight * cfg.score_weight_military) +
    (result.ciWeakness * riskWeight * cfg.score_weight_ci_weakness) +
    (result.diplomaticWeight * cfg.score_weight_diplomatic)

  return result

proc selectBestEspionageTargets*(
  controller: AIController,
  intelSnapshot: IntelligenceSnapshot,
  filtered: FilteredGameState,
  personality: ai_types.AIPersonality,
  currentAct: GameAct,
  maxTargets: int = 3
): seq[HouseId] =
  ## Phase 5.1: Select best espionage targets using multi-factor scoring
  ## Returns up to maxTargets houses sorted by score (best first)

  var scoredTargets: seq[EspionageTargetScore] = @[]

  # Score all known enemy houses
  var candidateHouses = initHashSet[HouseId]()
  for (systemId, owner) in intelSnapshot.knownEnemyColonies:
    if owner != filtered.viewingHouse:
      candidateHouses.incl(owner)

  for fleet in intelSnapshot.military.knownEnemyFleets:
    if fleet.owner != filtered.viewingHouse:
      candidateHouses.incl(fleet.owner)

  # Score each candidate
  for house in candidateHouses:
    let score = scoreEspionageTarget(
      controller, house, filtered.viewingHouse, intelSnapshot, filtered, personality, currentAct
    )
    scoredTargets.add(score)

  # Sort by score (highest first)
  scoredTargets.sort(proc(a, b: EspionageTargetScore): int =
    if a.score > b.score: -1
    elif a.score < b.score: 1
    else: 0
  )

  # Return top N targets
  result = @[]
  for i in 0 ..< min(maxTargets, scoredTargets.len):
    result.add(scoredTargets[i].houseId)
    logDebug(LogCategory.lcAI,
             &"Espionage target {i+1}: {scoredTargets[i].houseId} " &
             &"(score={scoredTargets[i].score:.1f}, tech={scoredTargets[i].techValue:.1f}, " &
             &"econ={scoredTargets[i].economicValue:.1f}, military={scoredTargets[i].militaryThreat:.1f}, " &
             &"ci={scoredTargets[i].ciWeakness:.1f}, diplo={scoredTargets[i].diplomaticWeight:.1f})")

  return result

# =============================================================================
# Phase 5.3: Economic Intelligence for Sabotage
# =============================================================================

type
  SabotageTarget = object
    ## Prioritized sabotage target with bottleneck analysis
    systemId: SystemId
    owner: HouseId
    score: float
    shipyardCount: int
    activeProjects: int
    productionValue: int
    reason: string

proc selectSabotageBottlenecks*(
  controller: AIController,
  intelSnapshot: IntelligenceSnapshot,
  maxTargets: int = 3
): seq[SabotageTarget] =
  ## Phase 5.3: Select sabotage targets based on economic bottlenecks
  ## Prioritizes shipyard concentrations and high-value infrastructure

  result = @[]
  var scoredTargets: seq[SabotageTarget] = @[]
  let cfg = controller.rbaConfig.drungarius_requirements

  # Analyze construction activity for shipyard concentrations
  for systemId, activity in intelSnapshot.economic.constructionActivity:
    # Find system owner
    var owner: HouseId = HouseId("")
    for (sysId, ownerHouse) in intelSnapshot.knownEnemyColonies:
      if sysId == systemId:
        owner = ownerHouse
        break

    if owner == HouseId(""):
      continue  # Unknown owner, skip

    # Calculate bottleneck score
    let shipyardWeight = activity.shipyardCount * cfg.sabotage_shipyard_weight
    let projectWeight = activity.constructionQueue.len * cfg.sabotage_project_weight
    let activityWeight = case activity.activityLevel
      of ConstructionActivityLevel.VeryHigh: cfg.sabotage_activity_very_high
      of ConstructionActivityLevel.High: cfg.sabotage_activity_high
      of ConstructionActivityLevel.Moderate: cfg.sabotage_activity_moderate
      of ConstructionActivityLevel.Low: cfg.sabotage_activity_low
      else: 0

    # Infrastructure value (IU and starbases)
    let infrastructureValue = activity.observedInfrastructure * cfg.sabotage_infrastructure_unit_value + activity.observedStarbases * cfg.sabotage_starbase_value

    # Total score
    let totalScore = float(shipyardWeight + projectWeight + activityWeight + infrastructureValue)

    if totalScore > 0:
      scoredTargets.add(SabotageTarget(
        systemId: systemId,
        owner: owner,
        score: totalScore,
        shipyardCount: activity.shipyardCount,
        activeProjects: activity.constructionQueue.len,
        productionValue: activity.observedInfrastructure,
        reason: if activity.shipyardCount >= cfg.sabotage_shipyard_concentration:
          &"Shipyard concentration ({activity.shipyardCount} yards)"
        elif activity.activityLevel == ConstructionActivityLevel.VeryHigh:
          "Very high construction activity"
        else:
          "High-value infrastructure target"
      ))

  # Sort by score (highest first)
  scoredTargets.sort(proc(a, b: SabotageTarget): int =
    if a.score > b.score: -1
    elif a.score < b.score: 1
    else: 0
  )

  # Return top N targets
  for i in 0 ..< min(maxTargets, scoredTargets.len):
    result.add(scoredTargets[i])
    logDebug(LogCategory.lcAI,
             &"Sabotage target {i+1}: {scoredTargets[i].systemId} ({scoredTargets[i].owner}) " &
             &"score={scoredTargets[i].score:.0f} - {scoredTargets[i].reason}")

  return result

# =============================================================================
# Phase 5.2: Counter-Intelligence Assessment
# =============================================================================

proc assessCounterIntelligenceNeeds*(
  controller: AIController,
  filtered: FilteredGameState,
  intelSnapshot: IntelligenceSnapshot,
  currentCIP: int,
  targetCIP: int
): seq[EspionageRequirement] =
  ## Phase 5.2: Assess counter-intelligence needs based on detected threats
  ## Returns CIP investment and counter-intel sweep requirements

  result = @[]
  let cfg = controller.rbaConfig.drungarius_requirements

  # Track detected espionage activity by house
  var espionageActivityByHouse = initTable[HouseId, int]()

  # Check for detected espionage operations from intelligence
  if intelSnapshot.espionage.detectionRisks.len > 0:
    # Houses with detection risks indicate they're running operations
    for houseId, risk in intelSnapshot.espionage.detectionRisks:
      case risk
      of DetectionRiskLevel.High, DetectionRiskLevel.Critical:
        # High/Critical risk = we're detecting heavy espionage
        if not espionageActivityByHouse.hasKey(houseId):
          espionageActivityByHouse[houseId] = 0
        espionageActivityByHouse[houseId] += cfg.ci_detection_heavy_activity
      of DetectionRiskLevel.Moderate:
        if not espionageActivityByHouse.hasKey(houseId):
          espionageActivityByHouse[houseId] = 0
        espionageActivityByHouse[houseId] += cfg.ci_detection_moderate_activity
      else:
        discard

  # Calculate total espionage threat
  var totalThreat = 0
  for house, activity in espionageActivityByHouse:
    totalThreat += activity

  # If significant espionage threat detected, boost CIP investment
  if totalThreat >= cfg.ci_total_threat_threshold and currentCIP < (targetCIP + cfg.ci_emergency_cip_boost_max):
    let cipBoost = min(cfg.ci_emergency_cip_boost_max, (targetCIP + cfg.ci_emergency_cip_boost_max) - currentCIP)
    let investmentCost = cipBoost * cfg.ci_pp_per_point

    result.add(EspionageRequirement(
      requirementType: EspionageRequirementType.CIPInvestment,
      priority: RequirementPriority.High,
      targetHouse: none(HouseId),
      operation: none(esp_types.EspionageAction),
      estimatedCost: investmentCost,
      reason: &"Emergency CIP boost (detected {totalThreat} espionage threats)"
    ))

    logInfo(LogCategory.lcAI,
            &"Counter-Intel: Detected heavy espionage activity ({totalThreat} threats), " &
            &"boosting CIP by {cipBoost} points")

  # Generate counter-intel sweeps for each active threat
  for houseId, activity in espionageActivityByHouse:
    if activity >= cfg.ci_significant_activity:
      result.add(EspionageRequirement(
        requirementType: EspionageRequirementType.Operation,
        priority: RequirementPriority.High,
        targetHouse: none(HouseId),  # Counter-intel is defensive
        operation: some(esp_types.EspionageAction.CounterIntelSweep),
        estimatedCost: cfg.cost_counter_intel_sweep,
        reason: &"Counter-intel sweep vs {houseId} espionage (activity level: {activity})"
      ))

      logInfo(LogCategory.lcAI,
              &"Counter-Intel: Scheduling sweep against {houseId} operations")

  return result

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
  let cfg = controller.rbaConfig.drungarius_requirements

  # Check if "MaintainPrestige" GOAP goal is active (Gap 6)
  # TODO: Re-enable once goapPlanTracker is integrated into AIController
  let isMaintainPrestigeActive = false
  # let isMaintainPrestigeActive = controller.goapPlanTracker.activePlans.anyIt(
  #   it.status == PlanStatus.Active and it.plan.goal.goalType == GoalType.MaintainPrestige
  # )
  let prestigePenaltyThresholdRatio = cfg.prestige_penalty_threshold_ratio
  let ppPerEBP_CIP = cfg.ci_pp_per_point

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Drungarius: Generating espionage requirements " &
          &"(EBP={currentEBP}, CIP={currentCIP}, Act={currentAct}, MaintainPrestigeActive={isMaintainPrestigeActive})")

  # Phase 5.1: Select best espionage targets using multi-factor scoring
  let bestTargets = selectBestEspionageTargets(controller, intelSnapshot, filtered, p, currentAct, maxTargets = 3)

  # === EBP/CIP Investment Target Levels by Act ===
  # Configuration from config/rba.toml [drungarius]
  var targetEBP = controller.rbaConfig.drungarius.espionage_budget_act1 # Use var for modification
  var targetCIP = controller.rbaConfig.drungarius.research_budget_act1

  case currentAct
  of ai_types.GameAct.Act1_LandGrab:
    targetEBP = controller.rbaConfig.drungarius.espionage_budget_act1
    targetCIP = controller.rbaConfig.drungarius.research_budget_act1
  of ai_types.GameAct.Act2_RisingTensions:
    targetEBP = controller.rbaConfig.drungarius.espionage_budget_act2
    targetCIP = controller.rbaConfig.drungarius.research_budget_act2
  of ai_types.GameAct.Act3_TotalWar:
    targetEBP = controller.rbaConfig.drungarius.espionage_budget_act3 + cfg.act3_war_ebp_bonus
    targetCIP = controller.rbaConfig.drungarius.research_budget_act3 + cfg.act3_war_cip_bonus
  of ai_types.GameAct.Act4_Endgame:
    targetEBP = controller.rbaConfig.drungarius.espionage_budget_act4
    targetCIP = controller.rbaConfig.drungarius.research_budget_act4

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
    let priority = if currentEBP < cfg.ebp_critical_threshold:
      RequirementPriority.Critical  # Very low EBP = critical
    elif ebpGap >= cfg.ebp_high_gap_threshold:
      RequirementPriority.High  # Significant gap
    else:
      RequirementPriority.Medium

    let investmentCost = ebpGap * ppPerEBP_CIP

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
    let priority = if cipGap >= cfg.cip_high_gap_threshold:
      RequirementPriority.High  # Significant gap
    else:
      RequirementPriority.Medium

    let investmentCost = cipGap * ppPerEBP_CIP

    result.requirements.add(EspionageRequirement(
      requirementType: EspionageRequirementType.CIPInvestment,
      priority: priority,
      targetHouse: none(HouseId),
      operation: none(esp_types.EspionageAction),
      estimatedCost: investmentCost,
      reason: &"CIP investment (current: {currentCIP}, target: {targetCIP} for {currentAct})"
    ))
    result.totalEstimatedCost += investmentCost

  # === MEDIUM/HIGH: Phase 5.2 - Intelligence-Driven Counter-Intelligence ===
  # Use intelligence to detect espionage threats and respond
  let ciRequirements = assessCounterIntelligenceNeeds(controller, filtered, intelSnapshot, currentCIP, targetCIP)
  for req in ciRequirements:
    result.requirements.add(req)
    result.totalEstimatedCost += req.estimatedCost

  # Fallback: Basic risk-based sweeps if no threats detected
  if ciRequirements.len == 0:
    if currentCIP < targetCIP:
      let priority = if currentCIP < cfg.cip_high_priority_threshold: RequirementPriority.High else: RequirementPriority.Medium
      let cost = cfg.cost_counter_intel_sweep

      result.requirements.add(EspionageRequirement(
        requirementType: EspionageRequirementType.Operation,
        priority: priority,
        targetHouse: none(HouseId),
        operation: some(esp_types.EspionageAction.CounterIntelSweep),
        estimatedCost: cost,
        reason: &"Preventive Counter-Intelligence Sweep (CIP: {currentCIP}/{targetCIP})"
      ))
      result.totalEstimatedCost += cost
    elif p.riskTolerance < cfg.risk_tolerance_ci_maintenance and currentCIP < cfg.cip_risk_averse_threshold:
      # Risk-averse personalities maintain CI posture
      let cost = cfg.cost_counter_intel_sweep
      result.requirements.add(EspionageRequirement(
        requirementType: EspionageRequirementType.Operation,
        priority: RequirementPriority.Medium,
        targetHouse: none(HouseId),
        operation: some(esp_types.EspionageAction.CounterIntelSweep),
        estimatedCost: cost,
        reason: &"Maintain CI posture (risk tolerance: {p.riskTolerance:.2f})"
      ))
      result.totalEstimatedCost += cost

  # === HIGH: Phase 5.3 - Economic Bottleneck Sabotage ===
  # Target shipyard concentrations and high-value infrastructure
  if currentEBP >= cfg.req_ebp_sabotage_bottleneck:
    let bottlenecks = selectSabotageBottlenecks(controller, intelSnapshot, maxTargets = 2)

    if bottlenecks.len > 0:
      # Target top bottleneck with high-priority sabotage
      let primary = bottlenecks[0]
      result.requirements.add(EspionageRequirement(
        requirementType: EspionageRequirementType.Operation,
        priority: RequirementPriority.High,
        targetHouse: some(primary.owner),
        operation: some(esp_types.EspionageAction.SabotageHigh),
        targetSystem: some(primary.systemId),
        estimatedCost: cfg.cost_sabotage,
        reason: &"Economic bottleneck sabotage - {primary.systemId}: {primary.reason}"
      ))
      result.totalEstimatedCost += cfg.cost_sabotage

      logInfo(LogCategory.lcAI,
              &"{controller.houseId} Drungarius: Targeting bottleneck {primary.systemId} " &
              &"({primary.shipyardCount} shipyards, score={primary.score:.0f})")

      # If aggressive and multiple bottlenecks, add secondary target
      if bottlenecks.len >= 2 and p.aggression > cfg.aggression_secondary_sabotage and currentEBP >= cfg.req_ebp_secondary_sabotage:
        let secondary = bottlenecks[1]
        result.requirements.add(EspionageRequirement(
          requirementType: EspionageRequirementType.Operation,
          priority: RequirementPriority.Medium,
          targetHouse: some(secondary.owner),
          operation: some(esp_types.EspionageAction.SabotageHigh),
          targetSystem: some(secondary.systemId),
          estimatedCost: cfg.cost_sabotage,
          reason: &"Secondary bottleneck - {secondary.systemId}: {secondary.reason}"
        ))
        result.totalEstimatedCost += cfg.cost_sabotage
    elif intelSnapshot.highValueTargets.len > 0:
      # Fallback: Use legacy high-value target list if no bottlenecks identified
      let targetSystem = intelSnapshot.highValueTargets[0]
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
          targetSystem: some(targetSystem),
          estimatedCost: cfg.cost_sabotage,
          reason: &"High-value target - system {targetSystem}"
        ))
        result.totalEstimatedCost += cfg.cost_sabotage

  # === HIGH: Operations against enemies ===
  # Phase 5.1: Use multi-factor scored targets instead of simple list
  if currentEBP >= cfg.req_ebp_operations_vs_enemies and bestTargets.len > 0:
    # Target best-scored house
    let targetHouse = bestTargets[0]

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
      estimatedCost: cfg.cost_intelligence_theft,
      reason: &"Intelligence theft from {targetHouse} (multi-factor scoring: best target){detectionRiskNote}"
    ))
    result.totalEstimatedCost += cfg.cost_intelligence_theft

  # === MEDIUM: Disinformation operations ===
  if currentEBP >= cfg.req_ebp_disinformation and p.aggression > cfg.aggression_disinformation:
    # Phase 5.1: Aggressive AIs target military threats with disinformation
    if bestTargets.len > 0:
      let targetHouse = bestTargets[0]  # Best target (likely military threat)

      result.requirements.add(EspionageRequirement(
        requirementType: EspionageRequirementType.Operation,
        priority: RequirementPriority.Medium,
        targetHouse: some(targetHouse),
        operation: some(esp_types.EspionageAction.PlantDisinformation),
        estimatedCost: cfg.cost_disinformation,
        reason: &"Plant disinformation against {targetHouse} (aggression={p.aggression:.2f}, scored target)"
      ))
      result.totalEstimatedCost += cfg.cost_disinformation

  # === MEDIUM: Economic manipulation ===
  if currentEBP >= cfg.req_ebp_economic_manipulation and p.economicFocus > controller.rbaConfig.drungarius_operations.economic_focus_manipulation:
    # Phase 5.1: Economic-focused AIs target high producers
    if bestTargets.len > 0:
      # For economic ops, prefer second-best target if available (diversify)
      let targetHouse = if bestTargets.len >= 2: bestTargets[1] else: bestTargets[0]

      result.requirements.add(EspionageRequirement(
        requirementType: EspionageRequirementType.Operation,
        priority: RequirementPriority.Medium,
        targetHouse: some(targetHouse),
        operation: some(esp_types.EspionageAction.EconomicManipulation),
        estimatedCost: cfg.cost_economic_manipulation,
        reason: &"Economic manipulation against {targetHouse} (economicFocus={p.economicFocus:.2f}, scored target)"
      ))
      result.totalEstimatedCost += cfg.cost_economic_manipulation

  # === LOW: Cyber attacks ===
  if currentEBP >= cfg.req_ebp_cyber_attack:
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
          estimatedCost: cfg.cost_cyber_attack,
          reason: &"Cyber attack on {targetOwner} system {targetSystem}"
        ))
        result.totalEstimatedCost += cfg.cost_cyber_attack

  # === DEFERRED: Assassination (luxury operation) ===
  if currentEBP >= cfg.req_ebp_assassination and p.aggression > cfg.aggression_assassination:
    # Phase 5.1: Very aggressive AIs target most threatening enemy
    if bestTargets.len > 0:
      let targetHouse = bestTargets[0]  # Best target (highest threat)

      result.requirements.add(EspionageRequirement(
        requirementType: EspionageRequirementType.Operation,
        priority: RequirementPriority.Deferred,
        targetHouse: some(targetHouse),
        operation: some(esp_types.EspionageAction.Assassination),
        estimatedCost: cfg.cost_assassination,
        reason: &"Assassination attempt on {targetHouse} (luxury operation, aggression={p.aggression:.2f}, highest-scored threat)"
      ))
      result.totalEstimatedCost += cfg.cost_assassination

  # === Scout Requirements and Deployment ===
  # Drungarius owns scout pipeline: identify needs → build scouts → deploy
  # scouts
  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Drungarius: Assessing reconnaissance needs")

  result.scoutBuildRequirements = recon_req.assessScoutGaps(
    filtered, controller, currentAct, intelSnapshot
  )
  result.reconnaissanceOrders = recon_deploy.generateScoutOrders(
    filtered, controller, intelSnapshot
  )

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Drungarius: Reconnaissance planning - " &
          &"{result.scoutBuildRequirements.len} scout build reqs, " &
          &"{result.reconnaissanceOrders.len} reconnaissance orders")

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
