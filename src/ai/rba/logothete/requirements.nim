## Logothete Research Requirements Module
##
## Byzantine Imperial Logothete - Research Requirements Generation
##
## Generates research requirements with priorities for Basileus mediation
## Intelligence-driven priorities (enemy tech, tech gaps, strategic needs)

import std/[tables, options, strformat]
import ../../../common/types/tech
import ../../../engine/[gamestate, fog_of_war, logger]
import ../../../engine/research/types as res_types
import ../../../engine/research/advancement  # For max tech level constants
import ../controller_types
import ../shared/intelligence_types  # For IntelligenceSnapshot
import ../../common/types as ai_types
import ./counter_tech  # Phase 6.2: Counter-tech module

proc generateResearchRequirements*(
  controller: AIController,
  filtered: FilteredGameState,
  intelSnapshot: IntelligenceSnapshot,
  currentAct: GameAct
): ResearchRequirements =
  ## Generate research requirements with intelligence-driven priorities
  ##
  ## Priority tiers:
  ## - Critical: Early CST unlocks (0-2), critical tech gaps vs enemies
  ## - High: Mid CST (3-4), counter-tech (enemy has advanced weapons/shields)
  ## - Medium: Advanced CST (5+), economic techs
  ## - Low: Luxury techs (Cloaking, Advanced Carrier Ops)
  ## - Deferred: Over-investment in already strong areas

  result.requirements = @[]
  result.totalEstimatedCost = 0
  result.generatedTurn = filtered.turn
  result.iteration = 0

  let p = controller.personality
  let currentEL = filtered.ownHouse.techTree.levels.economicLevel
  let currentSL = filtered.ownHouse.techTree.levels.scienceLevel
  let currentCST = filtered.ownHouse.techTree.levels.constructionTech

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Logothete: Generating research requirements " &
          &"(EL={currentEL}, SL={currentSL}, CST={currentCST}, Act={currentAct})")

  # === CRITICAL: Early CST (0-2) - Gates all unit production ===
  if currentCST < 3:
    let priority = if currentCST <= 1:
      RequirementPriority.Critical  # CST 0-1: absolutely critical
    else:
      RequirementPriority.High  # CST 2: high priority

    result.requirements.add(ResearchRequirement(
      techField: some(TechField.ConstructionTech),
      priority: priority,
      estimatedCost: 200,  # Rough estimate for early CST
      reason: &"Early CST unlock (current: {currentCST}) - gates unit production",
      expectedBenefit: &"Unlocks new ship classes and facilities"
    ))
    result.totalEstimatedCost += 200

  # === CRITICAL: EL/SL for early game economic foundation ===
  if currentEL < 3 or currentSL < 2:
    if currentEL < 3:
      result.requirements.add(ResearchRequirement(
        techField: none(TechField),  # ERP
        priority: RequirementPriority.Critical,
        estimatedCost: 150,
        reason: &"Early Economic Level (current: {currentEL}) - critical for PP generation",
        expectedBenefit: "Increases production capacity and efficiency"
      ))
      result.totalEstimatedCost += 150

    if currentSL < 2:
      result.requirements.add(ResearchRequirement(
        techField: none(TechField),  # SRP
        priority: RequirementPriority.Critical,
        estimatedCost: 150,
        reason: &"Early Science Level (current: {currentSL}) - enables tech progress",
        expectedBenefit: "Accelerates research and unlocks advanced techs"
      ))
      result.totalEstimatedCost += 150

  # === HIGH: Mid-game CST (3-4) - Unlocks advanced units ===
  if currentCST >= 3 and currentCST < 5:
    result.requirements.add(ResearchRequirement(
      techField: some(TechField.ConstructionTech),
      priority: RequirementPriority.High,
      estimatedCost: 300,
      reason: &"Mid-game CST (current: {currentCST}) - unlocks Cruisers/Dreadnoughts",
      expectedBenefit: "Access to advanced combat ships"
    ))
    result.totalEstimatedCost += 300

  # === PHASE 6.1: Competitive Research Strategy ===
  # Use intelligence to identify tech gaps and advantages

  # 1. Urgent Research Needs: From intelligence analysis (Phase 2.1)
  if intelSnapshot.research.urgentResearchNeeds.len > 0:
    for need in intelSnapshot.research.urgentResearchNeeds:
      # Use priority from intelligence analysis
      result.requirements.add(ResearchRequirement(
        techField: some(need.field),
        priority: need.priority,
        estimatedCost: need.estimatedTurns * 50,  # Rough PP estimate
        reason: need.reason,
        expectedBenefit: &"Close gap in {need.field} (target: level {need.targetLevel})"
      ))
      result.totalEstimatedCost += need.estimatedTurns * 50

      logInfo(LogCategory.lcAI,
              &"{controller.houseId} Logothete: {need.priority} research - " &
              &"{need.field} (reason: {need.reason})")

  # 2. Tech Gaps: Close any identified gaps
  if intelSnapshot.research.techGaps.len > 0:
    for field in intelSnapshot.research.techGaps:
      # Don't duplicate if already in urgent needs
      var alreadyRequested = false
      for req in result.requirements:
        if req.techField.isSome and req.techField.get() == field:
          alreadyRequested = true
          break

      if not alreadyRequested:
        result.requirements.add(ResearchRequirement(
          techField: some(field),
          priority: RequirementPriority.High,
          estimatedCost: 250,
          reason: &"Tech gap identified - we lag in {field}",
          expectedBenefit: &"Catch up with enemy capabilities in {field}"
        ))
        result.totalEstimatedCost += 250

        logDebug(LogCategory.lcAI,
                 &"{controller.houseId} Logothete: Addressing tech gap - {field}")

  # 3. Tech Advantages: Exploit existing leads
  if intelSnapshot.research.techAdvantages.len > 0:
    for field in intelSnapshot.research.techAdvantages:
      # Don't duplicate existing requirements
      var alreadyRequested = false
      for req in result.requirements:
        if req.techField.isSome and req.techField.get() == field:
          alreadyRequested = true
          break

      if not alreadyRequested:
        result.requirements.add(ResearchRequirement(
          techField: some(field),
          priority: RequirementPriority.Medium,
          estimatedCost: 250,
          reason: &"Exploit tech advantage in {field}",
          expectedBenefit: &"Maintain technological superiority in {field}"
        ))
        result.totalEstimatedCost += 250

        logDebug(LogCategory.lcAI,
                 &"{controller.houseId} Logothete: Exploiting advantage - {field}")

  # 4. Threat-Responsive Research: Combat tech vs active threats
  if intelSnapshot.military.threatsByColony.len > 0:
    # Count critical/high threats
    var criticalThreats = 0
    for systemId, threat in intelSnapshot.military.threatsByColony:
      if threat.level in {intelligence_types.ThreatLevel.tlCritical, intelligence_types.ThreatLevel.tlHigh}:
        criticalThreats += 1

    # If multiple critical threats, prioritize weapons for combat effectiveness
    if criticalThreats >= 2:
      let currentWeapons = filtered.ownHouse.techTree.levels.weaponsTech
      if currentWeapons < maxWeaponsTech:
        # Don't duplicate if already requested
        var alreadyRequested = false
        for req in result.requirements:
          if req.techField.isSome and req.techField.get() == TechField.WeaponsTech:
            alreadyRequested = true
            break

        if not alreadyRequested:
          result.requirements.add(ResearchRequirement(
            techField: some(TechField.WeaponsTech),
            priority: RequirementPriority.High,
            estimatedCost: 250,
            reason: &"Combat weapons (under attack: {criticalThreats} critical threats)",
            expectedBenefit: "Improved fleet combat power vs attacking enemies"
          ))
          result.totalEstimatedCost += 250

          logInfo(LogCategory.lcAI,
                  &"{controller.houseId} Logothete: Prioritizing weapons - " &
                  &"{criticalThreats} critical threats detected")

  # 5. Phase 6.2: Counter-Tech Against Major Enemies
  # Generate counter-tech recommendations for top threats
  var enemyCounterTech = initTable[HouseId, int]()  # Track enemies we're countering

  for houseId, techLevels in intelSnapshot.research.enemyTechLevels:
    # Get counter-tech recommendations
    let recommendations = selectCounterTech(
      houseId, techLevels, filtered.ownHouse.techTree, intelSnapshot
    )

    # Add top 2 recommendations per enemy (avoid over-targeting single enemy)
    var added = 0
    for rec in recommendations:
      if added >= 2:
        break

      # Check if not already requested
      var alreadyRequested = false
      for req in result.requirements:
        if req.techField.isSome and req.techField.get() == rec.field:
          alreadyRequested = true
          break

      if not alreadyRequested:
        # Convert counter-tech priority (0.0-1.0) to RequirementPriority
        let reqPriority = if rec.priority >= 0.9:
          RequirementPriority.Critical
        elif rec.priority >= 0.7:
          RequirementPriority.High
        else:
          RequirementPriority.Medium

        result.requirements.add(ResearchRequirement(
          techField: some(rec.field),
          priority: reqPriority,
          estimatedCost: 250,
          reason: &"Counter-tech vs {houseId}: {rec.reason}",
          expectedBenefit: &"Neutralize enemy advantage in {rec.field}"
        ))
        result.totalEstimatedCost += 250
        added += 1

        logDebug(LogCategory.lcAI,
                 &"{controller.houseId} Logothete: Counter-tech - {rec.field} vs {houseId} " &
                 &"(priority={rec.priority:.2f})")

    if added > 0:
      enemyCounterTech[houseId] = added

  if enemyCounterTech.len > 0:
    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Logothete: Generated counter-tech vs {enemyCounterTech.len} enemies")

  # === HIGH: Weapons Tech (personality-driven, lower priority than gaps) ===
  if p.aggression > 0.5 or intelSnapshot.threatAssessment.len > 0:
    let currentWeapons = filtered.ownHouse.techTree.levels.weaponsTech
    if currentWeapons < maxWeaponsTech:
      let priority = if intelSnapshot.threatAssessment.len > 0:
        RequirementPriority.High  # Under threat = prioritize weapons
      else:
        RequirementPriority.Medium  # Aggressive but not threatened

      result.requirements.add(ResearchRequirement(
        techField: some(TechField.WeaponsTech),
        priority: priority,
        estimatedCost: 250,
        reason: &"Weapons advancement (aggression={p.aggression:.2f}, threats={intelSnapshot.threatAssessment.len})",
        expectedBenefit: "Increased combat effectiveness and ship damage"
      ))
      result.totalEstimatedCost += 250

  # === HIGH: Fighter Doctrine (always valuable for fleet combat) ===
  let currentFD = filtered.ownHouse.techTree.levels.fighterDoctrine
  if currentFD < maxFighterDoctrine:
    # Fighter Doctrine is universally important (fighters are efficient)
    result.requirements.add(ResearchRequirement(
      techField: some(TechField.FighterDoctrine),
      priority: RequirementPriority.High,
      estimatedCost: 200,
      reason: &"Fighter Doctrine (current: {currentFD}) - universally effective units",
      expectedBenefit: "More fighters per carrier, improved fighter combat"
    ))
    result.totalEstimatedCost += 200

  # === MEDIUM: Economic growth (EL/SL continued investment) ===
  if currentEL < maxEconomicLevel:
    let priority = if p.economicFocus > 0.6:
      RequirementPriority.High  # Economic personality = high priority
    else:
      RequirementPriority.Medium

    result.requirements.add(ResearchRequirement(
      techField: none(TechField),  # ERP
      priority: priority,
      estimatedCost: 200,
      reason: &"Economic Level growth (current: {currentEL}, focus={p.economicFocus:.2f})",
      expectedBenefit: "Increased PP generation and colony productivity"
    ))
    result.totalEstimatedCost += 200

  if currentSL < maxScienceLevel:
    result.requirements.add(ResearchRequirement(
      techField: none(TechField),  # SRP
      priority: RequirementPriority.Medium,
      estimatedCost: 200,
      reason: &"Science Level growth (current: {currentSL})",
      expectedBenefit: "Faster research progress across all fields"
    ))
    result.totalEstimatedCost += 200

  # === MEDIUM: Terraforming (economic personality priority) ===
  if p.economicFocus > 0.6:
    let currentTerra = filtered.ownHouse.techTree.levels.terraformingTech
    if currentTerra < maxTerraformingTech:
      result.requirements.add(ResearchRequirement(
        techField: some(TechField.TerraformingTech),
        priority: RequirementPriority.Medium,
        estimatedCost: 150,
        reason: &"Terraforming Tech (economicFocus={p.economicFocus:.2f})",
        expectedBenefit: "Improved colony habitability and population growth"
      ))
      result.totalEstimatedCost += 150

  # === MEDIUM: Electronic Intelligence (espionage support) ===
  let currentEI = filtered.ownHouse.techTree.levels.electronicIntelligence
  if currentEI < maxElectronicIntelligence:
    result.requirements.add(ResearchRequirement(
      techField: some(TechField.ElectronicIntelligence),
      priority: RequirementPriority.Medium,
      estimatedCost: 150,
      reason: &"Electronic Intelligence (current: {currentEI}) - supports espionage",
      expectedBenefit: "Improved espionage success rates and intelligence gathering"
    ))
    result.totalEstimatedCost += 150

  # === LOW: Shield Tech (defensive tech, lower priority than offense) ===
  let currentShield = filtered.ownHouse.techTree.levels.shieldTech
  if currentShield < maxShieldTech:
    result.requirements.add(ResearchRequirement(
      techField: some(TechField.ShieldTech),
      priority: RequirementPriority.Low,
      estimatedCost: 150,
      reason: &"Shield Tech (current: {currentShield}) - defensive improvement",
      expectedBenefit: "Increased ship survivability"
    ))
    result.totalEstimatedCost += 150

  # === LOW: Counter-Intelligence (defensive espionage) ===
  let currentCI = filtered.ownHouse.techTree.levels.counterIntelligence
  if currentCI < maxCounterIntelligence:
    result.requirements.add(ResearchRequirement(
      techField: some(TechField.CounterIntelligence),
      priority: RequirementPriority.Low,
      estimatedCost: 150,
      reason: &"Counter-Intelligence (current: {currentCI}) - espionage defense",
      expectedBenefit: "Reduces enemy espionage success rates"
    ))
    result.totalEstimatedCost += 150

  # === LOW: Cloaking Tech (luxury tech for aggressive personalities) ===
  if p.aggression > 0.7:
    let currentCloak = filtered.ownHouse.techTree.levels.cloakingTech
    if currentCloak < maxCloakingTech:
      result.requirements.add(ResearchRequirement(
        techField: some(TechField.CloakingTech),
        priority: RequirementPriority.Low,
        estimatedCost: 200,
        reason: &"Cloaking Tech (aggression={p.aggression:.2f}) - stealth warfare",
        expectedBenefit: "Enables cloaked ship construction and operations"
      ))
      result.totalEstimatedCost += 200

  # === LOW: Advanced Carrier Ops (late-game luxury) ===
  if currentCST >= 5:  # Only relevant when we have advanced carriers
    let currentACO = filtered.ownHouse.techTree.levels.advancedCarrierOps
    if currentACO < maxAdvancedCarrierOps:
      result.requirements.add(ResearchRequirement(
        techField: some(TechField.AdvancedCarrierOps),
        priority: RequirementPriority.Low,
        estimatedCost: 200,
        reason: &"Advanced Carrier Ops (CST={currentCST}) - late-game enhancement",
        expectedBenefit: "Improved carrier operations and fighter coordination"
      ))
      result.totalEstimatedCost += 200

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Logothete: Generated {result.requirements.len} research requirements " &
          &"(total cost estimate: {result.totalEstimatedCost}PP)")

  return result

proc reprioritizeResearchRequirements*(
  originalRequirements: ResearchRequirements,
  feedback: ScienceFeedback
): ResearchRequirements =
  ## Reprioritize unfulfilled research requirements based on Treasurer feedback
  ## Pattern: Critical stays, High→Medium, Medium→Low, drop Low/Deferred

  result = ResearchRequirements(
    requirements: @[],
    totalEstimatedCost: 0,
    generatedTurn: originalRequirements.generatedTurn,
    iteration: originalRequirements.iteration + 1
  )

  if feedback.unfulfilledRequirements.len == 0:
    # All requirements fulfilled, no reprioritization needed
    result.requirements = originalRequirements.requirements
    result.totalEstimatedCost = originalRequirements.totalEstimatedCost
    return result

  logInfo(LogCategory.lcAI,
          &"Logothete: Reprioritizing {feedback.unfulfilledRequirements.len} unfulfilled research requirements")

  # Keep fulfilled requirements unchanged
  for req in feedback.fulfilledRequirements:
    result.requirements.add(req)
    result.totalEstimatedCost += req.estimatedCost

  # Reprioritize unfulfilled requirements
  for req in feedback.unfulfilledRequirements:
    var adjustedReq = req
    case req.priority
    of RequirementPriority.Critical:
      # Keep Critical (absolute priority, must investigate budget issues)
      adjustedReq.priority = RequirementPriority.Critical
      adjustedReq.reason &= " [CRITICAL: Budget insufficient]"
    of RequirementPriority.High:
      adjustedReq.priority = RequirementPriority.Medium
      adjustedReq.reason &= " [Downgraded from High]"
    of RequirementPriority.Medium:
      adjustedReq.priority = RequirementPriority.Low
      adjustedReq.reason &= " [Downgraded from Medium]"
    of RequirementPriority.Low:
      # Drop Low (couldn't afford anyway)
      logDebug(LogCategory.lcAI, &"Logothete: Dropping Low priority requirement: {req.reason}")
      continue
    of RequirementPriority.Deferred:
      # Already deferred, drop
      continue

    result.requirements.add(adjustedReq)
    result.totalEstimatedCost += adjustedReq.estimatedCost

  logInfo(LogCategory.lcAI,
          &"Logothete: Reprioritized to {result.requirements.len} requirements " &
          &"(iteration {result.iteration})")

  return result
