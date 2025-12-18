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
import ../../../common/types/[core, units]

proc collectDrungariusMetrics*(state: GameState, houseId: HouseId, prevMetrics: DiagnosticMetrics): DiagnosticMetrics =
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
  result.espionageSuccessCount = house.lastTurnEspionageSuccess
  result.espionageFailureCount =
    max(0, house.lastTurnEspionageAttempts -
           house.lastTurnEspionageSuccess -
           house.lastTurnEspionageDetected)
  result.espionageDetectedCount = house.lastTurnEspionageDetected

  # Operation types
  result.techTheftsSuccessful = house.lastTurnTechThefts
  result.sabotageOperations = house.lastTurnSabotage
  result.assassinationAttempts = house.lastTurnAssassinations
  result.cyberAttacksLaunched = house.lastTurnCyberAttacks

  # Budget spent
  result.ebpPointsSpent = house.lastTurnEBPSpent
  result.cipPointsSpent = house.lastTurnCIPSpent

  # Counter-intelligence successes
  # TODO: Track when enemy espionage detected
  result.counterIntelSuccesses = 0

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
  result.totalInvasions = 0

  # Phase 1: Invasion planning metrics
  # NOTE: vulnerableTargets_count populated during intelligence analysis
  # (see colony_analyzer.nim analyzeColonyIntelligence)
  result.vulnerableTargets_count = 0  # Updated by order generation phase
