## Income Phase Implementation
##
## Calculates house income, applies taxes, manages treasury per economy.md
##
## Income Phase Steps (gameplay.md:1.3.2):
## 1. Calculate GCO for all colonies (after conflict damage)
## 2. Apply tax policy
## 3. Calculate prestige bonuses/penalties
## 4. Deposit NHV to treasury
## 5. Apply population growth

import std/[math, options]
import
  ../../types/
    [game_state, colony, income, production as production_types, core, prestige]
import ../../prestige/events
import ../../globals
import ../../state/engine
import ./multipliers
import ../production/engine

export colony.ColonyIncomeReport
export income.HouseIncomeReport, income.IncomePhaseReport

## Tax Policy Prestige Effects (economy.md:3.2)

proc calculateTaxPenalty*(avgTaxRate: int): int =
  ## Calculate prestige penalty from high rolling average tax rate
  ## Per economy.md:3.2.1
  if avgTaxRate <= 50:
    return 0
  elif avgTaxRate <= 60:
    return -1
  elif avgTaxRate <= 70:
    return -2
  elif avgTaxRate <= 80:
    return -4
  elif avgTaxRate <= 90:
    return -7
  else:
    return -11

proc calculateTaxBonus*(taxRate: int, colonyCount: int): int =
  ## Calculate prestige bonus from low tax rate
  ## Per economy.md:3.2.2
  ## Returns total prestige for all colonies
  var bonusPerColony = 0

  if taxRate >= 41:
    bonusPerColony = 0
  elif taxRate >= 31:
    bonusPerColony = 0
  elif taxRate >= 21:
    bonusPerColony = 1
  elif taxRate >= 11:
    bonusPerColony = 2
  else:
    bonusPerColony = 3

  return bonusPerColony * colonyCount

proc getPopulationGrowthMultiplier*(taxRate: int): float =
  ## Get population growth multiplier from tax rate
  ## Per economy.md:3.2.2
  if taxRate >= 41:
    return 1.0
  elif taxRate >= 31:
    return 1.05
  elif taxRate >= 21:
    return 1.10
  elif taxRate >= 11:
    return 1.15
  else:
    return 1.20

proc calculateRollingTaxAverage*(history: seq[int]): int =
  ## Calculate 6-turn rolling average tax rate
  ## Per economy.md:3.2.1
  if history.len == 0:
    return 0

  var sum = 0
  let count = min(history.len, 6)
  for i in 0 ..< count:
    sum += history[history.len - 1 - i] # Last 6 entries

  return int(float(sum) / float(count))

## Colony Income Calculation

proc calculateColonyIncome*(
    state: GameState,
    colony: Colony,
    houseELTech: int32,
    houseCSTTech: int32,
    houseTaxRate: int32,
): ColonyIncomeReport =
  ## Calculate income for single colony
  ##
  ## Args:
  ##   state: GameState for accessing planet data
  ##   colony: Colony economic data
  ##   houseELTech: House Economic Level tech
  ##   houseCSTTech: House Construction tech (affects capacity)
  ##   houseTaxRate: House-wide tax rate (colony can override)

  let taxRate =
    if colony.taxRate > 0:
      colony.taxRate
    else:
      houseTaxRate
  let output =
    calculateProductionOutput(
      state, colony, houseELTech, houseCSTTech
    )

  result = ColonyIncomeReport(
    colonyId: colony.id,  # Use actual colony ID, not system ID
    houseId: colony.owner,
    populationUnits: colony.populationUnits,
    grossOutput: output.grossOutput,
    taxRate: int32(taxRate),
    netValue: output.netValue,
    populationGrowth: 0.0, # Calculated later
    prestigeBonus: 0, # Calculated at house level
  )

## House Income Calculation

proc calculateHouseIncome*(
    state: GameState,
    colonies: seq[Colony],
    houseELTech: int32,
    houseCSTTech: int32,
    taxPolicy: TaxPolicy,
    treasury: int32,
): HouseIncomeReport =
  ## Calculate total income for house
  ##
  ## Args:
  ##   state: GameState for accessing planet data
  ##   colonies: All colonies owned by house
  ##   houseELTech: Economic Level tech
  ##   houseCSTTech: Construction tech (affects capacity)
  ##   taxPolicy: House tax policy with history
  ##   treasury: Current treasury balance

  result = HouseIncomeReport(
    houseId:
      if colonies.len > 0:
        colonies[0].owner
      else:
        HouseId(0),
    colonies: @[],
    totalGross: 0,
    totalNet: 0,
    taxRate: taxPolicy.currentRate,
    taxAverage6Turn: 0,
    taxPenalty: 0,
    totalPrestigeBonus: 0,
    treasuryBefore: int32(treasury),
    treasuryAfter: int32(treasury),
    transactions: @[],
    prestigeEvents: @[],
  )

  # Calculate each colony's income
  for colony in colonies:
    let colonyReport =
      calculateColonyIncome(state, colony, houseELTech, houseCSTTech, taxPolicy.currentRate)
    result.colonies.add(colonyReport)
    result.totalGross += colonyReport.grossOutput
    result.totalNet += colonyReport.netValue

  # Calculate tax effects
  var history: seq[int] = @[]
  for h in taxPolicy.history:
    history.add(int(h))
  result.taxAverage6Turn = int32(calculateRollingTaxAverage(history))
  result.taxPenalty = int32(calculateTaxPenalty(result.taxAverage6Turn))
  result.totalPrestigeBonus = int32(calculateTaxBonus(taxPolicy.currentRate, colonies.len))

  # Generate prestige events from tax policy
  # Low tax bonus (using configured thresholds and values)
  if result.totalPrestigeBonus > 0:
    result.prestigeEvents.add(
      createPrestigeEvent(
        PrestigeSource.LowTaxBonus,
        result.totalPrestigeBonus,
        "Low tax bonus (rate: " & $taxPolicy.currentRate & "%, " & $colonies.len &
          " colonies)",
      )
    )

  # High tax penalty (using configured thresholds and values)
  if result.taxPenalty < 0:
    result.prestigeEvents.add(
      createPrestigeEvent(
        PrestigeSource.HighTaxPenalty,
        result.taxPenalty,
        "High tax penalty (avg: " & $result.taxAverage6Turn & "%)",
      )
    )

  # Apply to treasury
  result.treasuryAfter = int32(treasury) + result.totalNet

  # Record transactions
  result.transactions.add(
    TreasuryTransaction(
      source: "Tax Collection",
      amount: result.totalNet,
      category: TransactionCategory.TaxIncome,
    )
  )

## Population Growth

proc getPlanetCapacity*(planetClass: PlanetClass): int =
  ## Get maximum population capacity for planet class
  ## Per planets.nim comments and economy.md:3.6
  case planetClass
  of PlanetClass.Extreme: 20
  of PlanetClass.Desolate: 60
  of PlanetClass.Hostile: 180
  of PlanetClass.Harsh: 500
  of PlanetClass.Benign: 1000
  of PlanetClass.Lush: 2000
  of PlanetClass.Eden: 5000

proc applyPopulationGrowth*(
    state: GameState, colony: var Colony, taxRate: int32, baseGrowthRate: float32
): float32 =
  ## Apply logistic population growth to colony
  ## Returns growth percentage for reporting
  ##
  ## Per economy.md:3.6:
  ## Uses logistic growth function with planet capacity limits
  ## Base growth rate loaded from config (natural_growth_rate)
  ## Modified by tax rate per economy.md:3.2.2
  ##
  ## Logistic growth formula: dP/dt = r × P × (1 - P/K)
  ## Where:
  ##   P = current population
  ##   r = growth rate (base × tax multiplier)
  ##   K = carrying capacity (planet class dependent)
  ##
  ## Args:
  ##   colony: Colony to apply growth to (modified)
  ##   taxRate: Current tax rate (affects growth multiplier)
  ##   baseGrowthRate: Base growth rate from config (e.g., 0.015 for 1.5%)

  let currentPU = float(colony.populationUnits)

  # Get planetClass from System (single source of truth)
  let systemOpt = state.system(colony.systemId)
  if systemOpt.isNone:
    return 0.0  # No growth if system not found
  let starSystem = systemOpt.get()
  let capacity = float(getPlanetCapacity(starSystem.planetClass))

  # Calculate effective growth rate with tax modifier, starbase bonus, and map scaling
  let taxMultiplier = getPopulationGrowthMultiplier(taxRate)
  let starbaseBonus = state.starbaseGrowthBonus(colony)
    # 5% per operational starbase, max 15%
  let mapScaleMultiplier = popGrowthMultiplier()
  let effectiveGrowthRate =
    baseGrowthRate * taxMultiplier * (1.0 + starbaseBonus) * mapScaleMultiplier

  # Apply simplified growth: PU_growth = max(2, floor(PU * rate * modifiers))
  # No logistic limiting - capped at planet capacity instead
  let growth = max(2.0, floor(currentPU * effectiveGrowthRate))

  # Calculate new population (ensure non-negative and within capacity)
  let newPU = int(min(currentPU + growth, capacity))
  colony.populationUnits = int32(max(1, newPU)) # Minimum 1 PU (colony doesn't die from growth)

  # Update PTU using formula: PTU = PU - 1 + exp(0.00657 * PU)
  # Per economy.md:3.6 - exponential relationship between PU and PTU
  let pu = float(colony.populationUnits)
  colony.populationTransferUnits = int32(pu - 1.0 + exp(0.00657 * pu))

  # Return actual growth percentage for reporting
  if currentPU > 0:
    return ((float(colony.populationUnits) - currentPU) / currentPU) * 100.0
  else:
    return 0.0

proc applyIndustrialGrowth*(
    state: GameState, colony: var Colony, taxRate: int, baseGrowthRate: float
): float =
  ## Apply passive industrial growth to colony
  ## IU grows naturally as colonies develop infrastructure
  ## Returns growth amount for reporting
  ##
  ## Design rationale:
  ## - IU should scale with population (spec shows IU at 10-150% of PU)
  ## - Passive growth represents natural industrialization
  ## - Growth rate is lower than population (infrastructure takes longer)
  ## - Target: Reach 50% of PU over ~30 turns with no investment
  ##
  ## Formula: IU growth = max(1, floor(PU / 200)) per turn
  ## - Small colonies (< 200 PU): +1 IU/turn
  ## - Medium colonies (400 PU): +2 IU/turn
  ## - Large colonies (800 PU): +4 IU/turn
  ##
  ## This allows homeworlds (840 PU) starting at 420 IU to reach 840 IU
  ## in ~100 turns of natural growth (players can accelerate with investment)

  let currentIU = float(colony.industrial.units)
  let currentPU = float(colony.populationUnits)

  # Base growth scales with population size (2x accelerated for 30-45 turn games)
  # Larger populations naturally build more infrastructure
  let growthConfig = gameConfig.economy.industrialGrowth
  let baseIndustrialGrowth = max(
    growthConfig.passiveGrowthMinimum,
    floor(currentPU / growthConfig.passiveGrowthDivisor),
  )

  # Apply same tax and starbase modifiers as population
  # Low taxes → more economic freedom → faster industrialization
  let taxMultiplier = getPopulationGrowthMultiplier(taxRate)
  let starbaseBonus = state.starbaseGrowthBonus(colony)
  let effectiveGrowth = baseIndustrialGrowth * taxMultiplier * (1.0 + starbaseBonus)

  # Apply growth
  let newIU = int(currentIU + effectiveGrowth)
  colony.industrial.units = int32(max(0, newIU))

  # Return growth amount
  return effectiveGrowth
