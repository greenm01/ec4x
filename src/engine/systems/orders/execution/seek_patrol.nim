## Seek Home and Patrol Order Execution
##
## This module contains the logic for executing 'Seek Home' and 'Patrol' fleet orders.

import std/[options, tables, strformat, algorithm, sets]
import ../../../../common/types/[core, units]
import ../../gamestate, ../../fleet, ../../logger, ../../starmap
import ../../index_maintenance
import ../../types/resolution as resolution_types
import ../../events/init as event_factory
import ../../standing_orders
import ../main as orders # For FleetOrder and FleetOrderType

proc executeSeekHomeOrder*(
  state: var GameState,
  fleet: Fleet,
  order: orders.FleetOrder,
  events: var seq[resolution_types.GameEvent]
): OrderOutcome =
  ## Order 02: Find closest friendly colony and move there
  ## If that colony is conquered, find next closest

  # Find all friendly colonies
  var friendlyColonies: seq[SystemId] = @[]
  if fleet.owner in state.coloniesByOwner:
    friendlyColonies = state.coloniesByOwner[fleet.owner]

  if friendlyColonies.len == 0:
    # No friendly colonies - abort mission
    events.add(event_factory.orderAborted(
      fleet.owner,
      fleet.id,
      "SeekHome",
      reason = "no friendly colonies available",
      systemId = some(fleet.location)
    ))
    return OrderOutcome.Aborted

  # Find closest colony using pathfinding
  var closestColony = friendlyColonies[0]
  var minDistance = int.high

  for colonyId in friendlyColonies:
    let pathResult = state.starMap.findPath(fleet.location, colonyId, fleet)
    if pathResult.found:
      let distance = pathResult.path.len - 1
      if distance < minDistance:
        minDistance = distance
        closestColony = colonyId

  # Check if already at closest colony - mission complete
  if fleet.location == closestColony:
    events.add(event_factory.orderCompleted(
      fleet.owner,
      fleet.id,
      "SeekHome",
      details = &"reached home at {closestColony}",
      systemId = some(closestColony)
    ))
    return OrderOutcome.Success

  # Create movement order to closest colony
  let moveOrder = orders.FleetOrder(
    fleetId: fleet.id,
    orderType: orders.FleetOrderType.Move,
    targetSystem: some(closestColony),
    targetFleet: none(FleetId),
    priority: order.priority
  )

  # Execute movement (delegated to fleet_orders.resolveMovementOrder)
  var moveEvents: seq[resolution_types.GameEvent] = @[]
  # fleet_orders.resolveMovementOrder(state, fleet.owner, moveOrder, moveEvents)
  # TODO: Re-introduce call to resolveMovementOrder after it's been refactored
  events.add(moveEvents)

  return OrderOutcome.Success

proc executePatrolOrder*(
  state: var GameState,
  fleet: Fleet,
  order: orders.FleetOrder,
  events: var seq[resolution_types.GameEvent]
): OrderOutcome =
  ## Order 03: Actively patrol system, engaging hostile forces
  ## Engagement rules per operations.md:6.2.4
  ## Persistent order - silent re-execution (only generates event on first execution)

  if order.targetSystem.isNone:
    events.add(event_factory.orderFailed(
      fleet.owner,
      fleet.id,
      "Patrol",
      reason = "no target system specified",
      systemId = some(fleet.location)
    ))
    return OrderOutcome.Failed

  let targetSystem = order.targetSystem.get()

  # Check if target system lost (conquered by enemy)
  if targetSystem in state.colonies:
    let colony = state.colonies[targetSystem]
    if colony.owner != fleet.owner:
      events.add(event_factory.orderAborted(
        fleet.owner,
        fleet.id,
        "Patrol",
        reason = "target system no longer friendly",
        systemId = some(targetSystem)
      ))
      return OrderOutcome.Aborted

  # Persistent order - stays active, combat happens in Conflict Phase
  # Silent - no OrderCompleted spam (would generate every turn)
  return OrderOutcome.Success
