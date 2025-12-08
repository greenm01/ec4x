## Order Event Factory
## Events for order validation and rejection
##
## DRY Principle: Single source of truth for order event creation
## DoD Principle: Data (GameEvent) separated from creation logic

import std/[options, strformat]
import ../../../common/types/core
import ../types as res_types

proc orderRejected*(
  houseId: HouseId,
  orderType: string,
  reason: string,
  systemId: Option[SystemId] = none(SystemId)
): res_types.GameEvent =
  ## Create event for rejected order (validation failure)
  res_types.GameEvent(
    eventType: res_types.GameEventType.OrderRejected,
    houseId: houseId,
    description: &"{orderType} order rejected: {reason}",
    systemId: systemId
  )
