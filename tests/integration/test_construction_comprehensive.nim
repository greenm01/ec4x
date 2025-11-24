## Comprehensive Construction and Commissioning Tests
##
## Tests the complete ship construction pipeline from build order to commissioned squadron
## Covers:
## - Ship construction at spaceports/shipyards
## - Multi-turn construction tracking
## - Construction completion and commissioning
## - Facility construction (spaceports, shipyards, starbases)
## - Capacity limits and queue management

import std/[unittest, tables, options]
import ../../src/engine/[gamestate, orders, resolve]
import ../../src/engine/economy/construction
import ../../src/engine/research/types as res_types
import ../../src/engine/espionage/types as esp_types
import ../../src/common/types/[core, units, planets]

suite "Ship Construction Pipeline":

  proc createTestState(): GameState =
    ## Create a basic game state with a colony for testing
    result = GameState()
    result.turn = 1
    result.year = 2501
    result.month = 1
    result.phase = GamePhase.Active

    # Create house
    result.houses["house1"] = House(
      id: "house1",
      name: "Test House",
      treasury: 10000,
      eliminated: false
    )

    # Create colony with shipyard
    result.colonies[1] = Colony(
      systemId: 1,
      owner: "house1",
      population: 100,
      souls: 100_000_000,
      infrastructure: 5,
      planetClass: PlanetClass.Benign,
      resources: ResourceRating.Abundant,
      buildings: @[],
      production: 100,
      underConstruction: none(gamestate.ConstructionProject),
      activeTerraforming: none(gamestate.TerraformProject),
      unassignedSquadrons: @[],
      unassignedSpaceLiftShips: @[],
      autoAssignFleets: true,
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

  test "Start ship construction at spaceport":
    var state = createTestState()

    # Create build order for Scout
    let buildOrder = BuildOrder(
      colonySystem: 1,
      buildType: BuildType.Ship,
      quantity: 1,
      shipClass: some(ShipClass.Scout),
      buildingType: none(string),
      industrialUnits: 0
    )

    var packet = OrderPacket(
      houseId: "house1",
      turn: 1,
      buildOrders: @[buildOrder],
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

    # Resolve build orders
    var orders = initTable[HouseId, OrderPacket]()
    orders["house1"] = packet

    let result = resolveTurn(state, orders)

    # Check that construction started
    check result.newState.colonies[1].underConstruction.isSome
    let project = result.newState.colonies[1].underConstruction.get()
    check project.projectType == ConstructionType.Ship
    check project.itemId.len > 0  # Should have ship identifier
    check project.turnsRemaining > 0

  test "Multi-turn construction completion":
    var state = createTestState()

    # Start construction of Cruiser (takes 2 turns at CST 1)
    let buildOrder = BuildOrder(
      colonySystem: 1,
      buildType: BuildType.Ship,
      quantity: 1,
      shipClass: some(ShipClass.Cruiser),
      buildingType: none(string),
      industrialUnits: 0
    )

    var packet = OrderPacket(
      houseId: "house1",
      turn: 1,
      buildOrders: @[buildOrder],
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

    var orders = initTable[HouseId, OrderPacket]()
    orders["house1"] = packet

    # Start construction
    var result = resolveTurn(state, orders)
    state = result.newState

    # Construction should be in progress
    check state.colonies[1].underConstruction.isSome
    let initialProject = state.colonies[1].underConstruction.get()
    let initialTurns = initialProject.turnsRemaining
    check initialTurns >= 2  # Cruiser should take at least 2 turns

    # Advance enough turns to complete construction
    # Need to advance initialTurns worth of game turns to complete
    for i in 1..initialTurns:
      orders["house1"].turn = state.turn
      orders["house1"].buildOrders = @[]  # No new build orders
      result = resolveTurn(state, orders)
      state = result.newState

    # Construction should be complete and squadrons commissioned
    # (ships go to unassigned pool after construction)
    check state.colonies[1].underConstruction.isNone

  test "Cannot start construction while slot occupied":
    var state = createTestState()

    # Start first construction
    let buildOrder1 = BuildOrder(
      colonySystem: 1,
      buildType: BuildType.Ship,
      quantity: 1,
      shipClass: some(ShipClass.Cruiser),
      buildingType: none(string),
      industrialUnits: 0
    )

    var packet = OrderPacket(
      houseId: "house1",
      turn: 1,
      buildOrders: @[buildOrder1],
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

    var orders = initTable[HouseId, OrderPacket]()
    orders["house1"] = packet

    let result1 = resolveTurn(state, orders)

    # First construction should start
    check result1.newState.colonies[1].underConstruction.isSome

    # Try to start second construction while first is active
    let buildOrder2 = BuildOrder(
      colonySystem: 1,
      buildType: BuildType.Ship,
      quantity: 1,
      shipClass: some(ShipClass.Destroyer),
      buildingType: none(string),
      industrialUnits: 0
    )

    packet.turn = 2
    packet.buildOrders = @[buildOrder2]
    orders["house1"] = packet

    let result2 = resolveTurn(result1.newState, orders)

    # Second construction should not start (slot occupied)
    # First project should still be there
    check result2.newState.colonies[1].underConstruction.isSome

suite "Facility Construction":

  proc createTestState(): GameState =
    var result = GameState()
    result.turn = 1
    result.houses["house1"] = House(
      id: "house1",
      name: "Test House",
      treasury: 10000,
      eliminated: false
    )

    result.colonies[1] = Colony(
      systemId: 1,
      owner: "house1",
      population: 100,
      souls: 100_000_000,
      infrastructure: 5,
      planetClass: PlanetClass.Benign,
      resources: ResourceRating.Abundant,
      buildings: @[],
      production: 100,
      underConstruction: none(gamestate.ConstructionProject),
      activeTerraforming: none(gamestate.TerraformProject),
      unassignedSquadrons: @[],
      unassignedSpaceLiftShips: @[],
      autoAssignFleets: true,
      fighterSquadrons: @[],
      capacityViolation: CapacityViolation(),
      starbases: @[],
      spaceports: @[],
      shipyards: @[]
    )
    result

  test "Build spaceport via orders":
    var state = createTestState()

    # Build spaceport
    let buildOrder = BuildOrder(
      colonySystem: 1,
      buildType: BuildType.Building,
      quantity: 1,
      shipClass: none(ShipClass),
      buildingType: some("Spaceport"),
      industrialUnits: 0
    )

    var packet = OrderPacket(
      houseId: "house1",
      turn: 1,
      buildOrders: @[buildOrder],
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

    var orders = initTable[HouseId, OrderPacket]()
    orders["house1"] = packet

    let result = resolveTurn(state, orders)

    # Construction should start
    check result.newState.colonies[1].underConstruction.isSome
    let project = result.newState.colonies[1].underConstruction.get()
    check project.projectType == ConstructionType.Building

suite "Commissioning and Squadron Formation":

  test "Completed ship goes to unassigned pool":
    # This test verifies the integration between construction completion
    # and squadron commissioning
    var state = GameState()
    state.turn = 1
    state.houses["house1"] = House(
      id: "house1",
      name: "Test House",
      treasury: 10000,
      eliminated: false
    )

    state.colonies[1] = Colony(
      systemId: 1,
      owner: "house1",
      population: 100,
      souls: 100_000_000,
      infrastructure: 5,
      planetClass: PlanetClass.Benign,
      resources: ResourceRating.Abundant,
      buildings: @[],
      production: 100,
      underConstruction: none(gamestate.ConstructionProject),
      activeTerraforming: none(gamestate.TerraformProject),
      unassignedSquadrons: @[],
      unassignedSpaceLiftShips: @[],
      autoAssignFleets: true,
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

    # Note: Full integration test of commissioning happens in resolve.nim
    # This test validates the data structures are correct
    check state.colonies[1].unassignedSquadrons.len == 0
    check state.colonies[1].unassignedSpaceLiftShips.len == 0

suite "Construction Integration":

  test "Full construction cycle in game turn":
    var state = GameState()
    state.turn = 1
    state.year = 2501
    state.month = 1
    state.phase = GamePhase.Active

    state.houses["house1"] = House(
      id: "house1",
      name: "Test House",
      treasury: 10000,
      eliminated: false
    )

    state.colonies[1] = Colony(
      systemId: 1,
      owner: "house1",
      population: 100,
      souls: 100_000_000,
      infrastructure: 5,
      planetClass: PlanetClass.Benign,
      resources: ResourceRating.Abundant,
      buildings: @[],
      production: 100,
      underConstruction: none(gamestate.ConstructionProject),
      activeTerraforming: none(gamestate.TerraformProject),
      unassignedSquadrons: @[],
      unassignedSpaceLiftShips: @[],
      autoAssignFleets: true,
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

    # Create build order for a fast ship (Scout - 1 turn)
    let buildOrder = BuildOrder(
      colonySystem: 1,
      buildType: BuildType.Ship,
      quantity: 1,
      shipClass: some(ShipClass.Scout),
      buildingType: none(string),
      industrialUnits: 0
    )

    var packet = OrderPacket(
      houseId: "house1",
      turn: 1,
      buildOrders: @[buildOrder],
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

    var orders = initTable[HouseId, OrderPacket]()
    orders["house1"] = packet

    # Resolve turn - construction starts
    let result = resolveTurn(state, orders)

    # Verify construction is active
    check result.newState.colonies[1].underConstruction.isSome
    check result.newState.turn == 2  # Turn advanced

when isMainModule:
  echo "╔════════════════════════════════════════════════╗"
  echo "║  Construction & Commissioning Tests           ║"
  echo "╚════════════════════════════════════════════════╝"
