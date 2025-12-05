## Espionage Domain Goals (Drungarius)
import std/[tables, options]
import ../../core/[types, conditions]
import ../../../../../common/types/[core]

proc createStealTechnologyGoal*(targetHouse: HouseId, priority: float): Goal =
  result = Goal(
    goalType: GoalType.StealTechnology,
    priority: priority,
    target: none(SystemId),
    targetHouse: some(targetHouse),
    requiredResources: 200,  # 5 EBP * 40 PP
    deadline: none(int),
    preconditions: @[hasMinBudget(200)],
    successCondition: nil,
    description: "Steal technology from " & targetHouse
  )

proc createSabotageEconomyGoal*(targetHouse: HouseId, systemId: SystemId, priority: float): Goal =
  result = Goal(
    goalType: GoalType.SabotageEconomy,
    priority: priority,
    target: some(systemId),
    targetHouse: some(targetHouse),
    requiredResources: 120,  # Average of low/high sabotage
    deadline: none(int),
    preconditions: @[hasMinBudget(120)],
    successCondition: nil,
    description: "Sabotage economy at system " & $systemId
  )

proc analyzeEspionageTargets*(state: WorldStateSnapshot): seq[Goal] =
  result = @[]
  for targetHouse in state.espionageTargets:
    result.add(createStealTechnologyGoal(targetHouse, priority = 0.6))
