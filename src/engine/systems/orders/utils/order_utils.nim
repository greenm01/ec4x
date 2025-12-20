## Shared Utility Functions for Fleet Order Execution
##
## This module provides common helper procedures used across various fleet order
## execution modules, ensuring DRY principles and consistent event generation.

import std/[options, strformat]
import ../../../common/types/core
import ../../gamestate # For GameState type
import ../../events/event_factory/init as event_factory
import ../../fleet # For FleetId

proc completeFleetOrder*(
  state: var GameState, fleetId: FleetId, orderType: string,
  details: string = "", systemId: Option[SystemId] = none(SystemId),
  events: var seq[event_factory.GameEvent]
) =
  ## Standard completion handler: generates OrderCompleted event
  ## Cleanup handled by event-driven order_cleanup module in Command Phase
  if fleetId notin state.fleets: return
  let houseId = state.fleets[fleetId].owner

  events.add(event_factory.orderCompleted(
    houseId, fleetId, orderType, details, systemId))

  logInfo(LogCategory.lcOrders, &"Fleet {fleetId} {orderType} order completed")
