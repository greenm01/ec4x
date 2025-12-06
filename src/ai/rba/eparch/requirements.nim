## Eparch Economic Requirements Module
##
## Byzantine Imperial Eparch - Economic Requirements Generation
##
## Generates economic requirements with priorities for Basileus mediation
## Focuses on terraforming, infrastructure, and colony development

import std/[options, strformat, random, math, sequtils]
import ../../../engine/[gamestate, fog_of_war, logger]
import ../controller_types
import ../shared/intelligence_types  # For IntelligenceSnapshot
import ../../common/types as ai_common_types  # For GameAct
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
    (colonyCount * 2)

proc findBestShipyardColony(colonies: seq[Colony]): Option[SystemId] =
  ## Select colony with highest production, no existing Shipyard, AND has Spaceport
  ## (Shipyards require Spaceport prerequisite per facilities.toml)
  var bestColony: Option[SystemId] = none(SystemId)
  var highestProduction = -1  # -1 to allow colonies with 0 production

  for colony in colonies:
    # CRITICAL: Must have Spaceport (prerequisite for Shipyard construction)
    if colony.spaceports.len > 0 and
       colony.shipyards.len == 0 and
       colony.production > highestProduction:
      bestColony = some(colony.systemId)
      highestProduction = colony.production

  return bestColony

proc findBestSpaceportColony(colonies: seq[Colony]): Option[SystemId] =
  ## Select colony without Spaceport (prefer high production colonies)
  var bestColony: Option[SystemId] = none(SystemId)
  var highestProduction = -1  # -1 to allow colonies with 0 production

  for colony in colonies:
    if colony.spaceports.len == 0 and
       colony.production > highestProduction:
      bestColony = some(colony.systemId)
      highestProduction = colony.production

  return bestColony

proc findBestStarbaseColony(colonies: seq[Colony]): Option[SystemId] =
  ## Select colony with Shipyard but no Starbase (prefer high-value targets)
  ## Starbases provide economic (ELI+2) and defensive bonuses
  var bestColony: Option[SystemId] = none(SystemId)
  var highestValue = -1

  for colony in colonies:
    # CRITICAL: Must have Spaceport (prerequisite for Starbase construction)
    # Also prefer colonies with existing Shipyards (military/economic hubs)
    if colony.spaceports.len > 0 and
       colony.starbases.len == 0:
      # Value = production + population (economic importance)
      let value = colony.production + colony.population
      if value > highestValue:
        bestColony = some(colony.systemId)
        highestValue = value

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
    colonyCount + (colonyCount div 2)

proc generateFacilityRequirements(
  filtered: FilteredGameState,
  houseId: HouseId,
  currentAct: ai_common_types.GameAct
): seq[EconomicRequirement] =
  ## Generate requirements for facility construction
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
    # Build at colonies without Spaceports
    let bestColony = findBestSpaceportColony(colonies)
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
    # Find best colony for Shipyard (highest production)
    logInfo(LogCategory.lcAI,
            &"{houseId} Eparch: Need {targetShipyards - currentShipyards} more Shipyards, finding best colony...")
    let bestColony = findBestShipyardColony(colonies)
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
    # Find best colony for Starbase (high-value economic targets)
    logInfo(LogCategory.lcAI,
            &"{houseId} Eparch: Need {targetStarbases - currentStarbases} more Starbases, finding best colony...")
    let bestColony = findBestStarbaseColony(colonies)
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
  let currentAct = ai_common_types.getCurrentGameAct(filtered.turn)
  let facilityRequirements = generateFacilityRequirements(filtered,
                                                          controller.houseId,
                                                          currentAct)

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
  original: EconomicRequirements
): EconomicRequirements =
  ## Reprioritize economic requirements based on feedback
  ## MVP: Pass-through (no reprioritization)
  result = original
  result.iteration += 1
