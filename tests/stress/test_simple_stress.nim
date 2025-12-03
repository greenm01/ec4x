## Simple Stress Test
## Demonstrates stress testing on actual engine code

import std/[times, strformat, random, tables, options, sequtils, math]
import unittest
import ../../src/engine/[gamestate, resolve, orders, starmap]
import ../../src/engine/colonization/engine as colonization
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
  result.colonies[homeSystemId] = colonization.initNewColony(
    homeSystemId,
    "house1",
    PlanetClass.Benign,
    ResourceRating.Abundant,
    2000  # startingPTU
  )

suite "Simple Stress: State Integrity":

  test "100-turn simulation maintains valid state":
    echo "\n🧪 Running 100-turn simulation..."

    var game = createTestGameState()
    var turnTimes: seq[float] = @[]

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
        echo &"❌ Turn {turn} crashed: {e.msg}"
        fail()
        break

      let elapsed = (cpuTime() - startTime) * 1000.0
      turnTimes.add(elapsed)

    # Calculate statistics
    let avgTime = turnTimes.sum() / turnTimes.len.float
    let maxTime = turnTimes.max()
    let minTime = turnTimes.min()

    echo &"\n✅ Completed 100 turns"
    echo &"  Average turn time: {avgTime:.2f}ms"
    echo &"  Min: {minTime:.2f}ms, Max: {maxTime:.2f}ms"

    # Basic sanity checks
    check game.houses.len > 0
    check game.colonies.len > 0
    echo &"  Final state: {game.houses.len} houses, {game.colonies.len} colonies, {game.fleets.len} fleets"

  test "Invalid system ID handling":
    echo "\n🧪 Testing invalid system ID..."

    var game = createTestGameState()

    # Try to move fleet to invalid system
    var orders = initTable[HouseId, OrderPacket]()
    orders["house1"] = OrderPacket(
      houseId: "house1",
      turn: 1,
      buildOrders: @[],
      fleetOrders: @[
        FleetOrder(
          fleetId: "test-fleet",
          orderType: FleetOrderType.Move,
          targetSystem: some(SystemId(999999)),
          targetFleet: none(FleetId),
          priority: 0
        )
      ],
      researchAllocation: initResearchAllocation(),
      diplomaticActions: @[],
      populationTransfers: @[],
      terraformOrders: @[],
      espionageAction: none(esp_types.EspionageAttempt),
      ebpInvestment: 0,
      cipInvestment: 0
    )

    # Engine should handle gracefully
    try:
      let result = resolveTurn(game, orders)
      game = result.newState
      echo "  ✅ Engine handled invalid system ID gracefully"
    except CatchableError as e:
      echo &"  ⚠️  Engine rejected invalid input: {e.msg}"
      # This is acceptable - engine validation caught it

when isMainModule:
  echo "╔════════════════════════════════════════════════╗"
  echo "║  Simple Stress Test - Engine Validation       ║"
  echo "╚════════════════════════════════════════════════╝"
  echo ""
