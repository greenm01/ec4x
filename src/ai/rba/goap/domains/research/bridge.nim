## Research Domain RBA Bridge (Logothete)
import std/[tables, options]
import ../../core/[types, conditions]
import goals, actions
import ../../../../../common/types/[core]

proc extractResearchGoalsFromState*(state: WorldStateSnapshot): seq[Goal] =
  result = analyzeResearchNeeds(state)

proc describeResearchPlan*(plan: GOAPlan): string =
  result = "Research Plan: " & plan.goal.description & "\n"
  result.add("  Total Cost: " & $plan.totalCost & " RP\n")
