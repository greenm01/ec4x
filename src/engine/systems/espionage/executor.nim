## Generic Espionage Executor
##
## Data-oriented design: Single execution path for all espionage actions
## Replaces 10 nearly-identical functions with 1 data-driven function

import std/[random, options]
import ../../types/[core, espionage, prestige]
import ../../prestige/events as prestige_events
import ../../config/[prestige_config, espionage_config]
import action_descriptors

export espionage, action_descriptors

## Generic Execution

proc executeEspionageAction*(
  descriptor: ActionDescriptor,
  attacker: HouseId,
  target: HouseId,
  targetSystem: Option[SystemId],
  detected: bool,
  rng: var Rand
): EspionageResult =
  ## Generic executor for all espionage actions
  ## Pure calculation - builds result from action descriptor
  ##
  ## This single function replaces:
  ## - executeTechTheft
  ## - executeSabotageLow
  ## - executeSabotageHigh
  ## - executeAssassination
  ## - executeCyberAttack
  ## - executeEconomicManipulation
  ## - executePsyopsCampaign
  ## - executeCounterIntelSweep
  ## - executeIntelligenceTheft
  ## - executePlantDisinformation

  # Base result structure (all actions)
  result = EspionageResult(
    success: not detected,
    detected: detected,
    action: descriptor.action,
    attacker: attacker,
    target: if descriptor.effectTargetsSelf: attacker else: target,
    description: if detected: descriptor.detectedDesc else: descriptor.successDesc,
    attackerPrestigeEvents: @[],
    targetPrestigeEvents: @[],
    srpStolen: 0,
    iuDamage: 0,
    effect: none(OngoingEffect),
    intelTheftSuccess: false
  )

  # Detected = failed (except CounterIntelSweep which is opposite)
  if detected:
    if descriptor.failedPrestigeReason != "":  # Some actions don't penalize detection
      result.attackerPrestigeEvents.add(prestige_events.createPrestigeEvent(
        PrestigeSource.Eliminated,
        globalPrestigeConfig.espionage.failed_espionage,
        descriptor.failedPrestigeReason
      ))
  else:
    # Success - apply action-specific effects

    # Prestige for attacker (ZERO-SUM: attacker gains, target loses equal amount)
    result.attackerPrestigeEvents.add(prestige_events.createPrestigeEvent(
      PrestigeSource.CombatVictory,  # Generic success source
      int32(descriptor.attackerSuccessPrestige),
      descriptor.successPrestigeReason
    ))

    # Prestige penalty for target (ZERO-SUM: equal and opposite to attacker gain)
    result.targetPrestigeEvents.add(prestige_events.createPrestigeEvent(
      PrestigeSource.Eliminated,
      int32(-descriptor.attackerSuccessPrestige),  # Negative of attacker gain
      if descriptor.targetSuccessReason != "": descriptor.targetSuccessReason
      else: "Victim of espionage"
    ))

    # SRP theft
    if descriptor.stealsSRP:
      result.srpStolen = int32(descriptor.srpAmount)

    # IU damage
    if descriptor.damagesIU:
      result.iuDamage = int32(rng.rand(1..descriptor.damageDice))
      # Update description with damage amount
      result.description = descriptor.successPrestigeReason & " (" & $result.iuDamage & " IU " &
                          (if descriptor.damageDice == globalEspionageConfig.effects.sabotage_low_dice: "damaged" else: "destroyed") & ")"
      # Update target prestige description
      if result.targetPrestigeEvents.len > 0:
        result.targetPrestigeEvents[0].description = descriptor.targetSuccessReason & " (" & $result.iuDamage & " IU lost)"

    # Intelligence theft
    if descriptor.stealsIntel:
      result.intelTheftSuccess = true

    # Ongoing effects
    if descriptor.hasEffect:
      let effectTarget = if descriptor.effectTargetsSelf: attacker else: target
      let effectSystem = if descriptor.requiresSystem: targetSystem else: none(SystemId)

      result.effect = some(OngoingEffect(
        effectType: descriptor.effectType,
        targetHouse: effectTarget,
        targetSystem: effectSystem,
        turnsRemaining: int32(descriptor.effectTurns),
        magnitude: descriptor.effectMagnitude
      ))

## Detection Helpers (exported for use in engine.nim)

proc getDetectionThreshold*(cicLevel: CICLevel): int =
  ## Get detection threshold for CIC level from config
  let config = globalEspionageConfig.detection
  case cicLevel
  of CICLevel.CIC0: config.cic0_threshold
  of CICLevel.CIC1: config.cic1_threshold
  of CICLevel.CIC2: config.cic2_threshold
  of CICLevel.CIC3: config.cic3_threshold
  of CICLevel.CIC4: config.cic4_threshold
  of CICLevel.CIC5: config.cic5_threshold

proc getCIPModifier*(cipPoints: int): int =
  ## Convert CIP (Counter-Intelligence Points) to detection roll modifier
  ## Uses tiered modifiers from espionage config
  let config = globalEspionageConfig.detection
  if cipPoints == 0:
    config.cip_0_modifier
  elif cipPoints <= 5:
    config.cip_1_5_modifier
  elif cipPoints <= 10:
    config.cip_6_10_modifier
  elif cipPoints <= 15:
    config.cip_11_15_modifier
  elif cipPoints <= 20:
    config.cip_16_20_modifier
  else:
    config.cip_21_plus_modifier

## Main Entry Point

proc executeEspionage*(
  attempt: EspionageAttempt,
  defenderCICLevel: CICLevel,
  defenderCIPPoints: int,
  rng: var Rand
): EspionageResult =
  ## Execute espionage attempt with detection
  ## Per diplomacy.md:8.2 and 8.3
  ##
  ## This is the only public function - replaces old executeEspionage

  # Get action descriptor (pure lookup)
  let descriptor = getActionDescriptor(attempt.action)

  # Import detection from engine.nim (we'll need to expose it)
  # For now, inline the detection logic
  var detected = false
  if defenderCICLevel != CICLevel.CIC0:
    let threshold = getDetectionThreshold(defenderCICLevel)
    let modifier = getCIPModifier(defenderCIPPoints)
    let roll = rng.rand(1..20)
    detected = (roll + modifier) >= threshold

  # Execute action using generic executor
  return executeEspionageAction(
    descriptor,
    attempt.attacker,
    attempt.target,
    attempt.targetSystem,
    detected,
    rng
  )
