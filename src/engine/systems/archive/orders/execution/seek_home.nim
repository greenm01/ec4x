## Seek Home Order Execution
##
## This module contains the logic for executing the 'Seek Home' fleet order,
## which directs a fleet to return to the nearest friendly colony.

import std/[options, tables, strformat, algorithm, sets]
import ../../../../common/types/[core, units]
import ../../gamestate, ../../fleet, ../../logger, ../../starmap
import ../../index_maintenance
import ../../types/resolution as resolution_types
import ../../events/init as event_factory
import ../../standing_orders
import ../../main as orders # For FleetOrder and FleetOrderType
import ../utils/movement_intelligence_utils # For findClosestOwnedColony

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

  # Find closest colony using pathfinding (using helper from utils)
  let closestColonyOpt = movement_intelligence_utils.findClosestOwnedColony(state, fleet.location, fleet.owner)

  if closestColonyOpt.isNone:
    events.add(event_factory.orderAborted(
      fleet.owner,
      fleet.id,
      "SeekHome",
      reason = "could not find a safe home colony",
      systemId = some(fleet.location)
    ))
    return OrderOutcome.Aborted

  let closestColony = closestColonyOpt.get()

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

  # Execute movement (delegated to fleet_order_executor which calls move.nim)
  # The dispatcher will pick up this new Move order next turn or immediately if priority allows
  # For now, just return success if the move order is successfully issued.
  state.fleetOrders[fleet.id] = moveOrder
  return OrderOutcome.Success
