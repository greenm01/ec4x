## Unified Threat Assessment Module
##
## Aggregates intelligence from all sources to produce per-colony threat assessments
## Phase B implementation - combines colony and system intelligence

import std/[tables, options]
import ../../../engine/[gamestate, fog_of_war, starmap, fleet]
import ../../../common/types/core
import ../controller_types # For AIController
import ../config
import ../shared/intelligence_types
import ../intelligence # For calculateDistance

proc assessColonyThreat*(
  colonyId: SystemId,
  filtered: FilteredGameState,
  enemyFleets: seq[EnemyFleetSummary],
  config: IntelligenceConfig,
  currentTurn: int
): ThreatAssessment =
  ## Assess threat level for a specific colony based on nearby enemy fleets
  ## Uses multi-factor threat calculation with configurable weights

  result = ThreatAssessment(
    systemId: colonyId,
    level: intelligence_types.ThreatLevel.tlNone,
    nearbyEnemyFleets: 0,
    estimatedEnemyStrength: 0,
    turnsUntilArrival: none(int),
    threatSources: @[],
    confidence: 1.0,
    lastUpdated: currentTurn
  )

  var totalThreat = 0.0
  var nearestFleetDistance = 999
  var threatFactors: seq[tuple[fleetId: FleetId, contribution: float]] = @[]

  # Analyze each enemy fleet for threat contribution
  for fleet in enemyFleets:
    let distance = calculateDistance(filtered.starMap, fleet.lastKnownLocation, colonyId)

    # Skip if too far away to be a threat
    if distance > config.threat_moderate_distance:
      continue

    # Calculate threat components
    var fleetThreat = 0.0

    # 1. Fleet strength factor (weight: 0.4)
    let strengthFactor = (fleet.estimatedStrength.float / 1000.0) * config.threat_fleet_strength_weight
    fleetThreat += strengthFactor

    # 2. Proximity factor (weight: 0.3)
    let proximityFactor = if distance <= config.threat_critical_distance:
      1.0 * config.threat_proximity_weight
    elif distance <= config.threat_high_distance:
      0.7 * config.threat_proximity_weight
    elif distance <= config.threat_moderate_distance:
      0.4 * config.threat_proximity_weight
    else:
      0.0
    fleetThreat += proximityFactor

    # 3. Recent activity factor (weight: 0.3)
    let intelAge = currentTurn - fleet.lastSeen
    let freshnessFactor = if intelAge <= 2:
      1.0 * config.threat_recent_activity_weight  # Very fresh intel
    elif intelAge <= 5:
      0.7 * config.threat_recent_activity_weight  # Recent intel
    elif intelAge <= 10:
      0.4 * config.threat_recent_activity_weight  # Aging intel
    else:
      0.1 * config.threat_recent_activity_weight  # Stale intel
    fleetThreat += freshnessFactor

    # Accumulate threat
    totalThreat += fleetThreat
    result.nearbyEnemyFleets += 1
    result.estimatedEnemyStrength += fleet.estimatedStrength
    result.threatSources.add(fleet.fleetId)
    threatFactors.add((fleet.fleetId, fleetThreat))

    # Track nearest fleet
    if distance < nearestFleetDistance:
      nearestFleetDistance = distance

  # Determine threat level based on total threat score
  if totalThreat >= 1.5:
    result.level = intelligence_types.ThreatLevel.tlCritical
  elif totalThreat >= 1.0:
    result.level = intelligence_types.ThreatLevel.tlHigh
  elif totalThreat >= 0.5:
    result.level = intelligence_types.ThreatLevel.tlModerate
  elif totalThreat >= 0.2:
    result.level = intelligence_types.ThreatLevel.tlLow
  else:
    result.level = intelligence_types.ThreatLevel.tlNone

  # Estimate turns until arrival (for nearest fleet)
  if nearestFleetDistance < 999:
    result.turnsUntilArrival = some(nearestFleetDistance)  # Assume 1 jump/turn

  # Calculate confidence based on intel freshness
  if result.nearbyEnemyFleets > 0:
    var avgIntelAge = 0
    for fleet in enemyFleets:
      if fleet.fleetId in result.threatSources:
        avgIntelAge += (currentTurn - fleet.lastSeen)
    avgIntelAge = avgIntelAge div result.nearbyEnemyFleets

    # Confidence decreases with intel age
    result.confidence = if avgIntelAge <= 2:
      1.0
    elif avgIntelAge <= 5:
      0.9
    elif avgIntelAge <= 10:
      0.7
    else:
      0.5

proc assessAllThreats*(
  filtered: FilteredGameState,
  enemyFleets: seq[EnemyFleetSummary],
  config: IntelligenceConfig,
  currentTurn: int
): Table[SystemId, ThreatAssessment] =
  ## Generate threat assessments for all friendly colonies
  result = initTable[SystemId, ThreatAssessment]()

  for colony in filtered.ownColonies:
    let threat = assessColonyThreat(
      colony.systemId,
      filtered,
      enemyFleets,
      config,
      currentTurn
    )

    # Only store non-None threats
    if threat.level != intelligence_types.ThreatLevel.tlNone:
      result[colony.systemId] = threat

proc calculateMaxThreatLevel*(threats: Table[SystemId, ThreatAssessment]): float =
  ## Calculate maximum threat level across all colonies (0.0-1.0)
  ## Used by Treasurer for dynamic budget allocation
  result = 0.0

  for systemId, threat in threats:
    let threatValue = case threat.level:
      of tlCritical: 1.0
      of tlHigh: 0.75
      of tlModerate: 0.5
      of tlLow: 0.25
      of tlNone: 0.0

    if threatValue > result:
      result = threatValue
