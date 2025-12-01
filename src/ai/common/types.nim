## Shared AI Types
##
## Common types used across all AI implementations (RBA and NNA)
## Extracted from tests/balance/ to create proper production architecture

import std/[tables, options]
import ../../engine/gamestate
import ../../engine/orders  # For BuildOrder type
import ../../engine/diplomacy/types as dip_types
import ../../common/types/[core, units, planets, tech]

# =============================================================================
# Game Phase Types
# =============================================================================

type
  GameAct* {.pure.} = enum
    ## 4-Act game structure that scales with map size
    ## Each act has different strategic priorities
    Act1_LandGrab,      # Turns 1-7: Rapid colonization, exploration
    Act2_RisingTensions, # Turns 8-15: Consolidation, military buildup, diplomacy
    Act3_TotalWar,      # Turns 16-25: Major conflicts, invasions
    Act4_Endgame        # Turns 26-30: Final push for victory

# =============================================================================
# AI Strategy & Personality Types
# =============================================================================

type
  AIStrategy* {.pure.} = enum
    ## Different AI play styles for balance testing (12 max for max players)
    Aggressive,          # Heavy military, early attacks
    Economic,            # Focus on growth and tech
    Espionage,           # Intelligence and sabotage
    Diplomatic,          # Pacts and manipulation
    Balanced,            # Mixed approach
    Turtle,              # Defensive, slow expansion
    Expansionist,        # Rapid colonization
    TechRush,            # Maximum tech priority, minimal military
    Raider,              # Hit-and-run, harassment focus
    MilitaryIndustrial,  # Balanced military + economy
    Opportunistic,       # Flexible, adapts to circumstances
    Isolationist         # Minimal interaction, self-sufficient

  AIPersonality* = object
    ## Continuous personality traits that define AI behavior
    ## All values 0.0-1.0, combined to create emergent strategies
    aggression*: float       # How likely to attack
    riskTolerance*: float    # Willingness to take risks
    economicFocus*: float    # Priority on economy vs military
    expansionDrive*: float   # How aggressively to expand
    diplomacyValue*: float   # Value placed on alliances
    techPriority*: float     # Research investment priority

# =============================================================================
# Intelligence & Reconnaissance Types
# =============================================================================

type
  IntelligenceReport* = object
    ## Intelligence gathered about a system
    systemId*: SystemId
    lastUpdated*: int         # Turn number of last intel
    hasColony*: bool          # Is system colonized?
    owner*: Option[HouseId]   # Who owns the colony?
    estimatedFleetStrength*: int  # Estimated military strength
    estimatedDefenses*: int   # Starbases, ground batteries
    planetClass*: Option[PlanetClass]
    resources*: Option[ResourceRating]
    confidenceLevel*: float   # 0.0-1.0: How reliable is this intel?

  EconomicIntelligence* = object
    ## Economic assessment of enemy houses
    targetHouse*: HouseId
    estimatedProduction*: int      # Total PP across all visible colonies
    highValueTargets*: seq[SystemId]  # Colonies with production >= 50
    economicStrength*: float        # Relative strength vs us (1.0 = equal)

# =============================================================================
# Operational Planning Types
# =============================================================================

type
  OperationType* {.pure.} = enum
    ## Types of coordinated operations
    Invasion,      # Multi-fleet invasion of enemy colony
    Defense,       # Multiple fleets defending important system
    Raid,          # Quick strike with concentrated force
    Blockade       # Economic warfare with fleet support

  CoordinatedOperation* = object
    ## Planned multi-fleet operation
    operationType*: OperationType
    targetSystem*: SystemId
    assemblyPoint*: SystemId  # Where fleets rendezvous
    requiredFleets*: seq[FleetId]  # Fleets assigned to operation
    readyFleets*: seq[FleetId]     # Fleets that have arrived at assembly
    turnScheduled*: int            # When operation was planned
    executionTurn*: Option[int]    # When to execute (after assembly)

  StrategicReserve* = object
    ## Fleet designated as strategic reserve
    fleetId*: FleetId
    assignedTo*: Option[SystemId]  # System assigned to defend
    responseRadius*: int           # How far can respond (in jumps)

# =============================================================================
# Combat Assessment Types
# =============================================================================

type
  CombatAssessment* = object
    ## Assessment of combat situation for attacking a target system
    targetSystem*: SystemId
    targetOwner*: HouseId

    # Fleet strengths
    attackerFleetStrength*: int    # Our attack power
    defenderFleetStrength*: int    # Enemy fleet defense at target

    # Defensive installations
    starbaseStrength*: int         # Starbase attack/defense
    groundBatteryCount*: int       # Ground batteries
    planetaryShieldLevel*: int     # Shield level (0-6)
    groundForces*: int             # Armies + marines

    # Combat odds
    estimatedCombatOdds*: float    # 0.0-1.0: Probability of victory
    expectedCasualties*: int       # Expected ship losses

    # Strategic factors
    violatesPact*: bool            # Would attack violate non-aggression pact?
    strategicValue*: int           # Value of target (production, resources)

    # Recommendations
    recommendAttack*: bool         # Should we attack?
    recommendReinforce*: bool      # Should we send reinforcements?
    recommendRetreat*: bool        # Should we retreat from system?

  InvasionViability* = object
    ## 3-phase invasion assessment
    ## Per docs/specs/operations.md: Invasions have 3 phases

    # Phase 1: Space Combat
    canWinSpaceCombat*: bool       # Can defeat enemy fleets?
    spaceOdds*: float              # Space combat victory odds

    # Phase 2: Starbase Assault
    canDestroyStarbases*: bool     # Can destroy defensive starbases?
    starbaseOdds*: float           # Starbase destruction odds

    # Phase 3: Ground Invasion
    canWinGroundCombat*: bool      # Can overcome ground forces?
    groundOdds*: float             # Ground combat victory odds
    attackerGroundForces*: int     # Marines available
    defenderGroundForces*: int     # Enemy marines + armies + batteries

    # Overall assessment
    invasionViable*: bool          # All 3 phases passable?
    recommendInvade*: bool         # Full invasion recommended?
    recommendBlitz*: bool          # Blitz (skip ground) recommended?
    recommendBlockade*: bool       # Blockade instead of invasion?
    strategicValue*: int           # Value of target (production, resources)

# =============================================================================
# Diplomatic Assessment Types
# =============================================================================

type
  DiplomaticAssessment* = object
    ## Assessment of diplomatic situation with target house
    ## 4-level diplomatic system: Neutral, Ally, Hostile, Enemy
    targetHouse*: HouseId
    relativeMilitaryStrength*: float  # Our strength / their strength (1.0 = equal)
    relativeEconomicStrength*: float  # Our economy / their economy (1.0 = equal)
    mutualEnemies*: seq[HouseId]      # Houses both consider enemies
    geographicProximity*: int         # Number of neighboring systems
    violationRisk*: float             # 0.0-1.0: Risk they violate pact
    currentState*: dip_types.DiplomaticState
    recommendPact*: bool              # Should we propose/maintain pact (Ally)?
    recommendBreak*: bool             # Should we break existing pact?
    recommendHostile*: bool           # Should we escalate to Hostile?
    recommendEnemy*: bool             # Should we escalate to Enemy?
    recommendNeutral*: bool           # Should we de-escalate to Neutral?

# =============================================================================
# Garrison & Defense Planning Types
# =============================================================================

type
  GarrisonPlan* = object
    ## Plan for maintaining marine garrisons
    systemId*: SystemId
    currentMarines*: int
    targetMarines*: int
    priority*: float  # Higher = more important to defend

# =============================================================================
# Budget Allocation Types (from ai_budget.nim)
# =============================================================================

type
  BuildObjective* {.pure.} = enum
    ## Strategic build objectives with competing priorities
    Expansion,      # ETACs, colony infrastructure
    Defense,        # Starbases, ground batteries
    Military,       # Frigates, destroyers, cruisers, battleships, dreadnoughts
    Reconnaissance, # Scouts for exploration and reconnaissance
    SpecialUnits,   # Fighters, carriers, transports, raiders, planet-breakers
    Technology      # Reserved for future research investment features

  BudgetAllocation* = Table[BuildObjective, float]
    ## Percentage of treasury allocated to each objective (must sum to ~1.0)

  ObjectiveBuildPlan* = object
    ## Build orders for a specific objective with allocated budget
    objective*: BuildObjective
    budgetPP*: int              # Allocated budget in PP
    orders*: seq[BuildOrder]    # Generated orders within budget
    spentPP*: int               # Actual PP spent
    remainingPP*: int           # Leftover budget

# =============================================================================
# Utility Functions
# =============================================================================

proc getCurrentGameAct*(turn: int): GameAct =
  ## Determine current game act based on turn number
  if turn <= 7:
    GameAct.Act1_LandGrab
  elif turn <= 15:
    GameAct.Act2_RisingTensions
  elif turn <= 25:
    GameAct.Act3_TotalWar
  else:
    GameAct.Act4_Endgame
