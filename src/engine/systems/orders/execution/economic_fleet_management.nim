## Economic and Fleet Management Order Execution
##
## This module contains the logic for executing 'Colonize', 'Join Fleet',
## 'Rendezvous', and 'Salvage' fleet orders.

import std/[options, tables, strformat, algorithm, sets]
import ../../../../common/types/[core, units]
import ../../gamestate, ../../fleet, ../../logger, ../../starmap
import ../../index_maintenance
import ../../types/resolution as resolution_types
import ../../events/init as event_factory
import ../../standing_orders
import ../main as orders # For FleetOrder and FleetOrderType
import ../../types/diplomacy as dip_types # For DiplomaticState

proc executeColonizeOrder*(
  state: var GameState,
  fleet: Fleet,
  order: orders.FleetOrder,
  events: var seq[resolution_types.GameEvent]
): OrderOutcome =
  ## Order 12: Establish colony with ETAC
  ## Reserved for ETAC under fleet escort per operations.md:6.2.13
  ## Calls resolveColonizationOrder to execute actual colonization

  if order.targetSystem.isNone:
    return OrderOutcome.Failed

  # Check fleet has ETAC with loaded colonists (Expansion squadrons)
  var hasLoadedETAC = false

  for squadron in fleet.squadrons:
    if squadron.squadronType == SquadronType.Expansion:
      if squadron.flagship.shipClass == ShipClass.ETAC and squadron.flagship.cargo.isSome:
        let cargo = squadron.flagship.cargo.get()
        if cargo.cargoType == CargoType.Colonists and cargo.quantity > 0:
          hasLoadedETAC = true
          break

  if not hasLoadedETAC:
    return OrderOutcome.Failed

  # Execute actual colonization using centralized colonization logic
  var colonizationEvents: seq[resolution_types.GameEvent] = @[]
  # fleet_orders.resolveColonizationOrder(state, fleet.owner, order,
  #                                       colonizationEvents)
  # TODO: Re-introduce call to resolveColonizationOrder after it's been refactored
  events.add(colonizationEvents)

  return OrderOutcome.Success

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
    # Create a movement order to target's current location
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
    # TODO: Re-introduce call to resolveMovementOrder after it's been refactored

    # Check if movement succeeded by comparing fleet location
    let updatedFleetOpt = state.getFleet(fleet.id)
    if updatedFleetOpt.isNone:
      return OrderOutcome.Failed

    let movedFleet = updatedFleetOpt.get()

    # Check if fleet actually moved (pathfinding succeeded)
    if movedFleet.location == fleet.location:
      # Fleet didn't move - no path found to target
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

  state.fleets[targetFleetId] = updatedTargetFleet

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
      let otherFleet = state.fleets[otherFleetId]
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
    for fleetId in state.fleetsByLocation[targetSystem]:
      if fleetId == fleet.id:
        continue  # Skip self
      if fleetId notin state.fleets:
        continue  # Skip stale index entry

      let otherFleet = state.fleets[fleetId]
      # Check if owned by same house
      if otherFleet.owner == fleet.owner:
        # Check if has Rendezvous order to same system
        if fleetId in state.fleetOrders:
          let otherOrder = state.fleetOrders[fleetId]
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
