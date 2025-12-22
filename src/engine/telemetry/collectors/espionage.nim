## @engine/telemetry/collectors/espionage.nim
##
## Collect espionage metrics from events and GameState.
## Covers: intelligence operations, counter-intelligence, spy missions.

import std/[options, math]
import ../../types/[telemetry, core, game_state, event, squadron, house]
import ../../state/entity_manager

proc collectEspionageMetrics*(
  state: GameState,
  houseId: HouseId,
  prevMetrics: DiagnosticMetrics
): DiagnosticMetrics =
  ## Collect espionage metrics from events and GameState
  result = prevMetrics  # Start with previous metrics

  let houseOpt = state.houses.entities.getEntity(houseId)
  if houseOpt.isNone:
    return result
  let house = houseOpt.get()

  # ================================================================
  # INTELLIGENCE ASSETS
  # ================================================================

  # Check if CLK researched but no Raiders built
  let hasCLK: bool = house.techTree.levels.cloakingTech > 1
  var hasRaiders: bool = false

  for squadron in state.squadrons.entities.data:
    if squadron.houseId == houseId and not squadron.destroyed:
      if squadron.flagship.shipClass == ShipClass.Raider:
        hasRaiders = true
        break

  result.clkResearchedNoRaiders = hasCLK and not hasRaiders

  # ================================================================
  # ESPIONAGE OPERATIONS (tracked from events)
  # ================================================================

  var espionageAttempts: int32 = 0
  var espionageSuccess: int32 = 0
  var espionageDetected: int32 = 0
  var techThefts: int32 = 0
  var sabotage: int32 = 0
  var assassinations: int32 = 0
  var cyberAttacks: int32 = 0
  var ebpSpent: int32 = 0
  var cipSpent: int32 = 0
  var counterIntelSuccesses: int32 = 0

  for event in state.lastTurnEvents:
    if event.houseId != some(houseId): continue

    case event.eventType:
    of SpyMissionSucceeded:
      espionageAttempts += 1
      espionageSuccess += 1
    of SpyMissionDetected:
      espionageDetected += 1
    of TechTheftExecuted:
      techThefts += 1
    of SabotageConducted:
      sabotage += 1
    of AssassinationAttempted:
      assassinations += 1
    of CyberAttackConducted:
      cyberAttacks += 1
    of CounterIntelSweepExecuted:
      counterIntelSuccesses += 1
    else:
      discard

  result.espionageSuccessCount = espionageSuccess
  result.espionageFailureCount = max(
    0, espionageAttempts - espionageSuccess - espionageDetected
  )
  result.espionageDetectedCount = espionageDetected
  result.techTheftsSuccessful = techThefts
  result.sabotageOperations = sabotage
  result.assassinationAttempts = assassinations
  result.cyberAttacksLaunched = cyberAttacks
  result.ebpPointsSpent = ebpSpent
  result.cipPointsSpent = cipSpent
  result.counterIntelSuccesses = counterIntelSuccesses

  # ================================================================
  # ESPIONAGE MISSION TRACKING (from orders)
  # ================================================================

  # TODO: These are populated during order generation phase
  result.spyPlanetMissions = prevMetrics.spyPlanetMissions
  result.hackStarbaseMissions = prevMetrics.hackStarbaseMissions
  result.totalEspionageMissions = prevMetrics.totalEspionageMissions

  # ================================================================
  # INVASIONS (Military intel support)
  # ================================================================

  var totalInvasions: int32 = 0
  for event in state.lastTurnEvents:
    if event.houseId != some(houseId): continue
    if event.eventType == InvasionBegan:
      totalInvasions += 1

  result.totalInvasions = prevMetrics.totalInvasions + totalInvasions
  result.vulnerableTargets_count = prevMetrics.vulnerableTargets_count
