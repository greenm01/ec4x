## Test RBA Budget Splitting Module (Gap Fix - Unit Construction)
##
## Tests the strategic vs filler budget split to prevent capacity fillers
## from burying high-priority requirements

import unittest
import std/tables
import ../../src/ai/rba/treasurer/budget/splitting
import ../../src/ai/common/types as ai_types

suite "RBA Budget Splitting":

  test "Act 1 reserves 20% for filler budget":
    # Arrange
    let totalBudget = 1000
    let act = ai_types.GameAct.Act1_LandGrab
    var allocation = initTable[ai_types.BuildObjective, float]()
    allocation[ai_types.BuildObjective.Defense] = 0.10
    allocation[ai_types.BuildObjective.Military] = 0.15
    allocation[ai_types.BuildObjective.Expansion] = 0.45
    allocation[ai_types.BuildObjective.Reconnaissance] = 0.10
    allocation[ai_types.BuildObjective.SpecialUnits] = 0.15
    allocation[ai_types.BuildObjective.Technology] = 0.05

    # Act
    let split = splitStrategicAndFillerBudgets(totalBudget, act, allocation)

    # Assert
    check split.strategicBudget == 800  # 80% of 1000
    check split.fillerBudget == 200     # 20% of 1000
    check split.fillerReservationPct == 0.20

  test "Act 2-4 reserve 15% for filler budget":
    # Arrange
    let totalBudget = 1000
    let act = ai_types.GameAct.Act2_RisingTensions
    var allocation = initTable[ai_types.BuildObjective, float]()
    allocation[ai_types.BuildObjective.Defense] = 0.15
    allocation[ai_types.BuildObjective.Military] = 0.15
    allocation[ai_types.BuildObjective.Expansion] = 0.20
    allocation[ai_types.BuildObjective.Reconnaissance] = 0.15
    allocation[ai_types.BuildObjective.SpecialUnits] = 0.30
    allocation[ai_types.BuildObjective.Technology] = 0.05

    # Act
    let split = splitStrategicAndFillerBudgets(totalBudget, act, allocation)

    # Assert
    check split.strategicBudget == 850  # 85% of 1000
    check split.fillerBudget == 150     # 15% of 1000
    check split.fillerReservationPct == 0.15

  test "Strategic budget allocated by percentages":
    # Arrange
    let totalBudget = 1000
    let act = ai_types.GameAct.Act1_LandGrab
    var allocation = initTable[ai_types.BuildObjective, float]()
    allocation[ai_types.BuildObjective.Defense] = 0.10
    allocation[ai_types.BuildObjective.Military] = 0.20
    allocation[ai_types.BuildObjective.Expansion] = 0.50
    allocation[ai_types.BuildObjective.Reconnaissance] = 0.10
    allocation[ai_types.BuildObjective.SpecialUnits] = 0.05
    allocation[ai_types.BuildObjective.Technology] = 0.05

    # Act
    let split = splitStrategicAndFillerBudgets(totalBudget, act, allocation)

    # Assert - strategic budget is 800PP (80%), distributed by percentages
    check split.strategicByObjective[ai_types.BuildObjective.Defense] == 80      # 10% of 800
    check split.strategicByObjective[ai_types.BuildObjective.Military] == 160    # 20% of 800
    check split.strategicByObjective[ai_types.BuildObjective.Expansion] == 400   # 50% of 800
    check split.strategicByObjective[ai_types.BuildObjective.Reconnaissance] == 80  # 10% of 800
    check split.strategicByObjective[ai_types.BuildObjective.SpecialUnits] == 40   # 5% of 800
    check split.strategicByObjective[ai_types.BuildObjective.Technology] == 40     # 5% of 800

  test "getStrategicBudgetForObjective returns correct amounts":
    # Arrange
    let totalBudget = 1000
    let act = ai_types.GameAct.Act1_LandGrab
    var allocation = initTable[ai_types.BuildObjective, float]()
    allocation[ai_types.BuildObjective.Defense] = 0.10
    allocation[ai_types.BuildObjective.Military] = 0.30
    allocation[ai_types.BuildObjective.Expansion] = 0.40
    allocation[ai_types.BuildObjective.Reconnaissance] = 0.10
    allocation[ai_types.BuildObjective.SpecialUnits] = 0.05
    allocation[ai_types.BuildObjective.Technology] = 0.05

    let split = splitStrategicAndFillerBudgets(totalBudget, act, allocation)

    # Act & Assert
    check getStrategicBudgetForObjective(split, ai_types.BuildObjective.Defense) == 80
    check getStrategicBudgetForObjective(split, ai_types.BuildObjective.Military) == 240
    check getStrategicBudgetForObjective(split, ai_types.BuildObjective.Expansion) == 320

  test "hasFillerBudgetRemaining correctly tracks spending":
    # Arrange
    let totalBudget = 1000
    let act = ai_types.GameAct.Act1_LandGrab
    var allocation = initTable[ai_types.BuildObjective, float]()
    allocation[ai_types.BuildObjective.Defense] = 0.50
    allocation[ai_types.BuildObjective.Military] = 0.50

    let split = splitStrategicAndFillerBudgets(totalBudget, act, allocation)
    # Filler budget is 200PP (20%)

    # Act & Assert
    check hasFillerBudgetRemaining(split, 0) == true      # Nothing spent
    check hasFillerBudgetRemaining(split, 100) == true    # 100PP spent, 100PP remaining
    check hasFillerBudgetRemaining(split, 199) == true    # 199PP spent, 1PP remaining
    check hasFillerBudgetRemaining(split, 200) == false   # All spent
    check hasFillerBudgetRemaining(split, 300) == false   # Overspent

  test "getFillerBudgetRemaining returns correct amount":
    # Arrange
    let totalBudget = 1000
    let act = ai_types.GameAct.Act2_RisingTensions  # 15% filler
    var allocation = initTable[ai_types.BuildObjective, float]()
    allocation[ai_types.BuildObjective.Defense] = 0.50
    allocation[ai_types.BuildObjective.Military] = 0.50

    let split = splitStrategicAndFillerBudgets(totalBudget, act, allocation)
    # Filler budget is 150PP (15%)

    # Act & Assert
    check getFillerBudgetRemaining(split, 0) == 150
    check getFillerBudgetRemaining(split, 50) == 100
    check getFillerBudgetRemaining(split, 150) == 0
    check getFillerBudgetRemaining(split, 200) == 0  # Overspent returns 0
