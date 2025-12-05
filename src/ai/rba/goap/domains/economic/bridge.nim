## Economic Domain RBA Bridge (Eparch)
import std/[tables, options]
import ../../core/[types, conditions]
import goals, actions
import ../../../../../common/types/[core]

proc extractEconomicGoalsFromState*(state: WorldStateSnapshot): seq[Goal] =
  result = @[]

proc describeEconomicPlan*(plan: GOAPlan): string =
  result = "Economic Plan: " & plan.goal.description & "\n"
