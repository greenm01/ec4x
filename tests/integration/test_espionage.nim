## Integration test for espionage system

import std/[unittest, random, options]
import ../../src/engine/espionage/[types, engine]
import ../../src/engine/prestige
import ../../src/engine/config/[prestige_config, espionage_config]
import ../../src/common/types/core

suite "Espionage System":

  test "EBP/CIP purchase":
    var budget = initEspionageBudget()
    budget.turnBudget = 1000

    # Purchase EBP
    let ebp = purchaseEBP(budget, 80)  # 80 PP = 2 EBP
    check ebp == 2
    check budget.ebpPoints == 2
    check budget.ebpInvested == 80

    # Purchase CIP
    let cip = purchaseCIP(budget, 120)  # 120 PP = 3 CIP
    check cip == 3
    check budget.cipPoints == 3
    check budget.cipInvested == 120

  test "Over-investment penalty calculation":
    var budget = initEspionageBudget()
    budget.turnBudget = 1000

    # 5% threshold = 50 PP
    # 7% investment = 70 PP = 2% over
    let penalty = calculateOverInvestmentPenalty(70, 1000)
    check penalty == -2  # -1 per 1% over threshold

    # No penalty at threshold
    let noPenalty = calculateOverInvestmentPenalty(50, 1000)
    check noPenalty == 0

  test "Action costs from config":
    check getActionCost(EspionageAction.TechTheft) == globalEspionageConfig.costs.tech_theft_ebp
    check getActionCost(EspionageAction.SabotageLow) == globalEspionageConfig.costs.sabotage_low_ebp
    check getActionCost(EspionageAction.Assassination) == globalEspionageConfig.costs.assassination_ebp

  test "Detection thresholds from config":
    check getDetectionThreshold(CICLevel.CIC0) == globalEspionageConfig.detection.cic0_threshold
    check getDetectionThreshold(CICLevel.CIC3) == globalEspionageConfig.detection.cic3_threshold
    check getDetectionThreshold(CICLevel.CIC5) == globalEspionageConfig.detection.cic5_threshold

  test "CIP modifiers from config":
    let config = globalEspionageConfig
    check getCIPModifier(0) == config.detection.cip_0_modifier
    check getCIPModifier(3) == config.detection.cip_1_5_modifier
    check getCIPModifier(8) == config.detection.cip_6_10_modifier
    check getCIPModifier(12) == config.detection.cip_11_15_modifier
    check getCIPModifier(25) == config.detection.cip_21_plus_modifier



  test "Detection system: CIC0 always fails":
    var rng = initRand(99999)
    let attempt = DetectionAttempt(
      defender: "house2".HouseId,
      cicLevel: CICLevel.CIC0,
      cipPoints: 10,
      action: EspionageAction.TechTheft
    )

    let result = attemptDetection(attempt, rng)
    check result.detected == false

  test "Detection system: CIC5 with high CIP very likely succeeds":
    var rng = initRand(88888)
    let attempt = DetectionAttempt(
      defender: "house2".HouseId,
      cicLevel: CICLevel.CIC5,
      cipPoints: 25,  # +5 modifier
      action: EspionageAction.TechTheft
    )

    # With CIC5 (threshold 4) and +5 modifier, any roll >= -1 succeeds
    # So virtually guaranteed
    let result = attemptDetection(attempt, rng)
    # Can't guarantee but very high probability
    check result.threshold == globalEspionageConfig.detection.cic5_threshold
    check result.modifier == globalEspionageConfig.detection.cip_21_plus_modifier

  test "Execute espionage with detection":
    var rng = initRand(77777)
    let attempt = EspionageAttempt(
      attacker: "house1".HouseId,
      target: "house2".HouseId,
      action: EspionageAction.TechTheft,
      targetSystem: none(SystemId)
    )

    # CIC0 = no detection
    let result = executeEspionage(attempt, CICLevel.CIC0, 0, rng)
    check result.success == true

  test "Budget management: can afford action":
    var budget = initEspionageBudget()
    discard purchaseEBP(budget, 200)  # 5 EBP

    check canAffordAction(budget, EspionageAction.TechTheft) == true
    check canAffordAction(budget, EspionageAction.Assassination) == false  # Needs 10 EBP

  test "Budget management: spend EBP":
    var budget = initEspionageBudget()
    discard purchaseEBP(budget, 200)  # 5 EBP

    let success = spendEBP(budget, EspionageAction.TechTheft)
    check success == true
    check budget.ebpPoints == 0  # 5 - 5 = 0

    let failedSpend = spendEBP(budget, EspionageAction.TechTheft)
    check failedSpend == false  # Not enough EBP

  test "Budget management: spend CIP":
    var budget = initEspionageBudget()
    discard purchaseCIP(budget, 120)  # 3 CIP

    let success = spendCIP(budget, 1)
    check success == true
    check budget.cipPoints == 2

    discard spendCIP(budget, 1)
    discard spendCIP(budget, 1)
    let failed = spendCIP(budget, 1)
    check failed == false  # No CIP left
