## Core combat system types for EC4X
##
## Pure data types for combat resolution.
## Based on EC4X specifications Section 7.0 Combat

import std/[tables, options]
import ./core
import ./fleet # For FleetStatus
import ./diplomacy # For DiplomaticState

type
  CombatState* {.pure.} = enum
    Undamaged
    Crippled
    Destroyed

  CombatPhase* {.pure.} = enum
    ## Strategic combat phases (three sequential stages of battle)
    Space      # Fleet vs fleet combat
    Orbital    # Orbital bombardment/facility combat
    Planetary  # Ground invasion/combat

  ResolutionPhase* {.pure.} = enum
    ## Tactical resolution phases within Space/Orbital combat
    ## Per docs/specs/07-combat.md Section 7.3.1
    Ambush          # Phase 1: Undetected Raiders
    Intercept       # Phase 2: Fighters
    MainEngagement  # Phase 3: Capital Ships

  CombatOutcome* {.pure.} = enum
    ## Result of combat engagement (for intel reports)
    Victory
    Defeat
    Retreat
    MutualRetreat
    Ongoing

  BlockadeStatus* {.pure.} = enum
    ## Status of orbital blockade (for intel reports)
    Established
    Lifted

  CERModifier* {.pure.} = enum
    Morale
    Ambush

  MoraleEffectTarget* {.pure.} = enum
    ## Who receives the CER bonus from a successful morale check
    ## Based on docs/specs/07-combat.md Section 7.3.3
    None      # No bonus applied
    Random    # Applies to one random ship
    All       # Applies to all ships

  MoraleTier* {.pure.} = enum
    ## Morale tier based on house prestige
    ## Based on docs/specs/07-combat.md Section 7.3.3
    Collapsing  # Prestige ≤ 0
    VeryLow     # Prestige ≤ 20
    Low         # Prestige ≤ 60
    Normal      # Prestige ≤ 80
    High        # Prestige ≤ 100
    VeryHigh    # Prestige > 100

  MoraleCheckResult* = object
    ## Result of a 1d20 morale check for a task force
    rolled*: bool              # Whether check was attempted
    roll*: int32               # 1d20 roll value
    threshold*: int32          # Required roll to succeed
    success*: bool             # Whether check succeeded
    cerBonus*: int32           # CER bonus if successful
    appliesTo*: MoraleEffectTarget  # Who receives the bonus
    criticalAutoSuccess*: bool # High morale critical hit rule

  CERRoll* = object
    naturalRoll*: int32
    modifiers*: int32
    finalRoll*: int32
    effectiveness*: float32
    isCriticalHit*: bool

  TargetBucket* {.pure.} = enum
    Raider = 1
    Capital = 2
    Escort = 3
    Fighter = 4
    Starbase = 5

  CombatTargetKind* {.pure.} = enum
    Ship
    Facility

  CombatTargetId* = object
    case kind*: CombatTargetKind
    of Ship:
      shipId*: ShipId
    of Facility:
      kastraId*: KastraId  # Defensive facility (Starbase)

  CombatShip* = object
    shipId*: ShipId # Reference ID
    attackStrength*: int32 # Cached AS from ship for combat
    defenseStrength*: int32 # Cached DS from ship for combat
    state*: CombatState
    fleetStatus*: FleetStatus
    damageThisTurn*: int32
    crippleRound*: int32
    bucket*: TargetBucket
    targetWeight*: float32

  CombatFacility* = object
    facilityId*: KastraId
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
    ships*: seq[CombatShip] # Combat state for ships in this TF
    facilities*: seq[CombatFacility] # Combat state for facilities in this TF
    roe*: int32
    isCloaked*: bool
    moraleModifier*: int32
    isDefendingHomeworld*: bool
    eliLevel*: int32
    clkLevel*: int32

  AttackResult* = object
    attackerId*: CombatTargetId # Can be ship or facility
    targetId*: CombatTargetId # Can be ship or facility
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
    phase*: ResolutionPhase
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
    hasDefenderStarbase*: bool

  CombatReport* = object
    systemId*: SystemId
    attackers*: seq[HouseId]
    defenders*: seq[HouseId]
    attackerLosses*: int32
    defenderLosses*: int32
    victor*: Option[HouseId]

  PlanetaryDefense* = object
    shields*: Option[ShieldLevel]
    groundUnitIds*: seq[GroundUnitId] # All ground units (batteries, armies, marines, shields)
    spaceport*: bool

  ShieldLevel* = object ## Planetary shield information (per reference.md Section 9.3)
    level*: int32 # 1-6 (SLD1-SLD6)
    blockChance*: float32 # Probability shield blocks damage
    blockPercentage*: float32 # % of hits blocked if successful

  BombardmentResult* = object ## Result of one bombardment round
    attackerHits*: int32
    defenderHits*: int32
    shieldBlocked*: int32 # Hits blocked by shields
    batteriesDestroyed*: int32
    batteriesCrippled*: int32
    shipsDestroyed*: int32
    shipsCrippled*: int32
    infrastructureDamage*: int32 # IU lost
    populationDamage*: int32 # PU lost
    roundsCompleted*: int32 # 1-3 max per turn

  InvasionResult* = object ## Result of planetary invasion or blitz
    success*: bool
    attacker*: HouseId
    defender*: HouseId
    attackerCasualties*: seq[GroundUnitId]
    defenderCasualties*: seq[GroundUnitId]
    infrastructureDestroyed*: int32 # IU lost (50% on invasion success)
    assetsSeized*: bool # True for blitz, false for invasion
    batteriesDestroyed*: int32 # Ground batteries destroyed (blitz Phase 1 bombardment)
