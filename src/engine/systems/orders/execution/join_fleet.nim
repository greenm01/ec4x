## Join Fleet Order Execution
##
## This module contains the logic for executing the 'Join Fleet' order,
## which merges a source fleet into a target fleet at the same location.

import std/[options, tables, strformat, algorithm, sets]
import ../../../../common/types/[core, units]
import ../../gamestate, ../../fleet, ../../logger, ../../starmap
import ../../index_maintenance
import ../../types/resolution as resolution_types
import ../../events/init as event_factory
import ../../standing_orders
import ../main as orders # For FleetOrder and FleetOrderType
import ../../types/diplomacy as dip_types # For DiplomaticState

proc executeJoinFleetOrder*(
  state: var GameState,
  fleet: Fleet,
  order: orders.FleetOrder,
  events: var seq[resolution_types.GameEvent]
): OrderOutcome =
  ## Order 13: Seek and merge with another fleet
  ## Old fleet disbands, squadrons join target
  ## Per operations.md:6.2.14
  ##
  ## SCOUT MESH NETWORK BENEFITS:
  ## When merging scout squadrons, they automatically gain mesh network ELI bonuses:
  ## - 2-3 scouts: +1 ELI bonus
  ## - 4-5 scouts: +2 ELI bonus
  ## - 6+ scouts: +3 ELI bonus (maximum)
  ## These bonuses apply to detection, counter-intelligence, and spy missions.
  ## See assets.md:2.4.2 for mesh network modifier table.

  if order.targetFleet.isNone:
    events.add(event_factory.orderFailed(
      fleet.owner,
      fleet.id,
      "JoinFleet",
      reason = "no target fleet specified",
      systemId = some(fleet.location)
    ))
    return OrderOutcome.Failed

  let targetFleetId = order.targetFleet.get()

  # Target is a normal fleet
  let targetFleetOpt = state.getFleet(targetFleetId)

  if targetFleetOpt.isNone:
    # Target fleet destroyed or deleted - clear the order and fall back to standing orders
    # Standing orders will be used automatically by the order resolution system
    if fleet.id in state.fleetOrders:
      state.fleetOrders.del(fleet.id)
      standing_orders.resetStandingOrderGracePeriod(state, fleet.id)

    events.add(event_factory.orderAborted(
        houseId = fleet.owner,
        fleetId = fleet.id,
        orderType = "JoinFleet",
        reason = "target fleet no longer exists",
        systemId = some(fleet.location)
      ))

    return OrderOutcome.Failed

  let targetFleet = targetFleetOpt.get()

  # Check same owner
  if targetFleet.owner != fleet.owner:
    events.add(event_factory.orderFailed(
      fleet.owner,
      fleet.id,
      "JoinFleet",
      reason = "target fleet is not owned by same house",
      systemId = some(fleet.location)
    ))
    return OrderOutcome.Failed

  # Check if at same location - if not, move toward target
  if targetFleet.location != fleet.location:
    # Fleet will follow target - use centralized movement system
    # Create a movement order to target\'s current location
    let movementOrder = orders.FleetOrder(
      fleetId: fleet.id,
      orderType: orders.FleetOrderType.Move,
      targetSystem: some(targetFleet.location),
      targetFleet: none(FleetId),
      priority: order.priority
    )

    # Use the centralized movement arbiter (handles all lane logic, pathfinding, etc.)
    # This respects DoD principles - movement logic in ONE place
    var events: seq[resolution_types.GameEvent] = @[]
    # resolveMovementOrder(state, fleet.owner, movementOrder, events)
    # TODO: Re-introduce call to resolveMovementOrder after it\'s been refactored

    # Check if movement succeeded by comparing fleet location
    let updatedFleetOpt = state.getFleet(fleet.id)
    if updatedFleetOpt.isNone:
      return OrderOutcome.Failed

    let movedFleet = updatedFleetOpt.get()

    # Check if fleet actually moved (pathfinding succeeded)
    if movedFleet.location == fleet.location:
      # Fleet didn\'t move - no path found to target
      # Cancel order and fall back to standing orders
      if fleet.id in state.fleetOrders:
        state.fleetOrders.del(fleet.id)
        standing_orders.resetStandingOrderGracePeriod(state, fleet.id)

      events.add(event_factory.orderAborted(
          houseId = fleet.owner,
          fleetId = fleet.id,
          orderType = "JoinFleet",
          reason = "cannot reach target",
          systemId = some(fleet.location)
        ))

      return OrderOutcome.Failed

    # If still not at target location, keep order persistent
    if movedFleet.location != targetFleet.location:
      # Keep the Join Fleet order active so it continues pursuit next turn
      # Order remains in fleetOrders table
      # Silent - ongoing pursuit
      return OrderOutcome.Success

    # If we got here, fleet reached target - fall through to merge logic below

  # At same location - merge squadrons into target fleet (all squadron types)
  var updatedTargetFleet = targetFleet
  for squadron in fleet.squadrons:
    updatedTargetFleet.squadrons.add(squadron)

  state.fleets[targetFleetId] = updatedTargetTargetFleet

  # Remove source fleet and clean up orders
  state.removeFleetFromIndices(fleet.id, fleet.owner, fleet.location)
  state.fleets.del(fleet.id)
  if fleet.id in state.fleetOrders:
    state.fleetOrders.del(fleet.id)
  if fleet.id in state.standingOrders:
    state.standingOrders.del(fleet.id)

  logInfo(LogCategory.lcFleet, "Fleet " & $fleet.id & " merged into fleet " & $targetFleetId & " (source fleet removed)")

  # Generate OrderCompleted event for successful fleet merge
  events.add(event_factory.orderCompleted(
    fleet.owner,
    fleet.id,
    "JoinFleet",
    details = &"merged into fleet {targetFleetId}",
    systemId = some(fleet.location)
  ))

  return OrderOutcome.Success
