## Generic Espionage Executor
##
## Data-oriented design: Single execution path for all espionage actions
## Replaces 10 nearly-identical functions with 1 data-driven function

import std/[random, options]
import types, action_descriptors
import ../../common/types/core
import ../prestige

export types, action_descriptors

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
      result.attackerPrestigeEvents.add(createPrestigeEvent(
        PrestigeSource.Eliminated,
        FAILED_ESPIONAGE_PENALTY,
        descriptor.failedPrestigeReason
      ))
  else:
    # Success - apply action-specific effects

    # Prestige for attacker
    result.attackerPrestigeEvents.add(createPrestigeEvent(
      PrestigeSource.CombatVictory,  # Generic success source
      descriptor.attackerSuccessPrestige,
      descriptor.successPrestigeReason
    ))

    # Prestige for target (if applicable)
    if descriptor.targetSuccessPrestige != 0:
      result.targetPrestigeEvents.add(createPrestigeEvent(
        PrestigeSource.Eliminated,
        descriptor.targetSuccessPrestige,
        descriptor.targetSuccessReason
      ))

    # SRP theft
    if descriptor.stealsSRP:
      result.srpStolen = descriptor.srpAmount

    # IU damage
    if descriptor.damagesIU:
      result.iuDamage = rng.rand(1..descriptor.damageDice)
      # Update description with damage amount
      result.description = descriptor.successPrestigeReason & " (" & $result.iuDamage & " IU " &
                          (if descriptor.damageDice == SABOTAGE_LOW_DICE: "damaged" else: "destroyed") & ")"
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
        turnsRemaining: descriptor.effectTurns,
        magnitude: descriptor.effectMagnitude
      ))

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
