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

import std/[math, options]
import ../../types/[production, colony, starmap, game_state, combat]
import ../../globals
import ../../state/engine

export production.ProductionOutput
export starmap.PlanetClass, starmap.ResourceRating

## RAW INDEX Table (economy.md:3.1)

proc rawIndex*(planetClass: PlanetClass, resources: ResourceRating): float32 =
  ## RAW INDEX modifier from config
  ## Returns percentage modifier (0.60 - 1.40)
  ##
  ## Uses config/economy.kdl raw_material_efficiency section
  ## Direct array access - O(1) lookup by enum values
  gameConfig.economy.rawMaterialEfficiency.multipliers[resources][planetClass]

proc economicLevelModifier*(techLevel: int32): float32 =
  ## EL_MOD from tech level
  ## Per economy.md:4.2 - "A House's GHO benefits from EL upgrades by 5% per level"
  ##
  ## CRITICAL: Tech starts at EL1 (gameplay.md:1.2), so EL1 = 1.05 (5% bonus)
  ## Formula: 1.0 + (techLevel × 0.05)
  ## - EL1 = 1.05 (5% bonus)
  ## - EL2 = 1.10 (10% bonus)
  ## - EL10 = 1.50 (50% bonus maximum)
  result = 1.0 + (float32(techLevel) * 0.05)

proc productivityGrowth*(taxRate: int32): float32 =
  ## PROD_GROWTH from tax rate
  ## Lower taxes = higher productivity growth
  ##
  ## Linear growth curve per economy.md:
  ## - Tax 100% = -10% growth (harsh taxation suppresses productivity)
  ## - Tax 50% = 0% growth (neutral baseline)
  ## - Tax 0% = +10% growth (economic freedom boosts productivity)
  ##
  ## Formula: PROD_GROWTH = (50 - taxRate) / 500
  result = (50.0 - float32(taxRate)) / 500.0

proc starbaseGrowthBonus*(state: GameState, colony: Colony): float32 =
  ## Starbase growth bonus for colony
  ## Per economy.md: +5% per operational starbase, max +15% (3 starbases)
  ##
  ## Counts operational (non-crippled) Kastras (Starbases) at colony
  var operationalStarbases: int32 = 0

  for kastraId in colony.kastraIds:
    let kastraOpt = state.kastra(kastraId)
    if kastraOpt.isSome:
      let kastra = kastraOpt.get()
      if kastra.state != CombatState.Crippled:
        operationalStarbases += 1

  # Cap at 3 starbases for max 15% bonus
  let effectiveStarbases = min(operationalStarbases, 3)
  return float32(effectiveStarbases) * 0.05

proc calculateGrossOutput*(
    state: GameState, colony: Colony, elTechLevel: int32, cstTechLevel: int32 = 1
): int32 =
  ## Calculate GCO (Gross Colony Output) for colony
  ## Per economy.md:3.1 and 4.5
  ##
  ## Formula: GCO = (PU × RAW_INDEX) + (IU × EL_MOD × CST_MOD × (1 + PROD_GROWTH))
  ## CST_MOD: Construction capacity multiplier per economy.md:4.5 (+10% per level)

  # Validate inputs - negative population/IU should not produce negative output
  let validPopulationUnits = max(0, colony.populationUnits)
  let validIndustrialUnits = max(0, colony.industrial.units)

  # Get planetClass and resources from System (single source of truth)
  let systemOpt = state.system(colony.systemId)
  if systemOpt.isNone:
    return 0  # No production if system not found
  let system = systemOpt.get()

  # Population production component
  let rawIdx = rawIndex(system.planetClass, system.resourceRating)
  let populationProd = float32(validPopulationUnits) * rawIdx

  # Industrial production component
  let elMod = economicLevelModifier(elTechLevel)
  let cstMod = 1.0 + (float32(cstTechLevel - 1) * 0.10) # CST capacity bonus
  let prodGrowth = productivityGrowth(colony.taxRate)
  let starbaseBonus = state.starbaseGrowthBonus(colony)
    # 5% per operational starbase, max 15%
  let industrialProd =
    float32(validIndustrialUnits) * elMod * cstMod * (1.0 + prodGrowth + starbaseBonus)

  # Total GCO (guaranteed non-negative)
  var totalGCO = populationProd + industrialProd

  # Apply blockade penalty: 60% reduction → 40% effective
  # Per operations.md:6.2.6: "Blockaded colonies produce at 40% capacity"
  if colony.blockaded:
    totalGCO = totalGCO * 0.4

  result = int32(totalGCO)

proc calculateNetValue*(grossOutput: int32, taxRate: int32): int32 =
  ## Calculate NCV (Net Colony Value) from GCO and tax rate
  ## Per economy.md:3.2: "PP Income = Total GCO across all colonies × Tax Rate (rounded up)"
  ## Per economy.md:3.3: Formula: NCV = GCO × tax rate
  ##
  ## Use ceil() to round up per specification
  result = int32(ceil(float32(grossOutput) * (float32(taxRate) / 100.0)))

proc calculateProductionOutput*(
    state: GameState, colony: Colony, elTechLevel: int32, cstTechLevel: int32 = 1
): ProductionOutput =
  ## Calculate full production output for colony
  let gco = state.calculateGrossOutput(colony, elTechLevel, cstTechLevel)
  let ncv = calculateNetValue(gco, colony.taxRate)

  # Get planetClass and resources from System (single source of truth)
  let systemOpt = state.system(colony.systemId)
  if systemOpt.isNone:
    return ProductionOutput(
      grossOutput: 0, netValue: 0, populationProduction: 0, industrialProduction: 0
    )
  let system = systemOpt.get()

  # Calculate component breakdown
  let rawIdx = rawIndex(system.planetClass, system.resourceRating)
  let popProd = int32(float32(colony.populationUnits) * rawIdx)

  let elMod = economicLevelModifier(elTechLevel)
  let cstMod = 1.0 + (float32(cstTechLevel - 1) * 0.10) # CST capacity bonus
  let prodGrowth = productivityGrowth(colony.taxRate)
  let starbaseBonus = state.starbaseGrowthBonus(colony)
    # 5% per operational starbase, max 15%
  let indProd = int32(
    float32(colony.industrial.units) * elMod * cstMod * (1.0 + prodGrowth + starbaseBonus)
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
      int32(float32(colony.grossOutput) * (1.0 - colony.infrastructureDamage))
