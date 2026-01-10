## Fleet movement, colonization, and seek home operations
##
## This module handles all fleet command resolution including:
## - Fleet movement with pathfinding and lane traversal rules
## - Colonization commands and new colony establishment
## - Automated Seek Home behavior for stranded fleets
## - Helper functions for path finding and hostility detection

import std/[tables, options, sequtils, strformat]
import ../../../common/logger
import ../../types/[
  core, game_state, command, fleet, event, diplomacy,
  intel, starmap, ship, prestige, colony, ground_unit, combat
]
import ../../state/[engine, iterators, fleet_queries]
import ../../globals # For gameConfig
import ../ship/entity # Ship helper functions
import ../../entities/[colony_ops, fleet_ops, ship_ops]
import ../../prestige/engine
import ../../event_factory/init
import ../../intel/generator
import ../../utils # For soulsPerPtu
import ./movement # For findPath
import ./entity

proc completeFleetCommand*(
    state: GameState,
    fleetId: FleetId,
    orderType: string,
    details: string = "",
    systemId: Option[SystemId] = none(SystemId),
    events: var seq[GameEvent],
) =
  ## Standard completion handler: generates OrderCompleted event
  ## Cleanup handled by event-driven order_cleanup module in Command Phase
  let fleetOpt = state.fleet(fleetId)
  if fleetOpt.isNone:
    return
  let houseId = fleetOpt.get().houseId

  events.add(
    commandCompleted(houseId, fleetId, orderType, details, systemId)
  )

  logInfo("Orders", &"Fleet {fleetId} {orderType} command completed")

proc isSystemHostile*(state: GameState, systemId: SystemId, houseId: HouseId): bool =
  ## Check if a system is hostile to a house based on known intel (fog-of-war)
  ## System is hostile if player KNOWS it contains:
  ## 1. Enemy colony (from intelligence database or visibility)
  ## 2. Enemy fleets (from intelligence database or visibility)
  ## IMPORTANT: This respects fog-of-war - only uses information available to the house

  let houseOpt = state.house(houseId)
  if houseOpt.isNone:
    return false

  # Check if system has enemy colony (visible or from intel database)
  let colonyOpt = state.colonyBySystem(systemId)
  if colonyOpt.isSome:
    let colony = colonyOpt.get()
    if colony.owner != houseId:
      # Check diplomatic status
      let key = (houseId, colony.owner)
      if state.diplomaticRelation.hasKey(key):
        if state.diplomaticRelation[key].state == DiplomaticState.Enemy:
          # Player can see this colony - it's hostile
          return true

  # TODO: Fix intelligence access - state.intel field doesn't exist
  # Intelligence system has been refactored, need to use correct API
  # This is a pre-existing bug, not introduced by CombatState refactoring
  # Check intelligence database for known enemy colonies
  # if state.intel.hasKey(houseId):
  #   let intel = state.intel[houseId]
  #   for colonyId, colonyIntel in intel.colonyReports:
  #     let colonyOpt = state.colony(colonyId)
  #     if colonyOpt.isSome:
  #       let colony = colonyOpt.get()
  #       if colony.systemId == systemId and colony.owner != houseId:
  #         let key = (houseId, colony.owner)
  #         if state.diplomaticRelation.hasKey(key):
  #           if state.diplomaticRelation[key].state == DiplomaticState.Enemy:
  #             return true

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
    else:
      let colonyOpt = state.colonyBySystem(systemId)
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
  ##
  ## FUTURE ENHANCEMENT: Strategic Retreat Planning (fallbackRoutes)
  ## ================================================================
  ## Per operations spec (06-operations.md), fleets use Seek Home command to retreat
  ## to nearest friendly colony with drydock facilities. The automatic fallback calculation
  ## balances distance and risk using fog-of-war information.
  ##
  ## A future enhancement would allow players to pre-define strategic retreat routes
  ## that override the automatic calculation:
  ##
  ## House Type Extension:
  ##   type FallbackRoute = object
  ##     region*: SystemId           ## Source region for this route
  ##     fallbackSystem*: SystemId   ## Designated safe harbor
  ##     lastUpdated*: int32         ## Turn when route was defined
  ##
  ##   type House = object
  ##     ...
  ##     fallbackRoutes*: seq[FallbackRoute]
  ##
  ## Implementation Logic (currently commented out):
  ##   - Check if house has pre-defined route for this region
  ##   - Verify route is recent (updated within 20 turns)
  ##   - Confirm fallback system still has friendly colony
  ##   - Return pre-defined route instead of automatic calculation
  ##
  ## Benefits:
  ##   - Players can plan retreat corridors in advance
  ##   - Avoid retreating into hostile territory
  ##   - Coordinate defensive fallback positions
  ##   - Strategic depth for defensive operations
  ##
  ## Current Status: Not implemented (House type lacks fallbackRoutes field)

  # Commented out pending House type extension:
  # let houseOpt = state.house(houseId)
  # if houseOpt.isSome:
  #   let house = houseOpt.get()
  #   for route in house.fallbackRoutes:
  #     if route.region == fromSystem and state.turn - route.lastUpdated < 20:
  #       if state.colonies.bySystem.hasKey(route.fallbackSystem):
  #         let colonyId = state.colonies.bySystem[route.fallbackSystem]
  #         let colonyOpt = state.colonie(colonyId)
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
      let dummyFleet = fleet_ops.newFleet(
        shipIds = @[],
        id = FleetId(999999), # Temporary ID for pathfinding
        owner = houseId,
        location = fromSystem,
        status = FleetStatus.Active,
      )

      # Use movement.nim findPath with full GameState
      let pathResult = movement.findPath(state, fromSystem, systemId, dummyFleet)
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
  ## - Guard/blockade commands where target is lost or captured
  ## - Patrol missions in now-hostile territory

  # Check if fleet is executing an command that becomes invalid due to hostility
  case command.commandType
  of FleetCommandType.Colonize:
    # ETAC missions abort if destination becomes enemy-controlled
    if command.targetSystem.isSome:
      let targetId = command.targetSystem.get()
      if isSystemHostile(state, targetId, fleet.houseId):
        return true
  of FleetCommandType.GuardStarbase, FleetCommandType.GuardColony,
      FleetCommandType.Blockade:
    # Guard/blockade commands abort if system lost to enemy
    if command.targetSystem.isSome:
      let targetId = command.targetSystem.get()
      let colonyOpt = state.colonyBySystem(targetId)
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
    let colonyOpt = state.colonyBySystem(fleet.location)
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
# Movement Resolution
# =============================================================================

proc resolveMovementCommand*(
    state: GameState,
    houseId: HouseId,
    command: FleetCommand,
    events: var seq[GameEvent],
) =
  ## Execute a fleet movement command with pathfinding and lane traversal rules
  ## Per operations.md:6.1 - Lane traversal rules:
  ##   - Major lanes: 2 jumps per turn if all systems owned by player
  ##   - Major lanes: 1 jump per turn if jumping into unexplored/rival system
  ##   - Minor/Restricted lanes: 1 jump per turn maximum
  ##   - Restricted lanes: ONLY non-crippled ETACs allowed (combat ships blocked)

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
  let fleetOpt = state.fleet(command.fleetId)
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

  # Already at destination - clear command (arrival complete)
  if startId == targetId:
    logDebug(
      "Fleet",
      &"Fleet {command.fleetId} arrived at destination, command complete",
    )
    # Generate OrderCompleted event - cleanup handled by Command Phase
    events.add(
      commandCompleted(
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
  let pathResult = movement.findPath(state, startId, targetId, fleet)

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
      let colonyOpt = state.colonyBySystem(systemId)
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
  state.updateFleet(command.fleetId, fleet)

  # Generate OrderCompleted event for fleet movement
  let moveDetails =
    if newLocation == targetId:
      &"arrived at {targetId}"
    else:
      &"moved from {startId} to {newLocation} ({actualJumps} jump(s))"

  events.add(
    commandCompleted(
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
      &"Fleet {command.fleetId} arrived at destination {targetId}, command complete",
    )

    # Check if this fleet is on a scout mission and start mission on arrival
    if fleet.missionState == MissionState.Traveling:
      fleet.missionState = MissionState.ScoutLocked
      fleet.missionStartTurn = state.turn

      let scoutCount = state.countScoutShips(fleet)

      # Register active mission

      # Update fleet in state
      state.updateFleet(command.fleetId, fleet)

      # Generate mission start event
      let missionName =
        case command.commandType
        of FleetCommandType.ScoutColony: "scout mission"
        of FleetCommandType.HackStarbase: "starbase hack"
        of FleetCommandType.ScoutSystem: "system reconnaissance"
        else: "unknown mission"

      events.add(
        commandCompleted(
          houseId,
          command.fleetId,
          "SpyMissionStarted",
          details = &"{missionName} started at {targetId} ({scoutCount} scouts)",
          systemId = some(targetId),
        )
      )

      logInfo(
        "Fleet",
        &"Fleet {command.fleetId} scout mission started at {targetId}",
      )
  else:
    logInfo(
      "Fleet",
      &"Fleet {command.fleetId} moved {actualJumps} jump(s) to system {newLocation}",
    )

  # Automatic intelligence gathering when arriving at system
  # ANY fleet presence reveals enemy colonies (passive reconnaissance)
  let colonyOpt = state.colonyBySystem(newLocation)
  if colonyOpt.isSome:
      let colony = colonyOpt.get()
      if colony.owner != houseId:
        # Generate basic intelligence report on enemy colony
        let intelReport = generateColonyIntelReport(
          state, houseId, newLocation, IntelQuality.Visual
        )
        if intelReport.isSome:
          let colonyId = colony.id # Needed for intel.colonyReports
          var intel = state.intel[houseId]
          intel.colonyReports[colonyId] = intelReport.get()
          state.intel[houseId] = intel
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
    let firstEnemyFleetOpt = state.fleet(enemyFleetsAtLocation[0])
    var diplomaticStatus = "neutral"
    if firstEnemyFleetOpt.isSome:
      let enemyHouseId = firstEnemyFleetOpt.get().houseId
      let key = (houseId, enemyHouseId)
      if state.diplomaticRelation.hasKey(key):
        diplomaticStatus = $state.diplomaticRelation[key].state

    events.add(
      fleetEncounter(
        houseId, command.fleetId, enemyFleetsAtLocation, diplomaticStatus, newLocation
      )
    )

    # Automatic fleet intelligence gathering - detected enemy fleets
    if enemyFleetsAtLocation.len > 0:
      let systemIntelReport = generateSystemIntelReport(
        state, houseId, newLocation, IntelQuality.Visual
      )
      if systemIntelReport.isSome:
        if not state.intel.hasKey(houseId):
          state.intel[houseId] = IntelDatabase(
            houseId: houseId,
            colonyReports: initTable[ColonyId, ColonyIntelReport](),
            orbitalReports: initTable[ColonyId, OrbitalIntelReport](),
            systemReports: initTable[SystemId, SystemIntelReport](),
            starbaseReports: initTable[KastraId, StarbaseIntelReport](),
            fleetIntel: initTable[FleetId, FleetIntel](),
            shipIntel: initTable[ShipId, ShipIntel](),
            fleetMovementHistory: initTable[FleetId, FleetMovementHistory](),
            constructionActivity: initTable[ColonyId, ConstructionActivityReport](),
            populationTransferStatus: initTable[PopulationTransferId, PopulationTransferStatusReport](),
          )
        var intel = state.intel[houseId]
        let package = systemIntelReport.get()
        intel.systemReports[newLocation] = package.report
        # Also store fleet and ship intel from the package
        for (fleetId, fleetIntel) in package.fleetIntel:
          intel.fleetIntel[fleetId] = fleetIntel
        for (shipId, shipIntel) in package.shipIntel:
          intel.shipIntel[shipId] = shipIntel
        state.intel[houseId] = intel
        logDebug(
          "Fleet",
          &"Fleet {command.fleetId} gathered intelligence on {enemyFleetsAtLocation.len} enemy fleet(s) at {newLocation}",
        )

    # Combat will be resolved in conflict phase next turn
    # This just logs the encounter

proc resolveColonizationCommand*(
    state: GameState,
    houseId: HouseId,
    command: FleetCommand,
    events: var seq[GameEvent],
) =
  ## Establish a new colony with prestige rewards
  if command.targetSystem.isNone:
    return

  let targetId = command.targetSystem.get()

  # Check if system already colonized
  let colonyOpt = state.colonyBySystem(targetId)
  if colonyOpt.isSome:
    let colony = colonyOpt.get()

    # ORBITAL INTELLIGENCE GATHERING
    # Fleet approaching colony for colonization/guard/blockade gets close enough to see orbital defenses
    if colony.owner != houseId:
      # Generate detailed colony intel including orbital defenses
      let colonyIntel = generateColonyIntelReport(
        state, houseId, targetId, IntelQuality.Visual
      )
      if colonyIntel.isSome:
        let colonyId = colony.id
        var intel = state.intel[houseId]
        intel.colonyReports[colonyId] = colonyIntel.get()
        state.intel[houseId] = intel
        logDebug(
          "Fleet",
          &"Fleet {command.fleetId} gathered orbital intelligence on enemy colony at {targetId}",
        )

      # Also gather system intel on any fleets present (including guard/reserve fleets)
      let systemIntel = generateSystemIntelReport(
        state, houseId, targetId, IntelQuality.Visual
      )
      if systemIntel.isSome:
        if not state.intel.hasKey(houseId):
          state.intel[houseId] = IntelDatabase(
            houseId: houseId,
            colonyReports: initTable[ColonyId, ColonyIntelReport](),
            orbitalReports: initTable[ColonyId, OrbitalIntelReport](),
            systemReports: initTable[SystemId, SystemIntelReport](),
            starbaseReports: initTable[KastraId, StarbaseIntelReport](),
            fleetIntel: initTable[FleetId, FleetIntel](),
            shipIntel: initTable[ShipId, ShipIntel](),
            fleetMovementHistory: initTable[FleetId, FleetMovementHistory](),
            constructionActivity: initTable[ColonyId, ConstructionActivityReport](),
            populationTransferStatus: initTable[PopulationTransferId, PopulationTransferStatusReport](),
          )
        var intel = state.intel[houseId]
        let package = systemIntel.get()
        intel.systemReports[targetId] = package.report
        # Also store fleet and ship intel from the package
        for (fleetId, fleetIntel) in package.fleetIntel:
          intel.fleetIntel[fleetId] = fleetIntel
        for (shipId, shipIntel) in package.shipIntel:
          intel.shipIntel[shipId] = shipIntel
        state.intel[houseId] = intel

    logWarn(
      "Colonization",
      &"Fleet {command.fleetId}: System {targetId} already colonized by {colony.owner}",
    )
    return

  let fleetOpt = state.fleet(command.fleetId)
  if fleetOpt.isNone:
    return

  # Check system exists
  if state.system(targetId).isNone:
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
    # Create temporary movement command to get fleet to destination
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
    let movedFleetOpt = state.fleet(command.fleetId)
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

  # Find ETAC ships with loaded colonists
  var etacShipId: Option[ShipId] = none(ShipId)
  var ptuToDeposit: int32 = 0

  for shipId in fleet.ships:
    let shipOpt = state.ship(shipId)
    if shipOpt.isNone:
      continue

    let ship = shipOpt.get()
    if ship.shipClass != ShipClass.ETAC:
      continue

    # Check if ETAC has colonist cargo
    if ship.cargo.isSome:
      let cargo = ship.cargo.get()
      if cargo.cargoType == CargoClass.Colonists and cargo.quantity > 0:
        etacShipId = some(shipId)
        ptuToDeposit = cargo.quantity
        break # Found ETAC with colonists

  if etacShipId.isNone or ptuToDeposit == 0:
    logError(
      "Colonization",
      &"Fleet {command.fleetId} has no ETAC with colonists (PTU) - colonization failed",
    )
    return

  # Establish colony using system's actual planet properties
  let systemOpt = state.system(targetId)
  if systemOpt.isNone:
    logError("Colonization", &"System {targetId} not found in entity manager")
    return
  let system = systemOpt.get()
  let planetClass = system.planetClass
  let resources = system.resourceRating

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
    ptuToDeposit,
  )

  logInfo(
    "Colonization",
    &"Colony {colonyId} established at {targetId} with {ptuToDeposit} PTU"
  )

  # ETAC cannibalization: Remove ETAC ship from fleet after colonization
  # Per spec: ETAC is consumed to provide colony infrastructure
  let shipId = etacShipId.get()

  # Get current fleet for modification
  var fleetMut = fleet
  fleetMut.ships = fleetMut.ships.filterIt(it != shipId)

  # Update fleet in entity manager
  state.updateFleet(command.fleetId, fleetMut)

  # Destroy ETAC ship (cleans up indexes)
  state.destroyShip(shipId)

  logInfo(
    "Colonization",
    &"ETAC ship {shipId} cannibalized for colony infrastructure"
  )

  # Apply prestige award for colonization
  let basePrestige = gameConfig.prestige.economic.establishColony
  let prestigeAmount = applyPrestigeMultiplier(basePrestige)
  let prestigeEvent = PrestigeEvent(
    source: PrestigeSource.ColonyEstablished,
    amount: prestigeAmount.int32,
    description: "Established colony at system " & $targetId
  )
  applyPrestigeEvent(state, houseId, prestigeEvent)

  # Generate colonization event
  events.add(colonyEstablished(houseId, targetId, 0))

  # Generate OrderCompleted event for successful colonization
  # Cleanup handled by Command Phase
  events.add(
    commandCompleted(
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
    state: GameState,
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
  let fleetOpt = state.fleet(command.fleetId)
  if fleetOpt.isNone:
    return
  let fleet = fleetOpt.get()

  if fleet.location != targetId:
    # Not at target yet, continue moving
    return

  # Get house using entity pattern
  let houseOpt = state.house(houseId)
  if houseOpt.isNone:
    return
  let house = houseOpt.get()

  # Gather intel on planet
  let colonyOpt = state.colonyBySystem(targetId)
  if colonyOpt.isNone:
    return
  let colony = colonyOpt.get()
  let colonyId = colony.id # Needed for intel report

  # Get system for planetClass
  let systemOpt = state.system(targetId)
  if systemOpt.isNone:
    return
  let system = systemOpt.get()

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

  # Store intel in state.intel
  if not state.intel.hasKey(houseId):
    state.intel[houseId] = IntelDatabase(
      houseId: houseId,
      colonyReports: initTable[ColonyId, ColonyIntelReport](),
      orbitalReports: initTable[ColonyId, OrbitalIntelReport](),
      systemReports: initTable[SystemId, SystemIntelReport](),
      starbaseReports: initTable[KastraId, StarbaseIntelReport](),
      fleetIntel: initTable[FleetId, FleetIntel](),
      shipIntel: initTable[ShipId, ShipIntel](),
      fleetMovementHistory: initTable[FleetId, FleetMovementHistory](),
      constructionActivity: initTable[ColonyId, ConstructionActivityReport](),
      populationTransferStatus: initTable[
        PopulationTransferId, PopulationTransferStatusReport
      ](),
    )
  var intel = state.intel[houseId]
  intel.colonyReports[colonyId] = intelReport
  state.intel[houseId] = intel

  logInfo(
    "Fleet",
    &"{house.name} viewed world at {targetId}: Owner={colony.owner}, Class={system.planetClass}",
  )

  # Generate event - use viewing house as target since ViewWorld scans neutral systems
  events.add(
    intelGathered(
      houseId,
      houseId, # ViewWorld doesn't target a specific house, use self
      targetId,
      "long-range planetary scan",
    )
  )

  # Generate OrderCompleted event for successful scan (reuse colonyOpt from above)
  let scanDetails =
    if colonyOpt.isSome:
      let colony = colonyOpt.get()
      &"scanned {targetId} (owner: {colony.owner})"
    else:
      &"scanned uncolonized system {targetId}"

  events.add(
    commandCompleted(
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

proc autoLoadMarines(
    state: GameState,
    fleet: Fleet,
    colony: Colony,
    colonyId: ColonyId,
    events: var seq[GameEvent],
) =
  ## Helper: Auto-load marines from colony garrison onto TroopTransports
  var colonyMut = colony
  var totalLoaded = 0

  # Helper: Count marines in colony
  proc countMarines(col: Colony): int =
    var count = 0
    for unitId in col.groundUnitIds:
      let unitOpt = state.groundUnit(unitId)
      if unitOpt.isSome and unitOpt.get().stats.unitType == GroundClass.Marine:
        count += 1
    return count

  for shipId in fleet.ships:
    if countMarines(colonyMut) == 0:
      break # No more marines to load

    let shipOpt = state.ship(shipId)
    if shipOpt.isNone:
      continue

    var ship = shipOpt.get()
    if ship.state == CombatState.Crippled or ship.shipClass != ShipClass.TroopTransport:
      continue # Only operational TroopTransports carry marines

    # Check cargo capacity
    let currentCargo =
      if ship.cargo.isSome:
        ship.cargo.get()
      else:
        ShipCargo(cargoType: CargoClass.None, quantity: 0, capacity: 0)

    let availableSpace = currentCargo.capacity - currentCargo.quantity
    if availableSpace <= 0:
      continue # Ship full

    # Load marines
    let loadAmount = min(availableSpace, int32(countMarines(colonyMut)))
    if loadAmount > 0:
      var newCargo = currentCargo
      newCargo.cargoType = CargoClass.Marines
      newCargo.quantity += loadAmount
      ship.cargo = some(newCargo)

      # Update ship
      state.updateShip(shipId, ship)

      # Remove marines from colony (remove N marine units from groundUnitIds)
      var marinesToRemove = int(loadAmount)
      var i = colonyMut.groundUnitIds.len - 1
      while marinesToRemove > 0 and i >= 0:
        let unitOpt = state.groundUnit(colonyMut.groundUnitIds[i])
        if unitOpt.isSome and unitOpt.get().stats.unitType == GroundClass.Marine:
          colonyMut.groundUnitIds.delete(i)
          marinesToRemove -= 1
        i -= 1

      totalLoaded += int(loadAmount)

  # Update colony if marines were loaded
  if totalLoaded > 0:
    state.updateColony(colonyId, colonyMut)
    logDebug(
      "AutoLoad", &"Auto-loaded {totalLoaded} marines onto fleet {fleet.id}"
    )

proc autoLoadColonists(
    state: GameState,
    fleet: Fleet,
    colony: Colony,
    colonyId: ColonyId,
    events: var seq[GameEvent],
) =
  ## Helper: Auto-load colonists onto ETACs for expansion missions
  var colonyMut = colony
  var totalLoaded = 0

  # Calculate available PTUs - must keep minimum population per config
  # Using minColonyPopulation from limits.kdl (5000 souls minimum)
  let minSoulsToKeep = gameConfig.limits.populationLimits.minColonyPopulation

  if colonyMut.souls <= minSoulsToKeep:
    return # Cannot load any PTUs

  let availableSouls = colonyMut.souls - minSoulsToKeep
  var availablePTUs = availableSouls div soulsPerPtu()

  for shipId in fleet.ships:
    if availablePTUs <= 0:
      break

    let shipOpt = state.ship(shipId)
    if shipOpt.isNone:
      continue

    var ship = shipOpt.get()
    if ship.state == CombatState.Crippled or ship.shipClass != ShipClass.ETAC:
      continue # Only operational ETACs carry colonists

    # Check cargo capacity
    let currentCargo =
      if ship.cargo.isSome:
        ship.cargo.get()
      else:
        ShipCargo(
          cargoType: CargoClass.None, quantity: 0, capacity: 3
        ) # ETACs carry 3 PTU

    let availableSpace = currentCargo.capacity - currentCargo.quantity
    if availableSpace <= 0:
      continue # Ship full

    # Load colonists (PTUs)
    let loadAmount = min(availableSpace, availablePTUs)
    if loadAmount > 0:
      var newCargo = currentCargo
      newCargo.cargoType = CargoClass.Colonists
      newCargo.quantity += loadAmount
      ship.cargo = some(newCargo)

      # Update ship
      state.updateShip(shipId, ship)

      # Remove colonists from colony
      let soulsToLoad = loadAmount * soulsPerPtu()
      colonyMut.souls -= soulsToLoad
      colonyMut.population = colonyMut.souls div 1_000_000

      totalLoaded += int(loadAmount)
      availablePTUs -= loadAmount

  # Update colony if colonists were loaded
  if totalLoaded > 0:
    state.updateColony(colonyId, colonyMut)
    logDebug("AutoLoad", &"Auto-loaded {totalLoaded} PTU onto fleet {fleet.id}")

proc autoLoadCargo*(
    state: GameState,
    orders: Table[HouseId, CommandPacket],
    events: var seq[GameEvent],
) =
  ## Automatically load available marines/colonists onto empty transports at colonies
  ## NOTE: Manual cargo operations now use zero-turn commands (executed before turn resolution)
  ## This auto-load only processes fleets that weren't manually managed
  ##
  ## Auto-load conditions:
  ## - Fleet is at friendly colony
  ## - Fleet has transport ships (TroopTransport/ETAC) with empty cargo space
  ## - Colony has available marines or population
  ## - Ship is not crippled

  # Process each colony
  for colony in state.allColonies():
    let colonyId = colony.id
    let systemId = colony.systemId
    let houseId = colony.owner

    # Check if colony has cargo to load
    # Count marines in groundUnitIds
    var hasMarines = false
    for unitId in colony.groundUnitIds:
      let unitOpt = state.groundUnit(unitId)
      if unitOpt.isSome and unitOpt.get().stats.unitType == GroundClass.Marine:
        hasMarines = true
        break
    # Must keep minimum population per limits config (5000 souls)
    let minSoulsToKeep = gameConfig.limits.populationLimits.minColonyPopulation
    let hasPopulation = colony.souls > minSoulsToKeep

    if not hasMarines and not hasPopulation:
      continue # No cargo available

    # Find fleets at this colony
    for fleet in state.fleetsInSystem(systemId):
      if fleet.houseId != houseId:
        continue # Not owned by colony's house

      # Check if fleet has transport capacity (ETAC or TroopTransport)
      var hasTransports = false
      for shipId in fleet.ships:
        let shipOpt = state.ship(shipId)
        if shipOpt.isSome:
          let ship = shipOpt.get()
          if ship.shipClass in {ShipClass.ETAC, ShipClass.TroopTransport}:
            hasTransports = true
            break

      if not hasTransports:
        continue

      # Auto-load marines onto TroopTransports if available
      if hasMarines:
        autoLoadMarines(state, fleet, colony, colonyId, events)

      # Auto-load colonists onto ETACs if available
      if hasPopulation:
        autoLoadColonists(state, fleet, colony, colonyId, events)
