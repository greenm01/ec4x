## Standing Orders Activation System
##
## Implements persistent fleet behaviors that activate automatically when
## no explicit order is given for a turn. Reduces micromanagement and provides
## quality-of-life improvements for both players and AI.
##
## Three-tier order lifecycle (applies to both active and standing orders):
## - Initiate (Command Phase Part B): Player configures standing order rules
## - Validate (Command Phase Part C): Engine validates configuration
## - Activate (Maintenance Phase Step 1a): Check conditions, generate fleet orders
## - Execute (Conflict/Income Phase): Missions happen at targets
##
## See docs/architecture/standing-orders.md for complete design.

import std/[tables, options, strformat, algorithm, sets, sequtils]
import gamestate, orders, fleet, starmap, logger, spacelift, fog_of_war
import order_types
import ../common/types/[core, planets]
import config/standing_orders_config
import resolution/[event_factory/init as event_factory, types as resolution_types]
import intelligence/types as intel_types

export StandingOrderType, StandingOrder, StandingOrderParams

type
  ActivationResult* = object
    ## Result of standing order activation attempt
    success*: bool
    action*: string               # Description of action taken
    error*: string                # Error message if failed
    updatedParams*: Option[StandingOrderParams]  # Updated params (e.g., patrol index)

# =============================================================================
# Fog-of-War Helpers (DRY Principle)
# =============================================================================

proc getKnownSystems*(state: GameState, houseId: HouseId): HashSet[SystemId] =
  ## Returns all systems the house knows about through fog-of-war
  ## Used by standing orders to avoid omniscient decisions
  ##
  ## **Known systems include:**
  ## - Own colonies (always visible)
  ## - Systems adjacent to own colonies (hex visibility)
  ## - Scouted systems (intelligence reports)
  ## - Enemy colonies with intel reports
  result = initHashSet[SystemId]()

  let house = state.houses[houseId]
  let intel = house.intelligence

  # 1. Own colonies (always known)
  for colonyId, colony in state.colonies:
    if colony.owner == houseId:
      result.incl(colonyId)
      # Add adjacent systems (hex visibility from owned colonies)
      for lane in state.starMap.lanes:
        if lane.source == colonyId:
          result.incl(lane.destination)
        elif lane.destination == colonyId:
          result.incl(lane.source)

  # 2. Systems with intelligence reports (scouted)
  for systemId in intel.systemReports.keys:
    result.incl(systemId)

  # 3. Enemy colonies we know about
  for colonyId in intel.colonyReports.keys:
    result.incl(colonyId)

proc hasColonyIntel*(state: GameState, houseId: HouseId, systemId: SystemId): bool =
  ## Check if house has intel on a colony at given system
  ## Returns true if:
  ## - System has own colony (always known)
  ## - System has enemy colony with intel report

  # Own colony at system
  if systemId in state.colonies and state.colonies[systemId].owner == houseId:
    return true

  # Enemy colony with intel report
  let house = state.houses[houseId]
  if systemId in house.intelligence.colonyReports:
    return true

  return false

proc getKnownEnemyFleetsInSystem*(state: GameState, houseId: HouseId,
                                   systemId: SystemId): seq[Fleet] =
  ## Returns enemy fleets at system that house has intel on
  ## Used by AutoEvade and other defensive standing orders
  ##
  ## **Detection sources:**
  ## - Fleet movement history (detected by scouts/surveillance)
  ## - Combat encounters (surviving ships report enemy presence)
  ## - System intelligence reports (SpySystem missions)
  result = @[]

  let house = state.houses[houseId]
  let intel = house.intelligence

  # Check system intel report for fleet presence
  let systemIntel = if systemId in intel.systemReports:
                      some(intel.systemReports[systemId])
                    else:
                      none(intel_types.SystemIntelReport)
  if systemIntel.isSome:
    # We have recent intel on fleets in this system
    let report = systemIntel.get()
    for fleetIntel in report.detectedFleets:
      # Only return fleets that are actually still there
      if fleetIntel.fleetId in state.fleets:
        let fleet = state.fleets[fleetIntel.fleetId]
        if fleet.location == systemId and fleet.owner != houseId:
          result.add(fleet)

  # Check fleet movement history for fleets detected at this location
  for fleetId, history in intel.fleetMovementHistory:
    if history.owner == houseId:
      continue  # Skip own fleets

    # Check if this fleet was last seen at this system
    if history.sightings.len > 0:
      let lastSighting = history.sightings[^1]  # Most recent sighting
      if lastSighting.systemId == systemId:
        # Verify fleet still exists and is at this location
        if fleetId in state.fleets:
          let fleet = state.fleets[fleetId]
          if fleet.location == systemId:
            # Avoid duplicates
            if not result.anyIt(it.id == fleetId):
              result.add(fleet)

# =============================================================================
# Activation Logic - Per Order Type
# =============================================================================

proc activatePatrolRoute(state: var GameState, fleetId: FleetId,
                       params: StandingOrderParams): ActivationResult =
  ## Execute patrol route - move to next system in path
  ## Loops continuously through patrol path
  let fleet = state.fleets[fleetId]
  let currentIndex = params.patrolIndex
  let nextSystem = params.patrolSystems[currentIndex]

  logDebug(LogCategory.lcOrders,
           &"{fleetId} PatrolRoute: Current position {currentIndex + 1}/" &
           &"{params.patrolSystems.len} in patrol path")

  # Verify target system exists and is reachable
  if nextSystem notin state.starMap.systems:
    logWarn(LogCategory.lcOrders,
            &"{fleetId} PatrolRoute failed: Target system {nextSystem} does not exist")
    return ActivationResult(success: false,
                          error: &"Target system {nextSystem} does not exist")

  # Generate move order to next patrol point
  let moveOrder = FleetOrder(
    fleetId: fleetId,
    orderType: FleetOrderType.Move,
    targetSystem: some(nextSystem),
    priority: 100  # Standing orders have lower priority than explicit orders
  )

  # Advance patrol index (loop back to start when reaching end)
  var newParams = params
  newParams.patrolIndex = (currentIndex + 1) mod params.patrolSystems.len

  # Store order for execution
  state.fleetOrders[fleetId] = moveOrder

  logInfo(LogCategory.lcOrders,
          &"{fleetId} PatrolRoute: {fleet.location} → system-{nextSystem} " &
          &"(step {currentIndex + 1}/{params.patrolSystems.len})")

  return ActivationResult(
    success: true,
    action: &"Move to system-{nextSystem}",
    updatedParams: some(newParams)
  )

proc activateDefendSystem(state: var GameState, fleetId: FleetId,
                        params: StandingOrderParams): ActivationResult =
  ## Execute defend system - stay at target or return if moved away
  let fleet = state.fleets[fleetId]
  let targetSystem = params.defendTargetSystem
  let maxRange = params.defendMaxRange

  logDebug(LogCategory.lcOrders,
           &"{fleetId} DefendSystem: Target=system-{targetSystem}, " &
           &"Current=system-{fleet.location}, MaxRange={maxRange}")

  # If already at target system, patrol/guard in place
  if fleet.location == targetSystem:
    let guardOrder = FleetOrder(
      fleetId: fleetId,
      orderType: FleetOrderType.Patrol,
      targetSystem: some(targetSystem),
      priority: 100
    )
    state.fleetOrders[fleetId] = guardOrder

    logInfo(LogCategory.lcOrders,
            &"{fleetId} DefendSystem: At target system-{targetSystem}, patrolling")

    return ActivationResult(success: true,
                          action: &"Patrol system-{targetSystem}")

  # Check distance from target (via jump lanes, not as the crow flies)
  let pathResult = state.starMap.findPath(fleet.location, targetSystem, fleet)
  if not pathResult.found:
    # Can't reach target - suspended order, log warning
    logWarn(LogCategory.lcOrders,
            &"{fleetId} DefendSystem: Cannot reach target system-{targetSystem}, no valid path")
    return ActivationResult(success: false,
                          error: "No path to target system")

  let distance = pathResult.path.len - 1  # Path includes start, so subtract 1

  if distance > maxRange:
    # Too far from target - return to defensive position
    let moveOrder = FleetOrder(
      fleetId: fleetId,
      orderType: FleetOrderType.Move,
      targetSystem: some(targetSystem),
      priority: 100
    )
    state.fleetOrders[fleetId] = moveOrder

    logInfo(LogCategory.lcOrders,
            &"{fleetId} DefendSystem: {distance} jumps from target, returning to system-{targetSystem}")

    return ActivationResult(success: true,
                          action: &"Return to system-{targetSystem}")

  # Within range but not at target - hold position
  let holdOrder = FleetOrder(
    fleetId: fleetId,
    orderType: FleetOrderType.Hold,
    targetSystem: none(SystemId),
    priority: 100
  )
  state.fleetOrders[fleetId] = holdOrder

  logInfo(LogCategory.lcOrders,
          &"{fleetId} DefendSystem: {distance} jumps from target (within range {maxRange}), holding position")

  return ActivationResult(success: true,
                        action: "Hold position within defensive range")

proc scoreColonizationCandidate*(
  turn: int,
  distance: int,
  planetClass: PlanetClass,
  proximityBonus: float = 0.0,
  proximityWeightAct1: float = 0.3,
  proximityWeightAct4: float = 0.9
): float =
  ## Calculate colonization score using Act-aware frontier expansion algorithm
  ##
  ## **Frontier Expansion (Act 1-2):** Distance 10x more important than quality
  ## **Quality Consolidation (Act 3-4):** Quality 3x more important than distance
  ## **Proximity Bonus:** Systems near owned colonies get weighted bonus (Act-aware)
  ##
  ## **Exported for reuse across engine and AI modules (DRY principle)**

  # Calculate current Act from turn number (7 turns per Act)
  let currentAct = if turn <= 7: 1
                   elif turn <= 14: 2
                   elif turn <= 21: 3
                   else: 4

  # Calculate planet quality score (0-100)
  let qualityScore = case planetClass
    of PlanetClass.Eden: 100.0
    of PlanetClass.Lush: 80.0
    of PlanetClass.Benign: 60.0
    of PlanetClass.Harsh: 40.0
    of PlanetClass.Hostile: 30.0
    of PlanetClass.Desolate: 20.0
    of PlanetClass.Extreme: 10.0

  # Calculate distance score (closer = better)
  # Exponential penalty for distance to strongly discourage distant systems
  let distanceScore = 100.0 / (1.0 + float(distance) * float(distance))

  # Calculate Act-aware proximity weight
  let proximityWeight = if currentAct <= 2:
    proximityWeightAct1  # Low weight in Act 1-2 (frontier expansion)
  else:
    proximityWeightAct4  # High weight in Act 3-4 (consolidation)

  # Act-aware weighting with proximity bonus
  result = if currentAct <= 2:
    # Act 1-2: FRONTIER EXPANSION (Distance 10x more important than quality)
    (distanceScore * 10.0) + (qualityScore * 1.0) + (proximityBonus * proximityWeight)
  else:
    # Act 3-4: QUALITY CONSOLIDATION (Quality 3x more important than distance)
    (qualityScore * 3.0) + (distanceScore * 1.0) + (proximityBonus * proximityWeight)

proc findColonizationTarget*(state: GameState, houseId: HouseId, fleet: Fleet,
                            currentLocation: SystemId,
                            maxRange: int,
                            alreadyTargeted: HashSet[SystemId],
                            preferredClasses: seq[PlanetClass] = @[]): Option[SystemId] =
  ## Engine-provided colonization target selection with Act-aware scoring
  ##
  ## **Frontier Expansion Algorithm (Act 1-2):**
  ## Prioritizes DISTANCE over planet quality to enable rapid expansion
  ## Prevents ETACs from traveling deep into enemy territory chasing high-quality planets
  ##
  ## **Quality Consolidation (Act 3-4):**
  ## Prioritizes planet quality over distance for strategic positioning
  ##
  ## **Fog-of-War Compliance:**
  ## Only considers systems the house knows about (uses getKnownSystems helper)
  ##
  ## **Duplicate Prevention:**
  ## Pass alreadyTargeted HashSet to skip systems already being colonized
  var candidates: seq[(SystemId, int, PlanetClass)] = @[]

  # Calculate current Act from turn number (7 turns per Act)
  let currentAct = if state.turn <= 7: 1
                   elif state.turn <= 14: 2
                   elif state.turn <= 21: 3
                   else: 4

  # Get known systems (fog-of-war compliant)
  let knownSystems = getKnownSystems(state, houseId)

  # Scan known systems within range
  for systemId in knownSystems:
    # Skip if we know it's colonized
    if hasColonyIntel(state, houseId, systemId):
      continue

    # Skip systems already targeted by other fleets (duplicate prevention)
    if systemId in alreadyTargeted:
      continue

    # Check distance via jump lanes
    let pathResult = state.starMap.findPath(currentLocation, systemId, fleet)
    if not pathResult.found:
      continue  # Can't reach this system

    let distance = pathResult.path.len - 1  # Path includes start, so subtract 1
    if distance > maxRange:
      continue

    # Get planet class
    let planetClass = state.starMap.systems[systemId].planetClass
    candidates.add((systemId, distance, planetClass))

  if candidates.len == 0:
    return none(SystemId)

  # Score candidates using shared frontier expansion algorithm
  type ScoredCandidate = tuple[systemId: SystemId, score: float, distance: int, planetClass: PlanetClass]
  var scoredCandidates: seq[ScoredCandidate] = @[]

  for (systemId, distance, planetClass) in candidates:
    let score = scoreColonizationCandidate(state.turn, distance, planetClass)
    scoredCandidates.add((systemId, score, distance, planetClass))

  # Sort by score (highest first)
  scoredCandidates.sort(proc(a, b: ScoredCandidate): int =
    if a.score > b.score: -1
    elif a.score < b.score: 1
    else: 0
  )

  let best = scoredCandidates[0]
  logDebug(LogCategory.lcOrders,
           &"AutoColonize target selection (Act {currentAct}): " &
           &"System {best.systemId} ({best.planetClass}, {best.distance} jumps, score={best.score:.1f})")

  return some(best.systemId)

proc findColonizationTargetFiltered*(filtered: FilteredGameState, fleet: Fleet,
                                     currentLocation: SystemId,
                                     maxRange: int,
                                     alreadyTargeted: HashSet[SystemId],
                                     preferredClasses: seq[PlanetClass] = @[]): Option[SystemId] =
  ## AI-optimized wrapper that works with pre-filtered game state
  ## Avoids redundant fog-of-war filtering when AI already has FilteredGameState
  ##
  ## Same Act-aware scoring and duplicate prevention as main function
  var candidates: seq[(SystemId, int, PlanetClass)] = @[]

  # Calculate current Act from turn number (7 turns per Act)
  let currentAct = if filtered.turn <= 7: 1
                   elif filtered.turn <= 14: 2
                   elif filtered.turn <= 21: 3
                   else: 4

  # Scan visible systems within range
  # Fog-of-war: Only visible systems are in this table (respects all players' visibility)
  for systemId, visSystem in filtered.visibleSystems:
    # Skip if colonized (check own colonies + visible colonies)
    var isColonized = false
    for colony in filtered.ownColonies:
      if colony.systemId == systemId:
        isColonized = true
        break
    if not isColonized:
      for visColony in filtered.visibleColonies:
        if visColony.systemId == systemId:
          isColonized = true
          break
    if isColonized:
      continue

    # Skip systems already targeted by other fleets (duplicate prevention)
    if systemId in alreadyTargeted:
      continue

    # Check distance via jump lanes (proper pathfinding)
    let pathResult = filtered.starMap.findPath(currentLocation, systemId, fleet)
    if not pathResult.found:
      continue  # Can't reach this system

    let distance = pathResult.path.len - 1  # Path includes start, so subtract 1
    if distance > maxRange:
      continue

    # Get planet class from star map (VisibleSystem doesn't include planet details)
    if systemId notin filtered.starMap.systems:
      continue  # System not in star map (shouldn't happen but be safe)
    let system = filtered.starMap.systems[systemId]
    let planetClass = system.planetClass
    candidates.add((systemId, distance, planetClass))

  if candidates.len == 0:
    return none(SystemId)

  # Score candidates using shared scoring function
  type ScoredCandidate = tuple[systemId: SystemId, score: float, distance: int, planetClass: PlanetClass]
  var scoredCandidates: seq[ScoredCandidate] = @[]

  for (systemId, distance, planetClass) in candidates:
    let score = scoreColonizationCandidate(filtered.turn, distance, planetClass)
    scoredCandidates.add((systemId, score, distance, planetClass))

  # Sort by score (highest first)
  scoredCandidates.sort(proc(a, b: ScoredCandidate): int =
    if a.score > b.score: -1
    elif a.score < b.score: 1
    else: 0
  )

  let best = scoredCandidates[0]
  logDebug(LogCategory.lcOrders,
           &"Colonization target (Act {currentAct}, filtered): " &
           &"System {best.systemId} ({best.planetClass}, ~{best.distance} hex, score={best.score:.1f})")

  return some(best.systemId)

proc activateAutoColonize(state: var GameState, fleetId: FleetId,
                        params: StandingOrderParams): ActivationResult =
  ## Execute auto-colonize - find and colonize nearest suitable system
  ## For ETAC fleets that should automatically expand
  let fleet = state.fleets[fleetId]

  logDebug(LogCategory.lcOrders,
           &"{fleetId} AutoColonize: Searching for targets within {params.colonizeMaxRange} jumps")

  # Verify fleet has colonization capability (ETAC with colonists)
  if fleet.spaceLiftShips.len == 0:
    logWarn(LogCategory.lcOrders,
            &"{fleetId} AutoColonize failed: Fleet has no spacelift ships")
    return ActivationResult(success: false,
                          error: "No spacelift ships for colonization")

  # Check if any spacelift ship carries colonists
  var hasColonists = false
  for ship in fleet.spaceLiftShips:
    if ship.cargo.cargoType == CargoType.Colonists:
      hasColonists = true
      break

  if not hasColonists:
    # ETAC empty - NO automatic orders generated
    # Player/AI must intentionally send ETAC home for reload
    # Passive auto-reload will occur when ETAC arrives at friendly colony
    logDebug(LogCategory.lcOrders,
      &"Fleet {fleetId} has empty ETAC - awaiting manual movement to colony for reload")
    return ActivationResult(success: false,
                          error: "Empty ETAC needs manual movement to colony for reload")

  # Find best colonization target
  # Standing orders don't coordinate across fleets - use empty alreadyTargeted set
  let targetOpt = findColonizationTarget(state, fleet.owner, fleet, fleet.location,
                                        params.colonizeMaxRange,
                                        initHashSet[SystemId](),
                                        params.preferredPlanetClasses)

  if targetOpt.isNone:
    logDebug(LogCategory.lcOrders,
             &"{fleetId} AutoColonize: No suitable systems within {params.colonizeMaxRange} jumps")
    return ActivationResult(success: false,
                          error: "No colonization targets available")

  let targetSystem = targetOpt.get()

  # Calculate distance via jump lanes
  let pathResult = state.starMap.findPath(fleet.location, targetSystem, fleet)
  let distance = if pathResult.found: pathResult.path.len - 1 else: 0

  # If already at target, issue colonize order
  if fleet.location == targetSystem:
    let colonizeOrder = FleetOrder(
      fleetId: fleetId,
      orderType: FleetOrderType.Colonize,
      targetSystem: some(targetSystem),
      priority: 100
    )
    state.fleetOrders[fleetId] = colonizeOrder

    logInfo(LogCategory.lcOrders,
            &"{fleetId} AutoColonize: At target system-{targetSystem}, colonizing")

    return ActivationResult(success: true,
                          action: &"Colonize system-{targetSystem}")

  # Move to colonization target
  let moveOrder = FleetOrder(
    fleetId: fleetId,
    orderType: FleetOrderType.Move,
    targetSystem: some(targetSystem),
    priority: 100
  )
  state.fleetOrders[fleetId] = moveOrder

  let planetClass = state.starMap.systems[targetSystem].planetClass

  logInfo(LogCategory.lcOrders,
          &"{fleetId} AutoColonize: Moving to system-{targetSystem} " &
          &"({planetClass}, {distance} jumps)")

  return ActivationResult(success: true,
                        action: &"Move to colonization target system-{targetSystem}")

proc activateAutoRepair(state: var GameState, fleetId: FleetId,
                      params: StandingOrderParams): ActivationResult =
  ## Execute auto-repair - return to nearest shipyard when ships are crippled
  ## Triggers when crippled ship percentage exceeds threshold
  let fleet = state.fleets[fleetId]

  # Count crippled ships vs total ships
  var totalShips = 0
  var crippledShips = 0

  for squadron in fleet.squadrons:
    totalShips += 1
    if squadron.flagship.isCrippled:
      crippledShips += 1

    # Include wingmen
    for ship in squadron.ships:
      totalShips += 1
      if ship.isCrippled:
        crippledShips += 1

  if totalShips == 0:
    # No ships (shouldn't happen, but safety check)
    return ActivationResult(success: false, error: "Fleet has no ships")

  let crippledPercent = crippledShips.float / totalShips.float

  logDebug(LogCategory.lcOrders,
           &"{fleetId} AutoRepair: Fleet {crippledShips}/{totalShips} ships crippled " &
           &"({(crippledPercent * 100).int}%), " &
           &"Threshold {(params.repairDamageThreshold * 100).int}%")

  # Check if damage threshold triggered
  if crippledPercent < params.repairDamageThreshold:
    # Fleet healthy, no repair needed
    logDebug(LogCategory.lcOrders,
             &"{fleetId} AutoRepair: Fleet above damage threshold, holding position")

    let holdOrder = FleetOrder(
      fleetId: fleetId,
      orderType: FleetOrderType.Hold,
      targetSystem: none(SystemId),
      priority: 100
    )
    state.fleetOrders[fleetId] = holdOrder

    return ActivationResult(success: true,
                          action: "Hold (fleet healthy)")

  # Fleet damaged - find nearest shipyard
  var nearestShipyard: Option[SystemId] = none(SystemId)
  var minDistance = int.high

  # Check for specific target shipyard
  if params.targetShipyard.isSome:
    let targetSystem = params.targetShipyard.get()
    if targetSystem in state.colonies:
      let colony = state.colonies[targetSystem]
      if colony.owner == fleet.owner and colony.hasOperationalShipyard():
        nearestShipyard = some(targetSystem)
        let pathResult = state.starMap.findPath(fleet.location, targetSystem, fleet)
        if pathResult.found:
          minDistance = pathResult.path.len - 1

  # If no specific target or target not found, search all colonies
  if nearestShipyard.isNone:
    for systemId, colony in state.colonies:
      # Only owned colonies with operational shipyards
      if colony.owner != fleet.owner:
        continue
      if not colony.hasOperationalShipyard():
        continue

      # Calculate distance via jump lanes
      let pathResult = state.starMap.findPath(fleet.location, systemId, fleet)
      if not pathResult.found:
        continue

      let distance = pathResult.path.len - 1
      if distance < minDistance:
        minDistance = distance
        nearestShipyard = some(systemId)

  if nearestShipyard.isNone:
    # No shipyard available
    logWarn(LogCategory.lcOrders,
            &"{fleetId} AutoRepair failed: No accessible shipyard found " &
            &"({crippledShips}/{totalShips} ships crippled)")
    return ActivationResult(success: false,
                          error: "No accessible shipyard")

  let targetSystem = nearestShipyard.get()

  # If already at shipyard, hold for repairs
  if fleet.location == targetSystem:
    logInfo(LogCategory.lcOrders,
            &"{fleetId} AutoRepair: At shipyard system-{targetSystem}, " &
            &"holding for repairs ({crippledShips}/{totalShips} ships crippled)")

    let holdOrder = FleetOrder(
      fleetId: fleetId,
      orderType: FleetOrderType.Hold,
      targetSystem: none(SystemId),
      priority: 100
    )
    state.fleetOrders[fleetId] = holdOrder

    return ActivationResult(success: true,
                          action: &"Hold at shipyard (repairing)")

  # Move to shipyard
  logInfo(LogCategory.lcOrders,
          &"{fleetId} AutoRepair: Damaged ({crippledShips}/{totalShips} ships crippled), " &
          &"returning to shipyard at system-{targetSystem} ({minDistance} jumps)")

  let moveOrder = FleetOrder(
    fleetId: fleetId,
    orderType: FleetOrderType.Move,
    targetSystem: some(targetSystem),
    priority: 100
  )
  state.fleetOrders[fleetId] = moveOrder

  return ActivationResult(success: true,
                        action: &"Return to shipyard at system-{targetSystem}")

proc activateAutoReinforce(state: var GameState, fleetId: FleetId,
                         params: StandingOrderParams): ActivationResult =
  ## Execute auto-reinforce - join damaged friendly fleet
  ## Finds nearest damaged fleet and moves to join it
  let fleet = state.fleets[fleetId]

  logDebug(LogCategory.lcOrders,
           &"{fleetId} AutoReinforce: Searching for damaged friendly fleets")

  # Find target fleet (specific or nearest damaged)
  var targetFleetId: Option[FleetId] = none(FleetId)
  var targetFleetLocation: SystemId
  var minDistance = int.high

  if params.targetFleet.isSome:
    # Specific target fleet
    let specificTarget = params.targetFleet.get()
    if specificTarget in state.fleets:
      let targetFleet = state.fleets[specificTarget]

      # Check if target belongs to same house
      if targetFleet.owner == fleet.owner:
        # Count crippled ships in target fleet
        var targetTotalShips = 0
        var targetCrippledShips = 0
        for squadron in targetFleet.squadrons:
          targetTotalShips += 1
          if squadron.flagship.isCrippled:
            targetCrippledShips += 1
          for ship in squadron.ships:
            targetTotalShips += 1
            if ship.isCrippled:
              targetCrippledShips += 1

        let targetCrippledPercent = if targetTotalShips > 0:
                                       targetCrippledShips.float / targetTotalShips.float
                                     else: 0.0

        # Check if target is damaged above threshold
        if targetCrippledPercent >= params.reinforceDamageThreshold:
          targetFleetId = some(specificTarget)
          targetFleetLocation = targetFleet.location

          let pathResult = state.starMap.findPath(fleet.location, targetFleet.location, fleet)
          if pathResult.found:
            minDistance = pathResult.path.len - 1

  # If no specific target or target not damaged, search for nearest damaged fleet
  if targetFleetId.isNone:
    for otherFleetId, otherFleet in state.fleets:
      # Skip self
      if otherFleetId == fleetId:
        continue

      # Only same house
      if otherFleet.owner != fleet.owner:
        continue

      # Count crippled ships
      var otherTotalShips = 0
      var otherCrippledShips = 0
      for squadron in otherFleet.squadrons:
        otherTotalShips += 1
        if squadron.flagship.isCrippled:
          otherCrippledShips += 1
        for ship in squadron.ships:
          otherTotalShips += 1
          if ship.isCrippled:
            otherCrippledShips += 1

      if otherTotalShips == 0:
        continue

      let otherCrippledPercent = otherCrippledShips.float / otherTotalShips.float

      # Check if damaged above threshold
      if otherCrippledPercent < params.reinforceDamageThreshold:
        continue

      # Calculate distance via jump lanes
      let pathResult = state.starMap.findPath(fleet.location, otherFleet.location, fleet)
      if not pathResult.found:
        continue

      let distance = pathResult.path.len - 1
      if distance < minDistance:
        minDistance = distance
        targetFleetId = some(otherFleetId)
        targetFleetLocation = otherFleet.location

  if targetFleetId.isNone:
    # No damaged fleets found
    logDebug(LogCategory.lcOrders,
             &"{fleetId} AutoReinforce: No damaged friendly fleets found " &
             &"(threshold {(params.reinforceDamageThreshold * 100).int}%)")

    let holdOrder = FleetOrder(
      fleetId: fleetId,
      orderType: FleetOrderType.Hold,
      targetSystem: none(SystemId),
      priority: 100
    )
    state.fleetOrders[fleetId] = holdOrder

    return ActivationResult(success: true,
                          action: "Hold (no damaged fleets)")

  let targetId = targetFleetId.get()

  # If already at target location, issue JoinFleet order
  if fleet.location == targetFleetLocation:
    logInfo(LogCategory.lcOrders,
            &"{fleetId} AutoReinforce: At location with {targetId}, joining fleet")

    let joinOrder = FleetOrder(
      fleetId: fleetId,
      orderType: FleetOrderType.JoinFleet,
      targetFleet: some(targetId),
      priority: 100
    )
    state.fleetOrders[fleetId] = joinOrder

    return ActivationResult(success: true,
                          action: &"Join fleet {targetId}")

  # Move to target fleet
  logInfo(LogCategory.lcOrders,
          &"{fleetId} AutoReinforce: Moving to reinforce {targetId} " &
          &"at system-{targetFleetLocation} ({minDistance} jumps)")

  let moveOrder = FleetOrder(
    fleetId: fleetId,
    orderType: FleetOrderType.Move,
    targetSystem: some(targetFleetLocation),
    priority: 100
  )
  state.fleetOrders[fleetId] = moveOrder

  return ActivationResult(success: true,
                        action: &"Move to reinforce {targetId}")

proc calculateFleetStrength(fleet: Fleet): int =
  ## Calculate raw combat strength of fleet
  ## Sum of attack strength across all ships
  result = 0
  for squadron in fleet.squadrons:
    result += squadron.flagship.stats.attackStrength
    for ship in squadron.ships:
      result += ship.stats.attackStrength

proc activateAutoEvade(state: var GameState, fleetId: FleetId,
                     params: StandingOrderParams, roe: int): ActivationResult =
  ## Execute auto-evade - retreat to fallback system when outnumbered
  ## Uses evadeTriggerRatio to determine when to retreat
  let fleet = state.fleets[fleetId]
  let currentLocation = fleet.location

  logDebug(LogCategory.lcOrders,
           &"{fleetId} AutoEvade: Checking for hostile forces at system-{currentLocation}")

  # Calculate our strength
  let ourStrength = calculateFleetStrength(fleet)

  # Find hostile fleets at current location (fog-of-war compliant)
  let knownEnemyFleets = getKnownEnemyFleetsInSystem(state, fleet.owner, currentLocation)
  var totalHostileStrength = 0
  let hostileCount = knownEnemyFleets.len

  for enemyFleet in knownEnemyFleets:
    let hostileStrength = calculateFleetStrength(enemyFleet)
    totalHostileStrength += hostileStrength

    logDebug(LogCategory.lcOrders,
             &"{fleetId} AutoEvade: Detected {enemyFleet.id} " &
             &"(strength {hostileStrength}, intel-based)")

  if hostileCount == 0:
    # No hostiles - hold position
    logDebug(LogCategory.lcOrders,
             &"{fleetId} AutoEvade: No hostile forces detected, holding position")

    let holdOrder = FleetOrder(
      fleetId: fleetId,
      orderType: FleetOrderType.Hold,
      targetSystem: none(SystemId),
      priority: 100
    )
    state.fleetOrders[fleetId] = holdOrder

    return ActivationResult(success: true,
                          action: "Hold (no hostiles)")

  # Calculate strength ratio
  let strengthRatio = if totalHostileStrength > 0:
                        ourStrength.float / totalHostileStrength.float
                      else:
                        1.0

  logDebug(LogCategory.lcOrders,
           &"{fleetId} AutoEvade: Strength ratio {strengthRatio:.2f} " &
           &"(us {ourStrength} vs them {totalHostileStrength}), " &
           &"trigger {params.evadeTriggerRatio:.2f}")

  # Check if we should retreat
  if strengthRatio >= params.evadeTriggerRatio:
    # We're strong enough - hold position
    logInfo(LogCategory.lcOrders,
            &"{fleetId} AutoEvade: Strength sufficient ({strengthRatio:.2f} >= " &
            &"{params.evadeTriggerRatio:.2f}), holding position")

    let holdOrder = FleetOrder(
      fleetId: fleetId,
      orderType: FleetOrderType.Hold,
      targetSystem: none(SystemId),
      priority: 100
    )
    state.fleetOrders[fleetId] = holdOrder

    return ActivationResult(success: true,
                          action: &"Hold (strength ratio {strengthRatio:.2f})")

  # Retreat to fallback system
  let fallbackSystem = params.fallbackSystem

  # Verify fallback system exists and is reachable
  if fallbackSystem notin state.starMap.systems:
    logWarn(LogCategory.lcOrders,
            &"{fleetId} AutoEvade failed: Fallback system-{fallbackSystem} does not exist")
    return ActivationResult(success: false,
                          error: "Fallback system does not exist")

  let pathResult = state.starMap.findPath(currentLocation, fallbackSystem, fleet)
  if not pathResult.found:
    logWarn(LogCategory.lcOrders,
            &"{fleetId} AutoEvade failed: Cannot reach fallback system-{fallbackSystem}")
    return ActivationResult(success: false,
                          error: "Cannot reach fallback system")

  let distance = pathResult.path.len - 1

  # If already at fallback, hold position
  if currentLocation == fallbackSystem:
    logInfo(LogCategory.lcOrders,
            &"{fleetId} AutoEvade: Already at fallback system-{fallbackSystem}, holding")

    let holdOrder = FleetOrder(
      fleetId: fleetId,
      orderType: FleetOrderType.Hold,
      targetSystem: none(SystemId),
      priority: 100
    )
    state.fleetOrders[fleetId] = holdOrder

    return ActivationResult(success: true,
                          action: "Hold at fallback")

  # Retreat to fallback
  logInfo(LogCategory.lcOrders,
          &"{fleetId} AutoEvade: RETREATING - outnumbered " &
          &"({strengthRatio:.2f} < {params.evadeTriggerRatio:.2f}), " &
          &"falling back to system-{fallbackSystem} ({distance} jumps)")

  let moveOrder = FleetOrder(
    fleetId: fleetId,
    orderType: FleetOrderType.Move,
    targetSystem: some(fallbackSystem),
    priority: 100
  )
  state.fleetOrders[fleetId] = moveOrder

  return ActivationResult(success: true,
                        action: &"Retreat to fallback system-{fallbackSystem}")

proc activateBlockadeTarget(state: var GameState, fleetId: FleetId,
                          params: StandingOrderParams): ActivationResult =
  ## Execute blockade target - maintain blockade on enemy colony
  ## Moves to target colony and issues BlockadePlanet order
  let fleet = state.fleets[fleetId]
  let targetColony = params.blockadeTargetColony

  logDebug(LogCategory.lcOrders,
           &"{fleetId} BlockadeTarget: Target=system-{targetColony}, " &
           &"Current=system-{fleet.location}")

  # Verify we have intel on target colony (fog-of-war compliant)
  if not hasColonyIntel(state, fleet.owner, targetColony):
    logWarn(LogCategory.lcOrders,
            &"{fleetId} BlockadeTarget failed: No intel on colony at system-{targetColony}")
    return ActivationResult(success: false,
                          error: "No intel on target colony")

  # Verify target exists and is enemy colony
  if targetColony notin state.colonies:
    logWarn(LogCategory.lcOrders,
            &"{fleetId} BlockadeTarget failed: Colony at system-{targetColony} no longer exists " &
            &"(intel may be stale)")
    return ActivationResult(success: false,
                          error: "Target colony no longer exists")

  let colony = state.colonies[targetColony]

  # Verify target is not owned by same house
  if colony.owner == fleet.owner:
    logWarn(LogCategory.lcOrders,
            &"{fleetId} BlockadeTarget failed: Cannot blockade own colony at system-{targetColony}")
    return ActivationResult(success: false,
                          error: "Cannot blockade own colony")

  # If already at target, issue blockade order
  if fleet.location == targetColony:
    logInfo(LogCategory.lcOrders,
            &"{fleetId} BlockadeTarget: At target system-{targetColony}, " &
            &"maintaining blockade (colony owner: {colony.owner})")

    let blockadeOrder = FleetOrder(
      fleetId: fleetId,
      orderType: FleetOrderType.BlockadePlanet,
      targetSystem: some(targetColony),
      priority: 100
    )
    state.fleetOrders[fleetId] = blockadeOrder

    return ActivationResult(success: true,
                          action: &"Blockade colony at system-{targetColony}")

  # Move to target colony
  let pathResult = state.starMap.findPath(fleet.location, targetColony, fleet)
  if not pathResult.found:
    logWarn(LogCategory.lcOrders,
            &"{fleetId} BlockadeTarget failed: Cannot reach target system-{targetColony}")
    return ActivationResult(success: false,
                          error: "Cannot reach target colony")

  let distance = pathResult.path.len - 1

  logInfo(LogCategory.lcOrders,
          &"{fleetId} BlockadeTarget: Moving to blockade {colony.owner} colony " &
          &"at system-{targetColony} ({distance} jumps)")

  let moveOrder = FleetOrder(
    fleetId: fleetId,
    orderType: FleetOrderType.Move,
    targetSystem: some(targetColony),
    priority: 100
  )
  state.fleetOrders[fleetId] = moveOrder

  return ActivationResult(success: true,
                        action: &"Move to blockade target at system-{targetColony}")

# =============================================================================
# Grace Period Management
# =============================================================================

proc resetStandingOrderGracePeriod*(state: var GameState, fleetId: FleetId) =
  ## Reset activation delay countdown when explicit order completes
  ## Gives player time to issue new orders before standing order reactivates
  ## Called after every order completion (via state.fleetOrders.del)
  if fleetId in state.standingOrders:
    var standingOrder = state.standingOrders[fleetId]
    standingOrder.turnsUntilActivation = standingOrder.activationDelayTurns
    state.standingOrders[fleetId] = standingOrder
    logDebug(LogCategory.lcOrders,
      &"Fleet {fleetId} standing order grace period reset to " &
      &"{standingOrder.activationDelayTurns} turn(s)")

# =============================================================================
# Main Activation Function
# =============================================================================

proc activateStandingOrder*(state: var GameState, fleetId: FleetId,
                          standingOrder: StandingOrder, turn: int): ActivationResult =
  ## Execute a single standing order
  ## Called during Command Phase for fleets without explicit orders

  case standingOrder.orderType
  of StandingOrderType.None:
    return ActivationResult(success: true, action: "No standing order")

  of StandingOrderType.PatrolRoute:
    return activatePatrolRoute(state, fleetId, standingOrder.params)

  of StandingOrderType.DefendSystem, StandingOrderType.GuardColony:
    return activateDefendSystem(state, fleetId, standingOrder.params)

  of StandingOrderType.AutoColonize:
    return activateAutoColonize(state, fleetId, standingOrder.params)

  of StandingOrderType.AutoReinforce:
    return activateAutoReinforce(state, fleetId, standingOrder.params)

  of StandingOrderType.AutoRepair:
    return activateAutoRepair(state, fleetId, standingOrder.params)

  of StandingOrderType.AutoEvade:
    return activateAutoEvade(state, fleetId, standingOrder.params, standingOrder.roe)

  of StandingOrderType.BlockadeTarget:
    return activateBlockadeTarget(state, fleetId, standingOrder.params)

proc activateStandingOrders*(state: var GameState, turn: int, events: var seq[resolution_types.GameEvent]) =
  ## Activate standing orders for all fleets without explicit orders
  ## Called during Maintenance Phase Step 1a
  ##
  ## Three-tier order lifecycle:
  ## - Initiate (Command Phase): Player configures standing order rules
  ## - Activate (Maintenance Phase): Standing orders generate fleet orders ← THIS PROC
  ## - Execute (Conflict/Income Phase): Missions happen at targets
  ##
  ## COMPREHENSIVE LOGGING:
  ## - INFO: High-level activation summary
  ## - DEBUG: Per-fleet decision logic
  ## - WARN: Failures and issues
  ##
  ## Phase 7b: Emits StandingOrderActivated events when orders activate

  logInfo(LogCategory.lcOrders,
          &"=== Standing Order Activation: Turn {turn} ===")

  # Check global master switch
  if not globalStandingOrdersConfig.activation.global_enabled:
    logInfo(LogCategory.lcOrders,
            "Standing orders globally disabled in config - skipping all activation")
    return

  var activatedCount = 0
  var skippedCount = 0
  var failedCount = 0
  var notImplementedCount = 0

  for fleetId, fleet in state.fleets:
    # Skip if fleet has explicit order this turn
    if fleetId in state.fleetOrders:
      let explicitOrder = state.fleetOrders[fleetId]
      logDebug(LogCategory.lcOrders,
               &"{fleetId} has explicit order ({explicitOrder.orderType}), " &
               &"skipping standing order")
      skippedCount += 1

      # Reset activation countdown when explicit order exists
      if fleetId in state.standingOrders:
        var standingOrder = state.standingOrders[fleetId]
        standingOrder.turnsUntilActivation = standingOrder.activationDelayTurns
        state.standingOrders[fleetId] = standingOrder

        # Emit StandingOrderSuspended event (suspended by explicit order)
        events.add(event_factory.standingOrderSuspended(
          fleet.owner,
          fleetId,
          $standingOrder.orderType,
          "explicit order issued",
          fleet.location
        ))

      continue

    # Check for standing order
    if fleetId notin state.standingOrders:
      continue

    var standingOrder = state.standingOrders[fleetId]

    # Skip if suspended
    if standingOrder.suspended:
      logDebug(LogCategory.lcOrders,
               &"{fleetId} standing order suspended, skipping")
      skippedCount += 1
      continue

    # Skip if not enabled (player control)
    if not standingOrder.enabled:
      logDebug(LogCategory.lcOrders,
               &"{fleetId} standing order disabled by player, skipping")
      skippedCount += 1
      continue

    # Check activation delay countdown
    if standingOrder.turnsUntilActivation > 0:
      # Decrement countdown
      standingOrder.turnsUntilActivation -= 1
      state.standingOrders[fleetId] = standingOrder
      logDebug(LogCategory.lcOrders,
               &"{fleetId} standing order waiting {standingOrder.turnsUntilActivation} more turn(s)")
      skippedCount += 1
      continue

    # Activate standing order
    let result = activateStandingOrder(state, fleetId, standingOrder, turn)

    if result.success:
      activatedCount += 1
      logInfo(LogCategory.lcOrders,
              &"{fleetId} activated {standingOrder.orderType}: {result.action}")

      # Get generated fleet order type
      let generatedOrderType = if fleetId in state.fleetOrders:
        $state.fleetOrders[fleetId].orderType
      else:
        "None"

      # Emit StandingOrderActivated event (Phase 7b)
      events.add(event_factory.standingOrderActivated(
        fleet.owner,
        fleetId,
        $standingOrder.orderType,
        generatedOrderType,
        result.action,
        fleet.location
      ))

      # Update activation tracking and params
      var updatedOrder = standingOrder
      updatedOrder.lastActivatedTurn = turn
      updatedOrder.activationCount += 1

      # Reset activation countdown (standing order generated a new fleet order)
      updatedOrder.turnsUntilActivation = updatedOrder.activationDelayTurns

      # Update params if returned (e.g., patrol index advanced)
      if result.updatedParams.isSome:
        updatedOrder.params = result.updatedParams.get()

      state.standingOrders[fleetId] = updatedOrder

    elif result.error == "Not yet implemented":
      notImplementedCount += 1
      logDebug(LogCategory.lcOrders,
               &"{fleetId} {standingOrder.orderType} not yet implemented")

    else:
      failedCount += 1
      logWarn(LogCategory.lcOrders,
              &"{fleetId} {standingOrder.orderType} failed: {result.error}")

  # Summary logging
  let totalAttempted = activatedCount + failedCount + notImplementedCount
  logInfo(LogCategory.lcOrders,
          &"Standing Orders Summary: {activatedCount}/{totalAttempted} activated, " &
          &"{skippedCount} skipped (explicit orders), {failedCount} failed, " &
          &"{notImplementedCount} not implemented")
