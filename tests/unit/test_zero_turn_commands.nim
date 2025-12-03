## Comprehensive Zero-Turn Command Tests
##
## Tests the unified zero-turn command system for fleet operations,
## cargo management, and squadron management

import std/[unittest, tables, options, strutils]
import ../../src/engine/[gamestate, orders, fleet, squadron, ship, spacelift]
import ../../src/engine/commands/zero_turn_commands
import ../../src/engine/economy/types as econ_types
import ../../src/engine/research/types as res_types
import ../../src/engine/espionage/types as esp_types
import ../../src/common/types/[core, units, planets]

suite "Zero-Turn Commands: Basic Validation":

  proc createTestState(): GameState =
    var result = GameState()
    result.turn = 1
    result.houses["H1"] = House(
      id: "H1",
      name: "House One",
      treasury: 10000,
      eliminated: false,
      techTree: res_types.initTechTree()
    )

    result.colonies[SystemId(1)] = Colony(
      systemId: SystemId(1),
      owner: "H1",
      population: 100_000_000,
      souls: 20000,
      marines: 10,
      infrastructure: 5,
      planetClass: PlanetClass.Benign,
      resources: ResourceRating.Abundant,
      buildings: @[],
      production: 100,
      underConstruction: none(econ_types.ConstructionProject),
      activeTerraforming: none(gamestate.TerraformProject),
      unassignedSquadrons: @[],
      unassignedSpaceLiftShips: @[],
      fighterSquadrons: @[],
      capacityViolation: CapacityViolation(),
      starbases: @[],
      spaceports: @[],
      shipyards: @[]
    )

    result

  test "validateOwnership - valid house":
    let state = createTestState()
    let result = validateOwnership(state, "H1")
    check result.valid == true

  test "validateOwnership - invalid house":
    let state = createTestState()
    let result = validateOwnership(state, "H_INVALID")
    check result.valid == false

  test "validateColonyOwnership - valid colony":
    let state = createTestState()
    let result = validateColonyOwnership(state, SystemId(1), "H1")
    check result.valid == true

  test "validateColonyOwnership - no colony":
    let state = createTestState()
    let result = validateColonyOwnership(state, SystemId(999), "H1")
    check result.valid == false

suite "Zero-Turn Commands: Fleet Operations":

  proc createFleetTestState(): GameState =
    var result = GameState()
    result.turn = 1
    result.houses["H1"] = House(
      id: "H1",
      name: "House One",
      treasury: 10000,
      eliminated: false,
      techTree: res_types.initTechTree()
    )

    result.colonies[SystemId(1)] = Colony(
      systemId: SystemId(1),
      owner: "H1",
      population: 100_000_000,
      souls: 20000,
      marines: 10,
      infrastructure: 5,
      planetClass: PlanetClass.Benign,
      resources: ResourceRating.Abundant,
      buildings: @[],
      production: 100,
      underConstruction: none(econ_types.ConstructionProject),
      activeTerraforming: none(gamestate.TerraformProject),
      unassignedSquadrons: @[],
      unassignedSpaceLiftShips: @[],
      fighterSquadrons: @[],
      capacityViolation: CapacityViolation(),
      starbases: @[],
      spaceports: @[],
      shipyards: @[]
    )

    # Create a fleet with 2 ships
    let destroyer1 = newEnhancedShip(ShipClass.Destroyer)
    let destroyer2 = newEnhancedShip(ShipClass.Destroyer)
    var sq1 = newSquadron(destroyer1, id = "S1", owner = "H1", location = 1)
    discard sq1.addShip(destroyer2)

    result.fleets["F1"] = Fleet(
      id: "F1",
      owner: "H1",
      location: SystemId(1),
      squadrons: @[sq1],
      spaceLiftShips: @[],
      status: FleetStatus.Active,
      autoBalanceSquadrons: true
    )

    result

  test "DetachShips - create new fleet":
    var state = createFleetTestState()

    let cmd = ZeroTurnCommand(
      houseId: "H1",
      commandType: ZeroTurnCommandType.DetachShips,
      sourceFleetId: some("F1"),
      shipIndices: @[0]
    )

    let result = submitZeroTurnCommand(state, cmd)
    check result.success == true
    check result.newFleetId.isSome

    # Original fleet should be deleted (only had 1 squadron, detached all of it)
    # NOTE: Detaching any ship from a squadron detaches the entire squadron
    check not state.fleets.hasKey("F1")

    # New fleet should exist with the detached squadron
    check state.fleets.hasKey(result.newFleetId.get())
    check state.fleets[result.newFleetId.get()].squadrons.len == 1

  test "MergeFleets - combine two fleets":
    var state = createFleetTestState()

    # Create second fleet
    let cruiser = newEnhancedShip(ShipClass.Cruiser)
    var sq2 = newSquadron(cruiser, id = "S2", owner = "H1", location = 1)

    state.fleets["F2"] = Fleet(
      id: "F2",
      owner: "H1",
      location: SystemId(1),
      squadrons: @[sq2],
      spaceLiftShips: @[],
      status: FleetStatus.Active,
      autoBalanceSquadrons: true
    )

    let cmd = ZeroTurnCommand(
      houseId: "H1",
      commandType: ZeroTurnCommandType.MergeFleets,
      sourceFleetId: some("F1"),
      targetFleetId: some("F2")
    )

    let result = submitZeroTurnCommand(state, cmd)
    check result.success == true

    # Source fleet should be deleted
    check not state.fleets.hasKey("F1")

    # Target fleet should have both squadrons
    check state.fleets["F2"].squadrons.len == 2

suite "Zero-Turn Commands: Cargo Operations":

  proc createCargoTestState(): GameState =
    var result = GameState()
    result.turn = 1
    result.houses["H1"] = House(
      id: "H1",
      name: "House One",
      treasury: 10000,
      eliminated: false,
      techTree: res_types.initTechTree()
    )

    result.colonies[SystemId(1)] = Colony(
      systemId: SystemId(1),
      owner: "H1",
      population: 100_000_000,
      souls: 20000,
      marines: 10,
      infrastructure: 5,
      planetClass: PlanetClass.Benign,
      resources: ResourceRating.Abundant,
      buildings: @[],
      production: 100,
      underConstruction: none(econ_types.ConstructionProject),
      activeTerraforming: none(gamestate.TerraformProject),
      unassignedSquadrons: @[],
      unassignedSpaceLiftShips: @[],
      fighterSquadrons: @[],
      capacityViolation: CapacityViolation(),
      starbases: @[],
      spaceports: @[],
      shipyards: @[]
    )

    # Create fleet with spacelift ship
    let troopTransport = newSpaceLiftShip("troop1", ShipClass.TroopTransport, "H1", SystemId(1))

    result.fleets["F1"] = Fleet(
      id: "F1",
      owner: "H1",
      location: SystemId(1),
      squadrons: @[],
      spaceLiftShips: @[troopTransport],
      status: FleetStatus.Active,
      autoBalanceSquadrons: true
    )

    result

  test "LoadCargo - load marines":
    var state = createCargoTestState()

    let cmd = ZeroTurnCommand(
      houseId: "H1",
      commandType: ZeroTurnCommandType.LoadCargo,
      sourceFleetId: some("F1"),
      colonySystem: some(SystemId(1)),
      cargoType: some(CargoType.Marines),
      cargoQuantity: some(5)
    )

    let result = submitZeroTurnCommand(state, cmd)
    check result.success == true
    check result.cargoLoaded > 0

    # Colony marines should decrease
    check state.colonies[SystemId(1)].marines < 10

  test "UnloadCargo - unload marines":
    var state = createCargoTestState()

    # Load cargo first
    var ship = state.fleets["F1"].spaceLiftShips[0]
    ship.cargo = SpaceLiftCargo(cargoType: CargoType.Marines, quantity: 5)
    state.fleets["F1"].spaceLiftShips[0] = ship

    let cmd = ZeroTurnCommand(
      houseId: "H1",
      commandType: ZeroTurnCommandType.UnloadCargo,
      sourceFleetId: some("F1"),
      colonySystem: some(SystemId(1))
    )

    let result = submitZeroTurnCommand(state, cmd)
    check result.success == true
    check result.cargoUnloaded > 0

    # Colony should receive marines
    check state.colonies[SystemId(1)].marines > 10

suite "Zero-Turn Commands: TransferShips":

  proc createTransferTestState(): GameState =
    var result = GameState()
    result.turn = 1
    result.houses["H1"] = House(
      id: "H1",
      name: "House One",
      treasury: 10000,
      eliminated: false,
      techTree: res_types.initTechTree()
    )

    result.colonies[SystemId(1)] = Colony(
      systemId: SystemId(1),
      owner: "H1",
      population: 100_000_000,
      souls: 20000,
      marines: 10,
      infrastructure: 5,
      planetClass: PlanetClass.Benign,
      resources: ResourceRating.Abundant,
      buildings: @[],
      production: 100,
      underConstruction: none(econ_types.ConstructionProject),
      activeTerraforming: none(gamestate.TerraformProject),
      unassignedSquadrons: @[],
      unassignedSpaceLiftShips: @[],
      fighterSquadrons: @[],
      capacityViolation: CapacityViolation(),
      starbases: @[],
      spaceports: @[],
      shipyards: @[]
    )

    # Create source fleet with 2 squadrons (total 4 ships)
    let destroyer1 = newEnhancedShip(ShipClass.Destroyer)
    let destroyer2 = newEnhancedShip(ShipClass.Destroyer)
    var sq1 = newSquadron(destroyer1, id = "S1", owner = "H1", location = 1)
    discard sq1.addShip(destroyer2)

    let cruiser1 = newEnhancedShip(ShipClass.Cruiser)
    let cruiser2 = newEnhancedShip(ShipClass.Cruiser)
    var sq2 = newSquadron(cruiser1, id = "S2", owner = "H1", location = 1)
    discard sq2.addShip(cruiser2)

    result.fleets["F1"] = Fleet(
      id: "F1",
      owner: "H1",
      location: SystemId(1),
      squadrons: @[sq1, sq2],
      spaceLiftShips: @[],
      status: FleetStatus.Active,
      autoBalanceSquadrons: true
    )

    # Create target fleet (empty)
    result.fleets["F2"] = Fleet(
      id: "F2",
      owner: "H1",
      location: SystemId(1),
      squadrons: @[],
      spaceLiftShips: @[],
      status: FleetStatus.Active,
      autoBalanceSquadrons: true
    )

    result

  test "TransferShips - move one squadron between fleets":
    var state = createTransferTestState()

    # Transfer first squadron
    # NOTE: Selecting ANY ship in a squadron transfers the ENTIRE squadron
    let cmd = ZeroTurnCommand(
      houseId: "H1",
      commandType: ZeroTurnCommandType.TransferShips,
      sourceFleetId: some("F1"),
      targetFleetId: some("F2"),
      shipIndices: @[0]  # First squadron's flagship
    )

    let result = submitZeroTurnCommand(state, cmd)
    check result.success == true

    # Source fleet should still exist (second squadron with 2 ships remaining)
    check state.fleets.hasKey("F1")

    # Target fleet should have received first squadron
    check state.fleets["F2"].squadrons.len > 0

    # Total ships should be preserved (4 total: 2 in F1, 2 in F2)
    var totalShips = 0
    if state.fleets.hasKey("F1"):
      for sq in state.fleets["F1"].squadrons:
        totalShips += (1 + sq.ships.len)  # flagship + escorts
    for sq in state.fleets["F2"].squadrons:
      totalShips += (1 + sq.ships.len)  # flagship + escorts
    check totalShips == 4

  test "TransferShips - transfer all squadrons deletes source":
    var state = createTransferTestState()

    # Transfer both squadrons (all 4 ships)
    let cmd = ZeroTurnCommand(
      houseId: "H1",
      commandType: ZeroTurnCommandType.TransferShips,
      sourceFleetId: some("F1"),
      targetFleetId: some("F2"),
      shipIndices: @[0, 2]  # One ship from each squadron = both entire squadrons
    )

    let result = submitZeroTurnCommand(state, cmd)
    check result.success == true

    # Source fleet should be deleted (all squadrons transferred)
    check not state.fleets.hasKey("F1")

    # Target fleet should have all 4 ships (auto-balanced into squadrons)
    var totalShips = 0
    for sq in state.fleets["F2"].squadrons:
      totalShips += (1 + sq.ships.len)  # flagship + escorts
    check totalShips == 4

  test "TransferShips - fails if fleets at different locations":
    var state = createTransferTestState()

    # Move F2 to different system
    var f2 = state.fleets["F2"]
    f2.location = SystemId(999)
    state.fleets["F2"] = f2

    let cmd = ZeroTurnCommand(
      houseId: "H1",
      commandType: ZeroTurnCommandType.TransferShips,
      sourceFleetId: some("F1"),
      targetFleetId: some("F2"),
      shipIndices: @[0]
    )

    let result = submitZeroTurnCommand(state, cmd)
    check result.success == false
    check "same location" in result.error

suite "Zero-Turn Commands: Edge Cases":

  proc createEdgeCaseState(): GameState =
    var result = GameState()
    result.turn = 1
    result.houses["H1"] = House(
      id: "H1",
      name: "House One",
      treasury: 10000,
      eliminated: false,
      techTree: res_types.initTechTree()
    )
    result.houses["H2"] = House(
      id: "H2",
      name: "House Two",
      treasury: 10000,
      eliminated: false,
      techTree: res_types.initTechTree()
    )

    result.colonies[SystemId(1)] = Colony(
      systemId: SystemId(1),
      owner: "H1",
      population: 100_000_000,
      souls: 20000,
      marines: 10,
      infrastructure: 5,
      planetClass: PlanetClass.Benign,
      resources: ResourceRating.Abundant,
      buildings: @[],
      production: 100,
      underConstruction: none(econ_types.ConstructionProject),
      activeTerraforming: none(gamestate.TerraformProject),
      unassignedSquadrons: @[],
      unassignedSpaceLiftShips: @[],
      fighterSquadrons: @[],
      capacityViolation: CapacityViolation(),
      starbases: @[],
      spaceports: @[],
      shipyards: @[]
    )

    let destroyer1 = newEnhancedShip(ShipClass.Destroyer)
    var sq1 = newSquadron(destroyer1, id = "S1", owner = "H1", location = 1)

    result.fleets["F1"] = Fleet(
      id: "F1",
      owner: "H1",
      location: SystemId(1),
      squadrons: @[sq1],
      spaceLiftShips: @[],
      status: FleetStatus.Active,
      autoBalanceSquadrons: true
    )

    result

  test "DetachShips - cannot operate on enemy fleet":
    var state = createEdgeCaseState()

    # Create enemy fleet
    let cruiser = newEnhancedShip(ShipClass.Cruiser)
    var sq2 = newSquadron(cruiser, id = "S2", owner = "H2", location = 1)

    state.fleets["F2"] = Fleet(
      id: "F2",
      owner: "H2",  # Different owner
      location: SystemId(1),
      squadrons: @[sq2],
      spaceLiftShips: @[],
      status: FleetStatus.Active,
      autoBalanceSquadrons: true
    )

    let cmd = ZeroTurnCommand(
      houseId: "H1",
      commandType: ZeroTurnCommandType.DetachShips,
      sourceFleetId: some("F2"),  # Enemy fleet
      shipIndices: @[0]
    )

    let result = submitZeroTurnCommand(state, cmd)
    check result.success == false
    check "not owned by" in result.error

  test "MergeFleets - preserves fleet orders on target":
    var state = createEdgeCaseState()

    # Create second fleet
    let cruiser = newEnhancedShip(ShipClass.Cruiser)
    var sq2 = newSquadron(cruiser, id = "S2", owner = "H1", location = 1)

    state.fleets["F2"] = Fleet(
      id: "F2",
      owner: "H1",
      location: SystemId(1),
      squadrons: @[sq2],
      spaceLiftShips: @[],
      status: FleetStatus.Active,
      autoBalanceSquadrons: true
    )

    # Add orders to both fleets
    state.fleetOrders["F1"] = FleetOrder(
      fleetId: "F1",
      orderType: FleetOrderType.Hold,
      targetSystem: none(SystemId),
      targetFleet: none(FleetId),
      priority: 0
    )

    state.fleetOrders["F2"] = FleetOrder(
      fleetId: "F2",
      orderType: FleetOrderType.Hold,
      targetSystem: none(SystemId),
      targetFleet: none(FleetId),
      priority: 0
    )

    let cmd = ZeroTurnCommand(
      houseId: "H1",
      commandType: ZeroTurnCommandType.MergeFleets,
      sourceFleetId: some("F1"),
      targetFleetId: some("F2")
    )

    let result = submitZeroTurnCommand(state, cmd)
    check result.success == true

    # F1 orders should be deleted
    check not state.fleetOrders.hasKey("F1")

    # F2 orders should be preserved
    check state.fleetOrders.hasKey("F2")
    check state.fleetOrders["F2"].orderType == FleetOrderType.Hold

  test "LoadCargo - respects cargo capacity":
    var state = createEdgeCaseState()

    # Create fleet with small capacity transport
    let smallTransport = newSpaceLiftShip("small1", ShipClass.TroopTransport, "H1", SystemId(1))

    state.fleets["F1"] = Fleet(
      id: "F1",
      owner: "H1",
      location: SystemId(1),
      squadrons: @[],
      spaceLiftShips: @[smallTransport],
      status: FleetStatus.Active,
      autoBalanceSquadrons: true
    )

    # Try to load more than capacity (capacity is 5 for TroopTransport)
    let cmd = ZeroTurnCommand(
      houseId: "H1",
      commandType: ZeroTurnCommandType.LoadCargo,
      sourceFleetId: some("F1"),
      colonySystem: some(SystemId(1)),
      cargoType: some(CargoType.Marines),
      cargoQuantity: some(100)  # Request way more than capacity
    )

    let result = submitZeroTurnCommand(state, cmd)
    check result.success == true
    # Should only load up to capacity (5)
    check result.cargoLoaded <= 5

  test "DetachShips - invalid ship indices rejected":
    var state = createEdgeCaseState()

    let cmd = ZeroTurnCommand(
      houseId: "H1",
      commandType: ZeroTurnCommandType.DetachShips,
      sourceFleetId: some("F1"),
      shipIndices: @[999]  # Invalid index
    )

    let result = submitZeroTurnCommand(state, cmd)
    check result.success == false
    check "Invalid ship index" in result.error or "out of range" in result.error

echo "Zero-Turn Commands Test Suite Complete"
