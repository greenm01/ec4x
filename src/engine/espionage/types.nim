## Espionage System Types
##
## Type definitions for espionage operations per diplomacy.md:8.2
##
## Core concepts:
## - EBP (Espionage Budget Points): Cost 40 PP each
## - CIP (Counter-Intelligence Points): Cost 40 PP each
## - 7 espionage actions with varying costs and effects
## - Detection system with CIC levels

import std/[options]
import ../../common/types/core
import ../prestige
import ../config/espionage_config

export core.HouseId, core.SystemId
export prestige.PrestigeEvent
export espionage_config.globalEspionageConfig

type
  ## Espionage Actions

  EspionageAction* {.pure.} = enum
    TechTheft,          # 5 EBP: Steal 10 SRP
    SabotageLow,        # 2 EBP: 1d6 IU damage
    SabotageHigh,       # 7 EBP: 1d20 IU damage
    Assassination,      # 10 EBP: -50% SRP gain for 1 turn
    CyberAttack,        # 6 EBP: Cripple starbase
    EconomicManipulation,  # 6 EBP: Halve NCV for 1 turn
    PsyopsCampaign,     # 3 EBP: -25% tax revenue for 1 turn
    CounterIntelSweep,  # 4 EBP: Block intelligence gathering for 1 turn
    IntelligenceTheft,  # 8 EBP: Steal target's intelligence database
    PlantDisinformation # 6 EBP: Corrupt target's intel with false data

  ## Counter-Intelligence Command (CIC)

  CICLevel* {.pure.} = enum
    ## Counter-intelligence sophistication level
    CIC0,  # No counter-intelligence
    CIC1,  # Basic: > 15 on d20
    CIC2,  # Improved: > 12 on d20
    CIC3,  # Advanced: > 10 on d20
    CIC4,  # Expert: > 7 on d20
    CIC5   # Elite: > 4 on d20

  ## Espionage Budget & Investment

  EspionageBudget* = object
    ## Espionage budget tracking
    ebpPoints*: int      # Available EBP
    cipPoints*: int      # Available CIP
    ebpInvested*: int    # Total EBP invested this turn (for over-investment check)
    cipInvested*: int    # Total CIP invested this turn (for over-investment check)
    turnBudget*: int     # Total PP budget this turn (for % calculation)

  ## Espionage Operations

  EspionageAttempt* = object
    ## Attempt to perform espionage action
    attacker*: HouseId
    target*: HouseId
    action*: EspionageAction
    targetSystem*: Option[SystemId]  # For sabotage, cyber attack

  EspionageResult* = object
    ## Result of espionage attempt
    success*: bool
    detected*: bool
    action*: EspionageAction
    attacker*: HouseId
    target*: HouseId
    description*: string
    attackerPrestigeEvents*: seq[PrestigeEvent]
    targetPrestigeEvents*: seq[PrestigeEvent]
    srpStolen*: int           # For tech theft
    iuDamage*: int            # For sabotage
    effect*: Option[OngoingEffect]  # For assassination, economic manipulation, psyops
    intelTheftSuccess*: bool  # For intelligence theft - did we steal their database?

  ## Ongoing Effects

  EffectType* {.pure.} = enum
    SRPReduction,      # -50% SRP gain (assassination)
    NCVReduction,      # -50% NCV (economic manipulation)
    TaxReduction,      # -25% tax revenue (psyops)
    StarbaseCrippled,  # Starbase offline (cyber attack)
    IntelBlocked,      # Intelligence gathering blocked (counter-intel sweep)
    IntelCorrupted     # Intelligence data corrupted (disinformation)

  OngoingEffect* = object
    ## Effect that lasts for turns
    effectType*: EffectType
    targetHouse*: HouseId
    targetSystem*: Option[SystemId]  # For starbase effects
    turnsRemaining*: int
    magnitude*: float  # Percentage reduction (0.5 = 50%, 0.25 = 25%)

  ## Detection System

  DetectionAttempt* = object
    ## Counter-intelligence detection attempt
    defender*: HouseId
    cicLevel*: CICLevel
    cipPoints*: int
    action*: EspionageAction

  DetectionResult* = object
    ## Result of detection attempt
    detected*: bool
    roll*: int
    threshold*: int
    modifier*: int

  ## Reports

  EspionageReport* = object
    ## Espionage phase report
    turn*: int
    attempts*: seq[EspionageResult]
    overInvestmentPenalties*: seq[tuple[houseId: HouseId, penalty: int]]

## Constants per diplomacy.md:8.2

const
  # Costs
  EBP_COST_PP* = 40  # PP per EBP
  CIP_COST_PP* = 40  # PP per CIP

  # Over-investment
  INVESTMENT_THRESHOLD* = 5  # 5% of budget
  INVESTMENT_PENALTY* = -1   # -1 prestige per 1% over threshold

  # Detection
  CIP_DEDUCTION_PER_ROLL* = 1  # CIP consumed per detection attempt

  # Action costs (EBP)
  TECH_THEFT_COST* = 5
  SABOTAGE_LOW_COST* = 2
  SABOTAGE_HIGH_COST* = 7
  ASSASSINATION_COST* = 10
  CYBER_ATTACK_COST* = 6
  ECONOMIC_MANIPULATION_COST* = 6
  PSYOPS_CAMPAIGN_COST* = 3
  COUNTER_INTEL_SWEEP_COST* = 4
  INTELLIGENCE_THEFT_COST* = 8
  PLANT_DISINFORMATION_COST* = 6

  # Action effects
  TECH_THEFT_SRP* = 10     # SRP stolen
  SABOTAGE_LOW_DICE* = 6   # d6 IU damage
  SABOTAGE_HIGH_DICE* = 20  # d20 IU damage
  ASSASSINATION_REDUCTION* = 0.5  # 50% SRP reduction
  ECONOMIC_REDUCTION* = 0.5  # 50% NCV reduction
  PSYOPS_REDUCTION* = 0.25  # 25% tax reduction
  EFFECT_DURATION* = 1  # Turns effect lasts
  INTEL_BLOCK_DURATION* = 1  # Turns intel blocked (counter-intel sweep)
  DISINFORMATION_DURATION* = 2  # Turns disinformation lasts
  DISINFORMATION_MIN_VARIANCE* = 0.2  # 20% min corruption
  DISINFORMATION_MAX_VARIANCE* = 0.4  # 40% max corruption

  # Detection rolls (target threshold)
  FAILED_ESPIONAGE_PENALTY* = -2  # Prestige penalty when detected

## Helper Procs

proc getActionCost*(action: EspionageAction): int =
  ## Get EBP cost for action (from config)
  let config = globalEspionageConfig
  case action
  of EspionageAction.TechTheft: config.costs.tech_theft_ebp
  of EspionageAction.SabotageLow: config.costs.sabotage_low_ebp
  of EspionageAction.SabotageHigh: config.costs.sabotage_high_ebp
  of EspionageAction.Assassination: config.costs.assassination_ebp
  of EspionageAction.CyberAttack: config.costs.cyber_attack_ebp
  of EspionageAction.EconomicManipulation: config.costs.economic_manipulation_ebp
  of EspionageAction.PsyopsCampaign: config.costs.psyops_campaign_ebp
  of EspionageAction.CounterIntelSweep: config.costs.counter_intel_sweep_ebp
  of EspionageAction.IntelligenceTheft: config.costs.intelligence_theft_ebp
  of EspionageAction.PlantDisinformation: config.costs.plant_disinformation_ebp

proc getDetectionThreshold*(cicLevel: CICLevel): int =
  ## Get detection roll threshold for CIC level (from config)
  ## Per diplomacy.md:8.3 - roll must meet or exceed threshold
  let config = globalEspionageConfig
  case cicLevel
  of CICLevel.CIC0: config.detection.cic0_threshold
  of CICLevel.CIC1: config.detection.cic1_threshold
  of CICLevel.CIC2: config.detection.cic2_threshold
  of CICLevel.CIC3: config.detection.cic3_threshold
  of CICLevel.CIC4: config.detection.cic4_threshold
  of CICLevel.CIC5: config.detection.cic5_threshold

proc getCIPModifier*(cipPoints: int): int =
  ## Get detection modifier based on CIP points (from config)
  ## Per diplomacy.md:8.3
  let config = globalEspionageConfig
  if cipPoints == 0: config.detection.cip_0_modifier
  elif cipPoints <= 5: config.detection.cip_1_5_modifier
  elif cipPoints <= 10: config.detection.cip_6_10_modifier
  elif cipPoints <= 15: config.detection.cip_11_15_modifier
  elif cipPoints <= 20: config.detection.cip_16_20_modifier
  else: config.detection.cip_21_plus_modifier

proc initEspionageBudget*(): EspionageBudget =
  ## Initialize empty espionage budget
  result = EspionageBudget(
    ebpPoints: 0,
    cipPoints: 0,
    ebpInvested: 0,
    cipInvested: 0,
    turnBudget: 0
  )

proc calculateOverInvestmentPenalty*(invested: int, turnBudget: int): int =
  ## Calculate prestige penalty for over-investment
  ## Per diplomacy.md:8.2: -1 prestige per 1% over 5% threshold
  if turnBudget == 0:
    return 0

  let percentage = int((float(invested) / float(turnBudget)) * 100.0)
  if percentage <= INVESTMENT_THRESHOLD:
    return 0

  let excessPercentage = percentage - INVESTMENT_THRESHOLD
  return INVESTMENT_PENALTY * excessPercentage
