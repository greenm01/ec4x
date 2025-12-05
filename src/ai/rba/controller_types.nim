## AI Controller Type Definition
##
## Separated to avoid circular imports between controller and subsystems

import std/[tables, options]
import ../common/types
import ../../engine/gamestate  # For FallbackRoute
import ../../engine/order_types  # For StandingOrder
import ../../engine/commands/zero_turn_commands  # For ZeroTurnCommand
import ../../common/types/[core, units, planets]  # For ShipClass, PlanetClass
import ../../engine/espionage/types as esp_types  # For EspionageAction
import ../../engine/diplomacy/proposals as dip_proposals  # For ProposalType
import ./shared/intelligence_types  # Enhanced intelligence types (Phase B+)

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

  BuildRequirement* = object
    requirementType*: RequirementType
    priority*: RequirementPriority
    shipClass*: Option[ShipClass]
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

  TreasurerFeedback* = object
    ## Treasurer's feedback to Admiral on which requirements were fulfilled
    fulfilledRequirements*: seq[BuildRequirement]
    unfulfilledRequirements*: seq[BuildRequirement]
    deferredRequirements*: seq[BuildRequirement]
    totalBudgetAvailable*: int
    totalBudgetSpent*: int
    totalUnfulfilledCost*: int

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

    # Phase C: Enhanced intelligence distribution
    intelligenceSnapshot*: Option[IntelligenceSnapshot]  # Current turn's intelligence from Drungarius
