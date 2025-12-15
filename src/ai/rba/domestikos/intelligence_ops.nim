## Domestikos Intelligence Operations
##
## Extracted from build_requirements.nim to maintain file size limits
## Handles threat assessment and intelligence-driven military analysis

import std/tables # Removed options
import ../../../engine/[gamestate, fog_of_war, fleet, starmap]
import ../../../common/types/core
import ../controller_types # For AIController
import ../controller_types # For AIController
import ../config
import ../shared/intelligence_types

proc estimateLocalThreat*(
  systemId: SystemId,
  filtered: FilteredGameState,
  controller: AIController
): float =
  ## Estimate threat level at a system (0.0-1.0)
  ## DEPRECATED: Use estimateLocalThreatFromIntel() for Phase B+ intelligence
  ## Kept for backward compatibility during transition
  result = 0.0

  let config = globalRBAConfig.domestikos
  let radius = config.threat_assessment_radius

  # Check intelligence database for enemy fleets nearby
  for fleetId, history in filtered.ownHouse.intelligence.fleetMovementHistory:
    if history.owner == controller.houseId:
      continue  # Skip own fleets

    # Calculate distance to threat
    let pathResult = filtered.starMap.findPath(systemId, history.lastKnownLocation, Fleet())
    if pathResult.found:
      let distance = pathResult.path.len
      if distance <= radius:
        # Threat decreases with distance
        let threatContribution = 1.0 - (distance.float / radius.float)
        result += threatContribution * globalRBAConfig.domestikos.intelligence_ops.threat_contribution_per_fleet

  # Cap at 1.0
  result = min(result, 1.0)

proc estimateLocalThreatFromIntel*(
  systemId: SystemId,
  intelSnapshot: IntelligenceSnapshot
): float =
  ## Enhanced threat estimation using IntelligenceSnapshot (Phase B+)
  ## Uses unified threat assessment with multi-factor calculation
  ## Returns: 0.0-1.0 threat level

  # Check if we have a threat assessment for this colony
  if intelSnapshot.military.threatsByColony.hasKey(systemId):
    let threat = intelSnapshot.military.threatsByColony[systemId]

    # Convert ThreatLevel to float (0.0-1.0)
    result = case threat.level:
      of tlCritical: 1.0
      of tlHigh: globalRBAConfig.domestikos.intelligence_ops.threat_level_high_score
      of tlModerate: globalRBAConfig.domestikos.intelligence_ops.threat_level_moderate_score
      of tlLow: globalRBAConfig.domestikos.intelligence_ops.threat_level_low_score
      of tlNone: 0.0

    # Adjust by confidence (reduce threat if intel is stale)
    result = result * threat.confidence
  else:
    # No threat detected
    result = 0.0
