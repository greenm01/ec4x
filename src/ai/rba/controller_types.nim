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
    DefenseGap, OffensivePrep, ReconnaissanceGap, ExpansionSupport, ThreatResponse

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
