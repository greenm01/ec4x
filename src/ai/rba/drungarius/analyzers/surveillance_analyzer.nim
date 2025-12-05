## Surveillance Intelligence Analyzer
##
## Processes StarbaseSurveillanceReport from engine intelligence database
## Identifies surveillance gaps and tracks automated sensor data
##
## Phase D implementation

import std/[tables, options, sequtils]
import ../../../../engine/[gamestate, fog_of_war, starmap]
import ../../../../engine/intelligence/types as intel_types
import ../../../../common/types/core
import ../../controller_types
import ../../config
import ../../shared/intelligence_types

proc analyzeSurveillanceReports*(
  filtered: FilteredGameState,
  controller: AIController
): tuple[gaps: seq[SurveillanceGap], coverage: Table[SystemId, StarbaseCoverageInfo]] =
  ## Analyze StarbaseSurveillanceReport data to identify surveillance gaps
  ## Phase D: Complete implementation

  let config = globalRBAConfig.intelligence
  var coverage = initTable[SystemId, StarbaseCoverageInfo]()
  var gaps: seq[SurveillanceGap] = @[]

  # Build coverage map from surveillance reports
  for report in filtered.ownHouse.intelligence.starbaseSurveillance:
    if report.owner != controller.houseId:
      continue  # Only process our own starbases

    coverage[report.systemId] = StarbaseCoverageInfo(
      hasStarbase: true,
      starbaseId: some(report.starbaseId),
      detectedThreats: report.detectedFleets.mapIt(it.fleetId),
      lastActivity: report.turn,
      coverageRadius: 0  # Current implementation: own system only
    )

  # Identify border systems without coverage
  for colony in filtered.ownColonies:
    if coverage.hasKey(colony.systemId):
      continue  # Already has starbase

    # Check if this is a border system (adjacent to enemy territory)
    var isBorderSystem = false
    let adjacentSystems = getAdjacentSystems(filtered.starMap, colony.systemId)

    for adjSystemId in adjacentSystems:
      if filtered.ownHouse.intelligence.colonyReports.hasKey(adjSystemId):
        let report = filtered.ownHouse.intelligence.colonyReports[adjSystemId]
        if report.targetOwner != controller.houseId:
          isBorderSystem = true
          break

    if isBorderSystem:
      gaps.add(SurveillanceGap(
        systemId: colony.systemId,
        priority: 0.9,  # config.border_system_priority (will be added to config)
        reason: SurveillanceGapReason.NoBorderCoverage,
        estimatedThreats: 0,
        lastActivity: none(int)
      ))

  # Identify high-value targets without coverage
  for colony in filtered.ownColonies:
    if coverage.hasKey(colony.systemId):
      continue  # Already has starbase

    let production = colony.colony.grossOutput
    if production >= 500:  # High-value threshold
      gaps.add(SurveillanceGap(
        systemId: colony.systemId,
        priority: 0.8,  # config.high_value_priority
        reason: SurveillanceGapReason.HighValueTarget,
        estimatedThreats: 0,
        lastActivity: none(int)
      ))

  # Identify systems with recent threat activity but no permanent coverage
  # Check if threats table exists in intelligence database
  for systemId, history in filtered.ownHouse.intelligence.fleetMovementHistory:
    if coverage.hasKey(systemId):
      continue  # Already has starbase

    if history.owner == controller.houseId:
      continue  # Our own fleet, not a threat

    # Recent enemy activity in this system
    if history.lastSeen >= filtered.turn - 5:
      var alreadyAdded = false
      for gap in gaps:
        if gap.systemId == systemId:
          alreadyAdded = true
          break

      if not alreadyAdded:
        gaps.add(SurveillanceGap(
          systemId: systemId,
          priority: 0.7,  # config.recent_activity_priority
          reason: SurveillanceGapReason.RecentThreatActivity,
          estimatedThreats: 1,
          lastActivity: some(history.lastSeen)
        ))

  result = (gaps, coverage)
