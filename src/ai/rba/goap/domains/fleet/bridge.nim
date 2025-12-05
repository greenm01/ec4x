## Fleet Domain RBA Bridge (Domestikos)
##
## Converts RBA requirements → GOAP goals
## Converts GOAP plans → RBA orders
##
## Integration point between tactical RBA and strategic GOAP

import std/[tables, options, sequtils]
import ../../core/[types, conditions]
import goals, actions
import ../../../../../common/types/[core]
import ../../../controller_types

# =============================================================================
# RBA → GOAP Conversion (Phase 2: Placeholder)
# =============================================================================
# Phase 2 Note: Full requirements → goals conversion will be implemented in Phase 4
# For now, we use direct state analysis from goals.nim

proc extractFleetGoalsFromState*(state: WorldStateSnapshot): seq[Goal] =
  ## Extract fleet goals directly from world state analysis
  ##
  ## Uses state analysis functions from goals.nim
  ## This is the primary method for Phase 2-3

  result = @[]

  # Analyze defense needs
  let defenseGoals = analyzeDefenseNeeds(state)
  for goal in defenseGoals:
    result.add(goal)

  # Analyze offensive opportunities
  let offenseGoals = analyzeOffensiveOpportunities(state)
  for goal in offenseGoals:
    result.add(goal)

  # Analyze reconnaissance needs
  let reconGoals = analyzeReconnaissanceNeeds(state)
  for goal in reconGoals:
    result.add(goal)

# =============================================================================
# GOAP → RBA Conversion (Phase 2: Placeholder)
# =============================================================================
# Phase 2 Note: Full plan → orders conversion will be implemented in Phase 4
# For now, plans are validated but not converted to executable orders

proc describeFleetPlan*(plan: GOAPlan): string =
  ## Describe fleet plan in human-readable format
  ##
  ## Used for debugging and logging
  ## Phase 4 will convert to actual game orders

  result = "Fleet Plan: " & plan.goal.description & "\n"
  result.add("  Total Cost: " & $plan.totalCost & " PP\n")
  result.add("  Estimated Turns: " & $plan.estimatedTurns & "\n")
  result.add("  Actions:\n")

  for i, action in plan.actions:
    result.add("    " & $(i+1) & ". " & action.description & "\n")

# =============================================================================
# Plan Validation
# =============================================================================

proc validateFleetPlan*(
  plan: GOAPlan,
  state: WorldStateSnapshot
): bool =
  ## Validate that fleet plan is executable
  ##
  ## Checks:
  ## - Preconditions are met
  ## - Required resources available
  ## - Fleet capacity sufficient

  # Check budget
  if plan.totalCost > state.treasury:
    return false

  # Check preconditions for all actions
  for action in plan.actions:
    if not allPreconditionsMet(state, action.preconditions):
      return false

  # Check fleet availability
  if plan.goal.goalType in [GoalType.DefendColony, GoalType.EstablishFleetPresence]:
    if state.idleFleets.len == 0:
      return false

  return true
