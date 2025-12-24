## Fleet movement, colonization, and seek home operations
##
## This module handles all fleet order resolution including:
## - Fleet movement with pathfinding and lane traversal rules
## - Colonization orders and new colony establishment
## - Automated Seek Home behavior for stranded fleets
## - Helper functions for path finding and hostility detection

import std/[tables, options, sequtils, strformat]
import ../../common/types/[core, combat, units]
import ../gamestate, ../orders, ../fleet, ../squadron, ../starmap, ../logger
import ../ship/entity as ship_entity  # Ship helper functions
import ../index_maintenance
import ../state_helpers
import ../initialization/colony
import ../colonization/engine as col_engine
import ../diplomacy/[types as dip_types]
import ../config/population_config
import ../prestige
import ./types  # Common resolution types
import ./event_factory/init as event_factory
import ../intelligence/generator
import ../intelligence/types as intel_types
import ../standing_orders

proc completeFleetCommand*(
  state: var GameState, fleetId: FleetId, orderType: string,
  details: string = "", systemId: Option[SystemId] = none(SystemId),
  events: var seq[GameEvent]
) =
  ## Standard completion handler: generates OrderCompleted event
  ## Cleanup handled by event-driven order_cleanup module in Command Phase
  if fleetId notin state.fleets: return
  let houseId = state.fleets[fleetId].owner

  events.add(event_factory.orderCompleted(
    houseId, fleetId, orderType, details, systemId))

  logInfo(LogCategory.lcOrders, &"Fleet {fleetId} {orderType} order completed")

proc isSystemHostile*(state: GameState, systemId: SystemId, houseId: HouseId): bool =
  ## Check if a system is hostile to a house based on known intel (fog-of-war)
  ## System is hostile if player KNOWS it contains:
  ## 1. Enemy colony (from intelligence database or visibility)
  ## 2. Enemy fleets (from intelligence database or visibility)
  ## IMPORTANT: This respects fog-of-war - only uses information available to the house

  let house = state.houses[houseId]

  # Check if system has enemy colony (visible or from intel database)
  if systemId in state.colonies:
    let colony = state.colonies[systemId]
    if colony.owner != houseId:
      # Check diplomatic status
      if house.diplomaticRelations.isEnemy(colony.owner):
        # Player can see this colony - it's hostile
        return true

  # Check intelligence database for known enemy colonies
  if systemId in house.intelligence.colonyReports:
    let colonyIntel = house.intelligence.colonyReports[systemId]
    if colonyIntel.targetOwner != houseId and house.diplomaticRelations.isEnemy(colonyIntel.targetOwner):
      return true

  # Check for enemy fleets at system (visible or from intel)
  for fleetId, fleet in state.fleets:
    if fleet.location == systemId and fleet.owner != houseId:
      if house.diplomaticRelations.isEnemy(fleet.owner):
        return true

  return false

proc estimatePathRisk*(state: GameState, path: seq[SystemId], houseId: HouseId): int =
  ## Estimate risk level of a path (0 = safe, higher = more risky)
  ## Uses fog-of-war information available to the house
  result = 0

  for systemId in path:
    if isSystemHostile(state, systemId, houseId):
      result += 10  # Known enemy system - high risk
    elif systemId in state.colonies:
      let colony = state.colonies[systemId]
      if colony.owner != houseId:
        # Foreign but not enemy (neutral) - moderate risk
        result += 3
    else:
      # Unexplored or empty - low risk
      result += 1

proc findClosestOwnedColony*(state: GameState, fromSystem: SystemId, houseId: HouseId): Option[SystemId] =
  ## Find the closest owned colony for a house, excluding the fromSystem
  ## Returns None if house has no colonies
  ## Used by Space Guild to find alternative delivery destination
  ## Also used for automated Seek Home behavior for stranded fleets
  ##
  ## INTEGRATION: Checks house's pre-planned fallback routes first for optimal retreat paths

  # Check if house has a pre-planned fallback route from this region
  if houseId in state.houses:
    let house = state.houses[houseId]
    for route in house.fallbackRoutes:
      # Route is valid if it matches our region and hasn't expired (< 20 turns old)
      if route.region == fromSystem and state.turn - route.lastUpdated < 20:
        # Verify fallback system still exists and is owned
        if route.fallbackSystem in state.colonies and
           state.colonies[route.fallbackSystem].owner == houseId:
          return some(route.fallbackSystem)

  # Fallback: Calculate best retreat route balancing distance and risk
  # IMPORTANT: Uses fog-of-war information only (player's knowledge)
  var bestColony: Option[SystemId] = none(SystemId)
  var bestScore = int.high  # Lower is better (combines distance and risk)

  # Iterate through all colonies owned by this house
  for systemId, colony in state.colonies:
    if colony.owner == houseId and systemId != fromSystem:
      # Calculate distance (jump count) to this colony
      # Create dummy fleet for pathfinding
      let dummyFleet = Fleet(
        id: "temp",
        owner: houseId,
        location: fromSystem,
        squadrons: @[],
        status: FleetStatus.Active
      )

      let pathResult = state.starMap.findPath(fromSystem, systemId, dummyFleet)
      if pathResult.path.len > 0:
        let distance = pathResult.path.len - 1  # Number of jumps

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

proc shouldAutoSeekHome*(state: GameState, fleet: Fleet, order: FleetOrder): bool =
  ## Determine if a fleet should automatically seek home due to dangerous situation
  ## Respects house's auto-retreat policy setting
  ## Triggers based on policy:
  ## - Never: Never auto-retreat
  ## - MissionsOnly: Abort missions (ETAC, Guard, Blockade) when target lost
  ## - ConservativeLosing: Also retreat fleets clearly losing combat
  ## - AggressiveSurvival: Also retreat any fleet at risk

  # Check house's auto-retreat policy
  let house = state.houses[fleet.owner]

  # Never policy: player always controls retreats
  if house.autoRetreatPolicy == AutoRetreatPolicy.Never:
    return false

  # Check if fleet is executing an order that becomes invalid due to hostility
  # (MissionsOnly and higher policies)
  case order.commandType
  of FleetOrderType.Colonize:
    # ETAC missions abort if destination becomes enemy-controlled
    if order.targetSystem.isSome:
      let targetId = order.targetSystem.get()
      if isSystemHostile(state, targetId, fleet.owner):
        return true

  of FleetOrderType.GuardStarbase, FleetOrderType.GuardPlanet, FleetOrderType.BlockadePlanet:
    # Guard/blockade orders abort if system lost to enemy
    if order.targetSystem.isSome:
      let targetId = order.targetSystem.get()
      if targetId in state.colonies:
        let colony = state.colonies[targetId]
        # If colony ownership changed to enemy, abort
        if colony.owner != fleet.owner:
          let house = state.houses[fleet.owner]
          if house.diplomaticRelations.isEnemy(colony.owner):
            return true
      else:
        # Colony destroyed - abort
        return true

  of FleetOrderType.Patrol:
    # Patrols abort if their patrol zone becomes enemy territory
    # Check if current location is hostile
    if fleet.location in state.colonies:
      let colony = state.colonies[fleet.location]
      if colony.owner != fleet.owner:
        let house = state.houses[fleet.owner]
        if house.diplomaticRelations.isEnemy(colony.owner):
          return true

    # Also check if patrol target destination is hostile
    if order.targetSystem.isSome:
      let targetId = order.targetSystem.get()
      if isSystemHostile(state, targetId, fleet.owner):
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

proc resolveMovementCommand*(state: var GameState, houseId: HouseId, order: FleetOrder,
                         events: var seq[GameEvent]) =
  ## Execute a fleet movement order with pathfinding and lane traversal rules
  ## Per operations.md:6.1 - Lane traversal rules:
  ##   - Major lanes: 2 jumps per turn if all systems owned by player
  ##   - Major lanes: 1 jump per turn if jumping into unexplored/rival system
  ##   - Minor/Restricted lanes: 1 jump per turn maximum
  ##   - Crippled ships or Spacelift ships cannot cross Restricted lanes

  # Detect infinite recursion
  movementCallDepth += 1
  if movementCallDepth > 100:
    logFatal(LogCategory.lcFleet, "resolveMovementCommand recursion depth > 100! Infinite loop detected!")
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

    # Automatic fleet intelligence gathering - detected enemy fleets
    if enemyFleetsAtLocation.len > 0:
      let systemIntelReport = generateSystemIntelReport(state, houseId, newLocation, intel_types.IntelQuality.Visual)
      if systemIntelReport.isSome:
        state.withHouse(houseId):
          house.intelligence.addSystemReport(systemIntelReport.get())
        logDebug(LogCategory.lcFleet, &"Fleet {order.fleetId} gathered intelligence on {enemyFleetsAtLocation.len} enemy fleet(s) at {newLocation}")

    # Combat will be resolved in conflict phase next turn
    # This just logs the encounter

proc resolveColonizationCommand*(state: var GameState, houseId: HouseId, order: FleetOrder,
                              events: var seq[GameEvent]) =
  ## Establish a new colony with prestige rewards
  if order.targetSystem.isNone:
    return

  let targetId = order.targetSystem.get()

  # Check if system already colonized
  if targetId in state.colonies:
    let colony = state.colonies[targetId]

    # ORBITAL INTELLIGENCE GATHERING
    # Fleet approaching colony for colonization/guard/blockade gets close enough to see orbital defenses
    if colony.owner != houseId:
      # Generate detailed colony intel including orbital defenses
      let colonyIntel = generateColonyIntelReport(state, houseId, targetId, intel_types.IntelQuality.Visual)
      if colonyIntel.isSome:
        state.withHouse(houseId):
          house.intelligence.addColonyReport(colonyIntel.get())
        logDebug(LogCategory.lcFleet, &"Fleet {order.fleetId} gathered orbital intelligence on enemy colony at {targetId}")

      # Also gather system intel on any fleets present (including guard/reserve fleets)
      let systemIntel = generateSystemIntelReport(state, houseId, targetId, intel_types.IntelQuality.Visual)
      if systemIntel.isSome:
        state.withHouse(houseId):
          house.intelligence.addSystemReport(systemIntel.get())

    logWarn(LogCategory.lcColonization, &"Fleet {order.fleetId}: System {targetId} already colonized by {colony.owner}")
    return

  let fleetOpt = state.getFleet(order.fleetId)
  if fleetOpt.isNone:
    return

  # Check system exists
  if targetId notin state.starMap.systems:
    logError(LogCategory.lcColonization, &"Fleet {order.fleetId}: System {targetId} not found in starMap")
    return

  var fleet = fleetOpt.get()

  # If fleet not at target, move there first
  if fleet.location != targetId:
    logDebug(LogCategory.lcColonization, &"Fleet {order.fleetId} not at target - moving from {fleet.location} to {targetId}")
    # Create temporary movement order to get fleet to destination
    let moveOrder = FleetOrder(
      fleetId: order.fleetId,
      orderType: FleetOrderType.Move,
      targetSystem: some(targetId),
      targetFleet: none(FleetId),
      priority: order.priority
    )
    logDebug(LogCategory.lcColonization, &"Calling resolveMovementCommand for fleet {order.fleetId}")
    resolveMovementCommand(state, houseId, moveOrder, events)
    logDebug(LogCategory.lcColonization, &"resolveMovementCommand returned for fleet {order.fleetId}")

    # Reload fleet after movement
    let movedFleetOpt = state.getFleet(order.fleetId)
    if movedFleetOpt.isNone:
      return
    fleet = movedFleetOpt.get()

    # Check if fleet reached destination (might be multiple jumps away)
    if fleet.location != targetId:
      logWarn(LogCategory.lcColonization, &"Fleet {order.fleetId} still not at target after movement (too far)")
      return

  # Check fleet has colonists (in Expansion squadrons)
  var hasColonists = false
  for squadron in fleet.squadrons:
    if squadron.squadronType == SquadronType.Expansion:
      if squadron.flagship.cargo.isSome:
        let cargo = squadron.flagship.cargo.get()
        if cargo.cargoType == CargoType.Colonists and cargo.quantity > 0:
          hasColonists = true
          break

  if not hasColonists:
    logError(LogCategory.lcColonization, &"Fleet {order.fleetId} has no colonists (PTU) - colonization failed")
    return

  # Establish colony using system's actual planet properties
  # Get system to determine planet class and resources
  let system = state.starMap.systems[targetId]
  let planetClass = system.planetClass
  let resources = system.resourceRating

  # Get PTU quantity from ETAC cargo (should be 3 for new ETACs)
  var ptuToDeposit = 0
  for squadron in fleet.squadrons:
    if squadron.squadronType == SquadronType.Expansion:
      if squadron.flagship.cargo.isSome:
        let cargo = squadron.flagship.cargo.get()
        if cargo.cargoType == CargoType.Colonists:
          ptuToDeposit = cargo.quantity
          break

  logInfo(LogCategory.lcColonization, &"Fleet {order.fleetId} colonizing {planetClass} world with {resources} resources at {targetId} (depositing {ptuToDeposit} PTU)")

  # Create ETAC colony (foundation colony with ptuToDeposit starter population)
  let colony = createETACColony(targetId, houseId, planetClass, resources,
                                ptuToDeposit)

  # Use colonization engine to establish with prestige
  let result = col_engine.establishColony(
    houseId,
    targetId,
    colony.planetClass,
    colony.resources,
    ptuToDeposit  # Deposit all cargo (3 PTU = 3 PU foundation colony)
  )

  if not result.success:
    logError(LogCategory.lcColonization, &"Failed to establish colony at {targetId}")
    return

  state.colonies[targetId] = colony

  # Unload colonists from Expansion squadrons
  for squadron in fleet.squadrons.mitems:
    if squadron.squadronType == SquadronType.Expansion:
      if squadron.flagship.cargo.isSome:
        var cargo = squadron.flagship.cargo.get()
        if cargo.cargoType == CargoType.Colonists:
          logInfo(LogCategory.lcColonization,
            &"⚠️  PRE-UNLOAD: {squadron.flagship.shipClass} {squadron.id} has {cargo.quantity} PTU")
          # Unload cargo
          cargo.quantity = 0
          cargo.cargoType = CargoType.None
          squadron.flagship.cargo = some(cargo)
          logInfo(LogCategory.lcColonization,
            &"⚠️  POST-UNLOAD: {squadron.flagship.shipClass} {squadron.id} has {cargo.quantity} PTU")

  # ETAC cannibalized - remove from game, structure becomes colony infrastructure
  logInfo(LogCategory.lcColonization,
    &"⚠️  CANNIBALIZATION CHECK: Fleet {order.fleetId} has " &
    &"{fleet.squadrons.len} squadrons")

  var cannibalized_count = 0
  for i in countdown(fleet.squadrons.high, 0):
    let squadron = fleet.squadrons[i]
    if squadron.squadronType == SquadronType.Expansion:
      let cargo = squadron.flagship.cargo
      let cargoQty = if cargo.isSome: cargo.get().quantity else: 0
      logInfo(LogCategory.lcColonization,
        &"⚠️  Squadron {i}: class={squadron.flagship.shipClass}, cargoQty={cargoQty}")

      if squadron.flagship.shipClass == ShipClass.ETAC and cargoQty == 0:
        # ETAC cannibalized - ship structure becomes starting IU
        fleet.squadrons.delete(i)
        cannibalized_count += 1

        # Fire GameEvent for colonization success
        events.add(GameEvent(
          eventType: GameEventType.ColonyEstablished,
          turn: state.turn,
          houseId: some(houseId),
          systemId: some(targetId),
          description: &"ETAC {squadron.id} cannibalized establishing colony infrastructure",
          colonyEventType: some("Established")
        ))

        logInfo(LogCategory.lcColonization,
          &"⚠️  ✅ CANNIBALIZED ETAC {squadron.id} at {targetId}")

  logInfo(LogCategory.lcColonization,
    &"⚠️  CANNIBALIZATION RESULT: {cannibalized_count} ETACs removed, " &
    &"{fleet.squadrons.len} squadrons remain")

  state.fleets[order.fleetId] = fleet

  # Apply prestige award
  var prestigeAwarded = 0
  if result.prestigeEvent.isSome:
    let prestigeEvent = result.prestigeEvent.get()
    prestigeAwarded = prestigeEvent.amount
    applyPrestigeEvent(state, houseId, prestigeEvent)
    logInfo(LogCategory.lcColonization, &"{state.houses[houseId].name} colonized system {targetId} (+{prestigeEvent.amount} prestige)")

  # Generate event
  events.add(event_factory.colonyEstablished(
    houseId,
    targetId,
    prestigeAwarded
  ))

  # Generate OrderCompleted event for successful colonization
  # Cleanup handled by Command Phase
  events.add(event_factory.orderCompleted(
    houseId, order.fleetId, "Colonize",
    details = &"established colony at {targetId}",
    systemId = some(targetId)
  ))

  logDebug(LogCategory.lcColonization,
    &"Fleet {order.fleetId} colonization complete, cleanup deferred to Command Phase")

proc resolveViewWorldCommand*(state: var GameState, houseId: HouseId, order: FleetOrder,
                            events: var seq[GameEvent]) =
  ## Perform long-range planetary reconnaissance (Order 19)
  ## Ship approaches system edge, scans planet, retreats to deep space
  ## Gathers: planet owner (if colonized) and planet class (production potential)
  if order.targetSystem.isNone:
    return

  let targetId = order.targetSystem.get()
  let fleet = state.fleets.getOrDefault(order.fleetId)

  if fleet.location != targetId:
    # Not at target yet, continue moving
    return

  # Fleet is at system - perform long-range scan
  var house = state.houses[houseId]

  # Gather intel on planet
  if targetId in state.colonies:
    let colony = state.colonies[targetId]

    # Create minimal colony intel report from long-range scan
    # ViewWorld only gathers: owner + planet class (no detailed statistics)
    let intelReport = ColonyIntelReport(
      colonyId: targetId,
      targetOwner: colony.owner,
      gatheredTurn: state.turn,
      quality: intel_types.IntelQuality.Scan,  # Long-range scan quality
      # Colony stats: minimal info from long-range scan
      population: 0,               # Unknown from long range
      industry: 0,                 # Unknown from long range
      defenses: 0,                 # Unknown from long range
      starbaseLevel: 0,            # Unknown from long range
      constructionQueue: @[],      # Unknown from long range
      # Economic intel: not available from long-range scan
      grossOutput: none(int),
      taxRevenue: none(int),
      # Orbital defenses: not visible from deep space approach
      unassignedSquadronCount: 0,
      reserveFleetCount: 0,
      mothballedFleetCount: 0,
      shipyardCount: 0
    )

    house.intelligence.colonyReports[targetId] = intelReport
    logInfo(LogCategory.lcFleet,
            &"{house.name} viewed world at {targetId}: Owner={colony.owner}, Class={colony.planetClass}")
  else:
    # Uncolonized system - no intel report needed
    # Just log that we found an uncolonized system
    if targetId in state.starMap.systems:
      logInfo(LogCategory.lcFleet,
              &"{house.name} viewed uncolonized system at {targetId}")

  state.houses[houseId] = house

  # Generate event
  events.add(event_factory.intelGathered(
    houseId,
    HouseId("neutral"),  # ViewWorld doesn't target a specific house
    targetId,
    "long-range planetary scan"
  ))

  # Generate OrderCompleted event for successful scan
  var scanDetails = if targetId in state.colonies:
    let colony = state.colonies[targetId]
    &"scanned {targetId} (owner: {colony.owner})"
  else:
    &"scanned uncolonized system {targetId}"

  events.add(event_factory.orderCompleted(
    houseId,
    order.fleetId,
    "ViewWorld",
    details = scanDetails,
    systemId = some(targetId)
  ))

  # Order completes - fleet remains at system (player must issue new orders)
  # NOTE: Fleet is in deep space, not orbit, so no orbital combat triggered
  # Cleanup handled by Command Phase

proc autoLoadCargo*(state: var GameState, orders: Table[HouseId, OrderPacket], events: var seq[GameEvent]) =
  ## Automatically load available marines/colonists onto empty transports at colonies
  ## NOTE: Manual cargo operations now use zero-turn commands (executed before turn resolution)
  ## This auto-load only processes fleets that weren't manually managed

  # Process each colony
  for systemId, colony in state.colonies:
    # Find fleets at this colony
    for fleetId, fleet in state.fleets:
      if fleet.location != systemId or fleet.owner != colony.owner:
        continue

      # Auto-load empty transports if colony has inventory
      var colony = state.colonies[systemId]
      var fleet = state.fleets[fleetId]
      var modified = false

      for squadron in fleet.squadrons.mitems:
        # Only process Expansion/Auxiliary squadrons
        if squadron.squadronType notin {SquadronType.Expansion, SquadronType.Auxiliary}:
          continue

        # Skip crippled ships
        if squadron.flagship.isCrippled:
          continue

        # Skip ships already loaded
        if squadron.flagship.cargo.isSome:
          let cargo = squadron.flagship.cargo.get()
          if cargo.cargoType != CargoType.None:
            continue

        # Determine what cargo this ship can carry
        case squadron.flagship.shipClass
        of ShipClass.TroopTransport:
          # Auto-load marines if available (capacity from config)
          if colony.marines > 0:
            let capacity = squadron.flagship.baseCarryLimit()
            let loadAmount = min(capacity, colony.marines)
            squadron.flagship.cargo = some(ShipCargo(
              cargoType: CargoType.Marines,
              quantity: loadAmount,
              capacity: capacity
            ))
            colony.marines -= loadAmount
            modified = true
            logInfo(LogCategory.lcFleet, &"Auto-loaded {loadAmount} Marines onto {squadron.id} at {systemId}")

        of ShipClass.ETAC:
          # Auto-load colonists if available (1 PTU commitment)
          # ETACs carry exactly 1 PTU for colonization missions
          # Per config/population.toml [transfer_limits] min_source_pu_remaining = 1
          let minSoulsToKeep = 1_000_000  # 1 PU minimum
          if colony.souls > minSoulsToKeep + soulsPerPtu():
            let capacity = squadron.flagship.baseCarryLimit()
            squadron.flagship.cargo = some(ShipCargo(
              cargoType: CargoType.Colonists,
              quantity: 1,
              capacity: capacity
            ))
            colony.souls -= soulsPerPtu()
            colony.population = colony.souls div 1_000_000
            modified = true
            logInfo(LogCategory.lcColonization, &"Auto-loaded 1 PTU onto {squadron.id} at {systemId}")

        else:
          discard  # Other ship classes don't have spacelift capability

      # Write back modified state if any cargo was loaded
      if modified:
        state.fleets[fleetId] = fleet
        state.colonies[systemId] = colony
