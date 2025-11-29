## Performance Regression Tests
##
## Monitors turn resolution performance over time to detect:
## - O(n²) or worse algorithms that degrade with game size
## - Memory leaks causing slowdown
## - Performance regression from code changes
##
## Establishes performance baselines and alerts on degradation

import std/[times, strformat, random, tables, options, sequtils, stats]
import unittest
import ../../src/engine/[gamestate, resolve, orders]
import ../../src/engine/research/types as res_types
import ../../src/engine/espionage/types as esp_types
import ../../src/common/types/core

type
  PerformanceMetrics* = object
    turnNumber*: int
    resolutionTimeMs*: float
    stateSize*: int  # Approximate state size (fleets + colonies + houses)
    memoryUsageMB*: float  # If available

proc measureTurnTime(game: var GameState, orders: Table[HouseId, OrderPacket]): float =
  ## Measure turn resolution time in milliseconds
  let start = cpuTime()
  let result = resolveTurn(game, orders)
  game = result.newState
  return (cpuTime() - start) * 1000.0

proc estimateStateSize(game: GameState): int =
  ## Rough estimate of game state complexity
  game.fleets.len + game.colonies.len + game.houses.len

proc createNoOpOrders(houseId: HouseId, turn: int): OrderPacket =
  OrderPacket(
    houseId: houseId,
    turn: turn,
    buildOrders: @[],
    fleetOrders: @[],
    researchAllocation: initResearchAllocation(),
    diplomaticActions: @[],
    populationTransfers: @[],
    squadronManagement: @[],
    cargoManagement: @[],
    terraformOrders: @[],
    espionageAction: none(esp_types.EspionageAttempt),
    ebpInvestment: 0,
    cipInvestment: 0
  )

suite "Performance: Turn Resolution Timing":

  test "Performance baseline: 2-house game, 100 turns":
    ## Establish baseline for small game

    echo "\n📊 Measuring baseline performance (2 houses, 100 turns)..."

    var game = newGame("perf-test", 2, 42)
    var metrics: seq[PerformanceMetrics] = @[]

    for turn in 1..100:
      var ordersTable = initTable[HouseId, OrderPacket]()
      for houseId in game.houses.keys:
        ordersTable[houseId] = createNoOpOrders(houseId, turn)

      let timeMs = measureTurnTime(game, ordersTable)
      let stateSize = estimateStateSize(game)

      metrics.add(PerformanceMetrics(
        turnNumber: turn,
        resolutionTimeMs: timeMs,
        stateSize: stateSize,
        memoryUsageMB: 0.0  # TODO: Add memory tracking
      ))

    # Analyze metrics
    let times = metrics.mapIt(it.resolutionTimeMs)
    let avgTime = times.mean()
    let stdDev = times.standardDeviation()
    let minTime = times.min()
    let maxTime = times.max()

    echo &"  Average turn time: {avgTime:.2f}ms (±{stdDev:.2f}ms)"
    echo &"  Min: {minTime:.2f}ms, Max: {maxTime:.2f}ms"
    echo &"  Final state size: {metrics[^1].stateSize} entities"

    # Performance threshold: turns should complete in < 100ms on average
    if avgTime > 100.0:
      echo &"  ⚠️  WARNING: Average turn time {avgTime:.2f}ms exceeds 100ms threshold"

  test "Performance scaling: 12-house game":
    ## Test performance with maximum game size

    echo "\n📊 Measuring performance at max scale (12 houses, 50 turns)..."

    var game = newGame("perf-test-12", 12, 999)
    var metrics: seq[PerformanceMetrics] = @[]

    for turn in 1..50:
      if turn mod 10 == 0:
        echo &"  Turn {turn}/50..."

      var ordersTable = initTable[HouseId, OrderPacket]()
      for houseId in game.houses.keys:
        ordersTable[houseId] = createNoOpOrders(houseId, turn)

      let timeMs = measureTurnTime(game, ordersTable)
      let stateSize = estimateStateSize(game)

      metrics.add(PerformanceMetrics(
        turnNumber: turn,
        resolutionTimeMs: timeMs,
        stateSize: stateSize,
        memoryUsageMB: 0.0
      ))

    # Analyze
    let times = metrics.mapIt(it.resolutionTimeMs)
    let avgTime = times.mean()
    let stdDev = times.standardDeviation()
    let maxTime = times.max()

    echo &"  Average turn time: {avgTime:.2f}ms (±{stdDev:.2f}ms)"
    echo &"  Max: {maxTime:.2f}ms"
    echo &"  Final state size: {metrics[^1].stateSize} entities"

    # With 12 houses, expect longer turns but should still be reasonable
    if avgTime > 500.0:
      echo &"  ⚠️  WARNING: 12-house average {avgTime:.2f}ms exceeds 500ms threshold"

  test "Performance degradation: detect O(n²) algorithms":
    ## Run progressively longer games and check if time scales linearly

    echo "\n📊 Checking for algorithmic degradation..."

    # Run games of increasing length
    let turnCounts = [10, 50, 100, 200]
    var scalingData: seq[tuple[turns: int, avgTimeMs: float]] = @[]

    for numTurns in turnCounts:
      echo &"  Testing {numTurns} turns..."

      var game = newGame("perf-test-degrad", 3, 123)
      var times: seq[float] = @[]

      for turn in 1..numTurns:
        var ordersTable = initTable[HouseId, OrderPacket]()
        for houseId in game.houses.keys:
          ordersTable[houseId] = createNoOpOrders(houseId, turn)

        let timeMs = measureTurnTime(game, ordersTable)
        times.add(timeMs)

      let avgTime = times.mean()
      scalingData.add((numTurns, avgTime))
      echo &"    Average time: {avgTime:.2f}ms"

    # Check if scaling is roughly linear
    # If turn time increases faster than linearly, we have O(n²) or worse
    echo "\n  Scaling analysis:"
    for i in 1..<scalingData.len:
      let prev = scalingData[i-1]
      let curr = scalingData[i]
      let turnRatio = curr.turns.float / prev.turns.float
      let timeRatio = curr.avgTimeMs / prev.avgTimeMs

      echo &"    {prev.turns} → {curr.turns} turns: time increased {timeRatio:.2f}x (expected ~{turnRatio:.2f}x for linear)"

      # If time increases much faster than turn count, we have a problem
      if timeRatio > turnRatio * 1.5:
        echo &"    ⚠️  WARNING: Non-linear scaling detected (O(n²) algorithm?)"

  test "Performance consistency: detect variance spikes":
    ## Check for occasional slow turns that indicate intermittent issues

    echo "\n📊 Checking for performance variance..."

    var game = newGame("perf-test-var", 4, 456)
    var times: seq[float] = @[]

    for turn in 1..100:
      var ordersTable = initTable[HouseId, OrderPacket]()
      for houseId in game.houses.keys:
        ordersTable[houseId] = createNoOpOrders(houseId, turn)

      let timeMs = measureTurnTime(game, ordersTable)
      times.add(timeMs)

    # Detect outliers (turns that are abnormally slow)
    let avgTime = times.mean()
    let stdDev = times.standardDeviation()
    var outliers: seq[tuple[turn: int, timeMs: float]] = @[]

    for i, time in times:
      if time > avgTime + (3 * stdDev):  # 3-sigma outlier
        outliers.add((i + 1, time))

    echo &"  Average: {avgTime:.2f}ms, StdDev: {stdDev:.2f}ms"
    echo &"  Outliers (> 3σ): {outliers.len}/100"

    if outliers.len > 0:
      echo "  Slow turns detected:"
      for (turn, timeMs) in outliers:
        echo &"    Turn {turn}: {timeMs:.2f}ms ({(timeMs/avgTime):.1f}x average)"

      if outliers.len > 10:
        echo "  ⚠️  WARNING: Too many slow turns (intermittent performance issue?)"

suite "Performance: Memory Pressure":

  test "Memory: sustained operation":
    ## Run long simulation and monitor for memory growth
    ## This is a proxy for memory leak detection

    echo "\n📊 Testing sustained operation (500 turns)..."

    var game = newGame("perf-test-mem", 3, 789)

    # Sample state size over time
    var stateSizes: seq[tuple[turn: int, size: int]] = @[]

    for turn in 1..500:
      if turn mod 50 == 0:
        echo &"  Turn {turn}/500..."

      var ordersTable = initTable[HouseId, OrderPacket]()
      for houseId in game.houses.keys:
        ordersTable[houseId] = createNoOpOrders(houseId, turn)

      let result = resolveTurn(game, ordersTable)
      game = result.newState

      if turn mod 10 == 0:
        let size = estimateStateSize(game)
        stateSizes.add((turn, size))

    # Check if state size grows unboundedly
    echo "\n  State size over time:"
    echo &"    Turn 10: {stateSizes[0].size} entities"
    echo &"    Turn 250: {stateSizes[24].size} entities"
    echo &"    Turn 500: {stateSizes[49].size} entities"

    let initialSize = stateSizes[0].size
    let finalSize = stateSizes[^1].size
    let growth = finalSize.float / initialSize.float

    echo &"  Growth factor: {growth:.2f}x"

    if growth > 5.0:
      echo "  ⚠️  WARNING: State size grew significantly (possible memory leak)"

when isMainModule:
  echo "╔════════════════════════════════════════════════╗"
  echo "║  EC4X Performance Regression Tests            ║"
  echo "║  Monitoring turn times and scaling behavior   ║"
  echo "╚════════════════════════════════════════════════╝"
  echo ""
