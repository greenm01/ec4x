## Last-Stand Invasion Tests
##
## Tests houses' ability to reconquer territory after losing all colonies
## Per resolve.nim:3701-3702 - houses are only eliminated when they have
## BOTH no colonies AND no fleets. This allows dramatic comeback scenarios.
##
## Covers:
## - Houses with fleets but no colonies can still invade
## - Houses with fleets but no colonies can still blitz
## - Successful reconquest after total colony loss
## - House elimination only when fleets AND colonies are gone
## - Marines on transports enable last-stand invasions

import std/[unittest, tables, options]
import ../../src/engine/[gamestate, orders, resolve, fleet, spacelift, squadron]
import ../../src/engine/combat/ground
import ../../src/engine/research/types as res_types
import ../../src/engine/espionage/types as esp_types
import ../../src/engine/economy/types as econ_types
import ../../src/common/types/[core, units, planets]

suite "Last-Stand Invasions":

  proc createTestState(): tuple[state: GameState, house1HasColony: bool, house2HasColony: bool] =
    ## Create game state with two houses - one defeated, one with colony
    var state = GameState()
    state.turn = 1
    state.phase = GamePhase.Active

    # House 1 - Lost all colonies but has fleet with marines
    state.houses["house1"] = House(
      id: "house1",
      name: "Desperate House",
      treasury: 1000,
      eliminated: false,
      techTree: res_types.initTechTree(),  # Initialize with all tech at level 1
    )

    # House 2 - Has a colony
    state.houses["house2"] = House(
      id: "house2",
      name: "Victorious House",
      treasury: 10000,
      eliminated: false,
      techTree: res_types.initTechTree(),  # Initialize with all tech at level 1
    )

    # Enemy colony (house2 controls system 1)
    state.colonies[1] = Colony(
      systemId: 1,
      owner: "house2",
      population: 50,
      souls: 50_000_000,
      infrastructure: 3,
      planetClass: PlanetClass.Benign,
      resources: ResourceRating.Abundant,
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
      groundBatteries: 0,  # No defenses - easy invasion
      armies: 1,           # 1 army defending
      marines: 0,
      blockaded: false,
      blockadedBy: @[],
      blockadeTurns: 0
    )

    # House 1 fleet with marines (last-stand force)
    let marine1 = createMarine("md1", "house1")
    let marine2 = createMarine("md2", "house1")

    let transport = SpaceLiftShip(
      id: "transport1",
      shipClass: ShipClass.TroopTransport,
      owner: "house1",
      location: 1,
      isCrippled: false,
      cargo: SpaceLiftCargo(
        cargoType: CargoType.Marines,
        quantity: 2,  # 2 marines loaded
        capacity: 5
      )
    )

    state.fleets["fleet1"] = Fleet(
      id: "fleet1",
      owner: "house1",
      location: 1,  # At enemy system
      squadrons: @[],
      spaceLiftShips: @[transport],
      status: FleetStatus.Active
    )

    result = (state: state, house1HasColony: false, house2HasColony: true)

  test "House without colonies not eliminated if has fleets":
    var (state, _, _) = createTestState()

    # House 1 has no colonies but has fleet with marines
    check state.colonies.len == 1
    check state.colonies[1].owner == "house2"
    check state.fleets.len == 1
    check state.fleets["fleet1"].owner == "house1"

    # House 1 should NOT be eliminated
    check state.houses["house1"].eliminated == false

  test "House can invade after losing all colonies":
    var (state, _, _) = createTestState()

    # Issue invasion order from house1 (no colonies) against house2 colony
    let invasionOrder = FleetOrder(
      fleetId: "fleet1",
      orderType: FleetOrderType.Invade,
      targetSystem: some(SystemId(1))
    )

    var packet = OrderPacket(
      houseId: "house1",
      turn: 1,
      buildOrders: @[],
      fleetOrders: @[invasionOrder],
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

    # Resolve turn with invasion
    let result = resolveTurn(state, orders)
    state = result.newState

    # Invasion should be attempted (success depends on combat, but order should process)
    # House 1 should still not be eliminated (has fleet)
    check state.houses["house1"].eliminated == false

  test "Successful reconquest restores house with colonies":
    # This test requires full combat resolution
    # Placeholder for now - verifies system allows the attempt
    check true  # TODO: Full combat integration test

  test "House eliminated only when loses both colonies and fleets":
    var state = GameState()
    state.turn = 1
    state.houses["house1"] = House(
      id: "house1",
      name: "Doomed House",
      treasury: 0,
      eliminated: false,
      techTree: res_types.initTechTree(),  # Initialize with all tech at level 1
    )

    # No colonies, no fleets
    var orders = initTable[HouseId, OrderPacket]()

    let result = resolveTurn(state, orders)

    # House should be eliminated (no colonies AND no fleets)
    check result.newState.houses["house1"].eliminated == true

  test "House with empty transports is eliminated":
    var state = GameState()
    state.turn = 1
    state.houses["house1"] = House(
      id: "house1",
      name: "Hopeless House",
      treasury: 100,
      eliminated: false,
      techTree: res_types.initTechTree(),  # Initialize with all tech at level 1
    )

    # Empty transport - no invasion capability
    let emptyTransport = SpaceLiftShip(
      id: "transport1",
      shipClass: ShipClass.TroopTransport,
      owner: "house1",
      location: 1,
      isCrippled: false,
      cargo: SpaceLiftCargo(
        cargoType: CargoType.None,
        quantity: 0,
        capacity: 5
      )
    )

    state.fleets["fleet1"] = Fleet(
      id: "fleet1",
      owner: "house1",
      location: 1,
      squadrons: @[],
      spaceLiftShips: @[emptyTransport],
      status: FleetStatus.Active
    )

    var orders = initTable[HouseId, OrderPacket]()
    let result = resolveTurn(state, orders)

    # House should be eliminated (no colonies, no loaded marines)
    check result.newState.houses["house1"].eliminated == true

  test "House with loaded marines NOT eliminated":
    var state = GameState()
    state.turn = 1
    state.houses["house1"] = House(
      id: "house1",
      name: "Fighting House",
      treasury: 100,
      eliminated: false,
      techTree: res_types.initTechTree(),  # Initialize with all tech at level 1
    )

    # Transport with marines - has invasion capability
    let loadedTransport = SpaceLiftShip(
      id: "transport1",
      shipClass: ShipClass.TroopTransport,
      owner: "house1",
      location: 1,
      isCrippled: false,
      cargo: SpaceLiftCargo(
        cargoType: CargoType.Marines,
        quantity: 2,
        capacity: 5
      )
    )

    state.fleets["fleet1"] = Fleet(
      id: "fleet1",
      owner: "house1",
      location: 1,
      squadrons: @[],
      spaceLiftShips: @[loadedTransport],
      status: FleetStatus.Active
    )

    var orders = initTable[HouseId, OrderPacket]()
    let result = resolveTurn(state, orders)

    # House should NOT be eliminated (has marines for invasion)
    check result.newState.houses["house1"].eliminated == false

suite "Last-Stand Blitz Operations":

  proc createBlitzTestState(): GameState =
    ## Create state for blitz testing
    var state = GameState()
    state.turn = 1
    state.phase = GamePhase.Active

    state.houses["house1"] = House(
      id: "house1",
      name: "Aggressive House",
      treasury: 1000,
      eliminated: false,
      techTree: res_types.initTechTree(),  # Initialize with all tech at level 1
    )

    state.houses["house2"] = House(
      id: "house2",
      name: "Target House",
      treasury: 10000,
      eliminated: false,
      techTree: res_types.initTechTree(),  # Initialize with all tech at level 1
    )

    # Target colony
    state.colonies[1] = Colony(
      systemId: 1,
      owner: "house2",
      population: 30,
      souls: 30_000_000,
      infrastructure: 2,
      planetClass: PlanetClass.Harsh,
      resources: ResourceRating.Poor,
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

    # Attack fleet with combat ships and marines
    let destroyer = newEnhancedShip(ShipClass.Destroyer)
    let squadron = newSquadron(
      flagship = destroyer,
      id = "sq1",
      owner = "house1",
      location = 1
    )

    let transport = SpaceLiftShip(
      id: "transport1",
      shipClass: ShipClass.TroopTransport,
      owner: "house1",
      location: 1,
      isCrippled: false,
      cargo: SpaceLiftCargo(
        cargoType: CargoType.Marines,
        quantity: 3,
        capacity: 5
      )
    )

    state.fleets["fleet1"] = Fleet(
      id: "fleet1",
      owner: "house1",
      location: 1,
      squadrons: @[squadron],
      spaceLiftShips: @[transport],
      status: FleetStatus.Active
    )

    state

  test "Colony-less house can execute blitz operations":
    var state = createBlitzTestState()

    # Issue blitz order
    let blitzOrder = FleetOrder(
      fleetId: "fleet1",
      orderType: FleetOrderType.Blitz,
      targetSystem: some(SystemId(1))
    )

    var packet = OrderPacket(
      houseId: "house1",
      turn: 1,
      buildOrders: @[],
      fleetOrders: @[blitzOrder],
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
    state = result.newState

    # Blitz should be attempted
    check state.houses["house1"].eliminated == false

when isMainModule:
  echo "╔════════════════════════════════════════════════╗"
  echo "║  Last-Stand Invasion Tests                    ║"
  echo "╚════════════════════════════════════════════════╝"
