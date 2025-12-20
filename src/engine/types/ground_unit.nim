## Ground Unit Type Definitions for EC4X
##
## This module contains the type definitions for ground units, planetary defenses,
## and other related combat types for ground and orbital combat.

import std/[options]
import ../core

type

  GroundUnitType* {.pure.} = enum
    Army, Marine, GroundBattery, Spacelift

  GroundUnit* = object
    ## Individual ground combat unit
    id*: GroundUnitId
    unitType*: GroundUnitType
    owner*: HouseId
    attackStrength*: int32
    defenseStrength*: int32
    state*: CombatState  # Undamaged, Crippled, Destroyed

  GroundUnits* = object
    data: seq[GroundUnit]
    index: Table[GroundUnitId, int]
    nextId: uint32

  PlanetaryDefense* = object
    shields*: Option[ShieldLevel]
    groundBatteryIds*: seq[GroundUnitId]  # Store IDs, not objects
    groundForceIds*: seq[GroundUnitId]
    spaceport*: bool  

  ShieldLevel* = object
    ## Planetary shield information (per reference.md Section 9.3)
    level*: int32  # 1-6 (SLD1-SLD6)
    blockChance*: float32  # Probability shield blocks damage
    blockPercentage*: float32  # % of hits blocked if successful

  BombardmentResult* = object
    ## Result of one bombardment round
    attackerHits*: int32
    defenderHits*: int32
    shieldBlocked*: int32  # Hits blocked by shields
    batteriesDestroyed*: int32
    batteriesCrippled*: int32
    squadronsDestroyed*: int32
    squadronsCrippled*: int32
    infrastructureDamage*: int32  # IU lost
    populationDamage*: int32  # PU lost
    roundsCompleted*: int32  # 1-3 max per turn

  InvasionResult* = object
    ## Result of planetary invasion or blitz
    success*: bool
    attacker*: HouseId
    defender*: HouseId
    attackerCasualties*: seq[GroundUnitId]
    defenderCasualties*: seq[GroundUnitId]
    infrastructureDestroyed*: int32  # IU lost (50% on invasion success)
    assetsSeized*: bool  # True for blitz, false for invasion
    batteriesDestroyed*: int32  # Ground batteries destroyed (blitz Phase 1 bombardment)
