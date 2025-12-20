## Ground Unit Type Definitions for EC4X
##
## This module contains the type definitions for ground units, planetary defenses,
## and other related combat types for ground and orbital combat.

import std/[options]
import ../../../common/types/[core, units, combat as commonCombat]

export CombatState

type
  GroundUnitType* {.pure.} = enum
    ## Types of ground forces
    Army,           # Garrison forces (defense)
    Marine,         # Invasion forces (offense)
    GroundBattery,  # Planetary defense weapons
    Spacelift       # Transport squadrons (Blitz only)

  GroundUnit* = object
    ## Individual ground combat unit
    unitType*: GroundUnitType
    id*: string
    owner*: HouseId
    attackStrength*: int
    defenseStrength*: int
    state*: CombatState  # Undamaged, Crippled, Destroyed

  PlanetaryDefense* = object
    ## Complete planetary defense setup
    shields*: Option[ShieldLevel]  # SLD1-SLD6
    groundBatteries*: seq[GroundUnit]
    groundForces*: seq[GroundUnit]  # Armies and Marines
    spaceport*: bool  # Destroyed during invasion

  ShieldLevel* = object
    ## Planetary shield information (per reference.md Section 9.3)
    level*: int  # 1-6 (SLD1-SLD6)
    blockChance*: float  # Probability shield blocks damage
    blockPercentage*: float  # % of hits blocked if successful

  BombardmentResult* = object
    ## Result of one bombardment round
    attackerHits*: int
    defenderHits*: int
    shieldBlocked*: int  # Hits blocked by shields
    batteriesDestroyed*: int
    batteriesCrippled*: int
    squadronsDestroyed*: int
    squadronsCrippled*: int
    infrastructureDamage*: int  # IU lost
    populationDamage*: int  # PU lost
    roundsCompleted*: int  # 1-3 max per turn

  InvasionResult* = object
    ## Result of planetary invasion or blitz
    success*: bool
    attacker*: HouseId
    defender*: HouseId
    attackerCasualties*: seq[GroundUnit]
    defenderCasualties*: seq[GroundUnit]
    infrastructureDestroyed*: int  # IU lost (50% on invasion success)
    assetsSeized*: bool  # True for blitz, false for invasion
    batteriesDestroyed*: int  # Ground batteries destroyed (blitz Phase 1 bombardment)
