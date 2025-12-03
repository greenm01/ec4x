## Eparch - Industrial Investment Module
##
## Evaluates IU investment opportunities and calculates ROI
## Understands passive IU growth rates and when manual investment is beneficial

import std/[options, math, algorithm]
import ../../../common/types/[core, units]
import ../../../engine/gamestate
import ../../../engine/fog_of_war
import ../../../engine/economy/types as econ_types
import ../../common/types as ai_types
import ../controller_types

type
  IUInvestmentOpportunity* = object
    ## Recommendation for IU investment at a colony
    colonyId*: SystemId
    currentIU*: int
    currentPU*: int
    targetIU*: int  # Recommended IU target
    investmentCost*: int  # Total PP needed
    paybackTurns*: int  # Turns to recover investment
    priority*: float  # 0.0-1.0, higher = more urgent
    reason*: string

proc calculateIUInvestmentCost*(currentIU: int, targetIU: int, populationUnits: int): int =
  ## Calculate total cost to invest from currentIU to targetIU
  ## Uses tiered pricing from config/economy.toml
  ##
  ## Tiers based on IU as % of PU:
  ## - ≤50%: 5 PP per IU
  ## - 51-75%: 6 PP per IU
  ## - 76-100%: 8 PP per IU
  ## - 101-150%: 10 PP per IU
  ## - 151%+: 13 PP per IU

  var totalCost = 0

  for iu in (currentIU + 1) .. targetIU:
    let percentOfPU = (float(iu) / float(populationUnits)) * 100.0

    let costPerIU = if percentOfPU <= 50.0:
      5  # Tier 1
    elif percentOfPU <= 75.0:
      6  # Tier 2
    elif percentOfPU <= 100.0:
      8  # Tier 3
    elif percentOfPU <= 150.0:
      10  # Tier 4
    else:
      13  # Tier 5

    totalCost += costPerIU

  return totalCost

proc calculatePassiveIUGrowth*(populationUnits: int): int =
  ## Calculate passive IU growth per turn
  ## Formula: max(1, floor(PU / 200))
  return max(1, int(floor(float(populationUnits) / 200.0)))

proc estimateIUProductionValue*(iu: int, elTech: int): int =
  ## Estimate PP production per turn from IU
  ## Rough estimate: 1 IU produces ~1 PP at EL1, scales with EL
  ## This is simplified - actual formula is more complex
  let elModifier = 1.0 + (float(elTech - 1) * 0.10)  # +10% per EL
  return int(float(iu) * elModifier)

proc evaluateIUInvestment*(
  colony: Colony,
  houseELTech: int,
  houseTreasury: int,
  turnNumber: int,
  strategy: AIStrategy = AIStrategy.Balanced
): Option[IUInvestmentOpportunity] =
  ## Evaluate whether IU investment is worthwhile at this colony
  ##
  ## Investment is recommended when:
  ## 1. Colony has sufficient population to justify IU
  ## 2. Current IU is significantly below optimal level
  ## 3. Payback period is reasonable (< 10 turns)
  ## 4. House has sufficient treasury reserves

  let currentIU = colony.industrial.units
  let currentPU = colony.populationUnits
  let passiveGrowth = calculatePassiveIUGrowth(currentPU)

  # Early game: Let passive growth handle it
  if turnNumber < 5:
    return none(IUInvestmentOpportunity)

  # Small colonies: Not worth investing yet
  if currentPU < 100:
    return none(IUInvestmentOpportunity)

  # Calculate optimal IU target based on strategy
  # Aggressive/MilitaryIndustrial/Raider: 150% of PU (maximize production for military)
  # Balanced/Opportunistic: 100% of PU (balanced development)
  # Turtle/Economic/Isolationist: 125% of PU (strong economy for defense)
  # Espionage/Diplomatic/TechRush/Expansionist: 100% PU (balanced, focus elsewhere)
  let optimalIU = case strategy
    of AIStrategy.Aggressive, AIStrategy.MilitaryIndustrial, AIStrategy.Raider:
      (currentPU * 3) div 2  # 150%
    of AIStrategy.Balanced, AIStrategy.Opportunistic:
      currentPU  # 100%
    of AIStrategy.Turtle, AIStrategy.Economic, AIStrategy.Isolationist:
      (currentPU * 5) div 4  # 125%
    of AIStrategy.Espionage, AIStrategy.Diplomatic, AIStrategy.TechRush, AIStrategy.Expansionist:
      currentPU  # 100%

  # Already at or above optimal
  if currentIU >= optimalIU:
    return none(IUInvestmentOpportunity)

  # Calculate investment needed to reach optimal
  let deficit = optimalIU - currentIU

  # If passive growth will reach optimal in < 5 turns, don't invest
  let turnsToOptimalPassive = int(ceil(float(deficit) / float(passiveGrowth)))
  if turnsToOptimalPassive <= 5:
    return none(IUInvestmentOpportunity)

  # Evaluate partial investment (25% of deficit, minimum 10 IU)
  let targetIU = currentIU + max(10, deficit div 4)
  let investmentCost = calculateIUInvestmentCost(currentIU, targetIU, currentPU)

  # Check if house can afford it (need 3x investment in treasury for safety)
  if houseTreasury < investmentCost * 3:
    return none(IUInvestmentOpportunity)

  # Calculate payback period
  let iuGain = targetIU - currentIU
  let productionGainPerTurn = estimateIUProductionValue(iuGain, houseELTech)
  let paybackTurns = if productionGainPerTurn > 0:
    int(ceil(float(investmentCost) / float(productionGainPerTurn)))
  else:
    999  # Infinite payback = bad investment

  # Reject if payback > 10 turns
  if paybackTurns > 10:
    return none(IUInvestmentOpportunity)

  # Calculate priority (higher for larger colonies, shorter payback)
  let populationFactor = min(1.0, float(currentPU) / 1000.0)  # 0.0-1.0
  let paybackFactor = max(0.0, 1.0 - (float(paybackTurns) / 10.0))  # 1.0 at 0 turns, 0.0 at 10
  let priority = (populationFactor + paybackFactor) / 2.0

  return some(IUInvestmentOpportunity(
    colonyId: colony.systemId,
    currentIU: currentIU,
    currentPU: currentPU,
    targetIU: targetIU,
    investmentCost: investmentCost,
    paybackTurns: paybackTurns,
    priority: priority,
    reason: "Accelerate industrial development: " & $iuGain &
            " IU for " & $investmentCost & " PP (" & $paybackTurns & "-turn payback)"
  ))

proc generateIUInvestmentRecommendations*(
  controller: AIController,
  filtered: FilteredGameState
): seq[IUInvestmentOpportunity] =
  ## Generate IU investment recommendations for all colonies
  ## Returns sorted by priority (highest first)

  result = @[]

  # Access own house data from filtered state (fog of war enforced)
  let house = filtered.ownHouse

  for colony in filtered.ownColonies:
    let opportunity = evaluateIUInvestment(
      colony,
      house.techTree.levels.economicLevel,
      house.treasury,
      filtered.turn,
      controller.strategy
    )

    if opportunity.isSome:
      result.add(opportunity.get())

  # Sort by priority (descending)
  result.sort(proc (a, b: IUInvestmentOpportunity): int =
    if a.priority > b.priority: -1
    elif a.priority < b.priority: 1
    else: 0
  )
