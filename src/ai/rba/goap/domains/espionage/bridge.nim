## Espionage Domain RBA Bridge (Drungarius)
import std/[tables, options]
import ../../core/[types, conditions]
import goals, actions
import ../../../../../common/types/[core]

proc extractEspionageGoalsFromState*(state: WorldStateSnapshot): seq[Goal] =
  result = analyzeEspionageTargets(state)

proc describeEspionagePlan*(plan: GOAPlan): string =
  result = "Espionage Plan: " & plan.goal.description & "\n"
