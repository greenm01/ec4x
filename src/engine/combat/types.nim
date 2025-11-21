## Core combat system types for EC4X
##
## Pure data types for combat resolution.
## No I/O, no JSON - just game logic types.
##
## Based on EC4X specifications Section 7.0 Combat

import std/[tables, options]
import ../../common/types/[core, units, combat as commonCombat, diplomacy]
import ../squadron

export HouseId, SystemId, FleetId, SquadronId
export Squadron, EnhancedShip, ShipClass
export commonCombat.CombatState  # Use existing CombatState from common
export diplomacy.DiplomaticState

type
  ## Combat Phases (Section 7.3.1)
  CombatPhase* {.pure.} = enum
    PreCombat,      # Detection rolls, Task Force formation
    Ambush,         # Phase 1: Undetected Raiders
    Intercept,      # Phase 2: Fighter Squadrons
    MainEngagement, # Phase 3: Capital Ships
    PostCombat      # Retreat evaluation, cleanup

  ## Combat Effectiveness Rating (Section 7.3.3)
  CERModifier* {.pure.} = enum
    Scouts,    # +1 (max, for all scouts in TF)
    Morale,    # -1 to +2 (per turn morale check)
    Surprise,  # +3 (first round only)
    Ambush     # +4 (first round only, Phase 1)

  CERRoll* = object
    ## Result of rolling for Combat Effectiveness Rating
    naturalRoll*: int        # 1-10 (natural die roll before modifiers)
    modifiers*: int          # Sum of all applicable modifiers
    finalRoll*: int          # naturalRoll + modifiers
    effectiveness*: float    # 0.25, 0.5, 0.75, or 1.0
    isCriticalHit*: bool     # Natural 9 before modifiers

  ## Target Priority Buckets (Section 7.3.2.2)
  TargetBucket* {.pure.} = enum
    Raider = 1,     # Squadron with Raider flagship
    Capital = 2,    # Squadron with Cruiser/Carrier flagship
    Destroyer = 3,  # Squadron with Destroyer flagship
    Fighter = 4,    # Fighter squadron (no capital flagship)
    Starbase = 5    # Orbital installation

  ## Squadron in combat context
  ## Note: CombatState is imported from common/types/combat.nim
  CombatSquadron* = object
    squadron*: Squadron
    state*: CombatState
    damageThisTurn*: int     # Track damage for destruction protection
    crippleRound*: int       # Round when crippled (for destruction protection)
    bucket*: TargetBucket
    targetWeight*: float     # Base weight × crippled modifier

  ## Task Force (Section 7.2)
  TaskForce* = object
    house*: HouseId
    squadrons*: seq[CombatSquadron]
    roe*: int                # Rules of Engagement (0-10)
    isCloaked*: bool         # All Raiders, none detected
    moraleModifier*: int     # -1 to +2 from prestige
    scoutBonus*: bool        # Has scouts (+1 CER)
    isDefendingHomeworld*: bool  # Never retreat

  ## Combat Round Result
  RoundResult* = object
    phase*: CombatPhase
    roundNumber*: int
    attacks*: seq[AttackResult]
    stateChanges*: seq[StateChange]

  AttackResult* = object
    attackerId*: SquadronId
    targetId*: SquadronId
    cerRoll*: CERRoll
    damageDealt*: int
    targetStateBefore*: CombatState
    targetStateAfter*: CombatState

  StateChange* = object
    squadronId*: SquadronId
    fromState*: CombatState
    toState*: CombatState
    destructionProtectionApplied*: bool

  ## Retreat Decision
  RetreatEvaluation* = object
    taskForce*: HouseId
    wantsToRetreat*: bool
    effectiveROE*: int       # Base ROE + morale modifier
    ourStrength*: int
    enemyStrength*: int
    strengthRatio*: float
    reason*: string

  ## Complete Combat Result
  CombatResult* = object
    systemId*: SystemId
    rounds*: seq[seq[RoundResult]]  # Each round has multiple phases
    survivors*: seq[TaskForce]
    retreated*: seq[HouseId]
    eliminated*: seq[HouseId]
    victor*: Option[HouseId]
    totalRounds*: int
    wasStalemate*: bool

  ## Battle Context (input to combat resolution)
  BattleContext* = object
    systemId*: SystemId
    taskForces*: seq[TaskForce]
    seed*: int64              # For deterministic PRNG
    maxRounds*: int           # Default 20 (stalemate)

## Helper procs for combat squadrons

proc getCurrentAS*(cs: CombatSquadron): int =
  ## Get current attack strength (reduced if crippled)
  if cs.state == CombatState.Crippled:
    return cs.squadron.combatStrength() div 2
  elif cs.state == CombatState.Destroyed:
    return 0
  else:
    return cs.squadron.combatStrength()

proc getCurrentDS*(cs: CombatSquadron): int =
  ## Get defense strength (doesn't change when crippled)
  return cs.squadron.defenseStrength()

proc isAlive*(cs: CombatSquadron): bool =
  ## Check if squadron can still fight
  cs.state != CombatState.Destroyed

proc canBeTargeted*(cs: CombatSquadron): bool =
  ## Check if squadron is valid target
  cs.state != CombatState.Destroyed

## Task Force helpers

proc totalAS*(tf: TaskForce): int =
  ## Calculate total attack strength of Task Force
  result = 0
  for sq in tf.squadrons:
    result += sq.getCurrentAS()

proc aliveSquadrons*(tf: TaskForce): seq[CombatSquadron] =
  ## Get all non-destroyed squadrons
  result = @[]
  for sq in tf.squadrons:
    if sq.isAlive():
      result.add(sq)

proc isEliminated*(tf: TaskForce): bool =
  ## Check if Task Force has no surviving squadrons
  for sq in tf.squadrons:
    if sq.isAlive():
      return false
  return true

## CER Table lookup (Section 7.3.3)

proc lookupCER*(modifiedRoll: int): float =
  ## Convert modified die roll to effectiveness multiplier
  ## Based on CER Table from Section 7.3.3
  if modifiedRoll <= 2:
    return 0.25
  elif modifiedRoll <= 4:
    return 0.50
  elif modifiedRoll <= 6:
    return 0.75
  else:
    return 1.0

proc isCritical*(naturalRoll: int): bool =
  ## Check if natural roll (before modifiers) is critical hit
  ## Natural 9 = critical hit (Section 7.3.3)
  naturalRoll == 9

## Target bucket classification (Section 7.3.2.2)

proc classifyBucket*(sq: Squadron): TargetBucket =
  ## Determine target priority bucket for squadron
  case sq.flagship.shipClass
  of ShipClass.Raider:
    return TargetBucket.Raider
  of ShipClass.Cruiser, ShipClass.LightCruiser, ShipClass.HeavyCruiser,
     ShipClass.Battlecruiser, ShipClass.Battleship,
     ShipClass.Dreadnought, ShipClass.SuperDreadnought,
     ShipClass.Carrier, ShipClass.SuperCarrier:
    return TargetBucket.Capital
  of ShipClass.Destroyer:
    return TargetBucket.Destroyer
  of ShipClass.Fighter:
    return TargetBucket.Fighter
  of ShipClass.Starbase:
    return TargetBucket.Starbase
  else:
    # Default to capital for unknown types
    return TargetBucket.Capital

proc baseWeight*(bucket: TargetBucket): float =
  ## Get base targeting weight for bucket (Section 7.3.2.2)
  case bucket
  of TargetBucket.Raider: 1.0
  of TargetBucket.Capital: 2.0
  of TargetBucket.Destroyer: 3.0
  of TargetBucket.Fighter: 4.0
  of TargetBucket.Starbase: 5.0

proc calculateTargetWeight*(cs: CombatSquadron): float =
  ## Calculate weighted random selection weight
  ## Crippled units get 2x weight (Section 7.3.2.5)
  let base = cs.bucket.baseWeight()
  if cs.state == CombatState.Crippled:
    return base * 2.0
  else:
    return base
