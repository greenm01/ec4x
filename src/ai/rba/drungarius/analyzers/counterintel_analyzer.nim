## Counter-Intelligence Analyzer - Phase E
##
## Processes EspionageActivityReport to detect espionage patterns:
## - Houses conducting espionage against us
## - Frequency and success rate tracking
## - Counter-intelligence investment priorities
## - Detection risk assessment

import std/[tables, sequtils, strformat, strutils, algorithm] # Removed options
import ../../../../engine/[gamestate, fog_of_war, logger]
import ../../../../engine/intelligence/types as intel_types
import ../../../../common/types/core
import ../../controller_types
import ../../config
import ../../shared/intelligence_types

proc analyzeCounterIntelligence*(
  filtered: FilteredGameState,
  controller: AIController
): tuple[
  espionagePatterns: Table[HouseId, EspionagePattern],
  detectionRisks: Table[HouseId, DetectionRiskLevel]
] =
  ## Analyze EspionageActivityReport data for counter-intelligence
  ## Phase E: Critical for detecting espionage threats and adjusting operations

  let config = globalRBAConfig.intelligence_counterintel
  var espionagePatterns = initTable[HouseId, EspionagePattern]()
  var detectionRisks = initTable[HouseId, DetectionRiskLevel]()

  # Track all detected espionage per house
  var attemptsPerHouse = initTable[HouseId, int]()
  var successesPerHouse = initTable[HouseId, int]()
  var lastAttemptPerHouse = initTable[HouseId, int]()
  var targetTypesPerHouse = initTable[HouseId, seq[string]]()

  # Process all espionage activity reports
  for report in filtered.ownHouse.intelligence.espionageActivity:
    # Skip if perpetrator not detected
    if not report.detected:
      continue

    let perpetrator = report.perpetrator

    # Track attempts
    attemptsPerHouse[perpetrator] = attemptsPerHouse.getOrDefault(perpetrator, 0) + 1

    # Track target types
    if not targetTypesPerHouse.hasKey(perpetrator):
      targetTypesPerHouse[perpetrator] = @[]
    if report.action notin targetTypesPerHouse[perpetrator]:
      targetTypesPerHouse[perpetrator].add(report.action)

    # Track last attempt turn
    if not lastAttemptPerHouse.hasKey(perpetrator) or report.turn > lastAttemptPerHouse[perpetrator]:
      lastAttemptPerHouse[perpetrator] = report.turn

    # Detect successful operations from description
    # (Engine generates descriptions like "successful espionage" or "failed attempt")
    if "successful" in report.description.toLowerAscii() or "succeeded" in report.description.toLowerAscii():
      successesPerHouse[perpetrator] = successesPerHouse.getOrDefault(perpetrator, 0) + 1

  # Build espionage patterns
  for perpetrator, attempts in attemptsPerHouse:
    let successes = successesPerHouse.getOrDefault(perpetrator, 0)
    let lastAttempt = lastAttemptPerHouse[perpetrator]
    let targetTypes = targetTypesPerHouse.getOrDefault(perpetrator, @[])

    espionagePatterns[perpetrator] = EspionagePattern(
      perpetrator: perpetrator,
      attempts: attempts,
      successes: successes,
      lastAttempt: lastAttempt,
      targetTypes: targetTypes
    )

  # Calculate detection risks for each house
  # (How often they detect our espionage attempts)
  # NOTE: This requires tracking OUR espionage attempts vs their detections
  # For now, use heuristic: houses that spy on us frequently = high detection capability
  for perpetrator, pattern in espionagePatterns:
    let detectionRate = if pattern.attempts > 0:
      1.0 - (pattern.successes.float / pattern.attempts.float)
    else:
      0.0

    # Classify detection risk
    let risk = if detectionRate >= config.detection_success_threshold:
      DetectionRiskLevel.High
    elif detectionRate >= 0.4:
      DetectionRiskLevel.Moderate
    elif detectionRate >= 0.2:
      DetectionRiskLevel.Low
    else:
      DetectionRiskLevel.Unknown

    detectionRisks[perpetrator] = risk

  # Log high-frequency espionage threats
  var highFrequencyThreats = 0
  for perpetrator, pattern in espionagePatterns:
    if pattern.attempts >= config.high_frequency_threshold:
      highFrequencyThreats += 1
      logInfo(LogCategory.lcAI,
              &"{controller.houseId} Drungarius: High-frequency espionage from {perpetrator} " &
              &"({pattern.attempts} attempts, {pattern.successes} successful)")

  # Log detection risks
  var highRiskHouses = 0
  for house, risk in detectionRisks:
    if risk == DetectionRiskLevel.High:
      highRiskHouses += 1
      logDebug(LogCategory.lcAI,
               &"{controller.houseId} Drungarius: High detection risk for operations vs {house}")

  # Summary logging
  if espionagePatterns.len > 0:
    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Drungarius: {espionagePatterns.len} espionage patterns detected " &
            &"({highFrequencyThreats} high-frequency threats)")

  if highRiskHouses > 0:
    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Drungarius: {highRiskHouses} houses with high detection capability")

  result = (espionagePatterns, detectionRisks)

proc shouldBoostCounterIntel*(
  espionagePatterns: Table[HouseId, EspionagePattern],
  config: CounterintelConfig
): bool =
  ## Determine if we should boost counter-intelligence spending
  ## Returns true if under significant espionage pressure

  var totalAttempts = 0
  var highFrequencyCount = 0

  for pattern in espionagePatterns.values:
    totalAttempts += pattern.attempts
    if pattern.attempts >= config.high_frequency_threshold:
      highFrequencyCount += 1

  # Boost if:
  # 1. Multiple houses conducting high-frequency espionage (2+)
  # 2. Total attempts very high (10+)
  result = (highFrequencyCount >= 2) or (totalAttempts >= 10)

proc prioritizeCounterIntelTargets*(
  espionagePatterns: Table[HouseId, EspionagePattern],
  config: CounterintelConfig
): seq[HouseId] =
  ## Prioritize houses for counter-intelligence operations
  ## Returns houses sorted by espionage threat (highest first)

  var housePriorities: seq[tuple[house: HouseId, priority: float]] = @[]

  for house, pattern in espionagePatterns:
    # Priority = attempts * frequency_multiplier + success_weight
    var priority = pattern.attempts.float

    # High-frequency multiplier
    if pattern.attempts >= config.high_frequency_threshold:
      priority *= 2.0

    # Success weight (successful operations = more dangerous)
    priority += pattern.successes.float * 1.5

    housePriorities.add((house, priority))

  # Sort by priority (highest first)
  housePriorities.sort(proc (a, b: tuple[house: HouseId, priority: float]): int = cmp(b.priority, a.priority))

  result = housePriorities.mapIt(it.house)
