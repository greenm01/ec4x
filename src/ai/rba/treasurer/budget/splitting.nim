## Treasurer Budget Splitting Module (Unit Construction Fixes)
##
## Separates strategic budget from capacity filler budget.
## Prevents high-priority requirements from being buried by fillers.
##
## Following DoD (Data-Oriented Design): Pure functions for budget allocation.

import std/[tables, strformat]
import ../../../../engine/logger
import ../../common/types as ai_common_types
import ../../config

type
  BudgetSplit* = object
    ## Result of splitting total budget into strategic and filler portions
    strategicBudget*: int           # 80-85% for Critical/High requirements
    fillerBudget*: int              # 15-20% for capacity utilization
    strategicByObjective*: Table[ai_common_types.BuildObjective, int]
    fillerReservationPct*: float    # Actual reservation percentage used

proc splitStrategicAndFillerBudgets*(
  totalBudget: int,
  act: ai_common_types.GameAct,
  allocation: Table[ai_common_types.BuildObjective, float]
): BudgetSplit =
  ## Split total budget into strategic requirements and capacity filler budgets
  ##
  ## Strategic budget: 80-85% → High/Critical requirements only
  ## Filler budget: 15-20% → Medium priority capacity utilization
  ##
  ## Act-specific reservations (from config/rba.toml):
  ## - Act 1: 20% filler (expansion focus, need capacity utilization)
  ## - Act 2-4: 15% filler (more strategic focus)

  # Get act-specific filler reservation from config
  let fillerReservationPct = case act
    of ai_common_types.GameAct.Act1_LandGrab:
      globalRBAConfig.budget_act1_land_grab.filler_budget_reserved
    of ai_common_types.GameAct.Act2_RisingTensions:
      globalRBAConfig.budget_act2_rising_tensions.filler_budget_reserved
    of ai_common_types.GameAct.Act3_TotalWar:
      globalRBAConfig.budget_act3_total_war.filler_budget_reserved
    of ai_common_types.GameAct.Act4_Endgame:
      globalRBAConfig.budget_act4_endgame.filler_budget_reserved

  # Calculate split
  let fillerBudget = int(float(totalBudget) * fillerReservationPct)
  let strategicBudget = totalBudget - fillerBudget

  # Allocate strategic budget across objectives using percentages
  var strategicByObjective: Table[ai_common_types.BuildObjective, int]
  for objective, percentage in allocation:
    let objectiveBudget = int(float(strategicBudget) * percentage)
    strategicByObjective[objective] = objectiveBudget

  logInfo(LogCategory.lcAI,
          &"Budget split ({act}): Strategic={strategicBudget}PP " &
          &"({int((1.0 - fillerReservationPct) * 100.0)}%), " &
          &"Filler={fillerBudget}PP " &
          &"({int(fillerReservationPct * 100.0)}%)")

  # Log objective breakdown for diagnostics
  for objective, budget in strategicByObjective:
    logDebug(LogCategory.lcAI,
             &"  Strategic[{objective}] = {budget}PP")

  result = BudgetSplit(
    strategicBudget: strategicBudget,
    fillerBudget: fillerBudget,
    strategicByObjective: strategicByObjective,
    fillerReservationPct: fillerReservationPct
  )

proc getStrategicBudgetForObjective*(
  split: BudgetSplit,
  objective: ai_common_types.BuildObjective
): int =
  ## Get strategic budget allocated to specific objective
  if split.strategicByObjective.hasKey(objective):
    return split.strategicByObjective[objective]
  else:
    return 0

proc hasFillerBudgetRemaining*(split: BudgetSplit, spent: int): bool =
  ## Check if filler budget has remaining capacity
  return spent < split.fillerBudget

proc getFillerBudgetRemaining*(split: BudgetSplit, spent: int): int =
  ## Get remaining filler budget after spending
  result = split.fillerBudget - spent
  if result < 0:
    result = 0
