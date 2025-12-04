## Resource Tracking - Generic Budget/Resource Management
##
## Provides reusable budget tracking infrastructure for both RBA and potential GOAP.
## Prevents overspending by maintaining running totals per objective.
##
## Design:
## - Generic over objective types (not hardcoded to BuildObjective)
## - Thread-safe for future parallel execution
## - Detailed logging for debugging

import std/[tables, strformat]
import ../../../../engine/logger
import ../../../../common/types/core

type
  ResourceTracker*[ObjectiveType] = object
    ## Generic resource tracker for any objective-based allocation
    ## ObjectiveType: enum of objectives (e.g., BuildObjective, ResearchObjective)
    ownerId*: HouseId
    totalBudget*: int
    allocated*: Table[ObjectiveType, int]
    spent*: Table[ObjectiveType, int]
    transactionCount*: int

proc initResourceTracker*[T](ownerId: HouseId, totalBudget: int,
                              allocation: Table[T, float]): ResourceTracker[T] =
  ## Create new resource tracker with percentage allocations
  ## allocation: Table mapping objectives to percentage (0.0-1.0)
  result = ResourceTracker[T](
    ownerId: ownerId,
    totalBudget: totalBudget,
    allocated: initTable[T, int](),
    spent: initTable[T, int](),
    transactionCount: 0
  )

  # Convert percentages to absolute budgets
  for objective, percentage in allocation:
    result.allocated[objective] = int(float(totalBudget) * percentage)
    result.spent[objective] = 0

  logDebug(LogCategory.lcAI,
           &"{ownerId} ResourceTracker initialized: {totalBudget} total budget")

proc canAfford*[T](tracker: ResourceTracker[T], objective: T, cost: int): bool =
  ## Check if objective has sufficient remaining budget
  let remaining = tracker.allocated[objective] - tracker.spent[objective]
  result = remaining >= cost

  if not result:
    logDebug(LogCategory.lcAI,
             &"{tracker.ownerId} Insufficient budget for {objective}: " &
             &"need {cost}, have {remaining}")

proc recordTransaction*[T](tracker: var ResourceTracker[T], objective: T, cost: int) =
  ## Record spending against objective budget
  ## Must be called after successful resource allocation
  tracker.spent[objective] += cost
  tracker.transactionCount += 1

  logDebug(LogCategory.lcAI,
           &"{tracker.ownerId} Transaction #{tracker.transactionCount}: " &
           &"{cost} spent on {objective}")

proc getRemainingBudget*[T](tracker: ResourceTracker[T], objective: T): int =
  ## Get unspent budget for specific objective
  result = tracker.allocated[objective] - tracker.spent[objective]

proc getTotalSpent*[T](tracker: ResourceTracker[T]): int =
  ## Calculate total spending across all objectives
  result = 0
  for spent in tracker.spent.values:
    result += spent

proc getTotalRemaining*[T](tracker: ResourceTracker[T]): int =
  ## Calculate total unspent budget across all objectives
  result = tracker.totalBudget - tracker.getTotalSpent()

proc getUtilization*[T](tracker: ResourceTracker[T]): float =
  ## Calculate budget utilization percentage (0.0-1.0)
  if tracker.totalBudget == 0:
    return 0.0
  return tracker.getTotalSpent().float / tracker.totalBudget.float

proc logSummary*[T](tracker: ResourceTracker[T]) =
  ## Log detailed budget summary for debugging
  let totalSpent = tracker.getTotalSpent()
  let utilization = tracker.getUtilization()
  let utilizationPct = int(utilization * 100.0)

  logInfo(LogCategory.lcAI,
          &"{tracker.ownerId} ResourceTracker Summary: " &
          &"Total={tracker.totalBudget}, Spent={totalSpent} ({utilizationPct}%), " &
          &"Transactions={tracker.transactionCount}")

  for objective, allocated in tracker.allocated:
    let spent = tracker.spent[objective]
    let remaining = allocated - spent
    logDebug(LogCategory.lcAI,
             &"  {objective}: allocated={allocated}, spent={spent}, remaining={remaining}")
