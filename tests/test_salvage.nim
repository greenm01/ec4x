## Tests for Salvage and Repair System

import std/[unittest, options, tables, strutils]
import ../src/common/types/[core, units]
import ../src/engine/[gamestate, fleet, squadron, starmap]
import ../src/engine/initialization/game
import ../src/engine/economy/maintenance
import ../src/engine/economy/types as econ_types

# Import salvage module with alias to avoid conflicts
import ../src/engine/salvage as salvage_module

suite "Salvage Operations":
  test "salvage value calculation":
    # Test normal salvage (50% value)
    let destroyerValue = salvage_module.getSalvageValue(ShipClass.Destroyer, salvage_module.SalvageType.Normal)
    let destroyerCost = getShipStats(ShipClass.Destroyer).buildCost
    check destroyerValue == int(float(destroyerCost) * 0.5)

    # Test emergency salvage (25% value)
    let emergencyValue = salvage_module.getSalvageValue(ShipClass.Destroyer, salvage_module.SalvageType.Emergency)
    check emergencyValue == int(float(destroyerCost) * 0.25)

  test "salvage destroyed ship":
    let result = salvage_module.salvageShip(ShipClass.Cruiser, salvage_module.SalvageType.Normal)
    check result.success
    check result.shipClass == ShipClass.Cruiser
    check result.salvageType == salvage_module.SalvageType.Normal
    check result.resourcesRecovered > 0
    check result.resourcesRecovered == salvage_module.getSalvageValue(ShipClass.Cruiser, salvage_module.SalvageType.Normal)

  test "salvage multiple ships":
    let destroyed = @[ShipClass.Fighter, ShipClass.Scout, ShipClass.Destroyer]
    let results = salvage_module.salvageDestroyedShips(destroyed, salvage_module.SalvageType.Emergency)

    check results.len == 3
    check results[0].shipClass == ShipClass.Fighter
    check results[1].shipClass == ShipClass.Scout
    check results[2].shipClass == ShipClass.Destroyer

    # All should be emergency salvage
    for result in results:
      check result.salvageType == salvage_module.SalvageType.Emergency
      check result.success

  test "fleet salvage value":
    # Create fleet with multiple ships
    let squadron1 = createSquadron(ShipClass.Cruiser, 1, "sq1", "house1", 100)
    let squadron2 = createSquadron(ShipClass.Destroyer, 1, "sq2", "house1", 100)
    let squadron3 = createSquadron(ShipClass.Scout, 1, "sq3", "house1", 100)

    var fleet = Fleet(
      id: "fleet1",
      owner: "house1",
      location: 100,
      squadrons: @[squadron1, squadron2, squadron3]
    )

    let totalValue = salvage_module.getFleetSalvageValue(fleet, salvage_module.SalvageType.Normal)
    let expectedValue =
      salvage_module.getSalvageValue(ShipClass.Cruiser, salvage_module.SalvageType.Normal) +
      salvage_module.getSalvageValue(ShipClass.Destroyer, salvage_module.SalvageType.Normal) +
      salvage_module.getSalvageValue(ShipClass.Scout, salvage_module.SalvageType.Normal)

    check totalValue == expectedValue

suite "Repair Operations":
  test "ship repair cost calculation":
    let destroyerCost = salvage_module.getShipRepairCost(ShipClass.Destroyer)
    let destroyerBuildCost = getShipStats(ShipClass.Destroyer).buildCost
    check destroyerCost == int(float(destroyerBuildCost) * 0.25)

    let dreadnoughtCost = salvage_module.getShipRepairCost(ShipClass.Dreadnought)
    let dreadnoughtBuildCost = getShipStats(ShipClass.Dreadnought).buildCost
    check dreadnoughtCost == int(float(dreadnoughtBuildCost) * 0.25)

  test "starbase repair cost":
    let cost = salvage_module.getStarbaseRepairCost()
    check cost > 0
    # Should be 25% of starbase build cost

  test "repair turns":
    let turns = salvage_module.getRepairTurns()
    check turns == 1  # Per config: ship_repair_turns = 1

  test "get crippled ships from fleet":
    # Create fleet with some crippled ships
    var squadron1 = createSquadron(ShipClass.Cruiser, 1, "sq1", "house1", 100)
    var squadron2 = createSquadron(ShipClass.Destroyer, 1, "sq2", "house1", 100)
    var squadron3 = createSquadron(ShipClass.Scout, 1, "sq3", "house1", 100)

    # Cripple two ships
    squadron1.flagship.isCrippled = true
    squadron3.flagship.isCrippled = true

    let fleet = Fleet(
      id: "fleet1",
      owner: "house1",
      location: 100,
      squadrons: @[squadron1, squadron2, squadron3]
    )

    let crippled = salvage_module.getCrippledShips(fleet)
    check crippled.len == 2
    check crippled[0] == (0, ShipClass.Cruiser)
    check crippled[1] == (2, ShipClass.Scout)

  test "repair ship validation - wrong owner":
    # Create game state with colony owned by different house
    var starmap = newStarMap(2)
    starmap.populate()
    var state = newGameState("test", 2, starmap)

    var house1 = initializeHouse("House1", "blue")
    var house2 = initializeHouse("House2", "red")
    state.houses["house1"] = house1
    state.houses["house2"] = house2

    var colony = Colony(
      systemId: 100,
      owner: "house2",  # Owned by house2
      population: 100,
      infrastructure: 5,
      planetClass: PlanetClass.Lush,
      resources: ResourceRating.Rich,
      buildings: @[],
      production: 100,
      underConstruction: none(econ_types.ConstructionProject),
      fighterSquadrons: @[],
      capacityViolation: CapacityViolation(active: false, turnsRemaining: 0, violationTurn: 0),
      starbases: @[],
      spaceports: @[],
      shipyards: @[Shipyard(id: "sy1", commissionedTurn: 1, docks: 10, isCrippled: false)],
      planetaryShieldLevel: 0,
      groundBatteries: 0,
      armies: 0,
      marines: 0
    )

    state.colonies[100] = colony

    let request = salvage_module.RepairRequest(
      targetType: salvage_module.RepairTargetType.Ship,
      shipClass: some(ShipClass.Destroyer),
      systemId: 100,
      requestingHouse: "house1"  # house1 trying to repair at house2's colony
    )

    let validation = salvage_module.validateRepairRequest(request, state)
    check not validation.valid
    check validation.message.contains("another house")

  test "repair ship validation - no shipyard":
    # Create game state with colony but no shipyard
    var starmap = newStarMap(2)
    starmap.populate()
    var state = newGameState("test", 2, starmap)

    var house = initializeHouse("TestHouse", "blue")
    state.houses["house1"] = house

    var colony = Colony(
      systemId: 100,
      owner: "house1",
      population: 100,
      infrastructure: 5,
      planetClass: PlanetClass.Lush,
      resources: ResourceRating.Rich,
      buildings: @[],
      production: 100,
      underConstruction: none(econ_types.ConstructionProject),
      fighterSquadrons: @[],
      capacityViolation: CapacityViolation(active: false, turnsRemaining: 0, violationTurn: 0),
      starbases: @[],
      spaceports: @[],
      shipyards: @[],
      planetaryShieldLevel: 0,
      groundBatteries: 0,
      armies: 0,
      marines: 0
    )

    state.colonies[100] = colony

    let request = salvage_module.RepairRequest(
      targetType: salvage_module.RepairTargetType.Ship,
      shipClass: some(ShipClass.Destroyer),
      systemId: 100,
      requestingHouse: "house1"
    )

    let validation = salvage_module.validateRepairRequest(request, state)
    check not validation.valid
    check validation.message.contains("no shipyard")

  test "repair ship validation - insufficient funds":
    # Create game state with shipyard but no money
    var starmap = newStarMap(2)
    starmap.populate()
    var state = newGameState("test", 2, starmap)

    var house = initializeHouse("TestHouse", "blue")
    house.treasury = 5  # Very low funds (Cruiser repair costs 25% of 60 = 15 PP)
    state.houses["house1"] = house

    var colony = Colony(
      systemId: 100,
      owner: "house1",
      population: 100,
      infrastructure: 5,
      planetClass: PlanetClass.Lush,
      resources: ResourceRating.Rich,
      buildings: @[],
      production: 100,
      underConstruction: none(econ_types.ConstructionProject),
      fighterSquadrons: @[],
      capacityViolation: CapacityViolation(active: false, turnsRemaining: 0, violationTurn: 0),
      starbases: @[],
      spaceports: @[],
      shipyards: @[Shipyard(id: "sy1", commissionedTurn: 1, docks: 10, isCrippled: false)],
      planetaryShieldLevel: 0,
      groundBatteries: 0,
      armies: 0,
      marines: 0
    )

    state.colonies[100] = colony

    let request = salvage_module.RepairRequest(
      targetType: salvage_module.RepairTargetType.Ship,
      shipClass: some(ShipClass.Cruiser),  # 60 PP build cost, 15 PP repair cost
      systemId: 100,
      requestingHouse: "house1"
    )

    let validation = salvage_module.validateRepairRequest(request, state)
    check not validation.valid
    check validation.message.contains("Insufficient funds")

  test "repair ship validation - success":
    # Create game state with shipyard and sufficient funds
    var starmap = newStarMap(2)
    starmap.populate()
    var state = newGameState("test", 2, starmap)

    var house = initializeHouse("TestHouse", "blue")
    house.treasury = 10000  # Plenty of funds
    state.houses["house1"] = house

    var colony = Colony(
      systemId: 100,
      owner: "house1",
      population: 100,
      infrastructure: 5,
      planetClass: PlanetClass.Lush,
      resources: ResourceRating.Rich,
      buildings: @[],
      production: 100,
      underConstruction: none(econ_types.ConstructionProject),
      fighterSquadrons: @[],
      capacityViolation: CapacityViolation(active: false, turnsRemaining: 0, violationTurn: 0),
      starbases: @[],
      spaceports: @[],
      shipyards: @[Shipyard(id: "sy1", commissionedTurn: 1, docks: 10, isCrippled: false)],
      planetaryShieldLevel: 0,
      groundBatteries: 0,
      armies: 0,
      marines: 0
    )

    state.colonies[100] = colony

    let request = salvage_module.RepairRequest(
      targetType: salvage_module.RepairTargetType.Ship,
      shipClass: some(ShipClass.Destroyer),
      systemId: 100,
      requestingHouse: "house1"
    )

    let validation = salvage_module.validateRepairRequest(request, state)
    check validation.valid
    check validation.cost > 0
    check validation.message == "Repair approved"

suite "Upkeep Calculations":
  test "ship upkeep costs from config":
    # Test that upkeep comes from ships.toml
    let fighterUpkeep = getShipMaintenanceCost(ShipClass.Fighter, false)
    check fighterUpkeep == 1  # Per ships.toml

    let cruiserUpkeep = getShipMaintenanceCost(ShipClass.Cruiser, false)
    check cruiserUpkeep == 2  # Per ships.toml

    let dreadnoughtUpkeep = getShipMaintenanceCost(ShipClass.Dreadnought, false)
    check dreadnoughtUpkeep == 10  # Per ships.toml

  test "crippled ship upkeep decrease":
    let normalUpkeep = getShipMaintenanceCost(ShipClass.Destroyer, false)
    let crippledUpkeep = getShipMaintenanceCost(ShipClass.Destroyer, true)

    # Crippled ships cost 50% (half cost) per combat.toml
    check crippledUpkeep == normalUpkeep div 2

  test "facility upkeep costs":
    check getSpaceportUpkeep() == 5    # Per facilities.toml
    check getShipyardUpkeep() == 5     # Per facilities.toml
    check getStarbaseUpkeep() == 75    # Per construction.toml
    check getGroundBatteryUpkeep() == 5  # Per construction.toml
    check getPlanetaryShieldUpkeep() == 50  # Per construction.toml

  test "ground unit upkeep costs":
    check getArmyUpkeep() == 1  # Per ground_units.toml
    check getMarineUpkeep() == 1  # Per ground_units.toml

  test "colony total upkeep calculation":
    # Create colony with various assets
    let colony = Colony(
      systemId: 100,
      owner: "house1",
      population: 100,
      infrastructure: 5,
      planetClass: PlanetClass.Lush,
      resources: ResourceRating.Rich,
      buildings: @[],
      production: 100,
      underConstruction: none(econ_types.ConstructionProject),
      fighterSquadrons: @[],
      capacityViolation: CapacityViolation(active: false, turnsRemaining: 0, violationTurn: 0),
      starbases: @[
        Starbase(id: "sb1", commissionedTurn: 1, isCrippled: false),
        Starbase(id: "sb2", commissionedTurn: 2, isCrippled: false)
      ],
      spaceports: @[
        Spaceport(id: "sp1", commissionedTurn: 1, docks: 5)
      ],
      shipyards: @[
        Shipyard(id: "sy1", commissionedTurn: 1, docks: 10, isCrippled: false)
      ],
      planetaryShieldLevel: 3,  # SLD-3
      groundBatteries: 5,
      armies: 10,
      marines: 2
    )

    let upkeep = calculateColonyUpkeep(colony)
    let expected =
      (2 * getStarbaseUpkeep()) +    # 2 starbases
      (1 * getSpaceportUpkeep()) +   # 1 spaceport
      (1 * getShipyardUpkeep()) +    # 1 shipyard
      getPlanetaryShieldUpkeep() +   # 1 shield
      (5 * getGroundBatteryUpkeep()) +  # 5 batteries
      (10 * getArmyUpkeep()) +       # 10 armies
      (2 * getMarineUpkeep())        # 2 marines

    check upkeep == expected

echo "\nSalvage and Repair Tests Complete!"
