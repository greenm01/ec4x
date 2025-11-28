## Fleet movement, colonization, and seek home operations
##
## This module handles all fleet order resolution including:
## - Fleet movement with pathfinding and lane traversal rules
## - Colonization orders and new colony establishment
## - Automated Seek Home behavior for stranded fleets
## - Helper functions for path finding and hostility detection

import std/[tables, options, sequtils, strformat]
import ../../common/types/[core, combat, units]
import ../gamestate, ../orders, ../fleet, ../squadron, ../starmap, ../spacelift, ../logger
import ../state_helpers
import ../colonization/engine as col_engine
import ../diplomacy/[types as dip_types]
import ../config/population_config
import ../prestige
import ./types  # Common resolution types
import ../intelligence/generator
import ../intelligence/types as intel_types

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
        # Foreign but not enemy (neutral/ally) - moderate risk
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
        spaceLiftShips: @[],
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
  case order.orderType
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

proc resolveMovementOrder*(state: var GameState, houseId: HouseId, order: FleetOrder,
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
    logFatal(LogCategory.lcFleet, "resolveMovementOrder recursion depth > 100! Infinite loop detected!")
    quit(1)

  defer:
    movementCallDepth -= 1

  if order.targetSystem.isNone:
    return

  let fleetOpt = state.getFleet(order.fleetId)
  if fleetOpt.isNone:
    return

  var fleet = fleetOpt.get()
  let targetId = order.targetSystem.get()
  let startId = fleet.location

  # Already at destination
  if startId == targetId:
    logDebug(LogCategory.lcFleet, &"Fleet {order.fleetId} already at destination")
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

  fleet.location = newLocation
  state.fleets[order.fleetId] = fleet

  logInfo(LogCategory.lcFleet, &"Fleet {order.fleetId} moved {actualJumps} jump(s) to system {newLocation}")

  # Automatic intelligence gathering when arriving at system
  # ANY fleet presence reveals enemy colonies (passive reconnaissance)
  if newLocation in state.colonies:
    let colony = state.colonies[newLocation]
    if colony.owner != houseId:
      # Generate basic intelligence report on enemy colony
      let intelReport = generateColonyIntelReport(state, houseId, newLocation, intel_types.IntelQuality.Visual)
      if intelReport.isSome:
        state.withHouse(houseId):
          house.intelligence.addColonyReport(intelReport.get())
        logDebug(LogCategory.lcFleet, &"Fleet {order.fleetId} gathered intelligence on enemy colony at {newLocation}")

  # Check for fleet encounters at destination with STEALTH DETECTION
  # Per assets.md:2.4.3 - Cloaked fleets can only be detected by scouts or starbases
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

  # Automatic fleet intelligence gathering - detected enemy fleets
  if enemyFleetsAtLocation.len > 0:
    let systemIntelReport = generateSystemIntelReport(state, houseId, newLocation, intel_types.IntelQuality.Visual)
    if systemIntelReport.isSome:
      state.withHouse(houseId):
        house.intelligence.addSystemReport(systemIntelReport.get())
      logDebug(LogCategory.lcFleet, &"Fleet {order.fleetId} gathered intelligence on {enemyFleetsAtLocation.len} enemy fleet(s) at {newLocation}")

  # Combat will be resolved in conflict phase next turn
        # This just logs the encounter

proc resolveColonizationOrder*(state: var GameState, houseId: HouseId, order: FleetOrder,
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
    logDebug(LogCategory.lcColonization, &"Calling resolveMovementOrder for fleet {order.fleetId}")
    resolveMovementOrder(state, houseId, moveOrder, events)
    logDebug(LogCategory.lcColonization, &"resolveMovementOrder returned for fleet {order.fleetId}")

    # Reload fleet after movement
    let movedFleetOpt = state.getFleet(order.fleetId)
    if movedFleetOpt.isNone:
      return
    fleet = movedFleetOpt.get()

    # Check if fleet reached destination (might be multiple jumps away)
    if fleet.location != targetId:
      logWarn(LogCategory.lcColonization, &"Fleet {order.fleetId} still not at target after movement (too far)")
      return

  # Check fleet has colonists
  var hasColonists = false
  for ship in fleet.spaceLiftShips:
    if ship.cargo.cargoType == CargoType.Colonists and ship.cargo.quantity > 0:
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

  logInfo(LogCategory.lcColonization, &"Fleet {order.fleetId} colonizing {planetClass} world with {resources} resources at {targetId}")

  # Create ETAC colony with 1 PTU (50k souls)
  let colony = createETACColony(targetId, houseId, planetClass, resources)

  # Use colonization engine to establish with prestige
  let result = col_engine.establishColony(
    houseId,
    targetId,
    colony.planetClass,
    colony.resources,
    1  # ETAC carries exactly 1 PTU
  )

  if not result.success:
    logError(LogCategory.lcColonization, &"Failed to establish colony at {targetId}")
    return

  state.colonies[targetId] = colony

  # Unload colonists from fleet
  for ship in fleet.spaceLiftShips.mitems:
    if ship.cargo.cargoType == CargoType.Colonists:
      discard ship.unloadCargo()
  state.fleets[order.fleetId] = fleet

  # Apply prestige award
  if result.prestigeEvent.isSome:
    let prestigeEvent = result.prestigeEvent.get()
    state.withHouse(houseId):
      house.prestige += prestigeEvent.amount
    logInfo(LogCategory.lcColonization, &"{state.houses[houseId].name} colonized system {targetId} (+{prestigeEvent.amount} prestige)")

  # Generate event
  events.add(GameEvent(
    eventType: GameEventType.ColonyEstablished,
    houseId: houseId,
    description: "Established colony at system " & $targetId,
    systemId: some(targetId)
  ))

proc autoLoadCargo*(state: var GameState, orders: Table[HouseId, OrderPacket], events: var seq[GameEvent]) =
  ## Automatically load available marines/colonists onto empty transports at colonies
  ## Only auto-load if no manual cargo order exists for that fleet

  # Build set of fleets with manual cargo orders
  var manualCargoFleets: seq[FleetId] = @[]
  for houseId, packet in orders:
    for order in packet.cargoManagement:
      manualCargoFleets.add(order.fleetId)

  # Process each colony
  for systemId, colony in state.colonies:
    # Find fleets at this colony
    for fleetId, fleet in state.fleets:
      if fleet.location != systemId or fleet.owner != colony.owner:
        continue

      # Skip if fleet has manual cargo orders
      if fleetId in manualCargoFleets:
        continue

      # Auto-load empty transports if colony has inventory
      var colony = state.colonies[systemId]
      var fleet = state.fleets[fleetId]
      var modifiedShips: seq[SpaceLiftShip] = @[]
      var modified = false

      for ship in fleet.spaceLiftShips:
        var mutableShip = ship

        if ship.isCrippled or ship.cargo.cargoType != CargoType.None:
          modifiedShips.add(mutableShip)
          continue  # Skip crippled ships or ships already loaded

        # Determine what cargo this ship can carry
        case ship.shipClass
        of ShipClass.TroopTransport:
          # Auto-load marines if available
          if colony.marines > 0:
            let loadAmount = min(1, colony.marines)  # TroopTransport capacity = 1 MD
            if mutableShip.loadCargo(CargoType.Marines, loadAmount):
              colony.marines -= loadAmount
              modified = true
              logInfo(LogCategory.lcFleet, &"Auto-loaded {loadAmount} Marines onto {ship.id} at {systemId}")

        of ShipClass.ETAC:
          # Auto-load colonists if available (1 PTU commitment)
          # ETACs carry exactly 1 PTU for colonization missions
          # Per config/population.toml [transfer_limits] min_source_pu_remaining = 1
          let minSoulsToKeep = 1_000_000  # 1 PU minimum
          if colony.souls > minSoulsToKeep + soulsPerPtu():
            if mutableShip.loadCargo(CargoType.Colonists, 1):
              colony.souls -= soulsPerPtu()
              colony.population = colony.souls div 1_000_000
              modified = true
              logInfo(LogCategory.lcColonization, &"Auto-loaded 1 PTU onto {ship.id} at {systemId}")

        else:
          discard  # Other ship classes don't have spacelift capability

        modifiedShips.add(mutableShip)

      # Write back modified state if any cargo was loaded
      if modified:
        fleet.spaceLiftShips = modifiedShips
        state.fleets[fleetId] = fleet
        state.colonies[systemId] = colony
