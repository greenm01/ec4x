## Spy Scout Order Execution
## Handles orders for spy scout "fleets" - transparent to user
## Spy scouts can merge with each other or with normal fleets

import std/[tables, options]
import ../../common/[types/core, logger]
import ../[gamestate, fleet, squadron, starmap]

# =============================================================================
# Order Execution
# =============================================================================

proc executeSpyScoutJoinFleet*(state: var GameState, spyScout: SpyScout, targetFleetId: FleetId): bool =
  ## Merge spy scout with normal fleet
  ## Spy scout becomes a squadron, SpyScout object is deleted
  ## Returns true if successful

  # Find target fleet
  if targetFleetId notin state.fleets:
    logWarn("SpyScoutOrders", "Target fleet not found",
            "spyScout=", spyScout.id, " targetFleet=", $targetFleetId)
    return false

  let targetFleet = state.fleets[targetFleetId]

  # Check same owner
  if targetFleet.owner != spyScout.owner:
    logWarn("SpyScoutOrders", "Cannot join fleet owned by different house",
            "spyScout=", spyScout.id, " spyOwner=", $spyScout.owner, " fleetOwner=", $targetFleet.owner)
    return false

  # Check same location
  if targetFleet.location != spyScout.location:
    logWarn("SpyScoutOrders", "Spy scout and fleet must be at same location",
            "spyScout=", spyScout.id, " spyLocation=", $spyScout.location, " fleetLocation=", $targetFleet.location)
    return false

  # Convert spy scout back to squadron
  # Create scout ship with ELI level matching spy scout
  let scoutShip = newEnhancedShip(ShipClass.Scout, techLevel = spyScout.eliLevel)
  var squadron = newSquadron(scoutShip, spyScout.id & "-sq", spyScout.owner, spyScout.location)

  # If spy scout had merged scouts, add multiple squadrons (up to mergedScoutCount)
  var updatedFleet = targetFleet
  for i in 0..<spyScout.mergedScoutCount:
    updatedFleet.squadrons.add(squadron)

  state.fleets[targetFleetId] = updatedFleet

  # Remove spy scout object
  state.spyScouts.del(spyScout.id)
  if spyScout.id in state.spyScoutOrders:
    state.spyScoutOrders.del(spyScout.id)

  logInfo("SpyScoutOrders", "Spy scout merged into fleet",
         "spyScout=", spyScout.id, " targetFleet=", $targetFleetId, " squadronsAdded=", $spyScout.mergedScoutCount)

  return true

proc executeSpyScoutJoinSpyScout*(state: var GameState, sourceId: string, targetId: string): bool =
  ## Merge two spy scouts together
  ## Source spy scout merges into target, source is deleted
  ## Target gains merged scout count (mesh network bonus)
  ## Returns true if successful

  # Validate both spy scouts exist
  if sourceId notin state.spyScouts or targetId notin state.spyScouts:
    logWarn("SpyScoutOrders", "Spy scout not found for merge",
            "source=", sourceId, " target=", targetId)
    return false

  let source = state.spyScouts[sourceId]
  var target = state.spyScouts[targetId]

  # Check same owner
  if source.owner != target.owner:
    logWarn("SpyScoutOrders", "Cannot merge spy scouts from different houses",
            "source=", sourceId, " target=", targetId)
    return false

  # Check same location
  if source.location != target.location:
    logWarn("SpyScoutOrders", "Spy scouts must be at same location to merge",
            "source=", sourceId, " target=", targetId)
    return false

  # Merge: add source's scout count to target
  target.mergedScoutCount += source.mergedScoutCount

  # Update target spy scout
  state.spyScouts[targetId] = target

  # Remove source spy scout
  state.spyScouts.del(sourceId)
  if sourceId in state.spyScoutOrders:
    state.spyScoutOrders.del(sourceId)

  # Calculate mesh network bonus
  let meshBonus =
    if target.mergedScoutCount >= 6: 3
    elif target.mergedScoutCount >= 4: 2
    elif target.mergedScoutCount >= 2: 1
    else: 0

  logInfo("SpyScoutOrders", "Spy scouts merged",
         "source=", sourceId, " target=", targetId,
         " totalScouts=", $target.mergedScoutCount, " meshBonus=+", $meshBonus, " ELI")

  return true

proc executeSpyScoutMove*(state: var GameState, spyScout: SpyScout, targetSystem: SystemId): bool =
  ## Move spy scout to new target system
  ## Recalculates travel path using jump lanes
  ## Returns true if successful

  # Create a temporary scout fleet for pathfinding
  # Spy scouts use same pathfinding rules as normal scout fleets
  let scoutShip = newEnhancedShip(ShipClass.Scout, techLevel = spyScout.eliLevel)
  var squadron = newSquadron(scoutShip, "temp-sq", spyScout.owner, spyScout.location)
  let tempFleet = newFleet(squadrons = @[squadron], id = "temp-path", owner = spyScout.owner, location = spyScout.location)

  # Calculate new path from current location to target
  let path = findPath(state.starMap, spyScout.location, targetSystem, tempFleet)

  if path.path.len == 0:
    logWarn("SpyScoutOrders", "No jump lane route to target",
            "spyScout=", spyScout.id, " from=", $spyScout.location, " to=", $targetSystem)
    return false

  # Update spy scout with new path
  var updated = spyScout
  updated.targetSystem = targetSystem
  updated.travelPath = path.path
  updated.currentPathIndex = 0
  updated.state = SpyScoutState.Traveling

  state.spyScouts[spyScout.id] = updated

  logInfo("SpyScoutOrders", "Spy scout moving to new target",
         "spyScout=", spyScout.id, " target=", $targetSystem, " jumps=", $path.path.len)

  return true

proc resolveSpyScoutOrders*(state: var GameState) =
  ## Process all pending spy scout orders
  ## Called during Command Phase resolution

  for spyScoutId, order in state.spyScoutOrders:
    # Skip if spy scout no longer exists (detected/destroyed)
    if spyScoutId notin state.spyScouts:
      continue

    let spyScout = state.spyScouts[spyScoutId]

    case order.orderType
    of SpyScoutOrderType.Hold:
      # Do nothing - spy scout stays at current location
      discard

    of SpyScoutOrderType.Move:
      if order.targetSystem.isSome:
        discard executeSpyScoutMove(state, spyScout, order.targetSystem.get())

    of SpyScoutOrderType.JoinSpyScout:
      if order.targetSpyScout.isSome:
        discard executeSpyScoutJoinSpyScout(state, spyScoutId, order.targetSpyScout.get())

    of SpyScoutOrderType.JoinFleet:
      if order.targetFleet.isSome:
        discard executeSpyScoutJoinFleet(state, spyScout, order.targetFleet.get())

    of SpyScoutOrderType.Rendezvous:
      # Rendezvous handled separately (multiple spy scouts coordinate)
      discard

    of SpyScoutOrderType.CancelMission:
      # Set spy scout to return home
      var updated = spyScout
      updated.state = SpyScoutState.Returning
      # Find path back to nearest friendly colony
      # TODO: Implement return-to-home pathfinding
      state.spyScouts[spyScoutId] = updated

  # Clear processed orders
  state.spyScoutOrders.clear()
