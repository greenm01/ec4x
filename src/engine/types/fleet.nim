## fleet type definitions for ec4x
##
## This module contains the type definitions for fleets, which are collections
## of squadrons that can move together and engage in combat as a unit.
import std/[options, tables]
import ./core

type
  FleetStatus* {.pure.} = enum
    Active
    Reserve
    Mothballed

  ThreatLevel* {.pure.} = enum
    ## Categorizes fleet mission threat levels for diplomatic escalation
    ## Per docs/specs/08-diplomacy.md Section 8.1.5
    Benign     # Non-threatening missions (Move, SeekHome, Guard own assets)
    Contest    # System control contestation (Patrol, Hold, Rendezvous in enemy space)
    Attack     # Direct colony attacks (Blockade, Bombard, Invade, Blitz)

  Fleet* = object ## A collection of ships that move together
    id*: FleetId # Unique fleet identifier
    ships*: seq[ShipId] # All ship types (combat, intel, auxiliary)
    houseId*: HouseId # House that owns this fleet
    location*: SystemId # Current system location
    status*: FleetStatus # Operational status (active/reserve/mothballed)
    roe*: int32 # Rules of Engagement (0-10, default 6 = engage if equal)
    # Command tracking (entity-manager pattern - data lives on entity)
    command*: Option[FleetCommand] # Active command (player OR standing-generated)
    standingCommand*: Option[StandingCommand] # Persistent behavior configuration
    # Mission state trackers
    missionState*: MissionState # mission state
    missionTarget*: Option[SystemId] # Target system for mission
    missionStartTurn*: int32 # Turn mission began (for duration tracking)

  Fleets* = object
    entities*: EntityManager[FleetId, Fleet]
    bySystem*: Table[SystemId, seq[FleetId]]
    byOwner*: Table[HouseId, seq[FleetId]]

  FleetCommandType* {.pure.} = enum
    Hold # Hold position, do nothing
    Move # Navigate to target system
    SeekHome # Find closest friendly system
    Patrol # Defend and intercept in system
    GuardStarbase # Protect orbital installation
    GuardColony # Colony defense
    Blockade # Siege a colony/planet
    Bombard # Orbital bombardment
    Invade # Ground assault
    Blitz # Combined bombardment + invasion
    Colonize # Establish colony
    SpyColony # Intelligence gathering on colony
    SpySystem # Reconnaissance of system
    HackStarbase # Electronic warfare
    JoinFleet # Merge with another fleet (scouts gain mesh network ELI bonus)
    Rendezvous # Meet and join with other fleets at location
    Salvage # Scrap fleet and reclaim production points (25%)
    Reserve # Place fleet on reserve status (50% maint, half AS/DS, can't move)
    Mothball # Mothball fleet (0% maint, offline, screened in combat)
    Reactivate # Return reserve/mothballed fleet to active duty
    View # Long-range reconnaissance 

  FleetCommand* = object
    ## Persistent fleet command that continues until completed or overridden
    fleetId*: FleetId # The fleet receiving this command
    commandType*: FleetCommandType
    targetSystem*: Option[SystemId]
    targetFleet*: Option[FleetId]
    priority*: int32 # Execution order within turn
    roe*: Option[int32] # Mission-specific retreat threshold (overrides standing command)

  MissionState* {.pure.} = enum
    ## State machine for fleets
    None # No command assigned (no mission)
    Executing # Executing the mission (arrived at mission objective)
    Traveling # En route to mission target
    ScoutLocked # Active scout mission (locked, gathering intel)
    ScoutDetected # Detected during scout mission (destroyed next phase)

  StandingCommandType* {.pure.} = enum
    None
    PatrolRoute
    DefendSystem
    GuardColony
    AutoReinforce
    AutoRepair
    BlockadeTarget

  StandingCommandParams* = object
    patrolSystems*: seq[SystemId]
    patrolIndex*: int32
    defendSystem*: Option[SystemId]
    guardColony*: Option[ColonyId]
    blockadeTargetColony*: Option[ColonyId]
    reinforceTarget*: Option[FleetId]
    repairThreshold*: float32

  StandingCommand* = object
    ## Persistent fleet behavior configuration (entity-manager pattern)
    ## Stored on Fleet.standingCommand field, NOT in global table
    commandType*: StandingCommandType
    params*: StandingCommandParams
    turnsUntilActivation*: int32
    activationDelayTurns*: int32

  ActivationResult* = object ## Result of standing command activation attempt
    success*: bool
    action*: string # Description of action taken
    error*: string # Error message if failed
    updatedParams*: Option[StandingCommandParams] # Updated params (e.g., patrol index)

## Maps fleet commands to their threat level for diplomatic escalation
## Per docs/specs/08-diplomacy.md Section 8.1.5
const CommandThreatLevels* = {
  # Attack tier - Direct colony attacks (Enemy escalation, immediate combat)
  FleetCommandType.Blockade: ThreatLevel.Attack,
  FleetCommandType.Bombard: ThreatLevel.Attack,
  FleetCommandType.Invade: ThreatLevel.Attack,
  FleetCommandType.Blitz: ThreatLevel.Attack,

  # Contest tier - System control contestation (Hostile escalation, grace period)
  FleetCommandType.Patrol: ThreatLevel.Contest,
  FleetCommandType.Hold: ThreatLevel.Contest,
  FleetCommandType.Rendezvous: ThreatLevel.Contest,

  # Benign tier - Non-threatening missions
  FleetCommandType.Move: ThreatLevel.Benign,
  FleetCommandType.SeekHome: ThreatLevel.Benign,
  FleetCommandType.GuardStarbase: ThreatLevel.Benign,
  FleetCommandType.GuardColony: ThreatLevel.Benign,
  FleetCommandType.Colonize: ThreatLevel.Benign,
  FleetCommandType.SpyColony: ThreatLevel.Benign,
  FleetCommandType.SpySystem: ThreatLevel.Benign,
  FleetCommandType.HackStarbase: ThreatLevel.Benign,
  FleetCommandType.JoinFleet: ThreatLevel.Benign,
  FleetCommandType.Salvage: ThreatLevel.Benign,
  FleetCommandType.Reserve: ThreatLevel.Benign,
  FleetCommandType.Mothball: ThreatLevel.Benign,
  FleetCommandType.Reactivate: ThreatLevel.Benign,
  FleetCommandType.View: ThreatLevel.Benign,
}.toTable
