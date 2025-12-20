## Salvage Order Execution
##
## This module contains the logic for executing the 'Salvage' fleet order,
## which recovers resources from destroyed ships and derelict facilities.

import std/[options, tables, strformat, algorithm]
import ../../../../common/types/[core, units]
import ../../gamestate, ../../fleet, ../../logger, ../../starmap
import ../../index_maintenance
import ../../types/resolution as resolution_types
import ../../events/init as event_factory
import ../../standing_orders
import ../main as orders # For FleetOrder and FleetOrderType

proc executeSalvageOrder*(
  state: var GameState,
  fleet: Fleet,
  order: orders.FleetOrder,
  events: var seq[resolution_types.GameEvent]
): OrderOutcome =
  ## Order 15: Salvage fleet at closest friendly colony with spaceport or shipyard
  ## Fleet disbands, ships salvaged for 50% PC
  ## Per operations.md:6.2.16
  ##
  ## AUTOMATIC EXECUTION: This order executes immediately when given
  ## FACILITIES: Works at colonies with either spaceport OR shipyard

  # Find closest friendly colony with salvage facilities (spaceport or shipyard)
  var closestColony: Option[SystemId] = none(SystemId)

  # Check if fleet is currently at a friendly colony with facilities
  if fleet.location in state.colonies:
    let colony = state.colonies[fleet.location]
    let hasFacilities = colony.spaceports.len > 0 or colony.shipyards.len > 0

    if colony.owner == fleet.owner and hasFacilities:
      # Already at a suitable colony - use it immediately
      closestColony = some(fleet.location)

  # If not at suitable colony, search all owned colonies for one with facilities
  # Note: For simplicity, we take the first colony with facilities found
  # A more sophisticated implementation would use pathfinding to find truly closest
  # Use coloniesByOwner index for O(1) lookup instead of O(F) scan
  if closestColony.isNone:
    if fleet.owner in state.coloniesByOwner:
      for colonyId in state.coloniesByOwner[fleet.owner]:
        if colonyId in state.colonies:
          let colony = state.colonies[colonyId]
          # Check if colony has salvage facilities
          let hasFacilities = colony.spaceports.len > 0 or colony.shipyards.len > 0

          if hasFacilities:
            closestColony = some(colonyId)
            break

  if closestColony.isNone:
    events.add(event_factory.orderFailed(
      fleet.owner,
      fleet.id,
      "Salvage",
      reason = "no friendly colonies with salvage facilities (spaceport or shipyard)",
      systemId = some(fleet.location)
    ))
    return OrderOutcome.Failed

  # Calculate salvage value (50% of ship PC per operations.md:6.2.16)
  var salvageValue = 0
  for squadron in fleet.squadrons:
    # Flagship
    salvageValue += (squadron.flagship.stats.buildCost div 2)
    # Other ships in squadron
    for ship in squadron.ships:
      salvageValue += (ship.stats.buildCost div 2)

  # Add salvage PP to house treasury
  state.withHouse(fleet.owner):
    house.treasury += salvageValue

  # Generate event
  let targetSystem = closestColony.get()
  let transitMessage = if fleet.location == targetSystem:
    "at colony"
  else:
    "after transit to " & $targetSystem

  # Remove fleet from game state
  state.removeFleetFromIndices(fleet.id, fleet.owner, fleet.location)
  state.fleets.del(fleet.id)
  if fleet.id in state.fleetOrders:
    state.fleetOrders.del(fleet.id)
  if fleet.id in state.standingOrders:
    state.standingOrders.del(fleet.id)

  # Generate OrderCompleted event for salvage operation
  events.add(event_factory.orderCompleted(
    fleet.owner,
    fleet.id,
    "Salvage",
    details = &"recovered {salvageValue} PP from {fleet.squadrons.len} squadron(s)",
    systemId = some(targetSystem)
  ))

  return OrderOutcome.Success
