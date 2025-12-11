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
    # Specific event types
    ColonyEstablished,    # Colony founded
    SystemCaptured,       # System ownership changed via combat
    ColonyCaptured,       # Colony captured via invasion
    TerraformComplete,    # Terraforming project completed
    Battle,               # Generic battle event
    BattleOccurred,       # Battle observed by third party
    Bombardment,          # Planetary bombardment
    FleetDestroyed,       # Fleet eliminated in combat
    InvasionRepelled,     # Successful defense against invasion
    ConstructionStarted,  # Construction project initiated
    ShipCommissioned,     # New ship entered service
    BuildingCompleted,    # Building construction finished
    UnitRecruited,        # Ground unit recruited
    UnitDisbanded,        # Unit disbanded
    TechAdvance,          # Technology level increased
    HouseEliminated,      # House eliminated from game
    PopulationTransfer,   # Population moved between systems
    IntelGathered,        # Intelligence report generated
    PrestigeGained,       # Prestige increased
    PrestigeLost,         # Prestige decreased
    WarDeclared,          # War declaration
    PeaceSigned,          # Peace treaty signed
    ResourceWarning,      # Resource shortage warning
    ThreatDetected,       # Threat identified
    AutomationCompleted,  # Automated task completed
    SpyMissionSucceeded,  # Espionage operation succeeded
    SabotageConducted,    # Sabotage operation executed
    TechTheftExecuted,    # Technology stolen
    AssassinationAttempted, # Assassination attempt
    EconomicManipulationExecuted, # Economic warfare executed
    CyberAttackConducted, # Cyber attack executed
    PsyopsCampaignLaunched, # Psychological operations launched
    IntelligenceTheftExecuted, # Intelligence stolen
    DisinformationPlanted, # Disinformation planted
    CounterIntelSweepExecuted, # Counter-intelligence sweep
    SpyMissionDetected,   # Enemy espionage detected
    ScoutDetected,        # Scout detected in system
    ScoutDestroyed        # Scout eliminated
    
  GameEvent* = ref object of RootObj
    ## Base type for all game events.
    ## Uses a 'case' statement on `eventType` to hold specific event data.
    turn*: int # Added turn field
    houseId*: Option[HouseId] # House that triggered or is primarily affected
    systemId*: Option[SystemId] # System primarily affected
    description*: string # Human-readable summary for logs/UI
    # Common optional fields used by multiple event types
    sourceHouseId*: Option[HouseId] # Source house for multi-house events
    targetHouseId*: Option[HouseId] # Target house for multi-house events
    targetSystemId*: Option[SystemId] # Target system for operations
    success*: Option[bool] # Whether operation/action succeeded
    detected*: Option[bool] # Whether operation was detected
    details*: Option[string] # Additional details for various events
    fleetId*: Option[FleetId] # Fleet involved in event
    newOwner*: Option[HouseId] # New owner after ownership change
    oldOwner*: Option[HouseId] # Previous owner before ownership change

    case eventType*: GameEventType
    of General, Battle, BattleOccurred, Bombardment, ResourceWarning,
       ThreatDetected, AutomationCompleted:
      message*: string # Generic message or simple description

    of OrderIssued, OrderCompleted, OrderRejected, OrderFailed, OrderAborted:
      ## Events for fleet and other orders (fleetId/details in common fields)
      orderType*: Option[string] # String representation of the order type (e.g., "MoveFleet", "BuildFleet")
      reason*: Option[string] # Why it failed/rejected/aborted

    of CombatResult, SystemCaptured, ColonyCaptured, InvasionRepelled:
      ## Events for combat outcomes (newOwner/oldOwner in common fields)
      attackingHouseId*: Option[HouseId]
      defendingHouseId*: Option[HouseId]
      outcome*: Option[string] # "Victory", "Defeat", "Draw", "MutualAnnihilation" for CombatResult
      totalAttackStrength*: Option[int]
      totalDefenseStrength*: Option[int]
      attackerLosses*: Option[int]
      defenderLosses*: Option[int]

    of Espionage, SpyMissionSucceeded, SabotageConducted, TechTheftExecuted, AssassinationAttempted,
       EconomicManipulationExecuted, CyberAttackConducted, PsyopsCampaignLaunched,
       IntelligenceTheftExecuted, DisinformationPlanted, CounterIntelSweepExecuted, SpyMissionDetected:
      ## Events for espionage operations (success/detected in common fields)
      operationType*: Option[esp_types.EspionageAction] # e.g., SabotageHigh, TechTheft

    of Diplomacy, WarDeclared, PeaceSigned:
      ## Events for diplomatic actions (success in common fields)
      action*: Option[string] # e.g., "ProposeAlliance", "DeclareWar"
      proposalType*: Option[string] # e.g., "NonAggressionPact", "Alliance"
      oldState*: Option[DiplomaticState]
      newState*: Option[DiplomaticState]

    of Research, TechAdvance:
      ## Research events (houseId in common fields)
      techField*: TechField
      oldLevel*: Option[int]
      newLevel*: Option[int]
      breakthrough*: Option[string] # "Minor", "Major", "Revolutionary"

    of Economy, ConstructionStarted, PopulationTransfer:
      ## Economic events (details in common fields)
      category*: Option[string] # "Income", "Maintenance", "Production" for generic Economy
      amount*: Option[int] # PP, IU, etc.

    of Colony, ColonyEstablished, BuildingCompleted, UnitRecruited, UnitDisbanded, TerraformComplete:
      ## Colony events (newOwner/oldOwner/details in common fields)
      colonyEventType*: Option[string] # "Established", "Lost", "Damage", "BuildingCompleted", "UnitRecruited", "UnitDisbanded", "TerraformComplete"

    of Fleet, FleetDestroyed, ShipCommissioned, ScoutDestroyed:
      ## Fleet events (fleetId/details in common fields)
      fleetEventType*: Option[string] # "Created", "Destroyed", "Crippled", "Repaired" for generic Fleet
      shipClass*: Option[ShipClass] # For fleet creation/destruction/crippling/commissioning/scout destruction

    of Intelligence, IntelGathered, ScoutDetected:
      ## Intelligence events (details in common fields)
      intelType*: Option[string] # "ScoutReport", "SpyReport", "CombatIntel" for IntelGathered

    of Prestige, PrestigeGained, PrestigeLost:
      ## Prestige events (details in common fields)
      changeAmount*: Option[int]

    of HouseEliminated:
      eliminatedBy*: Option[HouseId] # House that eliminated them

  CombatReport* = object
    systemId*: SystemId
    attackers*: seq[HouseId]
    defenders*: seq[HouseId]
    attackerLosses*: int
    defenderLosses*: int
    victor*: Option[HouseId]
