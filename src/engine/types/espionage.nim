## Espionage System Types
##
## Type definitions for espionage operations per diplomacy.md:8.2
##
## Core concepts:
## - EBP (Espionage Budget Points): Cost 40 PP each
## - CIP (Counter-Intelligence Points): Cost 40 PP each
## - 7 espionage actions with varying costs and effects
## - Detection system with CIC levels
import std/options
import ./[core, prestige]

type
  EspionageAction* {.pure.} = enum
    TechTheft
    SabotageLow
    SabotageHigh
    Assassination
    CyberAttack
    EconomicManipulation
    PsyopsCampaign
    CounterIntelSweep
    IntelTheft
    PlantDisinformation

  #TODO: why do we have this when they are already captured in fleet commands?
  SpyMissionType* {.pure.} = enum
    SpyOnPlanet
    HackStarbase
    SpyOnSystem

  CICLevel* {.pure.} = enum
    CIC0
    CIC1
    CIC2
    CIC3
    CIC4
    CIC5

  ActiveSpyMission* = object
    fleetId*: FleetId
    missionType*: SpyMissionType
    targetSystem*: SystemId
    scoutCount*: int32
    startTurn*: int32
    ownerHouse*: HouseId

  EspionageBudget* = object
    houseId*: HouseId # Back-reference
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
    SRPReduction
    NCVReduction
    TaxReduction
    StarbaseCrippled
    IntelBlocked
    IntelCorrupted

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

  # Scout-based intelligence operations (moved from simultaneous.nim)
  # Per docs/specs/09-intel-espionage.md Section 9.1.1
  ScoutIntelOperation* = object
    ## Tracks a scout-based intelligence gathering operation
    ## Replaces EspionageIntent (removed conflict terminology)
    houseId*: HouseId
    fleetId*: FleetId
    targetSystem*: SystemId
    #TODO: Why is this a string?
    orderType*: string # "SpyColony", "SpySystem", "HackStarbase"
    espionageStrength*: int32

  ScoutIntelResult* = object
    ## Result of a scout intelligence operation
    ## Replaces simultaneous.EspionageResult (avoids naming conflict)
    houseId*: HouseId
    fleetId*: FleetId
    targetSystem*: SystemId
    detected*: bool # Whether scouts were detected
    intelligenceGathered*: bool # Whether intel was successfully gathered
