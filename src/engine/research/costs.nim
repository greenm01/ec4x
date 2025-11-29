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
import ../config/tech_config

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
  ## Per economy.md:4.2 and config/tech.toml
  ##
  ## Loads from globalTechConfig instead of hardcoded formula
  return getELUpgradeCostFromConfig(currentLevel)

proc getELModifier*(level: int): float =
  ## Get EL economic modifier (as multiplier)
  ## Per economy.md:4.2: +5% per level, capped at 50%
  ## Returns 1.0 + bonus (e.g., 1.05 for EL1, 1.50 for EL10+)
  result = 1.0 + min(float(level) * EL_MODIFIER_PER_LEVEL, EL_MAX_MODIFIER)

## Science Research Points (economy.md:4.3)

proc calculateSRPCost*(currentSL: int): float =
  ## Calculate PP cost per SRP
  ## Formula per economy.md:4.3: 1 SRP = 2 + SL(0.5) PP
  result = 2.0 + float(currentSL) * 0.5

proc convertPPToSRP*(pp: int, currentSL: int): int =
  ## Convert PP to SRP
  let costPerSRP = calculateSRPCost(currentSL)
  result = int(float(pp) / costPerSRP)

proc getSLUpgradeCost*(currentLevel: int): int =
  ## Get SRP cost to advance Science Level
  ## Per economy.md:4.3 and config/tech.toml
  ##
  ## Loads from globalTechConfig instead of hardcoded formula
  return getSLUpgradeCostFromConfig(currentLevel)

proc getSLModifier*(level: int): float =
  ## Get SL research modifier
  ## Affects TRP costs per economy.md:4.4
  ##
  ## Per the TRP formula: 1 TRP = (5 + 4(SL))/10 + log(GHO) * 0.5 PP
  ## Higher SL increases TRP cost (more advanced science infrastructure)
  ##
  ## This modifier is 5% per SL level (baseline 1.0 at SL0)
  result = 1.0 + (float(level) * 0.05)

## Technology Research Points (economy.md:4.4)

proc getTRPCost*(techField: TechField, slLevel: int, gho: int): float =
  ## Get PP cost per TRP for specific tech field
  ## Formula per economy.md:4.4: 1 TRP = (5 + 4(SL))/10 + log(GHO) * 0.5 PP
  ##
  ## Args:
  ##   techField: The technology being researched
  ##   slLevel: Current Science Level
  ##   gho: Gross House Output
  result = (5.0 + 4.0 * float(slLevel)) / 10.0 + log10(float(gho)) * 0.5

proc convertPPToTRP*(pp: int, techField: TechField, slLevel: int, gho: int): int =
  ## Convert PP to TRP for specific tech field
  let costPerTRP = getTRPCost(techField, slLevel, gho)
  result = int(float(pp) / costPerTRP)

proc getTechUpgradeCost*(techField: TechField, currentLevel: int): int =
  ## Get TRP cost to advance tech level
  ## Per economy.md:4.4-4.12 and config/tech.toml
  ##
  ## Loads from globalTechConfig instead of hardcoded values
  return getTechUpgradeCostFromConfig(techField, currentLevel)

## Research Allocation

proc allocateResearch*(allocation: ResearchAllocation,
                      gho: int, slLevel: int): ResearchPoints =
  ## Convert PP allocations to RP
  ##
  ## Args:
  ##   allocation: PP allocated to each category
  ##   gho: Gross House Output (for RP conversion)
  ##   slLevel: Science Level (affects TRP costs)

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
    result.science = convertPPToSRP(allocation.science, slLevel)

  # Convert technology allocations
  for field, pp in allocation.technology:
    if pp > 0:
      result.technology[field] = convertPPToTRP(pp, field, slLevel, gho)

proc calculateTotalRPInvested*(allocation: ResearchAllocation): int =
  ## Calculate total RP invested (for breakthrough calculation)
  result = allocation.economic + allocation.science

  for pp in allocation.technology.values:
    result += pp
