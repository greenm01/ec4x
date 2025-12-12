## Eparch Economic Requirements Module
##
## Byzantine Imperial Eparch - Economic Requirements Generation
##
## Generates economic requirements with priorities for Basileus mediation
## Focuses on terraforming, infrastructure, and colony development

import std/[options, strformat, random, math, sequtils, algorithm, tables]
import ../../../engine/[gamestate, fog_of_war, logger]
import ../controller_types
import ../shared/intelligence_types  # For IntelligenceSnapshot
import ../../common/types as ai_common_types  # For GameAct
import ../config
import ./industrial_investment
import ./terraforming

# ============================================================================
# FACILITY REQUIREMENTS GENERATION
# ============================================================================

proc countFacilities(colonies: seq[Colony], facilityType: string): int =
  ## Count total facilities of given type across all colonies
  result = 0
  for colony in colonies:
    if facilityType == "Shipyard":
      result += colony.shipyards.len
    elif facilityType == "Spaceport":
      result += colony.spaceports.len

proc getTargetShipyards(act: ai_common_types.GameAct, colonyCount: int): int =
  ## Target Shipyard count by Act (from unit-progression.md)
  ## Scales with colony expansion to support production capacity
  case act
  of ai_common_types.GameAct.Act1_LandGrab:
    # Act 1: 1 Shipyard per 2 colonies (expansion-focused production)
    # 1-2 colonies: 1, 3-4: 2, 5-6: 3, etc.
    max(1, (colonyCount + 1) div 2)
  of ai_common_types.GameAct.Act2_RisingTensions:
    # Act 2: 1 Shipyard per colony (military buildup)
    max(2, colonyCount)
  of ai_common_types.GameAct.Act3_TotalWar:
    # Act 3: 1-2 Shipyards per colony (maximum production)
    max(colonyCount, (colonyCount * 3) div 2)
  of ai_common_types.GameAct.Act4_Endgame:
    # Act 4: Over-capacity for endgame capital ship production
    # Increased from 2.0x to 2.5x to address late-game hoarding
    (colonyCount * 5) div 2  # 2.5x using integer math

proc findBestShipyardColony(
  colonies: seq[Colony],
  intelSnapshot: Option[IntelligenceSnapshot]
): Option[SystemId] =
  ## Phase 7.1: Select colony with highest production, considering threat levels
  ## (Shipyards require Spaceport prerequisite per facilities.toml)
  var bestColony: Option[SystemId] = none(SystemId)
  var highestScore = -1000.0  # Allow negative scores

  for colony in colonies:
    # CRITICAL: Must have Spaceport (prerequisite for Shipyard construction)
    if colony.spaceports.len > 0 and colony.shipyards.len == 0:
      var score = float(colony.production)

      # Phase 7.1: Apply threat penalty
      if intelSnapshot.isSome:
        let snap = intelSnapshot.get()
        if snap.military.threatsByColony.hasKey(colony.systemId):
          let threat = snap.military.threatsByColony[colony.systemId]
          case threat.level
          of intelligence_types.ThreatLevel.tlCritical:
            score *= 0.2  # 80% penalty - avoid critical threats
          of intelligence_types.ThreatLevel.tlHigh:
            score *= 0.5  # 50% penalty - risky
          of intelligence_types.ThreatLevel.tlModerate:
            score *= 0.8  # 20% penalty - slight risk
          else:
            discard

        # Staleness penalty for blind spots
        if colony.systemId in snap.staleIntelSystems:
          score *= 0.9  # 10% penalty - unknown risk

      if score > highestScore:
        bestColony = some(colony.systemId)
        highestScore = score

  return bestColony

proc findBestSpaceportColony(
  colonies: seq[Colony],
  intelSnapshot: Option[IntelligenceSnapshot]
): Option[SystemId] =
  ## Phase 7.1: Select colony for Spaceport, considering threat levels
  var bestColony: Option[SystemId] = none(SystemId)
  var highestScore = -1000.0

  for colony in colonies:
    if colony.spaceports.len == 0:
      var score = float(colony.production)

      # Phase 7.1: Apply threat penalty
      if intelSnapshot.isSome:
        let snap = intelSnapshot.get()
        if snap.military.threatsByColony.hasKey(colony.systemId):
          let threat = snap.military.threatsByColony[colony.systemId]
          case threat.level
          of intelligence_types.ThreatLevel.tlCritical:
            score *= 0.2  # Avoid critical threats
          of intelligence_types.ThreatLevel.tlHigh:
            score *= 0.5  # Risky
          of intelligence_types.ThreatLevel.tlModerate:
            score *= 0.8  # Slight risk
          else:
            discard

        # Staleness penalty
        if colony.systemId in snap.staleIntelSystems:
          score *= 0.9

      if score > highestScore:
        bestColony = some(colony.systemId)
        highestScore = score

  return bestColony

proc findBestStarbaseColony(
  colonies: seq[Colony],
  intelSnapshot: Option[IntelligenceSnapshot]
): Option[SystemId] =
  ## Phase 7.1: Select colony for Starbase, avoiding threatened locations
  ## Starbases provide economic (ELI+2) and defensive bonuses
  var bestColony: Option[SystemId] = none(SystemId)
  var highestScore = -1000.0

  for colony in colonies:
    # CRITICAL: Must have Spaceport (prerequisite for Starbase construction)
    if colony.spaceports.len > 0 and colony.starbases.len == 0:
      # Value = production + population (economic importance)
      var score = float(colony.production + colony.population)

      # Phase 7.1: Apply threat penalty (Starbases are expensive - avoid risky locations)
      if intelSnapshot.isSome:
        let snap = intelSnapshot.get()
        if snap.military.threatsByColony.hasKey(colony.systemId):
          let threat = snap.military.threatsByColony[colony.systemId]
          case threat.level
          of intelligence_types.ThreatLevel.tlCritical:
            score *= 0.1  # Heavy penalty - don't waste expensive Starbases
          of intelligence_types.ThreatLevel.tlHigh:
            score *= 0.3  # Significant penalty
          of intelligence_types.ThreatLevel.tlModerate:
            score *= 0.7  # Moderate penalty
          else:
            discard

        # Staleness penalty
        if colony.systemId in snap.staleIntelSystems:
          score *= 0.85  # Stronger penalty for expensive Starbases

      if score > highestScore:
        bestColony = some(colony.systemId)
        highestScore = score

  return bestColony

proc getTargetStarbases(act: ai_common_types.GameAct, colonyCount: int): int =
  ## Target Starbase count by Act
  ## Starbases provide ELI+2 and growth bonuses - valuable but not urgent
  case act
  of ai_common_types.GameAct.Act1_LandGrab:
    # Act 1: 0-1 Starbases (low priority during expansion)
    0
  of ai_common_types.GameAct.Act2_RisingTensions:
    # Act 2: 1 per 2 colonies (start building economic infrastructure)
    max(1, colonyCount div 2)
  of ai_common_types.GameAct.Act3_TotalWar:
    # Act 3: 1 per colony (economic and defensive bonuses matter)
    colonyCount
  of ai_common_types.GameAct.Act4_Endgame:
    # Act 4: 1-2 per colony (full infrastructure)
    # Increased from 1.5x to 2.0x to address late-game hoarding
    colonyCount * 2

proc generateFacilityRequirements(
  filtered: FilteredGameState,
  houseId: HouseId,
  currentAct: ai_common_types.GameAct,
  intelSnapshot: Option[IntelligenceSnapshot]  # Phase 7.1: Threat-aware planning
): seq[EconomicRequirement] =
  ## Phase 7.1: Generate requirements for facility construction (threat-aware)
  ## Priority order: Spaceport → Shipyard → Starbase
  result = @[]

  let colonies = filtered.ownColonies
  if colonies.len == 0:
    logInfo(LogCategory.lcAI,
            &"{houseId} Eparch: No colonies, skipping facility requirements")
    return result

  logInfo(LogCategory.lcAI,
          &"{houseId} Eparch: Evaluating facility needs for {colonies.len} colonies (Act {currentAct})")

  # 1. Evaluate Spaceport needs FIRST (prerequisite for Shipyards)
  # Target: 1 Spaceport per colony (no more - they're 2x cost vs Shipyards)
  # Note: Spaceports are 2x expensive for ship production and can't repair
  # Only build Spaceport if colony has none (first infrastructure priority)
  let currentSpaceports = countFacilities(colonies, "Spaceport")
  let targetShipyards = getTargetShipyards(currentAct, colonies.len)
  let spaceportsNeeded = colonies.len  # Max 1 per colony (no advantage to multiple)

  logInfo(LogCategory.lcAI,
          &"{houseId} Eparch: Spaceports - have {currentSpaceports}, need {spaceportsNeeded} " &
          &"(1 per colony, then build Shipyards for production)")

  if currentSpaceports < spaceportsNeeded:
    # Build at colonies without Spaceports (Phase 7.1: threat-aware)
    let bestColony = findBestSpaceportColony(colonies, intelSnapshot)
    if bestColony.isSome:
      result.add(EconomicRequirement(
        requirementType: EconomicRequirementType.Facility,
        priority: RequirementPriority.High,  # High priority (prerequisite for Shipyard)
        targetColony: bestColony.get(),
        facilityType: some("Spaceport"),
        terraformTarget: none(PlanetClass),
        estimatedCost: 50,  # Spaceport cost (from config)
        reason: &"Spaceport {currentSpaceports+1}/{spaceportsNeeded} baseline " &
                &"infrastructure (required for ship operations)"
      ))

  # 2. Evaluate Shipyard needs SECOND (production capacity)
  let currentShipyards = countFacilities(colonies, "Shipyard")
  # targetShipyards already calculated above for Spaceport logic

  logInfo(LogCategory.lcAI,
          &"{houseId} Eparch: Shipyards - have {currentShipyards}, need {targetShipyards}")

  if currentShipyards < targetShipyards:
    # Find best colony for Shipyard (Phase 7.1: threat-aware)
    logInfo(LogCategory.lcAI,
            &"{houseId} Eparch: Need {targetShipyards - currentShipyards} more Shipyards, finding best colony...")
    let bestColony = findBestShipyardColony(colonies, intelSnapshot)
    if bestColony.isSome:
      logInfo(LogCategory.lcAI,
              &"{houseId} Eparch: Found colony {bestColony.get()} for Shipyard construction")
      result.add(EconomicRequirement(
        requirementType: EconomicRequirementType.Facility,
        priority: RequirementPriority.High,
        targetColony: bestColony.get(),
        facilityType: some("Shipyard"),
        terraformTarget: none(PlanetClass),
        estimatedCost: 100,  # Shipyard cost (from config)
        reason: &"Shipyard {currentShipyards+1}/{targetShipyards} needed for " &
                &"Act {currentAct} production capacity"
      ))
    else:
      logWarn(LogCategory.lcAI,
              &"{houseId} Eparch: No suitable colony found for Shipyard (all colonies may already have Shipyards)")

  # 3. Evaluate Starbase needs THIRD (economic and defensive bonuses)
  let currentStarbases = colonies.mapIt(it.starbases.len).sum()
  let targetStarbases = getTargetStarbases(currentAct, colonies.len)

  logInfo(LogCategory.lcAI,
          &"{houseId} Eparch: Starbases - have {currentStarbases}, need {targetStarbases}")

  if currentStarbases < targetStarbases:
    # Find best colony for Starbase (Phase 7.1: threat-aware, expensive infrastructure)
    logInfo(LogCategory.lcAI,
            &"{houseId} Eparch: Need {targetStarbases - currentStarbases} more Starbases, finding best colony...")
    let bestColony = findBestStarbaseColony(colonies, intelSnapshot)
    if bestColony.isSome:
      logInfo(LogCategory.lcAI,
              &"{houseId} Eparch: Found colony {bestColony.get()} for Starbase construction")
      result.add(EconomicRequirement(
        requirementType: EconomicRequirementType.Facility,
        priority: RequirementPriority.Medium,  # Medium priority (can be delayed for military needs)
        targetColony: bestColony.get(),
        facilityType: some("Starbase"),
        terraformTarget: none(PlanetClass),
        estimatedCost: 300,  # Starbase cost (from config)
        reason: &"Starbase {currentStarbases+1}/{targetStarbases} for economic (ELI+2) " &
                &"and defensive bonuses"
      ))
    else:
      logWarn(LogCategory.lcAI,
              &"{houseId} Eparch: No suitable colony found for Starbase (need Spaceport prerequisite)")

proc generateEconomicRequirements*(
  controller: AIController,
  filtered: FilteredGameState,
  intelSnapshot: IntelligenceSnapshot
): EconomicRequirements =
  ## Generate economic requirements with priorities
  ## Includes IU investment and terraforming recommendations

  logDebug(LogCategory.lcAI,
           &"{controller.houseId} Eparch: Generating economic requirements")

  var requirements: seq[EconomicRequirement] = @[]
  var totalCost = 0

  # Generate IU investment opportunities (Phase E: intelligence-aware)
  let iuOpportunities = generateIUInvestmentRecommendations(controller, filtered, some(intelSnapshot))

  for opportunity in iuOpportunities:
    # Convert float priority (0.0-1.0) to RequirementPriority enum
    let priorityEnum = if opportunity.priority >= 0.75:
                         RequirementPriority.Critical
                       elif opportunity.priority >= 0.50:
                         RequirementPriority.High
                       elif opportunity.priority >= 0.25:
                         RequirementPriority.Medium
                       else:
                         RequirementPriority.Low

    # Convert IU investment opportunity to EconomicRequirement
    requirements.add(EconomicRequirement(
      requirementType: EconomicRequirementType.IUInvestment,
      priority: priorityEnum,
      targetColony: opportunity.colonyId,
      facilityType: none(string),  # Not a facility
      terraformTarget: none(PlanetClass),  # Not terraforming
      estimatedCost: opportunity.investmentCost,
      reason: opportunity.reason
    ))
    totalCost += opportunity.investmentCost

    logDebug(LogCategory.lcAI,
             &"{controller.houseId} Eparch: IU investment opportunity at {opportunity.colonyId}: " &
             &"{opportunity.currentIU}→{opportunity.targetIU} IU for {opportunity.investmentCost} PP " &
             &"(priority {opportunity.priority:.2f})")

  # Generate terraforming opportunities
  var rng = initRand()  # Simple RNG for terraforming evaluation
  let terraformOrders = generateTerraformOrders(controller, filtered, rng)

  for order in terraformOrders:
    # Terraforming is high priority (permanent population capacity increase)
    # Priority scaled by cost (expensive upgrades need higher priority)
    let priorityScore = 0.7 + (float(order.ppCost) / 5000.0)  # 0.7-0.9 range
    let priorityEnum = if priorityScore >= 0.75:
                         RequirementPriority.Critical
                       else:
                         RequirementPriority.High

    # Convert int target class to PlanetClass enum
    # targetClass is 1-7 corresponding to Extreme-Eden
    let targetPlanetClass = PlanetClass(order.targetClass - 1)  # 0-indexed enum

    requirements.add(EconomicRequirement(
      requirementType: EconomicRequirementType.Terraforming,
      priority: priorityEnum,
      targetColony: order.colonySystem,
      facilityType: none(string),  # Not a facility
      terraformTarget: some(targetPlanetClass),
      estimatedCost: order.ppCost,
      reason: "Terraform colony to improve capacity and productivity"
    ))
    totalCost += order.ppCost

    logDebug(LogCategory.lcAI,
             &"{controller.houseId} Eparch: Terraforming opportunity at {order.colonySystem}: " &
             &"upgrade for {order.ppCost} PP in {order.turnsRemaining} turns " &
             &"(priority {priorityScore:.2f})")

  # Generate facility requirements (Shipyards and Spaceports)
  # Phase 7.1: Pass intelligence snapshot for threat-aware facility selection
  let currentAct = ai_common_types.getCurrentGameAct(filtered.turn)
  let facilityRequirements = generateFacilityRequirements(filtered,
                                                          controller.houseId,
                                                          currentAct,
                                                          some(intelSnapshot))

  for facility in facilityRequirements:
    requirements.add(facility)
    totalCost += facility.estimatedCost

    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Eparch: FACILITY REQUIREMENT GENERATED at {facility.targetColony}: " &
            &"{facility.facilityType.get()} for {facility.estimatedCost} PP " &
            &"(priority {facility.priority}, reason: {facility.reason})")

  result = EconomicRequirements(
    requirements: requirements,
    totalEstimatedCost: totalCost,
    generatedTurn: filtered.turn,
    iteration: 0
  )

proc reprioritizeEconomicRequirements*(
  original: EconomicRequirements,
  eparchFeedback: EparchFeedback,
  treasury: int
): EconomicRequirements =
  ## Reprioritize economic requirements based on Treasurer feedback
  ##
  ## Strategy (Gap 4):
  ## 1. Escalate unfulfilled requirements based on starvation time
  ##    - Medium (10+ iterations) → High
  ##    - High (20+ iterations) → Critical
  ## 2. Downgrade expensive unfulfilled High requirements to Medium
  ##    - Expensive = >30% of treasury
  ## 3. Preserve Critical facility requirements (Spaceports are essential)
  ##
  ## This ensures critical infrastructure eventually gets built while
  ## remaining flexible about expensive long-term investments

  const MAX_ITERATIONS = 3

  if original.iteration >= MAX_ITERATIONS:
    logWarn(LogCategory.lcAI,
            &"Eparch reprioritization limit reached ({MAX_ITERATIONS} iterations). " &
            &"Accepting unfulfilled requirements.")
    return original

  # If everything was fulfilled, no need to reprioritize
  if eparchFeedback.unfulfilledRequirements.len == 0:
    return original

  logInfo(LogCategory.lcAI,
          &"Eparch reprioritizing {eparchFeedback.unfulfilledRequirements.len} " &
          &"unfulfilled requirements (iteration {original.iteration + 1}, " &
          &"shortfall: {eparchFeedback.totalBudgetAvailable - eparchFeedback.totalBudgetSpent}PP, " &
          &"treasury={treasury}PP)")

  var reprioritized: seq[EconomicRequirement] = @[]

  # Add all fulfilled requirements (these were already affordable)
  reprioritized.add(eparchFeedback.fulfilledRequirements)

  # Reprioritize unfulfilled requirements based on starvation time
  let facilityHighToMediumTurns = globalRBAConfig.reprioritization
                                   .facility_high_to_medium_turns
  let facilityCriticalToHighTurns = globalRBAConfig.reprioritization
                                     .facility_critical_to_high_turns

  for req in eparchFeedback.unfulfilledRequirements:
    var adjustedReq = req

    # Calculate cost-effectiveness ratio
    let costRatio = if treasury > 0:
                      float(req.estimatedCost) / float(treasury)
                    else:
                      1.0

    # Escalate based on starvation time (iteration as proxy)
    if original.iteration >= facilityHighToMediumTurns:
      # 20+ iterations → Escalate to Critical
      if req.priority == RequirementPriority.High:
        adjustedReq.priority = RequirementPriority.Critical
        logInfo(LogCategory.lcAI,
                &"Eparch: Escalating '{req.reason}' (High → Critical) " &
                &"after {original.iteration} iterations")
      elif req.priority == RequirementPriority.Medium:
        adjustedReq.priority = RequirementPriority.High
        logInfo(LogCategory.lcAI,
                &"Eparch: Escalating '{req.reason}' (Medium → High) " &
                &"after {original.iteration} iterations")

    elif original.iteration >= facilityCriticalToHighTurns:
      # 10+ iterations → Escalate Medium to High
      if req.priority == RequirementPriority.Medium:
        adjustedReq.priority = RequirementPriority.High
        logInfo(LogCategory.lcAI,
                &"Eparch: Escalating '{req.reason}' (Medium → High) " &
                &"after {original.iteration} iterations")

    # Downgrade expensive High requirements to Medium
    # (allows more affordable requirements to get funded first)
    if costRatio > 0.3 and req.priority == RequirementPriority.High:
      adjustedReq.priority = RequirementPriority.Medium
      logDebug(LogCategory.lcAI,
               &"Eparch: Downgrading expensive '{req.reason}' " &
               &"(High → Medium, {req.estimatedCost}PP = " &
               &"{int(costRatio*100)}% of treasury)")

    # EXCEPTION: Never downgrade Spaceport requirements below High
    # (Spaceports are essential prerequisites for all other facilities)
    if req.facilityType.isSome and
       req.facilityType.get() == "Spaceport" and
       adjustedReq.priority < RequirementPriority.High:
      adjustedReq.priority = RequirementPriority.High
      logDebug(LogCategory.lcAI,
               &"Eparch: Preserving Spaceport requirement at High priority " &
               &"(essential prerequisite)")

    reprioritized.add(adjustedReq)

  # Re-sort by new priorities (same logic as other requirements)
  reprioritized.sort(proc(a, b: EconomicRequirement): int =
    if a.priority > b.priority: 1  # Higher ord (Low=3) comes AFTER
    elif a.priority < b.priority: -1  # Lower ord (Critical=0) comes FIRST
    else: 0
  )

  result = EconomicRequirements(
    requirements: reprioritized,
    totalEstimatedCost: reprioritized.mapIt(it.estimatedCost).foldl(a + b, 0),
    generatedTurn: original.generatedTurn,
    iteration: original.iteration + 1
  )

  logInfo(LogCategory.lcAI,
          &"Eparch reprioritized requirements: {result.requirements.len} total " &
          &"(iteration={result.iteration})")
