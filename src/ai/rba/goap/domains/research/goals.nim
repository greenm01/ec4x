## Research Domain Goals (Logothete)
import std/[tables, options]
import ../../core/[types, conditions]
import ../../../../../common/types/[core, tech]

proc createAchieveTechLevelGoal*(field: TechField, level: int, priority: float): Goal =
  result = Goal(
    goalType: GoalType.AchieveTechLevel,
    priority: priority,
    target: none(SystemId),
    targetHouse: none(HouseId),
    requiredResources: level * 50,
    deadline: none(int),
    preconditions: @[hasMinBudget(level * 50)],
    successCondition: nil,
    description: "Achieve " & $field & " level " & $level
  )

proc createCloseResearchGapGoal*(field: TechField, priority: float): Goal =
  result = Goal(
    goalType: GoalType.CloseResearchGap,
    priority: priority,
    target: none(SystemId),
    targetHouse: none(HouseId),
    requiredResources: 100,
    deadline: none(int),
    preconditions: @[hasMinBudget(100)],
    successCondition: nil,
    description: "Close research gap in " & $field
  )

proc analyzeResearchNeeds*(state: WorldStateSnapshot): seq[Goal] =
  result = @[]
  for techField in state.criticalTechGaps:
    result.add(createCloseResearchGapGoal(techField, priority = 0.8))
