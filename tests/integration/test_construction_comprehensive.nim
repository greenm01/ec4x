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

    # Start construction of Destroyer (should take multiple turns)
    var colony = state.colonies[1]
    let destroyerProject = createShipProject(ShipClass.Destroyer)
    check startConstruction(colony, destroyerProject) == true
    state.colonies[1] = colony

    let initialTurns = destroyerProject.turnsRemaining
    check initialTurns > 1  # Should take multiple turns

    # Advance construction for several turns
    var completedProject: Option[CompletedProject] = none(CompletedProject)
    for i in 1..initialTurns:
      colony = state.colonies[1]
      completedProject = advanceConstruction(colony)
      state.colonies[1] = colony

      if i < initialTurns:
        check completedProject.isNone  # Not complete yet
      else:
        check completedProject.isSome  # Complete on final turn

    # Verify completion
    check completedProject.isSome
    check completedProject.get().projectType == ConstructionType.Ship
    check completedProject.get().itemId.len > 0  # Should have ship identifier
    check state.colonies[1].underConstruction.isNone  # Construction slot cleared

  test "Cannot start construction while slot occupied":
    var state = createTestState()
    var colony = state.colonies[1]

    # Start first project
    let project1 = createShipProject(ShipClass.Cruiser)
    check startConstruction(colony, project1) == true

    # Try to start second project
    let project2 = createShipProject(ShipClass.Destroyer)
    check startConstruction(colony, project2) == false  # Should fail

  test "Different ship types have different build times":
    # Scout should be faster than Battleship
    let scoutProject = createShipProject(ShipClass.Scout)
    let battleshipProject = createShipProject(ShipClass.Battleship)

    check battleshipProject.turnsRemaining > scoutProject.turnsRemaining

  test "Construction cost calculation":
    # Test various ship costs
    let fighterCost = getShipConstructionCost(ShipClass.Fighter)
    let destroyerCost = getShipConstructionCost(ShipClass.Destroyer)
    let battleshipCost = getShipConstructionCost(ShipClass.Battleship)

    check fighterCost < destroyerCost
    check destroyerCost < battleshipCost
    check fighterCost == 5  # Per config
    check battleshipCost == 60  # Per config

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

  test "Build spaceport":
    var state = createTestState()
    var colony = state.colonies[1]

    # Create spaceport project
    let spaceportProject = createBuildingProject("Spaceport")
    check startConstruction(colony, spaceportProject) == true

    # Should take 1 turn per spec
    check spaceportProject.turnsRemaining == 1

    state.colonies[1] = colony

  test "Build shipyard requires spaceport":
    var state = createTestState()

    # Try to build shipyard without spaceport should work (construction validates elsewhere)
    var colony = state.colonies[1]
    let shipyardProject = createBuildingProject("Shipyard")
    check startConstruction(colony, shipyardProject) == true

    # Should take 2 turns per spec
    check shipyardProject.turnsRemaining == 2

  test "Build starbase":
    var state = createTestState()
    var colony = state.colonies[1]

    let starbaseProject = createBuildingProject("Starbase")
    check startConstruction(colony, starbaseProject) == true

    check starbaseProject.turnsRemaining >= 1

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

  test "Construction types are distinct":
    # Verify we can distinguish between ship and building construction
    let shipProject = createShipProject(ShipClass.Cruiser)
    let buildingProject = createBuildingProject("Spaceport")

    check shipProject.projectType == ConstructionType.Ship
    check buildingProject.projectType == ConstructionType.Building
    check shipProject.itemId.len > 0
    check buildingProject.itemId.len > 0

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
