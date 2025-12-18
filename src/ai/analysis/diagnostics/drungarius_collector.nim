## Drungarius Collector - Intelligence & Espionage Domain
##
## Tracks intelligence assets (scouts, CLK tech), espionage operations
## (tech theft, sabotage, assassinations, cyber attacks), and
## counter-intelligence successes.
##
## REFACTORED: 2025-12-06 - Extracted from diagnostics.nim (lines 843-888, 1145-1156)

import std/tables
import ./types
import ../../../engine/gamestate
import ../../../engine/diagnostics_data
import ../../../common/types/[core, units]

proc collectDrungariusMetrics*(state: GameState, houseId: HouseId, prevMetrics: DiagnosticMetrics, report: TurnResolutionReport): DiagnosticMetrics =
  ## Collect intelligence & espionage metrics
  result = initDiagnosticMetrics(state.turn, houseId)

  let house = state.houses.getOrDefault(houseId)

  # ================================================================
  # INTELLIGENCE ASSETS
  # ================================================================

  # Check if CLK researched but no Raiders built
  # This detects wasted cloaking tech investment
  let hasCLK = house.techTree.levels.cloakingTech > 1
  var hasRaiders = false

  for fleetId, fleet in state.fleets:
    if fleet.owner == houseId:
      for squadron in fleet.squadrons:
        if squadron.flagship.shipClass == ShipClass.Raider:
          hasRaiders = true
          break
      if hasRaiders:
        break

  result.clkResearchedNoRaiders = hasCLK and not hasRaiders

  # ================================================================
  # ESPIONAGE OPERATIONS (tracked from turn resolution)
  # ================================================================

  # Success/failure/detected counts
  result.espionageSuccessCount = report.espionageSuccess
  result.espionageFailureCount =
    max(0, report.espionageAttempts -
           report.espionageSuccess -
           report.espionageDetected)
  result.espionageDetectedCount = report.espionageDetected

  # Operation types
  result.techTheftsSuccessful = report.techThefts
  result.sabotageOperations = report.sabotage
  result.assassinationAttempts = report.assassinations
  result.cyberAttacksLaunched = report.cyberAttacks

  # Budget spent
  result.ebpPointsSpent = report.ebpSpent
  result.cipPointsSpent = report.cipSpent

  # Counter-intelligence successes
  result.counterIntelSuccesses = report.counterIntelSuccesses

  # ================================================================
  # ESPIONAGE MISSION TRACKING (from orders, set by orchestrator)
  # ================================================================

  # These are fleet-based espionage missions (SpyPlanet, HackStarbase, SpySystem)
  # Set by orchestrator when processing order packets
  result.spyPlanetMissions = 0
  result.hackStarbaseMissions = 0
  result.totalEspionageMissions = 0

  # ================================================================
  # INVASIONS (Military intel support)
  # ================================================================

  # Track total invasions (useful for strategy analysis)
  result.totalInvasions = prevMetrics.totalInvasions + report.totalInvasions

  # Phase 1: Invasion planning metrics
  # NOTE: vulnerableTargets_count populated during intelligence analysis
  # (see colony_analyzer.nim analyzeColonyIntelligence)
  result.vulnerableTargets_count = 0  # Updated by order generation phase
