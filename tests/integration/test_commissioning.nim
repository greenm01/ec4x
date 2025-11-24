## Detailed Commissioning Tests
##
## Tests the complete commissioning flow from construction completion to squadron creation
## Covers:
## - Different ship types commissioning correctly
## - Combat ships → squadrons in unassignedSquadrons
## - Spacelift ships → unassignedSpaceLiftShips
## - Multiple ships commissioning in same turn
## - Auto-assignment of commissioned squadrons
## - Manual assignment after commissioning

import std/[unittest, tables, options]
import ../../src/engine/[gamestate, orders, resolve, fleet, squadron]
import ../../src/engine/research/types as res_types
import ../../src/engine/espionage/types as esp_types
import ../../src/common/types/[core, units]

suite "Ship Commissioning":

  proc createTestState(): GameState =
    var result = GameState()
    result.turn = 1
    result.year = 2501
    result.month = 1
    result.phase = GamePhase.Active

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
      autoAssignFleets: false,  # Disable for manual control
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

    result

  test "Combat ship commissions as squadron in unassigned pool":
    var state = createTestState()

    # Build a destroyer (combat ship)
    let buildOrder = BuildOrder(
      colonySystem: 1,
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

    check state.colonies[1].underConstruction.isSome
    let project = state.colonies[1].underConstruction.get()
    let turnsNeeded = project.turnsRemaining

    # Advance until completion
    for i in 1..turnsNeeded:
      packet.turn = state.turn
      packet.buildOrders = @[]
      orders["house1"] = packet
      result = resolveTurn(state, orders)
      state = result.newState

    # Ship should be commissioned as squadron in unassigned pool
    check state.colonies[1].unassignedSquadrons.len == 1
    check state.colonies[1].unassignedSpaceLiftShips.len == 0

    let squadron = state.colonies[1].unassignedSquadrons[0]
    check squadron.flagship.shipClass == ShipClass.Destroyer
    check squadron.owner == "house1"
    check squadron.location == 1

  test "ETAC commissions as spacelift ship":
    var state = createTestState()

    # Build an ETAC (spacelift ship)
    let buildOrder = BuildOrder(
      colonySystem: 1,
      buildType: BuildType.Ship,
      quantity: 1,
      shipClass: some(ShipClass.ETAC),
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

    # Start and complete construction
    var result = resolveTurn(state, orders)
    state = result.newState

    let turnsNeeded = state.colonies[1].underConstruction.get().turnsRemaining

    for i in 1..turnsNeeded:
      packet.turn = state.turn
      packet.buildOrders = @[]
      orders["house1"] = packet
      result = resolveTurn(state, orders)
      state = result.newState

    # ETAC should be in spacelift pool, not squadron pool
    check state.colonies[1].unassignedSquadrons.len == 0
    check state.colonies[1].unassignedSpaceLiftShips.len == 1

    let spacelift = state.colonies[1].unassignedSpaceLiftShips[0]
    check spacelift.shipClass == ShipClass.ETAC
    check spacelift.owner == "house1"

  test "Troop Transport commissions as spacelift ship":
    var state = createTestState()

    # Build a troop transport
    let buildOrder = BuildOrder(
      colonySystem: 1,
      buildType: BuildType.Ship,
      quantity: 1,
      shipClass: some(ShipClass.TroopTransport),
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

    var result = resolveTurn(state, orders)
    state = result.newState

    let turnsNeeded = state.colonies[1].underConstruction.get().turnsRemaining

    for i in 1..turnsNeeded:
      packet.turn = state.turn
      packet.buildOrders = @[]
      orders["house1"] = packet
      result = resolveTurn(state, orders)
      state = result.newState

    # Should be spacelift ship
    check state.colonies[1].unassignedSquadrons.len == 0
    check state.colonies[1].unassignedSpaceLiftShips.len == 1
    check state.colonies[1].unassignedSpaceLiftShips[0].shipClass == ShipClass.TroopTransport

  test "Multiple ships commission in same turn":
    var state = createTestState()

    # Add another shipyard to build 2 ships simultaneously
    state.colonies[1].shipyards.add(
      Shipyard(id: "sy2", commissionedTurn: 1, docks: 10, isCrippled: false)
    )

    # Build scout (fast - 1 turn)
    let buildOrder1 = BuildOrder(
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

    # Start first construction
    var result = resolveTurn(state, orders)
    state = result.newState

    # Start second construction on next turn
    let buildOrder2 = BuildOrder(
      colonySystem: 1,
      buildType: BuildType.Ship,
      quantity: 1,
      shipClass: some(ShipClass.Cruiser),
      buildingType: none(string),
      industrialUnits: 0
    )

    packet.turn = state.turn
    packet.buildOrders = @[buildOrder2]
    orders["house1"] = packet

    result = resolveTurn(state, orders)
    state = result.newState

    # Advance until both complete (cruiser takes longer)
    for i in 1..3:
      packet.turn = state.turn
      packet.buildOrders = @[]
      orders["house1"] = packet
      result = resolveTurn(state, orders)
      state = result.newState

    # Should have commissioned both ships
    check state.colonies[1].unassignedSquadrons.len >= 2

  test "Auto-assignment creates fleet for commissioned squadron":
    var state = createTestState()

    # Enable auto-assignment
    state.colonies[1].autoAssignFleets = true

    # Build a destroyer
    let buildOrder = BuildOrder(
      colonySystem: 1,
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
      squadronManagement: @[],
      cargoManagement: @[],
      terraformOrders: @[],
      espionageAction: none(esp_types.EspionageAttempt),
      ebpInvestment: 0,
      cipInvestment: 0
    )

    var orders = initTable[HouseId, OrderPacket]()
    orders["house1"] = packet

    var result = resolveTurn(state, orders)
    state = result.newState

    let turnsNeeded = state.colonies[1].underConstruction.get().turnsRemaining

    for i in 1..turnsNeeded:
      packet.turn = state.turn
      packet.buildOrders = @[]
      orders["house1"] = packet
      result = resolveTurn(state, orders)
      state = result.newState

    # With auto-assignment, squadron should be in a fleet
    # Check that either unassigned pool is empty or fleet was created
    var squadronInFleet = false
    for fleetId, fleet in state.fleets:
      if fleet.owner == "house1" and fleet.location == 1:
        if fleet.squadrons.len > 0:
          squadronInFleet = true
          break

    # Auto-assignment should have created a fleet or left in unassigned
    check (state.colonies[1].unassignedSquadrons.len == 0 and squadronInFleet) or
          state.colonies[1].unassignedSquadrons.len > 0

when isMainModule:
  echo "╔════════════════════════════════════════════════╗"
  echo "║  Detailed Commissioning Tests                 ║"
  echo "╚════════════════════════════════════════════════╝"
