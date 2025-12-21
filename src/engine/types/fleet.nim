## fleet type definitions for ec4x
##
## This module contains the type definitions for fleets, which are collections
## of squadrons that can move together and engage in combat as a unit.
import std/[options, sequtils, tables]
import ./core

type

  FleetStatus* {.pure.} = enum
    Active, Reserve, Mothballed

  Fleet* = object
    ## A collection of squadrons that move together
    id*: FleetId                       # Unique fleet identifier
    squadrons*: seq[SquadronId]        # All squadron types (Combat, Intel, Expansion, Auxiliary)
    houseId*: HouseId                  # House that owns this fleet
    location*: SystemId                # Current system location
    status*: FleetStatus               # Operational status (active/reserve/mothballed)
    command*: Option[FleetCommand]
    autoBalanceSquadrons*: bool        # Auto-optimize squadron composition (default: true)
    # Spy mission state (for Scout-only fleets)
    missionState*: FleetMissionState   # Spy mission state
    missionType*: Option[int32]        # Type of active mission (SpyMissionType)
    missionTarget*: Option[SystemId]   # Target system for mission
    missionStartTurn*: int32           # Turn mission began (for duration tracking)

  Fleets* = object
    entities*: EntityManager[FleetId, Fleet]
    bySystem*: Table[SystemId, seq[FleetId]]

  FleetCommandType* {.pure.} = enum
    Hold              # Hold position, do nothing
    Move              # Navigate to target system
    SeekHome          # Find closest friendly system
    Patrol            # Defend and intercept in system
    GuardStarbase     # Protect orbital installation
    GuardColony       # Colony defense
    Blockade          # Siege a colony/planet
    Bombard           # Orbital bombardment
    Invade            # Ground assault
    Blitz             # Combined bombardment + invasion
    Colonize          # Establish colony
    SpyColony         # Intelligence gathering on colony
    SpySystem         # Reconnaissance of system
    HackStarbase      # Electronic warfare
    JoinFleet         # Merge with another fleet (scouts gain mesh network ELI bonus)
    Rendezvous        # Meet and join with other fleets at location
    Salvage           # Scrap fleet and reclaim production points (25%)
    Reserve           # Place fleet on reserve status (50% maint, half AS/DS, can't move)
    Mothball          # Mothball fleet (0% maint, offline, screened in combat)
    Reactivate        # Return reserve/mothballed fleet to active duty
    View              # Long-range reconnaissance 

  FleetCommand* = object
    ## Persistent fleet order that continues until completed or overridden
    orderType*: FleetCommandType
    targetSystem*: Option[SystemId]
    targetFleet*: Option[FleetId]
    priority*: int32  # Execution order within turn
    roe*: Option[int32]  # Mission-specific retreat threshold (overrides standing order)

  FleetMissionState* {.pure.} = enum
    ## State machine for fleet spy missions
    None,           # Normal fleet operation
    Traveling,      # En route to spy mission target
    OnSpyMission,   # Active spy mission (locked, gathering intel)
    Detected        # Detected during spy mission (destroyed next phase)

  StandingOrderType* {.pure.} = enum
    None, PatrolRoute, DefendSystem, GuardColony,
    AutoReinforce, AutoRepair, BlockadeTarget

  StandingOrderParams* = object
    patrolSystems*: seq[SystemId]
    patrolIndex*: int32
    defendSystem*: Option[SystemId]
    guardColony*: Option[ColonyId]
    blockadeTargetColony*: Option[ColonyId]
    reinforceTarget*: Option[FleetId]
    repairThreshold*: float32

  ActivationResult* = object
    ## Result of standing order activation attempt
    success*: bool
    action*: string               # Description of action taken
    error*: string                # Error message if failed
    updatedParams*: Option[StandingOrderParams]  # Updated params (e.g., patrol index)

