## Blockade Colony Order Execution
##
## This module contains the logic for executing the 'Blockade Colony' fleet order,
## which commands a fleet to blockade an enemy planet, reducing its GCO.

import std/[options, tables, strformat]
import ../../../../common/types/[core, units]
import ../../gamestate, ../../fleet, ../../logger, ../../starmap
import ../../index_maintenance
import ../../types/resolution as resolution_types
import ../../events/init as event_factory
import ../main as orders # For FleetOrder and FleetOrderType
import ../../types/diplomacy as dip_types # For DiplomaticState

proc executeBlockadeColonyOrder*(
  state: var GameState,
  fleet: Fleet,
  order: orders.FleetOrder,
  events: var seq[resolution_types.GameEvent]
): OrderOutcome =
  ## Order 06 (Blockade): Block enemy planet, reduce GCO by 60%
  ## Per operations.md:6.2.6 - Immediate effect during Income Phase
  ## Prestige penalty: -2 per turn if colony under blockade
  ## Persistent order - silent re-execution

  if order.targetSystem.isNone:
    events.add(event_factory.orderFailed(
      fleet.owner,
      fleet.id,
      "BlockadeColony",
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
      "BlockadeColony",
      reason = "no combat-capable ships",
      systemId = some(fleet.location)
    ))
    return OrderOutcome.Failed

  # Check target colony exists and is hostile
  if targetSystem notin state.colonies:
    events.add(event_factory.orderAborted(
      houseId,
      fleet.id,
      "BlockadeColony",
      reason = "target system has no colony",
      systemId = some(targetSystem)
    ))
    return OrderOutcome.Aborted

  let colony = state.colonies[targetSystem]
  if colony.owner == houseId:
    events.add(event_factory.orderAborted(
      houseId,
      fleet.id,
      "BlockadeColony",
      reason = "cannot blockade own colony",
      systemId = some(targetSystem)
    ))
    return OrderOutcome.Aborted

  # Validate target house is not eliminated (leaderboard is public info)
  if colony.owner in state.houses:
    let targetHouse = state.houses[colony.owner]
    if targetHouse.eliminated:
      events.add(event_factory.orderAborted(
        houseId,
        fleet.id,
        "BlockadeColony",
        reason = "target house eliminated",
        systemId = some(targetSystem)
      ))
      return OrderOutcome.Aborted

  # NOTE: Blockade tracking not yet implemented in Colony type
  # Blockade effects are calculated dynamically during Income Phase by checking
  # for BlockadePlanet fleet orders at colony systems (see income.nim)
  # Future enhancement: Add blockaded: bool field to Colony type for faster lookups

  # Persistent order - stays active, silent re-execution
  return OrderOutcome.Success
