## Common types for resolution modules

import std/[options, tables, strformat] # Added tables, strformat
import ../../common/types/core
import ../../common/types/units # For ShipClass
import ../../common/types/diplomacy # For DiplomaticState, DiplomaticActionType
import ../../common/types/tech # For TechField
import ../../engine/espionage/types as esp_types # For EspionageAction (for operationType field)

type
  GameEventType* {.pure.} = enum
    ## Categories of game events.
    ## This enum now consolidates all specific event kinds.
    General,              # Generic informational event
    OrderIssued,          # An order was successfully issued
    OrderCompleted,       # An order was completed
    OrderRejected,        # An order was rejected due to validation failure
    OrderFailed,          # An order failed during execution
    OrderAborted,         # An order was aborted due to changed conditions
    CombatResult,         # Result of a space combat or planetary assault
    Espionage,            # Outcome of an espionage operation
    Diplomacy,            # Outcome of a diplomatic action
    Research,             # Research advancement or breakthrough
    Economy,              # Economic changes (income, production, shortfall)
    Colony,               # Colony established, lost, or major change
    Fleet,                # Fleet created, destroyed, or major status change
    Intelligence,         # Intel gathered or updated
    Prestige,             # Prestige gained or lost
    # New event types were already merged here based on previous work.
    # We ensure they are all present for the case statement.
    ColonyEstablished, SystemCaptured, ColonyCaptured, TerraformComplete,
    Battle, BattleOccurred, Bombardment, FleetDestroyed, InvasionRepelled,
    ConstructionStarted, ShipCommissioned, BuildingCompleted, UnitRecruited,
    UnitDisbanded,
    TechAdvance, HouseEliminated, PopulationTransfer, IntelGathered,
    PrestigeGained, PrestigeLost,
    WarDeclared, PeaceSigned,
    ResourceWarning, ThreatDetected, AutomationCompleted,
    SpyMissionSucceeded, SabotageConducted, TechTheftExecuted, AssassinationAttempted,
    EconomicManipulationExecuted, CyberAttackConducted, PsyopsCampaignLaunched,
    IntelligenceTheftExecuted, DisinformationPlanted, CounterIntelSweepExecuted,
    SpyMissionDetected, ScoutDetected, ScoutDestroyed
    
  GameEvent* = ref object of RootObj
    ## Base type for all game events.
    ## Uses a 'case' statement on `eventType` to hold specific event data.
    eventType*: GameEventType
    turn*: int # Added turn field
    houseId*: Option[HouseId] # House that triggered or is primarily affected
    systemId*: Option[SystemId] # System primarily affected
    description*: string # Human-readable summary for logs/UI

    case eventType
    of General, Battle, BattleOccurred, Bombardment, ResourceWarning, ThreatDetected, AutomationCompleted:
      message*: string # Generic message or simple description

    of OrderIssued, OrderCompleted, OrderRejected, OrderFailed, OrderAborted:
      ## Events for fleet and other orders.
      fleetId*: Option[FleetId]
      orderType*: Option[string] # String representation of the order type (e.g., "MoveFleet", "BuildFleet")
      reason*: Option[string] # Why it failed/rejected/aborted
      details*: Option[string] # Extra details for completion (e.g. for OrderCompleted)

    of CombatResult, SystemCaptured, ColonyCaptured, InvasionRepelled:
      ## Events for combat outcomes
      attackingHouseId*: Option[HouseId]
      defendingHouseId*: Option[HouseId]
      outcome*: Option[string] # "Victory", "Defeat", "Draw", "MutualAnnihilation" for CombatResult
      newOwner*: Option[HouseId] # If system ownership changed (for SystemCaptured/ColonyCaptured)
      totalAttackStrength*: Option[int]
      totalDefenseStrength*: Option[int]
      attackerLosses*: Option[int]
      defenderLosses*: Option[int]
      # For SystemCaptured/ColonyCaptured/InvasionRepelled, oldOwner can be derived or added if needed

    of Espionage, SpyMissionSucceeded, SabotageConducted, TechTheftExecuted, AssassinationAttempted,
       EconomicManipulationExecuted, CyberAttackConducted, PsyopsCampaignLaunched,
       IntelligenceTheftExecuted, DisinformationPlanted, CounterIntelSweepExecuted:
      ## Events for espionage operations (sourceHouseId is now event.houseId)
      targetHouseId*: HouseId
      targetSystemId*: Option[SystemId] # For system-specific ops (e.g., SabotageHigh, CyberAttack)
      operationType*: esp_types.EspionageAction # e.g., SabotageHigh, TechTheft
      success*: Option[bool] # Whether the operation succeeded
      detected*: Option[bool] # Whether the operation was detected
      # Specific effects details could go here, e.g., damageAmount: Option[int]

    of Diplomacy, WarDeclared, PeaceSigned:
      ## Events for diplomatic actions
      sourceHouseId*: Option[HouseId] # House that initiated the diplomatic action
      targetHouseId*: HouseId
      action*: DiplomaticActionType # e.g., ProposeAlliance, DeclareWar
      proposalType*: Option[DiplomaticProposalType] # e.g., NonAggressionPact, Alliance
      success*: Option[bool]
      oldState*: Option[DiplomaticState]
      newState*: Option[DiplomaticState]

    of Research, TechAdvance:
      houseId*: HouseId # Redundant with event.houseId but kept for clarity
      techField*: TechField
      oldLevel*: Option[int]
      newLevel*: Option[int]
      breakthrough*: Option[string] # "Minor", "Major", "Revolutionary"

    of Economy, ConstructionStarted, PopulationTransfer, TerraformComplete:
      category*: Option[string] # "Income", "Maintenance", "Production" for generic Economy
      amount*: Option[int] # PP, IU, etc.
      details*: Option[string] # Specifics of the economic event

    of Colony, ColonyEstablished:
      colonyEventType*: Option[string] # "Established", "Lost", "Damage" for generic Colony
      newOwner*: Option[HouseId]
      oldOwner*: Option[HouseId]
      details*: Option[string] # Additional details for colony events

    of Fleet, FleetDestroyed:
      fleetEventType*: Option[string] # "Created", "Destroyed", "Crippled", "Repaired" for generic Fleet
      fleetId*: Option[FleetId]
      shipClass*: Option[ShipClass] # For fleet creation/destruction/crippling
      details*: Option[string]

    of Intelligence, IntelGathered, SpyMissionDetected, ScoutDetected, ScoutDestroyed:
      sourceHouseId*: Option[HouseId] # House that gathered/detected
      targetHouseId*: Option[HouseId] # House that was targeted/detected
      targetSystemId*: Option[SystemId] # System where intel was gathered/detection occurred
      intelType*: Option[string] # "ScoutReport", "SpyReport", "CombatIntel" for IntelGathered
      details*: Option[string]

    of Prestige, PrestigeGained, PrestigeLost:
      sourceHouseId*: Option[HouseId] # House that gained/lost prestige
      changeAmount*: Option[int]
      details*: Option[string]

    of HouseEliminated:
      eliminatedBy*: Option[HouseId] # House that eliminated them

  CombatReport* = object
    systemId*: SystemId
    attackers*: seq[HouseId]
    defenders*: seq[HouseId]
    attackerLosses*: int
    defenderLosses*: int
    victor*: Option[HouseId]
