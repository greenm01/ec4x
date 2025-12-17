## System Intelligence Analyzer
##
## Processes SystemIntelReport from engine intelligence database
## Tracks enemy fleet movements and composition
##
## Phase B implementation - second priority analyzer

import std/[tables, options, sets, algorithm, strformat]
import ../../../../engine/[gamestate, fog_of_war, starmap, fleet, logger]
import ../../../../engine/intelligence/types as intel_types
import ../../../../common/types/core
import ../../controller_types
import ../../config
import ../../shared/intelligence_types
import ../../intelligence # For calculateDistance

proc analyzeFleetComposition(squadronDetails: Option[seq[intel_types.SquadronIntel]]): FleetComposition =
  ## Analyze squadron details to determine fleet composition
  result = FleetComposition(
    capitalShips: 0,
    cruisers: 0,
    destroyers: 0,
    escorts: 0,
    scouts: 0,
    expansionShips: 0,
    auxiliaryShips: 0,
    totalShips: 0,
    avgTechLevel: 0
  )

  if squadronDetails.isNone:
    return

  var techLevelSum = 0
  var techLevelCount = 0

  for squadron in squadronDetails.get():
    let shipCount = squadron.shipCount
    result.totalShips += shipCount

    # Classify by ship class
    case squadron.shipClass
    of "Battleship", "Carrier":
      result.capitalShips += shipCount
    of "Cruiser":
      result.cruisers += shipCount
    of "Destroyer":
      result.destroyers += shipCount
    of "Escort", "Frigate":
      result.escorts += shipCount
    of "Scout":
      result.scouts += shipCount
    else:
      discard  # Unknown type

    # Track tech level
    if squadron.techLevel > 0:
      techLevelSum += squadron.techLevel * shipCount
      techLevelCount += shipCount

  # Calculate average tech level
  if techLevelCount > 0:
    result.avgTechLevel = techLevelSum div techLevelCount

proc findThreatenedColonies(
  fleetLocation: SystemId,
  ownColonies: seq[Colony],
  starMap: StarMap,
  threatRadius: int
): seq[SystemId] =
  ## Find friendly colonies within threat range of enemy fleet
  result = @[]
  for colony in ownColonies:
    let distance = calculateDistance(starMap, fleetLocation, colony.systemId)
    if distance <= threatRadius:
      result.add(colony.systemId)

proc analyzeSystemIntelligence*(
  filtered: FilteredGameState,
  controller: AIController
): seq[EnemyFleetSummary] =
  ## Analyze SystemIntelReport data to track enemy fleet locations and composition
  ## Phase B implementation

  result = @[]
  let config = controller.rbaConfig.intelligence
  var processedFleets = initHashSet[FleetId]()

  # Process SystemIntelReports (detailed fleet intel)
  for systemId, report in filtered.ownHouse.intelligence.systemReports:
    for fleetIntel in report.detectedFleets:
      # Skip own fleets
      if fleetIntel.owner == controller.houseId:
        continue

      # Skip if already processed
      if fleetIntel.fleetId in processedFleets:
        continue
      processedFleets.incl(fleetIntel.fleetId)

      # Analyze composition
      let composition = analyzeFleetComposition(fleetIntel.squadronDetails)

      # Calculate estimated strength
      let estimatedStrength =
        composition.capitalShips * 200 +
        composition.cruisers * 100 +
        composition.destroyers * 50 +
        composition.escorts * 25 +
        composition.scouts * 10

      # Find threatened colonies
      let threatened = findThreatenedColonies(
        fleetIntel.location,
        filtered.ownColonies,
        filtered.starMap,
        config.threat_high_distance
      )

      result.add(EnemyFleetSummary(
        fleetId: fleetIntel.fleetId,
        owner: fleetIntel.owner,
        lastKnownLocation: fleetIntel.location,
        lastSeen: report.gatheredTurn,
        estimatedStrength: estimatedStrength,
        composition: some(composition),
        threatenedColonies: threatened,
        isMoving: false  # Can't determine from static report
      ))

  # Supplement with FleetMovementHistory (for fleets without detailed intel)
  for fleetId, history in filtered.ownHouse.intelligence.fleetMovementHistory:
    # Skip own fleets
    if history.owner == controller.houseId:
      continue

    # Skip if already processed from SystemIntelReport
    if fleetId in processedFleets:
      continue

    # Find threatened colonies
    let threatened = findThreatenedColonies(
      history.lastKnownLocation,
      filtered.ownColonies,
      filtered.starMap,
      config.threat_high_distance
    )

    # Rough strength estimate (we don't have composition data)
    let roughStrength = 100  # Default unknown fleet strength

    result.add(EnemyFleetSummary(
      fleetId: fleetId,
      owner: history.owner,
      lastKnownLocation: history.lastKnownLocation,
      lastSeen: history.lastSeen,
      estimatedStrength: roughStrength,
      composition: none(FleetComposition),
      threatenedColonies: threatened,
      isMoving: false
    ))

  # Sort by threat level (strength * threatened colonies)
  result.sort(proc(a, b: EnemyFleetSummary): int =
    let aThreat = a.estimatedStrength * max(a.threatenedColonies.len, 1)
    let bThreat = b.estimatedStrength * max(b.threatenedColonies.len, 1)
    return cmp(bThreat, aThreat)  # Descending (highest threat first)
  )

# ==============================================================================
# PHASE E: PATROL PATTERN DETECTION
# ==============================================================================

proc analyzeMovementPattern(
  sightings: seq[tuple[turn: int, systemId: SystemId]]
): tuple[isPattern: bool, confidence: float, route: seq[SystemId]] =
  ## Analyze sighting sequence to detect repeating patterns
  ## Returns true if pattern detected with confidence level

  result.isPattern = false
  result.confidence = 0.0
  result.route = @[]

  if sightings.len < 3:
    return

  # Extract system sequence
  var systemSequence: seq[SystemId] = @[]
  for sighting in sightings:
    # Avoid duplicate consecutive sightings
    if systemSequence.len == 0 or systemSequence[^1] != sighting.systemId:
      systemSequence.add(sighting.systemId)

  if systemSequence.len < 3:
    return

  # Look for repeating subsequences
  # Try different pattern lengths (3-6 systems)
  for patternLen in 3..min(6, systemSequence.len div 2):
    let pattern = systemSequence[0..<patternLen]
    var matches = 0
    var totalChecks = 0

    # Count how many times this pattern repeats
    var i = patternLen
    while i + patternLen <= systemSequence.len:
      totalChecks += 1
      let subsequence = systemSequence[i..<(i + patternLen)]
      if subsequence == pattern:
        matches += 1
      i += patternLen

    if totalChecks > 0:
      let matchRate = matches.float / totalChecks.float
      if matchRate >= 0.7:  # 70% match rate = strong pattern
        result.isPattern = true
        result.confidence = matchRate
        result.route = pattern
        return

  # No strong pattern found
  result.isPattern = false

proc detectPatrolRoutes*(
  filtered: FilteredGameState,
  controller: AIController
): seq[PatrolRoute] =
  ## Detect enemy patrol routes from FleetMovementHistory
  ## Phase E: Enables predictive threat modeling

  let config = controller.rbaConfig.intelligence_patrol_detection
  var routes: seq[PatrolRoute] = @[]

  # Process fleet movement history
  for fleetId, history in filtered.ownHouse.intelligence.fleetMovementHistory:
    # Skip own fleets
    if history.owner == controller.houseId:
      continue

    # Need minimum sightings to detect pattern
    if history.sightings.len < config.min_sightings_for_pattern:
      continue

    # Check if pattern is stale
    if history.lastSeen < filtered.turn - config.staleness_threshold_turns:
      continue

    # Analyze sighting pattern for repeating routes
    let pattern = analyzeMovementPattern(history.sightings)

    if pattern.isPattern and pattern.confidence >= config.pattern_confidence_threshold:
      routes.add(PatrolRoute(
        fleetId: fleetId,
        owner: history.owner,
        systems: pattern.route,
        confidence: pattern.confidence,
        lastUpdated: history.lastSeen
      ))

      # Log detected patrol
      logInfo(LogCategory.lcAI,
              &"{controller.houseId} Drungarius: Patrol route detected - " &
              &"Fleet {fleetId} ({history.owner}) - {pattern.route.len} systems, " &
              &"confidence {pattern.confidence * 100:.0f}%")

  result = routes

# ==============================================================================
# PHASE 2.3: FLEET MOVEMENT TRACKING
# ==============================================================================

proc trackFleetMovements*(
  filtered: FilteredGameState,
  previousSnapshot: Option[IntelligenceSnapshot],
  currentTurn: int
): Table[HouseId, seq[FleetMovement]] =
  ## Track enemy fleet movements by comparing current positions with previous snapshot
  ## Detects when fleets change systems between turns
  ## Phase 2.3: Enables predictive defense allocation

  result = initTable[HouseId, seq[FleetMovement]]()

  # If no previous snapshot, can't detect movement
  if previousSnapshot.isNone:
    return

  let prevSnap = previousSnapshot.get()

  # Build map of previous fleet positions from previous snapshot
  var previousPositions = initTable[FleetId, SystemId]()
  for houseId, movements in prevSnap.enemyFleetMovements:
    for movement in movements:
      previousPositions[movement.fleetId] = movement.lastKnownLocation

  # Check current fleet positions from FleetMovementHistory
  for fleetId, history in filtered.ownHouse.intelligence.fleetMovementHistory:
    # Skip own fleets
    if history.owner == filtered.viewingHouse:
      continue

    # Check if we saw this fleet in previous snapshot
    if not previousPositions.hasKey(fleetId):
      # New fleet detected - not a movement, just first sighting
      continue

    let previousLocation = previousPositions[fleetId]
    let currentLocation = history.lastKnownLocation

    # Detect movement: fleet changed systems
    if previousLocation != currentLocation:
      # Movement detected!
      let movement = FleetMovement(
        fleetId: fleetId,
        owner: history.owner,
        lastKnownLocation: currentLocation,
        lastSeenTurn: history.lastSeen,
        estimatedStrength: 0  # TODO: Track strength from SystemIntelReport
      )

      # Add to result table
      if not result.hasKey(history.owner):
        result[history.owner] = @[]
      result[history.owner].add(movement)

      # Log detected movement
      logInfo(LogCategory.lcAI,
              &"Fleet movement detected - Fleet {fleetId} ({history.owner}) " &
              &"moved from {previousLocation} to {currentLocation}")

  return result
