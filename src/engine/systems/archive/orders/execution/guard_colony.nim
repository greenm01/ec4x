## Guard Colony Order Execution
##
## This module contains the logic for executing the 'Guard Colony' fleet order,
## which commands a fleet to protect a friendly colony.

import std/[options, tables, strformat]
import ../../../../common/types/[core, units]
import ../../gamestate, ../../fleet, ../../logger, ../../starmap
import ../../index_maintenance
import ../../types/resolution as resolution_types
import ../../events/init as event_factory
import ../main as orders # For FleetOrder and FleetOrderType
import ../../types/diplomacy as dip_types # For DiplomaticState

proc executeGuardColonyOrder*(
  state: var GameState,
  fleet: Fleet,
  order: orders.FleetOrder,
  events: var seq[resolution_types.GameEvent]
): OrderOutcome =
  ## Order 05 (Guard): Protect friendly colony, rear guard position
  ## Does not auto-join starbase Task Force (allows Raiders)
  ## Persistent order - silent re-execution

  if order.targetSystem.isNone:
    events.add(event_factory.orderFailed(
      fleet.owner,
      fleet.id,
      "GuardColony",
      reason = "no target system specified",
      systemId = some(fleet.location)
    ))
    return OrderOutcome.Failed

  let targetSystem = order.targetSystem.get()
  let houseId = fleet.owner

  # Check for combat capability
  var hasCombatShips = false
  for squadron in fleet.squadrons:
    if squadron.flagship.stats.attackStrength > 0:
      hasCombatShips = true
      break

  if not hasCombatShips:
    events.add(event_factory.orderFailed(
      houseId,
      fleet.id,
      "GuardColony",
      reason = "no combat-capable ships",
      systemId = some(fleet.location)
    ))
    return OrderOutcome.Failed

  # Check target colony still exists and is friendly
  if targetSystem in state.colonies:
    let colony = state.colonies[targetSystem]
    if colony.owner != houseId:
      events.add(event_factory.orderAborted(
        houseId,
        fleet.id,
        "GuardColony",
        reason = "colony no longer friendly",
        systemId = some(targetSystem)
      ))
      return OrderOutcome.Aborted
  else:
    events.add(event_factory.orderAborted(
      houseId,
      fleet.id,
      "GuardColony",
      reason = "target system has no colony",
      systemId = some(targetSystem)
    ))
    return OrderOutcome.Aborted

  # Persistent order - stays active, silent re-execution
  return OrderOutcome.Success
