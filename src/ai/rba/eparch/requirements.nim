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

  var requirements: seq[Requirement] = @[]
  var totalCost = 0

  # Generate IU investment opportunities
  let iuOpportunities = generateIUInvestmentRecommendations(controller, filtered)

  for opportunity in iuOpportunities:
    # Convert IU investment opportunity to Requirement
    requirements.add(Requirement(
      requirementType: RequirementType.Economic,
      priority: opportunity.priority,
      estimatedCost: opportunity.investmentCost,
      description: opportunity.reason,
      targetSystem: some(opportunity.colonyId)
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
    let priority = 0.7 + (float(order.ppCost) / 5000.0)  # 0.7-0.9 range

    requirements.add(Requirement(
      requirementType: RequirementType.Economic,
      priority: priority,
      estimatedCost: order.ppCost,
      description: "Terraform colony to improve capacity and productivity",
      targetSystem: some(order.colonySystem)
    ))
    totalCost += order.ppCost

    logDebug(LogCategory.lcAI,
             &"{controller.houseId} Eparch: Terraforming opportunity at {order.colonySystem}: " &
             &"upgrade for {order.ppCost} PP in {order.turnsRemaining} turns " &
             &"(priority {priority:.2f})")

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
