## Order Event Factory
## Events for order validation and rejection
##
## DRY Principle: Single source of truth for order event creation
## DoD Principle: Data (GameEvent) separated from creation logic

import std/[options, strformat]
import ../../../common/types/core
import ../../../engine/order_types # For FleetOrderType
import ../types as event_types # Renamed alias to avoid confusion with res_types.GameEvent in engine/resolution

# Export the new event_types alias explicitly
export event_types

proc orderRejected*(
  houseId: HouseId,
  orderType: string, # This should be FleetOrderType, but matching existing for now
  reason: string,
  systemId: Option[SystemId] = none(SystemId),
  fleetId: Option[FleetId] = none(FleetId) # Added fleetId
): event_types.GameEvent =
  ## Create event for rejected order (validation failure)
  event_types.GameEvent(
    kind: event_types.GameEventKind.OrderRejected,
    turn: 0, # Will be set by event dispatcher
    houseId: some(houseId),
    systemId: systemId,
    description: &"{orderType} order rejected: {reason}",
    fleetId: fleetId,
    orderType: orderType,
    reason: some(reason)
  )

proc orderFailed*(
  houseId: HouseId,
  fleetId: FleetId,
  orderType: string, # This should be FleetOrderType
  reason: string,
  systemId: Option[SystemId] = none(SystemId)
): event_types.GameEvent =
  ## Order execution failed (validation failure at execution time)
  event_types.GameEvent(
    kind: event_types.GameEventKind.OrderFailed,
    turn: 0, # Will be set by event dispatcher
    houseId: some(houseId),
    systemId: systemId,
    description: &"Fleet {fleetId} {orderType} failed: {reason}",
    fleetId: some(fleetId),
    orderType: orderType,
    reason: some(reason)
  )

proc orderAborted*(
  houseId: HouseId,
  fleetId: FleetId,
  orderType: string, # This should be FleetOrderType
  reason: string,
  systemId: Option[SystemId] = none(SystemId)
): event_types.GameEvent =
  ## Order cancelled/aborted (target lost, conditions changed)
  event_types.GameEvent(
    kind: event_types.GameEventKind.OrderAborted,
    turn: 0, # Will be set by event dispatcher
    houseId: some(houseId),
    systemId: systemId,
    description: &"Fleet {fleetId} {orderType} aborted: {reason}",
    fleetId: some(fleetId),
    orderType: orderType,
    reason: some(reason)
  )

proc orderIssued*(
  houseId: HouseId,
  fleetId: FleetId,
  orderType: string, # This should be FleetOrderType
  systemId: Option[SystemId] = none(SystemId)
): event_types.GameEvent =
  ## Order submitted and added to fleet orders queue
  event_types.GameEvent(
    kind: event_types.GameEventKind.OrderIssued,
    turn: 0, # Will be set by event dispatcher
    houseId: some(houseId),
    systemId: systemId,
    description: &"Fleet {fleetId}: Order issued - {orderType}",
    fleetId: some(fleetId),
    orderType: orderType
  )

proc orderCompleted*(
  houseId: HouseId,
  fleetId: FleetId,
  orderType: string, # This should be FleetOrderType
  details: string = "",
  systemId: Option[SystemId] = none(SystemId)
): event_types.GameEvent =
  ## Order successfully completed (state change or one-shot operation)
  let desc = if details.len > 0:
    &"Fleet {fleetId} {orderType} completed: {details}"
  else:
    &"Fleet {fleetId} {orderType} completed"

  event_types.GameEvent(
    kind: event_types.GameEventKind.OrderCompleted,
    turn: 0, # Will be set by event dispatcher
    houseId: some(houseId),
    systemId: systemId,
    description: desc,
    fleetId: some(fleetId),
    orderType: orderType,
    details: some(details)
  )
