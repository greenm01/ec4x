## Eparch Economic Requirements Module
##
## Byzantine Imperial Eparch - Economic Requirements Generation
##
## Generates economic requirements with priorities for Basileus mediation
## Focuses on terraforming, infrastructure, and colony development

import std/[options, strformat, random]
import ../../../engine/[gamestate, fog_of_war, logger]
import ../controller_types
import ./industrial_investment
import ./terraforming

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

  # Generate IU investment opportunities
  let iuOpportunities = generateIUInvestmentRecommendations(controller, filtered)

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
