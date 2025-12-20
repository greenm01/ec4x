## Espionage System Types
##
## Type definitions for espionage operations per diplomacy.md:8.2
##
## Core concepts:
## - EBP (Espionage Budget Points): Cost 40 PP each
## - CIP (Counter-Intelligence Points): Cost 40 PP each
## - 7 espionage actions with varying costs and effects
## - Detection system with CIC levels
import std/[tables, options]
import ./core

type
  EspionageAction* {.pure.} = enum
    TechTheft, SabotageLow, SabotageHigh, Assassination,
    CyberAttack, EconomicManipulation, PsyopsCampaign,
    CounterIntelSweep, IntelligenceTheft, PlantDisinformation

  CICLevel* {.pure.} = enum
    CIC0, CIC1, CIC2, CIC3, CIC4, CIC5

  EspionageBudget* = object
    houseId*: HouseId  # Back-reference
    ebpPoints*: int32
    cipPoints*: int32
    ebpInvested*: int32
    cipInvested*: int32
    turnBudget*: int32

  EspionageAttempt* = object
    attacker*: HouseId
    target*: HouseId
    action*: EspionageAction
    targetSystem*: Option[SystemId]

  EffectType* {.pure.} = enum
    SRPReduction, NCVReduction, TaxReduction,
    StarbaseCrippled, IntelBlocked, IntelCorrupted

  OngoingEffect* = object
    effectType*: EffectType
    targetHouse*: HouseId
    targetSystem*: Option[SystemId]
    turnsRemaining*: int32
    magnitude*: float32

  EspionageResult* = object
    success*: bool
    detected*: bool
    action*: EspionageAction
    attacker*: HouseId
    target*: HouseId
    description*: string
    attackerPrestigeEvents*: seq[PrestigeEvent]
    targetPrestigeEvents*: seq[PrestigeEvent]
    srpStolen*: int32
    iuDamage*: int32
    effect*: Option[OngoingEffect]
    intelTheftSuccess*: bool

  DetectionAttempt* = object
    defender*: HouseId
    cicLevel*: CICLevel
    cipPoints*: int32
    action*: EspionageAction

  DetectionResult* = object
    detected*: bool
    roll*: int32
    threshold*: int32
    modifier*: int32

  EspionageReport* = object
    turn*: int32
    attempts*: seq[EspionageResult]
    overInvestmentPenalties*: seq[tuple[houseId: HouseId, penalty: int32]]
