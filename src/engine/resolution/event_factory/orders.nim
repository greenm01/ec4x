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

proc orderFailed*(
  houseId: HouseId,
  fleetId: FleetId,
  orderType: string,
  reason: string,
  systemId: Option[SystemId] = none(SystemId)
): res_types.GameEvent =
  ## Order execution failed (validation failure at execution time)
  res_types.GameEvent(
    eventType: res_types.GameEventType.OrderFailed,
    houseId: houseId,
    description: &"Fleet {fleetId} {orderType} failed: {reason}",
    systemId: systemId
  )

proc orderAborted*(
  houseId: HouseId,
  fleetId: FleetId,
  orderType: string,
  reason: string,
  systemId: Option[SystemId] = none(SystemId)
): res_types.GameEvent =
  ## Order cancelled/aborted (target lost, conditions changed)
  res_types.GameEvent(
    eventType: res_types.GameEventType.OrderAborted,
    houseId: houseId,
    description: &"Fleet {fleetId} {orderType} aborted: {reason}",
    systemId: systemId
  )

proc orderIssued*(
  houseId: HouseId,
  fleetId: FleetId,
  orderType: string,
  systemId: Option[SystemId] = none(SystemId)
): res_types.GameEvent =
  ## Order submitted and added to fleet orders queue
  res_types.GameEvent(
    eventType: res_types.GameEventType.OrderIssued,
    houseId: houseId,
    description: &"Fleet {fleetId}: Order issued - {orderType}",
    systemId: systemId
  )

proc orderCompleted*(
  houseId: HouseId,
  fleetId: FleetId,
  orderType: string,
  details: string = "",
  systemId: Option[SystemId] = none(SystemId)
): res_types.GameEvent =
  ## Order successfully completed (state change or one-shot operation)
  let desc = if details.len > 0:
    &"Fleet {fleetId} {orderType} completed: {details}"
  else:
    &"Fleet {fleetId} {orderType} completed"

  res_types.GameEvent(
    eventType: res_types.GameEventType.OrderCompleted,
    houseId: houseId,
    description: desc,
    systemId: systemId
  )
