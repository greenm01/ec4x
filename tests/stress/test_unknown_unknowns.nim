## Unknown-Unknowns Detection
##
## Statistical anomaly detection to find bugs we didn't know to look for:
## - Values that should be impossible but occur anyway
## - Statistical outliers indicating broken game mechanics
## - Emergent bugs from system interactions
## - Invariants that hold 99% of the time but occasionally break
##
## This test runs many simulations and looks for anomalies

import std/[times, strformat, random, tables, options, sequtils, stats, algorithm, math, strutils]
import unittest
import stress_framework
import ../../src/engine/[gamestate, resolve, orders]
import ../../src/engine/initialization/game
import ../../src/engine/research/types as res_types
import ../../src/engine/espionage/types as esp_types
import ../../src/common/types/core

type
  GameMetrics* = object
    ## Metrics collected per game for anomaly detection
    gameId*: int
    finalTurn*: int
    totalViolations*: int
    criticalViolations*: int

    # Per-house metrics (average across all houses)
    avgFinalPrestige*: float
    minFinalPrestige*: int
    maxFinalPrestige*: int

    avgFinalTreasury*: float
    minFinalTreasury*: int

    avgTechLevel*: float  # Average across all tech fields

    totalFleets*: int
    totalColonies*: int
    totalSquadrons*: int

    # Anomaly flags
    negativePrestige*: bool
    negativeTreasury*: bool
    zeroColonies*: bool

proc collectGameMetrics(game: GameState, gameId: int, turn: int, violations: seq[InvariantViolation]): GameMetrics =
  ## Collect metrics from game state

  var prestiges: seq[int] = @[]
  var treasuries: seq[int] = @[]
  var techLevels: seq[int] = @[]

  for house in game.houses.values:
    prestiges.add(house.prestige)
    treasuries.add(house.treasury)

    # Average tech level across all fields
    let avgTech = (
      house.techTree.levels.constructionTech + house.techTree.levels.weaponsTech + house.techTree.levels.economicLevel +
      house.techTree.levels.scienceLevel + house.techTree.levels.terraformingTech + house.techTree.levels.electronicIntelligence +
      house.techTree.levels.cloakingTech + house.techTree.levels.shieldTech + house.techTree.levels.counterIntelligence +
      house.techTree.levels.fighterDoctrine + house.techTree.levels.advancedCarrierOps
    ) div 11
    techLevels.add(avgTech)

  # Count entities
  var squadronCount = 0
  for fleet in game.fleets.values:
    squadronCount += fleet.squadrons.len

  # Handle empty sequences (all houses eliminated)
  let hasHouses = prestiges.len > 0

  result = GameMetrics(
    gameId: gameId,
    finalTurn: turn,
    totalViolations: violations.len,
    criticalViolations: violations.filterIt(it.severity == ViolationSeverity.Critical).len,

    avgFinalPrestige: if hasHouses: prestiges.mean() else: 0,
    minFinalPrestige: if hasHouses: prestiges.min() else: 0,
    maxFinalPrestige: if hasHouses: prestiges.max() else: 0,

    avgFinalTreasury: if hasHouses: treasuries.mean() else: 0,
    minFinalTreasury: if hasHouses: treasuries.min() else: 0,

    avgTechLevel: if hasHouses: techLevels.mean() else: 0,

    totalFleets: game.fleets.len,
    totalColonies: game.colonies.len,
    totalSquadrons: squadronCount,

    negativePrestige: if hasHouses: prestiges.anyIt(it < 0) else: false,
    negativeTreasury: if hasHouses: treasuries.anyIt(it < 0) else: false,
    zeroColonies: game.colonies.len == 0
  )

proc createNoOpOrders(houseId: HouseId, turn: int): OrderPacket =
  OrderPacket(
    houseId: houseId,
    turn: turn,
    buildOrders: @[],
    fleetOrders: @[],
    researchAllocation: initResearchAllocation(),
    diplomaticActions: @[],
    populationTransfers: @[],
    terraformOrders: @[],
    espionageAction: none(esp_types.EspionageAttempt),
    ebpInvestment: 0,
    cipInvestment: 0
  )

suite "Unknown-Unknowns: Statistical Anomaly Detection":

  test "Anomaly detection: 100 games, 50 turns each":
    ## Run many simulations and look for statistical anomalies

    echo "\n🔍 Running 100 games to detect unknown-unknowns..."
    echo "   This will take a few minutes...\n"

    let startTime = cpuTime()
    var allMetrics: seq[GameMetrics] = @[]
    var allViolations: seq[InvariantViolation] = @[]

    for gameId in 1..100:
      if gameId mod 10 == 0:
        echo &"  Game {gameId}/100..."

      # Create game with random seed
      var game = newGame(&"unknowns-{gameId}", 3, int64(gameId * 42))
      var gameViolations: seq[InvariantViolation] = @[]

      # Run 50 turns
      for turn in 1..50:
        var ordersTable = initTable[HouseId, OrderPacket]()
        for houseId in game.houses.keys:
          ordersTable[houseId] = createNoOpOrders(houseId, turn)

        try:
          let result = resolveTurn(game, ordersTable)
          game = result.newState
        except CatchableError as e:
          echo &"    ❌ Game {gameId} crashed at turn {turn}: {e.msg}"
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
      let finalViolations = checkStateInvariants(game, 50)
      gameViolations.add(finalViolations)
      allViolations.add(gameViolations)

      # Collect metrics
      let metrics = collectGameMetrics(game, gameId, 50, gameViolations)
      allMetrics.add(metrics)

    let elapsed = cpuTime() - startTime
    echo &"\n✅ Completed 100 games in {elapsed:.1f}s"

    # Analyze for anomalies
    echo "\n📊 Statistical Analysis:"
    echo "=" .repeat(60)

    # Violation statistics
    let violationCounts = allMetrics.mapIt(it.totalViolations)
    let crashCount = allMetrics.filterIt(it.criticalViolations > 0).len

    echo &"\nViolations:"
    echo &"  Games with violations: {violationCounts.countIt(it > 0)}/100"
    echo &"  Games with crashes: {crashCount}/100"
    echo &"  Total violations: {violationCounts.sum()}"

    if crashCount > 0:
      echo "\n  🔴 CRITICAL: Crashes detected in {crashCount} games!"
      fail()

    # Prestige analysis
    let prestiges = allMetrics.mapIt(it.avgFinalPrestige)
    let negPrestigeCount = allMetrics.filterIt(it.negativePrestige).len

    echo &"\nPrestige:"
    echo &"  Average final prestige: {prestiges.mean():.1f} (±{prestiges.standardDeviation():.1f})"
    echo &"  Range: {prestiges.min():.1f} to {prestiges.max():.1f}"
    echo &"  Games with negative prestige: {negPrestigeCount}/100"

    # Treasury analysis
    let treasuries = allMetrics.mapIt(it.avgFinalTreasury)
    let negTreasuryCount = allMetrics.filterIt(it.negativeTreasury).len

    echo &"\nTreasury:"
    echo &"  Average final treasury: {treasuries.mean():.0f} PP (±{treasuries.standardDeviation():.0f})"
    echo &"  Games with negative treasury: {negTreasuryCount}/100"

    # Tech progression
    let techLevels = allMetrics.mapIt(it.avgTechLevel)

    echo &"\nTechnology:"
    echo &"  Average tech level (50 turns): {techLevels.mean():.2f} (±{techLevels.standardDeviation():.2f})"

    # Entity counts
    let fleetCounts = allMetrics.mapIt(it.totalFleets)
    let colonyCounts = allMetrics.mapIt(it.totalColonies)
    let squadronCounts = allMetrics.mapIt(it.totalSquadrons)

    echo &"\nEntities:"
    echo &"  Average fleets: {fleetCounts.mean():.1f}"
    echo &"  Average colonies: {colonyCounts.mean():.1f}"
    echo &"  Average squadrons: {squadronCounts.mean():.1f}"

    # Detect anomalies
    echo "\n🔍 Anomaly Detection:"
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
      echo "  ✅ No statistical anomalies detected"
    else:
      echo &"\n  ⚠️  Detected {anomalyCount} anomalous games"
      if anomalyCount > 10:
        echo "  🔴 High anomaly rate (>{anomalyCount}%) - investigate!"

    # Report all violations if any critical ones found
    let allCritical = allViolations.filterIt(it.severity == ViolationSeverity.Critical)
    if allCritical.len > 0:
      echo &"\n🔴 Found {allCritical.len} CRITICAL violations:"
      reportViolations(allCritical)
      fail()

  test "Anomaly detection: rare events":
    ## Look for events that should be very rare but might occur

    echo "\n🔍 Looking for rare anomalies (1000 games, 10 turns each)..."
    echo "   Testing for rare edge cases...\n"

    var rareEvents = initTable[string, int]()
    rareEvents["crash"] = 0
    rareEvents["zero_colonies"] = 0
    rareEvents["extreme_prestige"] = 0
    rareEvents["duplicate_ids"] = 0
    rareEvents["invalid_location"] = 0

    for gameId in 1..1000:
      if gameId mod 100 == 0:
        echo &"  Game {gameId}/1000..."

      var game = newGame(&"rare-{gameId}", 2, int64(gameId))

      # Run 10 turns quickly
      for turn in 1..10:
        var ordersTable = initTable[HouseId, OrderPacket]()
        for houseId in game.houses.keys:
          ordersTable[houseId] = createNoOpOrders(houseId, turn)

        try:
          let result = resolveTurn(game, ordersTable)
          game = result.newState
        except CatchableError:
          rareEvents["crash"] += 1
          break

      # Check for rare events
      let violations = checkStateInvariants(game, 10)

      for v in violations:
        case v.category:
          of "InvalidLocation":
            rareEvents["invalid_location"] += 1
          of "DuplicateId":
            rareEvents["duplicate_ids"] += 1
          else:
            discard

      # Check colonies
      if game.colonies.len == 0:
        rareEvents["zero_colonies"] += 1

      # Check for extreme prestige
      for house in game.houses.values:
        if abs(house.prestige) > 1000:
          rareEvents["extreme_prestige"] += 1

    echo "\n📊 Rare Event Statistics (out of 1000 games):"
    echo "=" .repeat(60)
    for event, count in rareEvents:
      let pct = (count.float / 1000.0) * 100.0
      echo &"  {event}: {count} ({pct:.2f}%)"

      if event == "crash" and count > 0:
        echo "    🔴 CRITICAL: Crashes should never occur!"

      if event in ["duplicate_ids", "invalid_location"] and count > 0:
        echo "    🔴 CRITICAL: Data corruption detected!"

    # Fail if any critical rare events detected
    if rareEvents["crash"] > 0 or rareEvents["duplicate_ids"] > 0 or rareEvents["invalid_location"] > 0:
      fail()

when isMainModule:
  echo "╔════════════════════════════════════════════════╗"
  echo "║  EC4X Unknown-Unknowns Detection              ║"
  echo "║  Statistical analysis to find hidden bugs     ║"
  echo "╚════════════════════════════════════════════════╝"
  echo ""
