## Colony Intelligence Analyzer
##
## Processes ColonyIntelReport from engine intelligence database
## Generates military vulnerability and economic value assessments
##
## Phase B implementation - highest priority analyzer

import std/[tables, options, algorithm, strformat]
import ../../../../engine/[gamestate, fog_of_war, starmap, fleet, logger]
import ../../../../engine/intelligence/types as intel_types
import ../../../../common/types/core
import ../../controller_types
import ../../config
import ../../shared/intelligence_types
import ../../intelligence # For calculateDistance

proc findNearestOwnColony(systemId: SystemId, ownColonies: seq[Colony], starMap: StarMap): int =
  ## Find distance to nearest friendly colony
  var minDistance = 999
  for colony in ownColonies:
    let distance = calculateDistance(starMap, colony.systemId, systemId)
    if distance < minDistance:
      minDistance = distance
  return minDistance

proc analyzeColonyIntelligence*(
  filtered: FilteredGameState,
  controller: AIController
): tuple[vulnerableTargets: seq[InvasionOpportunity], highValueTargets: seq[HighValueTarget]] =
  ## Analyze ColonyIntelReport data to identify vulnerable and high-value enemy colonies
  ## Phase B implementation

  result.vulnerableTargets = @[]
  result.highValueTargets = @[]

  let config = globalRBAConfig.intelligence

  # Phase 1 diagnostic: Log intelligence database size
  logInfo(LogCategory.lcAI,
    &"{filtered.viewingHouse} Colony Analyzer: Processing " &
    &"{filtered.ownHouse.intelligence.colonyReports.len} colony intel reports")

  # Iterate through all colony intelligence reports
  for systemId, report in filtered.ownHouse.intelligence.colonyReports:
    # Skip own colonies
    if report.targetOwner == controller.houseId:
      continue

    # Calculate economic value (grossOutput + industry production equivalent)
    let grossOutput = report.grossOutput.get(0)  # Default to 0 if unknown
    let industryValue = report.industry * 100  # Each IU worth ~100 PP/turn
    let economicValue = grossOutput + industryValue

    # Calculate defense strength
    let groundDefenses = report.defenses * 10  # Each ground unit worth ~10 points
    let starbaseStrength = report.starbaseLevel * 100  # Starbase worth ~100 points
    let orbitalDefenses = report.unassignedSquadronCount * 50 + report.reserveFleetCount * 75
    let totalDefenseStrength = groundDefenses + starbaseStrength + orbitalDefenses

    # High-value target assessment
    if economicValue > config.vulnerability_value_threshold:
      result.highValueTargets.add(HighValueTarget(
        systemId: systemId,
        owner: report.targetOwner,
        estimatedValue: economicValue,
        estimatedDefenses: totalDefenseStrength,
        hasStarbase: report.starbaseLevel > 0,
        shipyardCount: report.shipyardCount,
        lastUpdated: report.gatheredTurn,
        intelQuality: report.quality
      ))

    # Vulnerability assessment: weak defenses relative to value
    if economicValue > 0:
      let defenseRatio = totalDefenseStrength.float / economicValue.float

      # Log ALL candidate evaluations for diagnostic visibility
      logDebug(LogCategory.lcAI,
        &"{filtered.viewingHouse} Colony Analyzer: Evaluating system {systemId} " &
        &"(owner: {report.targetOwner}) - value={economicValue}, " &
        &"defenses={totalDefenseStrength}, ratio={defenseRatio:.2f}")

      if defenseRatio < config.vulnerability_defense_ratio_threshold:
        logInfo(LogCategory.lcAI,
          &"{filtered.viewingHouse} Colony Analyzer: TARGET IDENTIFIED - {systemId}")
        # Vulnerable: weak defenses for its value
        let distance = findNearestOwnColony(systemId, filtered.ownColonies, filtered.starMap)

        # Estimate force required (defenses + buffer)
        let requiredForce = totalDefenseStrength + (totalDefenseStrength div 2)  # 1.5x defenses

        # Calculate vulnerability score (0.0-1.0, higher = more vulnerable)
        let vulnerabilityScore = 1.0 - defenseRatio / config.vulnerability_defense_ratio_threshold

        result.vulnerableTargets.add(InvasionOpportunity(
          systemId: systemId,
          owner: report.targetOwner,
          vulnerability: min(vulnerabilityScore, 1.0),
          estimatedDefenses: totalDefenseStrength,
          estimatedValue: economicValue,
          requiredForce: requiredForce,
          distance: distance,
          lastIntelTurn: report.gatheredTurn,
          intelQuality: report.quality
        ))
      else:
        logDebug(LogCategory.lcAI,
          &"{filtered.viewingHouse} Colony Analyzer: REJECTED - defenses too " &
          &"strong (ratio {defenseRatio:.2f} >= threshold " &
          &"{config.vulnerability_defense_ratio_threshold})")

  # Sort vulnerable targets by vulnerability score (most vulnerable first)
  result.vulnerableTargets.sort(proc(a, b: InvasionOpportunity): int =
    # Primary: vulnerability score (descending)
    if a.vulnerability > b.vulnerability:
      return -1
    elif a.vulnerability < b.vulnerability:
      return 1
    # Secondary: distance (ascending - prefer closer targets)
    return cmp(a.distance, b.distance)
  )

  # Sort high-value targets by value (highest first)
  result.highValueTargets.sort(proc(a, b: HighValueTarget): int =
    return cmp(b.estimatedValue, a.estimatedValue)  # Descending
  )
