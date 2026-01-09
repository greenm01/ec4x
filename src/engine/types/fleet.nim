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
    # Fleets always have a command - Hold (00) is default after mission completion.
    # See docs/specs/06-operations.md "Command Defaults and Lifecycle"
    command*: FleetCommand
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
    ScoutColony # Intelligence gathering on colony
    ScoutSystem # Reconnaissance of system
    HackStarbase # Electronic warfare (cyber intrusion)
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
    priority*: int32 # Execution command within turn
    roe*: Option[int32] # Mission-specific retreat threshold

  MissionState* {.pure.} = enum
    ## State machine for fleets
    None # No command assigned (no mission)
    Executing # Executing the mission (arrived at mission objective)
    Traveling # En route to mission target
    ScoutLocked # Active scout mission (locked, gathering intel)
    ScoutDetected # Detected during scout mission (destroyed next phase)

  # Scout intelligence operation results
  # Per docs/specs/09-intel-espionage.md Section 9.1.1
  ScoutIntelResult* = object
    ## Result of a scout intelligence operation
    houseId*: HouseId
    fleetId*: FleetId
    targetSystem*: SystemId
    detected*: bool # Whether scouts were detected
    intelligenceGathered*: bool # Whether intel was successfully gathered

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
  FleetCommandType.ScoutColony: ThreatLevel.Benign,
  FleetCommandType.ScoutSystem: ThreatLevel.Benign,
  FleetCommandType.HackStarbase: ThreatLevel.Benign,
  FleetCommandType.JoinFleet: ThreatLevel.Benign,
  FleetCommandType.Salvage: ThreatLevel.Benign,
  FleetCommandType.Reserve: ThreatLevel.Benign,
  FleetCommandType.Mothball: ThreatLevel.Benign,
  FleetCommandType.Reactivate: ThreatLevel.Benign,
  FleetCommandType.View: ThreatLevel.Benign,
}.toTable
