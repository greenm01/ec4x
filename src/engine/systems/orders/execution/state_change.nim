## State Change Order Execution
##
## This module contains the logic for executing 'Reserve', 'Mothball',
## and 'Reactivate' fleet orders.

import std/[options, tables, strformat, algorithm, sets]
import ../../../../common/types/[core, units]
import ../../gamestate, ../../fleet, ../../logger, ../../starmap
import ../../index_maintenance
import ../../types/resolution as resolution_types
import ../../events/init as event_factory
import ../../standing_orders
import ../main as orders # For FleetOrder and FleetOrderType

proc executeReserveOrder*(
  state: var GameState,
  fleet: Fleet,
  order: orders.FleetOrder,
  events: var seq[resolution_types.GameEvent]
): OrderOutcome =
  ## Place fleet on Reserve status (50% maintenance, half AS/DS, can't move)
  ## Per economy.md:3.9
  ## If not at friendly colony, auto-seeks nearest friendly colony first

  # Check if already at a friendly colony
  var atFriendlyColony = false
  if fleet.location in state.colonies:
    let colony = state.colonies[fleet.location]
    if colony.owner == fleet.owner:
      atFriendlyColony = true

  # If not at friendly colony, find closest one and move there
  if not atFriendlyColony:
    # Find all friendly colonies
    var friendlyColonies: seq[SystemId] = @[]
    for colonyId, colony in state.colonies:
      if colony.owner == fleet.owner:
        friendlyColonies.add(colonyId)

    if friendlyColonies.len == 0:
      return OrderOutcome.Failed

    # Find closest colony using pathfinding
    var closestColony = friendlyColonies[0]
    var minDistance = int.high

    for colonyId in friendlyColonies:
      let pathResult = state.starMap.findPath(fleet.location, colonyId, fleet)
      if pathResult.found:
        let distance = pathResult.path.len - 1
        if distance < minDistance:
          minDistance = distance
          closestColony = colonyId

    # Not at colony yet - move toward it
    if fleet.location != closestColony:
      # Create movement order to target colony
      let moveOrder = orders.FleetOrder(
        fleetId: fleet.id,
        orderType: orders.FleetOrderType.Move,
        targetSystem: some(closestColony),
        targetFleet: none(FleetId),
        priority: order.priority
      )

      # Use centralized movement arbiter
      var events: seq[resolution_types.GameEvent] = @[]
      # resolveMovementOrder(state, fleet.owner, moveOrder, events)
      # TODO: Re-introduce call to resolveMovementOrder after it's been refactored

      # Check if fleet moved
      let updatedFleetOpt = state.getFleet(fleet.id)
      if updatedFleetOpt.isNone:
        return OrderOutcome.Failed

      let movedFleet = updatedFleetOpt.get()

      # Check if actually moved (pathfinding succeeded)
      if movedFleet.location == fleet.location:
        # Fleet didn't move - no path found
        events.add(event_factory.orderFailed(
          houseId = fleet.owner,
          fleetId = fleet.id,
          orderType = "Reserve",
          reason = "cannot reach colony",
          systemId = some(fleet.location)
        ))
        return OrderOutcome.Failed

      # Keep order persistent - will execute when fleet arrives
      # Silent - movement in progress
      return OrderOutcome.Success

  # At friendly colony - apply reserve status
  var updatedFleet = fleet
  updatedFleet.status = FleetStatus.Reserve
  state.fleets[fleet.id] = updatedFleet

  # Generate OrderCompleted event for state change
  events.add(event_factory.orderCompleted(
    fleet.owner,
    fleet.id,
    "Reserve",
    details = "placed on reserve status",
    systemId = some(fleet.location)
  ))

  return OrderOutcome.Success

proc executeMothballOrder*(
  state: var GameState,
  fleet: Fleet,
  order: orders.FleetOrder,
  events: var seq[resolution_types.GameEvent]
): OrderOutcome =
  ## Mothball fleet (0% maintenance, offline, screened in combat)
  ## Per economy.md:3.9
  ## If not at friendly colony with spaceport, auto-seeks nearest one first

  # Check if already at a friendly colony with spaceport
  var atFriendlyColonyWithSpaceport = false
  if fleet.location in state.colonies:
    let colony = state.colonies[fleet.location]
    if colony.owner == fleet.owner and colony.spaceports.len > 0:
      atFriendlyColonyWithSpaceport = true

  # If not at friendly colony with spaceport, find closest one and move there
  if not atFriendlyColonyWithSpaceport:
    # Find all friendly colonies with spaceports
    var friendlyColoniesWithSpaceports: seq[SystemId] = @[]
    for colonyId, colony in state.colonies:
      if colony.owner == fleet.owner and colony.spaceports.len > 0:
        friendlyColoniesWithSpaceports.add(colonyId)

    if friendlyColoniesWithSpaceports.len == 0:
      return OrderOutcome.Failed

    # Find closest colony using pathfinding
    var closestColony = friendlyColoniesWithSpaceports[0]
    var minDistance = int.high

    for colonyId in friendlyColoniesWithSpaceports:
      let pathResult = state.starMap.findPath(fleet.location, colonyId, fleet)
      if pathResult.found:
        let distance = pathResult.path.len - 1
        if distance < minDistance:
          minDistance = distance
          closestColony = colonyId

    # Not at colony yet - move toward it
    if fleet.location != closestColony:
      # Create movement order to target colony
      let moveOrder = orders.FleetOrder(
        fleetId: fleet.id,
        orderType: orders.FleetOrderType.Move,
        targetSystem: some(closestColony),
        targetFleet: none(FleetId),
        priority: order.priority
      )

      # Use centralized movement arbiter
      var events: seq[resolution_types.GameEvent] = @[]
      # resolveMovementOrder(state, fleet.owner, moveOrder, events)
      # TODO: Re-introduce call to resolveMovementOrder after it's been refactored

      # Check if fleet moved
      let updatedFleetOpt = state.getFleet(fleet.id)
      if updatedFleetOpt.isNone:
        return OrderOutcome.Failed

      let movedFleet = updatedFleetOpt.get()

      # Check if actually moved (pathfinding succeeded)
      if movedFleet.location == fleet.location:
        # Fleet didn't move - no path found
        events.add(event_factory.orderFailed(
          houseId = fleet.owner,
          fleetId = fleet.id,
          orderType = "Mothball",
          reason = "cannot reach colony",
          systemId = some(fleet.location)
        ))
        return OrderOutcome.Failed

      # Keep order persistent - will execute when fleet arrives
      # Silent - movement in progress
      return OrderOutcome.Success

  # At friendly colony with spaceport - apply mothball status
  var updatedFleet = fleet
  updatedFleet.status = FleetStatus.Mothballed
  state.fleets[fleet.id] = updatedFleet

  # Generate OrderCompleted event for state change
  events.add(event_factory.orderCompleted(
    fleet.owner,
    fleet.id,
    "Mothball",
    details = "mothballed",
    systemId = some(fleet.location)
  ))

  return OrderOutcome.Success

proc executeReactivateOrder*(
  state: var GameState,
  fleet: Fleet,
  order: orders.FleetOrder,
  events: var seq[resolution_types.GameEvent]
): OrderOutcome =
  ## Return reserve or mothballed fleet to active duty

  if fleet.status == FleetStatus.Active:
    events.add(event_factory.orderFailed(
      houseId = fleet.owner,
      fleetId = fleet.id,
      orderType = "Reactivate",
      reason = "fleet already active",
      systemId = some(fleet.location)
    ))
    return OrderOutcome.Failed

  # Change status to Active
  var updatedFleet = fleet
  updatedFleet.status = FleetStatus.Active
  state.fleets[fleet.id] = updatedFleet

  # Generate OrderCompleted event for state change
  events.add(event_factory.orderCompleted(
    fleet.owner,
    fleet.id,
    "Reactivate",
    details = "reactivated",
    systemId = some(fleet.location)
  ))

  return OrderOutcome.Success
