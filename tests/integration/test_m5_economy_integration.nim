## Integration Test for M5 Economy System
##
## Tests that M5 economy modules integrate correctly with resolve.nim

import std/[unittest, tables, options]
import ../../src/engine/[gamestate, resolve, orders, starmap]
import ../../src/engine/initialization/game
import ../../src/engine/research/types as res_types
import ../../src/common/types/[core, planets, units, tech]

suite "M5 Economy Integration with resolve.nim":
  test "Income phase runs with M5 economy":
    # Create minimal game state
    var testMap = newStarMap(10)  # 10 systems
    testMap.populate()
    var state = newGameState("test-game", 2, testMap)

    # Add two houses
    let house1 = initializeHouse("Alpha", "blue")
    let house2 = initializeHouse("Beta", "red")
    state.houses["house-alpha"] = house1
    state.houses["house-beta"] = house2

    # Add a colony for house1
    var colony1 = createHomeColony(SystemId(1), "house-alpha")
    colony1.population = 100  # 100 million = 100 PU
    colony1.infrastructure = 5  # Will map to 50 IU
    colony1.planetClass = PlanetClass.Eden
    colony1.resources = ResourceRating.Abundant
    state.colonies[SystemId(1)] = colony1

    # Add a colony for house2
    var colony2 = createHomeColony(SystemId(2), "house-beta")
    colony2.population = 50
    colony2.infrastructure = 3
    colony2.planetClass = PlanetClass.Benign
    colony2.resources = ResourceRating.Poor
    state.colonies[SystemId(2)] = colony2

    # Create empty order packets
    var orders = initTable[HouseId, OrderPacket]()
    orders["house-alpha"] = OrderPacket(
      houseId: "house-alpha",
      turn: 1,
      buildOrders: @[],
      fleetOrders: @[],
      researchAllocation: res_types.ResearchAllocation(
        economic: 0,
        science: 0,
        technology: initTable[TechField, int]()
      )
    )

    # Resolve a turn
    let result = resolveTurn(state, orders)

    # Verify houses got income
    check result.newState.houses["house-alpha"].treasury > 0
    check result.newState.houses["house-beta"].treasury > 0

    # House with better colony should have more income
    check result.newState.houses["house-alpha"].treasury >= result.newState.houses["house-beta"].treasury

  test "Maintenance phase runs with M5 economy":
    # Create game state with fleets
    var testMap = newStarMap(10)
    testMap.populate()
    var state = newGameState("test-game", 1, testMap)

    let house1 = initializeHouse("Alpha", "blue")
    state.houses["house-alpha"] = house1

    # Add colony
    let colony1 = createHomeColony(SystemId(1), "house-alpha")
    state.colonies[SystemId(1)] = colony1

    # TODO: Add fleet with ships
    # For now, test passes if no errors

    var orders = initTable[HouseId, OrderPacket]()
    let result = resolveTurn(state, orders)

    # Should complete without errors
    check result.newState.turn == state.turn + 1

  test "Full turn cycle processes all phases":
    # Create complete game state
    var testMap = newStarMap(10)
    testMap.populate()
    var state = newGameState("test-game", 2, testMap)
    state.phase = GamePhase.Active

    # Setup houses and colonies
    state.houses["house-alpha"] = initializeHouse("Alpha", "blue")
    state.houses["house-beta"] = initializeHouse("Beta", "red")

    let colony1 = createHomeColony(SystemId(1), "house-alpha")
    let colony2 = createHomeColony(SystemId(2), "house-beta")
    state.colonies[SystemId(1)] = colony1
    state.colonies[SystemId(2)] = colony2

    var orders = initTable[HouseId, OrderPacket]()

    # Run 3 turns
    var currentState = state
    for i in 1..3:
      let result = resolveTurn(currentState, orders)
      currentState = result.newState

      # Verify turn advanced
      check currentState.turn == state.turn + i
      check result.events.len >= 0  # May have events

    # After 3 turns, game should still be active
    check currentState.phase == GamePhase.Active
