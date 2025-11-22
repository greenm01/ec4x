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
    check getActionCost(EspionageAction.TechTheft) == globalEspionageConfig.techTheftEBP
    check getActionCost(EspionageAction.SabotageLow) == globalEspionageConfig.sabotageLowEBP
    check getActionCost(EspionageAction.Assassination) == globalEspionageConfig.assassinationEBP

  test "Detection thresholds from config":
    check getDetectionThreshold(CICLevel.CIC0) == globalEspionageConfig.cic0Threshold
    check getDetectionThreshold(CICLevel.CIC3) == globalEspionageConfig.cic3Threshold
    check getDetectionThreshold(CICLevel.CIC5) == globalEspionageConfig.cic5Threshold

  test "CIP modifiers from config":
    let config = globalEspionageConfig
    check getCIPModifier(0) == config.cip0Modifier
    check getCIPModifier(3) == config.cip15Modifier
    check getCIPModifier(8) == config.cip610Modifier
    check getCIPModifier(12) == config.cip1115Modifier
    check getCIPModifier(25) == config.cip21PlusModifier

  test "Tech theft successful (not detected)":
    var rng = initRand(12345)
    let result = executeTechTheft("house1".HouseId, "house2".HouseId, detected = false)

    check result.success == true
    check result.detected == false
    check result.srpStolen == globalEspionageConfig.techTheftSRP
    check result.attackerPrestigeEvents.len > 0
    check result.attackerPrestigeEvents[0].amount == globalPrestigeConfig.espionage.tech_theft
    check result.targetPrestigeEvents.len > 0
    check result.targetPrestigeEvents[0].amount < 0

  test "Tech theft detected (failed)":
    let result = executeTechTheft("house1".HouseId, "house2".HouseId, detected = true)

    check result.success == false
    check result.detected == true
    check result.srpStolen == 0
    check result.attackerPrestigeEvents.len > 0
    check result.attackerPrestigeEvents[0].amount == globalEspionageConfig.failedEspionagePrestige

  test "Sabotage low successful":
    var rng = initRand(54321)
    let result = executeSabotageLow("house1".HouseId, "house2".HouseId, 100.SystemId, detected = false, rng)

    check result.success == true
    check result.iuDamage > 0
    check result.iuDamage <= globalEspionageConfig.sabotageLowDice
    check result.attackerPrestigeEvents.len > 0

  test "Sabotage high successful":
    var rng = initRand(11111)
    let result = executeSabotageHigh("house1".HouseId, "house2".HouseId, 100.SystemId, detected = false, rng)

    check result.success == true
    check result.iuDamage > 0
    check result.iuDamage <= globalEspionageConfig.sabotageHighDice
    check result.attackerPrestigeEvents.len > 0

  test "Assassination creates SRP reduction effect":
    let result = executeAssassination("house1".HouseId, "house2".HouseId, detected = false)

    check result.success == true
    check result.effect.isSome

    let effect = result.effect.get()
    check effect.effectType == EffectType.SRPReduction
    check effect.targetHouse == "house2".HouseId
    check effect.turnsRemaining == globalEspionageConfig.effectDurationTurns
    check effect.magnitude == (globalEspionageConfig.assassinationSRPReduction.float / 100.0)

  test "Cyber attack creates starbase crippled effect":
    let result = executeCyberAttack("house1".HouseId, "house2".HouseId, 50.SystemId, detected = false)

    check result.success == true
    check result.effect.isSome

    let effect = result.effect.get()
    check effect.effectType == EffectType.StarbaseCrippled
    check effect.targetSystem.isSome
    check effect.targetSystem.get() == 50.SystemId

  test "Economic manipulation creates NCV reduction effect":
    let result = executeEconomicManipulation("house1".HouseId, "house2".HouseId, detected = false)

    check result.success == true
    check result.effect.isSome

    let effect = result.effect.get()
    check effect.effectType == EffectType.NCVReduction
    check effect.magnitude == (globalEspionageConfig.economicNCVReduction.float / 100.0)

  test "Psyops campaign creates tax reduction effect":
    let result = executePsyopsCampaign("house1".HouseId, "house2".HouseId, detected = false)

    check result.success == true
    check result.effect.isSome

    let effect = result.effect.get()
    check effect.effectType == EffectType.TaxReduction
    check effect.magnitude == (globalEspionageConfig.psyopsTaxReduction.float / 100.0)

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
    check result.threshold == globalEspionageConfig.cic5Threshold
    check result.modifier == globalEspionageConfig.cip21PlusModifier

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
