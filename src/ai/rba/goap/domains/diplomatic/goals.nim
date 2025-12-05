## Diplomatic Domain Goals (Protostrator)
import std/[tables, options]
import ../../core/[types, conditions]
import ../../../../../common/types/[core]

proc createSecureAllianceGoal*(targetHouse: HouseId, priority: float): Goal =
  result = Goal(
    goalType: GoalType.SecureAlliance,
    priority: priority,
    target: none(SystemId),
    targetHouse: some(targetHouse),
    requiredResources: 0,
    deadline: none(int),
    preconditions: @[],
    successCondition: nil,
    description: "Secure alliance with " & targetHouse
  )

proc createDeclareWarGoal*(targetHouse: HouseId, priority: float): Goal =
  result = Goal(
    goalType: GoalType.DeclareWar,
    priority: priority,
    target: none(SystemId),
    targetHouse: some(targetHouse),
    requiredResources: 0,
    deadline: none(int),
    preconditions: @[],
    successCondition: nil,
    description: "Declare war on " & targetHouse
  )
