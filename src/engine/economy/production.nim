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
import types
import ../../common/types/planets
import ../config/economy_config
import ../gamestate  # For unified Colony type

export types.ProductionOutput

## RAW INDEX Table (economy.md:3.1)

proc getRawIndex*(planetClass: PlanetClass, resources: ResourceRating): float =
  ## Get RAW INDEX modifier from config
  ## Returns percentage modifier (0.60 - 1.40)
  ##
  ## Uses config/economy.toml raw_material_efficiency section
  let cfg = globalEconomyConfig.raw_material_efficiency

  # Map enum values to config fields
  # ResourceRating: VeryPoor=0, Poor=1, Abundant=2, Rich=3, VeryRich=4
  # PlanetClass: Extreme=0, Desolate=1, Hostile=2, Harsh=3, Benign=4, Lush=5, Eden=6
  case resources
  of ResourceRating.VeryPoor:
    case planetClass
    of PlanetClass.Extreme: return cfg.very_poor_extreme
    of PlanetClass.Desolate: return cfg.very_poor_desolate
    of PlanetClass.Hostile: return cfg.very_poor_hostile
    of PlanetClass.Harsh: return cfg.very_poor_harsh
    of PlanetClass.Benign: return cfg.very_poor_benign
    of PlanetClass.Lush: return cfg.very_poor_lush
    of PlanetClass.Eden: return cfg.very_poor_eden
  of ResourceRating.Poor:
    case planetClass
    of PlanetClass.Extreme: return cfg.poor_extreme
    of PlanetClass.Desolate: return cfg.poor_desolate
    of PlanetClass.Hostile: return cfg.poor_hostile
    of PlanetClass.Harsh: return cfg.poor_harsh
    of PlanetClass.Benign: return cfg.poor_benign
    of PlanetClass.Lush: return cfg.poor_lush
    of PlanetClass.Eden: return cfg.poor_eden
  of ResourceRating.Abundant:
    case planetClass
    of PlanetClass.Extreme: return cfg.abundant_extreme
    of PlanetClass.Desolate: return cfg.abundant_desolate
    of PlanetClass.Hostile: return cfg.abundant_hostile
    of PlanetClass.Harsh: return cfg.abundant_harsh
    of PlanetClass.Benign: return cfg.abundant_benign
    of PlanetClass.Lush: return cfg.abundant_lush
    of PlanetClass.Eden: return cfg.abundant_eden
  of ResourceRating.Rich:
    case planetClass
    of PlanetClass.Extreme: return cfg.rich_extreme
    of PlanetClass.Desolate: return cfg.rich_desolate
    of PlanetClass.Hostile: return cfg.rich_hostile
    of PlanetClass.Harsh: return cfg.rich_harsh
    of PlanetClass.Benign: return cfg.rich_benign
    of PlanetClass.Lush: return cfg.rich_lush
    of PlanetClass.Eden: return cfg.rich_eden
  of ResourceRating.VeryRich:
    case planetClass
    of PlanetClass.Extreme: return cfg.very_rich_extreme
    of PlanetClass.Desolate: return cfg.very_rich_desolate
    of PlanetClass.Hostile: return cfg.very_rich_hostile
    of PlanetClass.Harsh: return cfg.very_rich_harsh
    of PlanetClass.Benign: return cfg.very_rich_benign
    of PlanetClass.Lush: return cfg.very_rich_lush
    of PlanetClass.Eden: return cfg.very_rich_eden

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

proc calculateGrossOutput*(colony: Colony, elTechLevel: int, cstTechLevel: int = 1): int =
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
  let cstMod = 1.0 + (float(cstTechLevel - 1) * 0.10)  # CST capacity bonus
  let prodGrowth = getProductivityGrowth(colony.taxRate)
  let starbaseBonus = getStarbaseGrowthBonus(colony)  # 5% per operational starbase, max 15%
  let industrialProd = float(validIndustrialUnits) * elMod * cstMod * (1.0 + prodGrowth + starbaseBonus)

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

proc calculateProductionOutput*(colony: Colony, elTechLevel: int, cstTechLevel: int = 1): ProductionOutput =
  ## Calculate full production output for colony
  let gco = calculateGrossOutput(colony, elTechLevel, cstTechLevel)
  let ncv = calculateNetValue(gco, colony.taxRate)

  # Calculate component breakdown
  let rawIndex = getRawIndex(colony.planetClass, colony.resources)
  let popProd = int(float(colony.populationUnits) * rawIndex)

  let elMod = getEconomicLevelModifier(elTechLevel)
  let cstMod = 1.0 + (float(cstTechLevel - 1) * 0.10)  # CST capacity bonus
  let prodGrowth = getProductivityGrowth(colony.taxRate)
  let starbaseBonus = getStarbaseGrowthBonus(colony)  # 5% per operational starbase, max 15%
  let indProd = int(float(colony.industrial.units) * elMod * cstMod * (1.0 + prodGrowth + starbaseBonus))

  result = ProductionOutput(
    grossOutput: gco,
    netValue: ncv,
    populationProduction: popProd,
    industrialProduction: indProd
  )

proc applyInfrastructureDamage*(colony: var Colony) =
  ## Apply infrastructure damage to reduce GCO
  ## Bombardment reduces output per operations.md:6.2.6
  ##
  ## Damage reduces both population and industrial production
  if colony.infrastructureDamage > 0.0:
    # Reduce cached GCO by damage percentage
    colony.grossOutput = int(float(colony.grossOutput) * (1.0 - colony.infrastructureDamage))
