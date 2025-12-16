## Construction Trends Analyzer - Phase E
##
## Processes ConstructionActivityReport to detect enemy buildups:
## - Military buildup warnings (shipyard construction)
## - Economic expansion trends
## - Infrastructure investment patterns
## - Construction velocity analysis

import std/[tables, options, sequtils, strformat, algorithm]
import ../../../../engine/[gamestate, fog_of_war, logger]
import ../../../../engine/intelligence/types as intel_types
import ../../../../common/types/core
import ../../controller_types
import ../../config
import ../../shared/intelligence_types

proc analyzeConstructionTrends*(
  filtered: FilteredGameState,
  controller: AIController
): Table[SystemId, ConstructionTrend] =
  ## Analyze ConstructionActivityReport data for enemy buildup detection
  ## Phase E: Critical for detecting military expansion threats

  let config = controller.rbaConfig.intelligence_construction_analysis
  var trends = initTable[SystemId, ConstructionTrend]()

  # Process all construction activity reports
  for systemId, report in filtered.ownHouse.intelligence.constructionActivity:
    # Skip if not enough observations
    if report.observedTurns.len < 2:
      continue

    # Calculate shipyard growth
    var shipyardGrowth = 0
    if report.infrastructureHistory.len >= 2:
      # Find earliest observation with shipyard data
      # Note: shipyardCount is current, need to infer growth from context
      # For now, use heuristic: if shipyardCount > 0 and recent observations, assume growth
      if report.shipyardCount > 0:
        shipyardGrowth = report.shipyardCount  # Simplified - actual growth tracking would need historical data

    # Calculate construction velocity (projects per turn)
    let observationWindow = min(report.observedTurns.len, config.observation_window_turns)
    let recentProjects = report.completedSinceLastVisit.len + report.activeProjects.len
    let turnSpan = if report.observedTurns.len >= 2:
      report.observedTurns[^1] - report.observedTurns[0]
    else:
      1

    let constructionVelocity = if turnSpan > 0:
      recentProjects.float / turnSpan.float
    else:
      0.0

    # Get current infrastructure level
    let infrastructureLevel = if report.infrastructureHistory.len > 0:
      report.infrastructureHistory[^1].level
    else:
      0

    # Determine activity level
    let activityLevel = if constructionVelocity >= config.velocity_threat_threshold:
      ConstructionActivityLevel.VeryHigh
    elif constructionVelocity >= 1.0:
      ConstructionActivityLevel.High
    elif constructionVelocity >= 0.5:
      ConstructionActivityLevel.Moderate
    elif constructionVelocity > 0.0:
      ConstructionActivityLevel.Low
    else:
      ConstructionActivityLevel.Unknown

    # Store trend
    trends[systemId] = ConstructionTrend(
      systemId: systemId,
      owner: report.owner,
      observedInfrastructure: infrastructureLevel,
      observedStarbases: report.starbaseCount,
      shipyardCount: report.shipyardCount,
      constructionQueue: report.activeProjects,
      activityLevel: activityLevel,
      lastObserved: if report.observedTurns.len > 0: report.observedTurns[^1] else: 0
    )

    # Log military buildup warnings
    if report.shipyardCount >= config.buildup_threshold_shipyards:
      logInfo(LogCategory.lcAI,
              &"{controller.houseId} Drungarius: Military buildup detected - " &
              &"{report.owner} has {report.shipyardCount} shipyards at system {systemId}")

    # Log rapid expansion
    if constructionVelocity >= config.velocity_threat_threshold:
      logInfo(LogCategory.lcAI,
              &"{controller.houseId} Drungarius: Rapid expansion detected - " &
              &"{report.owner} constructing {constructionVelocity:.1f} projects/turn at system {systemId}")

  # Summary logging
  if trends.len > 0:
    var buildupSystems = 0
    var rapidExpansion = 0

    for trend in trends.values:
      if trend.shipyardCount >= config.buildup_threshold_shipyards:
        buildupSystems += 1
      if trend.activityLevel in {ConstructionActivityLevel.VeryHigh, ConstructionActivityLevel.High}:
        rapidExpansion += 1

    if buildupSystems > 0 or rapidExpansion > 0:
      logInfo(LogCategory.lcAI,
              &"{controller.houseId} Drungarius: Construction analysis - " &
              &"{buildupSystems} military buildups, {rapidExpansion} rapid expansion sites")

  result = trends

proc detectMilitaryBuildup*(
  trends: Table[SystemId, ConstructionTrend],
  config: ConstructionAnalysisConfig
): seq[tuple[systemId: SystemId, owner: HouseId, shipyards: int]] =
  ## Identify systems with significant military buildup
  ## Returns systems sorted by threat level (highest shipyard count first)

  var buildups: seq[tuple[systemId: SystemId, owner: HouseId, shipyards: int]] = @[]

  for systemId, trend in trends:
    if trend.shipyardCount >= config.buildup_threshold_shipyards:
      buildups.add((systemId, trend.owner, trend.shipyardCount))

  # Sort by shipyard count (descending)
  buildups.sort(proc (a, b: auto): int = cmp(b.shipyards, a.shipyards))

  result = buildups

proc assessEconomicExpansion*(
  trends: Table[SystemId, ConstructionTrend],
  houseId: HouseId
): tuple[totalInfrastructure: int, expansionRate: float] =
  ## Assess overall economic expansion for a specific house
  ## Returns total infrastructure and average expansion rate

  var totalInfra = 0
  var systemCount = 0
  var totalVelocity = 0.0

  for trend in trends.values:
    if trend.owner == houseId:
      totalInfra += trend.observedInfrastructure
      systemCount += 1

      # Estimate velocity from activity level
      let velocity = case trend.activityLevel
        of ConstructionActivityLevel.VeryHigh: 2.0
        of ConstructionActivityLevel.High: 1.5
        of ConstructionActivityLevel.Moderate: 0.75
        of ConstructionActivityLevel.Low: 0.25
        else: 0.0

      totalVelocity += velocity

  let avgExpansionRate = if systemCount > 0:
    totalVelocity / systemCount.float
  else:
    0.0

  result = (totalInfra, avgExpansionRate)
