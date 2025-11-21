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

export types.ProductionOutput

## RAW INDEX Table (economy.md:3.1)

const RAW_INDEX_TABLE = [
  # Format: [resource_rating][planet_class] = percentage (0.0-1.4)
  # Rows: Very Poor, Poor, Abundant, Rich, Very Rich
  # Cols: Extreme, Desolate, Hostile, Harsh, Benign, Lush, Eden
  # (Enum order: Extreme=0, Desolate=1, ..., Eden=6)

  [0.60, 0.60, 0.60, 0.60, 0.60, 0.60, 0.60],  # Very Poor
  [0.62, 0.63, 0.64, 0.65, 0.70, 0.75, 0.80],  # Poor (reversed from spec)
  [0.64, 0.66, 0.68, 0.70, 0.80, 0.90, 1.00],  # Abundant (reversed from spec)
  [0.66, 0.69, 0.72, 0.75, 0.90, 1.05, 1.20],  # Rich (reversed from spec)
  [0.68, 0.72, 0.76, 0.80, 1.00, 1.20, 1.40],  # Very Rich (reversed from spec)
]

proc getRawIndex*(planetClass: PlanetClass, resources: ResourceRating): float =
  ## Get RAW INDEX modifier from table
  ## Returns percentage modifier (0.60 - 1.40)
  let resourceIdx = ord(resources)
  let planetIdx = ord(planetClass)
  return RAW_INDEX_TABLE[resourceIdx][planetIdx]

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
