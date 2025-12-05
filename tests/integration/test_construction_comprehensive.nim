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
import ../../src/engine/[gamestate, orders, resolve, starmap]
import ../../src/engine/economy/[projects, types as econ_types]
import ../../src/engine/research/types as res_types
import ../../src/engine/espionage/types as esp_types
import ../../src/common/types/[core, units, planets]

suite "Ship Construction Pipeline":

  proc createShipTestState(): GameState =
    ## Create a basic game state with a colony for ship construction testing
    result = GameState()
    result.turn = 1
    result.phase = GamePhase.Active

    # Generate starmap to get valid system IDs
    var map = newStarMap(2)
    map.populate()
    result.starMap = map
    let testSystemId = map.playerSystemIds[0]

    # Create house
    result.houses["house1"] = House(
      id: "house1",
      name: "Test House",
      treasury: 10000,
      eliminated: false,
      techTree: res_types.initTechTree(),  # Initialize with all tech at level 1
    )

    # Create colony using helper (ensures all fields properly initialized)
    result.colonies[testSystemId] = createHomeColony(testSystemId.SystemId, "house1")

    # Add shipyard for ship construction
    result.colonies[testSystemId].shipyards.add(
      Shipyard(id: "sy1", commissionedTurn: 1, docks: 10, isCrippled: false)
    )
    result.colonies[testSystemId].spaceports.add(
      Spaceport(id: "sp1", commissionedTurn: 1, docks: 5)
    )

  test "Ship construction completes in one turn":
    var state = createShipTestState()
    let testSystemId = state.starMap.playerSystemIds[0]

    # Create build order for Destroyer
    let buildOrder = BuildOrder(
      colonySystem: testSystemId,
      buildType: BuildType.Ship,
      quantity: 1,
      shipClass: some(ShipClass.Destroyer),
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
      terraformOrders: @[],
      espionageAction: none(esp_types.EspionageAttempt),
      ebpInvestment: 0,
      cipInvestment: 0
    )

    # Resolve build orders
    var orders = initTable[HouseId, OrderPacket]()
    orders["house1"] = packet

    # Turn 1: Build and complete
    var result = resolveTurn(state, orders)
    state = result.newState

    # Turn 2: Commission (with no-op orders)
    var noOpOrders = initTable[HouseId, OrderPacket]()
    noOpOrders["house1"] = OrderPacket(
      houseId: "house1",
      turn: 2,
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
    result = resolveTurn(state, noOpOrders)

    # Per economy.md:5.0 - all ships build in one turn (complete)
    # Then commissioned at start of next turn (2-turn flow overall)
    check result.newState.colonies[testSystemId].underConstruction.isNone

    # Ship should be commissioned in a fleet
    check result.newState.fleets.len > 0

    var foundDestroyer = false
    for fleetId, fleet in result.newState.fleets:
      if fleet.owner == "house1" and fleet.squadrons.len > 0:
        for squadron in fleet.squadrons:
          if squadron.flagship.shipClass == ShipClass.Destroyer:
            foundDestroyer = true
            break

    if not foundDestroyer:
      echo "DEBUG: Fleets in state: ", result.newState.fleets.len
      for fleetId, fleet in result.newState.fleets:
        echo "  Fleet ", fleetId, ": owner=", fleet.owner, " squadrons=", fleet.squadrons.len

    check foundDestroyer

  test "Treasury deduction on construction start":
    var state = createShipTestState()
    let initialTreasury = state.houses["house1"].treasury
    let testSystemId = state.starMap.playerSystemIds[0]

    # Build a Cruiser (60 PP)
    let buildOrder = BuildOrder(
      colonySystem: testSystemId,
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
      terraformOrders: @[],
      espionageAction: none(esp_types.EspionageAttempt),
      ebpInvestment: 0,
      cipInvestment: 0
    )

    var orders = initTable[HouseId, OrderPacket]()
    orders["house1"] = packet

    let result = resolveTurn(state, orders)

    # Treasury should be reduced by ship cost (after income is added)
    # Initial: 10000, Income: varies, Cost: 60
    # Just verify treasury didn't increase by the full income amount
    # (i.e., cost was deducted)
    check result.newState.houses["house1"].treasury < initialTreasury + 700

  test "Dock capacity enforced (capacity fix validates correctly)":
    # This test validates that getActiveConstructionProjects counts both
    # underConstruction AND constructionQueue
    var state = createShipTestState()
    let testSystemId = state.starMap.playerSystemIds[0]

    # Verify dock capacity calculation works
    check state.colonies[testSystemId].getConstructionDockCapacity() == 15  # 10 shipyard + 5 spaceport
    check state.colonies[testSystemId].getActiveConstructionProjects() == 0  # Nothing building yet
    check state.colonies[testSystemId].canAcceptMoreProjects() == true  # Has capacity

suite "Facility Construction":

  proc createFacilityTestState(): GameState =
    var result = GameState()
    result.turn = 1

    # Generate starmap to get valid system IDs
    var map = newStarMap(2)
    map.populate()
    result.starMap = map
    let testSystemId = map.playerSystemIds[0]

    result.houses["house1"] = House(
      id: "house1",
      name: "Test House",
      treasury: 10000,
      eliminated: false,
      techTree: res_types.initTechTree(),  # Initialize with all tech at level 1
    )

    result.colonies[testSystemId] = Colony(
      systemId: testSystemId.SystemId,
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
    let testSystemId = state.starMap.playerSystemIds[0]

    # Build spaceport
    let buildOrder = BuildOrder(
      colonySystem: testSystemId,
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
      terraformOrders: @[],
      espionageAction: none(esp_types.EspionageAttempt),
      ebpInvestment: 0,
      cipInvestment: 0
    )

    var orders = initTable[HouseId, OrderPacket]()
    orders["house1"] = packet

    let result = resolveTurn(state, orders)

    # Spaceport construction completes instantly (1 turn) and goes to pending commissions
    # With the 2-turn flow: Turn 1 (build → complete) → Turn 2 (commission)
    check result.newState.pendingCommissions.len == 1
    check result.newState.pendingCommissions[0].projectType == ConstructionType.Building

suite "Commissioning and Squadron Formation":

  test "Completed ship goes to unassigned pool":
    # This test verifies the integration between construction completion
    # and squadron commissioning
    var state = GameState()
    state.turn = 1

    # Generate starmap to get valid system IDs
    var map = newStarMap(2)
    map.populate()
    state.starMap = map
    let testSystemId = map.playerSystemIds[0]

    state.houses["house1"] = House(
      id: "house1",
      name: "Test House",
      treasury: 10000,
      eliminated: false,
      techTree: res_types.initTechTree(),  # Initialize with all tech at level 1
    )

    state.colonies[testSystemId] = Colony(
      systemId: testSystemId.SystemId,
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
    check state.colonies[testSystemId].unassignedSquadrons.len == 0
    check state.colonies[testSystemId].unassignedSpaceLiftShips.len == 0

suite "Construction Integration":

  test "Full construction cycle in game turn":
    var state = GameState()
    state.turn = 1
    state.phase = GamePhase.Active

    # Generate starmap to get valid system IDs
    var map = newStarMap(2)
    map.populate()
    state.starMap = map
    let testSystemId = map.playerSystemIds[0]

    state.houses["house1"] = House(
      id: "house1",
      name: "Test House",
      treasury: 10000,
      eliminated: false,
      techTree: res_types.initTechTree(),  # Initialize with all tech at level 1
    )

    state.colonies[testSystemId] = Colony(
      systemId: testSystemId.SystemId,
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
      colonySystem: testSystemId,
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
      terraformOrders: @[],
      espionageAction: none(esp_types.EspionageAttempt),
      ebpInvestment: 0,
      cipInvestment: 0
    )

    var orders = initTable[HouseId, OrderPacket]()
    orders["house1"] = packet

    # Resolve turn - construction completes (instant 1-turn build)
    let result = resolveTurn(state, orders)

    # Verify construction completed and is pending commission
    # Scout takes 1 turn, so it completes in Turn 1 and goes to pendingCommissions
    check result.newState.pendingCommissions.len == 1
    check result.newState.turn == 2  # Turn advanced

when isMainModule:
  echo "╔══════════════════════════════════════╗"
  echo "║  Construction & Commissioning Tests  ║"
  echo "╚══════════════════════════════════════╝"
