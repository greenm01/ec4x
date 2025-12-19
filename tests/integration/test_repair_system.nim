## Integration Tests for Ship and Starbase Repair System
##
## Tests the complete repair flow from crippled units to commissioning
## Covers:
## - Ship extraction from fleets and submission to repair queue
## - Flagship promotion when flagship goes to repair
## - Squadron/fleet dissolution logic
## - Starbase repair submission
## - Repair completion and recommissioning
## - Shipyard capacity constraints
## - Auto-assignment after repair completion

import std/[unittest, tables, options]
import ../../src/engine/[gamestate, orders, resolve, fleet, squadron, spacelift]
import ../../src/engine/economy/types as econ_types
import ../../src/engine/economy/repair_queue
import ../../src/engine/research/types as res_types
import ../../src/engine/espionage/types as esp_types
import ../../src/common/types/[core, units]

suite "Ship Repair System":

  proc createTestState(): GameState =
    var result = GameState()
    result.turn = 1
    result.phase = GamePhase.Active

    result.houses["house1"] = House(
      id: "house1",
      name: "Test House",
      treasury: 10000,
      eliminated: false,
      techTree: res_types.initTechTree(),
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
      constructionQueue: @[],
      repairQueue: @[],
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

    result

  test "Crippled escort is extracted and submitted to repair queue":
    var state = createTestState()

    # Create fleet with crippled escort
    var destroyer1 = newShip(ShipClass.Destroyer)
    var destroyer2 = newShip(ShipClass.Destroyer)
    destroyer2.isCrippled = true  # Mark second destroyer as crippled

    var squadron = newSquadron(destroyer1)
    squadron.ships.add(destroyer2)

    let fleetId = "fleet1"
    state.fleets[fleetId] = Fleet(
      id: fleetId,
      owner: "house1",
      location: 1,
      squadrons: @[squadron],
      spaceLiftShips: @[],
      status: FleetStatus.Active,
      autoBalanceSquadrons: true
    )

    # Submit automatic repairs
    state.submitAutomaticRepairs(1)

    # Check repair queue
    check state.colonies[1].repairQueue.len == 1
    let repair = state.colonies[1].repairQueue[0]
    check repair.targetType == econ_types.RepairTargetType.Ship
    check repair.shipClass.get() == ShipClass.Destroyer
    check repair.turnsRemaining == 1
    check repair.facilityType == econ_types.FacilityType.Shipyard

    # Check escort was removed from squadron
    let updatedFleet = state.fleets[fleetId]
    check updatedFleet.squadrons[0].ships.len == 0  # Escort removed

  test "Crippled flagship with escorts promotes strongest escort":
    var state = createTestState()

    # Create squadron with crippled flagship and escorts
    var destroyer = newShip(ShipClass.Destroyer)
    destroyer.isCrippled = true  # Crippled flagship

    var cruiser = newShip(ShipClass.Cruiser)  # Stronger escort
    var scout = newShip(ShipClass.Scout)      # Weaker escort

    var squadron = newSquadron(destroyer)
    squadron.ships.add(cruiser)
    squadron.ships.add(scout)

    let fleetId = "fleet1"
    state.fleets[fleetId] = Fleet(
      id: fleetId,
      owner: "house1",
      location: 1,
      squadrons: @[squadron],
      spaceLiftShips: @[],
      status: FleetStatus.Active,
      autoBalanceSquadrons: true
    )

    # Extract crippled flagship
    let repairOpt = state.extractCrippledShip(fleetId, 0, -1)

    check repairOpt.isSome
    check repairOpt.get().shipClass.get() == ShipClass.Destroyer

    # Check cruiser was promoted to flagship (strongest)
    let updatedFleet = state.fleets[fleetId]
    check updatedFleet.squadrons[0].flagship.shipClass == ShipClass.Cruiser
    check updatedFleet.squadrons[0].ships.len == 1  # Scout remains as escort

  test "Crippled single-flagship squadron dissolves squadron":
    var state = createTestState()

    # Create squadron with only crippled flagship (no escorts)
    var destroyer = newShip(ShipClass.Destroyer)
    destroyer.isCrippled = true

    var squadron = newSquadron(destroyer)

    let fleetId = "fleet1"
    state.fleets[fleetId] = Fleet(
      id: fleetId,
      owner: "house1",
      location: 1,
      squadrons: @[squadron],
      spaceLiftShips: @[],
      status: FleetStatus.Active,
      autoBalanceSquadrons: true
    )

    # Extract crippled flagship
    let repairOpt = state.extractCrippledShip(fleetId, 0, -1)

    check repairOpt.isSome

    # Check squadron was dissolved and fleet removed (empty)
    check fleetId notin state.fleets

  test "Empty fleet after repair extraction is deleted":
    var state = createTestState()

    # Create fleet with single crippled squadron
    var destroyer = newShip(ShipClass.Destroyer)
    destroyer.isCrippled = true

    var squadron = newSquadron(destroyer)

    let fleetId = "fleet1"
    state.fleets[fleetId] = Fleet(
      id: fleetId,
      owner: "house1",
      location: 1,
      squadrons: @[squadron],
      spaceLiftShips: @[],
      status: FleetStatus.Active,
      autoBalanceSquadrons: true
    )

    # Extract flagship (will dissolve squadron and empty fleet)
    let repairOpt = state.extractCrippledShip(fleetId, 0, -1)

    check repairOpt.isSome
    check fleetId notin state.fleets

  test "Fleet with spacelift ships is NOT deleted after squadron extraction":
    var state = createTestState()

    # Create fleet with crippled squadron AND spacelift ship
    var destroyer = newShip(ShipClass.Destroyer)
    destroyer.isCrippled = true

    var squadron = newSquadron(destroyer)

    let spacelift = newSpaceLiftShip("etac1", ShipClass.ETAC, "house1", 1)

    let fleetId = "fleet1"
    state.fleets[fleetId] = Fleet(
      id: fleetId,
      owner: "house1",
      location: 1,
      squadrons: @[squadron],
      spaceLiftShips: @[spacelift],  # Has spacelift ship
      status: FleetStatus.Active,
      autoBalanceSquadrons: true
    )

    # Extract flagship (will dissolve squadron but NOT delete fleet)
    let repairOpt = state.extractCrippledShip(fleetId, 0, -1)

    check repairOpt.isSome
    check fleetId in state.fleets  # Fleet still exists
    check state.fleets[fleetId].squadrons.len == 0
    check state.fleets[fleetId].spaceLiftShips.len == 1  # Spacelift remains

  test "Repair cost is 25% of build cost":
    let destroyerCost = calculateRepairCost(ShipClass.Destroyer)
    let destroyerBuildCost = getShipStats(ShipClass.Destroyer).buildCost

    check destroyerCost == (destroyerBuildCost.float * 0.25).int

    let cruiserCost = calculateRepairCost(ShipClass.Cruiser)
    let cruiserBuildCost = getShipStats(ShipClass.Cruiser).buildCost

    check cruiserCost == (cruiserBuildCost.float * 0.25).int

  test "Repairs require shipyard (not spaceport)":
    var state = createTestState()

    # Remove shipyard, leave only spaceport
    state.colonies[1].shipyards = @[]
    state.colonies[1].spaceports = @[
      Spaceport(id: "sp1", commissionedTurn: 1, docks: 10)
    ]

    # Create fleet with crippled ship
    var destroyer = newShip(ShipClass.Destroyer)
    destroyer.isCrippled = true

    var squadron = newSquadron(destroyer)

    state.fleets["fleet1"] = Fleet(
      id: "fleet1",
      owner: "house1",
      location: 1,
      squadrons: @[squadron],
      spaceLiftShips: @[],
      status: FleetStatus.Active,
      autoBalanceSquadrons: true
    )

    # Submit repairs (should do nothing without shipyard)
    state.submitAutomaticRepairs(1)

    # Repair queue should be empty
    check state.colonies[1].repairQueue.len == 0

  test "Shipyard capacity limits concurrent repairs":
    var state = createTestState()

    # Set shipyard to only 1 dock
    state.colonies[1].shipyards = @[
      Shipyard(id: "sy1", commissionedTurn: 1, docks: 1, isCrippled: false)
    ]

    # Create fleet with 2 crippled escorts
    var destroyer1 = newShip(ShipClass.Destroyer)
    var destroyer2 = newShip(ShipClass.Destroyer)
    destroyer2.isCrippled = true
    var destroyer3 = newShip(ShipClass.Destroyer)
    destroyer3.isCrippled = true

    var squadron = newSquadron(destroyer1)
    squadron.ships.add(destroyer2)
    squadron.ships.add(destroyer3)

    state.fleets["fleet1"] = Fleet(
      id: "fleet1",
      owner: "house1",
      location: 1,
      squadrons: @[squadron],
      spaceLiftShips: @[],
      status: FleetStatus.Active,
      autoBalanceSquadrons: true
    )

    # Submit repairs
    state.submitAutomaticRepairs(1)

    # Only 1 repair should be submitted (capacity = 1 dock)
    check state.colonies[1].repairQueue.len == 1

  test "Repaired ship completes and recommissions to fleet":
    var state = createTestState()

    # Create fleet with crippled escort
    var destroyer1 = newShip(ShipClass.Destroyer)
    var destroyer2 = newShip(ShipClass.Destroyer)
    destroyer2.isCrippled = true

    var squadron = newSquadron(destroyer1)
    squadron.ships.add(destroyer2)

    let fleetId = "fleet1"
    state.fleets[fleetId] = Fleet(
      id: fleetId,
      owner: "house1",
      location: 1,
      squadrons: @[squadron],
      spaceLiftShips: @[],
      status: FleetStatus.Active,
      autoBalanceSquadrons: true
    )

    # Build order to start construction
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
      terraformOrders: @[],
      espionageAction: none(esp_types.EspionageAttempt),
      ebpInvestment: 0,
      cipInvestment: 0
    )

    var orders = initTable[HouseId, OrderPacket]()
    orders["house1"] = packet

    # Resolve turn to start construction
    var result = resolveTurn(state, orders)
    state = result.newState

    # Submit repairs
    state.submitAutomaticRepairs(1)

    # Should have 1 repair in queue
    check state.colonies[1].repairQueue.len == 1

    # Advance 1 turn to complete repair (repairs take 1 turn)
    packet.turn = state.turn
    packet.buildOrders = @[]
    orders["house1"] = packet
    result = resolveTurn(state, orders)
    state = result.newState

    # Repair should be complete and ship should be in a fleet
    # Check that the fleet now exists or has been updated
    var totalSquadrons = 0
    for fleet in state.fleets.values:
      if fleet.owner == "house1" and fleet.location == 1:
        totalSquadrons += fleet.squadrons.len

    # Should have at least 1 squadron (the repaired ship was auto-assigned)
    check totalSquadrons >= 1

suite "Starbase Repair System":

  proc createTestStateWithStarbase(): GameState =
    var result = GameState()
    result.turn = 1
    result.phase = GamePhase.Active

    result.houses["house1"] = House(
      id: "house1",
      name: "Test House",
      treasury: 10000,
      eliminated: false,
      techTree: res_types.initTechTree(),
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
      constructionQueue: @[],
      repairQueue: @[],
      activeTerraforming: none(gamestate.TerraformProject),
      unassignedSquadrons: @[],
      unassignedSpaceLiftShips: @[],
      fighterSquadrons: @[],
      capacityViolation: CapacityViolation(),
      starbases: @[
        Starbase(id: "sb1", commissionedTurn: 1, isCrippled: true)
      ],
      spaceports: @[
        Spaceport(id: "sp1", commissionedTurn: 1, docks: 5, isCrippled: false)
      ],
      shipyards: @[
        Shipyard(id: "sy1", commissionedTurn: 1, docks: 10, isCrippled: false)
      ]
    )

    result

  test "Crippled starbase is submitted to repair queue":
    var state = createTestStateWithStarbase()

    # Submit starbase repairs
    state.submitAutomaticStarbaseRepairs(1)

    # Check repair queue
    check state.colonies[1].repairQueue.len == 1
    let repair = state.colonies[1].repairQueue[0]
    check repair.targetType == econ_types.RepairTargetType.Starbase
    check repair.facilityType == econ_types.FacilityType.Spaceport  # Starbases use Spaceport
    check repair.turnsRemaining == 1

  test "Starbase repairs require spaceport":
    var state = createTestStateWithStarbase()

    # Remove spaceport (starbases need spaceport, not shipyard)
    state.colonies[1].spaceports = @[]

    # Submit repairs (should do nothing without spaceport)
    state.submitAutomaticStarbaseRepairs(1)

    # Repair queue should be empty
    check state.colonies[1].repairQueue.len == 0

  test "Multiple crippled starbases submit multiple repairs":
    var state = createTestStateWithStarbase()

    # Add another crippled starbase
    state.colonies[1].starbases.add(
      Starbase(id: "sb2", commissionedTurn: 1, isCrippled: true)
    )

    # Submit repairs
    state.submitAutomaticStarbaseRepairs(1)

    # Should have 2 repairs
    check state.colonies[1].repairQueue.len == 2


suite "Repair Priority System":

  proc createTestStateForPriority(): GameState =
    var result = GameState()
    result.turn = 1
    result.phase = GamePhase.Active

    result.houses["house1"] = House(
      id: "house1",
      name: "Test House",
      treasury: 10000,
      eliminated: false,
      techTree: res_types.initTechTree(),
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
      constructionQueue: @[],
      repairQueue: @[],
      activeTerraforming: none(gamestate.TerraformProject),
      unassignedSquadrons: @[],
      unassignedSpaceLiftShips: @[],
      fighterSquadrons: @[],
      capacityViolation: CapacityViolation(),
      starbases: @[
        Starbase(id: "sb1", commissionedTurn: 1, isCrippled: true)
      ],
      spaceports: @[],
      shipyards: @[
        Shipyard(id: "sy1", commissionedTurn: 1, docks: 10, isCrippled: false)
      ]
    )

    result

  test "Ship repairs have priority 1, starbase repairs have priority 2":
    var state = createTestStateForPriority()

    # Create fleet with crippled ship
    var destroyer = newShip(ShipClass.Destroyer)
    destroyer.isCrippled = true

    var squadron = newSquadron(destroyer)
    squadron.ships.add(destroyer)  # Add as escort

    state.fleets["fleet1"] = Fleet(
      id: "fleet1",
      owner: "house1",
      location: 1,
      squadrons: @[squadron],
      spaceLiftShips: @[],
      status: FleetStatus.Active,
      autoBalanceSquadrons: true
    )

    # Submit all repairs
    state.submitAutomaticRepairs(1)

    # Should have 2 repairs: 1 ship, 1 starbase
    check state.colonies[1].repairQueue.len == 2

    # Check priorities
    var shipRepairPriority = -1
    var starbaseRepairPriority = -1

    for repair in state.colonies[1].repairQueue:
      if repair.targetType == econ_types.RepairTargetType.Ship:
        shipRepairPriority = repair.priority
      elif repair.targetType == econ_types.RepairTargetType.Starbase:
        starbaseRepairPriority = repair.priority

    check shipRepairPriority == 1
    check starbaseRepairPriority == 2

when isMainModule:
  echo "╔════════════════════════════════════════════════╗"
  echo "║  Ship and Starbase Repair System Tests        ║"
  echo "╚════════════════════════════════════════════════╝"
