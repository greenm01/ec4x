## Espionage Action Descriptors
##
## Data-oriented design: Extract action-specific data from execution logic
## This eliminates 93% code duplication in engine.nim (448 lines → ~30 lines)

import types
import ../config/[prestige_config, espionage_config]

export types

## Action-Specific Data

type
  ActionDescriptor* = object
    ## Data describing an espionage action's effects
    action*: EspionageAction
    detectedDesc*: string
    successDesc*: string
    failedPrestigeReason*: string
    successPrestigeReason*: string
    attackerSuccessPrestige*: int  # From config
    targetSuccessPrestige*: int     # Usually negative
    targetSuccessReason*: string
    requiresSystem*: bool           # Whether targetSystem is required
    # Effect generation (if any)
    hasEffect*: bool
    effectType*: EffectType
    effectTurns*: int
    effectMagnitude*: float
    effectTargetsSelf*: bool  # For defensive actions like CounterIntelSweep
    # Special mechanics
    stealsSRP*: bool
    srpAmount*: int
    damagesIU*: bool
    damageDice*: int  # d6 or d20
    stealsIntel*: bool

## Action Descriptor Table

proc getActionDescriptor*(action: EspionageAction): ActionDescriptor =
  ## Get action-specific data for execution
  ## Pure function - all action mechanics defined here

  let prestigeConfig = globalPrestigeConfig
  let espConfig = globalEspionageConfig

  case action
  of EspionageAction.TechTheft:
    ActionDescriptor(
      action: action,
      detectedDesc: "Tech theft detected and prevented",
      successDesc: "Successfully stole research data",
      failedPrestigeReason: "Failed espionage attempt (detected)",
      successPrestigeReason: "Tech theft successful",
      attackerSuccessPrestige: prestigeConfig.espionage.tech_theft,
      targetSuccessPrestige: -prestigeConfig.espionage.tech_theft - 1,
      targetSuccessReason: "Research stolen",
      requiresSystem: false,
      hasEffect: false,
      stealsSRP: true,
      srpAmount: espConfig.effects.tech_theft_srp
    )

  of EspionageAction.SabotageLow:
    ActionDescriptor(
      action: action,
      detectedDesc: "Sabotage detected and prevented",
      successDesc: "Industrial sabotage successful",
      failedPrestigeReason: "Failed sabotage attempt",
      successPrestigeReason: "Sabotage successful",
      attackerSuccessPrestige: prestigeConfig.espionage.low_impact_sabotage,
      targetSuccessPrestige: -1,
      targetSuccessReason: "Industrial sabotage",
      requiresSystem: true,
      hasEffect: false,
      damagesIU: true,
      damageDice: SABOTAGE_LOW_DICE
    )

  of EspionageAction.SabotageHigh:
    ActionDescriptor(
      action: action,
      detectedDesc: "Major sabotage detected and prevented",
      successDesc: "Devastating industrial sabotage",
      failedPrestigeReason: "Failed major sabotage",
      successPrestigeReason: "Major sabotage",
      attackerSuccessPrestige: prestigeConfig.espionage.high_impact_sabotage,
      targetSuccessPrestige: -5,
      targetSuccessReason: "Devastating sabotage",
      requiresSystem: true,
      hasEffect: false,
      damagesIU: true,
      damageDice: SABOTAGE_HIGH_DICE
    )

  of EspionageAction.Assassination:
    ActionDescriptor(
      action: action,
      detectedDesc: "Assassination attempt foiled",
      successDesc: "Key figure eliminated",
      failedPrestigeReason: "Failed assassination",
      successPrestigeReason: "Assassination successful",
      attackerSuccessPrestige: prestigeConfig.espionage.assassination,
      targetSuccessPrestige: -7,
      targetSuccessReason: "Key figure assassinated",
      requiresSystem: false,
      hasEffect: true,
      effectType: EffectType.SRPReduction,
      effectTurns: EFFECT_DURATION,
      effectMagnitude: ASSASSINATION_REDUCTION
    )

  of EspionageAction.CyberAttack:
    ActionDescriptor(
      action: action,
      detectedDesc: "Cyber attack detected and blocked",
      successDesc: "Starbase systems compromised",
      failedPrestigeReason: "Failed cyber attack",
      successPrestigeReason: "Cyber attack successful",
      attackerSuccessPrestige: prestigeConfig.espionage.cyber_attack,
      targetSuccessPrestige: -3,
      targetSuccessReason: "Starbase crippled by cyber attack",
      requiresSystem: true,
      hasEffect: true,
      effectType: EffectType.StarbaseCrippled,
      effectTurns: EFFECT_DURATION,
      effectMagnitude: 1.0
    )

  of EspionageAction.EconomicManipulation:
    ActionDescriptor(
      action: action,
      detectedDesc: "Economic manipulation detected",
      successDesc: "Markets disrupted successfully",
      failedPrestigeReason: "Failed economic manipulation",
      successPrestigeReason: "Economic disruption successful",
      attackerSuccessPrestige: prestigeConfig.espionage.economic_manipulation,
      targetSuccessPrestige: -4,
      targetSuccessReason: "Economy disrupted",
      requiresSystem: false,
      hasEffect: true,
      effectType: EffectType.NCVReduction,
      effectTurns: EFFECT_DURATION,
      effectMagnitude: ECONOMIC_REDUCTION
    )

  of EspionageAction.PsyopsCampaign:
    ActionDescriptor(
      action: action,
      detectedDesc: "Propaganda campaign exposed",
      successDesc: "Psyops campaign undermines morale",
      failedPrestigeReason: "Failed psyops campaign",
      successPrestigeReason: "Psyops campaign successful",
      attackerSuccessPrestige: prestigeConfig.espionage.psyops_campaign,
      targetSuccessPrestige: -2,
      targetSuccessReason: "Public morale damaged by propaganda",
      requiresSystem: false,
      hasEffect: true,
      effectType: EffectType.TaxReduction,
      effectTurns: EFFECT_DURATION,
      effectMagnitude: PSYOPS_REDUCTION
    )

  of EspionageAction.CounterIntelSweep:
    ActionDescriptor(
      action: action,
      detectedDesc: "Counter-intel sweep detected by enemy operatives",
      successDesc: "Counter-intel sweep successful - intelligence secured",
      failedPrestigeReason: "",  # Not used for defensive action
      successPrestigeReason: "Counter-intelligence sweep successful",
      attackerSuccessPrestige: 1,
      targetSuccessPrestige: 0,  # No target prestige change
      targetSuccessReason: "",
      requiresSystem: false,
      hasEffect: true,
      effectType: EffectType.IntelBlocked,
      effectTurns: espConfig.effects.intel_block_duration,
      effectMagnitude: 1.0,
      effectTargetsSelf: true  # Defensive action
    )

  of EspionageAction.IntelligenceTheft:
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
      stealsIntel: true
    )

  of EspionageAction.PlantDisinformation:
    let avgVariance = (espConfig.effects.disinformation_min_variance +
                       espConfig.effects.disinformation_max_variance) / 2.0
    ActionDescriptor(
      action: action,
      detectedDesc: "Disinformation campaign detected and purged",
      successDesc: "Disinformation planted in target intelligence",
      failedPrestigeReason: "Failed disinformation campaign",
      successPrestigeReason: "Disinformation campaign successful",
      attackerSuccessPrestige: 2,
      targetSuccessPrestige: 0,  # No prestige change for target
      targetSuccessReason: "",
      requiresSystem: false,
      hasEffect: true,
      effectType: EffectType.IntelCorrupted,
      effectTurns: espConfig.effects.disinformation_duration,
      effectMagnitude: avgVariance
    )
