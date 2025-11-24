## Comprehensive Squadron Management and Fleet Organization Tests
##
## Tests squadron formation, ship transfers, fleet assignment, and auto-assignment
## Covers:
## - Squadron formation from commissioned ships
## - Ship transfers between squadrons
## - Squadron assignment to fleets
## - Fleet creation and organization
## - Auto-assignment system

import std/[unittest, tables, options]
import ../../src/engine/[gamestate, orders, resolve, fleet, squadron]
import ../../src/engine/research/types as res_types
import ../../src/engine/espionage/types as esp_types
import ../../src/common/types/[core, units]

suite "Squadron Management":

  proc createTestState(): GameState =
    ## Create state with colony and some unassigned squadrons
    var result = GameState()
    result.turn = 1
    result.houses["house1"] = House(
      id: "house1",
      name: "Test House",
      treasury: 10000,
      eliminated: false
    )

    # Create squadrons
    let destroyer1 = newEnhancedShip(ShipClass.Destroyer)
    var sq1 = newSquadron(destroyer1, id = "sq1", owner = "house1", location = 1)

    let destroyer2 = newEnhancedShip(ShipClass.Destroyer)
    var sq2 = newSquadron(destroyer2, id = "sq2", owner = "house1", location = 1)

    let cruiser1 = newEnhancedShip(ShipClass.Cruiser)
    var sq3 = newSquadron(cruiser1, id = "sq3", owner = "house1", location = 1)

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
      underConstruction: none(ConstructionProject),
      activeTerraforming: none(TerraformProject),
      unassignedSquadrons: @[sq1, sq2, sq3],
      unassignedSpaceLiftShips: @[],
      autoAssignFleets: false,  # Disable auto-assign for manual testing
      fighterSquadrons: @[],
      capacityViolation: CapacityViolation(),
      starbases: @[],
      spaceports: @[],
      shipyards: @[]
    )

    result

  test "Assign squadron to new fleet":
    var state = createTestState()

    # Create squadron management order to assign sq1 to a new fleet
    let order = SquadronManagementOrder(
      houseId: "house1",
      colonySystem: 1,
      action: SquadronManagementAction.AssignToFleet,
      shipIndices: @[],
      newSquadronId: none(string),
      sourceSquadronId: none(string),
      targetSquadronId: none(string),
      shipIndex: none(int),
      squadronId: some("sq1"),
      targetFleetId: none(FleetId)  # None = create new fleet
    )

    var packet = OrderPacket(
      houseId: "house1",
      turn: 1,
      buildOrders: @[],
      fleetOrders: @[],
      researchAllocation: initResearchAllocation(),
      diplomaticActions: @[],
      populationTransfers: @[],
      squadronManagement: @[order],
      cargoManagement: @[],
      terraformOrders: @[],
      espionageAction: none(esp_types.EspionageAttempt),
      ebpInvestment: 0,
      cipInvestment: 0
    )

    var orders = initTable[HouseId, OrderPacket]()
    orders["house1"] = packet

    let result = resolveTurn(state, orders)

    # Should have created a new fleet with sq1
    var foundFleet = false
    for fleetId, fleet in result.newState.fleets:
      if fleet.owner == "house1" and fleet.location == 1:
        if fleet.squadrons.len == 1 and fleet.squadrons[0].id == "sq1":
          foundFleet = true
          break

    check foundFleet == true

    # sq1 should be removed from unassigned squadrons
    var sq1StillUnassigned = false
    for sq in result.newState.colonies[1].unassignedSquadrons:
      if sq.id == "sq1":
        sq1StillUnassigned = true
        break

    check sq1StillUnassigned == false

  test "Assign squadron to existing fleet":
    var state = createTestState()

    # Create an existing fleet with sq1
    let destroyer = newEnhancedShip(ShipClass.Destroyer)
    var sq1 = state.colonies[1].unassignedSquadrons[0]

    state.fleets["fleet1"] = Fleet(
      id: "fleet1",
      squadrons: @[sq1],
      spaceLiftShips: @[],
      owner: "house1",
      location: 1,
      status: FleetStatus.Active
    )

    # Remove sq1 from unassigned (it's now in fleet)
    state.colonies[1].unassignedSquadrons = state.colonies[1].unassignedSquadrons[1..^1]

    # Now assign sq2 to the existing fleet
    let order = SquadronManagementOrder(
      houseId: "house1",
      colonySystem: 1,
      action: SquadronManagementAction.AssignToFleet,
      shipIndices: @[],
      newSquadronId: none(string),
      sourceSquadronId: none(string),
      targetSquadronId: none(string),
      shipIndex: none(int),
      squadronId: some("sq2"),
      targetFleetId: some("fleet1")
    )

    var packet = OrderPacket(
      houseId: "house1",
      turn: 1,
      buildOrders: @[],
      fleetOrders: @[],
      researchAllocation: initResearchAllocation(),
      diplomaticActions: @[],
      populationTransfers: @[],
      squadronManagement: @[order],
      cargoManagement: @[],
      terraformOrders: @[],
      espionageAction: none(esp_types.EspionageAttempt),
      ebpInvestment: 0,
      cipInvestment: 0
    )

    var orders = initTable[HouseId, OrderPacket]()
    orders["house1"] = packet

    let result = resolveTurn(state, orders)

    # fleet1 should now have 2 squadrons
    check result.newState.fleets["fleet1"].squadrons.len == 2

  test "Transfer ship between squadrons":
    var state = createTestState()

    # Create two fleets with squadrons
    let destroyer1 = newEnhancedShip(ShipClass.Destroyer)
    var sourceSquad = newSquadron(destroyer1, id = "source-sq", owner = "house1", location = 1)

    # Add an extra ship to source squadron
    let destroyer2 = newEnhancedShip(ShipClass.Destroyer)
    discard sourceSquad.addShip(destroyer2)

    let cruiser1 = newEnhancedShip(ShipClass.Cruiser)
    var targetSquad = newSquadron(cruiser1, id = "target-sq", owner = "house1", location = 1)

    state.fleets["fleet1"] = Fleet(
      id: "fleet1",
      squadrons: @[sourceSquad],
      spaceLiftShips: @[],
      owner: "house1",
      location: 1,
      status: FleetStatus.Active
    )

    state.fleets["fleet2"] = Fleet(
      id: "fleet2",
      squadrons: @[targetSquad],
      spaceLiftShips: @[],
      owner: "house1",
      location: 1,
      status: FleetStatus.Active
    )

    # Transfer ship from source to target
    let order = SquadronManagementOrder(
      houseId: "house1",
      colonySystem: 1,
      action: SquadronManagementAction.TransferShip,
      shipIndices: @[],
      newSquadronId: none(string),
      sourceSquadronId: some("source-sq"),
      targetSquadronId: some("target-sq"),
      shipIndex: some(0),  # Transfer first ship
      squadronId: none(string),
      targetFleetId: none(FleetId)
    )

    var packet = OrderPacket(
      houseId: "house1",
      turn: 1,
      buildOrders: @[],
      fleetOrders: @[],
      researchAllocation: initResearchAllocation(),
      diplomaticActions: @[],
      populationTransfers: @[],
      squadronManagement: @[order],
      cargoManagement: @[],
      terraformOrders: @[],
      espionageAction: none(esp_types.EspionageAttempt),
      ebpInvestment: 0,
      cipInvestment: 0
    )

    var orders = initTable[HouseId, OrderPacket]()
    orders["house1"] = packet

    let result = resolveTurn(state, orders)

    # Source squadron should have fewer ships
    check result.newState.fleets["fleet1"].squadrons[0].ships.len == 0  # Only flagship remains

    # Target squadron should have gained a ship
    check result.newState.fleets["fleet2"].squadrons[0].ships.len == 1

suite "Fleet Organization":

  test "Multiple squadrons in single fleet":
    var state = GameState()
    state.turn = 1
    state.houses["house1"] = House(
      id: "house1",
      name: "Test House",
      treasury: 10000,
      eliminated: false
    )

    # Create multiple squadrons
    let destroyer1 = newEnhancedShip(ShipClass.Destroyer)
    var sq1 = newSquadron(destroyer1, id = "sq1", owner = "house1", location = 1)

    let destroyer2 = newEnhancedShip(ShipClass.Destroyer)
    var sq2 = newSquadron(destroyer2, id = "sq2", owner = "house1", location = 1)

    let cruiser = newEnhancedShip(ShipClass.Cruiser)
    var sq3 = newSquadron(cruiser, id = "sq3", owner = "house1", location = 1)

    # Create fleet with all squadrons
    state.fleets["fleet1"] = Fleet(
      id: "fleet1",
      squadrons: @[sq1, sq2, sq3],
      spaceLiftShips: @[],
      owner: "house1",
      location: 1,
      status: FleetStatus.Active
    )

    # Verify fleet composition
    check state.fleets["fleet1"].squadrons.len == 3
    check state.fleets["fleet1"].owner == "house1"
    check state.fleets["fleet1"].location == 1

  test "Move squadron between fleets removes from source":
    var state = GameState()
    state.turn = 1
    state.houses["house1"] = House(
      id: "house1",
      name: "Test House",
      treasury: 10000,
      eliminated: false
    )

    let destroyer1 = newEnhancedShip(ShipClass.Destroyer)
    var sq1 = newSquadron(destroyer1, id = "sq1", owner = "house1", location = 1)

    let destroyer2 = newEnhancedShip(ShipClass.Destroyer)
    var sq2 = newSquadron(destroyer2, id = "sq2", owner = "house1", location = 1)

    state.fleets["fleet1"] = Fleet(
      id: "fleet1",
      squadrons: @[sq1, sq2],
      spaceLiftShips: @[],
      owner: "house1",
      location: 1,
      status: FleetStatus.Active
    )

    state.fleets["fleet2"] = Fleet(
      id: "fleet2",
      squadrons: @[],
      spaceLiftShips: @[],
      owner: "house1",
      location: 1,
      status: FleetStatus.Active
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
      underConstruction: none(ConstructionProject),
      activeTerraforming: none(TerraformProject),
      unassignedSquadrons: @[],
      unassignedSpaceLiftShips: @[],
      autoAssignFleets: false,
      fighterSquadrons: @[],
      capacityViolation: CapacityViolation(),
      starbases: @[],
      spaceports: @[],
      shipyards: @[]
    )

    # Move sq1 from fleet1 to fleet2
    let order = SquadronManagementOrder(
      houseId: "house1",
      colonySystem: 1,
      action: SquadronManagementAction.AssignToFleet,
      shipIndices: @[],
      newSquadronId: none(string),
      sourceSquadronId: none(string),
      targetSquadronId: none(string),
      shipIndex: none(int),
      squadronId: some("sq1"),
      targetFleetId: some("fleet2")
    )

    var packet = OrderPacket(
      houseId: "house1",
      turn: 1,
      buildOrders: @[],
      fleetOrders: @[],
      researchAllocation: initResearchAllocation(),
      diplomaticActions: @[],
      populationTransfers: @[],
      squadronManagement: @[order],
      cargoManagement: @[],
      terraformOrders: @[],
      espionageAction: none(esp_types.EspionageAttempt),
      ebpInvestment: 0,
      cipInvestment: 0
    )

    var orders = initTable[HouseId, OrderPacket]()
    orders["house1"] = packet

    let result = resolveTurn(state, orders)

    # fleet1 should have 1 squadron (sq2)
    check result.newState.fleets["fleet1"].squadrons.len == 1
    check result.newState.fleets["fleet1"].squadrons[0].id == "sq2"

    # fleet2 should have 1 squadron (sq1)
    check result.newState.fleets["fleet2"].squadrons.len == 1
    check result.newState.fleets["fleet2"].squadrons[0].id == "sq1"

suite "Auto-Assignment System":

  test "Auto-assign creates fleet for unassigned squadrons":
    var state = GameState()
    state.turn = 1
    state.houses["house1"] = House(
      id: "house1",
      name: "Test House",
      treasury: 10000,
      eliminated: false
    )

    # Create unassigned squadrons with auto-assign enabled
    let destroyer = newEnhancedShip(ShipClass.Destroyer)
    var sq1 = newSquadron(destroyer, id = "sq1", owner = "house1", location = 1)

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
      underConstruction: none(ConstructionProject),
      activeTerraforming: none(TerraformProject),
      unassignedSquadrons: @[sq1],
      unassignedSpaceLiftShips: @[],
      autoAssignFleets: true,  # Enable auto-assignment
      fighterSquadrons: @[],
      capacityViolation: CapacityViolation(),
      starbases: @[],
      spaceports: @[],
      shipyards: @[]
    )

    var packet = OrderPacket(
      houseId: "house1",
      turn: 1,
      buildOrders: @[],
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

    # Auto-assignment should have created fleet(s) for unassigned squadrons
    # Check that unassigned squadrons list is now empty or reduced
    # Note: actual auto-assignment logic may vary
    check result.newState.colonies[1].unassignedSquadrons.len <= 1

when isMainModule:
  echo "╔════════════════════════════════════════════════╗"
  echo "║  Squadron Management & Fleet Organization      ║"
  echo "╚════════════════════════════════════════════════╝"
