## Core combat system types for EC4X
##
## Pure data types for combat resolution.
## Based on EC4X specifications Section 7.0 Combat

import std/[tables, options]
import ./core
import ./fleet  # For FleetStatus
import ./diplomacy  # For DiplomaticState

type
  CombatState* {.pure.} = enum
    Undamaged, Crippled, Destroyed

  CombatPhase* {.pure.} = enum
    PreCombat, Ambush, Intercept, MainEngagement, PostCombat

  CERModifier* {.pure.} = enum
    Scouts, Morale, Surprise, Ambush

  CERRoll* = object
    naturalRoll*: int32
    modifiers*: int32
    finalRoll*: int32
    effectiveness*: float32
    isCriticalHit*: bool

  TargetBucket* {.pure.} = enum
    Raider = 1, Capital = 2, Escort = 3, Fighter = 4, Starbase = 5

  CombatTargetKind* {.pure.} = enum
    Squadron, Facility

  CombatTargetId* = object
    case kind*: CombatTargetKind
    of Squadron:
      squadronId*: SquadronId
    of Facility:
      facilityId*: StarbaseId  # Use typed ID, not string

  CombatSquadron* = object
    squadronId*: SquadronId  # Reference, not embedded object
    state*: CombatState
    fleetStatus*: FleetStatus
    damageThisTurn*: int32
    crippleRound*: int32
    bucket*: TargetBucket
    targetWeight*: float32

  CombatFacility* = object
    facilityId*: StarbaseId
    systemId*: SystemId
    owner*: HouseId
    attackStrength*: int32
    defenseStrength*: int32
    state*: CombatState
    damageThisTurn*: int32
    crippleRound*: int32
    bucket*: TargetBucket
    targetWeight*: float32

  TaskForce* = object
    houseId*: HouseId
    squadronIds*: seq[SquadronId]  # Store IDs, not objects
    facilityIds*: seq[StarbaseId]
    roe*: int32
    isCloaked*: bool
    moraleModifier*: int32
    isDefendingHomeworld*: bool
    eliLevel*: int32
    clkLevel*: int32

  AttackResult* = object
    attackerId*: SquadronId
    targetId*: CombatTargetId  # Can be squadron or facility
    cerRoll*: CERRoll
    damageDealt*: int32
    targetStateBefore*: CombatState
    targetStateAfter*: CombatState

  StateChange* = object
    targetId*: CombatTargetId
    fromState*: CombatState
    toState*: CombatState
    destructionProtectionApplied*: bool

  RoundResult* = object
    phase*: CombatPhase
    roundNumber*: int32
    attacks*: seq[AttackResult]
    stateChanges*: seq[StateChange]

  RetreatEvaluation* = object
    taskForceHouse*: HouseId
    wantsToRetreat*: bool
    effectiveROE*: int32
    ourStrength*: int32
    enemyStrength*: int32
    strengthRatio*: float32
    reason*: string

  CombatResult* = object
    systemId*: SystemId
    rounds*: seq[seq[RoundResult]]
    survivors*: seq[TaskForce]
    retreated*: seq[HouseId]
    eliminated*: seq[HouseId]
    victor*: Option[HouseId]
    totalRounds*: int32
    wasStalemate*: bool

  BattleContext* = object
    systemId*: SystemId
    taskForces*: seq[TaskForce]
    seed*: int64
    maxRounds*: int32
    allowAmbush*: bool
    allowStarbaseCombat*: bool
    preDetectedHouses*: seq[HouseId]
    diplomaticRelations*: Table[(HouseId, HouseId), DiplomaticState]
    systemOwner*: Option[HouseId]

  CombatReport* = object
    systemId*: SystemId
    attackers*: seq[HouseId]
    defenders*: seq[HouseId]
    attackerLosses*: int32
    defenderLosses*: int32
    victor*: Option[HouseId]
