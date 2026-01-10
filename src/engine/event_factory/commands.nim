## Command Event Factory
## Events for fleet command execution, validation, and rejection
##
## DRY Principle: Single source of truth for command event creation
## DoD Principle: Data (GameEvent) separated from creation logic

import std/[options, strformat]
import ../types/[core, event]

# Export the new event_types alias explicitly
export event

proc orderRejected*(
    houseId: HouseId,
    orderType: string, # This should be FleetCommandType, but matching existing for now
    reason: string,
    systemId: Option[SystemId] = none(SystemId),
    fleetId: Option[FleetId] = none(FleetId), # Added fleetId
): event.GameEvent =
  ## Create event for rejected command (validation failure)
  event.GameEvent(
    eventType: event.GameEventType.CommandRejected,
    houseId: some(houseId),
    systemId: systemId,
    description: &"{orderType} command rejected: {reason}",
    fleetId: fleetId,
    orderType: some(orderType),
    reason: some(reason),
  )

proc commandFailed*(
    houseId: HouseId,
    fleetId: FleetId,
    orderType: string, # This should be FleetCommandType
    reason: string,
    systemId: Option[SystemId] = none(SystemId),
): event.GameEvent =
  ## Order execution failed (validation failure at execution time)
  event.GameEvent(
    eventType: event.GameEventType.CommandFailed,
    houseId: some(houseId),
    systemId: systemId,
    description: &"Fleet {fleetId} {orderType} failed: {reason}",
    fleetId: some(fleetId),
    orderType: some(orderType),
    reason: some(reason),
  )

proc commandAborted*(
    houseId: HouseId,
    fleetId: FleetId,
    orderType: string, # This should be FleetCommandType
    reason: string,
    systemId: Option[SystemId] = none(SystemId),
): event.GameEvent =
  ## Order cancelled/aborted (target lost, conditions changed)
  event.GameEvent(
    eventType: event.GameEventType.CommandAborted,
    houseId: some(houseId),
    systemId: systemId,
    description: &"Fleet {fleetId} {orderType} aborted: {reason}",
    fleetId: some(fleetId),
    orderType: some(orderType),
    reason: some(reason),
  )

proc commandIssued*(
    houseId: HouseId,
    fleetId: FleetId,
    orderType: string, # This should be FleetCommandType
    systemId: Option[SystemId] = none(SystemId),
): event.GameEvent =
  ## Order submitted and added to fleet commands queue
  event.GameEvent(
    eventType: event.GameEventType.CommandIssued,
    houseId: some(houseId),
    systemId: systemId,
    description: &"Fleet {fleetId}: Command issued - {orderType}",
    fleetId: some(fleetId),
    orderType: some(orderType),
  )

proc commandCompleted*(
    houseId: HouseId,
    fleetId: FleetId,
    orderType: string, # This should be FleetCommandType
    details: string = "",
    systemId: Option[SystemId] = none(SystemId),
): event.GameEvent =
  ## Order successfully completed (state change or one-shot operation)
  let desc =
    if details.len > 0:
      &"Fleet {fleetId} {orderType} completed: {details}"
    else:
      &"Fleet {fleetId} {orderType} completed"

  event.GameEvent(
    eventType: event.GameEventType.CommandCompleted,
    houseId: some(houseId),
    systemId: systemId,
    description: desc,
    fleetId: some(fleetId),
    orderType: some(orderType),
    details: some(details),
  )

proc fleetArrived*(
    houseId: HouseId, fleetId: FleetId, orderType: string, systemId: SystemId
): event.GameEvent =
  ## Fleet arrived at command target system (ready for command execution)
  ## Generated in Maintenance Phase, checked in Conflict/Income phase
  event.GameEvent(
    eventType: event.GameEventType.FleetArrived,
    houseId: some(houseId),
    systemId: some(systemId),
    description: &"Fleet {fleetId} arrived at {systemId} ({orderType} ready)",
    fleetId: some(fleetId),
    orderType: some(orderType),
  )
