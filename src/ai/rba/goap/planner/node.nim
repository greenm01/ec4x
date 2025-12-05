## GOAP Plan Node
##
## Represents a node in A* search space
## Each node is a state + partial action sequence

import std/[tables, options]
import ../core/types

type
  PlanNode* = object
    ## A node in A* search graph
    state*: WorldStateSnapshot         ## Current world state
    actionsExecuted*: seq[Action]      ## Actions taken to reach this state
    totalCost*: float                  ## g(n): Actual cost from start
    estimatedRemaining*: float         ## h(n): Estimated cost to goal
    totalEstimated*: float             ## f(n) = g(n) + h(n)
    parent*: Option[ref PlanNode]      ## Parent node for path reconstruction

proc newPlanNode*(
  state: WorldStateSnapshot,
  actionsExecuted: seq[Action] = @[],
  totalCost: float = 0.0,
  estimatedRemaining: float = 0.0,
  parent: Option[ref PlanNode] = none(ref PlanNode)
): ref PlanNode =
  ## Create a new plan node
  new(result)
  result.state = state
  result.actionsExecuted = actionsExecuted
  result.totalCost = totalCost
  result.estimatedRemaining = estimatedRemaining
  result.totalEstimated = totalCost + estimatedRemaining
  result.parent = parent

proc `<`*(a, b: ref PlanNode): bool =
  ## Compare nodes by total estimated cost (for priority queue)
  a.totalEstimated < b.totalEstimated
