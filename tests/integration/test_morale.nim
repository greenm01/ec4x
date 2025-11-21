## Integration tests for Morale System

import std/[unittest]
import ../../src/engine/morale/types
import ../../src/common/types/core

suite "Morale System":

  test "Morale level: Collapsing (< -100)":
    let level = getMoraleLevel(-150)
    check level == MoraleLevel.Collapsing

    let modifiers = getMoraleModifiers(level)
    check modifiers.taxEfficiency == 0.5  # -50%
    check modifiers.combatBonus == -0.2   # -20%

  test "Morale level: Very Low (-100 to 0)":
    let level = getMoraleLevel(-50)
    check level == MoraleLevel.VeryLow

    let modifiers = getMoraleModifiers(level)
    check modifiers.taxEfficiency == 0.75  # -25%
    check modifiers.combatBonus == -0.1    # -10%

  test "Morale level: Low (0 to 500)":
    let level = getMoraleLevel(250)
    check level == MoraleLevel.Low

    let modifiers = getMoraleModifiers(level)
    check modifiers.taxEfficiency == 0.9   # -10%
    check modifiers.combatBonus == -0.05   # -5%

  test "Morale level: Normal (500 to 1500)":
    let level = getMoraleLevel(1000)
    check level == MoraleLevel.Normal

    let modifiers = getMoraleModifiers(level)
    check modifiers.taxEfficiency == 1.0   # No modifier
    check modifiers.combatBonus == 0.0     # No modifier

  test "Morale level: High (1500 to 3000)":
    let level = getMoraleLevel(2000)
    check level == MoraleLevel.High

    let modifiers = getMoraleModifiers(level)
    check modifiers.taxEfficiency == 1.1   # +10%
    check modifiers.combatBonus == 0.05    # +5%

  test "Morale level: Very High (3000 to 5000)":
    let level = getMoraleLevel(4000)
    check level == MoraleLevel.VeryHigh

    let modifiers = getMoraleModifiers(level)
    check modifiers.taxEfficiency == 1.2   # +20%
    check modifiers.combatBonus == 0.1     # +10%

  test "Morale level: Exceptional (5000+)":
    let level = getMoraleLevel(6000)
    check level == MoraleLevel.Exceptional

    let modifiers = getMoraleModifiers(level)
    check modifiers.taxEfficiency == 1.3   # +30%
    check modifiers.combatBonus == 0.15    # +15%

  test "Initialize house morale":
    let morale = initHouseMorale("house1".HouseId, 2500)

    check morale.houseId == "house1".HouseId
    check morale.currentLevel == MoraleLevel.High
    check morale.prestige == 2500
    check morale.modifiers.taxEfficiency == 1.1

  test "Update morale when prestige changes":
    var morale = initHouseMorale("house1".HouseId, 1000)
    check morale.currentLevel == MoraleLevel.Normal

    # Prestige increases to High range
    updateMorale(morale, 2000)
    check morale.currentLevel == MoraleLevel.High
    check morale.modifiers.taxEfficiency == 1.1

    # Prestige drops to Low range
    updateMorale(morale, 300)
    check morale.currentLevel == MoraleLevel.Low
    check morale.modifiers.taxEfficiency == 0.9

  test "Morale at exact thresholds":
    # Test boundary conditions
    check getMoraleLevel(-100) == MoraleLevel.VeryLow  # Exactly at threshold
    check getMoraleLevel(0) == MoraleLevel.Low
    check getMoraleLevel(500) == MoraleLevel.Normal
    check getMoraleLevel(1500) == MoraleLevel.High
    check getMoraleLevel(3000) == MoraleLevel.VeryHigh
    check getMoraleLevel(5000) == MoraleLevel.Exceptional

  test "Tax efficiency impact calculation":
    # Demonstrate tax collection impact
    let baseTax = 1000

    # Collapsing morale
    let collapsingMods = getMoraleModifiers(MoraleLevel.Collapsing)
    let collapsingTax = int(float(baseTax) * collapsingMods.taxEfficiency)
    check collapsingTax == 500  # 50% of base

    # Exceptional morale
    let exceptionalMods = getMoraleModifiers(MoraleLevel.Exceptional)
    let exceptionalTax = int(float(baseTax) * exceptionalMods.taxEfficiency)
    check exceptionalTax == 1300  # 130% of base

  test "Combat bonus impact":
    # Show combat effectiveness changes
    let normalMods = getMoraleModifiers(MoraleLevel.Normal)
    check normalMods.combatBonus == 0.0

    let collapsingMods = getMoraleModifiers(MoraleLevel.Collapsing)
    check collapsingMods.combatBonus == -0.2  # 20% weaker

    let exceptionalMods = getMoraleModifiers(MoraleLevel.Exceptional)
    check exceptionalMods.combatBonus == 0.15  # 15% stronger

  test "Morale progression from negative to exceptional":
    # Test full progression path
    var morale = initHouseMorale("test".HouseId, -200)
    check morale.currentLevel == MoraleLevel.Collapsing

    updateMorale(morale, -50)
    check morale.currentLevel == MoraleLevel.VeryLow

    updateMorale(morale, 250)
    check morale.currentLevel == MoraleLevel.Low

    updateMorale(morale, 1000)
    check morale.currentLevel == MoraleLevel.Normal

    updateMorale(morale, 2000)
    check morale.currentLevel == MoraleLevel.High

    updateMorale(morale, 4000)
    check morale.currentLevel == MoraleLevel.VeryHigh

    updateMorale(morale, 6000)
    check morale.currentLevel == MoraleLevel.Exceptional
