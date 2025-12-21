## Espionage-Specific Game State Types for EC4X
##
## This module defines data structures related to espionage missions and effects,
## adhering to the Data-Oriented Design (DoD) principle.

import std/[tables, options]
import ../../common/types/core # For HouseId, SystemId, FleetId

# Re-export core types required by Espionage
export core.HouseId, core.SystemId, core.FleetId

type
  SpyMissionType* {.pure.} = enum
    ## Types of spy scout missions (operations.md:6.2.9-6.2.11)
    SpyOnPlanet     # Order 09: Gather planet intelligence
    HackStarbase    # Order 10: Infiltrate starbase network
    SpyOnSystem     # Order 11: System reconnaissance

  ActiveSpyMission* = object
    ## Active spy mission tracked in fleet-based system
    ## Replaces SpyScout entity for persistent mission tracking
    fleetId*: FleetId
    missionType*: SpyMissionType
    targetSystem*: SystemId
    scoutCount*: int        # Number of scouts on the mission
    startTurn*: int         # Turn mission began
    ownerHouse*: HouseId

  EspionageBudget* = object
    ## Espionage budget points (EBP) and counter-intelligence points (CIP)
    ebp*: int
    cip*: int
    lastTurnEbpGain*: int
    lastTurnCipGain*: int

  OngoingEffectType* {.pure.} = enum
    ## Types of ongoing espionage effects (e.g., hacked starbase)
    HackedStarbase
    SystemRecon
    PlanetIntel

  OngoingEffect* = object
    ## An active, persistent effect from an espionage mission
    effectType*: OngoingEffectType
    targetSystem*: SystemId
    sourceHouse*: HouseId       # House that initiated the effect
    targetHouse*: HouseId       # House affected by the effect (e.g., whose starbase is hacked)
    turnsRemaining*: int        # How many turns the effect will last
    intensity*: float           # E.g., severity of hack, quality of intel
