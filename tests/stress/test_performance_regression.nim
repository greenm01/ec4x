## Performance Regression Tests
##
## Monitors turn resolution performance over time to detect:
## - O(n^2) or worse algorithms that degrade with game size
## - Memory leaks causing slowdown
## - Performance regression from code changes
##
## Establishes performance baselines and alerts on degradation
##
## Updated for new engine architecture (2026-01)

import std/[times, strformat, random, tables, options, sequtils, stats]
import unittest
import ../../src/engine/engine
import ../../src/engine/types/[core, command, house, tech, espionage]
import ../../src/engine/state/iterators
import ../../src/engine/turn_cycle/engine

type
  PerformanceMetrics* = object
    turnNumber*: int
    resolutionTimeMs*: float
    stateSize*: int  # Approximate state size (fleets + colonies + houses)

proc measureTurnTime(
    game: GameState,
    commands: Table[HouseId, CommandPacket],
    rng: var Rand
): float =
  ## Measure turn resolution time in milliseconds
  let start = cpuTime()
  discard game.resolveTurn(commands, rng)
  return (cpuTime() - start) * 1000.0

proc estimateStateSize(game: GameState): int =
  ## Rough estimate of game state complexity
  var count = 0
  for _ in game.allFleets(): count += 1
  for _ in game.allColonies(): count += 1
  for _ in game.allHouses(): count += 1
  count

proc createNoOpCommands(
    game: GameState, turn: int
): Table[HouseId, CommandPacket] =
  ## Create empty commands for all houses
  result = initTable[HouseId, CommandPacket]()
  for (houseId, house) in game.activeHousesWithId():
    result[houseId] = CommandPacket(
      houseId: houseId,
      turn: turn.int32,
      treasury: house.treasury.int32,
      fleetCommands: @[],
      buildCommands: @[],
      repairCommands: @[],
      researchAllocation: ResearchAllocation(),
      diplomaticCommand: @[],
      populationTransfers: @[],
      terraformCommands: @[],
      colonyManagement: @[],
      espionageActions: @[],
      ebpInvestment: 0,
      cipInvestment: 0
    )

suite "Performance: Turn Resolution Timing":

  test "Performance baseline: 4-house game, 100 turns":
    ## Establish baseline for standard game size

    echo "\nMeasuring baseline performance (4 houses, 100 turns)..."

    var game = newGame()
    var rng = initRand(42)
    var metrics: seq[PerformanceMetrics] = @[]

    for turn in 1..100:
      let commands = createNoOpCommands(game, turn)
      let timeMs = measureTurnTime(game, commands, rng)
      let stateSize = estimateStateSize(game)

      metrics.add(PerformanceMetrics(
        turnNumber: turn,
        resolutionTimeMs: timeMs,
        stateSize: stateSize
      ))
      
      # Handle victory
      let turnResult = game.resolveTurn(commands, rng)
      if turnResult.victoryCheck.victoryOccurred:
        echo &"  Game ended at turn {turn}"
        break

    # Analyze metrics
    if metrics.len > 0:
      let times = metrics.mapIt(it.resolutionTimeMs)
      let avgTime = times.mean()
      let stdDev = times.standardDeviation()
      let minTime = times.min()
      let maxTime = times.max()

      echo &"  Average turn time: {avgTime:.2f}ms (+/-{stdDev:.2f}ms)"
      echo &"  Min: {minTime:.2f}ms, Max: {maxTime:.2f}ms"
      echo &"  Final state size: {metrics[^1].stateSize} entities"

      # Performance threshold: turns should complete in < 100ms on average
      if avgTime > 100.0:
        echo &"  WARNING: Average turn time {avgTime:.2f}ms exceeds 100ms threshold"

  test "Performance degradation: detect O(n^2) algorithms":
    ## Run progressively longer games and check if time scales linearly

    echo "\nChecking for algorithmic degradation..."

    # Run games of increasing length
    let turnCounts = [10, 50, 100]
    var scalingData: seq[tuple[turns: int, avgTimeMs: float]] = @[]

    for numTurns in turnCounts:
      echo &"  Testing {numTurns} turns..."

      var game = newGame()
      var rng = initRand(123)
      var times: seq[float] = @[]

      for turn in 1..numTurns:
        let commands = createNoOpCommands(game, turn)
        let timeMs = measureTurnTime(game, commands, rng)
        times.add(timeMs)
        
        # Advance state
        let turnResult = game.resolveTurn(commands, rng)
        if turnResult.victoryCheck.victoryOccurred:
          break

      if times.len > 0:
        let avgTime = times.mean()
        scalingData.add((times.len, avgTime))
        echo &"    Average time: {avgTime:.2f}ms"

    # Check if scaling is roughly linear
    echo "\n  Scaling analysis:"
    for i in 1..<scalingData.len:
      let prev = scalingData[i-1]
      let curr = scalingData[i]
      let timeRatio = curr.avgTimeMs / prev.avgTimeMs

      echo &"    {prev.turns} -> {curr.turns} turns: time {timeRatio:.2f}x (expected ~1.0x for O(1) per turn)"

      # If time per turn increases significantly, we have a problem
      if timeRatio > 1.5:
        echo "    WARNING: Non-linear scaling detected (O(n) cumulative cost?)"

  test "Performance consistency: detect variance spikes":
    ## Check for occasional slow turns that indicate intermittent issues

    echo "\nChecking for performance variance..."

    var game = newGame()
    var rng = initRand(456)
    var times: seq[float] = @[]

    for turn in 1..100:
      let commands = createNoOpCommands(game, turn)
      let timeMs = measureTurnTime(game, commands, rng)
      times.add(timeMs)
      
      let turnResult = game.resolveTurn(commands, rng)
      if turnResult.victoryCheck.victoryOccurred:
        break

    if times.len < 10:
      echo "  Game ended too early for meaningful analysis"
      skip()

    # Detect outliers (turns that are abnormally slow)
    let avgTime = times.mean()
    let stdDev = times.standardDeviation()
    var outlierCount = 0

    for i, time in times:
      if time > avgTime + (3 * stdDev):  # 3-sigma outlier
        outlierCount += 1

    echo &"  Average: {avgTime:.2f}ms, StdDev: {stdDev:.2f}ms"
    echo &"  Outliers (> 3 sigma): {outlierCount}/{times.len}"

    if outlierCount > times.len div 10:
      echo "  WARNING: Too many slow turns (intermittent performance issue?)"

suite "Performance: Memory Pressure":

  test "Memory: sustained operation":
    ## Run long simulation and monitor for state size growth
    ## This is a proxy for memory leak detection

    echo "\nTesting sustained operation (500 turns)..."

    var game = newGame()
    var rng = initRand(789)

    # Sample state size over time
    var stateSizes: seq[tuple[turn: int, size: int]] = @[]

    for turn in 1..500:
      if turn mod 50 == 0:
        echo &"  Turn {turn}/500..."

      let commands = createNoOpCommands(game, turn)
      let turnResult = game.resolveTurn(commands, rng)
      
      if turnResult.victoryCheck.victoryOccurred:
        echo &"  Game ended at turn {turn}"
        break

      if turn mod 10 == 0:
        let size = estimateStateSize(game)
        stateSizes.add((turn, size))

    if stateSizes.len < 3:
      echo "  Game ended too early for meaningful analysis"
      skip()

    # Check if state size grows unboundedly
    echo "\n  State size over time:"
    echo &"    Early: {stateSizes[0].size} entities"
    echo &"    Middle: {stateSizes[stateSizes.len div 2].size} entities"
    echo &"    Final: {stateSizes[^1].size} entities"

    let initialSize = stateSizes[0].size
    let finalSize = stateSizes[^1].size
    
    if initialSize > 0:
      let growth = finalSize.float / initialSize.float
      echo &"  Growth factor: {growth:.2f}x"

      if growth > 5.0:
        echo "  WARNING: State size grew significantly (possible memory leak)"

when isMainModule:
  echo "========================================"
  echo "  EC4X Performance Regression Tests"
  echo "  Monitoring turn times and scaling"
  echo "========================================"
  echo ""
