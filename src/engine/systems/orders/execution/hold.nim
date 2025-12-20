## Hold Order Execution
##
## This module contains the logic for executing the 'Hold' fleet order,
## which commands a fleet to maintain its current position.

import std/[options, tables, strformat]
import ../../../../common/types/[core, units]
import ../../gamestate, ../../fleet, ../../logger
import ../../types/resolution as resolution_types
import ../../events/init as event_factory
import ../main as orders # For FleetOrder and FleetOrderType

proc executeHoldOrder*(
  state: var GameState,
  fleet: Fleet,
  order: orders.FleetOrder,
  events: var seq[resolution_types.GameEvent]
): OrderOutcome =
  ## Order 00: Hold position at current system
  ## Persistent order - no OrderCompleted event spam

  logDebug(LogCategory.lcFleet, &"Fleet {fleet.id} holding position at {fleet.location}")
  return OrderOutcome.Success