## Standing Commands Activation System
##
## Implements persistent fleet behaviors that activate automatically when
## no explicit command is given for a turn. Reduces micromanagement and provides
## quality-of-life improvements for both players and AI.
##
## Three-tier command lifecycle (applies to both active and standing commands):
## - Initiate (Command Phase Part B): Player configures standing command rules
## - Validate (Command Phase Part C): Engine validates configuration
## - Activate (Maintenance Phase Step 1a): Check conditions, generate fleet commands
## - Execute (Conflict/Income Phase): Commands execute at targets
##
## See docs/architecture/standing-commands.md for complete design.

import std/[tables, options, strformat, algorithm, sets, sequtils]
import ../../../common/logger
import ../../types/[core, game_state, command, fleet, squadron, starmap, intel, event]
import ../../starmap
import ../../state/[engine, iterators]
import ../../event_factory/init as event_factory
import ./movement # For findPath

# Export standing command types from command module
export StandingCommandType, StandingCommandParams

type ActivationResult* = object ## Result of standing command activation attempt
  success*: bool
  action*: string # Description of action taken
  error*: string # Error message if failed
  updatedParams*: Option[StandingCommandParams] # Updated params (e.g., patrol index)

# =============================================================================
# Fog-of-War Helpers (DRY Principle)
# =============================================================================

proc getKnownSystems*(state: GameState, houseId: HouseId): HashSet[SystemId] =
  ## Returns all systems the house knows about through fog-of-war
  ## Used by standing commands to avoid omniscient decisions
  ##
  ## **BUG FIX:** In early-mid game, scouts have visited ALL systems but
  ## systemReports only exist for systems with enemy fleets. This prevented
  ## AutoColonize from targeting empty frontier systems.
  ##
  ## **Solution:** Once scouts reach Act 2+, assume full map knowledge.
  ## This matches gameplay reality - scouts have been everywhere by turn 10.
  result = initHashSet[SystemId]()

  # Act 2+ (turn 8+): Full map knowledge (scouts have explored everything)
  if state.turn >= 8:
    for system in state.allSystems():
      result.incl(system.id)
    return result

  # Act 1 (turns 1-7): Fog-of-war intelligence (original logic)
  if not state.intelligence.hasKey(houseId):
    return result
  let intel = state.intelligence[houseId]

  # 1. Own colonies (always known)
  for colony in state.coloniesOwned(houseId):
    result.incl(colony.systemId)
    # Add adjacent systems (hex visibility from owned colonies) - O(1) lookup
    for adjacentId in state.starMap.getAdjacentSystems(colony.systemId):
      result.incl(adjacentId)

  # 2. Systems with intelligence reports (scouted)
  for systemId in intel.systemReports.keys:
    result.incl(systemId)

  # 3. Enemy colonies we know about - map ColonyId to SystemId
  for colonyId in intel.colonyReports.keys:
    let colonyOpt = state.colony(colonyId)
    if colonyOpt.isSome:
      result.incl(colonyOpt.get().systemId)

proc hasColonyIntel*(state: GameState, houseId: HouseId, systemId: SystemId): bool =
  ## Check if house has intel on a colony at given system
  ## Returns true if:
  ## - System has own colony (always known)
  ## - System has enemy colony with intel report

  # Own colony at system
  let colonyOpt = state.colonyBySystem(systemId)
  if colonyOpt.isSome and colonyOpt.get().owner == houseId:
    return true

  # Enemy colony with intel report
  if not state.intelligence.hasKey(houseId):
    return false
  let intel = state.intelligence[houseId]

  # Check if we have colony intel reports (reuse colonyOpt from above)
  if colonyOpt.isSome:
    let colonyId = colonyOpt.get().id
    if colonyId in intel.colonyReports:
      return true

  return false

proc getKnownEnemyFleetsInSystem*(
    state: GameState, houseId: HouseId, systemId: SystemId
): seq[Fleet] =
  ## Returns enemy fleets at system that house has intel on
  ## Used by defensive standing commands
  ##
  ## **Detection sources:**
  ## - Fleet movement history (detected by scouts/surveillance)
  ## - Combat encounters (surviving ships report enemy presence)
  ## - System intelligence reports (SpySystem missions)
  result = @[]

  if not state.intelligence.hasKey(houseId):
    return result
  let intel = state.intelligence[houseId]

  # Check system intel report for fleet presence
  let systemIntel =
    if systemId in intel.systemReports:
      some(intel.systemReports[systemId])
    else:
      none(SystemIntelReport)
  if systemIntel.isSome:
    # We have recent intel on fleets in this system
    let report = systemIntel.get()
    for fleetId in report.detectedFleetIds:
      # Only return fleets that are actually still there
      let fleetOpt = state.fleet(fleetId)
      if fleetOpt.isSome:
        let fleet = fleetOpt.get()
        if fleet.location == systemId and fleet.houseId != houseId:
          result.add(fleet)

  # Check fleet movement history for fleets detected at this location
  for fleetId, history in intel.fleetMovementHistory:
    if history.owner == houseId:
      continue # Skip own fleets

    # Check if this fleet was last seen at this system
    if history.sightings.len > 0:
      let lastSighting = history.sightings[^1] # Most recent sighting
      if lastSighting.systemId == systemId:
        # Verify fleet still exists and is at this location
        let fleetOpt = state.fleet(fleetId)
        if fleetOpt.isSome:
          let fleet = fleetOpt.get()
          if fleet.location == systemId:
            # Avoid duplicates
            if not result.anyIt(it.id == fleetId):
              result.add(fleet)

# =============================================================================
# Activation Logic - Per Order Type
# =============================================================================

proc activatePatrolRoute(
    state: var GameState, fleetId: FleetId, params: StandingCommandParams
): ActivationResult =
  ## Execute patrol route - move to next system in path
  ## Loops continuously through patrol path
  let fleetOpt = state.fleet(fleetId)
  if fleetOpt.isNone:
    return ActivationResult(success: false, error: "Fleet does not exist")
  let fleet = fleetOpt.get()
  let currentIndex = params.patrolIndex
  let nextSystem = params.patrolSystems[currentIndex]

  logDebug(
    "Orders",
    &"{fleetId} PatrolRoute: Current position {currentIndex + 1}/" &
      &"{params.patrolSystems.len} in patrol path",
  )

  # Verify target system exists and is reachable
  if state.system(nextSystem).isNone:
    logWarn(
      "Orders",
      &"{fleetId} PatrolRoute failed: Target system {nextSystem} does not exist",
    )
    return ActivationResult(
      success: false, error: &"Target system {nextSystem} does not exist"
    )

  # Generate move order to next patrol point
  let moveOrder = FleetCommand(
    fleetId: fleetId,
    commandType: FleetCommandType.Move,
    targetSystem: some(nextSystem),
    priority: 100, # Standing commands have lower priority than explicit orders
  )

  # Advance patrol index (loop back to start when reaching end)
  var newParams = params
  newParams.patrolIndex = int32((currentIndex + 1) mod params.patrolSystems.len)

  # Store order for execution
  state.fleetCommands[fleetId] = moveOrder

  logInfo(
    "Orders",
    &"{fleetId} PatrolRoute: {fleet.location} → system-{nextSystem} " &
      &"(step {currentIndex + 1}/{params.patrolSystems.len})",
  )

  return ActivationResult(
    success: true,
    action: &"Move to system-{nextSystem}",
    updatedParams: some(newParams),
  )

proc activateDefendSystem(
    state: var GameState, fleetId: FleetId, params: StandingCommandParams
): ActivationResult =
  ## Execute defend system - stay at target or return if moved away
  let fleetOpt = state.fleet(fleetId)
  if fleetOpt.isNone:
    return ActivationResult(success: false, error: "Fleet does not exist")
  let fleet = fleetOpt.get()

  # Get defend target from params
  if params.defendSystem.isNone:
    return ActivationResult(success: false, error: "No defend target system specified")
  let targetSystem = params.defendSystem.get()

  # CRITICAL: Validate target system
  if targetSystem == SystemId(0):
    logError("Orders", &"[ENGINE ACTIVATION] {fleetId} DefendSystem: BUG - defendSystem is SystemId(0)!")
    return ActivationResult(success: false, error: "Invalid defend target (SystemId 0)")

  if state.system(targetSystem).isNone:
    logWarn("Orders", &"[ENGINE ACTIVATION] {fleetId} DefendSystem: Target system {targetSystem} does not exist")
    return ActivationResult(success: false, error: "Defend target system does not exist")

  # Note: defendMaxRange not in params - using fixed range for now
  let maxRange = 5  # TODO: Add to params or config

  logDebug(
    "Orders",
    &"{fleetId} DefendSystem: Target=system-{targetSystem}, " &
      &"Current=system-{fleet.location}, MaxRange={maxRange}",
  )

  # If already at target system, patrol/guard in place
  if fleet.location == targetSystem:
    let guardOrder = FleetCommand(
      fleetId: fleetId,
      commandType: FleetCommandType.Patrol,
      targetSystem: some(targetSystem),
      priority: 100,
    )
    state.fleetCommands[fleetId] = guardOrder

    logInfo(
      "Orders",
      &"{fleetId} DefendSystem: At target system-{targetSystem}, patrolling",
    )

    return ActivationResult(success: true, action: &"Patrol system-{targetSystem}")

  # Check distance from target (via jump lanes, not as the crow flies)
  let pathResult = findPath(state.starMap, fleet.location, targetSystem, fleet, state.squadrons[], state.ships)
  if not pathResult.found:
    # Can't reach target - suspended order, log warning
    logWarn(
      "Orders",
      &"{fleetId} DefendSystem: Cannot reach target system-{targetSystem}, no valid path",
    )
    return ActivationResult(success: false, error: "No path to target system")

  let distance = pathResult.path.len - 1 # Path includes start, so subtract 1

  if distance > maxRange:
    # Too far from target - return to defensive position
    let moveOrder = FleetCommand(
      fleetId: fleetId,
      commandType: FleetCommandType.Move,
      targetSystem: some(targetSystem),
      priority: 100,
    )
    state.fleetCommands[fleetId] = moveOrder

    logInfo(
      "Orders",
      &"{fleetId} DefendSystem: {distance} jumps from target, returning to system-{targetSystem}",
    )

    return ActivationResult(success: true, action: &"Return to system-{targetSystem}")

  # Within range but not at target - hold position
  let holdOrder = FleetCommand(
    fleetId: fleetId,
    commandType: FleetCommandType.Hold,
    targetSystem: none(SystemId),
    priority: 100,
  )
  state.fleetCommands[fleetId] = holdOrder

  logInfo(
    "Orders",
    &"{fleetId} DefendSystem: {distance} jumps from target (within range {maxRange}), holding position",
  )

  return ActivationResult(success: true, action: "Hold position within defensive range")

proc scoreColonizationCandidate*(
    turn: int,
    distance: int,
    planetClass: PlanetClass,
    proximityBonus: float = 0.0,
    proximityWeightAct1: float = 0.3,
    proximityWeightAct4: float = 0.9,
): float =
  ## Calculate colonization score using Act-aware frontier expansion algorithm
  ##
  ## **Frontier Expansion (Act 1-2):** Distance 10x more important than quality
  ## **Quality Consolidation (Act 3-4):** Quality 3x more important than distance
  ## **Proximity Bonus:** Systems near owned colonies get weighted bonus (Act-aware)
  ##
  ## **Exported for reuse across engine and AI modules (DRY principle)**

  # Calculate current Act from turn number (heuristic for colonization scoring)
  # Aligned with colonization-based Act transitions (Act 1 ~15 turns, Act 2 ~22, Act 3 ~35)
  let currentAct =
    if turn <= 15:
      1
    elif turn <= 22:
      2
    elif turn <= 35:
      3
    else:
      4

  # Calculate planet quality score (0-100)
  let qualityScore =
    case planetClass
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
  let proximityWeight =
    if currentAct <= 2:
      proximityWeightAct1 # Low weight in Act 1-2 (frontier expansion)
    else:
      proximityWeightAct4 # High weight in Act 3-4 (consolidation)

  # Act-aware weighting with proximity bonus
  result =
    if currentAct <= 2:
      # Act 1-2: FRONTIER EXPANSION (Distance 10x more important than quality)
      (distanceScore * 10.0) + (qualityScore * 1.0) + (proximityBonus * proximityWeight)
    else:
      # Act 3-4: QUALITY CONSOLIDATION (Quality 3x more important than distance)
      (qualityScore * 3.0) + (distanceScore * 1.0) + (proximityBonus * proximityWeight)

proc findColonizationTarget*(
    state: GameState,
    houseId: HouseId,
    fleet: Fleet,
    currentLocation: SystemId,
    maxRange: int,
    alreadyTargeted: HashSet[SystemId],
    preferredClasses: seq[PlanetClass] = @[],
): Option[SystemId] =
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

  # Calculate current Act from turn number (heuristic for colonization scoring)
  # Aligned with colonization-based Act transitions (Act 1 ~15 turns, Act 2 ~22, Act 3 ~35)
  let currentAct =
    if state.turn <= 15:
      1
    elif state.turn <= 22:
      2
    elif state.turn <= 35:
      3
    else:
      4

  # Get known systems (fog-of-war compliant)
  let knownSystems = getKnownSystems(state, houseId)

  # Scan known systems within range
  for systemId in knownSystems:
    # Skip if system actually has a colony (ground truth check)
    # This prevents targeting systems that were colonized after our last scout
    if state.colonies.bySystem.hasKey(systemId):
      continue

    # Skip systems already targeted by other fleets (duplicate prevention)
    if systemId in alreadyTargeted:
      continue

    # Check distance via jump lanes
    let pathResult = findPath(state.starMap, currentLocation, systemId, fleet, state.squadrons[], state.ships)
    if not pathResult.found:
      continue # Can't reach this system

    let distance = pathResult.path.len - 1 # Path includes start, so subtract 1
    if distance > maxRange:
      continue

    # Get planet class
    let systemOpt = state.system(systemId)
    if systemOpt.isNone:
      continue
    let planetClass = systemOpt.get().planetClass
    candidates.add((systemId, distance, planetClass))

  if candidates.len == 0:
    logDebug(
      "Orders",
      &"findColonizationTarget: No candidates found, returning None",
    )
    return none(SystemId)

  # Score candidates using shared frontier expansion algorithm
  type ScoredCandidate =
    tuple[systemId: SystemId, score: float, distance: int, planetClass: PlanetClass]

  var scoredCandidates: seq[ScoredCandidate] = @[]

  for (systemId, distance, planetClass) in candidates:
    let score = scoreColonizationCandidate(state.turn, distance, planetClass)
    scoredCandidates.add((systemId, score, distance, planetClass))

  # Sort by score (highest first)
  scoredCandidates.sort(
    proc(a, b: ScoredCandidate): int =
      if a.score > b.score:
        -1
      elif a.score < b.score:
        1
      else:
        0
  )

  let best = scoredCandidates[0]
  logDebug(
    "Orders",
    &"findColonizationTarget: Found target system {best.systemId} " &
      &"(Act {currentAct}, {best.planetClass}, {best.distance} jumps, score={best.score:.1f})",
  )

  # CRITICAL VALIDATION: Ensure we never return SystemId(0)
  if best.systemId == SystemId(0):
    logError(
      "Orders",
      &"findColonizationTarget: BUG - best candidate is SystemId(0)! " &
        &"Candidates: {candidates.len}, returning None",
    )
    return none(SystemId)

  return some(best.systemId)

# Commented out - FilteredGameState type doesn't exist
# proc findColonizationTargetFiltered*(
#     filtered: FilteredGameState,
#     fleet: Fleet,
#     currentLocation: SystemId,
#     maxRange: int,
#     alreadyTargeted: HashSet[SystemId],
#     preferredClasses: seq[PlanetClass] = @[],
# ): Option[SystemId] =
#   ## AI-optimized wrapper that works with pre-filtered game state
#   ## Avoids redundant fog-of-war filtering when AI already has FilteredGameState
#   ##
#   ## Same Act-aware scoring and duplicate prevention as main function
#  var candidates: seq[(SystemId, int, PlanetClass)] = @[]
#
#  # Calculate current Act from turn number (heuristic for colonization scoring)
#  # Aligned with colonization-based Act transitions (Act 1 ~15 turns, Act 2 ~22, Act 3 ~35)
#  let currentAct =
#    if filtered.turn <= 15:
#      1
#    elif filtered.turn <= 22:
#      2
#    elif filtered.turn <= 35:
#      3
#    else:
#      4
#
#  # Scan visible systems within range
#  # Fog-of-war: Only visible systems are in this table (respects all players' visibility)
#  for systemId, visSystem in filtered.visibleSystems:
#    # Skip if colonized (check own colonies + visible colonies)
#    var isColonized = false
#    for colony in filtered.ownColonies:
#      if colony.systemId == systemId:
#        isColonized = true
#        break
#    if not isColonized:
#      for visColony in filtered.visibleColonies:
#        if visColony.systemId == systemId:
#          isColonized = true
#          break
#    if isColonized:
#      continue
#
#    # Skip systems already targeted by other fleets (duplicate prevention)
#    if systemId in alreadyTargeted:
#      continue
#
#    # Check distance via jump lanes (proper pathfinding)
#    let pathResult = findPath(filtered.starMap, currentLocation, systemId, fleet, filtered.squadrons[], filtered.ships)
#    if not pathResult.found:
#      continue # Can't reach this system
#
#    let distance = pathResult.path.len - 1 # Path includes start, so subtract 1
#    if distance > maxRange:
#      continue
#
#    # Get planet class from star map (VisibleSystem doesn't include planet details)
#    if systemId notin filtered.starMap.systems:
#      continue # System not in star map (shouldn't happen but be safe)
#    let system = filtered.starMap.systems[systemId]
#    let planetClass = system.planetClass
#    candidates.add((systemId, distance, planetClass))
#
#  if candidates.len == 0:
#    logDebug(
#      "Orders",
#      &"findColonizationTargetFiltered: No candidates found, returning None",
#    )
#    return none(SystemId)
#
#  # Score candidates using shared scoring function
#  type ScoredCandidate =
#    tuple[systemId: SystemId, score: float, distance: int, planetClass: PlanetClass]
#
#  var scoredCandidates: seq[ScoredCandidate] = @[]
#
#  for (systemId, distance, planetClass) in candidates:
#    let score = scoreColonizationCandidate(filtered.turn, distance, planetClass)
#    scoredCandidates.add((systemId, score, distance, planetClass))
#
#  # Sort by score (highest first)
#  scoredCandidates.sort(
#    proc(a, b: ScoredCandidate): int =
#      if a.score > b.score:
#        -1
#      elif a.score < b.score:
#        1
#      else:
#        0
#  )
#
#  let best = scoredCandidates[0]
#  logDebug(
#    "Orders",
#    &"findColonizationTargetFiltered: Found target system {best.systemId} " &
#      &"(Act {currentAct}, {best.planetClass}, ~{best.distance} hex, score={best.score:.1f})",
#  )
#
#  # CRITICAL VALIDATION: Ensure we never return SystemId(0)
#  if best.systemId == SystemId(0):
#    logError(
#      "Orders",
#      &"findColonizationTargetFiltered: BUG - best candidate is SystemId(0)! " &
#        &"Candidates: {candidates.len}, returning None",
#    )
#    return none(SystemId)
#
#  return some(best.systemId)

proc activateAutoRepair(
    state: var GameState, fleetId: FleetId, params: StandingCommandParams
): ActivationResult =
  ## Execute auto-repair - return to nearest shipyard when ships are crippled
  ## Triggers when crippled ship percentage exceeds threshold
  let fleetOpt = state.fleet(fleetId)
  if fleetOpt.isNone:
    return ActivationResult(success: false, error: "Fleet does not exist")
  let fleet = fleetOpt.get()

  # Count crippled ships vs total ships
  var totalShips = 0
  var crippledShips = 0

  for squadronId in fleet.squadrons:
    let squadronOpt = state.squadron(squadronId)
    if squadronOpt.isNone:
      continue
    let squadron = squadronOpt.get()

    # Check flagship
    totalShips += 1
    let flagshipOpt = state.ship(squadron.flagshipId)
    if flagshipOpt.isSome:
      let flagship = flagshipOpt.get()
      if flagship.isCrippled:
        crippledShips += 1

    # Include escort ships
    for shipId in squadron.ships:
      totalShips += 1
      let shipOpt = state.ship(shipId)
      if shipOpt.isSome:
        let ship = shipOpt.get()
        if ship.isCrippled:
          crippledShips += 1

  if totalShips == 0:
    # No ships (shouldn't happen, but safety check)
    return ActivationResult(success: false, error: "Fleet has no ships")

  let crippledPercent = crippledShips.float / totalShips.float

  logDebug(
    "Orders",
    &"{fleetId} AutoRepair: Fleet {crippledShips}/{totalShips} ships crippled " &
      &"({(crippledPercent * 100).int}%), " &
      &"Threshold {(params.repairThreshold * 100).int}%",
  )

  # Check if damage threshold triggered
  if crippledPercent < params.repairThreshold:
    # Fleet healthy, no repair needed
    logDebug(
      "Orders",
      &"{fleetId} AutoRepair: Fleet above damage threshold, holding position",
    )

    let holdOrder = FleetCommand(
      fleetId: fleetId,
      commandType: FleetCommandType.Hold,
      targetSystem: none(SystemId),
      priority: 100,
    )
    state.fleetCommands[fleetId] = holdOrder

    return ActivationResult(success: true, action: "Hold (fleet healthy)")

  # Fleet damaged - find nearest shipyard
  var nearestShipyard: Option[SystemId] = none(SystemId)
  var minDistance = int.high

  # Search all owned colonies for shipyards/drydocks
  for colony in state.coloniesOwned(fleet.houseId):
    # Only owned colonies with operational shipyards
    if colony.shipyardIds.len == 0:
      continue

    # Calculate distance via jump lanes
    let pathResult = findPath(state.starMap, fleet.location, colony.systemId, fleet, state.squadrons[], state.ships)
    if not pathResult.found:
      continue

    let distance = pathResult.path.len - 1
    if distance < minDistance:
      minDistance = distance
      nearestShipyard = some(colony.systemId)

  if nearestShipyard.isNone:
    # No shipyard available
    logWarn(
      "Orders",
      &"{fleetId} AutoRepair failed: No accessible shipyard found " &
        &"({crippledShips}/{totalShips} ships crippled)",
    )
    return ActivationResult(success: false, error: "No accessible shipyard")

  let targetSystem = nearestShipyard.get()

  # If already at shipyard, hold for repairs
  if fleet.location == targetSystem:
    logInfo(
      "Orders",
      &"{fleetId} AutoRepair: At shipyard system-{targetSystem}, " &
        &"holding for repairs ({crippledShips}/{totalShips} ships crippled)",
    )

    let holdOrder = FleetCommand(
      fleetId: fleetId,
      commandType: FleetCommandType.Hold,
      targetSystem: none(SystemId),
      priority: 100,
    )
    state.fleetCommands[fleetId] = holdOrder

    return ActivationResult(success: true, action: &"Hold at shipyard (repairing)")

  # Move to shipyard
  logInfo(
    "Orders",
    &"{fleetId} AutoRepair: Damaged ({crippledShips}/{totalShips} ships crippled), " &
      &"returning to shipyard at system-{targetSystem} ({minDistance} jumps)",
  )

  let moveOrder = FleetCommand(
    fleetId: fleetId,
    commandType: FleetCommandType.Move,
    targetSystem: some(targetSystem),
    priority: 100,
  )
  state.fleetCommands[fleetId] = moveOrder

  return ActivationResult(
    success: true, action: &"Return to shipyard at system-{targetSystem}"
  )

proc activateAutoReinforce(
    state: var GameState, fleetId: FleetId, params: StandingCommandParams
): ActivationResult =
  ## Execute auto-reinforce - join damaged friendly fleet
  ## Finds nearest damaged fleet and moves to join it
  let fleetOpt = state.fleet(fleetId)
  if fleetOpt.isNone:
    return ActivationResult(success: false, error: "Fleet does not exist")
  let fleet = fleetOpt.get()

  logDebug(
    "Orders",
    &"{fleetId} AutoReinforce: Searching for damaged friendly fleets",
  )

  # Find target fleet (specific or nearest damaged)
  var targetFleetId: Option[FleetId] = none(FleetId)
  var targetFleetLocation: SystemId
  var minDistance = int.high

  if params.reinforceTarget.isSome:
    # Specific target fleet
    let specificTarget = params.reinforceTarget.get()
    let targetFleetOpt = state.fleet(specificTarget)
    if targetFleetOpt.isSome:
      let targetFleet = targetFleetOpt.get()

      # Check if target belongs to same house
      if targetFleet.houseId == fleet.houseId:
        # Count crippled ships in target fleet
        var targetTotalShips = 0
        var targetCrippledShips = 0
        for squadronId in targetFleet.squadrons:
          let squadronOpt = state.squadron(squadronId)
          if squadronOpt.isNone:
            continue
          let squadron = squadronOpt.get()

          # Check flagship
          targetTotalShips += 1
          let flagshipOpt = state.ship(squadron.flagshipId)
          if flagshipOpt.isSome:
            let flagship = flagshipOpt.get()
            if flagship.isCrippled:
              targetCrippledShips += 1

          # Check escort ships
          for shipId in squadron.ships:
            targetTotalShips += 1
            let shipOpt = state.ship(shipId)
            if shipOpt.isSome:
              let ship = shipOpt.get()
              if ship.isCrippled:
                targetCrippledShips += 1

        let targetCrippledPercent =
          if targetTotalShips > 0:
            targetCrippledShips.float / targetTotalShips.float
          else:
            0.0

        # Check if target is damaged above threshold (use same threshold as repair)
        if targetCrippledPercent >= params.repairThreshold:
          targetFleetId = some(specificTarget)
          targetFleetLocation = targetFleet.location

          let pathResult =
            findPath(state.starMap, fleet.location, targetFleet.location, fleet, state.squadrons[], state.ships)
          if pathResult.found:
            minDistance = pathResult.path.len - 1

  # If no specific target or target not damaged, search for nearest damaged fleet
  if targetFleetId.isNone:
    for otherFleet in state.fleetsOwned(fleet.houseId):
      # Skip self
      if otherFleet.id == fleetId:
        continue

      # Count crippled ships
      var otherTotalShips = 0
      var otherCrippledShips = 0
      for squadronId in otherFleet.squadrons:
        let squadronOpt = state.squadron(squadronId)
        if squadronOpt.isNone:
          continue
        let squadron = squadronOpt.get()

        # Check flagship
        otherTotalShips += 1
        let flagshipOpt = state.ship(squadron.flagshipId)
        if flagshipOpt.isSome:
          let flagship = flagshipOpt.get()
          if flagship.isCrippled:
            otherCrippledShips += 1

        # Check escort ships
        for shipId in squadron.ships:
          otherTotalShips += 1
          let shipOpt = state.ship(shipId)
          if shipOpt.isSome:
            let ship = shipOpt.get()
            if ship.isCrippled:
              otherCrippledShips += 1

      if otherTotalShips == 0:
        continue

      let otherCrippledPercent = otherCrippledShips.float / otherTotalShips.float

      # Check if damaged above threshold (use same threshold as repair)
      if otherCrippledPercent < params.repairThreshold:
        continue

      # Calculate distance via jump lanes
      let pathResult =
        findPath(state.starMap, fleet.location, otherFleet.location, fleet, state.squadrons[], state.ships)
      if not pathResult.found:
        continue

      let distance = pathResult.path.len - 1
      if distance < minDistance:
        minDistance = distance
        targetFleetId = some(otherFleet.id)
        targetFleetLocation = otherFleet.location

  if targetFleetId.isNone:
    # No damaged fleets found
    logDebug(
      "Orders",
      &"{fleetId} AutoReinforce: No damaged friendly fleets found " &
        &"(threshold {(params.repairThreshold * 100).int}%)",
    )

    let holdOrder = FleetCommand(
      fleetId: fleetId,
      commandType: FleetCommandType.Hold,
      targetSystem: none(SystemId),
      priority: 100,
    )
    state.fleetCommands[fleetId] = holdOrder

    return ActivationResult(success: true, action: "Hold (no damaged fleets)")

  let targetId = targetFleetId.get()

  # If already at target location, issue JoinFleet order
  if fleet.location == targetFleetLocation:
    logInfo(
      "Orders",
      &"{fleetId} AutoReinforce: At location with {targetId}, joining fleet",
    )

    let joinOrder = FleetCommand(
      fleetId: fleetId,
      commandType: FleetCommandType.JoinFleet,
      targetFleet: some(targetId),
      priority: 100,
    )
    state.fleetCommands[fleetId] = joinOrder

    return ActivationResult(success: true, action: &"Join fleet {targetId}")

  # Move to target fleet
  logInfo(
    "Orders",
    &"{fleetId} AutoReinforce: Moving to reinforce {targetId} " &
      &"at system-{targetFleetLocation} ({minDistance} jumps)",
  )

  let moveOrder = FleetCommand(
    fleetId: fleetId,
    commandType: FleetCommandType.Move,
    targetSystem: some(targetFleetLocation),
    priority: 100,
  )
  state.fleetCommands[fleetId] = moveOrder

  return ActivationResult(success: true, action: &"Move to reinforce {targetId}")

proc calculateFleetStrength(state: GameState, fleet: Fleet): int =
  ## Calculate raw combat strength of fleet
  ## Sum of attack strength across all ships
  result = 0
  for squadronId in fleet.squadrons:
    let squadronOpt = state.squadron(squadronId)
    if squadronOpt.isNone:
      continue
    let squadron = squadronOpt.get()

    # Add flagship strength
    let flagshipOpt = state.ship(squadron.flagshipId)
    if flagshipOpt.isSome:
      let flagship = flagshipOpt.get()
      result += flagship.stats.attackStrength

    # Add escort ship strength
    for shipId in squadron.ships:
      let shipOpt = state.ship(shipId)
      if shipOpt.isSome:
        let ship = shipOpt.get()
        result += ship.stats.attackStrength

proc activateBlockadeTarget(
    state: var GameState, fleetId: FleetId, params: StandingCommandParams
): ActivationResult =
  ## Execute blockade target - maintain blockade on enemy colony
  ## Moves to target colony and issues BlockadePlanet order
  let fleetOpt = state.fleet(fleetId)
  if fleetOpt.isNone:
    return ActivationResult(success: false, error: "Fleet does not exist")
  let fleet = fleetOpt.get()

  # Get target colony from params
  if params.blockadeTargetColony.isNone:
    return ActivationResult(success: false, error: "No blockade target specified")
  let targetColonyId = params.blockadeTargetColony.get()

  # Get colony entity to find its system
  let colonyOpt = state.colony(targetColonyId)
  if colonyOpt.isNone:
    return ActivationResult(success: false, error: "Target colony no longer exists")
  let colony = colonyOpt.get()
  let targetSystem = colony.systemId

  logDebug(
    "Orders",
    &"{fleetId} BlockadeTarget: Target=system-{targetSystem}, " &
      &"Current=system-{fleet.location}",
  )

  # Verify we have intel on target colony (fog-of-war compliant)
  if not hasColonyIntel(state, fleet.houseId, targetSystem):
    logWarn(
      "Orders",
      &"{fleetId} BlockadeTarget failed: No intel on colony at system-{targetSystem}",
    )
    return ActivationResult(success: false, error: "No intel on target colony")

  # Verify target is not owned by same house
  if colony.owner == fleet.houseId:
    logWarn(
      "Orders",
      &"{fleetId} BlockadeTarget failed: Cannot blockade own colony at system-{targetSystem}",
    )
    return ActivationResult(success: false, error: "Cannot blockade own colony")

  # If already at target, issue blockade order
  if fleet.location == targetSystem:
    logInfo(
      "Orders",
      &"{fleetId} BlockadeTarget: At target system-{targetSystem}, " &
        &"maintaining blockade (colony owner: {colony.owner})",
    )

    let blockadeOrder = FleetCommand(
      fleetId: fleetId,
      commandType: FleetCommandType.Blockade,
      targetSystem: some(targetSystem),
      priority: 100,
    )
    state.fleetCommands[fleetId] = blockadeOrder

    return ActivationResult(
      success: true, action: &"Blockade colony at system-{targetSystem}"
    )

  # Move to target colony
  let pathResult = findPath(state.starMap, fleet.location, targetSystem, fleet, state.squadrons[], state.ships)
  if not pathResult.found:
    logWarn(
      "Orders",
      &"{fleetId} BlockadeTarget failed: Cannot reach target system-{targetSystem}",
    )
    return ActivationResult(success: false, error: "Cannot reach target colony")

  let distance = pathResult.path.len - 1

  logInfo(
    "Orders",
    &"{fleetId} BlockadeTarget: Moving to blockade {colony.owner} colony " &
      &"at system-{targetSystem} ({distance} jumps)",
  )

  let moveOrder = FleetCommand(
    fleetId: fleetId,
    commandType: FleetCommandType.Move,
    targetSystem: some(targetSystem),
    priority: 100,
  )
  state.fleetCommands[fleetId] = moveOrder

  return ActivationResult(
    success: true, action: &"Move to blockade target at system-{targetSystem}"
  )

# =============================================================================
# Grace Period Management
# =============================================================================

proc resetStandingCommandGracePeriod*(state: var GameState, fleetId: FleetId) =
  ## Reset activation delay countdown when explicit order completes
  ## Gives player time to issue new orders before standing command reactivates
  ## Called after every order completion (via state.fleetCommands.del)
  if fleetId in state.standingCommands:
    var standingOrder = state.standingCommands[fleetId]
    standingOrder.turnsUntilActivation = standingOrder.activationDelayTurns
    state.standingCommands[fleetId] = standingOrder
    logDebug(
      "Orders",
      &"Fleet {fleetId} standing command grace period reset to " &
        &"{standingOrder.activationDelayTurns} turn(s)",
    )

# =============================================================================
# Main Activation Function
# =============================================================================

proc activateStandingCommand*(
    state: var GameState, fleetId: FleetId, standingCommand: StandingCommand, turn: int
): ActivationResult =
  ## Execute a single standing command
  ## Called during Command Phase for fleets without explicit orders

  case standingCommand.commandType
  of StandingCommandType.None:
    return ActivationResult(success: true, action: "No standing command")
  of StandingCommandType.PatrolRoute:
    return activatePatrolRoute(state, fleetId, standingCommand.params)
  of StandingCommandType.DefendSystem, StandingCommandType.GuardColony:
    return activateDefendSystem(state, fleetId, standingCommand.params)
  of StandingCommandType.AutoReinforce:
    return activateAutoReinforce(state, fleetId, standingCommand.params)
  of StandingCommandType.AutoRepair:
    return activateAutoRepair(state, fleetId, standingCommand.params)
  of StandingCommandType.BlockadeTarget:
    return activateBlockadeTarget(state, fleetId, standingCommand.params)

proc activateStandingCommands*(
    state: var GameState, turn: int, events: var seq[GameEvent]
) =
  ## Activate standing commands for all fleets without explicit orders
  ## Called during Maintenance Phase Step 1a
  ##
  ## Three-tier order lifecycle:
  ## - Initiate (Command Phase): Player configures standing command rules
  ## - Activate (Maintenance Phase): Standing commands generate fleet orders ← THIS PROC
  ## - Execute (Conflict/Income Phase): Missions happen at targets
  ##
  ## COMPREHENSIVE LOGGING:
  ## - INFO: High-level activation summary
  ## - DEBUG: Per-fleet decision logic
  ## - WARN: Failures and issues
  ##
  ## Phase 7b: Emits StandingOrderActivated events when orders activate

  logInfo("Orders", &"=== Standing Order Activation: Turn {turn} ===")

  # TODO: Check global master switch (config needed)
  # if not globalStandingOrdersConfig.activation.global_enabled:
  #   logInfo("Orders", "Standing commands globally disabled in config - skipping all activation")
  #   return

  var activatedCount = 0
  var skippedCount = 0
  var failedCount = 0
  var notImplementedCount = 0
  var noStandingOrderCount = 0 # Fleets without standing commands assigned

  for fleet in state.allFleets():
    let fleetId = fleet.id
    # Skip if fleet has explicit order this turn
    if fleetId in state.fleetCommands:
      let explicitOrder = state.fleetCommands[fleetId]
      logDebug(
        "Orders",
        &"{fleetId} has explicit order ({explicitOrder.commandType}), " &
          &"skipping standing command",
      )
      skippedCount += 1

      # Reset activation countdown when explicit order exists
      if fleetId in state.standingCommands:
        var standingOrder = state.standingCommands[fleetId]
        standingOrder.turnsUntilActivation = standingOrder.activationDelayTurns
        state.standingCommands[fleetId] = standingOrder

        # Emit StandingOrderSuspended event (suspended by explicit order)
        events.add(
          event_factory.standingOrderSuspended(
            fleet.houseId,
            fleetId,
            $standingOrder.commandType,
            "explicit order issued",
            fleet.location,
          )
        )

      continue

    # Check for standing command
    if fleetId notin state.standingCommands:
      logDebug(
        "Orders",
        &"{fleetId} (owner: {fleet.houseId}) has no standing command assigned, skipping",
      )
      noStandingOrderCount += 1
      continue

    var standingOrder = state.standingCommands[fleetId]

    # TODO: Skip if suspended or disabled (fields need to be added to StandingCommand type)
    # if standingOrder.suspended:
    #   logDebug("Orders", &"{fleetId} standing command suspended, skipping")
    #   skippedCount += 1
    #   continue
    # if not standingOrder.enabled:
    #   logDebug("Orders", &"{fleetId} standing command disabled by player, skipping")
    #   skippedCount += 1
    #   continue

    # Check activation delay countdown
    if standingOrder.turnsUntilActivation > 0:
      # Decrement countdown
      standingOrder.turnsUntilActivation -= 1
      state.standingCommands[fleetId] = standingOrder
      logDebug(
        "Orders",
        &"{fleetId} standing command waiting {standingOrder.turnsUntilActivation} more turn(s)",
      )
      skippedCount += 1
      continue

    # Activate standing command
    let result = activateStandingCommand(state, fleetId, standingOrder, turn)

    if result.success:
      activatedCount += 1
      logInfo(
        "Orders",
        &"{fleetId} activated {standingOrder.commandType}: {result.action}",
      )

      # Get generated fleet order type
      let generatedOrderType =
        if fleetId in state.fleetCommands:
          $state.fleetCommands[fleetId].commandType
        else:
          "None"

      # Emit StandingOrderActivated event (Phase 7b)
      events.add(
        event_factory.standingOrderActivated(
          fleet.houseId,
          fleetId,
          $standingOrder.commandType,
          generatedOrderType,
          result.action,
          fleet.location,
        )
      )

      # Update activation tracking and params
      var updatedOrder = standingOrder
      # TODO: Track activation history (fields need to be added to StandingCommand type)
      # updatedOrder.lastActivatedTurn = turn
      # updatedOrder.activationCount += 1

      # Reset activation countdown (standing command generated a new fleet order)
      updatedOrder.turnsUntilActivation = updatedOrder.activationDelayTurns

      # Update params if returned (e.g., patrol index advanced)
      if result.updatedParams.isSome:
        updatedOrder.params = result.updatedParams.get()

      state.standingCommands[fleetId] = updatedOrder
    elif result.error == "Not yet implemented":
      notImplementedCount += 1
      logDebug(
        "Orders",
        &"{fleetId} {standingOrder.commandType} not yet implemented",
      )
    else:
      failedCount += 1
      logWarn(
        "Orders",
        &"{fleetId} {standingOrder.commandType} failed: {result.error}",
      )

  # Summary logging
  let totalAttempted = activatedCount + failedCount + notImplementedCount
  let totalFleets = state.fleetsCount()
  logInfo(
    "Orders",
    &"Standing Orders Summary: {totalFleets} total fleets, " &
      &"{noStandingOrderCount} without standing commands, " &
      &"{skippedCount} skipped (explicit orders/suspended/disabled/delay), " &
      &"{activatedCount}/{totalAttempted} activated, " &
      &"{failedCount} failed, {notImplementedCount} not implemented",
  )
