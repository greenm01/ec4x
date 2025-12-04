## Game Limits Unit Tests
##
## Tests all game limits from reference.md:9.5 (Anti-Spam / Anti-Cheese Caps)
## - Capital-ship squadron limits (PU ÷ 100, min 8)
## - Planet-Breaker limits (1 per colony)
## - Fighter squadron limits (per colony, with FD multiplier)
## - Carrier hangar capacity (CV/CX with ACO tech)

import std/[unittest, tables, options]
import ../../src/engine/[gamestate, starmap, fleet, ship, squadron]
import ../../src/engine/config/military_config
import ../../src/common/types/[core, planets, tech, combat, units]
import ../../src/common/[hex, system]

suite "Game Limits: Anti-Spam/Anti-Cheese Caps":

  # ==========================================================================
  # Capital-Ship Squadron Limit Tests (economy.md:3.12)
  # ==========================================================================

  test "Squadron limit formula: PU ÷ 100 (round down)":
    var state = GameState()
    state.houses["house1"] = House(
      id: "house1",
      name: "Test House",
      treasury: 0,
      eliminated: false
    )

    # 1000 PU = 10 squadrons
    state.colonies[1] = Colony(
      systemId: 1,
      owner: "house1",
      population: 1000,  # PU = population in millions
      souls: 0,
      infrastructure: 5,
      planetClass: PlanetClass.Benign,
      resources: ResourceRating.Abundant,
      buildings: @[],
      production: 0,
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

    let limit = state.getSquadronLimit("house1")
    check limit == 10  # 1000 ÷ 100 = 10

  test "Squadron limit: minimum of 8 enforced":
    var state = GameState()
    state.houses["house1"] = House(
      id: "house1",
      name: "Test House",
      treasury: 0,
      eliminated: false
    )

    # 500 PU would be 5, but minimum is 8
    state.colonies[1] = Colony(
      systemId: 1,
      owner: "house1",
      population: 500,
      souls: 0,
      infrastructure: 5,
      planetClass: PlanetClass.Benign,
      resources: ResourceRating.Abundant,
      buildings: @[],
      production: 0,
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

    let limit = state.getSquadronLimit("house1")
    check limit == 8  # Minimum enforced

  test "Squadron limit: zero PU gets minimum 8":
    var state = GameState()
    state.houses["house1"] = House(
      id: "house1",
      name: "Test House",
      treasury: 0,
      eliminated: false
    )
    # No colonies

    let limit = state.getSquadronLimit("house1")
    check limit == 8  # Minimum enforced

  test "Squadron limit: large empire scales correctly":
    var state = GameState()
    state.houses["house1"] = House(
      id: "house1",
      name: "Test House",
      treasury: 0,
      eliminated: false
    )

    # Multiple colonies totaling 5000 PU
    for i in 1u..5u:
      state.colonies[i] = Colony(
        systemId: i,
        owner: "house1",
        population: 1000,  # 1000 each = 5000 total
        souls: 0,
        infrastructure: 5,
        planetClass: PlanetClass.Benign,
        resources: ResourceRating.Abundant,
        buildings: @[],
        production: 0,
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

    let totalPU = state.getHousePopulationUnits("house1")
    check totalPU == 5000

    let limit = state.getSquadronLimit("house1")
    check limit == 50  # 5000 ÷ 100 = 50

  test "Squadron count: counts capital-ship flagships":
    var state = GameState()
    state.houses["house1"] = House(
      id: "house1",
      name: "Test House",
      treasury: 0,
      eliminated: false
    )

    # Create squadrons with capital-ship flagships
    let dreadnought = newEnhancedShip(ShipClass.Dreadnought)
    var sq1 = newSquadron(dreadnought)

    let battleship = newEnhancedShip(ShipClass.Battleship)
    var sq2 = newSquadron(battleship)

    state.fleets["fleet-1"] = Fleet(
      id: "fleet-1",
      squadrons: @[sq1, sq2],
      spaceLiftShips: @[],
      owner: "house1",
      location: 1,
      status: FleetStatus.Active
    )

    let count = state.getHouseSquadronCount("house1")
    check count == 2  # Both count

  test "Squadron count: scouts are exempt":
    var state = GameState()
    state.houses["house1"] = House(
      id: "house1",
      name: "Test House",
      treasury: 0,
      eliminated: false
    )

    # Create scout squadrons
    let scout1 = newEnhancedShip(ShipClass.Scout)
    var sq1 = newSquadron(scout1)

    let scout2 = newEnhancedShip(ShipClass.Scout)
    var sq2 = newSquadron(scout2)

    state.fleets["fleet-1"] = Fleet(
      id: "fleet-1",
      squadrons: @[sq1, sq2],
      spaceLiftShips: @[],
      owner: "house1",
      location: 1,
      status: FleetStatus.Active
    )

    let count = state.getHouseSquadronCount("house1")
    check count == 0  # Scouts don't count

  test "Squadron limit: over limit detection":
    var state = GameState()
    state.houses["house1"] = House(
      id: "house1",
      name: "Test House",
      treasury: 0,
      eliminated: false
    )

    # 800 PU = limit of 8
    state.colonies[1] = Colony(
      systemId: 1,
      owner: "house1",
      population: 800,
      souls: 0,
      infrastructure: 5,
      planetClass: PlanetClass.Benign,
      resources: ResourceRating.Abundant,
      buildings: @[],
      production: 0,
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

    # Create 10 squadrons (over limit of 8)
    for i in 1..10:
      let destroyer = newEnhancedShip(ShipClass.Destroyer)
      var sq = newSquadron(destroyer)
      state.fleets["fleet-" & $i] = Fleet(
        id: "fleet-" & $i,
        squadrons: @[sq],
        spaceLiftShips: @[],
        owner: "house1",
        location: 1,
        status: FleetStatus.Active
      )

    check state.isOverSquadronLimit("house1") == true

  # ==========================================================================
  # Planet-Breaker Limit Tests (assets.md:2.4.8)
  # ==========================================================================

  test "Planet-Breaker limit: 1 per colony":
    var state = GameState()
    state.houses["house1"] = House(
      id: "house1",
      name: "Test House",
      treasury: 0,
      eliminated: false
    )

    # Add 3 colonies
    for i in 1u..3u:
      state.colonies[i] = Colony(
        systemId: i,
        owner: "house1",
        population: 100,
        souls: 0,
        infrastructure: 5,
        planetClass: PlanetClass.Benign,
        resources: ResourceRating.Abundant,
        buildings: @[],
        production: 0,
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

    let limit = state.getPlanetBreakerLimit("house1")
    check limit == 3  # 1 per colony

  test "Planet-Breaker limit: zero colonies = zero limit":
    var state = GameState()
    state.houses["house1"] = House(
      id: "house1",
      name: "Test House",
      treasury: 0,
      eliminated: false
    )
    # No colonies

    let limit = state.getPlanetBreakerLimit("house1")
    check limit == 0

  # ==========================================================================
  # Fighter Squadron Limit Tests (assets.md:2.4.1)
  # ==========================================================================

  test "Fighter capacity: FD multiplier effects":
    let colony = Colony(
      systemId: 1,
      owner: "house1",
      population: 1000,
      souls: 0,
      infrastructure: 840,
      planetClass: PlanetClass.Benign,
      resources: ResourceRating.Abundant,
      buildings: @[],
      production: 0,
      underConstruction: none(ConstructionProject),
      activeTerraforming: none(TerraformProject),
      unassignedSquadrons: @[],
      unassignedSpaceLiftShips: @[],
      autoAssignFleets: false,
      fighterSquadrons: @[],
      capacityViolation: CapacityViolation(),
      starbases: @[
        Starbase(id: "sb1", commissionedTurn: 1, isCrippled: false),
        Starbase(id: "sb2", commissionedTurn: 1, isCrippled: false),
        Starbase(id: "sb3", commissionedTurn: 1, isCrippled: false),
        Starbase(id: "sb4", commissionedTurn: 1, isCrippled: false)
      ],
      spaceports: @[],
      shipyards: @[]
    )

    # FD I = 1.0x: 10 FS
    check getFighterCapacity(colony, 1.0) == 8

    # FD II = 1.5x: 15 FS
    check getFighterCapacity(colony, 1.5) == 12

    # FD III = 2.0x: 20 FS
    check getFighterCapacity(colony, 2.0) == 16

  test "Fighter doctrine multipliers from tech":
    # FD I = 1.0x
    let techI = TechLevel(fighterDoctrine: 1)
    check getFighterDoctrineMultiplier(techI) == 1.0

    # FD II = 1.5x
    let techII = TechLevel(fighterDoctrine: 2)
    check getFighterDoctrineMultiplier(techII) == 1.5

    # FD III = 2.0x
    let techIII = TechLevel(fighterDoctrine: 3)
    check getFighterDoctrineMultiplier(techIII) == 2.0

  # ==========================================================================
  # Carrier Hangar Capacity Tests (assets.md:2.4.1)
  # ==========================================================================

  test "Carrier capacity: CV progression with ACO tech":
    let cv = newEnhancedShip(ShipClass.Carrier)
    var sq = newSquadron(cv)

    # ACO I: 3 FS
    check getCarrierCapacity(sq, acoLevel = 1) == 3

    # ACO II: 4 FS
    check getCarrierCapacity(sq, acoLevel = 2) == 4

    # ACO III: 5 FS
    check getCarrierCapacity(sq, acoLevel = 3) == 5

  test "Carrier capacity: CX progression with ACO tech":
    let cx = newEnhancedShip(ShipClass.SuperCarrier)
    var sq = newSquadron(cx)

    # ACO I: 5 FS
    check getCarrierCapacity(sq, acoLevel = 1) == 5

    # ACO II: 6 FS (interpolated from spec)
    check getCarrierCapacity(sq, acoLevel = 2) == 6

    # ACO III: 8 FS
    check getCarrierCapacity(sq, acoLevel = 3) == 8

  # ==========================================================================
  # Integration Tests
  # ==========================================================================

  test "Integration: empire growth increases squadron limit":
    var state = GameState()
    state.houses["house1"] = House(
      id: "house1",
      name: "Test House",
      treasury: 0,
      eliminated: false
    )

    # Start small: 500 PU = 8 minimum
    state.colonies[1] = Colony(
      systemId: 1,
      owner: "house1",
      population: 500,
      souls: 0,
      infrastructure: 5,
      planetClass: PlanetClass.Benign,
      resources: ResourceRating.Abundant,
      buildings: @[],
      production: 0,
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

    check state.getSquadronLimit("house1") == 8

    # Expand: add 1000 PU colony (1500 total = 15 limit)
    state.colonies[2] = Colony(
      systemId: 2,
      owner: "house1",
      population: 1000,
      souls: 0,
      infrastructure: 5,
      planetClass: PlanetClass.Benign,
      resources: ResourceRating.Abundant,
      buildings: @[],
      production: 0,
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

    check state.getSquadronLimit("house1") == 15

  test "Integration: FD tech increases fighter capacity":
    let colony = Colony(
      systemId: 1,
      owner: "house1",
      population: 1000,
      souls: 0,
      infrastructure: 5,
      planetClass: PlanetClass.Benign,
      resources: ResourceRating.Abundant,
      buildings: @[],
      production: 0,
      underConstruction: none(ConstructionProject),
      activeTerraforming: none(TerraformProject),
      unassignedSquadrons: @[],
      unassignedSpaceLiftShips: @[],
      autoAssignFleets: false,
      fighterSquadrons: @[],
      capacityViolation: CapacityViolation(),
      starbases: @[
        Starbase(id: "sb1", commissionedTurn: 1, isCrippled: false),
        Starbase(id: "sb2", commissionedTurn: 1, isCrippled: false),
        Starbase(id: "sb3", commissionedTurn: 1, isCrippled: false),
        Starbase(id: "sb4", commissionedTurn: 1, isCrippled: false)
      ],
      spaceports: @[],
      shipyards: @[]
    )

    # Research progression
    check getFighterCapacity(colony, 1.0) == 10   # FD I
    check getFighterCapacity(colony, 1.5) == 15   # FD II
    check getFighterCapacity(colony, 2.0) == 20   # FD III
