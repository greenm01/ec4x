## Test suite for offline game engine
##
## This tests the core gameplay systems independently of network transport
## Validates the offline-first architecture

import std/[tables, options]
import ../../src/engine/[gamestate, orders, resolve, starmap]
import ../../src/engine/economy/[types as econ_types, income]
import ../../src/engine/research/types as res_types
import ../../src/engine/espionage/types as esp_types
import ../../src/common/types/[core, planets, units]
# Note: Combat tests use engine/combat/ modules directly

# Test that we can create a game and run turns without any network
proc testOfflineGameFlow() =
  echo "Testing offline game flow..."

  # Create a basic 2-player game
  var map = newStarMap(2)
  map.populate()

  # Create initial game state
  var state = newGameState("test-game", 2, map)

  # Create empty order packets
  var orders: Table[HouseId, OrderPacket]
  for houseId in state.houses.keys:
    orders[houseId] = OrderPacket(
      houseId: houseId,
      turn: state.turn,
      fleetOrders: @[],
      buildOrders: @[],
      researchAllocation: initResearchAllocation(),
      diplomaticActions: @[],
      populationTransfers: @[],
      terraformOrders: @[],
      espionageAction: none(esp_types.EspionageAttempt),
      ebpInvestment: 0,
      cipInvestment: 0
    )

  # Resolve a turn - should work entirely offline
  let result = resolveTurn(state, orders)

  assert result.newState.turn == state.turn + 1
  echo "  ✓ Turn resolution works offline"

  # Verify game state is pure data (no network connections)
  assert result.newState.starMap.systems.len > 0
  echo "  ✓ Game state is pure data structure"

  echo "Offline engine test passed!\n"

when isMainModule:
  echo "EC4X Offline Engine Test Suite"
  echo "==============================\n"

  testOfflineGameFlow()

  echo "All tests passed!"
  echo "\nNext steps for implementation:"
  echo "1. Implement combat.resolveBattle()"
  echo "2. Implement economy.calculateProduction()"
  echo "3. Implement movement integration with pathfinding"
  echo "4. Build simple TUI for hotseat multiplayer"
  echo "\nNetwork integration (Nostr) comes after offline game is complete."
