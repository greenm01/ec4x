## Colony Production Calculation
##
## Implements GCO (Gross Colony Output) calculation per economy.md:3.1
##
## Formula: GCO = (PU × RAW_INDEX) + (IU × EL_MOD × CST_MOD × (1 + PROD_GROWTH + STARBASE_BONUS))
##
## Components:
## - PU: Population Units
## - RAW_INDEX: Resource quality modifier (60%-140% based on planet/resources)
## - IU: Industrial Units
## - EL_MOD: Economic Level tech modifier
## - CST_MOD: Construction tech capacity bonus (+10% per level)
## - PROD_GROWTH: Productivity growth from tax policy
## - STARBASE_BONUS: Operational starbases boost IU output (+5% per SB, max +15%)

import std/math
import ../../types/[production, colony, starmap, game_state]
import ../../globals
import ../../../common/logger

export production.ProductionOutput
export starmap.PlanetClass, starmap.ResourceRating

## RAW INDEX Table (economy.md:3.1)

proc getRawIndex*(planetClass: PlanetClass, resources: ResourceRating): float =
  ## Get RAW INDEX modifier from config
  ## Returns percentage modifier (0.60 - 1.40)
  ##
  ## Uses config/economy.kdl raw_material_efficiency section
  ## Direct array access - O(1) lookup by enum values
  gameConfig.economy.rawMaterialEfficiency.multipliers[resources][planetClass]

proc getEconomicLevelModifier*(techLevel: int): float =
  ## Get EL_MOD from tech level
  ## Per economy.md:4.2 - "A House's GHO benefits from EL upgrades by 5% per level"
  ##
  ## CRITICAL: Tech starts at EL1 (gameplay.md:1.2), so EL1 = 1.05 (5% bonus)
  ## Formula: 1.0 + (techLevel × 0.05)
  ## - EL1 = 1.05 (5% bonus)
  ## - EL2 = 1.10 (10% bonus)
  ## - EL10 = 1.50 (50% bonus maximum)
  result = 1.0 + (float(techLevel) * 0.05)

proc getProductivityGrowth*(taxRate: int): float =
  ## Get PROD_GROWTH from tax rate
  ## Lower taxes = higher productivity growth
  ##
  ## Linear growth curve per economy.md:
  ## - Tax 100% = -10% growth (harsh taxation suppresses productivity)
  ## - Tax 50% = 0% growth (neutral baseline)
  ## - Tax 0% = +10% growth (economic freedom boosts productivity)
  ##
  ## Formula: PROD_GROWTH = (50 - taxRate) / 500
  result = (50.0 - float(taxRate)) / 500.0

proc getStarbaseGrowthBonus*(colony: Colony): float =
  ## TODO: DoD refactoring needed
  ## This function needs GameState to count operational starbases via entity manager
  ## For now, return 0.0 (no bonus)
  ## Proper implementation should call commissioning.getStarbaseGrowthBonus(state, colonyId)
  return 0.0

proc calculateGrossOutput*(
    colony: Colony, elTechLevel: int, cstTechLevel: int = 1
): int =
  ## Calculate GCO (Gross Colony Output) for colony
  ## Per economy.md:3.1 and 4.5
  ##
  ## Formula: GCO = (PU × RAW_INDEX) + (IU × EL_MOD × CST_MOD × (1 + PROD_GROWTH))
  ## CST_MOD: Construction capacity multiplier per economy.md:4.5 (+10% per level)

  # Validate inputs - negative population/IU should not produce negative output
  let validPopulationUnits = max(0, colony.populationUnits)
  let validIndustrialUnits = max(0, colony.industrial.units)

  # Population production component
  let rawIndex = getRawIndex(colony.planetClass, colony.resources)
  let populationProd = float(validPopulationUnits) * rawIndex

  # Industrial production component
  let elMod = getEconomicLevelModifier(elTechLevel)
  let cstMod = 1.0 + (float(cstTechLevel - 1) * 0.10) # CST capacity bonus
  let prodGrowth = getProductivityGrowth(colony.taxRate)
  let starbaseBonus = getStarbaseGrowthBonus(colony)
    # 5% per operational starbase, max 15%
  let industrialProd =
    float(validIndustrialUnits) * elMod * cstMod * (1.0 + prodGrowth + starbaseBonus)

  # Total GCO (guaranteed non-negative)
  var totalGCO = populationProd + industrialProd

  # Apply blockade penalty: 60% reduction → 40% effective
  # Per operations.md:6.2.6: "Blockaded colonies produce at 40% capacity"
  if colony.blockaded:
    totalGCO = totalGCO * 0.4

  result = int(totalGCO)

proc calculateNetValue*(grossOutput: int, taxRate: int): int =
  ## Calculate NCV (Net Colony Value) from GCO and tax rate
  ## Per economy.md:3.2: "PP Income = Total GCO across all colonies × Tax Rate (rounded up)"
  ## Per economy.md:3.3: Formula: NCV = GCO × tax rate
  ##
  ## Use ceil() to round up per specification
  result = int(ceil(float(grossOutput) * (float(taxRate) / 100.0)))

proc calculateProductionOutput*(
    colony: Colony, elTechLevel: int, cstTechLevel: int = 1
): ProductionOutput =
  ## Calculate full production output for colony
  let gco = calculateGrossOutput(colony, elTechLevel, cstTechLevel)
  let ncv = calculateNetValue(gco, colony.taxRate)

  # Calculate component breakdown
  let rawIndex = getRawIndex(colony.planetClass, colony.resources)
  let popProd = int(float(colony.populationUnits) * rawIndex)

  let elMod = getEconomicLevelModifier(elTechLevel)
  let cstMod = 1.0 + (float(cstTechLevel - 1) * 0.10) # CST capacity bonus
  let prodGrowth = getProductivityGrowth(colony.taxRate)
  let starbaseBonus = getStarbaseGrowthBonus(colony)
    # 5% per operational starbase, max 15%
  let indProd = int(
    float(colony.industrial.units) * elMod * cstMod * (1.0 + prodGrowth + starbaseBonus)
  )

  result = ProductionOutput(
    grossOutput: int32(gco),
    netValue: int32(ncv),
    populationProduction: int32(popProd),
    industrialProduction: int32(indProd),
  )

proc applyInfrastructureDamage*(colony: var Colony) =
  ## Apply infrastructure damage to reduce GCO
  ## Bombardment reduces output per operations.md:6.2.6
  ##
  ## Damage reduces both population and industrial production
  if colony.infrastructureDamage > 0.0:
    # Reduce cached GCO by damage percentage
    colony.grossOutput =
      int32(float(colony.grossOutput) * (1.0 - colony.infrastructureDamage))
