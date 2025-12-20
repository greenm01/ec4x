## Fleet Type Definitions for EC4X
##
## This module contains the type definitions for fleets, which are collections
## of squadrons that can move together and engage in combat as a unit.

import std/[options, sequtils]
import ../../../common/types/[core, combat]
import ./squadron_types
import ../../../common/types/core

type

  FleetId* = distinct int32      ## Unique identifier for a fleet

  FleetStatus* {.pure.} = enum
    ## Fleet operational status per economy.md:3.9
    Active,      # Normal active duty (100% maintenance)
    Reserve,     # Reserve status (50% maintenance, half AS/DS, can't move)
    Mothballed   # Mothballed (0% maintenance, offline, screened in combat)

  Fleet* = object
    ## A collection of squadrons that move together
    id*: FleetId                       # Unique fleet identifier
    squadrons*: seq[Squadron]          # All squadron types (Combat, Intel, Expansion, Auxiliary)
    owner*: HouseId                    # House that owns this fleet
    location*: SystemId                # Current system location
    status*: FleetStatus               # Operational status (active/reserve/mothballed)
    autoBalanceSquadrons*: bool        # Auto-optimize squadron composition (default: true)

    # Spy mission state (for Scout-only fleets)
    missionState*: FleetMissionState      # Spy mission state
    missionType*: Option[int]             # Type of active mission (SpyMissionType)
    missionTarget*: Option[SystemId]      # Target system for mission
    missionStartTurn*: int                # Turn mission began (for duration tracking)

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
    fleetId*: FleetId
    orderType*: FleetCommandType
    targetSystem*: Option[SystemId]
    targetFleet*: Option[FleetId]
    priority*: int  # Execution order within turn
    roe*: Option[int]  # Mission-specific retreat threshold (overrides standing order)

  FleetMissionState* {.pure.} = enum
    ## State machine for fleet spy missions
    None,           # Normal fleet operation
    Traveling,      # En route to spy mission target
    OnSpyMission,   # Active spy mission (locked, gathering intel)
    Detected        # Detected during spy mission (destroyed next phase)
