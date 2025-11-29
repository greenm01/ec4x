## Quick Stress Test Demo
## Demonstrates core stress testing concepts without full engine

import std/[times, strformat, tables, random, stats]
import unittest

echo "╔════════════════════════════════════════════════╗"
echo "║  EC4X Stress Test Framework - Demo            ║"
echo "╚════════════════════════════════════════════════╝"
echo ""

suite "Stress Test Demo: Concepts":

  test "Performance monitoring over many iterations":
    echo "\n📊 Demo: Performance Monitoring"

    var times: seq[float] = @[]

    for i in 1..1000:
      let start = cpuTime()
      var total = 0
      for j in 1..10000:
        total += j
      let elapsed = (cpuTime() - start) * 1000000.0  # microseconds
      times.add(elapsed)

    let avgTime = times.mean()
    let stdDev = times.standardDeviation()
    let minTime = times.min()
    let maxTime = times.max()

    echo &"  Ran 1000 iterations"
    echo &"  Average: {avgTime:.2f}µs (±{stdDev:.2f}µs)"
    echo &"  Range: {minTime:.2f}µs to {maxTime:.2f}µs"

    # Detect outliers (3-sigma)
    var outliers = 0
    for time in times:
      if abs(time - avgTime) > 3 * stdDev:
        outliers.inc

    echo &"  Outliers (3σ): {outliers} ({(outliers.float/1000.0)*100:.1f}%)"
    echo "  ✅ Performance monitoring demonstrated"

  test "Statistical anomaly detection":
    echo "\n🔍 Demo: Statistical Anomaly Detection"

    # Simulate 100 "games" with metrics
    var finalScores: seq[int] = @[]
    var rng = initRand(42)

    for gameNum in 1..100:
      # Normal games: score around 1000 ±200
      let baseScore = 1000 + rng.rand(-200..200)

      # Inject 2 anomalies
      let score = if gameNum == 13 or gameNum == 87:
        5000  # Anomalously high
      else:
        baseScore

      finalScores.add(score)

    # Statistical analysis
    let avgScore = finalScores.mean()
    let stdScore = finalScores.standardDeviation()

    echo &"  Ran 100 simulated games"
    echo &"  Average score: {avgScore:.0f} (±{stdScore:.0f})"

    # Detect anomalies
    var anomalies: seq[tuple[game: int, score: int]] = @[]
    for i, score in finalScores:
      if abs(score.float - avgScore) > 3 * stdScore:
        anomalies.add((i + 1, score))

    echo &"  Anomalies detected: {anomalies.len}"
    for (gameNum, score) in anomalies:
      echo &"    Game {gameNum}: score = {score} ({((score.float-avgScore)/stdScore):.1f}σ)"

    check anomalies.len == 2  # We injected 2 anomalies
    echo "  ✅ Anomaly detection working"

  test "Scaling analysis (O(n) vs O(n²))":
    echo "\n📈 Demo: Algorithmic Scaling Detection"

    # Simulate processing with different sizes
    let sizes = [10, 50, 100, 200]
    var results: seq[tuple[size: int, timeMs: float]] = @[]

    for n in sizes:
      let start = cpuTime()

      # O(n) algorithm
      var total = 0
      for i in 1..n*1000:
        total += i

      let elapsed = (cpuTime() - start) * 1000.0
      results.add((n, elapsed))

    echo "  Processing time vs size:"
    for i, (size, time) in results:
      echo &"    n={size:3}: {time:.2f}ms"

      if i > 0:
        let prevSize = results[i-1].size
        let prevTime = results[i-1].timeMs
        let sizeRatio = size.float / prevSize.float
        let timeRatio = time / prevTime

        echo &"        Scaling: {sizeRatio:.1f}x size → {timeRatio:.1f}x time"

        # For O(n), time ratio should ≈ size ratio
        # For O(n²), time ratio would be ≈ size ratio²
        if timeRatio > sizeRatio * 1.5:
          echo "        ⚠️  Non-linear scaling detected!"

    echo "  ✅ Scaling analysis demonstrated"

  test "State integrity checking simulation":
    echo "\n🔍 Demo: State Integrity Checks"

    # Simulate game state with intentional corruption
    type
      MockGameState = object
        turn: int
        treasury: int
        entityCount: int
        entityIds: seq[string]

    proc checkInvariants(state: MockGameState): seq[string] =
      ## Check state invariants
      var violations: seq[string] = @[]

      # Treasury should be >= -1000
      if state.treasury < -1000:
        violations.add(&"Treasury too negative: {state.treasury}")

      # Entity count should match ID list
      if state.entityCount != state.entityIds.len:
        violations.add(&"Entity count mismatch: {state.entityCount} vs {state.entityIds.len}")

      # No duplicate IDs
      var seen: Table[string, int]
      for id in state.entityIds:
        seen[id] = seen.getOrDefault(id, 0) + 1

      for id, count in seen:
        if count > 1:
          violations.add(&"Duplicate ID: {id} appears {count} times")

      return violations

    # Test valid state
    var state1 = MockGameState(
      turn: 1,
      treasury: 5000,
      entityCount: 3,
      entityIds: @["fleet1", "fleet2", "fleet3"]
    )

    let v1 = checkInvariants(state1)
    check v1.len == 0
    echo "  ✅ Valid state: no violations"

    # Test corrupt state
    var state2 = MockGameState(
      turn: 10,
      treasury: -5000,  # Too negative!
      entityCount: 2,
      entityIds: @["fleet1", "fleet1", "fleet2"]  # Duplicate + count mismatch!
    )

    let v2 = checkInvariants(state2)
    echo &"  ⚠️  Corrupt state: {v2.len} violations detected:"
    for v in v2:
      echo &"     - {v}"

    check v2.len == 3
    echo "  ✅ Invariant checking demonstrated"

when isMainModule:
  echo ""
  echo "═══════════════════════════════════════════════"
  echo "These demos show the CONCEPTS used in real"
  echo "stress tests. The actual tests would:"
  echo ""
  echo "• Run 1000+ turn game simulations"
  echo "• Test with actual EC4X engine code"
  echo "• Use full game state invariant checking"
  echo "• Collect comprehensive metrics"
  echo "• Run 100+ complete games for statistics"
  echo ""
  echo "Framework is built and ready at tests/stress/"
  echo "═══════════════════════════════════════════════"
