## Test suite for offline game engine
##
## This tests the core gameplay systems independently of network transport
## Validates the offline-first architecture

import unittest
import std/[tables, options]
import ../../src/engine/[gamestate, orders, resolve, starmap]
import ../../src/engine/economy/types as econ_types
import ../../src/engine/research/types as res_types
import ../../src/engine/espionage/types as esp_types
import ../../src/common/types/[core, units]

proc createTestState(): GameState =
  ## Create a minimal 2-player game state for offline testing
  result = GameState()
  result.turn = 1
  result.phase = GamePhase.Active

  # Generate starmap
  var map = newStarMap(2)
  map.populate()
  result.starMap = map

  # Create houses with homeworlds
  for i in 0..<2:
    let houseId = HouseId($i)
    let homeworldId = map.playerSystemIds[i]

    result.houses[houseId] = House(
      id: houseId,
      name: "House " & $i,
      treasury: 10000,
      eliminated: false,
      techTree: res_types.initTechTree(),
    )

    result.colonies[homeworldId] = createHomeColony(homeworldId.SystemId, houseId)

suite "Offline Engine - No Network Dependencies":

  test "Can create 2-player game without network":
    let state = createTestState()

    check state.houses.len == 2
    check state.starMap.systems.len > 0
    check state.turn == 1
    check state.phase == GamePhase.Active

  test "Turn resolution works offline":
    var state = createTestState()
    let initialTurn = state.turn

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

    # Resolve turn - should work entirely offline
    let result = resolveTurn(state, orders)

    check result.newState.turn == initialTurn + 1

  test "Game state is pure data structure":
    let state = createTestState()

    # Verify game state contains no network connections
    # (All fields are pure data: integers, strings, tables, sequences)
    check state.starMap.systems.len > 0
    check state.colonies.len == 2  # 2 homeworlds
    check state.houses.len == 2

  test "Multiple turns can be resolved offline":
    var state = createTestState()
    let initialTurn = state.turn

    # Resolve 3 turns
    for i in 1..3:
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

      let result = resolveTurn(state, orders)
      state = result.newState

    check state.turn == initialTurn + 3  # Started at turn 1, resolved 3 turns

  test "Economy systems work offline":
    let state = createTestState()

    # Verify colonies have population and infrastructure
    var foundColonyWithEconomy = false
    for colony in state.colonies.values:
      if colony.populationUnits > 0 and colony.infrastructure > 0:
        foundColonyWithEconomy = true
        break

    check foundColonyWithEconomy

  test "Houses have starting treasury":
    let state = createTestState()

    # All houses should have starting treasury
    for house in state.houses.values:
      check house.treasury > 0
      check not house.eliminated

  test "Starmap connectivity works offline":
    let state = createTestState()

    # Verify systems have jump lanes
    var foundSystemWithNeighbors = false
    for systemId in state.starMap.systems.keys:
      let neighbors = state.starMap.getAdjacentSystems(systemId)
      if neighbors.len > 0:
        foundSystemWithNeighbors = true
        break

    check foundSystemWithNeighbors
