## Common types for resolution modules

import std/[options]
import ../../common/types/core

type
  GameEvent* = object
    eventType*: GameEventType
    houseId*: HouseId
    description*: string
    systemId*: Option[SystemId]
    targetHouseId*: Option[HouseId]  # For two-party events (espionage, combat)

  GameEventType* {.pure.} = enum
    # Existing types
    ColonyEstablished, SystemCaptured, ColonyCaptured, TerraformComplete,
    Battle, BattleOccurred, Bombardment, FleetDestroyed, InvasionRepelled,
    ConstructionStarted, ShipCommissioned, BuildingCompleted, UnitRecruited,
    UnitDisbanded,
    TechAdvance, HouseEliminated, PopulationTransfer, IntelGathered,
    OrderRejected,
    # New types for AI/client visibility
    PrestigeGained, PrestigeLost,  # Prestige changes
    WarDeclared, PeaceSigned,  # Diplomatic
    ResourceWarning, ThreatDetected, AutomationCompleted,  # Alerts
    # Espionage Events (event-driven intelligence integration)
    SpyMissionSucceeded,  # Passive intel (SpyOnPlanet/System/HackStarbase)
    SabotageConducted,  # Infrastructure damage
    TechTheftExecuted,  # SRP stolen
    AssassinationAttempted,  # SRP disruption
    EconomicManipulationExecuted,  # NCV reduction
    CyberAttackConducted,  # Starbase disabled
    PsyopsCampaignLaunched,  # Tax manipulation
    IntelligenceTheftExecuted,  # Database stolen
    DisinformationPlanted,  # False intel
    CounterIntelSweepExecuted,  # Defense operation
    SpyMissionDetected,  # Caught and foiled
    # Scout Events
    ScoutDetected,  # Scout caught during mission
    ScoutDestroyed,  # Scout eliminated
    # Fleet Order Lifecycle Events
    OrderIssued,  # Order submitted/validated
    OrderCompleted,  # Order successfully executed
    OrderFailed,  # Order execution failed (validation, conditions)
    OrderAborted  # Order cancelled (target lost, conditions changed)

  CombatReport* = object
    systemId*: SystemId
    attackers*: seq[HouseId]
    defenders*: seq[HouseId]
    attackerLosses*: int
    defenderLosses*: int
    victor*: Option[HouseId]
