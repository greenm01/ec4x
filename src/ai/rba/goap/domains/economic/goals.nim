## Economic Domain Goals (Eparch)
import std/[tables, options]
import ../../core/[types, conditions]
import ../../../../../common/types/[core]

proc createTransferPopulationGoal*(fromSystem: SystemId, toSystem: SystemId, priority: float): Goal =
  result = Goal(
    goalType: GoalType.TransferPopulation,
    priority: priority,
    target: some(toSystem),
    targetHouse: none(HouseId),
    requiredResources: 100,  # PTU transfer cost
    deadline: none(int),
    preconditions: @[hasMinBudget(100)],
    successCondition: nil,
    description: "Transfer population from " & $fromSystem & " to " & $toSystem
  )

proc createTerraformPlanetGoal*(systemId: SystemId, priority: float): Goal =
  result = Goal(
    goalType: GoalType.TerraformPlanet,
    priority: priority,
    target: some(systemId),
    targetHouse: none(HouseId),
    requiredResources: 500,
    deadline: none(int),
    preconditions: @[controlsSystem(systemId), hasMinBudget(500)],
    successCondition: nil,
    description: "Terraform planet at system " & $systemId
  )
