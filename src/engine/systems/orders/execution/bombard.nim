## Bombard Order Execution
##
## This module contains the logic for executing the 'Bombard' fleet order,
## which initiates orbital bombardment of an enemy colony.

import std/[options, tables, strformat]
import ../../../../common/types/[core, units]
import ../../gamestate, ../../fleet, ../../logger
import ../../types/resolution as resolution_types
import ../../events/init as event_factory
import ../main as orders # For FleetOrder and FleetOrderType

proc executeBombardOrder*(
  state: var GameState,
  fleet: Fleet,
  order: orders.FleetOrder,
  events: var seq[resolution_types.GameEvent]
): OrderOutcome =
  ## Order 07: Orbital bombardment of planet
  ## Resolved in Conflict Phase - this marks intent

  if order.targetSystem.isNone:
    return OrderOutcome.Failed

  let targetSystem = order.targetSystem.get()
  let houseId = fleet.owner

  # Check target colony exists
  if targetSystem notin state.colonies:
    events.add(event_factory.orderFailed(
      houseId,
      fleet.id,
      "Bombard",
      reason = "target system has no colony",
      systemId = some(targetSystem)
    ))
    return OrderOutcome.Failed

  let colony = state.colonies[targetSystem]
  if colony.owner == houseId:
    events.add(event_factory.orderFailed(
      houseId,
      fleet.id,
      "Bombard",
      reason = "target colony is owned by us",
      systemId = some(targetSystem)
    ))
    return OrderOutcome.Failed

  # Validate target house is not eliminated (leaderboard is public info)
  if colony.owner in state.houses:
    let targetHouse = state.houses[colony.owner]
    if targetHouse.eliminated:
      events.add(event_factory.orderFailed(
        houseId,
        fleet.id,
        "Bombard",
        reason = "target house is eliminated",
        systemId = some(targetSystem)
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
      houseId,
      fleet.id,
      "Bombard",
      reason = "fleet has no combat ships",
      systemId = some(targetSystem)
    ))
    return OrderOutcome.Failed

  return OrderOutcome.Success
