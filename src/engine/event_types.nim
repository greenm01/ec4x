import std/[options, tables, strformat]
import ../../common/types/core
import ../../common/types/units # For ShipClass
import ../../common/types/diplomacy # For DiplomaticState, DiplomaticActionType
import ../../common/types/tech # For TechField
import ../../engine/espionage/types as esp_types # For EspionageAction

# =============================================================================
# Core Game Event Types
# =============================================================================

type
  GameEventKind* {.pure.} = enum
    ## Categories of game events.
    ## These map to the different `GameEvent` variants.
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
    Prestige              # Prestige gained or lost

  GameEvent* = ref object of RootObj
    ## Base type for all game events.
    ## Uses a 'case' statement to hold specific event data.
    kind*: GameEventKind
    turn*: int
    houseId*: Option[HouseId] # House that triggered or is primarily affected
    systemId*: Option[SystemId] # System primarily affected
    description*: string # Human-readable summary for logs/UI

    case kind
    of General:
      message*: string # Generic message
    of OrderIssued, OrderCompleted, OrderRejected, OrderFailed, OrderAborted:
      ## Events for fleet and other orders.
      ## These events consolidate details for various order outcomes.
      fleetId*: Option[FleetId]
      orderType*: string # String representation of the order type (e.g., "MoveFleet", "BuildFleet")
      reason*: Option[string] # Why it failed/rejected/aborted
      details*: Option[string] # Extra details for completion
    of CombatResult:
      attackingHouseId*: HouseId
      defendingHouseId*: HouseId
      outcome*: string # "Victory", "Defeat", "Draw", "MutualAnnihilation"
      newOwner*: Option[HouseId] # If system ownership changed
      totalAttackStrength*: int
      totalDefenseStrength*: int
      attackerLosses*: int
      defenderLosses*: int
      # Add more combat details as needed
    of Espionage:
      sourceHouseId*: Option[HouseId] # House that initiated the espionage
      targetHouseId*: HouseId
      targetSystemId*: Option[SystemId] # For system-specific ops
      operationType*: esp_types.EspionageAction # e.g., SabotageHigh, TechTheft
      success*: bool
      detected*: bool # Was the operation detected?
      # Add more espionage details
    of Diplomacy:
      sourceHouseId*: Option[HouseId]
      targetHouseId*: HouseId
      action*: DiplomaticActionType # e.g., ProposeAlliance, DeclareWar
      proposalType*: Option[DiplomaticProposalType] # e.g., NonAggressionPact, Alliance
      success*: Option[bool]
      oldState*: DiplomaticState
      newState*: DiplomaticState
      # Add more diplomatic details
    of Research:
      houseId*: HouseId
      techField*: TechField
      oldLevel*: int
      newLevel*: int
      breakthrough*: Option[string] # "Minor", "Major", "Revolutionary"
    of Economy:
      category*: string # "Income", "Maintenance", "Production"
      amount*: int # PP, IU, etc.
      details*: Option[string]
    of Colony:
      colonyEventType*: string # "Established", "Lost", "Damage"
      newOwner*: Option[HouseId]
      oldOwner*: Option[HouseId]
      details*: Option[string]
    of Fleet:
      fleetEventType*: string # "Created", "Destroyed", "Crippled", "Repaired"
      fleetId*: Option[FleetId]
      shipClass*: Option[ShipClass] # For fleet creation/destruction/crippling
      details*: Option[string]
    of Intelligence:
      sourceHouseId*: HouseId
      targetHouseId*: Option[HouseId]
      targetSystemId*: Option[SystemId]
      intelType*: string # "ScoutReport", "SpyReport", "CombatIntel"
      details*: Option[string]
    of Prestige:
      sourceHouseId*: HouseId
      changeAmount*: int
      details*: Option[string]
