## Spy Colony Order Execution
##
## This module contains the logic for executing the 'Spy on a Colony' fleet order,
## which dispatches scout fleets to gather intelligence on enemy colonies.

import std/[options, tables, strformat]
import ../../../../common/types/[core, units]
import ../../gamestate, ../../fleet, ../../logger, ../../starmap
import ../../index_maintenance
import ../../intelligence/detection
import ../../types/resolution as resolution_types
import ../../events/init as event_factory
import ../main as orders # For FleetOrder and FleetOrderType, SpyMissionType

proc executeSpyColonyOrder*(
  state: var GameState,
  fleet: Fleet,
  order: orders.FleetOrder,
  events: var seq[resolution_types.GameEvent]
): OrderOutcome =
  ## Order 11: Deploy scout to gather planet intelligence
  ## Reserved for solo Scout operations per operations.md:6.2.10

  if order.targetSystem.isNone:
    events.add(event_factory.orderFailed(
      fleet.owner,
      fleet.id,
      "SpyColony",
      reason = "no target system specified",
      systemId = some(fleet.location)
    ))
    return OrderOutcome.Failed

  let targetSystem = order.targetSystem.get()
  let houseId = fleet.owner

  # Validate target house is not eliminated (leaderboard is public info)
  if targetSystem in state.colonies:
    let colony = state.colonies[targetSystem]
    if colony.owner in state.houses:
      let targetHouse = state.houses[colony.owner]
      if targetHouse.eliminated:
        events.add(event_factory.orderFailed(
          houseId,
          fleet.id,
          "SpyColony",
          reason = "target house eliminated",
          systemId = some(fleet.location)
        ))
        return OrderOutcome.Failed

  # Count scouts for mesh network bonus (validation already confirmed scout-only fleet)
  let scoutCount = fleet.squadrons.len

  # Set fleet mission state
  var updatedFleet = fleet
  updatedFleet.missionState = FleetMissionState.Traveling
  updatedFleet.missionType = some(ord(orders.SpyMissionType.SpyOnPlanet)) # Use orders.SpyMissionType
  updatedFleet.missionTarget = some(targetSystem)

  # Create movement order to target (if not already there)
  if fleet.location != targetSystem:
    # Calculate jump lane path from current location to target
    let path = findPath(state.starMap, fleet.location, targetSystem, fleet)

    if path.path.len == 0:
      events.add(event_factory.orderFailed(
        houseId,
        fleet.id,
        "SpyColony",
        reason = "no path to target system",
        systemId = some(fleet.location)
      ))
      return OrderOutcome.Failed

    # Create movement order
    let travelOrder = orders.FleetOrder(
      fleetId: fleet.id,
      orderType: orders.FleetOrderType.Move,
      targetSystem: some(targetSystem)
    )
    state.fleetOrders[fleet.id] = travelOrder

    # Update fleet in state
    state.fleets[fleet.id] = updatedFleet

    # Generate order accepted event
    events.add(event_factory.orderCompleted(
      houseId,
      fleet.id,
      "SpyColony",
      details = &"scout fleet traveling to {targetSystem} for spy mission ({scoutCount} scouts)",
      systemId = some(fleet.location)
    ))
  else:
    # Already at target - start mission immediately
    updatedFleet.missionState = FleetMissionState.OnSpyMission
    updatedFleet.missionStartTurn = state.turn


    # Update fleet in state
    state.fleets[fleet.id] = updatedFleet

    # Generate mission start event
    events.add(event_factory.orderCompleted(
      houseId,
      fleet.id,
      "SpyColony",
      details = &"spy mission started at {targetSystem} ({scoutCount} scouts)",
      systemId = some(targetSystem)
    ))

  return OrderOutcome.Success
