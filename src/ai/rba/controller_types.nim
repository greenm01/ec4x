## AI Controller Type Definition
##
## Separated to avoid circular imports between controller and subsystems

import std/[tables, options]
import ../common/types
import ../../engine/gamestate  # For FallbackRoute
import ../../engine/order_types  # For StandingOrder
import ../../engine/commands/zero_turn_commands  # For ZeroTurnCommand
import ../../common/types/[core, units, planets]  # For ShipClass, PlanetClass
import ../../engine/resolution/types as event_types # For EspionageAction, DiplomaticProposalType, GameEvent etc.
import ./shared/intelligence_types  # Enhanced intelligence types (Phase B+)
import ../../ai/goap/types as goap_types # For GOAPConfig
import ../../ai/goap/plan_tracking as goap_plan # For PlanTracker

# Re-export RequirementPriority from intelligence_types for convenience
export intelligence_types.RequirementPriority

# Forward declarations for Admiral integration
# Full types defined in domestikos/build_requirements.nim
type
  AdvisorType* {.pure.} = enum
    ## Imperial Byzantine Government advisors
    Domestikos       # Military commander
    Logothete        # Research & technology
    Drungarius       # Intelligence & espionage
    Eparch           # Economic & infrastructure
    Protostrator     # Diplomacy & foreign affairs
    Treasurer        # Budget & finance

  # RequirementPriority imported from intelligence_types (avoids duplication)

  RequirementType* {.pure.} = enum
    DefenseGap, OffensivePrep, ReconnaissanceGap, ExpansionSupport, ThreatResponse,
    StrategicAsset, Infrastructure

  ColonyDefenseHistory* = object
    ## Tracks defense history for escalation logic (Gap 5)
    systemId*: SystemId
    turnsUndefended*: int
    lastDefenderAssigned*: int           # Turn number
    lastCheckedTurn*: int

  BuildRequirement* = object
    ## AI build requirement for Domestikos advisor
    ##
    ## DESIGN: Two-type system matches engine BuildOrder architecture
    ## ================================================================
    ## The engine's BuildOrder uses BuildType enum: {Ship, Building, Infrastructure}
    ## - Ship: All ship classes (use shipClass field)
    ## - Building: Ground units + facilities (use itemId field)
    ## - Infrastructure: IU investment (not used by AI requirements)
    ##
    ## Why NOT three types (Offensive/Defensive/Infrastructure)?
    ## --------------------------------------------------------
    ## 1. Offensive/Defensive/Infrastructure are CONCEPTUAL CATEGORIES, not build types
    ## 2. Ships can be offensive (Destroyer) OR defensive (Starbase) - can't separate by type
    ## 3. Ground units can be offensive (Marine) OR defensive (Army) - same issue
    ## 4. This design mirrors engine's build system, not unit roles
    ##
    ## Unit Role Categories (for reference, NOT type fields):
    ## ======================================================
    ## OFFENSIVE (attack/invasion):
    ##   - Ships: Destroyer, Cruiser, Battleship, Dreadnought, SuperDreadnought,
    ##            Battlecruiser, Raider, Carrier, Fighter, PlanetBreaker
    ##   - Ground: Marine (itemId="Marine")
    ##   - Support: TroopTransport
    ##
    ## DEFENSIVE (colony protection):
    ##   - Ships: Starbase (shipClass), Corvette/Frigate (patrol)
    ##   - Ground: Army (itemId="Army"), GroundBattery (itemId="GroundBattery"),
    ##            PlanetaryShield (itemId="PlanetaryShield")
    ##
    ## INFRASTRUCTURE (production capacity):
    ##   - Facilities: Spaceport (itemId="Spaceport"), Shipyard (itemId="Shipyard")
    ##   - Note: Typically handled by Eparch advisor, not Domestikos
    ##
    ## Field Usage:
    ## ===========
    ## - shipClass: Some(ShipClass.X) + itemId: none → Ship build order
    ## - shipClass: none + itemId: Some("X") → Ground unit/facility build order
    ## - shipClass: none + itemId: none → Invalid (should not occur)
    requirementType*: RequirementType
    priority*: RequirementPriority
    shipClass*: Option[ShipClass]       # For ALL ships (offensive, defensive, support)
    itemId*: Option[string]             # For non-ships: ground units ("Army", "Marine", "GroundBattery", "PlanetaryShield") and facilities ("Spaceport", "Shipyard")
    quantity*: int
    buildObjective*: BuildObjective  # From ai_common_types
    targetSystem*: Option[SystemId]
    estimatedCost*: int
    reason*: string

  BuildRequirements* = object
    requirements*: seq[BuildRequirement]
    totalEstimatedCost*: int
    criticalCount*: int
    highCount*: int
    generatedTurn*: int
    act*: GameAct
    iteration*: int  # Feedback loop iteration (0 = initial, 1+ = reprioritized)

  RequirementFulfillmentStatus* {.pure.} = enum
    ## Tracks whether a requirement was fulfilled by Treasurer
    Fulfilled,    # Treasurer had budget and fulfilled the requirement
    Unfulfilled,  # Treasurer couldn't afford this requirement
    Deferred      # Low priority, intentionally skipped

  UnfulfillmentReason* {.pure.} = enum
    ## Detailed reason why a requirement could not be fulfilled (Gap 6)
    InsufficientBudget     # Not enough PP for even 1 unit
    PartialBudget          # Built some but not full quantity
    ColonyCapacityFull     # No available dock space
    TechNotAvailable       # CST requirement not met
    NoValidColony          # No colony meets build criteria
    BudgetReserved         # Budget allocated to higher priority
    SubstitutionFailed     # Tried substitution, still couldn't afford

  RequirementFeedback* = object
    ## Detailed feedback for a single unfulfilled requirement (Gap 6)
    requirement*: AdvisorRequirement # General type to hold any requirement type
    originalAdvisorReason*: string # The original reason string from the advisor
    unfulfillmentReason*: UnfulfillmentReason # Specific reason Treasurer could not fulfill
    budgetShortfall*: int           # PP gap (0 if partial fulfillment)
    quantityBuilt*: int             # How many were affordable (0 if none)
    suggestion*: Option[string]     # AI-generated suggestion for next steps

  RequirementFeedback* = object
    ## Detailed feedback for a single unfulfilled requirement (Gap 6)
    requirement*: BuildRequirement
    reason*: UnfulfillmentReason
    budgetShortfall*: int           # PP gap (0 if partial fulfillment)
    quantityBuilt*: int             # How many were affordable (0 if none)
    suggestion*: Option[string]     # AI-generated suggestion

  TreasurerFeedback* = object
    ## Treasurer's feedback to Admiral on which requirements were fulfilled
    fulfilledRequirements*: seq[BuildRequirement]
    unfulfilledRequirements*: seq[BuildRequirement]
    deferredRequirements*: seq[BuildRequirement]
    totalBudgetAvailable*: int
    totalBudgetSpent*: int
    totalUnfulfilledCost*: int
    # Gap 6: Rich feedback for intelligent reprioritization
    detailedFeedback*: seq[RequirementFeedback]

  ResearchRequirement* = object
    ## Science Advisor requirement for research investment
    techField*: Option[TechField]  # Some = TRP field, None = ERP/SRP
    priority*: RequirementPriority
    estimatedCost*: int
    reason*: string
    expectedBenefit*: string  # e.g., "Unlocks Dreadnoughts at CST 5"

  ResearchRequirements* = object
    ## Collection of research requirements from Science Advisor
    requirements*: seq[ResearchRequirement]
    totalEstimatedCost*: int
    generatedTurn*: int
    iteration*: int  # Feedback loop counter

  ScienceFeedback* = object
    ## Treasurer's feedback to Science Advisor on research allocation
    fulfilledRequirements*: seq[ResearchRequirement]
    unfulfilledRequirements*: seq[ResearchRequirement]
    totalRPAvailable*: int
    totalRPSpent*: int

  EspionageRequirementType* {.pure.} = enum
    EBPInvestment, CIPInvestment, Operation

  EspionageRequirement* = object
    ## Drungarius requirement for espionage operations
    requirementType*: EspionageRequirementType
    priority*: RequirementPriority
    targetHouse*: Option[HouseId]
    operation*: Option[esp_types.EspionageAction]
    targetSystem*: Option[SystemId] # Added for operations targeting specific systems (e.g., sabotage)
    estimatedCost*: int  # PP cost for EBP/CIP
    reason*: string

  EspionageRequirements* = object
    ## Collection of espionage requirements from Drungarius
    requirements*: seq[EspionageRequirement]
    totalEstimatedCost*: int
    generatedTurn*: int
    iteration*: int

  DrungariusFeedback* = object
    ## Treasurer's feedback to Drungarius on espionage budget
    fulfilledRequirements*: seq[EspionageRequirement]
    unfulfilledRequirements*: seq[EspionageRequirement]
    totalBudgetAvailable*: int
    totalBudgetSpent*: int

  EconomicRequirementType* {.pure.} = enum
    Facility, Terraforming, TaxPolicy, PopulationTransfer, IUInvestment

  EconomicRequirement* = object
    ## Eparch requirement for infrastructure and economy
    requirementType*: EconomicRequirementType
    priority*: RequirementPriority
    targetColony*: SystemId
    facilityType*: Option[string]  # "Shipyard", "Spaceport"
    terraformTarget*: Option[PlanetClass]
    estimatedCost*: int
    reason*: string

  EconomicRequirements* = object
    ## Collection of economic requirements from Eparch
    requirements*: seq[EconomicRequirement]
    totalEstimatedCost*: int
    generatedTurn*: int
    iteration*: int

  EparchFeedback* = object
    ## Treasurer's feedback to Eparch on economic budget
    fulfilledRequirements*: seq[EconomicRequirement]
    unfulfilledRequirements*: seq[EconomicRequirement]
    totalBudgetAvailable*: int
    totalBudgetSpent*: int

  DiplomaticRequirementType* {.pure.} = enum
    ProposePact, BreakPact, DeclareWar, SeekPeace, MaintainRelations

  DiplomaticRequirement* = object
    ## Protostrator requirement for diplomatic actions
    requirementType*: DiplomaticRequirementType
    priority*: RequirementPriority
    targetHouse*: HouseId
    proposalType*: Option[dip_proposals.ProposalType]
    estimatedCost*: int  # Usually 0, but could include bribes/tribute in future
    reason*: string
    expectedBenefit*: string

  DiplomaticRequirements* = object
    ## Collection of diplomatic requirements from Protostrator
    requirements*: seq[DiplomaticRequirement]
    generatedTurn*: int
    iteration*: int

  # Note: Diplomacy doesn't cost PP, so no ProtostratorFeedback from Treasurer
  # Basileus provides feedback on priority conflicts only

  AdvisorRequirement* = object
    ## Generic wrapper for all advisor requirements, used in mediation and feedback.
    advisor*: AdvisorType
    buildReq*: Option[BuildRequirement]
    researchReq*: Option[ResearchRequirement]
    espionageReq*: Option[EspionageRequirement]
    economicReq*: Option[EconomicRequirement]
    diplomaticReq*: Option[DiplomaticRequirement]
    # For matching to GOAP actions, e.g., "BuildFleet", "AllocateResearch"
    requirementType*: string # A string representation of the underlying requirement type for matching
    priority*: intelligence_types.RequirementPriority # Include priority here for easy access in mediation (from shared/intelligence_types)

  # ThreatLevel, FleetMovement, IntelligenceSnapshot now imported from shared/intelligence_types.nim (Phase B+)
  # Kept here for backward compatibility exports
  ThreatLevel* {.pure.} = enum
    ## Threat assessment levels for intelligence reports
    None, Low, Moderate, High, Critical

  # FleetMovement and IntelligenceSnapshot are now imported from intelligence_types.nim
  # Old definitions commented out to prevent duplicates

type
  ReconUpdate* = object
    ## Pending intelligence update from reconnaissance mission
    systemId*: SystemId
    fleetId*: FleetId
    scheduledTurn*: int  # Turn when intel update is expected

  AIController* = ref object
    houseId*: HouseId
    strategy*: AIStrategy
    personality*: AIPersonality
    intelligence*: Table[SystemId, IntelligenceReport]
    operations*: seq[CoordinatedOperation]
    reserves*: seq[StrategicReserve]
    fallbackRoutes*: seq[FallbackRoute]
    homeworld*: SystemId  # Primary fallback and repair location
    standingOrders*: Table[FleetId, StandingOrder]  # QoL: Standing orders for routine tasks
    defenseHistory*: Table[SystemId, ColonyDefenseHistory]  # Gap 5: Defense persistence tracking
    offensiveFleetOrders*: seq[FleetOrder]  # Domestikos offensive operations (Move, Attack, etc.)
    fleetManagementCommands*: seq[ZeroTurnCommand]  # Domestikos fleet management (Merge/Detach/Transfer)
    pendingIntelUpdates*: seq[ReconUpdate]  # Reconnaissance missions scheduled for intel gathering
    # Multi-advisor requirements and feedback (Basileus integration)
    domestikosRequirements*: Option[BuildRequirements]  # Military build requirements
    logotheteRequirements*: Option[ResearchRequirements]  # Research priorities
    drungariusRequirements*: Option[EspionageRequirements]  # Espionage operations
    eparchRequirements*: Option[EconomicRequirements]  # Infrastructure and economy
    protostratorRequirements*: Option[DiplomaticRequirements]  # Diplomatic actions
    treasurerFeedback*: Option[TreasurerFeedback]  # Treasurer feedback on build fulfillment
    scienceFeedback*: Option[ScienceFeedback]  # Treasurer feedback on research allocation
    drungariusFeedback*: Option[DrungariusFeedback]  # Treasurer feedback on espionage budget
    eparchFeedback*: Option[EparchFeedback]  # Treasurer feedback on economic budget

    # GOAP Phase 4: Strategic planning integration
    goapEnabled*: bool  # Quick check if GOAP is enabled
    goapLastPlanningTurn*: int  # Last turn GOAP planning was executed
    goapActiveGoals*: seq[string]  # Brief description of active goals (for debugging)
    goapBudgetEstimates*: Option[Table[DomainType, int]] # Current-turn budget guidance from GOAP
    goapReservedBudget*: Option[int] # Amount GOAP wants to reserve for future turns
    goapConfig*: goap_types.GOAPConfig # Configuration for the GOAP planner
    planTracker*: goap_plan.PlanTracker # Manages GOAP's multi-turn plans
    lastTurnAllocationResult*: Option[MultiAdvisorAllocation] # NEW: Stores result of last turn's budget allocation

    # Phase C: Enhanced intelligence distribution
    intelligenceSnapshot*: Option[IntelligenceSnapshot]  # Current turn's intelligence from Drungarius
