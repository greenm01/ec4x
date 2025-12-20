## Reconnaissance Order Execution
##
## This module contains the logic for executing 'View World' fleet orders.

import std/[options, tables, strformat]
import ../../../../common/types/[core, units]
import ../../gamestate, ../../fleet, ../../logger, ../../starmap
import ../../index_maintenance
import ../../types/resolution as resolution_types
import ../../events/init as event_factory
import ../main as orders # For FleetOrder and FleetOrderType

proc executeViewWorldOrder*(
  state: var GameState,
  fleet: Fleet,
  order: orders.FleetOrder,
  events: var seq[resolution_types.GameEvent]
): OrderOutcome =
  ## Order 19: Perform long-range scan of planet from system edge
  ## Gathers: planet owner (if colonized) + planet class (production potential)
  ## Resolution logic handled by resolveViewWorldOrder in fleet_orders.nim

  if order.targetSystem.isNone:
    events.add(event_factory.orderFailed(
      fleet.owner,
      fleet.id,
      "ViewWorld",
      reason = "no target system specified",
      systemId = some(fleet.location)
    ))
    return OrderOutcome.Failed

  return OrderOutcome.Success
