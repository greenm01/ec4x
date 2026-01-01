## Unit tests for Morale Check System
import std/unittest
import ../../src/engine/systems/combat/cer
import ../../src/engine/engine
import ../../src/engine/globals

suite "Morale Check Tests":
  setup:
    discard newGame()

  test "getMoraleTierFromPrestige: Crisis (≤0)":
    check getMoraleTierFromPrestige(-10) == MoraleTier.Collapsing
    check getMoraleTierFromPrestige(0) == MoraleTier.Collapsing

  test "getMoraleTierFromPrestige: VeryLow (≤10)":
    check getMoraleTierFromPrestige(1) == MoraleTier.VeryLow
    check getMoraleTierFromPrestige(10) == MoraleTier.VeryLow

  test "getMoraleTierFromPrestige: Low (≤20)":
    check getMoraleTierFromPrestige(11) == MoraleTier.Low
    check getMoraleTierFromPrestige(20) == MoraleTier.Low

  test "getMoraleTierFromPrestige: Normal (≤60)":
    check getMoraleTierFromPrestige(21) == MoraleTier.Normal
    check getMoraleTierFromPrestige(60) == MoraleTier.Normal

  test "getMoraleTierFromPrestige: High (≤80)":
    check getMoraleTierFromPrestige(61) == MoraleTier.High
    check getMoraleTierFromPrestige(80) == MoraleTier.High

  test "getMoraleTierFromPrestige: VeryHigh (>100)":
    check getMoraleTierFromPrestige(101) == MoraleTier.VeryHigh
    check getMoraleTierFromPrestige(200) == MoraleTier.VeryHigh

  test "rollMoraleCheck: Collapsing tier applies penalty regardless":
    var rng = initRNG(12345)
    let result = rollMoraleCheck(0, rng)
    check result.rolled == true
    check result.cerBonus == -1  # Penalty always applies
    check result.appliesTo == MoraleEffectTarget.None

  test "rollMoraleCheck: Success grants CER bonus":
    # Use high prestige (VeryHigh tier) for high success chance
    var rng = initRNG(99999)
    var successCount = 0
    var bonusSum = 0

    # Roll multiple times
    for i in 0 ..< 10:
      let result = rollMoraleCheck(150, rng)
      if result.success:
        successCount += 1
        bonusSum += result.cerBonus

    # VeryHigh tier has threshold 6, so most rolls should succeed
    check successCount > 0
    check bonusSum > 0

  test "rollMoraleCheck: Uses config thresholds":
    let cfg = gameConfig.combat.moraleChecks[MoraleTier.Normal]
    check cfg.threshold == 12  # From combat.kdl
    check cfg.cerBonus == 1
    check cfg.appliesTo == MoraleEffectTarget.All

  test "rollMoraleCheck: High morale config has criticalAutoSuccess":
    let cfg = gameConfig.combat.moraleChecks[MoraleTier.High]
    check cfg.criticalAutoSuccess == true
