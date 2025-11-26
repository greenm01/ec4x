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

import std/[tables, options]
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

  # Population growth
  BASE_POPULATION_GROWTH* = 0.015  # 1.5% per turn base rate

  # Industrial unit base cost
  BASE_IU_COST* = 30           # Base cost for IU up to 50% of PU

## Helper Procs

proc calculatePTU*(pu: int): int =
  ## Convert PU to PTU per economy.md:3.1
  ## PTU = pu - 1 + exp(0.00657 * pu)
  ##
  ## TODO: Implement proper exponential conversion
  ## For now, simple linear approximation
  result = pu

proc calculatePU*(ptu: int): int =
  ## Convert PTU to PU per economy.md:3.1
  ## Uses Lambert W function (complex)
  ##
  ## TODO: Implement proper inverse conversion
  ## For now, simple linear approximation
  result = ptu

# initColony has been moved to colonization/engine.nim as initNewColony
# This creates the full unified Colony type with all gamestate fields initialized
# See colonization/engine.nim:47 for the new implementation
