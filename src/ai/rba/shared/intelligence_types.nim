## RBA Intelligence Types
##
## Domain-specific intelligence type definitions for enhanced intelligence integration
## Provides structured intelligence summaries from engine intelligence reports
##
## Architecture: Centralized analysis (Drungarius Phase 0) → Domain summaries → Advisor consumption
## All types designed for minimal allocations and efficient passing

import std/[tables, options, sets]
import ../../../common/types/[core, tech, units]
import ../../../engine/combat/types as combat_types
import ../../../engine/intelligence/types as intel_types
import ../../common/types  # For GameAct

# Forward declaration of RequirementPriority from controller_types
# This avoids circular dependency since controller_types imports intelligence_types
type
  RequirementPriority* {.pure.} = enum
    Critical, High, Medium, Low, Deferred

type
  # ==============================================================================
  # COMMON TYPES
  # ==============================================================================

  ThreatLevel* {.pure.} = enum
    ## Threat assessment levels for intelligence reports
    tlNone, tlLow, tlModerate, tlHigh, tlCritical

  # ==============================================================================
  # MILITARY INTELLIGENCE
  # ==============================================================================

  EnemyFleetSummary* = object
    ## Processed summary of enemy fleet from SystemIntelReport + FleetMovementHistory
    fleetId*: FleetId
    owner*: HouseId
    lastKnownLocation*: SystemId
    lastSeen*: int  # Turn number
    estimatedStrength*: int  # Rough combat power
    composition*: Option[FleetComposition]  # If we have detailed intel
    threatenedColonies*: seq[SystemId]  # Our colonies in threat range
    isMoving*: bool  # Was observed in transit

  FleetComposition* = object
    ## Fleet composition details from SystemIntelReport
    capitalShips*: int  # Battleships, carriers
    cruisers*: int
    destroyers*: int
    escorts*: int
    scouts*: int
    spaceLiftShips*: int  # Transports
    totalShips*: int
    avgTechLevel*: int  # Average tech level if known (0 = unknown)

  MilitaryCapabilityAssessment* = object
    ## Overall military strength assessment per house
    houseId*: HouseId
    knownFleetCount*: int
    estimatedTotalShipCount*: int
    estimatedFleetStrength*: int  # Total combat power estimate
    observedTechLevel*: int  # 0 = unknown, 1-10 observed
    combatDoctrine*: Option[CombatDoctrine]  # From combat reports
    lastUpdated*: int  # Turn of most recent intel
    confidence*: float  # 0.0-1.0 confidence in assessment

  CombatDoctrine* {.pure.} = enum
    ## Observed enemy combat behavior patterns
    Unknown
    Aggressive    # Pursues, rarely retreats
    Balanced      # Mixed tactics
    Defensive     # Retreats often, defends colonies
    Raiding       # Hit-and-run, avoids large battles

  ThreatAssessment* = object
    ## Threat assessment for a specific colony
    systemId*: SystemId
    level*: ThreatLevel  # None, Low, Moderate, High, Critical
    nearbyEnemyFleets*: int
    estimatedEnemyStrength*: int
    turnsUntilArrival*: Option[int]  # If fleet movement detected
    threatSources*: seq[FleetId]  # Specific fleets threatening this colony
    confidence*: float  # 0.0-1.0 (based on intel freshness)
    lastUpdated*: int  # Turn of assessment

  InvasionOpportunity* = object
    ## Identified vulnerable enemy colony
    systemId*: SystemId
    owner*: HouseId
    vulnerability*: float  # 0.0-1.0 (higher = more vulnerable)
    estimatedDefenses*: int  # Ground units + starbase strength
    estimatedValue*: int  # Production value (PP/turn estimate)
    requiredForce*: int  # Estimated ships needed to take it
    distance*: int  # Jumps from nearest friendly colony
    lastIntelTurn*: int  # When intel was gathered
    intelQuality*: intel_types.IntelQuality

  TacticalLesson* = object
    ## Lessons learned from combat encounters
    combatId*: string
    turn*: int
    enemyHouse*: HouseId
    location*: SystemId
    outcome*: intel_types.CombatOutcome
    effectiveShipTypes*: seq[ShipClass]  # Ship types that performed well
    ineffectiveShipTypes*: seq[ShipClass]  # Ship types that performed poorly
    observedEnemyComposition*: FleetComposition
    ourLosses*: int
    enemyLosses*: int

  MilitaryIntelligence* = object
    ## Military domain intelligence summary for Domestikos
    knownEnemyFleets*: seq[EnemyFleetSummary]
    enemyMilitaryCapability*: Table[HouseId, MilitaryCapabilityAssessment]
    threatsByColony*: Table[SystemId, ThreatAssessment]
    vulnerableTargets*: seq[InvasionOpportunity]
    combatLessonsLearned*: seq[TacticalLesson]

    # Phase E patrol pattern detection
    detectedPatrolRoutes*: seq[PatrolRoute]  # Detected enemy patrol patterns

    lastUpdated*: int

  # ==============================================================================
  # ECONOMIC INTELLIGENCE
  # ==============================================================================

  EconomicAssessment* = object
    ## Economic strength assessment per house
    houseId*: HouseId
    knownColonyCount*: int
    estimatedTotalProduction*: int  # Total PP/turn estimate
    estimatedIncome*: Option[int]  # From StarbaseIntelReport
    estimatedTechSpending*: Option[int]  # Research budget from StarbaseIntelReport
    taxRate*: Option[float]  # From StarbaseIntelReport
    relativeStrength*: float  # vs our economy (0.5 = half our strength)
    lastUpdated*: int

  HighValueTarget* = object
    ## High-value enemy colony for targeting
    systemId*: SystemId
    owner*: HouseId
    estimatedValue*: int  # Production value (GCO + industry * 100)
    estimatedDefenses*: int
    hasStarbase*: bool
    shipyardCount*: int
    lastUpdated*: int
    intelQuality*: intel_types.IntelQuality

  TechGapAnalysis* = object
    ## Tech gap assessment vs specific house
    targetHouse*: HouseId
    gapsPerField*: Table[TechField, int]  # Negative = we're behind
    criticalGaps*: seq[TechField]  # Gaps >= 2 levels
    advantages*: seq[TechField]  # Where we lead
    lastUpdated*: int

  ConstructionTrend* = object
    ## Observed construction activity at enemy colony
    systemId*: SystemId
    owner*: HouseId
    observedInfrastructure*: int  # IU count
    observedStarbases*: int
    shipyardCount*: int
    constructionQueue*: seq[string]  # If spy quality intel
    activityLevel*: ConstructionActivityLevel
    lastObserved*: int

  ConstructionActivityLevel* {.pure.} = enum
    Unknown, Low, Moderate, High, VeryHigh

  EconomicIntelligence* = object
    ## Economic domain intelligence summary for Eparch
    enemyEconomicStrength*: Table[HouseId, EconomicAssessment]
    highValueTargets*: seq[HighValueTarget]
    enemyTechGaps*: Table[HouseId, TechGapAnalysis]
    constructionActivity*: Table[SystemId, ConstructionTrend]
    lastUpdated*: int

  # ==============================================================================
  # RESEARCH INTELLIGENCE
  # ==============================================================================

  TechLevelEstimate* = object
    ## Estimated tech levels per field for a house
    houseId*: HouseId
    techLevels*: Table[TechField, int]  # Best estimate per field
    confidence*: Table[TechField, float]  # 0.0-1.0 confidence per field
    currentResearch*: Option[TechField]  # What they're researching (if known)
    lastUpdated*: int
    source*: TechIntelSource

  TechIntelSource* {.pure.} = enum
    Unknown, CombatObservation, StarbaseHack, ScoutReport

  ResearchPriority* = object
    ## Urgent research need identified from intelligence
    field*: TechField
    currentLevel*: int  # Our current level
    targetLevel*: int  # Level we need to reach
    reason*: string  # Why this is urgent
    priority*: RequirementPriority
    estimatedTurns*: int  # Turns to research

  ResearchIntelligence* = object
    ## Research domain intelligence summary for Logothete
    enemyTechLevels*: Table[HouseId, TechLevelEstimate]
    techAdvantages*: seq[TechField]  # Fields where we lead
    techGaps*: seq[TechField]  # Fields where we lag (any enemy ahead)
    urgentResearchNeeds*: seq[ResearchPriority]
    lastUpdated*: int

  # ==============================================================================
  # ESPIONAGE INTELLIGENCE
  # ==============================================================================

  IntelCoverageScore* = object
    ## How well we know a specific house
    houseId*: HouseId
    knownColonies*: int
    totalEstimatedColonies*: int  # From prestige/visible systems
    coveragePercent*: float  # 0.0-1.0
    hasStarbaseIntel*: bool
    hasCombatIntel*: bool
    avgIntelAge*: float  # Average turns since intel gathered
    gaps*: seq[SystemId]  # Known systems with stale/no intel

  EspionageTarget* = object
    ## High-priority espionage target
    targetType*: EspionageTargetType
    systemId*: Option[SystemId]
    houseId*: HouseId
    priority*: RequirementPriority
    reason*: string
    lastAttemptTurn*: Option[int]

  EspionageTargetType* {.pure.} = enum
    ColonySpy, SystemSpy, StarbaseHack, ScoutRecon

  DetectionRiskLevel* {.pure.} = enum
    Unknown, Low, Moderate, High, Critical

  SurveillanceGapReason* {.pure.} = enum
    ## Reason why a system lacks starbase surveillance coverage
    NoBorderCoverage      # Border system adjacent to enemy territory without starbase
    HighValueTarget       # High-value colony without automated surveillance
    TransitRoute          # Key transit route between core colonies
    RecentThreatActivity  # System with recent threat detection but no permanent coverage

  SurveillanceGap* = object
    ## System identified as needing starbase coverage (Phase D)
    systemId*: SystemId
    priority*: float  # 0.0-1.0 (higher = more urgent)
    reason*: SurveillanceGapReason
    estimatedThreats*: int  # Number of threats detected in area
    lastActivity*: Option[int]  # Turn when last enemy activity detected

  StarbaseCoverageInfo* = object
    ## Starbase surveillance coverage details for a system (Phase D)
    hasStarbase*: bool
    starbaseId*: Option[string]
    detectedThreats*: seq[FleetId]  # Threats detected by this starbase
    lastActivity*: int  # Turn of most recent detection
    coverageRadius*: int  # Systems covered (current implementation: 0 = own system only)

  # ==============================================================================
  # PHASE E: ENHANCED INTELLIGENCE TYPES
  # ==============================================================================

  BlockadeInfo* = object
    ## Active blockade intelligence (Phase E)
    systemId*: SystemId
    blockader*: HouseId
    targetOwner*: HouseId
    established*: int  # Turn established
    economicImpact*: float  # Estimated GCO reduction (0.6 = 60% reduction)

  DiplomaticEventType* {.pure.} = enum
    ## Types of diplomatic events (Phase E)
    WarDeclared, PeaceTreaty, AllianceFormed, PactSigned,
    DiplomaticBreak, PactViolated

  DiplomaticEvent* = object
    ## Diplomatic event intelligence (Phase E)
    turn*: int
    eventType*: DiplomaticEventType
    houses*: seq[HouseId]  # Parties involved
    significance*: int  # 1-10 rating
    description*: string

  EspionagePattern* = object
    ## Detected espionage pattern against our house (Phase E)
    perpetrator*: HouseId
    attempts*: int  # Total attempts detected
    successes*: int  # Successful operations
    lastAttempt*: int  # Most recent turn
    targetTypes*: seq[string]  # What they're trying to steal/sabotage

  PatrolRoute* = object
    ## Detected enemy patrol route (Phase E)
    fleetId*: FleetId
    owner*: HouseId
    systems*: seq[SystemId]  # Ordered patrol route
    confidence*: float  # 0.0-1.0 (pattern strength)
    lastUpdated*: int

  EspionageIntelligence* = object
    ## Espionage domain intelligence summary for Drungarius
    intelCoverage*: Table[HouseId, IntelCoverageScore]
    staleIntelSystems*: seq[SystemId]  # Systems needing reconnaissance
    highPriorityTargets*: seq[EspionageTarget]
    detectionRisks*: Table[HouseId, DetectionRiskLevel]

    # Phase D surveillance gap tracking
    surveillanceGaps*: seq[SurveillanceGap]  # Systems without starbase coverage
    surveillanceCoverage*: Table[SystemId, StarbaseCoverageInfo]  # Coverage map

    # Phase E counter-intelligence tracking
    espionagePatterns*: Table[HouseId, EspionagePattern]  # Detected espionage against us

    lastUpdated*: int

  # ==============================================================================
  # DIPLOMATIC INTELLIGENCE
  # ==============================================================================

  HouseRelativeStrength* = object
    ## Overall strength comparison with another house
    houseId*: HouseId
    militaryStrength*: float  # 0.0-2.0 (1.0 = parity)
    economicStrength*: float
    techStrength*: float
    overallStrength*: float  # Weighted average
    prestigeGap*: int  # Their prestige - our prestige
    trend*: StrengthTrend  # Getting stronger/weaker relative to us

  StrengthTrend* {.pure.} = enum
    Unknown, Declining, Stable, Rising, Surging

  HostilityLevel* {.pure.} = enum
    Unknown, Neutral, Cautious, Hostile, Aggressive

  DiplomaticIntelligence* = object
    ## Diplomatic domain intelligence summary for Protostrator
    houseRelativeStrength*: Table[HouseId, HouseRelativeStrength]
    potentialAllies*: seq[HouseId]  # Weaker houses that might ally
    potentialThreats*: seq[HouseId]  # Stronger/hostile houses
    observedHostility*: Table[HouseId, HostilityLevel]

    # Phase E diplomatic event tracking
    activeBlockades*: seq[BlockadeInfo]  # Current blockades (against us or observed)
    recentDiplomaticEvents*: seq[DiplomaticEvent]  # Recent wars, alliances, pacts

    lastUpdated*: int

  # ==============================================================================
  # ENHANCED INTELLIGENCE SNAPSHOT
  # ==============================================================================

  IntelligenceSnapshot* = object
    ## Enhanced intelligence snapshot with domain-specific summaries
    ## Replaces minimal IntelligenceSnapshot in controller_types.nim
    turn*: int

    # Domain-specific processed intelligence (NEW)
    military*: MilitaryIntelligence
    economic*: EconomicIntelligence
    diplomatic*: DiplomaticIntelligence
    research*: ResearchIntelligence
    espionage*: EspionageIntelligence

    # Backward-compatible quick-access aggregations (EXISTING - maintain compatibility)
    knownEnemyColonies*: seq[tuple[systemId: SystemId, owner: HouseId]]
    enemyFleetMovements*: Table[HouseId, seq[FleetMovement]]
    highValueTargets*: seq[SystemId]
    threatAssessment*: Table[SystemId, ThreatLevel]
    staleIntelSystems*: seq[SystemId]
    espionageOpportunities*: seq[HouseId]

    # Raw report counts for debugging
    reportCounts*: tuple[
      colonies: int,
      systems: int,
      starbases: int,
      combat: int,
      surveillance: int
    ]

  # Backward-compatible type (referenced in existing code)
  FleetMovement* = object
    fleetId*: FleetId
    owner*: HouseId
    lastKnownLocation*: SystemId
    lastSeenTurn*: int
    estimatedStrength*: int
