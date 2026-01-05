## Core combat system types for EC4X
##
## Pure data types for combat resolution.
## Based on EC4X specifications Section 7.0 Combat
##
## **KEY ARCHITECTURE PRINCIPLES:**
## - Ships fight directly in fleets (no squadrons)
## - Task force is conceptual (all ships from one house's fleets)
## - Combat aggregates at house level
## - Only persistent state is ship.state (Undamaged/Crippled/Destroyed)

import std/[options, tables]
import ./core

type
  # =============================================================================
  # Ship State (Persistent - survives across rounds)
  # =============================================================================

  CombatState* {.pure.} = enum
    ## Ship/starbase combat state (persistent)
    ## Only three states - no damage tracking between rounds
    Undamaged
    Crippled
    Destroyed

  # =============================================================================
  # Combat Theaters (Sequential Stages)
  # =============================================================================

  CombatTheater* {.pure.} = enum
    ## Strategic combat theaters (three sequential stages of battle)
    ## Per docs/specs/07-combat.md Section 7.1
    Space      # Fleet vs fleet combat in open space
    Orbital    # Fleet vs orbital defenses (starbases)
    Planetary  # Ground combat (bombardment, invasion, blitz)

  # =============================================================================
  # Detection System
  # =============================================================================

  DetectionResult* {.pure.} = enum
    ## How well attacker was detected before combat
    ## Per docs/specs/07-combat.md Section 7.3
    Ambush      # Undetected by 5+ → +4 DRM first round
    Surprise    # Detected late by 1-4 → +3 DRM first round
    Intercept   # Detected normally → +0 DRM

  # =============================================================================
  # House Combat Forces (Replaces TaskForce)
  # =============================================================================

  HouseCombatForce* = object
    ## All fleets from one house participating in combat
    ## "Task force" is purely conceptual - just this aggregation
    ## Per docs/specs/07-combat.md Section 7.2.2
    houseId*: HouseId
    fleets*: seq[FleetId]
    morale*: int32  # DRM from prestige (±1 or ±2)
    eliLevel*: int32
    clkLevel*: int32
    isDefendingHomeworld*: bool

  # =============================================================================
  # Battle Structure
  # =============================================================================

  Battle* = object
    ## One hostile pair resolving combat
    ## Per docs/specs/07-combat.md Section 7.9
    attacker*: HouseCombatForce
    defender*: HouseCombatForce
    theater*: CombatTheater
    systemId*: SystemId
    detectionResult*: DetectionResult
    hasDefenderStarbase*: bool
    attackerRetreatedFleets*: seq[FleetId]
    defenderRetreatedFleets*: seq[FleetId]

  # =============================================================================
  # Multi-House Combat (Targeting System)
  # =============================================================================

  TargetingPriority* = object
    ## Defines what proportion of firepower to direct at a target house
    ## Per docs/specs/07-combat.md Section 7.9.2
    targetHouse*: HouseId
    fireProportion*: float  # 0.0-1.0, sum to 1.0 per shooter

  MultiHouseBattle* = object
    ## Single battle with N participants using targeting matrix
    ## Replaces pairwise Battle bucketing for 3+ house scenarios
    ## Per docs/specs/07-combat.md Section 7.9
    systemId*: SystemId
    theater*: CombatTheater
    participants*: seq[HouseCombatForce]
    targeting*: Table[HouseId, seq[TargetingPriority]]
    detection*: Table[HouseId, DetectionResult]  # One per house
    hasStarbase*: Table[HouseId, bool]  # Per defending house
    retreatedFleets*: seq[FleetId]

  # =============================================================================
  # Combat Results
  # =============================================================================

  ShipLossesByClass* = object
    ## Ship losses grouped by ship class for reporting
    ## Uses string to avoid circular dependency with ship.nim
    shipClassName*: string  # Name of ship class (e.g. "Battleship")
    destroyed*: int32
    crippled*: int32

  HouseCombatResult* = object
    ## Combat outcome for one house
    houseId*: HouseId
    losses*: seq[ShipLossesByClass]
    survived*: bool  # Did house have operational ships at end?
    retreatedFleets*: seq[FleetId]  # Which fleets retreated

  CombatResult* = object
    ## Complete combat result with per-house details
    ## Unified type for both internal resolution and reporting
    systemId*: SystemId
    theater*: CombatTheater
    rounds*: int32
    participants*: seq[HouseCombatResult]
    victor*: Option[HouseId]

  # =============================================================================
  # Outcome Classification
  # =============================================================================

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

  # =============================================================================
  # Planetary Combat
  # =============================================================================

  PlanetaryDefense* = object
    ## Colony defensive assets
    shields*: Option[ShieldLevel]
    groundUnitIds*: seq[GroundUnitId] # All ground units
    spaceport*: bool

  ShieldLevel* = object
    ## Planetary shield information
    ## Per docs/specs/reference.md Section 9.3
    level*: int32 # 1-6 (SLD1-SLD6)
    blockChance*: float32 # Probability shield blocks damage
    blockPercentage*: float32 # % of hits blocked if successful

  BombardmentResult* = object
    ## Result of one bombardment round
    ## Per docs/specs/07-combat.md Section 7.7
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

  InvasionResult* = object
    ## Result of planetary invasion or blitz
    ## Per docs/specs/07-combat.md Section 7.8
    success*: bool
    attacker*: HouseId
    defender*: HouseId
    attackerCasualties*: seq[GroundUnitId]
    defenderCasualties*: seq[GroundUnitId]
    infrastructureDestroyed*: int32 # IU lost
    assetsSeized*: bool # True for blitz, false for invasion
    batteriesDestroyed*: int32 # Ground batteries destroyed

  # =============================================================================
  # Morale System (Kept for Config Compatibility)
  # =============================================================================

  MoraleTier* {.pure.} = enum
    ## Morale tier based on house prestige
    ## Per docs/specs/07-combat.md Section 7.4.2
    Collapsing  # Prestige ≤ 0
    VeryLow     # Prestige ≤ 20
    Low         # Prestige ≤ 60
    Normal      # Prestige ≤ 80
    High        # Prestige ≤ 100
    VeryHigh    # Prestige > 100

  MoraleEffectTarget* {.pure.} = enum
    ## Who receives morale bonus (legacy config system)
    None      # No bonus applied
    Random    # Applies to one random ship
    All       # Applies to all ships

## Design Notes:
##
## **Removed Types (Squadron-Based Architecture):**
## - ResolutionPhase - No longer phased resolution
## - TargetBucket - No bucket targeting
## - CombatShip - Work directly with Ship entities
## - CombatFacility - Work directly with Kastra entities
## - TaskForce - Replaced with HouseCombatForce (conceptual aggregation)
## - AttackResult, RoundResult, StateChange - Simplified tracking
## - BattleContext - Replaced with Battle
##
## **Key Simplifications:**
## 1. Ships fight in fleets (Fleet → Ships, not Fleet → Squadron → Ships)
## 2. Task force is conceptual (just all ships from house's fleets)
## 3. Combat aggregates at house level (sum all AS from all house fleets)
## 4. Each fleet checks own ROE for retreat
## 5. Only persistent state is ship.state (Undamaged/Crippled/Destroyed)
## 6. No damage tracking between rounds
## 7. Two CER tables: Space/Orbital vs Ground
##
## **Spec Compliance:**
## - docs/specs/07-combat.md Section 7.1 - Combat Theaters
## - docs/specs/07-combat.md Section 7.2 - Combat Fundamentals
## - docs/specs/07-combat.md Section 7.3 - Detection & Intelligence
## - docs/specs/07-combat.md Section 7.4 - Combat Resolution System
## - docs/specs/07-combat.md Section 7.9 - Multi-House Combat
