## Combat Assault Order Execution
##
## This module contains the logic for executing 'Bombard', 'Invade', and 'Blitz' fleet orders.

import std/[options, tables, strformat]
import ../../../../common/types/[core, units]
import ../../gamestate, ../../fleet, ../../logger, ../../starmap
import ../../index_maintenance
import ../../types/resolution as resolution_types
import ../../events/init as event_factory
import ../main as orders # For FleetOrder and FleetOrderType

proc executeBombardOrder*(
  state: var GameState,
  fleet: Fleet,
  order: orders.FleetOrder,
  events: var seq[resolution_types.GameEvent]
): OrderOutcome =
  ## Order 06: Orbital bombardment of planet
  ## Resolved in Conflict Phase - this marks intent

  if order.targetSystem.isNone:
    return OrderOutcome.Failed

  let targetSystem = order.targetSystem.get()

  # Check target colony exists
  if targetSystem notin state.colonies:
    return OrderOutcome.Failed

  let colony = state.colonies[targetSystem]
  if colony.owner == fleet.owner:
    return OrderOutcome.Failed

  # Validate target house is not eliminated (leaderboard is public info)
  if colony.owner in state.houses:
    let targetHouse = state.houses[colony.owner]
    if targetHouse.eliminated:
      return OrderOutcome.Failed

  # Check for combat capability
  var hasCombatShips = false
  for squadron in fleet.squadrons:
    if squadron.flagship.stats.attackStrength > 0:
      hasCombatShips = true
      break

  if not hasCombatShips:
    return OrderOutcome.Failed

  return OrderOutcome.Success

proc executeInvadeOrder*(
  state: var GameState,
  fleet: Fleet,
  order: orders.FleetOrder,
  events: var seq[resolution_types.GameEvent]
): OrderOutcome =
  ## Order 07: Three-round planetary invasion
  ## 1) Destroy ground batteries
  ## 2) Pound population/ground troops
  ## 3) Land Marines (if batteries destroyed)

  if order.targetSystem.isNone:
    return OrderOutcome.Failed

  let targetSystem = order.targetSystem.get()

  # Check target colony exists
  if targetSystem notin state.colonies:
    return OrderOutcome.Failed

  let colony = state.colonies[targetSystem]
  if colony.owner == fleet.owner:
    return OrderOutcome.Failed

  # Validate target house is not eliminated (leaderboard is public info)
  if colony.owner in state.houses:
    let targetHouse = state.houses[colony.owner]
    if targetHouse.eliminated:
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
      if squadron.flagship.shipClass == ShipClass.TroopTransport and
         squadron.flagship.cargo.isSome:
        let cargo = squadron.flagship.cargo.get()
        if cargo.cargoType == CargoType.Marines and
           cargo.quantity > 0:
          hasLoadedTransports = true
          break

  if not hasCombatShips:
    return OrderOutcome.Failed

  if not hasLoadedTransports:
    return OrderOutcome.Failed

  return OrderOutcome.Success

proc executeBlitzOrder*(
  state: var GameState,
  fleet: Fleet,
  order: orders.FleetOrder,
  events: var seq[resolution_types.GameEvent]
): OrderOutcome =
  ## Order 08: Fast assault - dodge batteries, drop Marines
  ## Less planet damage, but requires 2:1 Marine superiority
  ## Per operations.md:6.2.9

  if order.targetSystem.isNone:
    return OrderOutcome.Failed

  let targetSystem = order.targetSystem.get()

  # Check target colony exists
  if targetSystem notin state.colonies:
    return OrderOutcome.Failed

  let colony = state.colonies[targetSystem]
  if colony.owner == fleet.owner:
    return OrderOutcome.Failed

  # Validate target house is not eliminated (leaderboard is public info)
  if colony.owner in state.houses:
    let targetHouse = state.houses[colony.owner]
    if targetHouse.eliminated:
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
    return OrderOutcome.Failed

  return OrderOutcome.Success
