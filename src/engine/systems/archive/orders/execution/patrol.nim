## Patrol Order Execution
##
## This module contains the logic for executing the 'Patrol' fleet order,
## which commands a fleet to actively patrol a system.

import std/[options, tables, strformat]
import ../../../../common/types/[core, units]
import ../../gamestate, ../../fleet, ../../logger, ../../starmap
import ../../index_maintenance
import ../../types/resolution as resolution_types
import ../../events/init as event_factory
import ../../standing_orders
import ../../main as orders # For FleetOrder and FleetOrderType
import ../utils/movement_intelligence_utils # For isSystemHostile

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
  let houseId = fleet.owner

  # Check if target system lost (conquered by enemy)
  if targetSystem in state.colonies:
    let colony = state.colonies[targetSystem]
    if colony.owner != houseId:
      events.add(event_factory.orderAborted(
        houseId,
        fleet.id,
        "Patrol",
        reason = "target system no longer friendly",
        systemId = some(targetSystem)
      ))
      return OrderOutcome.Aborted

  # Persistent order - stays active, combat happens in Conflict Phase
  # Silent - no OrderCompleted spam (would generate every turn)
  return OrderOutcome.Success
