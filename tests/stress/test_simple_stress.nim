## Simple Stress Test
## Demonstrates stress testing on actual engine code

import std/[times, strformat, random, tables, options]
import unittest

# Import from integration test to get working game state creation
import ../integration/test_resolution_comprehensive

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
        echo &"❌ Turn {turn} crashed: {e.msg}"
        fail()
        return

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
      squadronManagement: @[],
      cargoManagement: @[],
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
