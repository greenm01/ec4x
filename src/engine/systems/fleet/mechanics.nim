## Fleet movement, colonization, and seek home operations
##
## This module handles all fleet command resolution including:
## - Fleet movement with pathfinding and lane traversal rules
## - Colonization commands and new colony establishment
## - Automated Seek Home behavior for stranded fleets
## - Helper functions for path finding and hostility detection

import std/[tables, options, sequtils, strformat]
import ../../../common/logger
import ../../types/[core, combat, ground_unit, game_state, command, fleet, squadron, event, diplomacy, intel, starmap, espionage]
import ../../state/[entity_manager, iterators]
import ../../starmap as starmap_module
import ../ship/entity as ship_entity # Ship helper functions
import ../../entities/colony_ops
import ../colony/engine as col_engine
import ../../prestige/engine as prestige_engine
import ../../event_factory/init as event_factory
import ../../intel/generator
import ./standing
import ./movement # For findPath

proc completeFleetCommand*(
    state: var GameState,
    fleetId: FleetId,
    orderType: string,
    details: string = "",
    systemId: Option[SystemId] = none(SystemId),
    events: var seq[GameEvent],
) =
  ## Standard completion handler: generates OrderCompleted event
  ## Cleanup handled by event-driven order_cleanup module in Command Phase
  let fleetOpt = state.fleets.entities.entity(fleetId)
  if fleetOpt.isNone:
    return
  let houseId = fleetOpt.get().houseId

  events.add(
    event_factory.commandCompleted(houseId, fleetId, orderType, details, systemId)
  )

  logInfo("Orders", &"Fleet {fleetId} {orderType} order completed")

proc isSystemHostile*(state: GameState, systemId: SystemId, houseId: HouseId): bool =
  ## Check if a system is hostile to a house based on known intel (fog-of-war)
  ## System is hostile if player KNOWS it contains:
  ## 1. Enemy colony (from intelligence database or visibility)
  ## 2. Enemy fleets (from intelligence database or visibility)
  ## IMPORTANT: This respects fog-of-war - only uses information available to the house

  let houseOpt = state.houses.entities.entity(houseId)
  if houseOpt.isNone:
    return false
  let house = houseOpt.get()

  # Check if system has enemy colony (visible or from intel database)
  if state.colonies.bySystem.hasKey(systemId):
    let colonyId = state.colonies.bySystem[systemId]
    let colonyOpt = state.colonies.entities.entity(colonyId)
    if colonyOpt.isSome:
      let colony = colonyOpt.get()
      if colony.owner != houseId:
        # Check diplomatic status
        let key = (houseId, colony.owner)
        if state.diplomaticRelation.hasKey(key):
          if state.diplomaticRelation[key].state == DiplomaticState.Enemy:
            # Player can see this colony - it's hostile
            return true

  # Check intelligence database for known enemy colonies
  if state.intelligence.hasKey(houseId):
    let intel = state.intelligence[houseId]
    for colonyId, colonyIntel in intel.colonyReports:
      let colonyOpt = state.colonies.entities.entity(colonyId)
      if colonyOpt.isSome:
        let colony = colonyOpt.get()
        if colony.systemId == systemId and colony.owner != houseId:
          let key = (houseId, colony.owner)
          if state.diplomaticRelation.hasKey(key):
            if state.diplomaticRelation[key].state == DiplomaticState.Enemy:
              return true

  # Check for enemy fleets at system (visible or from intel)
  for fleet in state.fleetsInSystem(systemId):
    if fleet.houseId != houseId:
      let key = (houseId, fleet.houseId)
      if state.diplomaticRelation.hasKey(key):
        if state.diplomaticRelation[key].state == DiplomaticState.Enemy:
          return true

  return false

proc estimatePathRisk*(state: GameState, path: seq[SystemId], houseId: HouseId): int =
  ## Estimate risk level of a path (0 = safe, higher = more risky)
  ## Uses fog-of-war information available to the house
  result = 0

  for systemId in path:
    if isSystemHostile(state, systemId, houseId):
      result += 10 # Known enemy system - high risk
    elif state.colonies.bySystem.hasKey(systemId):
      let colonyId = state.colonies.bySystem[systemId]
      let colonyOpt = state.colonies.entities.entity(colonyId)
      if colonyOpt.isSome:
        let colony = colonyOpt.get()
        if colony.owner != houseId:
          # Foreign but not enemy (neutral) - moderate risk
          result += 3
    else:
      # Unexplored or empty - low risk
      result += 1

proc findClosestOwnedColony*(
    state: GameState, fromSystem: SystemId, houseId: HouseId
): Option[SystemId] =
  ## Find the closest owned colony for a house, excluding the fromSystem
  ## Returns None if house has no colonies
  ## Used by Space Guild to find alternative delivery destination
  ## Also used for automated Seek Home behavior for stranded fleets
  ##
  ## INTEGRATION: Checks house's pre-planned fallback routes first for optimal retreat paths

  # Check if house has a pre-planned fallback route from this region
  # TODO: Fallback routes not yet implemented in House type
  # let houseOpt = state.houses.entities.entity(houseId)
  # if houseOpt.isSome:
  #   let house = houseOpt.get()
  #   for route in house.fallbackRoutes:
  #     if route.region == fromSystem and state.turn - route.lastUpdated < 20:
  #       if state.colonies.bySystem.hasKey(route.fallbackSystem):
  #         let colonyId = state.colonies.bySystem[route.fallbackSystem]
  #         let colonyOpt = state.colonies.entities.entity(colonyId)
  #         if colonyOpt.isSome and colonyOpt.get().owner == houseId:
  #           return some(route.fallbackSystem)

  # Fallback: Calculate best retreat route balancing distance and risk
  # IMPORTANT: Uses fog-of-war information only (player's knowledge)
  var bestColony: Option[SystemId] = none(SystemId)
  var bestScore = int.high # Lower is better (combines distance and risk)

  # Iterate through all colonies owned by this house
  for colony in state.coloniesOwned(houseId):
    let systemId = colony.systemId
    if systemId != fromSystem:
      # Calculate distance (jump count) to this colony
      # Create dummy fleet for pathfinding
      let dummyFleet = Fleet(
        id: FleetId(999999), # Temporary ID for pathfinding
        houseId: houseId,
        location: fromSystem,
        squadrons: @[],
        status: FleetStatus.Active,
      )

      # Note: findPath requires squadrons and ships parameters
      let pathResult = findPath(state.starMap, fromSystem, systemId, dummyFleet, state.squadrons[], state.ships)
      if pathResult.path.len > 0:
        let distance = pathResult.path.len - 1 # Number of jumps

        # Calculate path risk using fog-of-war intel
        let risk = estimatePathRisk(state, pathResult.path, houseId)

        # Score combines distance and risk
        # Risk is weighted heavily (x3) to strongly prefer safer routes
        # But will accept risky routes if they're much shorter
        let score = distance + (risk * 3)

        if score < bestScore:
          bestScore = score
          bestColony = some(systemId)

  return bestColony

proc shouldAutoSeekHome*(state: GameState, fleet: Fleet, command: FleetCommand): bool =
  ## Determine if a fleet should automatically seek home due to dangerous situation
  ## NOTE: Retreat behavior is primarily controlled by ROE (Rules of Engagement)
  ## per 06-operations.md:6.5.10. This function checks for mission-critical aborts only.
  ##
  ## Auto-abort conditions:
  ## - ETAC missions where destination becomes enemy-controlled
  ## - Guard/blockade orders where target is lost or captured
  ## - Patrol missions in now-hostile territory

  # Check if fleet is executing an order that becomes invalid due to hostility
  case command.commandType
  of FleetCommandType.Colonize:
    # ETAC missions abort if destination becomes enemy-controlled
    if command.targetSystem.isSome:
      let targetId = command.targetSystem.get()
      if isSystemHostile(state, targetId, fleet.houseId):
        return true
  of FleetCommandType.GuardStarbase, FleetCommandType.GuardColony,
      FleetCommandType.Blockade:
    # Guard/blockade orders abort if system lost to enemy
    if command.targetSystem.isSome:
      let targetId = command.targetSystem.get()
      if state.colonies.bySystem.hasKey(targetId):
        let colonyId = state.colonies.bySystem[targetId]
        let colonyOpt = state.colonies.entities.entity(colonyId)
        if colonyOpt.isSome:
          let colony = colonyOpt.get()
          # If colony ownership changed to enemy, abort
          if colony.owner != fleet.houseId:
            let key = (fleet.houseId, colony.owner)
            if state.diplomaticRelation.hasKey(key):
              if state.diplomaticRelation[key].state == DiplomaticState.Enemy:
                return true
      else:
        # Colony destroyed - abort
        return true
  of FleetCommandType.Patrol:
    # Patrols abort if their patrol zone becomes enemy territory
    # Check if current location is hostile
    if state.colonies.bySystem.hasKey(fleet.location):
      let colonyId = state.colonies.bySystem[fleet.location]
      let colonyOpt = state.colonies.entities.entity(colonyId)
      if colonyOpt.isSome:
        let colony = colonyOpt.get()
        if colony.owner != fleet.houseId:
          let key = (fleet.houseId, colony.owner)
          if state.diplomaticRelation.hasKey(key):
            if state.diplomaticRelation[key].state == DiplomaticState.Enemy:
              return true

    # Also check if patrol target destination is hostile
    if command.targetSystem.isSome:
      let targetId = command.targetSystem.get()
      if isSystemHostile(state, targetId, fleet.houseId):
        return true
  else:
    discard

  return false

var movementCallDepth {.global.} = 0

# =============================================================================
# Spy Scout Movement Support
# =============================================================================

# =============================================================================
# Movement Resolution
# =============================================================================

proc resolveMovementCommand*(
    state: var GameState,
    houseId: HouseId,
    command: FleetCommand,
    events: var seq[GameEvent],
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
    logError(
      "Fleet",
      "resolveMovementCommand recursion depth > 100! Infinite loop detected!",
    )
    quit(1)

  defer:
    movementCallDepth -= 1

  if command.targetSystem.isNone:
    return

  # Get fleet
  let fleetOpt = state.fleets.entities.entity(command.fleetId)
  if fleetOpt.isNone:
    return
  var fleet = fleetOpt.get()

  # Reserve and Mothballed fleets cannot move (permanently stationed at colony)
  # Per operations.md: Both statuses represent fleets that are station-keeping
  # - Reserve: 50% maintenance, reduced combat, can fight in orbital defense
  # - Mothballed: 0% maintenance, must be screened, risks destruction in combat
  if fleet.status == FleetStatus.Reserve or fleet.status == FleetStatus.Mothballed:
    logWarn(
      "Fleet",
      &"Fleet {command.fleetId} cannot move - status: {fleet.status} (permanently stationed)",
    )
    return

  let targetId = command.targetSystem.get()
  let startId = fleet.location

  # Already at destination - clear order (arrival complete)
  if startId == targetId:
    logDebug(
      "Fleet",
      &"Fleet {command.fleetId} arrived at destination, order complete",
    )
    # Generate OrderCompleted event - cleanup handled by Command Phase
    events.add(
      event_factory.commandCompleted(
        houseId,
        command.fleetId,
        "Move",
        details = &"arrived at {targetId}",
        systemId = some(targetId),
      )
    )
    return

  logDebug(
    "Fleet", &"Fleet {command.fleetId} moving from {startId} to {targetId}"
  )

  # Find path to destination (operations.md:6.1)
  let pathResult = findPath(state.starMap, startId, targetId, fleet, state.squadrons[], state.ships)

  if not pathResult.found:
    logWarn(
      "Fleet",
      &"Fleet {command.fleetId}: No valid path found (blocked by restricted lanes or terrain)",
    )
    return

  if pathResult.path.len < 2:
    logError("Fleet", &"Fleet {command.fleetId}: Invalid path")
    return

  # Determine how many jumps the fleet can make this turn
  var jumpsAllowed = 1 # Default: 1 jump per turn

  # Check if we can do 2 major lane jumps (operations.md:6.1)
  if pathResult.path.len >= 3:
    # Check if all systems along path are owned by this house
    var allSystemsOwned = true
    for systemId in pathResult.path:
      if not state.colonies.bySystem.hasKey(systemId):
        allSystemsOwned = false
        break
      let colonyId = state.colonies.bySystem[systemId]
      let colonyOpt = state.colonies.entities.entity(colonyId)
      if colonyOpt.isNone or colonyOpt.get().owner != houseId:
        allSystemsOwned = false
        break

    # Check if next two jumps are both major lanes
    var nextTwoAreMajor = true
    if allSystemsOwned:
      for i in 0 ..< min(2, pathResult.path.len - 1):
        let fromSys = pathResult.path[i]
        let toSys = pathResult.path[i + 1]

        # Get lane type between these systems using connectionInfo
        let laneClass = state.starMap.lanes.connectionInfo.getOrDefault(
          (fromSys, toSys), LaneClass.Minor
        )

        if laneClass != LaneClass.Major:
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
  state.fleets.entities.updateEntity(command.fleetId, fleet)

  # Generate OrderCompleted event for fleet movement
  let moveDetails =
    if newLocation == targetId:
      &"arrived at {targetId}"
    else:
      &"moved from {startId} to {newLocation} ({actualJumps} jump(s))"

  events.add(
    event_factory.commandCompleted(
      houseId,
      command.fleetId,
      "Move",
      details = moveDetails,
      systemId = some(newLocation),
    )
  )

  # Check if we've arrived at final destination (N+1 behavior)
  # Event generated above, cleanup handled by Command Phase
  if newLocation == targetId:
    logInfo(
      "Fleet",
      &"Fleet {command.fleetId} arrived at destination {targetId}, order complete",
    )

    # Check if this fleet is on a spy mission and start mission on arrival
    if fleet.missionState == FleetMissionState.Traveling:
      fleet.missionState = FleetMissionState.OnSpyMission
      fleet.missionStartTurn = state.turn

      let scoutCount = int32(fleet.squadrons.len)

      # Register active mission
      state.activeSpyMissions[command.fleetId] = ActiveSpyMission(
        fleetId: command.fleetId,
        missionType: SpyMissionType(fleet.missionType.get()),
        targetSystem: fleet.location,
        scoutCount: scoutCount,
        startTurn: state.turn,
        ownerHouse: fleet.houseId,
      )

      # Update fleet in state
      state.fleets.entities.updateEntity(command.fleetId, fleet)

      # Generate mission start event
      let missionName =
        case SpyMissionType(fleet.missionType.get())
        of SpyMissionType.SpyOnPlanet: "spy mission"
        of SpyMissionType.HackStarbase: "starbase hack"
        of SpyMissionType.SpyOnSystem: "system reconnaissance"

      events.add(
        event_factory.commandCompleted(
          houseId,
          command.fleetId,
          "SpyMissionStarted",
          details = &"{missionName} started at {targetId} ({scoutCount} scouts)",
          systemId = some(targetId),
        )
      )

      logInfo(
        "Fleet",
        &"Fleet {command.fleetId} spy mission started at {targetId}",
      )
  else:
    logInfo(
      "Fleet",
      &"Fleet {command.fleetId} moved {actualJumps} jump(s) to system {newLocation}",
    )

  # Automatic intelligence gathering when arriving at system
  # ANY fleet presence reveals enemy colonies (passive reconnaissance)
  if state.colonies.bySystem.hasKey(newLocation):
    let colonyId = state.colonies.bySystem[newLocation]
    let colonyOpt = state.colonies.entities.entity(colonyId)
    if colonyOpt.isSome:
      let colony = colonyOpt.get()
      if colony.owner != houseId:
        # Generate basic intelligence report on enemy colony
        let intelReport = generateColonyIntelReport(
          state, houseId, newLocation, IntelQuality.Visual
        )
        if intelReport.isSome:
          var intel = state.intelligence[houseId]
          intel.colonyReports[colonyId] = intelReport.get()
          state.intelligence[houseId] = intel
          logInfo(
            "Fleet",
            &"Fleet {command.fleetId} ({houseId}) gathered intelligence on enemy colony at {newLocation} (owner: {colony.owner}) - DB now has {intel.colonyReports.len} reports",
          )
        else:
          logWarn(
            "Fleet",
            &"Fleet {command.fleetId} ({houseId}) failed to generate intel report for enemy colony at {newLocation}",
          )

  # Check for fleet encounters at destination
  # Note: Scout-only fleets are excluded from combat by combat resolution system
  var enemyFleetsAtLocation: seq[FleetId] = @[]

  for otherFleet in state.fleetsInSystem(newLocation):
    if otherFleet.id != command.fleetId and otherFleet.houseId != houseId:
      logInfo(
        "Fleet",
        &"Fleet {command.fleetId} encountered fleet {otherFleet.id} ({otherFleet.houseId}) at {newLocation}",
      )
      enemyFleetsAtLocation.add(otherFleet.id)

  # Generate fleet encounter event (Phase 7b)
  if enemyFleetsAtLocation.len > 0:
    # Get diplomatic relation
    let firstEnemyFleetOpt = state.fleets.entities.entity(enemyFleetsAtLocation[0])
    var diplomaticStatus = "neutral"
    if firstEnemyFleetOpt.isSome:
      let enemyHouseId = firstEnemyFleetOpt.get().houseId
      let key = (houseId, enemyHouseId)
      if state.diplomaticRelation.hasKey(key):
        diplomaticStatus = $state.diplomaticRelation[key].state

    events.add(
      event_factory.fleetEncounter(
        houseId, command.fleetId, enemyFleetsAtLocation, diplomaticStatus, newLocation
      )
    )

    # Automatic fleet intelligence gathering - detected enemy fleets
    if enemyFleetsAtLocation.len > 0:
      let systemIntelReport = generateSystemIntelReport(
        state, houseId, newLocation, IntelQuality.Visual
      )
      if systemIntelReport.isSome:
        if not state.intelligence.hasKey(houseId):
          state.intelligence[houseId] = IntelligenceDatabase(
            houseId: houseId,
            colonyReports: initTable[ColonyId, ColonyIntelReport](),
            orbitalReports: initTable[ColonyId, OrbitalIntelReport](),
            systemReports: initTable[SystemId, SystemIntelReport](),
            starbaseReports: initTable[StarbaseId, StarbaseIntelReport](),
            fleetIntel: initTable[FleetId, FleetIntel](),
            squadronIntel: initTable[SquadronId, SquadronIntel](),
            fleetMovementHistory: initTable[FleetId, FleetMovementHistory](),
            constructionActivity: initTable[ColonyId, ConstructionActivityReport](),
            populationTransferStatus: initTable[PopulationTransferId, PopulationTransferStatusReport](),
          )
        var intel = state.intelligence[houseId]
        let package = systemIntelReport.get()
        intel.systemReports[newLocation] = package.report
        # Also store fleet and squadron intel from the package
        for (fleetId, fleetIntel) in package.fleetIntel:
          intel.fleetIntel[fleetId] = fleetIntel
        for (squadronId, squadronIntel) in package.squadronIntel:
          intel.squadronIntel[squadronId] = squadronIntel
        state.intelligence[houseId] = intel
        logDebug(
          "Fleet",
          &"Fleet {command.fleetId} gathered intelligence on {enemyFleetsAtLocation.len} enemy fleet(s) at {newLocation}",
        )

    # Combat will be resolved in conflict phase next turn
    # This just logs the encounter

proc resolveColonizationCommand*(
    state: var GameState,
    houseId: HouseId,
    command: FleetCommand,
    events: var seq[GameEvent],
) =
  ## Establish a new colony with prestige rewards
  if command.targetSystem.isNone:
    return

  let targetId = command.targetSystem.get()

  # Check if system already colonized
  if state.colonies.bySystem.hasKey(targetId):
    let colonyId = state.colonies.bySystem[targetId]
    let colonyOpt = state.colonies.entities.entity(colonyId)
    if colonyOpt.isNone:
      return
    let colony = colonyOpt.get()

    # ORBITAL INTELLIGENCE GATHERING
    # Fleet approaching colony for colonization/guard/blockade gets close enough to see orbital defenses
    if colony.owner != houseId:
      # Generate detailed colony intel including orbital defenses
      let colonyIntel = generateColonyIntelReport(
        state, houseId, targetId, IntelQuality.Visual
      )
      if colonyIntel.isSome:
        let colonyId = state.colonies.bySystem[targetId]
        var intel = state.intelligence[houseId]
        intel.colonyReports[colonyId] = colonyIntel.get()
        state.intelligence[houseId] = intel
        logDebug(
          "Fleet",
          &"Fleet {command.fleetId} gathered orbital intelligence on enemy colony at {targetId}",
        )

      # Also gather system intel on any fleets present (including guard/reserve fleets)
      let systemIntel = generateSystemIntelReport(
        state, houseId, targetId, IntelQuality.Visual
      )
      if systemIntel.isSome:
        if not state.intelligence.hasKey(houseId):
          state.intelligence[houseId] = IntelligenceDatabase(
            houseId: houseId,
            colonyReports: initTable[ColonyId, ColonyIntelReport](),
            orbitalReports: initTable[ColonyId, OrbitalIntelReport](),
            systemReports: initTable[SystemId, SystemIntelReport](),
            starbaseReports: initTable[StarbaseId, StarbaseIntelReport](),
            fleetIntel: initTable[FleetId, FleetIntel](),
            squadronIntel: initTable[SquadronId, SquadronIntel](),
            fleetMovementHistory: initTable[FleetId, FleetMovementHistory](),
            constructionActivity: initTable[ColonyId, ConstructionActivityReport](),
            populationTransferStatus: initTable[PopulationTransferId, PopulationTransferStatusReport](),
          )
        var intel = state.intelligence[houseId]
        let package = systemIntel.get()
        intel.systemReports[targetId] = package.report
        # Also store fleet and squadron intel from the package
        for (fleetId, fleetIntel) in package.fleetIntel:
          intel.fleetIntel[fleetId] = fleetIntel
        for (squadronId, squadronIntel) in package.squadronIntel:
          intel.squadronIntel[squadronId] = squadronIntel
        state.intelligence[houseId] = intel

    logWarn(
      "Colonization",
      &"Fleet {command.fleetId}: System {targetId} already colonized by {colony.owner}",
    )
    return

  let fleetOpt = state.fleets.entities.entity(command.fleetId)
  if fleetOpt.isNone:
    return

  # Check system exists
  if state.systems.entities.entity(targetId).isNone:
    logError(
      "Colonization",
      &"Fleet {command.fleetId}: System {targetId} not found",
    )
    return

  var fleet = fleetOpt.get()

  # If fleet not at target, move there first
  if fleet.location != targetId:
    logDebug(
      "Colonization",
      &"Fleet {command.fleetId} not at target - moving from {fleet.location} to {targetId}",
    )
    # Create temporary movement order to get fleet to destination
    let moveOrder = FleetCommand(
      fleetId: command.fleetId,
      commandType: FleetCommandType.Move,
      targetSystem: some(targetId),
    )
    logDebug(
      "Colonization",
      &"Calling resolveMovementCommand for fleet {command.fleetId}",
    )
    resolveMovementCommand(state, houseId, moveOrder, events)
    logDebug(
      "Colonization",
      &"resolveMovementCommand returned for fleet {command.fleetId}",
    )

    # Reload fleet after movement
    let movedFleetOpt = state.fleets.entities.entity(command.fleetId)
    if movedFleetOpt.isNone:
      return
    fleet = movedFleetOpt.get()

    # Check if fleet reached destination (might be multiple jumps away)
    if fleet.location != targetId:
      logWarn(
        "Colonization",
        &"Fleet {command.fleetId} still not at target after movement (too far)",
      )
      return

  # Check fleet has colonists (assumes ETAC ships carry colonists)
  # Simplified check: any squadron in fleet is assumed to have colonists
  # TODO: Implement proper cargo tracking when cargo system is complete
  var hasColonists = fleet.squadrons.len > 0

  if not hasColonists:
    logError(
      "Colonization",
      &"Fleet {command.fleetId} has no colonists (PTU) - colonization failed",
    )
    return

  # Establish colony using system's actual planet properties
  # Get system to determine planet class and resources
  let systemOpt = state.systems.entities.entity(targetId)
  if systemOpt.isNone:
    logError("Colonization", &"System {targetId} not found in entity manager")
    return
  let system = systemOpt.get()
  let planetClass = system.planetClass
  let resources = system.resourceRating

  # Get PTU quantity from ETAC cargo (default: 3 PTU per ETAC)
  # TODO: Implement proper cargo tracking when cargo system is complete
  var ptuToDeposit = 3  # Standard ETAC carries 3 PTU

  logInfo(
    "Colonization",
    &"Fleet {command.fleetId} colonizing {planetClass} world with {resources} resources at {targetId} (depositing {ptuToDeposit} PTU)",
  )

  # Establish colony using entity operations
  let colonyId = colony_ops.establishColony(
    state,
    targetId,
    houseId,
    planetClass,
    resources,
    int32(ptuToDeposit),
  )

  logInfo(
    "Colonization",
    &"Colony {colonyId} established at {targetId} with {ptuToDeposit} PTU"
  )

  # TODO: Unload colonists from Expansion squadron cargo when cargo system is complete
  # TODO: ETAC cannibalization - remove ETAC from fleet after colonization
  # TODO: Apply prestige award for colonization

  # Generate colonization event
  events.add(event_factory.colonyEstablished(houseId, targetId, 0))

  # Generate OrderCompleted event for successful colonization
  # Cleanup handled by Command Phase
  events.add(
    event_factory.commandCompleted(
      houseId,
      command.fleetId,
      "Colonize",
      details = &"established colony at {targetId}",
      systemId = some(targetId),
    )
  )

  logDebug(
    "Colonization",
    &"Fleet {command.fleetId} colonization complete, cleanup deferred to Command Phase",
  )

proc resolveViewWorldCommand*(
    state: var GameState,
    houseId: HouseId,
    command: FleetCommand,
    events: var seq[GameEvent],
) =
  ## Perform long-range planetary reconnaissance (Order 19)
  ## Ship approaches system edge, scans planet, retreats to deep space
  ## Gathers: planet owner (if colonized) and planet class (production potential)
  if command.targetSystem.isNone:
    return

  let targetId = command.targetSystem.get()

  # Get fleet using entity pattern
  let fleetOpt = state.fleets.entities.entity(command.fleetId)
  if fleetOpt.isNone:
    return
  let fleet = fleetOpt.get()

  if fleet.location != targetId:
    # Not at target yet, continue moving
    return

  # Get house using entity pattern
  let houseOpt = state.houses.entities.entity(houseId)
  if houseOpt.isNone:
    return
  let house = houseOpt.get()

  # Gather intel on planet
  if state.colonies.bySystem.hasKey(targetId):
    let colonyId = state.colonies.bySystem[targetId]
    let colonyOpt = state.colonies.entities.entity(colonyId)
    if colonyOpt.isNone:
      return
    let colony = colonyOpt.get()

    # Create minimal colony intel report from long-range scan
    # ViewWorld only gathers: owner + planet class (no detailed statistics)
    let intelReport = ColonyIntelReport(
      colonyId: colonyId,
      targetOwner: colony.owner,
      gatheredTurn: state.turn,
      quality: IntelQuality.Scan, # Long-range scan quality
      # Colony stats: minimal info from long-range scan
      population: 0, # Unknown from long range
      infrastructure: 0, # Unknown from long range
      groundBatteryCount: 0, # Unknown from long range
    )

    # Store intel in state.intelligence
    if not state.intelligence.hasKey(houseId):
      state.intelligence[houseId] = IntelligenceDatabase(
        houseId: houseId,
        colonyReports: initTable[ColonyId, ColonyIntelReport](),
        orbitalReports: initTable[ColonyId, OrbitalIntelReport](),
        systemReports: initTable[SystemId, SystemIntelReport](),
        starbaseReports: initTable[StarbaseId, StarbaseIntelReport](),
        fleetIntel: initTable[FleetId, FleetIntel](),
        squadronIntel: initTable[SquadronId, SquadronIntel](),
        fleetMovementHistory: initTable[FleetId, FleetMovementHistory](),
        constructionActivity: initTable[ColonyId, ConstructionActivityReport](),
        populationTransferStatus: initTable[
          PopulationTransferId, PopulationTransferStatusReport
        ](),
      )
    var intel = state.intelligence[houseId]
    intel.colonyReports[colonyId] = intelReport
    state.intelligence[houseId] = intel

    logInfo(
      "Fleet",
      &"{house.name} viewed world at {targetId}: Owner={colony.owner}, Class={colony.planetClass}",
    )
  else:
    # Uncolonized system - no intel report needed
    # Just log that we found an uncolonized system
    if state.systems.entities.entity(targetId).isSome:
      logInfo(
        "Fleet", &"{house.name} viewed uncolonized system at {targetId}"
      )

  # Generate event - use viewing house as target since ViewWorld scans neutral systems
  events.add(
    event_factory.intelGathered(
      houseId,
      houseId, # ViewWorld doesn't target a specific house, use self
      targetId,
      "long-range planetary scan",
    )
  )

  # Generate OrderCompleted event for successful scan
  var scanDetails: string
  if state.colonies.bySystem.hasKey(targetId):
    let colonyId = state.colonies.bySystem[targetId]
    let colonyOpt = state.colonies.entities.entity(colonyId)
    if colonyOpt.isSome:
      let colony = colonyOpt.get()
      scanDetails = &"scanned {targetId} (owner: {colony.owner})"
    else:
      scanDetails = &"scanned uncolonized system {targetId}"
  else:
    scanDetails = &"scanned uncolonized system {targetId}"

  events.add(
    event_factory.commandCompleted(
      houseId,
      command.fleetId,
      "ViewWorld",
      details = scanDetails,
      systemId = some(targetId),
    )
  )

  # Order completes - fleet remains at system (player must issue new orders)
  # NOTE: Fleet is in deep space, not orbit, so no orbital combat triggered
  # Cleanup handled by Command Phase

proc autoLoadCargo*(
    state: var GameState,
    orders: Table[HouseId, CommandPacket],
    events: var seq[GameEvent],
) =
  ## Automatically load available marines/colonists onto empty transports at colonies
  ## NOTE: Manual cargo operations now use zero-turn commands (executed before turn resolution)
  ## This auto-load only processes fleets that weren't manually managed

  # TODO: Cargo system needs refactoring
  # Current implementation requires complex mutable fleet/squadron manipulation
  # that doesn't work well with entity pattern
  # Defer to future cargo system implementation per architecture.md

  # Process each colony
  for colony in state.allColonies():
    let systemId = colony.systemId

    # Find fleets at this colony
    for fleet in state.fleetsInSystem(systemId):
      if fleet.houseId != colony.owner:
        continue

      # TODO: Auto-load cargo functionality needs proper cargo system
      # For now, skip auto-loading until cargo system is implemented
      # See mechanics.nim colonization for similar deferral

      discard # Placeholder for future cargo system integration
