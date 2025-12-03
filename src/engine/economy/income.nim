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

import std/math
import types, production
import ../prestige
import ../gamestate  # For unified Colony type

export types.ColonyIncomeReport, types.HouseIncomeReport, types.IncomePhaseReport

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
  for i in 0..<count:
    sum += history[history.len - 1 - i]  # Last 6 entries

  return int(float(sum) / float(count))

## Colony Income Calculation

proc calculateColonyIncome*(colony: Colony, houseELTech: int, houseCSTTech: int, houseTaxRate: int): ColonyIncomeReport =
  ## Calculate income for single colony
  ##
  ## Args:
  ##   colony: Colony economic data
  ##   houseELTech: House Economic Level tech
  ##   houseCSTTech: House Construction tech (affects capacity)
  ##   houseTaxRate: House-wide tax rate (colony can override)

  let taxRate = if colony.taxRate > 0: colony.taxRate else: houseTaxRate
  let output = calculateProductionOutput(colony, houseELTech, houseCSTTech)

  result = ColonyIncomeReport(
    colonyId: colony.systemId,
    owner: colony.owner,
    populationUnits: colony.populationUnits,
    grossOutput: output.grossOutput,
    taxRate: taxRate,
    netValue: output.netValue,
    populationGrowth: 0.0,  # Calculated later
    prestigeBonus: 0        # Calculated at house level
  )

## House Income Calculation

proc calculateHouseIncome*(colonies: seq[Colony], houseELTech: int,
                          houseCSTTech: int, taxPolicy: TaxPolicy, treasury: int): HouseIncomeReport =
  ## Calculate total income for house
  ##
  ## Args:
  ##   colonies: All colonies owned by house
  ##   houseELTech: Economic Level tech
  ##   houseCSTTech: Construction tech (affects capacity)
  ##   taxPolicy: House tax policy with history
  ##   treasury: Current treasury balance

  result = HouseIncomeReport(
    houseId: if colonies.len > 0: colonies[0].owner else: "",
    colonies: @[],
    totalGross: 0,
    totalNet: 0,
    taxRate: taxPolicy.currentRate,
    taxAverage6Turn: 0,
    taxPenalty: 0,
    totalPrestigeBonus: 0,
    treasuryBefore: treasury,
    treasuryAfter: treasury,
    transactions: @[],
    prestigeEvents: @[]
  )

  # Calculate each colony's income
  for colony in colonies:
    let colonyReport = calculateColonyIncome(colony, houseELTech, houseCSTTech, taxPolicy.currentRate)
    result.colonies.add(colonyReport)
    result.totalGross += colonyReport.grossOutput
    result.totalNet += colonyReport.netValue

  # Calculate tax effects
  result.taxAverage6Turn = calculateRollingTaxAverage(taxPolicy.history)
  result.taxPenalty = calculateTaxPenalty(result.taxAverage6Turn)
  result.totalPrestigeBonus = calculateTaxBonus(taxPolicy.currentRate, colonies.len)

  # Generate prestige events from tax policy
  # Low tax bonus (using configured thresholds and values)
  if result.totalPrestigeBonus > 0:
    result.prestigeEvents.add(createPrestigeEvent(
      PrestigeSource.LowTaxBonus,
      result.totalPrestigeBonus,
      "Low tax bonus (rate: " & $taxPolicy.currentRate & "%, " & $colonies.len & " colonies)"
    ))

  # High tax penalty (using configured thresholds and values)
  if result.taxPenalty < 0:
    result.prestigeEvents.add(createPrestigeEvent(
      PrestigeSource.HighTaxPenalty,
      result.taxPenalty,
      "High tax penalty (avg: " & $result.taxAverage6Turn & "%)"
    ))

  # Apply to treasury
  result.treasuryAfter = treasury + result.totalNet

  # Record transactions
  result.transactions.add(TreasuryTransaction(
    source: "Tax Collection",
    amount: result.totalNet,
    category: TransactionCategory.TaxIncome
  ))

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

proc applyPopulationGrowth*(colony: var Colony, taxRate: int, baseGrowthRate: float): float =
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
  let capacity = float(getPlanetCapacity(colony.planetClass))

  # Calculate effective growth rate with tax modifier and starbase bonus
  let taxMultiplier = getPopulationGrowthMultiplier(taxRate)
  let starbaseBonus = getStarbaseGrowthBonus(colony)  # 5% per operational starbase, max 15%
  let effectiveGrowthRate = baseGrowthRate * taxMultiplier * (1.0 + starbaseBonus)

  # Apply logistic growth: dP = r × P × (1 - P/K)
  # Limiting factor prevents growth beyond capacity
  let limitingFactor = 1.0 - (currentPU / capacity)
  let growth = currentPU * effectiveGrowthRate * max(0.0, limitingFactor)

  # Calculate new population (ensure non-negative and within capacity)
  let newPU = int(min(currentPU + growth, capacity))
  colony.populationUnits = max(1, newPU)  # Minimum 1 PU (colony doesn't die from growth)

  # Update PTU
  colony.populationTransferUnits = calculatePTU(colony.populationUnits)

  # Return actual growth percentage for reporting
  if currentPU > 0:
    return ((float(colony.populationUnits) - currentPU) / currentPU) * 100.0
  else:
    return 0.0

proc applyIndustrialGrowth*(colony: var Colony, taxRate: int, baseGrowthRate: float): float =
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

  # Base growth scales with population size
  # Larger populations naturally build more infrastructure
  let baseIndustrialGrowth = max(1.0, floor(currentPU / 200.0))

  # Apply same tax and starbase modifiers as population
  # Low taxes → more economic freedom → faster industrialization
  let taxMultiplier = getPopulationGrowthMultiplier(taxRate)
  let starbaseBonus = getStarbaseGrowthBonus(colony)
  let effectiveGrowth = baseIndustrialGrowth * taxMultiplier * (1.0 + starbaseBonus)

  # Apply growth
  let newIU = int(currentIU + effectiveGrowth)
  colony.industrial.units = max(0, newIU)

  # Return growth amount
  return effectiveGrowth
