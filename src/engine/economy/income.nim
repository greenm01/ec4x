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

proc calculateColonyIncome*(colony: Colony, houseELTech: int, houseTaxRate: int): ColonyIncomeReport =
  ## Calculate income for single colony
  ##
  ## Args:
  ##   colony: Colony economic data
  ##   houseELTech: House Economic Level tech
  ##   houseTaxRate: House-wide tax rate (colony can override)

  let taxRate = if colony.taxRate > 0: colony.taxRate else: houseTaxRate
  let output = calculateProductionOutput(colony, houseELTech)

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
                          taxPolicy: TaxPolicy, treasury: int): HouseIncomeReport =
  ## Calculate total income for house
  ##
  ## Args:
  ##   colonies: All colonies owned by house
  ##   houseELTech: Economic Level tech
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
    let colonyReport = calculateColonyIncome(colony, houseELTech, taxPolicy.currentRate)
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

proc applyPopulationGrowth*(colony: var Colony, taxRate: int, baseGrowthRate: float): float =
  ## Apply population growth to colony
  ## Returns growth percentage for reporting
  ##
  ## Per economy.md:3.6:
  ## Base growth rate loaded from config (natural_growth_rate)
  ## Modified by tax rate per economy.md:3.2.2
  ##
  ## Args:
  ##   colony: Colony to apply growth to (modified)
  ##   taxRate: Current tax rate (affects growth multiplier)
  ##   baseGrowthRate: Base growth rate from config (e.g., 0.015 for 1.5%)

  let taxMultiplier = getPopulationGrowthMultiplier(taxRate)
  let growthRate = baseGrowthRate * taxMultiplier

  # Apply logistic growth
  # TODO: Implement proper logistic curve with planet capacity limits
  # For now, simple exponential growth
  let newPU = int(float(colony.populationUnits) * (1.0 + growthRate))
  colony.populationUnits = newPU

  # Update PTU
  colony.populationTransferUnits = calculatePTU(newPU)

  return growthRate * 100.0  # Return as percentage
