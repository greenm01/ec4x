## Unknown-Unknowns Detection
##
## Statistical anomaly detection to find bugs we didn't know to look for:
## - Values that should be impossible but occur anyway
## - Statistical outliers indicating broken game mechanics
## - Emergent bugs from system interactions
## - Invariants that hold 99% of the time but occasionally break
##
## This test runs many simulations and looks for anomalies
##
## Updated for new engine architecture (2026-01)

import std/[times, strformat, random, tables, options, sequtils, stats, algorithm, math, strutils]
import unittest
import stress_framework
import ../../src/engine/engine
import ../../src/engine/types/[core, command, house, tech, espionage]
import ../../src/engine/state/iterators
import ../../src/engine/turn_cycle/engine

type
  GameMetrics* = object
    ## Metrics collected per game for anomaly detection
    gameId*: int
    finalTurn*: int
    totalViolations*: int
    criticalViolations*: int

    # Per-house metrics (average across all houses)
    avgFinalPrestige*: float
    minFinalPrestige*: int32
    maxFinalPrestige*: int32

    avgFinalTreasury*: float
    minFinalTreasury*: int32

    avgTechLevel*: float  # Average across all tech fields

    totalFleets*: int
    totalColonies*: int
    totalShips*: int

    # Anomaly flags
    negativePrestige*: bool
    negativeTreasury*: bool
    zeroColonies*: bool

proc collectGameMetrics(
    game: GameState, gameId: int, turn: int, violations: seq[InvariantViolation]
): GameMetrics =
  ## Collect metrics from game state

  var prestiges: seq[int32] = @[]
  var treasuries: seq[int32] = @[]
  var techLevels: seq[int32] = @[]

  for house in game.allHouses():
    prestiges.add(house.prestige)
    treasuries.add(house.treasury)

    # Average tech level across all fields
    let tech = house.techTree.levels
    let avgTech = (
      tech.cst + tech.wep + tech.el + tech.sl + tech.ter + tech.eli +
      tech.clk + tech.sld + tech.cic + tech.fd + tech.aco
    ) div 11
    techLevels.add(avgTech)

  # Count entities
  var fleetCount = 0
  var colonyCount = 0
  var shipCount = 0

  for fleet in game.allFleets():
    fleetCount += 1
    shipCount += fleet.ships.len

  for _ in game.allColonies():
    colonyCount += 1

  # Handle empty sequences (all houses eliminated)
  let hasHouses = prestiges.len > 0

  result = GameMetrics(
    gameId: gameId,
    finalTurn: turn,
    totalViolations: violations.len,
    criticalViolations: violations.filterIt(it.severity == ViolationSeverity.Critical).len,

    avgFinalPrestige: if hasHouses: prestiges.mapIt(it.float).mean() else: 0,
    minFinalPrestige: if hasHouses: prestiges.min() else: 0,
    maxFinalPrestige: if hasHouses: prestiges.max() else: 0,

    avgFinalTreasury: if hasHouses: treasuries.mapIt(it.float).mean() else: 0,
    minFinalTreasury: if hasHouses: treasuries.min() else: 0,

    avgTechLevel: if hasHouses: techLevels.mapIt(it.float).mean() else: 0,

    totalFleets: fleetCount,
    totalColonies: colonyCount,
    totalShips: shipCount,

    negativePrestige: if hasHouses: prestiges.anyIt(it < 0) else: false,
    negativeTreasury: if hasHouses: treasuries.anyIt(it < 0) else: false,
    zeroColonies: colonyCount == 0
  )

proc createNoOpCommands(
    game: GameState, turn: int
): Table[HouseId, CommandPacket] =
  ## Create empty commands for all houses
  result = initTable[HouseId, CommandPacket]()
  for (houseId, house) in game.activeHousesWithId():
    result[houseId] = CommandPacket(
      houseId: houseId,
      turn: turn.int32,
      
      fleetCommands: @[],
      buildCommands: @[],
      repairCommands: @[],
      scrapCommands: @[],
      researchAllocation: ResearchAllocation(),
      diplomaticCommand: @[],
      populationTransfers: @[],
      terraformCommands: @[],
      colonyManagement: @[],
      espionageActions: @[],
      ebpInvestment: 0,
      cipInvestment: 0
    )

suite "Unknown-Unknowns: Statistical Anomaly Detection":

  test "Anomaly detection: 100 games, 50 turns each":
    ## Run many simulations and look for statistical anomalies

    echo "\nRunning 100 games to detect unknown-unknowns..."
    echo "   This will take a few minutes...\n"

    let startTime = cpuTime()
    var allMetrics: seq[GameMetrics] = @[]
    var allViolations: seq[InvariantViolation] = @[]

    for gameId in 1..100:
      if gameId mod 10 == 0:
        echo &"  Game {gameId}/100..."

      # Create game with different seed each time
      var game = newGame()
      var rng = initRand(int64(gameId * 42))
      var gameViolations: seq[InvariantViolation] = @[]
      var actualTurn = 0

      # Run 50 turns
      for turn in 1..50:
        actualTurn = turn
        let commands = createNoOpCommands(game, turn)

        try:
          let turnResult = game.resolveTurn(commands, rng)
          if turnResult.victoryCheck.victoryOccurred:
            break
        except CatchableError as e:
          echo &"    Game {gameId} crashed at turn {turn}: {e.msg}"
          # Record crash as critical violation
          var details = initTable[string, string]()
          details["gameId"] = $gameId
          details["turn"] = $turn
          details["error"] = e.msg
          gameViolations.add(newInvariantViolation(
            turn, ViolationSeverity.Critical,
            "Crash", &"Game crashed: {e.msg}", details
          ))
          break

      # Check final state
      let finalViolations = checkStateInvariants(game, actualTurn)
      gameViolations.add(finalViolations)
      allViolations.add(gameViolations)

      # Collect metrics
      let metrics = collectGameMetrics(game, gameId, actualTurn, gameViolations)
      allMetrics.add(metrics)

    let elapsed = cpuTime() - startTime
    echo &"\nCompleted 100 games in {elapsed:.1f}s"

    # Analyze for anomalies
    echo "\nStatistical Analysis:"
    echo "=" .repeat(60)

    # Violation statistics
    let violationCounts = allMetrics.mapIt(it.totalViolations)
    let crashCount = allMetrics.filterIt(it.criticalViolations > 0).len

    echo &"\nViolations:"
    echo &"  Games with violations: {violationCounts.countIt(it > 0)}/100"
    echo &"  Games with crashes: {crashCount}/100"
    echo &"  Total violations: {violationCounts.sum()}"

    if crashCount > 0:
      echo &"\n  CRITICAL: Crashes detected in {crashCount} games!"
      fail()

    # Prestige analysis
    let prestiges = allMetrics.mapIt(it.avgFinalPrestige)
    let negPrestigeCount = allMetrics.filterIt(it.negativePrestige).len

    echo &"\nPrestige:"
    echo &"  Average final prestige: {prestiges.mean():.1f} (+/-{prestiges.standardDeviation():.1f})"
    echo &"  Range: {prestiges.min():.1f} to {prestiges.max():.1f}"
    echo &"  Games with negative prestige: {negPrestigeCount}/100"

    # Treasury analysis
    let treasuries = allMetrics.mapIt(it.avgFinalTreasury)
    let negTreasuryCount = allMetrics.filterIt(it.negativeTreasury).len

    echo &"\nTreasury:"
    echo &"  Average final treasury: {treasuries.mean():.0f} PP (+/-{treasuries.standardDeviation():.0f})"
    echo &"  Games with negative treasury: {negTreasuryCount}/100"

    # Tech progression
    let techLevels = allMetrics.mapIt(it.avgTechLevel)

    echo &"\nTechnology:"
    echo &"  Average tech level (50 turns): {techLevels.mean():.2f} (+/-{techLevels.standardDeviation():.2f})"

    # Entity counts
    let fleetCounts = allMetrics.mapIt(it.totalFleets)
    let colonyCounts = allMetrics.mapIt(it.totalColonies)
    let shipCounts = allMetrics.mapIt(it.totalShips)

    echo &"\nEntities:"
    echo &"  Average fleets: {fleetCounts.mapIt(it.float).mean():.1f}"
    echo &"  Average colonies: {colonyCounts.mapIt(it.float).mean():.1f}"
    echo &"  Average ships: {shipCounts.mapIt(it.float).mean():.1f}"

    # Detect anomalies
    echo "\nAnomaly Detection:"
    echo "=" .repeat(60)

    var anomalyCount = 0

    # Check for games with extreme values (3-sigma outliers)
    let prestigeMean = prestiges.mean()
    let prestigeStd = prestiges.standardDeviation()

    for metrics in allMetrics:
      var anomalies: seq[string] = @[]

      # Prestige outliers
      if abs(metrics.avgFinalPrestige - prestigeMean) > 3 * prestigeStd:
        anomalies.add(&"Extreme prestige: {metrics.avgFinalPrestige:.0f}")

      # Zero colonies (should never happen unless all conquered)
      if metrics.zeroColonies:
        anomalies.add("Zero colonies")

      # Extremely high violation count
      if metrics.totalViolations > 10:
        anomalies.add(&"{metrics.totalViolations} violations")

      if anomalies.len > 0:
        anomalyCount += 1
        echo &"  Game {metrics.gameId}: {anomalies.join(\", \")}"

    if anomalyCount == 0:
      echo "  No statistical anomalies detected"
    else:
      echo &"\n  Detected {anomalyCount} anomalous games"
      if anomalyCount > 10:
        echo &"  High anomaly rate (>{anomalyCount}%) - investigate!"

    # Report all violations if any critical ones found
    let allCritical = allViolations.filterIt(it.severity == ViolationSeverity.Critical)
    if allCritical.len > 0:
      echo &"\nFound {allCritical.len} CRITICAL violations:"
      reportViolations(allCritical)
      fail()

  test "Anomaly detection: rare events":
    ## Look for events that should be very rare but might occur

    echo "\nLooking for rare anomalies (1000 games, 10 turns each)..."
    echo "   Testing for rare edge cases...\n"

    var rareEvents = initTable[string, int]()
    rareEvents["crash"] = 0
    rareEvents["zero_colonies"] = 0
    rareEvents["extreme_prestige"] = 0
    rareEvents["invalid_location"] = 0

    for gameId in 1..1000:
      if gameId mod 100 == 0:
        echo &"  Game {gameId}/1000..."

      var game = newGame()
      var rng = initRand(int64(gameId))

      # Run 10 turns quickly
      for turn in 1..10:
        let commands = createNoOpCommands(game, turn)

        try:
          let turnResult = game.resolveTurn(commands, rng)
          if turnResult.victoryCheck.victoryOccurred:
            break
        except CatchableError:
          rareEvents["crash"] += 1
          break

      # Check for rare events
      let violations = checkStateInvariants(game, 10)

      for v in violations:
        case v.category:
          of "InvalidLocation":
            rareEvents["invalid_location"] += 1
          else:
            discard

      # Check colonies
      var colonyCount = 0
      for _ in game.allColonies():
        colonyCount += 1
      if colonyCount == 0:
        rareEvents["zero_colonies"] += 1

      # Check for extreme prestige
      for house in game.allHouses():
        if abs(house.prestige) > 1000:
          rareEvents["extreme_prestige"] += 1

    echo "\nRare Event Statistics (out of 1000 games):"
    echo "=" .repeat(60)
    for event, count in rareEvents:
      let pct = (count.float / 1000.0) * 100.0
      echo &"  {event}: {count} ({pct:.2f}%)"

      if event == "crash" and count > 0:
        echo "    CRITICAL: Crashes should never occur!"

      if event == "invalid_location" and count > 0:
        echo "    CRITICAL: Data corruption detected!"

    # Fail if any critical rare events detected
    if rareEvents["crash"] > 0 or rareEvents["invalid_location"] > 0:
      fail()

when isMainModule:
  echo "========================================"
  echo "  EC4X Unknown-Unknowns Detection"
  echo "  Statistical analysis for hidden bugs"
  echo "========================================"
  echo ""
