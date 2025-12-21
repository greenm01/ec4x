## Blitz Order Execution
##
## This module contains the logic for executing the 'Blitz' fleet order,
## which initiates a rapid planetary assault combining bombardment and invasion.

import std/[options, tables, strformat]
import ../../../../common/types/[core, units]
import ../../gamestate, ../../fleet, ../../logger
import ../../types/resolution as resolution_types
import ../../events/init as event_factory
import ../main as orders # For FleetOrder and FleetOrderType

proc executeBlitzOrder*(
  state: var GameState,
  fleet: Fleet,
  order: orders.FleetOrder,
  events: var seq[resolution_types.GameEvent]
): OrderOutcome =
  ## Order 09: Fast assault - dodge batteries, drop Marines
  ## Less planet damage, but requires 2:1 Marine superiority
  ## Per operations.md:6.2.9

  if order.targetSystem.isNone:
    return OrderOutcome.Failed

  let targetSystem = order.targetSystem.get()
  let houseId = fleet.owner

  # Check target colony exists
  if targetSystem notin state.colonies:
    events.add(event_factory.orderFailed(
      houseId,
      fleet.id,
      "Blitz",
      reason = "target system has no colony",
      systemId = some(targetSystem)
    ))
    return OrderOutcome.Failed

  let colony = state.colonies[targetSystem]
  if colony.owner == houseId:
    events.add(event_factory.orderFailed(
      houseId,
      fleet.id,
      "Blitz",
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
        "Blitz",
        reason = "target house is eliminated",
        systemId = some(targetSystem)
      ))
      return OrderOutcome.Failed

  # Check for loaded troop transports (Auxiliary squadrons)
  var hasLoadedTransports = false

  for squadron in fleet.squadrons:
    if squadron.squadronType == SquadronType.Auxiliary:
      if squadron.flagship.shipClass == ShipClass.TroopTransport:
        # Check if transport has Marines loaded
        if squadron.flagship.cargo.isSome:
          let cargo = squadron.flagship.cargo.get()
          if cargo.cargoType == CargoType.Marines and cargo.quantity > 0:
            hasLoadedTransports = true
            break

  if not hasLoadedTransports:
    events.add(event_factory.orderFailed(
      houseId,
      fleet.id,
      "Blitz",
      reason = "fleet has no loaded troop transports",
      systemId = some(targetSystem)
    ))
    return OrderOutcome.Failed

  return OrderOutcome.Success
