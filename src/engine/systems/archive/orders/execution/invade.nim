## Invade Order Execution
##
## This module contains the logic for executing the 'Invade' fleet order,
## which initiates a planetary invasion operation.

import std/[options, tables, strformat]
import ../../../../common/types/[core, units]
import ../../gamestate, ../../fleet, ../../logger
import ../../types/resolution as resolution_types
import ../../events/init as event_factory
import ../main as orders # For FleetOrder and FleetOrderType

proc executeInvadeOrder*(
  state: var GameState,
  fleet: Fleet,
  order: orders.FleetOrder,
  events: var seq[resolution_types.GameEvent]
): OrderOutcome =
  ## Order 08: Three-round planetary invasion
  ## 1) Destroy ground batteries
  ## 2) Pound population/ground troops
  ## 3) Land Marines (if batteries destroyed)

  if order.targetSystem.isNone:
    return OrderOutcome.Failed

  let targetSystem = order.targetSystem.get()
  let houseId = fleet.owner

  # Check target colony exists
  if targetSystem notin state.colonies:
    events.add(event_factory.orderFailed(
      houseId,
      fleet.id,
      "Invade",
      reason = "target system has no colony",
      systemId = some(targetSystem)
    ))
    return OrderOutcome.Failed

  let colony = state.colonies[targetSystem]
  if colony.owner == houseId:
    events.add(event_factory.orderFailed(
      houseId,
      fleet.id,
      "Invade",
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
        "Invade",
        reason = "target house is eliminated",
        systemId = some(targetSystem)
      ))
      return OrderOutcome.Failed

  # Check for combat ships and loaded troop transports
  var hasCombatShips = false
  var hasLoadedTransports = false

  for squadron in fleet.squadrons:
    if squadron.flagship.stats.attackStrength > 0:
      hasCombatShips = true

  # Check Auxiliary squadrons for loaded marines
  for squadron in fleet.squadrons:
    if squadron.squadronType == SquadronType.Auxiliary:
      if squadron.flagship.shipClass == ShipClass.TroopTransport and \
         squadron.flagship.cargo.isSome:
        let cargo = squadron.flagship.cargo.get()
        if cargo.cargoType == CargoType.Marines and \
           cargo.quantity > 0:
          hasLoadedTransports = true
          break

  if not hasCombatShips:
    events.add(event_factory.orderFailed(
      houseId,
      fleet.id,
      "Invade",
      reason = "fleet has no combat ships",
      systemId = some(targetSystem)
    ))
    return OrderOutcome.Failed

  if not hasLoadedTransports:
    events.add(event_factory.orderFailed(
      houseId,
      fleet.id,
      "Invade",
      reason = "fleet has no loaded troop transports",
      systemId = some(targetSystem)
    ))
    return OrderOutcome.Failed

  return OrderOutcome.Success
