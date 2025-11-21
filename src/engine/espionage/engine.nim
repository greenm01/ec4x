## Espionage Engine
##
## Espionage operations and detection per diplomacy.md:8.2

import std/[random, options]
import types
import ../../common/types/core
import ../prestige
import ../config/[prestige_config, espionage_config]

export types

## Detection System

proc attemptDetection*(attempt: DetectionAttempt, rng: var Rand): DetectionResult =
  ## Attempt to detect espionage action
  ## Per diplomacy.md:8.3

  # CIC0 = no counter-intelligence, auto-fail detection
  if attempt.cicLevel == CICLevel.CIC0:
    return DetectionResult(
      detected: false,
      roll: 0,
      threshold: 21,
      modifier: 0
    )

  # Get threshold and modifier
  let threshold = getDetectionThreshold(attempt.cicLevel)
  let modifier = getCIPModifier(attempt.cipPoints)

  # Roll d20
  let roll = rng.rand(1..20)

  # Check if detected (roll + modifier >= threshold)
  let detected = (roll + modifier) >= threshold

  return DetectionResult(
    detected: detected,
    roll: roll,
    threshold: threshold,
    modifier: modifier
  )

## Espionage Actions

proc executeTechTheft*(attacker: HouseId, target: HouseId,
                      detected: bool): EspionageResult =
  ## Execute tech theft operation
  ## Per diplomacy.md:8.2.1: Steals SRP from target (configurable)

  let prestigeConfig = globalPrestigeConfig
  let espConfig = globalEspionageConfig

  var result = EspionageResult(
    success: not detected,
    detected: detected,
    action: EspionageAction.TechTheft,
    attacker: attacker,
    target: target,
    description: if detected: "Tech theft detected and prevented"
                 else: "Successfully stole research data",
    attackerPrestigeEvents: @[],
    targetPrestigeEvents: @[],
    srpStolen: 0,
    iuDamage: 0,
    effect: none(OngoingEffect)
  )

  if detected:
    # Failed - attacker loses prestige
    result.attackerPrestigeEvents.add(createPrestigeEvent(
      PrestigeSource.Eliminated,  # Using generic source
      espConfig.failedEspionagePrestige,
      "Failed espionage attempt (detected)"
    ))
  else:
    # Success - steal SRP and award prestige
    result.srpStolen = espConfig.techTheftSRP
    result.attackerPrestigeEvents.add(createPrestigeEvent(
      PrestigeSource.TechAdvancement,  # Closest match
      prestigeConfig.techTheft,
      "Tech theft successful"
    ))
    result.targetPrestigeEvents.add(createPrestigeEvent(
      PrestigeSource.TechAdvancement,
      -prestigeConfig.techTheft - 1,  # -3 prestige for target
      "Research stolen"
    ))

  return result

proc executeSabotageLow*(attacker: HouseId, target: HouseId, targetSystem: SystemId,
                        detected: bool, rng: var Rand): EspionageResult =
  ## Execute low impact sabotage
  ## Per diplomacy.md:8.2.1: 1d6 IU damage

  let config = globalPrestigeConfig

  var result = EspionageResult(
    success: not detected,
    detected: detected,
    action: EspionageAction.SabotageLow,
    attacker: attacker,
    target: target,
    description: if detected: "Sabotage detected and prevented"
                 else: "Industrial sabotage successful",
    attackerPrestigeEvents: @[],
    targetPrestigeEvents: @[],
    srpStolen: 0,
    iuDamage: 0,
    effect: none(OngoingEffect)
  )

  if detected:
    result.attackerPrestigeEvents.add(createPrestigeEvent(
      PrestigeSource.Eliminated,
      FAILED_ESPIONAGE_PENALTY,
      "Failed sabotage attempt"
    ))
  else:
    # Roll damage
    result.iuDamage = rng.rand(1..SABOTAGE_LOW_DICE)
    result.attackerPrestigeEvents.add(createPrestigeEvent(
      PrestigeSource.CombatVictory,  # Closest match
      config.lowImpactSabotage,
      "Sabotage successful (" & $result.iuDamage & " IU damaged)"
    ))
    result.targetPrestigeEvents.add(createPrestigeEvent(
      PrestigeSource.Eliminated,
      -1,  # -1 prestige for target
      "Industrial sabotage (" & $result.iuDamage & " IU lost)"
    ))

  return result

proc executeSabotageHigh*(attacker: HouseId, target: HouseId, targetSystem: SystemId,
                         detected: bool, rng: var Rand): EspionageResult =
  ## Execute high impact sabotage
  ## Per diplomacy.md:8.2.1: 1d20 IU damage

  let config = globalPrestigeConfig

  var result = EspionageResult(
    success: not detected,
    detected: detected,
    action: EspionageAction.SabotageHigh,
    attacker: attacker,
    target: target,
    description: if detected: "Major sabotage detected and prevented"
                 else: "Devastating industrial sabotage",
    attackerPrestigeEvents: @[],
    targetPrestigeEvents: @[],
    srpStolen: 0,
    iuDamage: 0,
    effect: none(OngoingEffect)
  )

  if detected:
    result.attackerPrestigeEvents.add(createPrestigeEvent(
      PrestigeSource.Eliminated,
      FAILED_ESPIONAGE_PENALTY,
      "Failed major sabotage"
    ))
  else:
    # Roll damage
    result.iuDamage = rng.rand(1..SABOTAGE_HIGH_DICE)
    result.attackerPrestigeEvents.add(createPrestigeEvent(
      PrestigeSource.CombatVictory,
      config.highImpactSabotage,
      "Major sabotage (" & $result.iuDamage & " IU destroyed)"
    ))
    result.targetPrestigeEvents.add(createPrestigeEvent(
      PrestigeSource.Eliminated,
      -5,  # -5 prestige for target
      "Devastating sabotage (" & $result.iuDamage & " IU lost)"
    ))

  return result

proc executeAssassination*(attacker: HouseId, target: HouseId,
                          detected: bool): EspionageResult =
  ## Execute assassination
  ## Per diplomacy.md:8.2.1: -50% SRP gain for 1 turn

  let config = globalPrestigeConfig

  var result = EspionageResult(
    success: not detected,
    detected: detected,
    action: EspionageAction.Assassination,
    attacker: attacker,
    target: target,
    description: if detected: "Assassination attempt foiled"
                 else: "Key figure eliminated",
    attackerPrestigeEvents: @[],
    targetPrestigeEvents: @[],
    srpStolen: 0,
    iuDamage: 0,
    effect: none(OngoingEffect)
  )

  if detected:
    result.attackerPrestigeEvents.add(createPrestigeEvent(
      PrestigeSource.Eliminated,
      FAILED_ESPIONAGE_PENALTY,
      "Failed assassination"
    ))
  else:
    # Create ongoing effect
    result.effect = some(OngoingEffect(
      effectType: EffectType.SRPReduction,
      targetHouse: target,
      targetSystem: none(SystemId),
      turnsRemaining: EFFECT_DURATION,
      magnitude: ASSASSINATION_REDUCTION
    ))
    result.attackerPrestigeEvents.add(createPrestigeEvent(
      PrestigeSource.CombatVictory,
      config.assassination,
      "Assassination successful"
    ))
    result.targetPrestigeEvents.add(createPrestigeEvent(
      PrestigeSource.Eliminated,
      -7,  # -7 prestige for target
      "Key figure assassinated"
    ))

  return result

proc executeCyberAttack*(attacker: HouseId, target: HouseId, targetSystem: SystemId,
                        detected: bool): EspionageResult =
  ## Execute cyber attack on starbase
  ## Per diplomacy.md:8.2.1: Cripples starbase

  let config = globalPrestigeConfig

  var result = EspionageResult(
    success: not detected,
    detected: detected,
    action: EspionageAction.CyberAttack,
    attacker: attacker,
    target: target,
    description: if detected: "Cyber attack detected and blocked"
                 else: "Starbase systems compromised",
    attackerPrestigeEvents: @[],
    targetPrestigeEvents: @[],
    srpStolen: 0,
    iuDamage: 0,
    effect: none(OngoingEffect)
  )

  if detected:
    result.attackerPrestigeEvents.add(createPrestigeEvent(
      PrestigeSource.Eliminated,
      FAILED_ESPIONAGE_PENALTY,
      "Failed cyber attack"
    ))
  else:
    # Create starbase crippled effect
    result.effect = some(OngoingEffect(
      effectType: EffectType.StarbaseCrippled,
      targetHouse: target,
      targetSystem: some(targetSystem),
      turnsRemaining: EFFECT_DURATION,
      magnitude: 1.0
    ))
    result.attackerPrestigeEvents.add(createPrestigeEvent(
      PrestigeSource.CombatVictory,
      config.cyberAttack,
      "Cyber attack successful"
    ))
    result.targetPrestigeEvents.add(createPrestigeEvent(
      PrestigeSource.Eliminated,
      -3,  # -3 prestige for target
      "Starbase crippled by cyber attack"
    ))

  return result

proc executeEconomicManipulation*(attacker: HouseId, target: HouseId,
                                  detected: bool): EspionageResult =
  ## Execute economic manipulation
  ## Per diplomacy.md:8.2.1: Halves NCV for 1 turn

  let config = globalPrestigeConfig

  var result = EspionageResult(
    success: not detected,
    detected: detected,
    action: EspionageAction.EconomicManipulation,
    attacker: attacker,
    target: target,
    description: if detected: "Economic manipulation detected"
                 else: "Markets disrupted successfully",
    attackerPrestigeEvents: @[],
    targetPrestigeEvents: @[],
    srpStolen: 0,
    iuDamage: 0,
    effect: none(OngoingEffect)
  )

  if detected:
    result.attackerPrestigeEvents.add(createPrestigeEvent(
      PrestigeSource.Eliminated,
      FAILED_ESPIONAGE_PENALTY,
      "Failed economic manipulation"
    ))
  else:
    # Create NCV reduction effect
    result.effect = some(OngoingEffect(
      effectType: EffectType.NCVReduction,
      targetHouse: target,
      targetSystem: none(SystemId),
      turnsRemaining: EFFECT_DURATION,
      magnitude: ECONOMIC_REDUCTION
    ))
    result.attackerPrestigeEvents.add(createPrestigeEvent(
      PrestigeSource.CombatVictory,
      config.economicManipulation,
      "Economic disruption successful"
    ))
    result.targetPrestigeEvents.add(createPrestigeEvent(
      PrestigeSource.Eliminated,
      -4,  # -4 prestige for target
      "Economy disrupted"
    ))

  return result

proc executePsyopsCampaign*(attacker: HouseId, target: HouseId,
                           detected: bool): EspionageResult =
  ## Execute psyops/propaganda campaign
  ## Per diplomacy.md:8.2.1: -25% tax revenue for 1 turn

  let config = globalPrestigeConfig

  var result = EspionageResult(
    success: not detected,
    detected: detected,
    action: EspionageAction.PsyopsCampaign,
    attacker: attacker,
    target: target,
    description: if detected: "Propaganda campaign exposed"
                 else: "Psyops campaign undermines morale",
    attackerPrestigeEvents: @[],
    targetPrestigeEvents: @[],
    srpStolen: 0,
    iuDamage: 0,
    effect: none(OngoingEffect)
  )

  if detected:
    result.attackerPrestigeEvents.add(createPrestigeEvent(
      PrestigeSource.Eliminated,
      FAILED_ESPIONAGE_PENALTY,
      "Failed psyops campaign"
    ))
  else:
    # Create tax reduction effect
    result.effect = some(OngoingEffect(
      effectType: EffectType.TaxReduction,
      targetHouse: target,
      targetSystem: none(SystemId),
      turnsRemaining: EFFECT_DURATION,
      magnitude: PSYOPS_REDUCTION
    ))
    result.attackerPrestigeEvents.add(createPrestigeEvent(
      PrestigeSource.CombatVictory,
      config.psyopsCampaign,
      "Psyops campaign successful"
    ))
    result.targetPrestigeEvents.add(createPrestigeEvent(
      PrestigeSource.Eliminated,
      -2,  # -2 prestige for target
      "Public morale damaged by propaganda"
    ))

  return result

## Main Espionage Execution

proc executeEspionage*(attempt: EspionageAttempt,
                      defenderCICLevel: CICLevel,
                      defenderCIPPoints: int,
                      rng: var Rand): EspionageResult =
  ## Execute espionage attempt with detection
  ## Per diplomacy.md:8.2 and 8.3

  # Attempt detection
  let detectionAttempt = DetectionAttempt(
    defender: attempt.target,
    cicLevel: defenderCICLevel,
    cipPoints: defenderCIPPoints,
    action: attempt.action
  )

  let detection = attemptDetection(detectionAttempt, rng)

  # Execute action based on detection
  case attempt.action
  of EspionageAction.TechTheft:
    return executeTechTheft(attempt.attacker, attempt.target, detection.detected)

  of EspionageAction.SabotageLow:
    let system = attempt.targetSystem.get(0.SystemId)  # Default if not provided
    return executeSabotageLow(attempt.attacker, attempt.target, system, detection.detected, rng)

  of EspionageAction.SabotageHigh:
    let system = attempt.targetSystem.get(0.SystemId)
    return executeSabotageHigh(attempt.attacker, attempt.target, system, detection.detected, rng)

  of EspionageAction.Assassination:
    return executeAssassination(attempt.attacker, attempt.target, detection.detected)

  of EspionageAction.CyberAttack:
    let system = attempt.targetSystem.get(0.SystemId)
    return executeCyberAttack(attempt.attacker, attempt.target, system, detection.detected)

  of EspionageAction.EconomicManipulation:
    return executeEconomicManipulation(attempt.attacker, attempt.target, detection.detected)

  of EspionageAction.PsyopsCampaign:
    return executePsyopsCampaign(attempt.attacker, attempt.target, detection.detected)

## Budget Management

proc purchaseEBP*(budget: var EspionageBudget, ppSpent: int): int =
  ## Purchase EBP with PP
  ## Returns number of EBP purchased
  let ebpPurchased = ppSpent div EBP_COST_PP
  budget.ebpPoints += ebpPurchased
  budget.ebpInvested += ppSpent
  return ebpPurchased

proc purchaseCIP*(budget: var EspionageBudget, ppSpent: int): int =
  ## Purchase CIP with PP
  ## Returns number of CIP purchased
  let cipPurchased = ppSpent div CIP_COST_PP
  budget.cipPoints += cipPurchased
  budget.cipInvested += ppSpent
  return cipPurchased

proc canAffordAction*(budget: EspionageBudget, action: EspionageAction): bool =
  ## Check if have enough EBP for action
  return budget.ebpPoints >= getActionCost(action)

proc spendEBP*(budget: var EspionageBudget, action: EspionageAction): bool =
  ## Spend EBP on action
  ## Returns true if successful
  let cost = getActionCost(action)
  if budget.ebpPoints >= cost:
    budget.ebpPoints -= cost
    return true
  return false

proc spendCIP*(budget: var EspionageBudget, amount: int = CIP_DEDUCTION_PER_ROLL): bool =
  ## Spend CIP on detection attempt
  ## Returns true if successful
  if budget.cipPoints >= amount:
    budget.cipPoints -= amount
    return true
  return false
