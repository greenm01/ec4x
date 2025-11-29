## Automated Seek Home Tests
##
## Tests automatic fleet retreat behavior when destinations become hostile
## Per resolve.nim:1900-1943 - fleets automatically seek home when:
## - ETAC colonization missions encounter hostile destinations
## - Guard/blockade orders where system becomes enemy-controlled
## - Patrol orders where patrol zone becomes hostile
##
## Covers:
## - Automated retreat for ETAC colonization missions
## - Automated retreat for guard orders
## - Automated retreat for blockade orders
## - Automated retreat for patrol orders
## - Fallback to Hold when no safe destination exists
## - Closest colony selection for retreat destination
## - Event generation for automated retreats

import std/[unittest, tables, options]
import ../../src/engine/[gamestate, orders, resolve, fleet, spacelift, squadron, starmap]
import ../../src/engine/research/types as res_types
import ../../src/engine/espionage/types as esp_types
import ../../src/engine/diplomacy/types as dip_types
import ../../src/engine/economy/types as econ_types
import ../../src/common/types/[core, units, planets, diplomacy]
import ../../src/common/[hex, system]

## Helper to create a simple linear starmap for testing
proc createTestStarMap(numSystems: int): StarMap =
  ## Create a simple linear starmap with systems 1..numSystems
  ## All systems connected in a line with Major lanes
  result = StarMap(
    systems: initTable[uint, System](),
    lanes: @[],
    adjacency: initTable[uint, seq[uint]](),
    playerCount: 2,
    numRings: uint32(numSystems),
    hubId: 0
  )

  # Add systems
  for i in 1..numSystems:
    result.systems[uint(i)] = System(
      id: uint(i),
      coords: hex(i, 0),
      ring: uint32(i),
      player: none(uint)
    )

  # Connect systems linearly: 1-2-3-4-5...
  for i in 1..<numSystems:
    let source = uint(i)
    let dest = uint(i + 1)

    # Add lane
    result.lanes.add(JumpLane(
      source: source,
      destination: dest,
      laneType: LaneType.Major
    ))

    # Update adjacency
    if source notin result.adjacency:
      result.adjacency[source] = @[]
    if dest notin result.adjacency:
      result.adjacency[dest] = @[]
    result.adjacency[source].add(dest)
    result.adjacency[dest].add(source)

suite "Automated Seek Home - ETAC Missions":

  proc createETACTestState(): GameState =
    ## Create state with ETAC mission and multiple colonies
    var state = GameState()
    state.turn = 1
    state.phase = GamePhase.Active

    # Initialize starmap with systems 1, 2, 3 connected linearly
    state.starMap = createTestStarMap(3)

    # House 1 - Has ETAC heading to system 3
    state.houses["house1"] = House(
      id: "house1",
      name: "Colonizing House",
      treasury: 5000,
      eliminated: false,
      techTree: res_types.initTechTree(),  # Initialize with all tech at level 1
      diplomaticRelations: initDiplomaticRelations()
    )
    state.houses["house1"].diplomaticRelations.setDiplomaticState("house2", DiplomaticState.Enemy, 1)

    # House 2 - Enemy house
    state.houses["house2"] = House(
      id: "house2",
      name: "Enemy House",
      treasury: 10000,
      eliminated: false,
      techTree: res_types.initTechTree(),  # Initialize with all tech at level 1
      diplomaticRelations: initDiplomaticRelations()
    )
    state.houses["house2"].diplomaticRelations.setDiplomaticState("house1", DiplomaticState.Enemy, 1)

    # House 1 homeworld (system 1)
    state.colonies[1] = Colony(
      systemId: 1,
      owner: "house1",
      population: 100,
      souls: 100_000_000,
      infrastructure: 5,
      planetClass: PlanetClass.Eden,
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
      shipyards: @[],
      planetaryShieldLevel: 0,
      groundBatteries: 0,
      armies: 5,
      marines: 0,
      blockaded: false,
      blockadedBy: @[],
      blockadeTurns: 0
    )

    # House 1 secondary colony (system 2) - closer retreat option
    state.colonies[2] = Colony(
      systemId: 2,
      owner: "house1",
      population: 50,
      souls: 50_000_000,
      infrastructure: 3,
      planetClass: PlanetClass.Lush,
      resources: ResourceRating.Rich,
      buildings: @[],
      production: 50,
      underConstruction: none(econ_types.ConstructionProject),
      activeTerraforming: none(gamestate.TerraformProject),
      unassignedSquadrons: @[],
      unassignedSpaceLiftShips: @[],
      fighterSquadrons: @[],
      capacityViolation: CapacityViolation(),
      starbases: @[],
      spaceports: @[],
      shipyards: @[],
      planetaryShieldLevel: 0,
      groundBatteries: 0,
      armies: 2,
      marines: 0,
      blockaded: false,
      blockadedBy: @[],
      blockadeTurns: 0
    )

    # System 3 - Now enemy controlled (was colonization target)
    state.colonies[3] = Colony(
      systemId: 3,
      owner: "house2",  # Enemy took it!
      population: 30,
      souls: 30_000_000,
      infrastructure: 2,
      planetClass: PlanetClass.Benign,
      resources: ResourceRating.Abundant,
      buildings: @[],
      production: 30,
      underConstruction: none(econ_types.ConstructionProject),
      activeTerraforming: none(gamestate.TerraformProject),
      unassignedSquadrons: @[],
      unassignedSpaceLiftShips: @[],
      fighterSquadrons: @[],
      capacityViolation: CapacityViolation(),
      starbases: @[],
      spaceports: @[],
      shipyards: @[],
      planetaryShieldLevel: 0,
      groundBatteries: 0,
      armies: 1,
      marines: 0,
      blockaded: false,
      blockadedBy: @[],
      blockadeTurns: 0
    )

    # ETAC fleet en route to system 3 (currently at system 2)
    let etac = SpaceLiftShip(
      id: "etac1",
      shipClass: ShipClass.ETAC,
      owner: "house1",
      location: 2,
      isCrippled: false,
      cargo: SpaceLiftCargo(
        cargoType: CargoType.Colonists,
        quantity: 10,  # 10 PU colonists
        capacity: 10
      )
    )

    state.fleets["fleet1"] = Fleet(
      id: "fleet1",
      owner: "house1",
      location: 2,  # At system 2
      squadrons: @[],
      spaceLiftShips: @[etac],
      status: FleetStatus.Active
    )

    state

  test "ETAC aborts colonization when destination becomes hostile":
    var state = createETACTestState()

    # Issue colonization order to now-hostile system 3
    let colonizeOrder = FleetOrder(
      fleetId: "fleet1",
      orderType: FleetOrderType.Colonize,
      targetSystem: some(SystemId(3))
    )

    var packet = OrderPacket(
      houseId: "house1",
      turn: 1,
      buildOrders: @[],
      fleetOrders: @[colonizeOrder],
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
    state = result.newState

    # Fleet should have auto-retreated, NOT colonized enemy system
    check state.fleets["fleet1"].location != 3
    # Should still have colonists (didn't attempt colonization)
    check state.fleets["fleet1"].spaceLiftShips[0].cargo.quantity == 10

  test "ETAC retreats to closest owned colony":
    var state = createETACTestState()

    # Fleet at system 2, should retreat to system 2 (already there) or system 1
    let colonizeOrder = FleetOrder(
      fleetId: "fleet1",
      orderType: FleetOrderType.Colonize,
      targetSystem: some(SystemId(3))
    )

    var orders = initTable[HouseId, OrderPacket]()
    orders["house1"] = OrderPacket(
      houseId: "house1",
      turn: 1,
      buildOrders: @[],
      fleetOrders: @[colonizeOrder],
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

    let result = resolveTurn(state, orders)
    state = result.newState

    # Should remain at or return to owned territory
    let fleet = state.fleets["fleet1"]
    check fleet.location in [SystemId(1), SystemId(2)]  # Should be at one of house1's colonies

suite "Automated Seek Home - Guard Orders":

  proc createGuardTestState(): GameState =
    ## Create state with fleet on guard duty
    var state = GameState()
    state.turn = 1
    state.phase = GamePhase.Active

    # Initialize starmap
    state.starMap = createTestStarMap(3)

    state.houses["house1"] = House(
      id: "house1",
      name: "Defending House",
      treasury: 5000,
      eliminated: false,
      techTree: res_types.initTechTree(),  # Initialize with all tech at level 1
      diplomaticRelations: initDiplomaticRelations()
    )
    state.houses["house1"].diplomaticRelations.setDiplomaticState("house2", DiplomaticState.Enemy, 1)

    state.houses["house2"] = House(
      id: "house2",
      name: "Conquering House",
      treasury: 10000,
      eliminated: false,
      techTree: res_types.initTechTree(),  # Initialize with all tech at level 1
      diplomaticRelations: initDiplomaticRelations()
    )
    state.houses["house2"].diplomaticRelations.setDiplomaticState("house1", DiplomaticState.Enemy, 1)

    # House 1 homeworld (system 1)
    state.colonies[1] = Colony(
      systemId: 1,
      owner: "house1",
      population: 100,
      souls: 100_000_000,
      infrastructure: 5,
      planetClass: PlanetClass.Eden,
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
      shipyards: @[],
      planetaryShieldLevel: 0,
      groundBatteries: 0,
      armies: 5,
      marines: 0,
      blockaded: false,
      blockadedBy: @[],
      blockadeTurns: 0
    )

    # System 2 - CONQUERED by enemy during previous turn
    state.colonies[2] = Colony(
      systemId: 2,
      owner: "house2",  # Now enemy controlled!
      population: 50,
      souls: 50_000_000,
      infrastructure: 3,
      planetClass: PlanetClass.Lush,
      resources: ResourceRating.Rich,
      buildings: @[],
      production: 50,
      underConstruction: none(econ_types.ConstructionProject),
      activeTerraforming: none(gamestate.TerraformProject),
      unassignedSquadrons: @[],
      unassignedSpaceLiftShips: @[],
      fighterSquadrons: @[],
      capacityViolation: CapacityViolation(),
      starbases: @[],
      spaceports: @[],
      shipyards: @[],
      planetaryShieldLevel: 0,
      groundBatteries: 0,
      armies: 3,
      marines: 0,
      blockaded: false,
      blockadedBy: @[],
      blockadeTurns: 0
    )

    # Guard fleet stranded at system 2 (now enemy territory)
    let cruiser = newEnhancedShip(ShipClass.LightCruiser)
    let squadron = newSquadron(
      flagship = cruiser,
      id = "sq1",
      owner = "house1",
      location = 2
    )

    state.fleets["fleet1"] = Fleet(
      id: "fleet1",
      owner: "house1",
      location: 2,  # Stranded in now-hostile system
      squadrons: @[squadron],
      spaceLiftShips: @[],
      status: FleetStatus.Active
    )

    state

  test "Guard order aborted when system conquered by enemy":
    var state = createGuardTestState()

    # Fleet ordered to guard planet that was just conquered
    let guardOrder = FleetOrder(
      fleetId: "fleet1",
      orderType: FleetOrderType.GuardPlanet,
      targetSystem: some(SystemId(2))
    )

    var orders = initTable[HouseId, OrderPacket]()
    orders["house1"] = OrderPacket(
      houseId: "house1",
      turn: 1,
      buildOrders: @[],
      fleetOrders: @[guardOrder],
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

    let result = resolveTurn(state, orders)
    state = result.newState

    # Fleet should have retreated to homeworld
    check state.fleets["fleet1"].location == SystemId(1)

  test "Starbase guard order aborted when system lost":
    var state = createGuardTestState()

    let guardOrder = FleetOrder(
      fleetId: "fleet1",
      orderType: FleetOrderType.GuardStarbase,
      targetSystem: some(SystemId(2))
    )

    var orders = initTable[HouseId, OrderPacket]()
    orders["house1"] = OrderPacket(
      houseId: "house1",
      turn: 1,
      buildOrders: @[],
      fleetOrders: @[guardOrder],
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

    let result = resolveTurn(state, orders)
    state = result.newState

    # Should retreat home
    check state.fleets["fleet1"].location == SystemId(1)

suite "Automated Seek Home - Blockade Orders":

  proc createBlockadeTestState(): GameState =
    ## Create state with blockade fleet at conquered system
    var state = GameState()
    state.turn = 1
    state.phase = GamePhase.Active

    # Initialize starmap
    state.starMap = createTestStarMap(3)

    state.houses["house1"] = House(
      id: "house1",
      name: "Blockading House",
      treasury: 5000,
      eliminated: false,
      techTree: res_types.initTechTree(),  # Initialize with all tech at level 1
      diplomaticRelations: initDiplomaticRelations()
    )
    state.houses["house1"].diplomaticRelations.setDiplomaticState("house2", DiplomaticState.Enemy, 1)

    state.houses["house2"] = House(
      id: "house2",
      name: "Liberating House",
      treasury: 10000,
      eliminated: false,
      techTree: res_types.initTechTree(),  # Initialize with all tech at level 1
      diplomaticRelations: initDiplomaticRelations()
    )
    state.houses["house2"].diplomaticRelations.setDiplomaticState("house1", DiplomaticState.Enemy, 1)

    # House 1 homeworld
    state.colonies[1] = Colony(
      systemId: 1,
      owner: "house1",
      population: 100,
      souls: 100_000_000,
      infrastructure: 5,
      planetClass: PlanetClass.Eden,
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
      shipyards: @[],
      planetaryShieldLevel: 0,
      groundBatteries: 0,
      armies: 5,
      marines: 0,
      blockaded: false,
      blockadedBy: @[],
      blockadeTurns: 0
    )

    # System 2 - Liberated by house2
    state.colonies[2] = Colony(
      systemId: 2,
      owner: "house2",  # Liberated!
      population: 40,
      souls: 40_000_000,
      infrastructure: 2,
      planetClass: PlanetClass.Benign,
      resources: ResourceRating.Abundant,
      buildings: @[],
      production: 40,
      underConstruction: none(econ_types.ConstructionProject),
      activeTerraforming: none(gamestate.TerraformProject),
      unassignedSquadrons: @[],
      unassignedSpaceLiftShips: @[],
      fighterSquadrons: @[],
      capacityViolation: CapacityViolation(),
      starbases: @[],
      spaceports: @[],
      shipyards: @[],
      planetaryShieldLevel: 0,
      groundBatteries: 0,
      armies: 2,
      marines: 0,
      blockaded: false,
      blockadedBy: @[],
      blockadeTurns: 0
    )

    # Blockade fleet now stranded
    let destroyer = newEnhancedShip(ShipClass.Destroyer)
    let squadron = newSquadron(
      flagship = destroyer,
      id = "sq1",
      owner = "house1",
      location = 2
    )

    state.fleets["fleet1"] = Fleet(
      id: "fleet1",
      owner: "house1",
      location: 2,
      squadrons: @[squadron],
      spaceLiftShips: @[],
      status: FleetStatus.Active
    )

    state

  test "Blockade order aborted when planet changes ownership":
    var state = createBlockadeTestState()

    let blockadeOrder = FleetOrder(
      fleetId: "fleet1",
      orderType: FleetOrderType.BlockadePlanet,
      targetSystem: some(SystemId(2))
    )

    var orders = initTable[HouseId, OrderPacket]()
    orders["house1"] = OrderPacket(
      houseId: "house1",
      turn: 1,
      buildOrders: @[],
      fleetOrders: @[blockadeOrder],
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

    let result = resolveTurn(state, orders)
    state = result.newState

    # Should retreat home
    check state.fleets["fleet1"].location == SystemId(1)

suite "Automated Seek Home - Patrol Orders":

  proc createPatrolTestState(): GameState =
    ## Create state with patrol fleet in conquered territory
    var state = GameState()
    state.turn = 1
    state.phase = GamePhase.Active

    # Initialize starmap
    state.starMap = createTestStarMap(3)

    state.houses["house1"] = House(
      id: "house1",
      name: "Patrol House",
      treasury: 5000,
      eliminated: false,
      techTree: res_types.initTechTree(),  # Initialize with all tech at level 1
      diplomaticRelations: initDiplomaticRelations()
    )
    state.houses["house1"].diplomaticRelations.setDiplomaticState("house2", DiplomaticState.Enemy, 1)

    state.houses["house2"] = House(
      id: "house2",
      name: "Invading House",
      treasury: 10000,
      eliminated: false,
      techTree: res_types.initTechTree(),  # Initialize with all tech at level 1
      diplomaticRelations: initDiplomaticRelations()
    )
    state.houses["house2"].diplomaticRelations.setDiplomaticState("house1", DiplomaticState.Enemy, 1)

    # House 1 homeworld
    state.colonies[1] = Colony(
      systemId: 1,
      owner: "house1",
      population: 100,
      souls: 100_000_000,
      infrastructure: 5,
      planetClass: PlanetClass.Eden,
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
      shipyards: @[],
      planetaryShieldLevel: 0,
      groundBatteries: 0,
      armies: 5,
      marines: 0,
      blockaded: false,
      blockadedBy: @[],
      blockadeTurns: 0
    )

    # System 2 - Conquered during patrol
    state.colonies[2] = Colony(
      systemId: 2,
      owner: "house2",  # Enemy conquered!
      population: 50,
      souls: 50_000_000,
      infrastructure: 3,
      planetClass: PlanetClass.Lush,
      resources: ResourceRating.Rich,
      buildings: @[],
      production: 50,
      underConstruction: none(econ_types.ConstructionProject),
      activeTerraforming: none(gamestate.TerraformProject),
      unassignedSquadrons: @[],
      unassignedSpaceLiftShips: @[],
      fighterSquadrons: @[],
      capacityViolation: CapacityViolation(),
      starbases: @[],
      spaceports: @[],
      shipyards: @[],
      planetaryShieldLevel: 0,
      groundBatteries: 0,
      armies: 3,
      marines: 0,
      blockaded: false,
      blockadedBy: @[],
      blockadeTurns: 0
    )

    # Patrol fleet
    let scout = newEnhancedShip(ShipClass.Scout)
    let squadron = newSquadron(
      flagship = scout,
      id = "sq1",
      owner = "house1",
      location = 2
    )

    state.fleets["fleet1"] = Fleet(
      id: "fleet1",
      owner: "house1",
      location: 2,
      squadrons: @[squadron],
      spaceLiftShips: @[],
      status: FleetStatus.Active
    )

    state

  test "Patrol aborted when patrol zone becomes enemy territory":
    var state = createPatrolTestState()

    let patrolOrder = FleetOrder(
      fleetId: "fleet1",
      orderType: FleetOrderType.Patrol,
      targetSystem: some(SystemId(2))
    )

    var orders = initTable[HouseId, OrderPacket]()
    orders["house1"] = OrderPacket(
      houseId: "house1",
      turn: 1,
      buildOrders: @[],
      fleetOrders: @[patrolOrder],
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

    let result = resolveTurn(state, orders)
    state = result.newState

    # Should retreat to safe territory
    check state.fleets["fleet1"].location == SystemId(1)

suite "Automated Seek Home - No Safe Destination":

  test "Fleet holds position when no owned colonies exist":
    var state = GameState()
    state.turn = 1
    state.phase = GamePhase.Active

    # Initialize starmap
    state.starMap = createTestStarMap(5)

    state.houses["house1"] = House(
      id: "house1",
      name: "Desperate House",
      treasury: 100,
      eliminated: false,
      techTree: res_types.initTechTree(),  # Initialize with all tech at level 1
      diplomaticRelations: initDiplomaticRelations()
    )
    state.houses["house1"].diplomaticRelations.setDiplomaticState("house2", DiplomaticState.Enemy, 1)

    state.houses["house2"] = House(
      id: "house2",
      name: "Dominant House",
      treasury: 10000,
      eliminated: false,
      techTree: res_types.initTechTree(),  # Initialize with all tech at level 1
      diplomaticRelations: initDiplomaticRelations()
    )
    state.houses["house2"].diplomaticRelations.setDiplomaticState("house1", DiplomaticState.Enemy, 1)

    # Only enemy colony exists
    state.colonies[1] = Colony(
      systemId: 1,
      owner: "house2",
      population: 100,
      souls: 100_000_000,
      infrastructure: 5,
      planetClass: PlanetClass.Eden,
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
      shipyards: @[],
      planetaryShieldLevel: 0,
      groundBatteries: 0,
      armies: 5,
      marines: 0,
      blockaded: false,
      blockadedBy: @[],
      blockadeTurns: 0
    )

    # Stranded fleet with no home
    let destroyer = newEnhancedShip(ShipClass.Destroyer)
    let squadron = newSquadron(
      flagship = destroyer,
      id = "sq1",
      owner = "house1",
      location = 5  # Deep space
    )

    state.fleets["fleet1"] = Fleet(
      id: "fleet1",
      owner: "house1",
      location: 5,
      squadrons: @[squadron],
      spaceLiftShips: @[],
      status: FleetStatus.Active
    )

    # Try to patrol hostile territory
    let patrolOrder = FleetOrder(
      fleetId: "fleet1",
      orderType: FleetOrderType.Patrol,
      targetSystem: some(SystemId(1))
    )

    var orders = initTable[HouseId, OrderPacket]()
    orders["house1"] = OrderPacket(
      houseId: "house1",
      turn: 1,
      buildOrders: @[],
      fleetOrders: @[patrolOrder],
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

    let result = resolveTurn(state, orders)
    state = result.newState

    # Should remain in place (no safe destination)
    check state.fleets["fleet1"].location == SystemId(5)

suite "Automated Seek Home - Multiple Fleets":

  test "Multiple fleets retreat simultaneously":
    var state = GameState()
    state.turn = 1
    state.phase = GamePhase.Active

    # Initialize starmap
    state.starMap = createTestStarMap(3)

    state.houses["house1"] = House(
      id: "house1",
      name: "Retreating House",
      treasury: 5000,
      eliminated: false,
      techTree: res_types.initTechTree(),  # Initialize with all tech at level 1
      diplomaticRelations: initDiplomaticRelations()
    )
    state.houses["house1"].diplomaticRelations.setDiplomaticState("house2", DiplomaticState.Enemy, 1)

    state.houses["house2"] = House(
      id: "house2",
      name: "Victorious House",
      treasury: 10000,
      eliminated: false,
      techTree: res_types.initTechTree(),  # Initialize with all tech at level 1
      diplomaticRelations: initDiplomaticRelations()
    )
    state.houses["house2"].diplomaticRelations.setDiplomaticState("house1", DiplomaticState.Enemy, 1)

    # Homeworld
    state.colonies[1] = Colony(
      systemId: 1,
      owner: "house1",
      population: 100,
      souls: 100_000_000,
      infrastructure: 5,
      planetClass: PlanetClass.Eden,
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
      shipyards: @[],
      planetaryShieldLevel: 0,
      groundBatteries: 0,
      armies: 5,
      marines: 0,
      blockaded: false,
      blockadedBy: @[],
      blockadeTurns: 0
    )

    # Lost colony
    state.colonies[2] = Colony(
      systemId: 2,
      owner: "house2",
      population: 50,
      souls: 50_000_000,
      infrastructure: 3,
      planetClass: PlanetClass.Lush,
      resources: ResourceRating.Rich,
      buildings: @[],
      production: 50,
      underConstruction: none(econ_types.ConstructionProject),
      activeTerraforming: none(gamestate.TerraformProject),
      unassignedSquadrons: @[],
      unassignedSpaceLiftShips: @[],
      fighterSquadrons: @[],
      capacityViolation: CapacityViolation(),
      starbases: @[],
      spaceports: @[],
      shipyards: @[],
      planetaryShieldLevel: 0,
      groundBatteries: 0,
      armies: 3,
      marines: 0,
      blockaded: false,
      blockadedBy: @[],
      blockadeTurns: 0
    )

    # Fleet 1 - Guard duty
    let cruiser1 = newEnhancedShip(ShipClass.LightCruiser)
    let sq1 = newSquadron(cruiser1, "sq1", "house1", 2)
    state.fleets["fleet1"] = Fleet(
      id: "fleet1",
      owner: "house1",
      location: 2,
      squadrons: @[sq1],
      spaceLiftShips: @[],
      status: FleetStatus.Active
    )

    # Fleet 2 - Blockade duty
    let destroyer = newEnhancedShip(ShipClass.Destroyer)
    let sq2 = newSquadron(destroyer, "sq2", "house1", 2)
    state.fleets["fleet2"] = Fleet(
      id: "fleet2",
      owner: "house1",
      location: 2,
      squadrons: @[sq2],
      spaceLiftShips: @[],
      status: FleetStatus.Active
    )

    # Fleet 3 - Patrol duty
    let scout = newEnhancedShip(ShipClass.Scout)
    let sq3 = newSquadron(scout, "sq3", "house1", 2)
    state.fleets["fleet3"] = Fleet(
      id: "fleet3",
      owner: "house1",
      location: 2,
      squadrons: @[sq3],
      spaceLiftShips: @[],
      status: FleetStatus.Active
    )

    # All fleets ordered to continue missions at now-hostile system
    let guardOrder = FleetOrder(
      fleetId: "fleet1",
      orderType: FleetOrderType.GuardPlanet,
      targetSystem: some(SystemId(2))
    )

    let blockadeOrder = FleetOrder(
      fleetId: "fleet2",
      orderType: FleetOrderType.BlockadePlanet,
      targetSystem: some(SystemId(2))
    )

    let patrolOrder = FleetOrder(
      fleetId: "fleet3",
      orderType: FleetOrderType.Patrol,
      targetSystem: some(SystemId(2))
    )

    var orders = initTable[HouseId, OrderPacket]()
    orders["house1"] = OrderPacket(
      houseId: "house1",
      turn: 1,
      buildOrders: @[],
      fleetOrders: @[guardOrder, blockadeOrder, patrolOrder],
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

    let result = resolveTurn(state, orders)
    state = result.newState

    # All fleets should retreat home
    check state.fleets["fleet1"].location == SystemId(1)
    check state.fleets["fleet2"].location == SystemId(1)
    check state.fleets["fleet3"].location == SystemId(1)

when isMainModule:
  echo "╔════════════════════════════════════════════════╗"
  echo "║  Automated Seek Home Tests                    ║"
  echo "╚════════════════════════════════════════════════╝"
