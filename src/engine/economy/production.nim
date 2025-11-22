## Colony Production Calculation
##
## Implements GCO (Gross Colony Output) calculation per economy.md:3.1
##
## Formula: GCO = (PU × RAW_INDEX) + (IU × EL_MOD × (1 + PROD_GROWTH))
##
## Components:
## - PU: Population Units
## - RAW_INDEX: Resource quality modifier (60%-140% based on planet/resources)
## - IU: Industrial Units
## - EL_MOD: Economic Level tech modifier
## - PROD_GROWTH: Productivity growth from tax policy

import std/math
import types
import ../../common/types/planets
import ../config/economy_config

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
  ## Per economy.md:3.5 - tech increases productivity
  ##
  ## TODO: Implement proper EL_MOD scaling
  ## Placeholder: +10% per tech level
  result = 1.0 + (float(techLevel) * 0.10)

proc getProductivityGrowth*(taxRate: int): float =
  ## Get PROD_GROWTH from tax rate
  ## Lower taxes = higher productivity growth
  ##
  ## TODO: Implement proper growth curve
  ## Placeholder: Linear relationship
  ## - Tax 100% = -10% growth
  ## - Tax 50% = 0% growth
  ## - Tax 0% = +10% growth
  result = (50.0 - float(taxRate)) / 500.0

proc calculateGrossOutput*(colony: Colony, elTechLevel: int): int =
  ## Calculate GCO (Gross Colony Output) for colony
  ## Per economy.md:3.1
  ##
  ## Formula: GCO = (PU × RAW_INDEX) + (IU × EL_MOD × (1 + PROD_GROWTH))

  # Population production component
  let rawIndex = getRawIndex(colony.planetClass, colony.resources)
  let populationProd = float(colony.populationUnits) * rawIndex

  # Industrial production component
  let elMod = getEconomicLevelModifier(elTechLevel)
  let prodGrowth = getProductivityGrowth(colony.taxRate)
  let industrialProd = float(colony.industrial.units) * elMod * (1.0 + prodGrowth)

  # Total GCO
  result = int(populationProd + industrialProd)

proc calculateNetValue*(grossOutput: int, taxRate: int): int =
  ## Calculate NCV (Net Colony Value) from GCO and tax rate
  ## Per economy.md:3.3
  ##
  ## Formula: NCV = GCO × tax rate
  result = int(float(grossOutput) * (float(taxRate) / 100.0))

proc calculateProductionOutput*(colony: Colony, elTechLevel: int): ProductionOutput =
  ## Calculate full production output for colony
  let gco = calculateGrossOutput(colony, elTechLevel)
  let ncv = calculateNetValue(gco, colony.taxRate)

  # Calculate component breakdown
  let rawIndex = getRawIndex(colony.planetClass, colony.resources)
  let popProd = int(float(colony.populationUnits) * rawIndex)

  let elMod = getEconomicLevelModifier(elTechLevel)
  let prodGrowth = getProductivityGrowth(colony.taxRate)
  let indProd = int(float(colony.industrial.units) * elMod * (1.0 + prodGrowth))

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
