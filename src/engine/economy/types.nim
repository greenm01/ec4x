## Economy System Types
##
## Type definitions for economy system per economy.md
##
## Core economic concepts:
## - PU (Population Units): Economic production measure
## - PTU (Population Transfer Units): ~50k souls for colonization
## - GCO (Gross Colony Output): Total colony production
## - NCV (Net Colony Value): Taxed colony revenue
## - IU (Industrial Units): Manufacturing capacity

import std/[tables, options, math]
import ../../common/types/[core, planets]
import ../prestige  # For PrestigeEvent

export core.HouseId, core.SystemId
export prestige.PrestigeEvent

type
  ## Production and Output

  ProductionOutput* = object
    ## Output from a single colony or entire house
    grossOutput*: int           # GCO: Total production before tax
    netValue*: int              # NCV: After tax collection
    populationProduction*: int  # Production from PU × RAW_INDEX
    industrialProduction*: int  # Production from IU × EL_MOD

  ## Colony Economics

  IndustrialUnits* = object
    ## Industrial capacity at colony
    units*: int                 # Number of IU
    investmentCost*: int        # Cost to add next IU (varies by % of PU)

  ## Construction

  ConstructionType* {.pure.} = enum
    Ship,           # Ship construction
    Building,       # Spaceport, Shipyard, etc.
    Industrial,     # IU investment
    Infrastructure, # Colony development

  ConstructionProject* = object
    ## Construction project at colony
    projectType*: ConstructionType
    itemId*: string             # Ship type, building name, etc.
    costTotal*: int             # Total PP cost
    costPaid*: int              # PP already invested
    turnsRemaining*: int        # Estimated completion (can vary)

  CompletedProject* = object
    ## Construction project completed this turn
    colonyId*: SystemId
    projectType*: ConstructionType
    itemId*: string

  ## Tax and Treasury

  TaxPolicy* = object
    ## House tax policy
    currentRate*: int           # 0-100, this turn
    history*: seq[int]          # Last 6 turns (for average calculation)

  TreasuryTransaction* = object
    ## Single income/expense transaction
    source*: string             # Description
    amount*: int                # Positive = income, negative = expense
    category*: TransactionCategory

  TransactionCategory* {.pure.} = enum
    TaxIncome,          # Colony tax collection
    Construction,       # Ship/building construction
    Maintenance,        # Fleet/facility upkeep
    Research,           # R&D investment
    IndustrialInvestment,  # IU purchase
    Terraforming,       # Planet improvement
    Prestige,           # Prestige-related income/penalty

  ## Reports

  ColonyIncomeReport* = object
    ## Income report for single colony
    colonyId*: SystemId
    owner*: HouseId
    populationUnits*: int
    grossOutput*: int           # GCO
    taxRate*: int
    netValue*: int              # NCV
    populationGrowth*: float    # PU growth this turn (%)
    prestigeBonus*: int         # From low tax rate

  HouseIncomeReport* = object
    ## Income report for entire house
    houseId*: HouseId
    colonies*: seq[ColonyIncomeReport]
    totalGross*: int            # Sum of all GCO
    totalNet*: int              # Sum of all NCV
    taxRate*: int               # House-wide tax rate
    taxAverage6Turn*: int       # Rolling 6-turn average
    taxPenalty*: int            # Prestige penalty from high taxes
    totalPrestigeBonus*: int    # Prestige bonus from low taxes
    treasuryBefore*: int
    treasuryAfter*: int
    transactions*: seq[TreasuryTransaction]
    prestigeEvents*: seq[PrestigeEvent]  # Prestige changes this turn

  IncomePhaseReport* = object
    ## Complete income phase results
    turn*: int
    houseReports*: Table[HouseId, HouseIncomeReport]

  ## Maintenance

  MaintenanceReport* = object
    ## Maintenance phase results
    turn*: int
    completedProjects*: seq[CompletedProject]
    houseUpkeep*: Table[HouseId, int]
    repairsApplied*: seq[tuple[colonyId: SystemId, repairAmount: float]]

## Constants per economy.md

const
  # Tax rate thresholds
  TAX_HIGH_THRESHOLD* = 50     # Above this triggers prestige penalty

  # Industrial unit base cost
  BASE_IU_COST* = 30           # Base cost for IU up to 50% of PU

  # NOTE: BASE_POPULATION_GROWTH removed - now loaded from config/economy.toml
  # Use GameConfig.economy.naturalGrowthRate instead

## Helper Procs

proc calculatePTU*(pu: int): int =
  ## Convert PU to PTU per economy.md:3.1
  ## Formula: PTU = pu - 1 + exp(0.00657 * pu)
  ##
  ## This exponential relationship models dis-inflationary economics:
  ## High-PU colonies contribute many PTUs with minimal PU loss,
  ## incentivizing population concentration and growth.

  if pu <= 0:
    return 0

  if pu == 1:
    # PTU = 1 - 1 + exp(0.00657) = 0 + 1.0066 ≈ 1
    return 1

  const conversionFactor = 0.00657
  let exponent = conversionFactor * float(pu)
  let expValue = exp(exponent)

  result = pu - 1 + int(round(expValue))

proc calculatePU*(ptu: int): int =
  ## Convert PTU to PU per economy.md:3.1
  ## Inverse of calculatePTU using binary search approximation
  ## (Lambert W function is complex to implement in Nim)
  ##
  ## Accurate within ±1 PU which is acceptable for game mechanics

  if ptu <= 0:
    return 0

  if ptu == 1:
    return 1

  # Binary search for PU that gives target PTU
  var low = 1
  var high = ptu + 100  # Upper bound estimate

  while low < high:
    let mid = (low + high) div 2
    let calculatedPTU = calculatePTU(mid)

    if calculatedPTU < ptu:
      low = mid + 1
    elif calculatedPTU > ptu:
      high = mid
    else:
      return mid  # Exact match

  # Return closest PU value
  let ptuLow = calculatePTU(low)
  let ptuHigh = if high <= ptu + 100: calculatePTU(high) else: int.high

  if abs(ptuLow - ptu) < abs(ptuHigh - ptu):
    result = low
  else:
    result = high

# initColony has been moved to colonization/engine.nim as initNewColony
# This creates the full unified Colony type with all gamestate fields initialized
# See colonization/engine.nim:47 for the new implementation
