## Engine Stress Test
## Real stress testing on actual EC4X engine code

import std/[times, strformat, tables, options, sequtils, stats]
import unittest
import stress_framework
import ../../src/engine/[gamestate, resolve, orders, starmap]
import ../../src/engine/research/types as res_types
import ../../src/engine/espionage/types as esp_types
import ../../src/engine/economy/types as econ_types
import ../../src/common/types/[core, planets]

proc createTestGameState(): GameState =
  ## Create a minimal game state for stress testing
  result = GameState()
  result.turn = 1
  result.phase = GamePhase.Active

  # Generate proper starmap (minimum 2 players)
  result.starMap = newStarMap(2, seed = 42)
  result.starMap.populate()

  # Get first player's starting system
  let homeSystemId = result.starMap.playerSystemIds[0]

  # Create test house
  result.houses["house1"] = House(
    id: "house1",
    name: "Test House",
    treasury: 10000,
    eliminated: false,
    techTree: res_types.initTechTree(),
  )

  # Create home colony at valid system
  result.colonies[homeSystemId] = Colony(
    systemId: homeSystemId,
    owner: "house1",
    population: 100,
    souls: 100_000_000,
    infrastructure: 5,
    planetClass: PlanetClass.Benign,
    resources: ResourceRating.Abundant,
    buildings: @[],
    production: 100,
    underConstruction: none(econ_types.ConstructionProject),
    constructionQueue: @[],
    activeTerraforming: none(gamestate.TerraformProject),
    unassignedSquadrons: @[],
    unassignedSpaceLiftShips: @[],
    fighterSquadrons: @[],
    capacityViolation: CapacityViolation(),
    starbases: @[],
    spaceports: @[
      Spaceport(id: "sp1", commissionedTurn: 1, docks: 5)
    ],
    shipyards: @[
      Shipyard(id: "sy1", commissionedTurn: 1, docks: 10, isCrippled: false)
    ]
  )

suite "Engine Stress: State Integrity":

  test "100-turn simulation maintains state integrity":
    echo "\n🧪 Running 100-turn engine stress test..."

    var game = createTestGameState()
    var turnTimes: seq[float] = @[]
    var allViolations: seq[InvariantViolation] = @[]

    for turn in 1..100:
      if turn mod 10 == 0:
        echo &"  Turn {turn}/100..."

      let startTime = cpuTime()

      # Create no-op orders
      var orders = initTable[HouseId, OrderPacket]()
      orders["house1"] = OrderPacket(
        houseId: "house1",
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

      # Resolve turn
      try:
        let result = resolveTurn(game, orders)
        game = result.newState
      except CatchableError as e:
        echo &"❌ Turn {turn} CRASHED: {e.msg}"
        fail()
        break

      let elapsed = (cpuTime() - startTime) * 1000.0
      turnTimes.add(elapsed)

      # Check state integrity every 10 turns
      if turn mod 10 == 0:
        let violations = checkStateInvariants(game, turn)
        if violations.len > 0:
          echo &"⚠️  Turn {turn}: Found {violations.len} violations"
          allViolations.add(violations)

    # Performance analysis
    let avgTime = turnTimes.mean()
    let stdDev = turnTimes.standardDeviation()
    let minTime = turnTimes.min()
    let maxTime = turnTimes.max()

    echo &"\n✅ Completed 100 turns"
    echo &"\n📊 Performance Metrics:"
    echo &"  Average turn time: {avgTime:.2f}ms (±{stdDev:.2f}ms)"
    echo &"  Range: {minTime:.2f}ms to {maxTime:.2f}ms"

    # Detect outliers
    var outliers = 0
    for time in turnTimes:
      if abs(time - avgTime) > 3 * stdDev:
        outliers.inc
    echo &"  Outliers (3σ): {outliers}/100 ({(outliers.float/100.0)*100:.1f}%)"

    # State analysis
    echo &"\n🔍 Final State:"
    echo &"  Houses: {game.houses.len}"
    echo &"  Colonies: {game.colonies.len}"
    echo &"  Fleets: {game.fleets.len}"
    echo &"  Treasury: {game.houses[\"house1\"].treasury} PP"

    # Report violations
    if allViolations.len > 0:
      echo &"\n⚠️  VIOLATIONS DETECTED: {allViolations.len} total"
      reportViolations(allViolations)

      let critical = allViolations.filterIt(it.severity == ViolationSeverity.Critical)
      if critical.len > 0:
        echo &"TEST FAILED: Found {critical.len} CRITICAL violations"
        fail()
    else:
      echo "\n✅ NO VIOLATIONS - State remained valid"

  test "500-turn long-duration test":
    echo "\n🧪 Running 500-turn long-duration stress test..."

    var game = createTestGameState()
    var checkpoints: seq[tuple[turn: int, houses: int, colonies: int, fleets: int]] = @[]

    for turn in 1..500:
      if turn mod 50 == 0:
        echo &"  Turn {turn}/500..."

      var orders = initTable[HouseId, OrderPacket]()
      orders["house1"] = OrderPacket(
        houseId: "house1",
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

      try:
        let result = resolveTurn(game, orders)
        game = result.newState
      except CatchableError as e:
        echo &"❌ CRASH at turn {turn}: {e.msg}"
        fail()
        break

      # Sample state size
      if turn mod 50 == 0:
        checkpoints.add((turn, game.houses.len, game.colonies.len, game.fleets.len))

    echo "\n✅ Completed 500 turns without crashing"
    echo "\n📊 State Growth Analysis:"
    for (turn, houses, colonies, fleets) in checkpoints:
      echo &"  Turn {turn:3}: {houses} houses, {colonies} colonies, {fleets} fleets"

    # Check for unbounded growth
    let initialSize = checkpoints[0]
    let finalSize = checkpoints[^1]
    echo &"\n  Growth: {finalSize.fleets - initialSize.fleets} fleets over 500 turns"

    if finalSize.fleets > initialSize.fleets + 100:
      echo "  ⚠️  WARNING: Significant fleet growth (possible leak?)"

suite "Engine Stress: Performance Scaling":

  test "Scaling analysis: 10, 50, 100 turns":
    echo "\n📈 Testing algorithmic scaling..."

    let turnCounts = [10, 50, 100]
    var results: seq[tuple[turns: int, avgMs: float]] = @[]

    for numTurns in turnCounts:
      echo &"  Running {numTurns} turns..."

      var game = createTestGameState()
      var times: seq[float] = @[]

      for turn in 1..numTurns:
        let start = cpuTime()

        var orders = initTable[HouseId, OrderPacket]()
        orders["house1"] = OrderPacket(
          houseId: "house1",
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

        let result = resolveTurn(game, orders)
        game = result.newState

        let elapsed = (cpuTime() - start) * 1000.0
        times.add(elapsed)

      let avgTime = times.mean()
      results.add((numTurns, avgTime))
      echo &"    Average: {avgTime:.2f}ms per turn"

    echo "\n📊 Scaling Analysis:"
    for i in 1..<results.len:
      let prev = results[i-1]
      let curr = results[i]
      let turnRatio = curr.turns.float / prev.turns.float
      let timeRatio = curr.avgMs / prev.avgMs

      echo &"  {prev.turns} → {curr.turns} turns: time {timeRatio:.2f}x (expected ~{turnRatio:.2f}x for linear)"

      if timeRatio > turnRatio * 1.5:
        echo "    ⚠️  Non-linear scaling detected (possible O(n²) algorithm)"

when isMainModule:
  echo "╔════════════════════════════════════════════════╗"
  echo "║  EC4X Engine Stress Tests                     ║"
  echo "║  Real stress testing on actual engine code    ║"
  echo "╚════════════════════════════════════════════════╝"
  echo ""
