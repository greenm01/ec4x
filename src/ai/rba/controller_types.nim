## AI Controller Type Definition
##
## Separated to avoid circular imports between controller and subsystems

import std/[tables, options]
import ../common/types
import ../../engine/gamestate  # For FallbackRoute
import ../../engine/order_types  # For StandingOrder
import ../../common/types/[core, units]  # For ShipClass

# Forward declarations for Admiral integration
# Full types defined in admiral/build_requirements.nim
type
  RequirementPriority* {.pure.} = enum
    Critical, High, Medium, Low, Deferred

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
    ## Tracks whether a requirement was fulfilled by CFO
    Fulfilled,    # CFO had budget and fulfilled the requirement
    Unfulfilled,  # CFO couldn't afford this requirement
    Deferred      # Low priority, intentionally skipped

  CFOFeedback* = object
    ## CFO's feedback to Admiral on which requirements were fulfilled
    fulfilledRequirements*: seq[BuildRequirement]
    unfulfilledRequirements*: seq[BuildRequirement]
    deferredRequirements*: seq[BuildRequirement]
    totalBudgetAvailable*: int
    totalBudgetSpent*: int
    totalUnfulfilledCost*: int

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
    pendingIntelUpdates*: seq[ReconUpdate]  # Reconnaissance missions scheduled for intel gathering
    admiralRequirements*: Option[BuildRequirements]  # Phase 3: Admiral build requirements
    cfoFeedback*: Option[CFOFeedback]  # Phase 3: CFO feedback on requirement fulfillment
