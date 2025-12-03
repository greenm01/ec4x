## Eparch Economic Requirements Module
##
## Byzantine Imperial Eparch - Economic Requirements Generation
##
## Generates economic requirements with priorities for Basileus mediation
## Focuses on terraforming, infrastructure, and colony development

import std/[options, strformat]
import ../../../engine/[gamestate, fog_of_war, logger]
import ../controller_types
import ./industrial_investment

proc generateEconomicRequirements*(
  controller: AIController,
  filtered: FilteredGameState,
  intelSnapshot: IntelligenceSnapshot
): EconomicRequirements =
  ## Generate economic requirements with priorities
  ## Now includes IU investment recommendations

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
