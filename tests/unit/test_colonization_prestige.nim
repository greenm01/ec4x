## Test for colonization prestige bug fix (Phase 8 Week 1 Day 1)
##
## This test verifies that prestige is correctly awarded when establishing colonies.
## Previously, line 442 in fleet_orders.nim had a critical bug where prestige
## was mutated on a Table copy and never persisted to the game state.

import std/[unittest, tables, options]
import ../../src/engine/[gamestate, state_helpers]
import ../../src/engine/resolution/fleet_orders
import ../../src/engine/colonization/engine as col_engine
import ../../src/common/types/[core, planets, units]
import ../../src/common/system
import ../../src/engine/[fleet, squadron, orders, starmap, spacelift]

proc createTestGameState(): GameState =
  ## Create minimal game state for colonization testing
  result = GameState(
    turn: 1,
    houses: initTable[HouseId, House](),
    colonies: initTable[SystemId, Colony](),
    fleets: initTable[FleetId, Fleet](),
    starMap: StarMap(
      systems: initTable[SystemId, System](),
      lanes: @[]
    ),
    fleetOrders: initTable[FleetId, FleetOrder](),
    standingOrders: initTable[FleetId, StandingOrder]()
  )

  # Create test house with initial prestige
  let house = House(
    id: "house-test",
    name: "Test House",
    treasury: 1000,
    prestige: 50,  # Starting prestige
    eliminated: false
  )
  result.houses["house-test"] = house

  # Create test system
  let system = System(
    id: "system-target",
    name: "Target System",
    planetClass: PlanetClass.Eden,
    resourceRating: ResourceRating.Rich,
    coordinates: (x: 0, y: 0)
  )
  result.starMap.systems["system-target"] = system

  # Create ETAC fleet with colonists at target system
  let etacShip = Ship(
    id: "ship-etac-1",
    class: ShipClass.ETAC,
    name: "Colony Ship",
    cargo: Cargo(
      cargoType: CargoType.Colonists,
      quantity: 1  # 1 PTU
    )
  )

  let fleet = Fleet(
    id: "fleet-colony",
    owner: "house-test",
    location: "system-target",
    status: FleetStatus.Active,
    squadrons: @[],
    spaceLiftShips: @[etacShip]
  )
  result.fleets["fleet-colony"] = fleet

suite "Colonization Prestige Bug Fix":
  test "Prestige is correctly awarded for colonizing Eden world":
    var state = createTestGameState()
    var events: seq[GameEvent] = @[]

    # Record initial prestige
    let prestigeBefore = state.houses["house-test"].prestige

    # Create colonization order
    let colonizationOrder = FleetOrder(
      fleetId: "fleet-colony",
      orderType: FleetOrderType.Colonize,
      targetSystem: some("system-target"),
      targetFleet: none(FleetId),
      priority: 1
    )

    # Execute colonization
    resolveColonizationOrder(state, "house-test", colonizationOrder, events)

    # Verify colony was established
    check "system-target" in state.colonies

    # CRITICAL: Verify prestige was correctly awarded (bug fix verification)
    let prestigeAfter = state.houses["house-test"].prestige
    let prestigeGained = prestigeAfter - prestigeBefore

    # Per economy.md:3.3, Eden worlds give +12 prestige
    check prestigeGained == 12
    check prestigeAfter == 62  # 50 + 12

    echo &"✓ Prestige correctly increased from {prestigeBefore} to {prestigeAfter} (+{prestigeGained})"

  test "Prestige persists through multiple state accesses":
    var state = createTestGameState()
    var events: seq[GameEvent] = @[]

    let prestigeBefore = state.houses["house-test"].prestige

    # Execute colonization
    let colonizationOrder = FleetOrder(
      fleetId: "fleet-colony",
      orderType: FleetOrderType.Colonize,
      targetSystem: some("system-target"),
      targetFleet: none(FleetId),
      priority: 1
    )
    resolveColonizationOrder(state, "house-test", colonizationOrder, events)

    # Access house multiple times to verify persistence
    let prestige1 = state.houses["house-test"].prestige
    let prestige2 = state.houses["house-test"].prestige
    let prestige3 = state.houses["house-test"].prestige

    # All reads should return the same updated value
    check prestige1 == prestige2
    check prestige2 == prestige3
    check prestige1 == prestigeBefore + 12

    echo &"✓ Prestige persists across multiple reads: {prestige1}"

  test "Multiple colonizations accumulate prestige correctly":
    var state = createTestGameState()
    var events: seq[GameEvent] = @[]

    # Create second target system
    let system2 = System(
      id: "system-target-2",
      name: "Target System 2",
      planetClass: PlanetClass.Arid,
      resourceRating: ResourceRating.Average,
      coordinates: (x: 1, y: 1)
    )
    state.starMap.systems["system-target-2"] = system2

    # Create second ETAC fleet
    let etacShip2 = Ship(
      id: "ship-etac-2",
      class: ShipClass.ETAC,
      name: "Colony Ship 2",
      cargo: Cargo(
        cargoType: CargoType.Colonists,
        quantity: 1
      )
    )

    let fleet2 = Fleet(
      id: "fleet-colony-2",
      owner: "house-test",
      location: "system-target-2",
      status: FleetStatus.Active,
      squadrons: @[],
      spaceLiftShips: @[etacShip2]
    )
    state.fleets["fleet-colony-2"] = fleet2

    let prestigeStart = state.houses["house-test"].prestige  # 50

    # First colonization (Eden: +12)
    let order1 = FleetOrder(
      fleetId: "fleet-colony",
      orderType: FleetOrderType.Colonize,
      targetSystem: some("system-target"),
      targetFleet: none(FleetId),
      priority: 1
    )
    resolveColonizationOrder(state, "house-test", order1, events)

    let prestigeAfterFirst = state.houses["house-test"].prestige
    check prestigeAfterFirst == 62  # 50 + 12

    # Second colonization (Arid: +10)
    let order2 = FleetOrder(
      fleetId: "fleet-colony-2",
      orderType: FleetOrderType.Colonize,
      targetSystem: some("system-target-2"),
      targetFleet: none(FleetId),
      priority: 1
    )
    resolveColonizationOrder(state, "house-test", order2, events)

    let prestigeFinal = state.houses["house-test"].prestige
    check prestigeFinal == 72  # 50 + 12 + 10

    echo &"✓ Multiple colonizations accumulate: {prestigeStart} → {prestigeAfterFirst} → {prestigeFinal}"

when isMainModule:
  echo "Running colonization prestige bug fix tests..."
  echo "This test verifies the fix for the critical Table copy bug at fleet_orders.nim:442"
  echo ""
