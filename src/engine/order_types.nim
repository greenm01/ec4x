## Fleet order types shared between modules
## Created to avoid circular dependencies between gamestate and orders modules

import std/options
import ../common/types/core

type
  FleetOrderType* {.pure.} = enum
    Hold              # Hold position, do nothing
    Move              # Navigate to target system
    SeekHome          # Find closest friendly system
    Patrol            # Defend and intercept in system
    GuardStarbase     # Protect orbital installation
    GuardPlanet       # Planetary defense
    BlockadePlanet    # Planetary siege
    Bombard           # Orbital bombardment
    Invade            # Ground assault
    Blitz             # Combined bombardment + invasion
    Colonize          # Establish colony
    SpyPlanet         # Intelligence gathering on planet
    SpySystem         # Reconnaissance of system
    HackStarbase      # Electronic warfare
    JoinFleet         # Merge with another fleet
    Rendezvous        # Coordinate movement with fleet
    Salvage           # Recover wreckage
    Reserve           # Place fleet on reserve status (50% maint, half AS/DS, can't move)
    Mothball          # Mothball fleet (0% maint, offline, screened in combat)
    Reactivate        # Return reserve/mothballed fleet to active duty

  FleetOrder* = object
    ## Persistent fleet order that continues until completed or overridden
    fleetId*: FleetId
    orderType*: FleetOrderType
    targetSystem*: Option[SystemId]
    targetFleet*: Option[FleetId]
    priority*: int  # Execution order within turn
