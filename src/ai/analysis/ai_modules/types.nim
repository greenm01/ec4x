## AI Controller Types
##
## Core type definitions for the AI controller system

import std/[tables, options]
import ../../../src/engine/[gamestate, fog_of_war]
import ../../../src/common/types/[core, planets]

# Export FallbackRoute from gamestate
export gamestate.FallbackRoute

type
  AIStrategy* {.pure.} = enum
    ## Different AI play styles for balance testing
    Aggressive,      # Heavy military, early attacks
    Economic,        # Focus on growth and tech
    Espionage,       # Intelligence and sabotage
    Diplomatic,      # Pacts and manipulation
    Balanced,        # Mixed approach
    Turtle,          # Defensive, slow expansion
    Expansionist     # Rapid colonization

  AIPersonality* = object
    aggression*: float       # 0.0-1.0: How likely to attack
    riskTolerance*: float    # 0.0-1.0: Willingness to take risks
    economicFocus*: float    # 0.0-1.0: Priority on economy vs military
    expansionDrive*: float   # 0.0-1.0: How aggressively to expand
    diplomacyValue*: float   # 0.0-1.0: Value placed on alliances
    techPriority*: float     # 0.0-1.0: Research investment priority

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

  AIController* = object
    houseId*: HouseId
    strategy*: AIStrategy
    personality*: AIPersonality
    lastTurnReport*: string  ## Previous turn's report for context
    intelligence*: Table[SystemId, IntelligenceReport]  ## Gathered intel on systems
    operations*: seq[CoordinatedOperation]  ## Planned multi-fleet operations
    reserves*: seq[StrategicReserve]        ## Strategic reserve fleets
    fallbackRoutes*: seq[FallbackRoute]     ## Phase 2h: Safe retreat routes

# Strategy personality profiles
proc getStrategyPersonality*(strategy: AIStrategy): AIPersonality =
  ## Get personality parameters for a strategy
  case strategy
  of AIStrategy.Aggressive:
    AIPersonality(
      aggression: 0.9,
      riskTolerance: 0.8,
      economicFocus: 0.3,
      expansionDrive: 0.5,
      diplomacyValue: 0.2,
      techPriority: 0.4
    )
  of AIStrategy.Economic:
    AIPersonality(
      aggression: 0.3,
      riskTolerance: 0.3,
      economicFocus: 0.9,
      expansionDrive: 0.5,
      diplomacyValue: 0.6,
      techPriority: 0.8
    )
  of AIStrategy.Espionage:
    AIPersonality(
      aggression: 0.5,
      riskTolerance: 0.6,
      economicFocus: 0.5,
      expansionDrive: 0.4,
      diplomacyValue: 0.4,
      techPriority: 0.6
    )
  of AIStrategy.Diplomatic:
    AIPersonality(
      aggression: 0.3,
      riskTolerance: 0.4,
      economicFocus: 0.6,
      expansionDrive: 0.5,
      diplomacyValue: 0.9,
      techPriority: 0.5
    )
  of AIStrategy.Balanced:
    AIPersonality(
      aggression: 0.4,
      riskTolerance: 0.5,
      economicFocus: 0.7,
      expansionDrive: 0.5,
      diplomacyValue: 0.6,
      techPriority: 0.5
    )
  of AIStrategy.Turtle:
    AIPersonality(
      aggression: 0.1,
      riskTolerance: 0.3,
      economicFocus: 0.7,
      expansionDrive: 0.4,
      diplomacyValue: 0.7,
      techPriority: 0.7
    )
  of AIStrategy.Expansionist:
    AIPersonality(
      aggression: 0.6,
      riskTolerance: 0.7,
      economicFocus: 0.4,
      expansionDrive: 0.95,
      diplomacyValue: 0.3,
      techPriority: 0.3
    )

proc newAIController*(houseId: HouseId, strategy: AIStrategy): AIController =
  ## Create a new AI controller for a house
  AIController(
    houseId: houseId,
    strategy: strategy,
    personality: getStrategyPersonality(strategy),
    intelligence: initTable[SystemId, IntelligenceReport](),
    operations: @[],
    reserves: @[],
    fallbackRoutes: @[]
  )

proc newAIControllerWithPersonality*(houseId: HouseId, personality: AIPersonality): AIController =
  ## Create a new AI controller with a custom personality
  AIController(
    houseId: houseId,
    strategy: AIStrategy.Balanced,
    personality: personality,
    intelligence: initTable[SystemId, IntelligenceReport](),
    operations: @[],
    reserves: @[],
    fallbackRoutes: @[]
  )
