## Guard Starbase Order Execution
##
## This module contains the logic for executing the 'Guard Starbase' fleet order,
## which commands a fleet to protect an orbiting starbase.

import std/[options, tables, strformat]
import ../../../../common/types/[core, units]
import ../../gamestate, ../../fleet, ../../logger, ../../starmap
import ../../index_maintenance
import ../../types/resolution as resolution_types
import ../../events/init as event_factory
import ../main as orders # For FleetOrder and FleetOrderType
import ../../types/diplomacy as dip_types # For DiplomaticState

proc executeGuardStarbaseOrder*(
  state: var GameState,
  fleet: Fleet,
  order: orders.FleetOrder,
  events: var seq[resolution_types.GameEvent]
): OrderOutcome =
  ## Order 04: Protect starbase, join Task Force when confronted
  ## Requires combat ships
  ## Persistent order - silent re-execution

  if order.targetSystem.isNone:
    events.add(event_factory.orderFailed(
      fleet.owner,
      fleet.id,
      "GuardStarbase",
      reason = "no target system specified",
      systemId = some(fleet.location)
    ))
    return OrderOutcome.Failed

  # Check for combat capability
  var hasCombatShips = false
  for squadron in fleet.squadrons:
    if squadron.flagship.stats.attackStrength > 0:
      hasCombatShips = true
      break

  if not hasCombatShips:
    events.add(event_factory.orderFailed(
      fleet.owner,
      fleet.id,
      "GuardStarbase",
      reason = "no combat-capable ships",
      systemId = some(fleet.location)
    ))
    return OrderOutcome.Failed

  let targetSystem = order.targetSystem.get()
  let houseId = fleet.owner

  # Validate starbase presence and ownership
  if targetSystem notin state.colonies:
    events.add(event_factory.orderAborted(
      houseId,
      fleet.id,
      "GuardStarbase",
      reason = "target system has no colony",
      systemId = some(targetSystem)
    ))
    return OrderOutcome.Aborted

  let colony = state.colonies[targetSystem]
  if colony.owner != houseId:
    events.add(event_factory.orderAborted(
      houseId,
      fleet.id,
      "GuardStarbase",
      reason = "colony no longer friendly",
      systemId = some(targetSystem)
    ))
    return OrderOutcome.Aborted

  if colony.starbases.len == 0:
    events.add(event_factory.orderAborted(
      houseId,
      fleet.id,
      "GuardStarbase",
      reason = "starbase destroyed",
      systemId = some(targetSystem)
    ))
    return OrderOutcome.Aborted

  # Persistent order - stays active, silent re-execution
  return OrderOutcome.Success
