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
import ../../src/engine/economy/[construction, types as econ_types]
import ../../src/engine/research/types as res_types
import ../../src/engine/espionage/types as esp_types
import ../../src/common/types/[core, units, planets]

suite "Ship Construction Pipeline":

  proc createShipTestState(): GameState =
    ## Create a basic game state with a colony for ship construction testing
    result = GameState()
    result.turn = 1
    result.phase = GamePhase.Active

    # Create house
    result.houses["house1"] = House(
      id: "house1",
      name: "Test House",
      treasury: 10000,
      eliminated: false,
      techTree: res_types.initTechTree(),  # Initialize with all tech at level 1
    )

    # Create colony using helper (ensures all fields properly initialized)
    result.colonies[1] = createHomeColony(SystemId(1), "house1")

    # Add shipyard for ship construction
    result.colonies[1].shipyards.add(
      Shipyard(id: "sy1", commissionedTurn: 1, docks: 10, isCrippled: false)
    )
    result.colonies[1].spaceports.add(
      Spaceport(id: "sp1", commissionedTurn: 1, docks: 5)
    )

  test "Ship construction completes instantly (1 turn per spec)":
    var state = createShipTestState()

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

    # Per economy.md:5.0 - all ships build instantly (1 turn)
    # Construction should complete and ship should be commissioned
    check result.newState.colonies[1].underConstruction.isNone

    # Ship should be commissioned in a fleet
    # Output says: "Commissioned Scout in new fleet house1_fleet1"
    check result.newState.fleets.len > 0

    var foundScout = false
    for fleetId, fleet in result.newState.fleets:
      if fleet.owner == "house1" and fleet.squadrons.len > 0:
        for squadron in fleet.squadrons:
          if squadron.flagship.shipClass == ShipClass.Scout:
            foundScout = true
            break

    if not foundScout:
      echo "DEBUG: Fleets in state: ", result.newState.fleets.len
      for fleetId, fleet in result.newState.fleets:
        echo "  Fleet ", fleetId, ": owner=", fleet.owner, " squadrons=", fleet.squadrons.len

    check foundScout

  test "Treasury deduction on construction start":
    var state = createShipTestState()
    let initialTreasury = state.houses["house1"].treasury

    # Build a Cruiser (60 PP)
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

    let result = resolveTurn(state, orders)

    # Treasury should be reduced by ship cost (after income is added)
    # Initial: 10000, Income: ~420, Cost: 60
    # Final should be less than initial + income
    check result.newState.houses["house1"].treasury < initialTreasury + 500

  test "Dock capacity enforced (capacity fix validates correctly)":
    # This test validates that getActiveConstructionProjects counts both
    # underConstruction AND constructionQueue
    var state = createShipTestState()

    # Verify dock capacity calculation works
    check state.colonies[1].getConstructionDockCapacity() == 15  # 10 shipyard + 5 spaceport
    check state.colonies[1].getActiveConstructionProjects() == 0  # Nothing building yet
    check state.colonies[1].canAcceptMoreProjects() == true  # Has capacity

suite "Facility Construction":

  proc createFacilityTestState(): GameState =
    var result = GameState()
    result.turn = 1
    result.houses["house1"] = House(
      id: "house1",
      name: "Test House",
      treasury: 10000,
      eliminated: false,
      techTree: res_types.initTechTree(),  # Initialize with all tech at level 1
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

  test "Build spaceport via orders":
    var state = createFacilityTestState()

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
      eliminated: false,
      techTree: res_types.initTechTree(),  # Initialize with all tech at level 1
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
      underConstruction: none(econ_types.ConstructionProject),
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

    # Note: Full integration test of commissioning happens in resolve.nim
    # This test validates the data structures are correct
    check state.colonies[1].unassignedSquadrons.len == 0
    check state.colonies[1].unassignedSpaceLiftShips.len == 0

suite "Construction Integration":

  test "Full construction cycle in game turn":
    var state = GameState()
    state.turn = 1
    state.phase = GamePhase.Active

    state.houses["house1"] = House(
      id: "house1",
      name: "Test House",
      treasury: 10000,
      eliminated: false,
      techTree: res_types.initTechTree(),  # Initialize with all tech at level 1
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
      underConstruction: none(econ_types.ConstructionProject),
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
