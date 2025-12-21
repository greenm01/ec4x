## Move Order Execution
##
## This module contains the logic for executing 'Move' fleet orders.
## It includes pathfinding, lane traversal rules, and destination arrival handling.

import std/[tables, options, sequtils, strformat, algorithm]
import ../../../../common/types/[core, units]
import ../../gamestate, ../../fleet, ../../squadron, ../../starmap, ../../logger
import ../../index_maintenance
import ../../state_helpers
import ../../intelligence/generator
import ../../intelligence/types as intel_types
import ../../types/resolution as resolution_types
import ../../events/init as event_factory
import ../../diplomacy/types as dip_types
import ../main as orders # For FleetOrder and FleetOrderType

var movementCallDepth {.global.} = 0 # Using global for recursion check, consider passing as param if feasible

proc resolveMovementOrder*(
  state: var GameState, houseId: HouseId, order: orders.FleetOrder,
  events: var seq[resolution_types.GameEvent]
) =
  ## Execute a fleet movement order with pathfinding and lane traversal rules
  ## Per operations.md:6.1 - Lane traversal rules:
  ##   - Major lanes: 2 jumps per turn if all systems owned by player
  ##   - Major lanes: 1 jump per turn if jumping into unexplored/rival system
  ##   - Minor/Restricted lanes: 1 jump per turn maximum
  ##   - Crippled ships or Spacelift ships cannot cross Restricted lanes

  # Detect infinite recursion
  movementCallDepth += 1
  if movementCallDepth > 100:
    logFatal(LogCategory.lcFleet, "resolveMovementOrder recursion depth > 100! Infinite loop detected!")
    quit(1)

  defer:
    movementCallDepth -= 1

  if order.targetSystem.isNone:
    return

  # Get fleet
  let fleetOpt = state.getFleet(order.fleetId)
  if fleetOpt.isNone:
    return
  var fleet = fleetOpt.get()

  # Reserve and Mothballed fleets cannot move (permanently stationed at colony)
  # Per operations.md: Both statuses represent fleets that are station-keeping
  # - Reserve: 50% maintenance, reduced combat, can fight in orbital defense
  # - Mothballed: 0% maintenance, must be screened, risks destruction in combat
  if fleet.status == FleetStatus.Reserve or fleet.status == FleetStatus.Mothballed:
    logWarn(LogCategory.lcFleet, &"Fleet {order.fleetId} cannot move - status: {fleet.status} (permanently stationed)")
    return

  let targetId = order.targetSystem.get()
  let startId = fleet.location

  # Already at destination - clear order (arrival complete)
  if startId == targetId:
    logDebug(LogCategory.lcFleet, &"Fleet {order.fleetId} arrived at destination, order complete")
    # Generate OrderCompleted event - cleanup handled by Command Phase
    events.add(event_factory.orderCompleted(
      houseId,
      order.fleetId,
      "Move",
      details = &"arrived at {targetId}",
      systemId = some(targetId)
    ))
    return

  logDebug(LogCategory.lcFleet, &"Fleet {order.fleetId} moving from {startId} to {targetId}")

  # Find path to destination (operations.md:6.1)
  let pathResult = state.starMap.findPath(startId, targetId, fleet)

  if not pathResult.found:
    logWarn(LogCategory.lcFleet, &"Fleet {order.fleetId}: No valid path found (blocked by restricted lanes or terrain)")
    return

  if pathResult.path.len < 2:
    logError(LogCategory.lcFleet, &"Fleet {order.fleetId}: Invalid path")
    return

  # Determine how many jumps the fleet can make this turn
  var jumpsAllowed = 1  # Default: 1 jump per turn

  # Check if we can do 2 major lane jumps (operations.md:6.1)
  if pathResult.path.len >= 3:
    # Check if all systems along path are owned by this house
    var allSystemsOwned = true
    for systemId in pathResult.path:
      if systemId notin state.colonies or state.colonies[systemId].owner != houseId:
        allSystemsOwned = false
        break

    # Check if next two jumps are both major lanes
    var nextTwoAreMajor = true
    if allSystemsOwned:
      for i in 0..<min(2, pathResult.path.len - 1):
        let fromSys = pathResult.path[i]
        let toSys = pathResult.path[i + 1]

        # Find lane type between these systems
        var laneIsMajor = false
        for lane in state.starMap.lanes:
          if (lane.source == fromSys and lane.destination == toSys) or
             (lane.source == toSys and lane.destination == fromSys):
            if lane.laneType == LaneType.Major:
              laneIsMajor = true
            break

        if not laneIsMajor:
          nextTwoAreMajor = false
          break

    # Apply 2-jump rule for major lanes in friendly territory
    if allSystemsOwned and nextTwoAreMajor:
      jumpsAllowed = 2

  # Execute movement (up to jumpsAllowed systems)
  let actualJumps = min(jumpsAllowed, pathResult.path.len - 1)
  let newLocation = pathResult.path[actualJumps]

  # Update fleet location
  fleet.location = newLocation
  state.updateFleetLocation(order.fleetId, startId, newLocation)
  state.fleets[order.fleetId] = fleet

  # Generate OrderCompleted event for fleet movement
  let moveDetails = if newLocation == targetId:
    &"arrived at {targetId}"
  else:
    &"moved from {startId} to {newLocation} ({actualJumps} jump(s))"

  events.add(event_factory.orderCompleted(
    houseId,
    order.fleetId,
    "Move",
    details = moveDetails,
    systemId = some(newLocation)
  ))

  # Check if we've arrived at final destination (N+1 behavior)
  # Event generated above, cleanup handled by Command Phase
  if newLocation == targetId:
    logInfo(LogCategory.lcFleet, &"Fleet {order.fleetId} arrived at destination {targetId}, order complete")

    # Check if this fleet is on a spy mission and start mission on arrival
    if fleet.missionState == FleetMissionState.Traveling:
      var updatedFleet = state.fleets[order.fleetId]
      updatedFleet.missionState = FleetMissionState.OnSpyMission
      updatedFleet.missionStartTurn = state.turn

      let scoutCount = updatedFleet.squadrons.len

      # Register active mission
      state.activeSpyMissions[order.fleetId] = ActiveSpyMission(
        fleetId: order.fleetId,
        missionType: SpyMissionType(updatedFleet.missionType.get()),
        targetSystem: updatedFleet.location,
        scoutCount: scoutCount,
        startTurn: state.turn,
        ownerHouse: updatedFleet.owner
      )

      # Update fleet in state
      state.fleets[order.fleetId] = updatedFleet

      # Generate mission start event
      let missionName = case SpyMissionType(updatedFleet.missionType.get())
        of SpyMissionType.SpyOnPlanet: "spy mission"
        of SpyMissionType.HackStarbase: "starbase hack"
        of SpyMissionType.SpyOnSystem: "system reconnaissance"

      events.add(event_factory.orderCompleted(
        houseId,
        order.fleetId,
        "SpyMissionStarted",
        details = &"{missionName} started at {targetId} ({scoutCount} scouts)",
        systemId = some(targetId)
      ))

      logInfo(LogCategory.lcFleet, &"Fleet {order.fleetId} spy mission started at {targetId}")

  else:
    logInfo(LogCategory.lcFleet, &"Fleet {order.fleetId} moved {actualJumps} jump(s) to system {newLocation}")

  # Automatic intelligence gathering when arriving at system
  # ANY fleet presence reveals enemy colonies (passive reconnaissance)
  if newLocation in state.colonies:
    let colony = state.colonies[newLocation]
    if colony.owner != houseId:
      # Generate basic intelligence report on enemy colony
      let intelReport = generateColonyIntelReport(state, houseId, newLocation, intel_types.IntelQuality.Visual)
      if intelReport.isSome:
        # Use withHouse template to ensure proper write-back
        var h = state.houses[houseId]
        h.intelligence.addColonyReport(intelReport.get())
        state.houses[houseId] = h
        logInfo(LogCategory.lcFleet, &"Fleet {order.fleetId} ({houseId}) gathered intelligence on enemy colony at {newLocation} (owner: {colony.owner}) - DB now has {h.intelligence.colonyReports.len} reports")
      else:
        logWarn(LogCategory.lcFleet, &"Fleet {order.fleetId} ({houseId}) failed to generate intel report for enemy colony at {newLocation}")

  # Check for fleet encounters at destination with STEALTH DETECTION
  # Per assets.md:2.4.3 - Cloaked fleets can only be detected by scouts or starbases
  # Note: Scout-only fleets are excluded from combat by combat resolution system
  var enemyFleetsAtLocation: seq[tuple[fleetId: FleetId, fleet: Fleet]] = @[]
  let detectingFleet = state.fleets[order.fleetId]
  let hasScouts = detectingFleet.squadrons.anyIt(it.hasScouts())

  for otherFleetId, otherFleet in state.fleets:
    if otherFleetId != order.fleetId and otherFleet.location == newLocation:
      if otherFleet.owner != houseId:
        # STEALTH CHECK: Cloaked fleets only detected by scouts
        if otherFleet.isCloaked() and not hasScouts:
          logDebug(LogCategory.lcFleet, &"Fleet {order.fleetId} failed to detect cloaked fleet {otherFleetId} at {newLocation} (no scouts)")
          continue  # Cloaked fleet remains undetected

        logInfo(LogCategory.lcFleet, &"Fleet {order.fleetId} encountered fleet {otherFleetId} ({otherFleet.owner}) at {newLocation}")
        enemyFleetsAtLocation.add((otherFleetId, otherFleet))

    # Generate fleet encounter event (Phase 7b)
    if enemyFleetsAtLocation.len > 0:
      let encounteredIds = enemyFleetsAtLocation.mapIt(it.fleetId)
      let relation = state.houses[houseId].diplomaticRelations.getDiplomaticState(enemyFleetsAtLocation[0].fleet.owner)
      let diplomaticStatus = $relation

      events.add(event_factory.fleetEncounter(
        houseId,
        order.fleetId,
        encounteredIds,
        diplomaticStatus,
        newLocation
      ))

    # Automatic intelligence gathering - detected enemy fleets
    if enemyFleetsAtLocation.len > 0:
      let systemIntelReport = generateSystemIntelReport(state, houseId, newLocation, intel_types.IntelQuality.Visual)
      if systemIntelReport.isSome:
        state.withHouse(houseId):
          house.intelligence.addSystemReport(systemIntelReport.get())
        logDebug(LogCategory.lcFleet, &"Fleet {order.fleetId} gathered intelligence on {enemyFleetsAtLocation.len} enemy fleet(s) at {newLocation}")

    # Combat will be resolved in conflict phase next turn
    # This just logs the encounter

  return OrderOutcome.Success