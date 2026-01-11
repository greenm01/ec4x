## Espionage Action Descriptors
##
## Data-driven design for EBP-based espionage actions.
## Eliminates code duplication by extracting action-specific data from execution logic.
##
## Per docs/specs/09-intel-espionage.md Section 9.2:
## - 10 espionage actions with varying costs and effects
## - EBP cost ranges from 2 (Low Sabotage) to 10 (Assassination)
## - Detection difficulty varies by action type
##
## **Design Pattern:**
## - ActionDescriptor type defines action effects as pure data
## - Generic executor in executor.nim uses descriptors (eliminates 93% duplication)
## - Original: 448 lines of duplicate code → After: ~30 lines of data

import ../../types/espionage
import ../../globals

export espionage

## Action-Specific Data

type ActionDescriptor* = object ## Data describing an espionage action's effects
  action*: EspionageAction
  detectedDesc*: string
  successDesc*: string
  failedPrestigeReason*: string
  successPrestigeReason*: string
  attackerSuccessPrestige*: int # From config
  targetSuccessPrestige*: int # Usually negative
  targetSuccessReason*: string
  requiresSystem*: bool # Whether targetSystem is required
  # Effect generation (if any)
  hasEffect*: bool
  effectType*: EffectType
  effectTurns*: int
  effectMagnitude*: float
  effectTargetsSelf*: bool # For defensive actions like CounterIntelSweep
  # Special mechanics
  stealsSRP*: bool
  srpAmount*: int
  damagesIU*: bool
  damageDice*: int # d6 or d20
  stealsIntel*: bool

## Action Descriptor Table

proc actionDescriptor*(action: EspionageAction): ActionDescriptor =
  ## Get action-specific data for execution
  ## Pure function - all action mechanics defined here

  case action
  of EspionageAction.TechTheft:
    ActionDescriptor(
      action: action,
      detectedDesc: "Tech theft detected and prevented",
      successDesc: "Successfully stole research data",
      failedPrestigeReason: "Failed espionage attempt (detected)",
      successPrestigeReason: "Tech theft successful",
      attackerSuccessPrestige: gameConfig.prestige.espionage.tech_theft,
      targetSuccessPrestige: -gameConfig.prestige.espionage.tech_theft - 1,
      targetSuccessReason: "Research stolen",
      requiresSystem: false,
      hasEffect: false,
      stealsSRP: true,
      srpAmount: gameConfig.espionage.effects.tech_theft_srp,
    )
  of EspionageAction.SabotageLow:
    ActionDescriptor(
      action: action,
      detectedDesc: "Sabotage detected and prevented",
      successDesc: "Industrial sabotage successful",
      failedPrestigeReason: "Failed sabotage attempt",
      successPrestigeReason: "Sabotage successful",
      attackerSuccessPrestige: gameConfig.prestige.espionage.low_impact_sabotage,
      targetSuccessPrestige: -1,
      targetSuccessReason: "Industrial sabotage",
      requiresSystem: true,
      hasEffect: false,
      damagesIU: true,
      damageDice: gameConfig.espionage.effects.sabotage_low_dice,
    )
  of EspionageAction.SabotageHigh:
    ActionDescriptor(
      action: action,
      detectedDesc: "Major sabotage detected and prevented",
      successDesc: "Devastating industrial sabotage",
      failedPrestigeReason: "Failed major sabotage",
      successPrestigeReason: "Major sabotage",
      attackerSuccessPrestige: gameConfig.prestige.espionage.high_impact_sabotage,
      targetSuccessPrestige: -5,
      targetSuccessReason: "Devastating sabotage",
      requiresSystem: true,
      hasEffect: false,
      damagesIU: true,
      damageDice: gameConfig.espionage.effects.sabotage_high_dice,
    )
  of EspionageAction.Assassination:
    ActionDescriptor(
      action: action,
      detectedDesc: "Assassination attempt foiled",
      successDesc: "Key figure eliminated",
      failedPrestigeReason: "Failed assassination",
      successPrestigeReason: "Assassination successful",
      attackerSuccessPrestige: gameConfig.prestige.espionage.assassination,
      targetSuccessPrestige: -7,
      targetSuccessReason: "Key figure assassinated",
      requiresSystem: false,
      hasEffect: true,
      effectType: EffectType.SRPReduction,
      effectTurns: gameConfig.espionage.effects.effect_duration_turns,
      effectMagnitude: float(gameConfig.espionage.effects.assassination_srp_reduction),
    )
  of EspionageAction.CyberAttack:
    ActionDescriptor(
      action: action,
      detectedDesc: "Cyber attack detected and blocked",
      successDesc: "Starbase systems compromised",
      failedPrestigeReason: "Failed cyber attack",
      successPrestigeReason: "Cyber attack successful",
      attackerSuccessPrestige: gameConfig.prestige.espionage.cyber_attack,
      targetSuccessPrestige: -3,
      targetSuccessReason: "Starbase crippled by cyber attack",
      requiresSystem: true,
      hasEffect: true,
      effectType: EffectType.StarbaseCrippled,
      effectTurns: gameConfig.espionage.effects.effect_duration_turns,
      effectMagnitude: 1.0,
    )
  of EspionageAction.EconomicManipulation:
    ActionDescriptor(
      action: action,
      detectedDesc: "Economic manipulation detected",
      successDesc: "Markets disrupted successfully",
      failedPrestigeReason: "Failed economic manipulation",
      successPrestigeReason: "Economic disruption successful",
      attackerSuccessPrestige: gameConfig.prestige.espionage.economic_manipulation,
      targetSuccessPrestige: -4,
      targetSuccessReason: "Economy disrupted",
      requiresSystem: false,
      hasEffect: true,
      effectType: EffectType.NCVReduction,
      effectTurns: gameConfig.espionage.effects.effect_duration_turns,
      effectMagnitude: float(gameConfig.espionage.effects.economic_ncv_reduction),
    )
  of EspionageAction.PsyopsCampaign:
    ActionDescriptor(
      action: action,
      detectedDesc: "Propaganda campaign exposed",
      successDesc: "Psyops campaign undermines morale",
      failedPrestigeReason: "Failed psyops campaign",
      successPrestigeReason: "Psyops campaign successful",
      attackerSuccessPrestige: gameConfig.prestige.espionage.psyops_campaign,
      targetSuccessPrestige: -2,
      targetSuccessReason: "Public morale damaged by propaganda",
      requiresSystem: false,
      hasEffect: true,
      effectType: EffectType.TaxReduction,
      effectTurns: gameConfig.espionage.effects.effect_duration_turns,
      effectMagnitude: float(gameConfig.espionage.effects.psyops_tax_reduction),
    )
  of EspionageAction.CounterIntelSweep:
    ActionDescriptor(
      action: action,
      detectedDesc: "Counter-intel sweep detected by enemy operatives",
      successDesc: "Counter-intel sweep successful - intelligence secured",
      failedPrestigeReason: "", # Not used for defensive action
      successPrestigeReason: "Counter-intelligence sweep successful",
      attackerSuccessPrestige: 1,
      targetSuccessPrestige: 0, # No target prestige change
      targetSuccessReason: "",
      requiresSystem: false,
      hasEffect: true,
      effectType: EffectType.IntelBlocked,
      effectTurns: gameConfig.espionage.effects.intel_block_duration,
      effectMagnitude: 1.0,
      effectTargetsSelf: true, # Defensive action
    )
  of EspionageAction.IntelTheft:
    ActionDescriptor(
      action: action,
      detectedDesc: "Intelligence theft detected and prevented",
      successDesc: "Intelligence database stolen successfully",
      failedPrestigeReason: "Failed intelligence theft",
      successPrestigeReason: "Intelligence theft successful",
      attackerSuccessPrestige: 3,
      targetSuccessPrestige: -3,
      targetSuccessReason: "Intelligence database compromised",
      requiresSystem: false,
      hasEffect: false,
      stealsIntel: true,
    )
  of EspionageAction.PlantDisinformation:
    let avgVariance =
      (
        gameConfig.espionage.effects.disinformation_min_variance +
        gameConfig.espionage.effects.disinformation_max_variance
      ) / 2.0
    ActionDescriptor(
      action: action,
      detectedDesc: "Disinformation campaign detected and purged",
      successDesc: "Disinformation planted in target intelligence",
      failedPrestigeReason: "Failed disinformation campaign",
      successPrestigeReason: "Disinformation campaign successful",
      attackerSuccessPrestige: 2,
      targetSuccessPrestige: 0, # No prestige change for target
      targetSuccessReason: "",
      requiresSystem: false,
      hasEffect: true,
      effectType: EffectType.IntelCorrupted,
      effectTurns: gameConfig.espionage.effects.disinformation_duration,
      effectMagnitude: avgVariance,
    )
