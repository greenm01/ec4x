## Engine Stress Test
## Real stress testing on actual EC4X engine code
##
## Updated for new engine architecture (2026-01)

import std/[times, strformat, tables, options, sequtils, stats, random]
import unittest
import stress_framework
import ../../src/engine/engine
import ../../src/engine/types/[core, command, house, tech, espionage]
import ../../src/engine/state/iterators
import ../../src/engine/turn_cycle/engine

suite "Engine Stress: State Integrity":

  test "100-turn simulation maintains state integrity":
    echo "\nRunning 100-turn engine stress test..."

    var game = newGame()
    var rng = initRand(42)
    var turnTimes: seq[float] = @[]
    var allViolations: seq[InvariantViolation] = @[]

    for turn in 1..100:
      if turn mod 10 == 0:
        echo &"  Turn {turn}/100..."

      let startTime = cpuTime()

      # Create empty commands (no-op turn)
      var commands = initTable[HouseId, CommandPacket]()
      for (houseId, house) in game.activeHousesWithId():
        commands[houseId] = CommandPacket(
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
          espionageAction: none(EspionageAttempt),
          ebpInvestment: 0,
          cipInvestment: 0
        )

      # Resolve turn
      try:
        let turnResult = game.resolveTurn(commands, rng)
        
        # Check for victory (game might end early)
        if turnResult.victoryCheck.victoryOccurred:
          echo &"  Victory achieved at turn {turn}: {turnResult.victoryCheck.status.description}"
          break
          
      except CatchableError as e:
        echo &"Turn {turn} CRASHED: {e.msg}"
        fail()
        break

      let elapsed = (cpuTime() - startTime) * 1000.0
      turnTimes.add(elapsed)

      # Check state integrity every 10 turns
      if turn mod 10 == 0:
        let violations = checkStateInvariants(game, turn)
        if violations.len > 0:
          echo &"  Turn {turn}: Found {violations.len} violations"
          allViolations.add(violations)

    # Performance analysis
    if turnTimes.len > 0:
      let avgTime = turnTimes.mean()
      let stdDev = turnTimes.standardDeviation()
      let minTime = turnTimes.min()
      let maxTime = turnTimes.max()

      echo &"\nCompleted {turnTimes.len} turns"
      echo &"\nPerformance Metrics:"
      echo &"  Average turn time: {avgTime:.2f}ms (+/-{stdDev:.2f}ms)"
      echo &"  Range: {minTime:.2f}ms to {maxTime:.2f}ms"

      # Detect outliers
      var outliers = 0
      for time in turnTimes:
        if abs(time - avgTime) > 3 * stdDev:
          outliers.inc
      echo &"  Outliers (3 sigma): {outliers}/{turnTimes.len}"

    # State analysis
    var houseCount, colonyCount, fleetCount = 0
    for _ in game.allHouses(): houseCount += 1
    for _ in game.allColonies(): colonyCount += 1
    for _ in game.allFleets(): fleetCount += 1

    echo &"\nFinal State:"
    echo &"  Houses: {houseCount}"
    echo &"  Colonies: {colonyCount}"
    echo &"  Fleets: {fleetCount}"

    # Report violations
    if allViolations.len > 0:
      echo &"\nVIOLATIONS DETECTED: {allViolations.len} total"
      reportViolations(allViolations)

      let critical = allViolations.filterIt(it.severity == ViolationSeverity.Critical)
      if critical.len > 0:
        echo &"TEST FAILED: Found {critical.len} CRITICAL violations"
        fail()
    else:
      echo "\nNO VIOLATIONS - State remained valid"

  test "500-turn long-duration test":
    echo "\nRunning 500-turn long-duration stress test..."

    var game = newGame()
    var rng = initRand(12345)
    var checkpoints: seq[tuple[turn: int, houses: int, colonies: int, fleets: int]] = @[]

    for turn in 1..500:
      if turn mod 50 == 0:
        echo &"  Turn {turn}/500..."

      var commands = initTable[HouseId, CommandPacket]()
      for (houseId, house) in game.activeHousesWithId():
        commands[houseId] = CommandPacket(
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
          espionageAction: none(EspionageAttempt),
          ebpInvestment: 0,
          cipInvestment: 0
        )

      try:
        let turnResult = game.resolveTurn(commands, rng)
        
        if turnResult.victoryCheck.victoryOccurred:
          echo &"  Victory achieved at turn {turn}"
          break
          
      except CatchableError as e:
        echo &"CRASH at turn {turn}: {e.msg}"
        fail()
        break

      # Sample state size
      if turn mod 50 == 0:
        var houses, colonies, fleets = 0
        for _ in game.allHouses(): houses += 1
        for _ in game.allColonies(): colonies += 1
        for _ in game.allFleets(): fleets += 1
        checkpoints.add((turn, houses, colonies, fleets))

    if checkpoints.len > 0:
      echo "\nCompleted long-duration test"
      echo "\nState Growth Analysis:"
      for (turn, houses, colonies, fleets) in checkpoints:
        echo &"  Turn {turn:3}: {houses} houses, {colonies} colonies, {fleets} fleets"

      # Check for unbounded growth
      if checkpoints.len > 1:
        let initialSize = checkpoints[0]
        let finalSize = checkpoints[^1]
        echo &"\n  Fleet growth: {finalSize.fleets - initialSize.fleets} over {checkpoints[^1].turn} turns"

        if finalSize.fleets > initialSize.fleets + 100:
          echo "  WARNING: Significant fleet growth (possible leak?)"

suite "Engine Stress: Performance Scaling":

  test "Scaling analysis: 10, 50, 100 turns":
    echo "\nTesting algorithmic scaling..."

    let turnCounts = [10, 50, 100]
    var results: seq[tuple[turns: int, avgMs: float]] = @[]

    for numTurns in turnCounts:
      echo &"  Running {numTurns} turns..."

      var game = newGame()
      var rng = initRand(numTurns.int64)
      var times: seq[float] = @[]

      for turn in 1..numTurns:
        let start = cpuTime()

        var commands = initTable[HouseId, CommandPacket]()
        for (houseId, house) in game.activeHousesWithId():
          commands[houseId] = CommandPacket(
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
            espionageAction: none(EspionageAttempt),
            ebpInvestment: 0,
            cipInvestment: 0
          )

        let turnResult = game.resolveTurn(commands, rng)
        
        if turnResult.victoryCheck.victoryOccurred:
          break

        let elapsed = (cpuTime() - start) * 1000.0
        times.add(elapsed)

      if times.len > 0:
        let avgTime = times.mean()
        results.add((numTurns, avgTime))
        echo &"    Average: {avgTime:.2f}ms per turn"

    if results.len > 1:
      echo "\nScaling Analysis:"
      for i in 1..<results.len:
        let prev = results[i-1]
        let curr = results[i]
        let timeRatio = curr.avgMs / prev.avgMs

        echo &"  {prev.turns} -> {curr.turns} turns: time {timeRatio:.2f}x (expected ~1.0x for O(1) per turn)"

        if timeRatio > 1.5:
          echo "    WARNING: Non-constant scaling detected (possible O(n) cumulative cost)"

when isMainModule:
  echo "========================================"
  echo "  EC4X Engine Stress Tests"
  echo "  Real stress testing on actual engine"
  echo "========================================"
  echo ""
