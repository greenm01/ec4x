## Treasurer Budget Splitting Module (Unit Construction Fixes)
##
## Separates strategic budget from capacity filler budget.
## Prevents high-priority requirements from being buried by fillers.
##
## Following DoD (Data-Oriented Design): Pure functions for budget allocation.

import std/[tables, strformat]
import ../../../../engine/logger
import ../../../common/types as ai_common_types
import ../../config
import ../../controller_types

proc getAverageShipCostForAct(act: ai_common_types.GameAct): int =
  ## Get average ship construction cost for act (for capacity-driven budgeting)
  ## Values derived from ships.toml typical ship mix per act
  case act
  of ai_common_types.GameAct.Act1_LandGrab:
    25  # ETACs, Scouts, light escorts
  of ai_common_types.GameAct.Act2_RisingTensions:
    50  # Light Cruisers, Destroyers, Carriers
  of ai_common_types.GameAct.Act3_TotalWar:
    125  # Battlecruisers, Battleships, Dreadnoughts
  of ai_common_types.GameAct.Act4_Endgame:
    200  # Super Dreadnoughts, Planet Breakers

type
  BudgetSplit* = object
    ## Result of splitting total budget into strategic and filler portions
    strategicBudget*: int           # 80-85% for Critical/High requirements
    fillerBudget*: int              # 15-20% for capacity utilization
    strategicByObjective*: Table[ai_common_types.BuildObjective, int]
    fillerReservationPct*: float    # Actual reservation percentage used

proc splitStrategicAndFillerBudgets*(
  controller: AIController,
  totalBudget: int,
  act: ai_common_types.GameAct,
  allocation: Table[ai_common_types.BuildObjective, float],
  availableDocks: int
): BudgetSplit =
  ## Split total budget into strategic requirements and capacity filler budgets
  ##
  ## Strategic budget: 80-85% → High/Critical requirements only
  ## Filler budget: 15-20% → Medium priority capacity utilization
  ##
  ## Act-specific reservations (from config/rba.toml):
  ## - Act 1: 20% filler (expansion focus, need capacity utilization)
  ## - Act 2-4: 15% filler (more strategic focus)

  # Get act-specific filler reservation from config (percentage-based)
  let fillerReservationPct = case act
    of ai_common_types.GameAct.Act1_LandGrab:
      controller.rbaConfig.budget_act1_land_grab.filler_budget_reserved
    of ai_common_types.GameAct.Act2_RisingTensions:
      controller.rbaConfig.budget_act2_rising_tensions.filler_budget_reserved
    of ai_common_types.GameAct.Act3_TotalWar:
      controller.rbaConfig.budget_act3_total_war.filler_budget_reserved
    of ai_common_types.GameAct.Act4_Endgame:
      controller.rbaConfig.budget_act4_endgame.filler_budget_reserved

  # Calculate capacity-driven budget (scales with dock capacity)
  let avgActCost = getAverageShipCostForAct(act)
  let capacityBasedBudget = availableDocks * avgActCost

  # Calculate percentage-based budget (traditional approach)
  let percentageBasedBudget = int(float(totalBudget) * fillerReservationPct)

  # Use higher of the two, but cap at 50% of treasury (prevents runaway spending)
  let uncappedFillerBudget = max(capacityBasedBudget, percentageBasedBudget)
  let maxFillerBudget = totalBudget div 2  # 50% cap
  let fillerBudget = min(uncappedFillerBudget, maxFillerBudget)

  let strategicBudget = totalBudget - fillerBudget

  # Allocate strategic budget across objectives using percentages
  var strategicByObjective: Table[ai_common_types.BuildObjective, int]
  for objective, percentage in allocation:
    let objectiveBudget = int(float(strategicBudget) * percentage)
    strategicByObjective[objective] = objectiveBudget

  logInfo(LogCategory.lcAI,
          &"Budget split ({act}): Strategic={strategicBudget}PP " &
          &"({int(float(strategicBudget) / float(totalBudget) * 100.0)}%), " &
          &"Filler={fillerBudget}PP " &
          &"({int(float(fillerBudget) / float(totalBudget) * 100.0)}%) " &
          &"[percentage={percentageBasedBudget}PP, " &
          &"capacity={capacityBasedBudget}PP ({availableDocks}×{avgActCost}PP), " &
          &"cap={maxFillerBudget}PP]")

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
