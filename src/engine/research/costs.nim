## Research Cost Calculation
##
## Calculate RP costs and PP conversion per economy.md:4.0
##
## Cost formulas:
## - ERP: (5 + log(GHO)) PP per ERP
## - SRP: Similar scaling
## - TRP: Varies by tech field

import std/[math, tables]
import types
import ../../common/types/tech

export types.ResearchAllocation

## Economic Research Points (economy.md:4.2)

proc calculateERPCost*(gho: int): float =
  ## Calculate PP cost per ERP
  ## Formula: 1 ERP = (5 + log(GHO)) PP
  result = 5.0 + log10(float(gho))

proc convertPPToERP*(pp: int, gho: int): int =
  ## Convert PP to ERP
  let costPerERP = calculateERPCost(gho)
  result = int(float(pp) / costPerERP)

proc getELUpgradeCost*(currentLevel: int): int =
  ## Get ERP cost to advance Economic Level
  ## Per economy.md:4.2
  ##
  ## EL1-5: 40 + EL(10)
  ## EL6+: 90 + 15 per level above 5

  if currentLevel <= 5:
    return 40 + currentLevel * 10
  else:
    # EL6 = 90 + 15 = 105, EL7 = 90 + 30 = 120, etc.
    let baseEL5Cost = 40 + 5 * 10  # 90
    let levelsAbove5 = currentLevel - 5
    return baseEL5Cost + (15 * levelsAbove5)

proc getELModifier*(level: int): float =
  ## Get EL economic modifier (as multiplier)
  ## Per economy.md:4.2: +5% per level, capped at 50%
  ## Returns 1.0 + bonus (e.g., 1.05 for EL1, 1.50 for EL10+)
  result = 1.0 + min(float(level) * EL_MODIFIER_PER_LEVEL, EL_MAX_MODIFIER)

## Science Research Points (economy.md:4.3)

proc calculateSRPCost*(gho: int, elLevel: int): float =
  ## Calculate PP cost per SRP
  ## Similar to ERP but scaled by EL
  ##
  ## TODO: Define proper SRP cost formula
  ## Placeholder: Similar to ERP
  result = calculateERPCost(gho)

proc convertPPToSRP*(pp: int, gho: int, elLevel: int): int =
  ## Convert PP to SRP
  let costPerSRP = calculateSRPCost(gho, elLevel)
  result = int(float(pp) / costPerSRP)

proc getSLUpgradeCost*(currentLevel: int): int =
  ## Get SRP cost to advance Science Level
  ## Per economy.md:4.3
  ##
  ## TODO: Define proper SL cost progression
  ## Placeholder: Similar to EL
  return getELUpgradeCost(currentLevel)

proc getSLModifier*(level: int): float =
  ## Get SL research modifier
  ## Affects TRP costs
  ##
  ## TODO: Define proper SL effects
  result = 1.0 + (float(level) * 0.05)

## Technology Research Points (economy.md:4.4)

proc getTRPCost*(techField: TechField, slLevel: int): float =
  ## Get PP cost per TRP for specific tech field
  ## Varies by field and Science Level
  ##
  ## TODO: Define per-field TRP costs
  ## Placeholder: Base cost modified by SL
  let baseCost = 10.0
  let slMod = getSLModifier(slLevel)
  result = baseCost / slMod

proc convertPPToTRP*(pp: int, techField: TechField, slLevel: int): int =
  ## Convert PP to TRP for specific tech field
  let costPerTRP = getTRPCost(techField, slLevel)
  result = int(float(pp) / costPerTRP)

proc getTechUpgradeCost*(techField: TechField, currentLevel: int): int =
  ## Get TRP cost to advance tech level
  ## Per economy.md:4.4-4.12 (varies by field)
  ##
  ## TODO: Load field-specific costs from specs
  ## Placeholder: Exponential scaling
  return 50 + (currentLevel * currentLevel * 10)

## Research Allocation

proc allocateResearch*(ppBudget: int, allocation: ResearchAllocation,
                      gho: int, elLevel: int, slLevel: int): ResearchPoints =
  ## Convert PP allocations to RP
  ##
  ## Args:
  ##   ppBudget: Total PP available for research
  ##   allocation: How PP should be split
  ##   gho: Gross House Output (for RP conversion)
  ##   elLevel: Economic Level (for costs)
  ##   slLevel: Science Level (for costs)

  result = ResearchPoints(
    economic: 0,
    science: 0,
    technology: initTable[TechField, int]()
  )

  # Convert economic allocation
  if allocation.economic > 0:
    result.economic = convertPPToERP(allocation.economic, gho)

  # Convert science allocation
  if allocation.science > 0:
    result.science = convertPPToSRP(allocation.science, gho, elLevel)

  # Convert technology allocations
  for field, pp in allocation.technology:
    if pp > 0:
      result.technology[field] = convertPPToTRP(pp, field, slLevel)

proc calculateTotalRPInvested*(allocation: ResearchAllocation): int =
  ## Calculate total RP invested (for breakthrough calculation)
  result = allocation.economic + allocation.science

  for pp in allocation.technology.values:
    result += pp
