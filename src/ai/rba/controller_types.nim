## AI Controller Type Definition
##
## Separated to avoid circular imports between controller and subsystems

import std/tables
import ../common/types
import ../../engine/gamestate  # For FallbackRoute
import ../../engine/order_types  # For StandingOrder
import ../../common/types/core

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
