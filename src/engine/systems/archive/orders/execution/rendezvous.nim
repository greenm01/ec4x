## Rendezvous Order Execution
##
## This module contains the logic for executing the 'Rendezvous' fleet order,
## which directs multiple fleets to a designated system for merging.

import std/[options, tables, strformat, algorithm, sets]
import ../../../../common/types/[core, units]
import ../../gamestate, ../../fleet, ../../logger, ../../starmap
import ../../index_maintenance
import ../../types/resolution as resolution_types
import ../../events/init as event_factory
import ../main as orders # For FleetOrder and FleetOrderType
import ../../types/diplomacy as dip_types # For DiplomaticState

proc executeRendezvousOrder*(
  state: var GameState,
  fleet: Fleet,
  order: orders.FleetOrder,
  events: var seq[resolution_types.GameEvent]
): OrderOutcome =
  ## Order 14: Move to system and merge with other rendezvous fleets
  ## Lowest fleet ID becomes host
  ## Per operations.md:6.2.15
  ##
  ## SCOUT MESH NETWORK BENEFITS:
  ## When multiple scout squadrons rendezvous, they automatically gain mesh network ELI bonuses:
  ## - 2-3 scouts: +1 ELI bonus
  ## - 4-5 scouts: +2 ELI bonus
  ## - 6+ scouts: +3 ELI bonus (maximum)
  ## All squadrons (including scouts) from all rendezvous fleets are merged into the host fleet.
  ## See assets.md:2.4.2 for mesh network modifier table.

  if order.targetSystem.isNone:
    events.add(event_factory.orderFailed(
      fleet.owner,
      fleet.id,
      "Rendezvous",
      reason = "no target system specified",
      systemId = some(fleet.location)
    ))
    return OrderOutcome.Failed

  let targetSystem = order.targetSystem.get()

  # Check if rendezvous point has hostile forces (enemy/neutral fleets)
  # Use fleetsByLocation index for O(1) lookup instead of O(F) scan
  let house = state.houses[fleet.owner]
  if targetSystem in state.fleetsByLocation:
    for otherFleetId in state.fleetsByLocation[targetSystem]:
      if otherFleetId notin state.fleets:
        continue  # Skip stale index entry
      let otherFleet = state.fleets[fleetId]
      if otherFleet.owner != fleet.owner:
        let relation = dip_types.getDiplomaticState(house.diplomaticRelations, otherFleet.owner)
        if relation == dip_types.DiplomaticState.Enemy or relation == dip_types.DiplomaticState.Hostile:
          # Hostile forces at rendezvous - abort
          events.add(event_factory.orderAborted(
            fleet.owner,
            fleet.id,
            "Rendezvous",
            reason = "hostile forces present at rendezvous point",
            systemId = some(fleet.location)
          ))
          return OrderOutcome.Aborted

  # Check if rendezvous point colony is enemy-controlled (additional check)
  if targetSystem in state.colonies:
    let colony = state.colonies[targetSystem]
    if colony.owner != fleet.owner:
      let relation = dip_types.getDiplomaticState(house.diplomaticRelations, colony.owner)
      if relation == dip_types.DiplomaticState.Enemy:
        # Rendezvous point is enemy territory - abort
        events.add(event_factory.orderAborted(
          fleet.owner,
          fleet.id,
          "Rendezvous",
          reason = "rendezvous point is enemy-controlled",
          systemId = some(fleet.location)
        ))
        return OrderOutcome.Aborted

  # Check if fleet is at rendezvous point
  if fleet.location != targetSystem:
    # Still moving to rendezvous
    return OrderOutcome.Success

  # Find other fleets at rendezvous with same order at same location
  # Use fleetsByLocation index for O(1) lookup instead of O(F) scan
  var rendezvousFleets: seq[Fleet] = @[]
  rendezvousFleets.add(fleet)

  # Collect all fleets with Rendezvous orders at this system
  if targetSystem in state.fleetsByLocation:
    for otherFleetId in state.fleetsByLocation[targetSystem]:
      if otherFleetId == fleet.id:
        continue  # Skip self
      if otherFleetId notin state.fleets:
        continue  # Skip stale index entry

      let otherFleet = state.fleets[otherFleetId]
      # Check if owned by same house
      if otherFleet.owner == fleet.owner:
        # Check if has Rendezvous order to same system
        if otherFleetId in state.fleetOrders:
          let otherOrder = state.fleetOrders[otherFleetId]
          if otherOrder.orderType == orders.FleetOrderType.Rendezvous and
             otherOrder.targetSystem.isSome and
             otherOrder.targetSystem.get() == targetSystem:
            rendezvousFleets.add(otherFleet)

  # If only this fleet, wait for others
  if rendezvousFleets.len == 1:
    # Silent - waiting
    return OrderOutcome.Success

  # Multiple fleets at rendezvous - merge into lowest ID fleet
  var lowestId = fleet.id
  for f in rendezvousFleets:
    if f.id < lowestId:
      lowestId = f.id

  # Get host fleet
  var hostFleet = state.fleets[lowestId]

  # Merge all other fleets into host
  var mergedCount = 0
  for f in rendezvousFleets:
    if f.id == lowestId:
      continue  # Skip host

    # Merge squadrons (all squadron types)
    for squadron in f.squadrons:
      hostFleet.squadrons.add(squadron)

    # Remove merged fleet and clean up orders
    state.removeFleetFromIndices(f.id, f.owner, f.location)
    state.fleets.del(f.id)
    if f.id in state.fleetOrders:
      state.fleetOrders.del(f.id)
    if f.id in state.standingOrders:
      state.standingOrders.del(f.id)

    mergedCount += 1
    logInfo(LogCategory.lcFleet, "Fleet " & $f.id & " merged into rendezvous host " & $lowestId & " (source fleet removed)")

  # Update host fleet
  state.fleets[lowestId] = hostFleet

  var message = "Rendezvous complete at " & $targetSystem & ": " & $mergedCount & " fleets merged into " & $lowestId

  # Generate OrderCompleted event for successful rendezvous
  var details = &"{mergedCount} fleet(s) merged"

  events.add(event_factory.orderCompleted(
    fleet.owner,
    lowestId,
    "Rendezvous",
    details = details,
    systemId = some(targetSystem)
  ))

  return OrderOutcome.Success
