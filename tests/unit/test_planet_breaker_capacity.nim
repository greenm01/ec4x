## Unit Tests for Planet-Breaker Capacity Enforcement
##
## Tests complete planet-breaker capacity system per assets.md:2.4.8
## Formula: Max PB = current colony count (1 per colony owned)

import std/[unittest, tables, options]
import ../../src/engine/economy/capacity/planet_breakers
import ../../src/engine/economy/capacity/types
import ../../src/engine/[gamestate, fleet, squadron]
import ../../src/common/types/core
import ../../src/common/types/units

proc createTestHouse(id: string, colonyCount: int, pbCount: int = 0): House =
  result = House(
    id: id,
    name: "Test House",
    planetBreakerCount: pbCount,
    techTree: TechTree()
  )

proc createTestGameState(houseId: HouseId, colonyCount: int, pbsInFleets: int = 0): GameState =
  var state = GameState(
    turn: 10,
    houses: initTable[HouseId, House](),
    colonies: initTable[SystemId, Colony](),
    fleets: initTable[FleetId, Fleet]()
  )

  # Add house
  state.houses[houseId] = createTestHouse(houseId, colonyCount, pbCount = 0)

  # Add colonies
  for i in 1..colonyCount:
    let systemId = SystemId(i)
    state.colonies[systemId] = Colony(
      systemId: systemId,
      owner: houseId,
      populationUnits: 100,
      infrastructure: 5
    )

  # Add planet-breakers in fleets if requested
  if pbsInFleets > 0:
    for i in 1..pbsInFleets:
      let fleetId = FleetId($houseId & "_fleet" & $i)
      let pbShip = newEnhancedShip(ShipClass.PlanetBreaker, techLevel = 1)
      let squadron = newSquadron(pbShip, $houseId & "_sq" & $i, houseId, SystemId(1))

      state.fleets[fleetId] = Fleet(
        id: fleetId,
        owner: houseId,
        location: SystemId(1),
        squadrons: @[squadron],
        spaceLiftShips: @[],
        status: FleetStatus.Active,
        autoBalanceSquadrons: true
      )

  return state

suite "Planet-Breaker Capacity Calculation":
  test "Max capacity equals colony count":
    check calculateMaxPlanetBreakers(0) == 0
    check calculateMaxPlanetBreakers(1) == 1
    check calculateMaxPlanetBreakers(5) == 5
    check calculateMaxPlanetBreakers(10) == 10

  test "Count planet-breakers in fleets":
    let state = createTestGameState("house-test", colonyCount = 5, pbsInFleets = 3)
    let count = countPlanetBreakersInFleets(state, "house-test")
    check count == 3

  test "Count planet-breakers in fleets - multiple per fleet":
    var state = createTestGameState("house-test", colonyCount = 5, pbsInFleets = 0)

    # Add fleet with 2 planet-breakers
    let fleetId = FleetId("house-test_fleet1")
    let pb1 = newEnhancedShip(ShipClass.PlanetBreaker, techLevel = 1)
    let pb2 = newEnhancedShip(ShipClass.PlanetBreaker, techLevel = 1)
    let sq1 = newSquadron(pb1, "house-test_sq1", "house-test", SystemId(1))
    let sq2 = newSquadron(pb2, "house-test_sq2", "house-test", SystemId(1))

    state.fleets[fleetId] = Fleet(
      id: fleetId,
      owner: "house-test",
      location: SystemId(1),
      squadrons: @[sq1, sq2],
      spaceLiftShips: @[],
      status: FleetStatus.Active,
      autoBalanceSquadrons: true
    )

    let count = countPlanetBreakersInFleets(state, "house-test")
    check count == 2

  test "Count excludes other house's planet-breakers":
    var state = createTestGameState("house-test", colonyCount = 5, pbsInFleets = 2)

    # Add planet-breaker for different house
    let fleetId = FleetId("house-other_fleet1")
    let pbShip = newEnhancedShip(ShipClass.PlanetBreaker, techLevel = 1)
    let squadron = newSquadron(pbShip, "house-other_sq1", "house-other", SystemId(1))

    state.fleets[fleetId] = Fleet(
      id: fleetId,
      owner: "house-other",
      location: SystemId(1),
      squadrons: @[squadron],
      spaceLiftShips: @[],
      status: FleetStatus.Active,
      autoBalanceSquadrons: true
    )

    let count = countPlanetBreakersInFleets(state, "house-test")
    check count == 2  # Should not count the other house's PB

suite "Capacity Analysis":
  test "No violation - within capacity":
    var state = createTestGameState("house-test", colonyCount = 5, pbsInFleets = 3)
    let status = analyzeCapacity(state, "house-test")

    check status.capacityType == CapacityType.PlanetBreaker
    check status.current == 3
    check status.maximum == 5
    check status.excess == 0
    check status.severity == ViolationSeverity.None

  test "At capacity - no violation":
    var state = createTestGameState("house-test", colonyCount = 3, pbsInFleets = 3)
    let status = analyzeCapacity(state, "house-test")

    check status.current == 3
    check status.maximum == 3
    check status.excess == 0
    check status.severity == ViolationSeverity.None

  test "Over capacity - critical violation":
    var state = createTestGameState("house-test", colonyCount = 2, pbsInFleets = 5)
    let status = analyzeCapacity(state, "house-test")

    check status.current == 5
    check status.maximum == 2
    check status.excess == 3
    check status.severity == ViolationSeverity.Critical

  test "Lost all colonies - all PBs in violation":
    var state = createTestGameState("house-test", colonyCount = 0, pbsInFleets = 3)
    let status = analyzeCapacity(state, "house-test")

    check status.current == 3
    check status.maximum == 0
    check status.excess == 3
    check status.severity == ViolationSeverity.Critical

suite "Check Violations Batch":
  test "Find violations across multiple houses":
    var state = GameState(
      turn: 10,
      houses: initTable[HouseId, House](),
      colonies: initTable[SystemId, Colony](),
      fleets: initTable[FleetId, Fleet]()
    )

    # House 1: No violation (3 colonies, 2 PBs)
    state.houses["house1"] = createTestHouse("house1", 3)
    for i in 1..3:
      state.colonies[SystemId(i)] = Colony(systemId: SystemId(i), owner: "house1")

    for i in 1..2:
      let fleetId = FleetId("house1_fleet" & $i)
      let pbShip = newEnhancedShip(ShipClass.PlanetBreaker, techLevel = 1)
      let squadron = newSquadron(pbShip, "house1_sq" & $i, "house1", SystemId(1))
      state.fleets[fleetId] = Fleet(
        id: fleetId, owner: "house1", location: SystemId(1),
        squadrons: @[squadron], spaceLiftShips: @[],
        status: FleetStatus.Active, autoBalanceSquadrons: true
      )

    # House 2: Violation (2 colonies, 5 PBs)
    state.houses["house2"] = createTestHouse("house2", 2)
    for i in 10..11:
      state.colonies[SystemId(i)] = Colony(systemId: SystemId(i), owner: "house2")

    for i in 1..5:
      let fleetId = FleetId("house2_fleet" & $i)
      let pbShip = newEnhancedShip(ShipClass.PlanetBreaker, techLevel = 1)
      let squadron = newSquadron(pbShip, "house2_sq" & $i, "house2", SystemId(10))
      state.fleets[fleetId] = Fleet(
        id: fleetId, owner: "house2", location: SystemId(10),
        squadrons: @[squadron], spaceLiftShips: @[],
        status: FleetStatus.Active, autoBalanceSquadrons: true
      )

    let violations = checkViolations(state)

    check violations.len == 1
    check violations[0].entityId == "house2"
    check violations[0].excess == 3

suite "Enforcement Planning":
  test "Plan enforcement for violation":
    var state = createTestGameState("house-test", colonyCount = 2, pbsInFleets = 5)
    let violation = analyzeCapacity(state, "house-test")
    let action = planEnforcement(state, violation)

    check action.actionType == "auto_scrap"
    check action.affectedUnits.len == 3  # 3 excess PBs
    check action.entityId == "house-test"

  test "No enforcement during grace period":
    # Planet-breakers have no grace period, but test severity check
    var state = createTestGameState("house-test", colonyCount = 3, pbsInFleets = 3)
    let violation = analyzeCapacity(state, "house-test")
    let action = planEnforcement(state, violation)

    check action.actionType == ""
    check action.affectedUnits.len == 0

  test "Scrap oldest squadrons first (by ID)":
    var state = createTestGameState("house-test", colonyCount = 1, pbsInFleets = 0)

    # Add 3 planet-breakers with specific IDs
    let fleetId = FleetId("house-test_fleet1")
    let pb1 = newEnhancedShip(ShipClass.PlanetBreaker, techLevel = 1)
    let pb2 = newEnhancedShip(ShipClass.PlanetBreaker, techLevel = 1)
    let pb3 = newEnhancedShip(ShipClass.PlanetBreaker, techLevel = 1)

    let sq1 = newSquadron(pb1, "house-test_sq_001", "house-test", SystemId(1))
    let sq2 = newSquadron(pb2, "house-test_sq_003", "house-test", SystemId(1))
    let sq3 = newSquadron(pb3, "house-test_sq_002", "house-test", SystemId(1))

    state.fleets[fleetId] = Fleet(
      id: fleetId,
      owner: "house-test",
      location: SystemId(1),
      squadrons: @[sq1, sq2, sq3],
      spaceLiftShips: @[],
      status: FleetStatus.Active,
      autoBalanceSquadrons: true
    )

    let violation = analyzeCapacity(state, "house-test")
    check violation.excess == 2

    let action = planEnforcement(state, violation)
    check action.affectedUnits.len == 2
    check "house-test_sq_001" in action.affectedUnits  # Lowest ID
    check "house-test_sq_002" in action.affectedUnits  # Second lowest

suite "Enforcement Application":
  test "Apply enforcement scraps planet-breakers":
    var state = createTestGameState("house-test", colonyCount = 1, pbsInFleets = 3)

    let violation = analyzeCapacity(state, "house-test")
    check violation.excess == 2

    let action = planEnforcement(state, violation)
    applyEnforcement(state, action)

    # Should have scrapped 2 PBs, leaving 1
    let remaining = countPlanetBreakersInFleets(state, "house-test")
    check remaining == 1

  test "Apply enforcement removes from multiple fleets":
    var state = createTestGameState("house-test", colonyCount = 1, pbsInFleets = 0)

    # Add 3 PBs across 2 fleets
    for i in 1..2:
      let fleetId = FleetId("house-test_fleet" & $i)
      let pbShip = newEnhancedShip(ShipClass.PlanetBreaker, techLevel = 1)
      let squadron = newSquadron(pbShip, "house-test_sq_" & $i, "house-test", SystemId(1))

      state.fleets[fleetId] = Fleet(
        id: fleetId,
        owner: "house-test",
        location: SystemId(1),
        squadrons: @[squadron],
        spaceLiftShips: @[],
        status: FleetStatus.Active,
        autoBalanceSquadrons: true
      )

    let fleetId3 = FleetId("house-test_fleet3")
    let pbShip3 = newEnhancedShip(ShipClass.PlanetBreaker, techLevel = 1)
    let squadron3 = newSquadron(pbShip3, "house-test_sq_3", "house-test", SystemId(1))
    state.fleets[fleetId3] = Fleet(
      id: fleetId3,
      owner: "house-test",
      location: SystemId(1),
      squadrons: @[squadron3],
      spaceLiftShips: @[],
      status: FleetStatus.Active,
      autoBalanceSquadrons: true
    )

    let violation = analyzeCapacity(state, "house-test")
    let action = planEnforcement(state, violation)
    applyEnforcement(state, action)

    let remaining = countPlanetBreakersInFleets(state, "house-test")
    check remaining == 1

suite "Process Capacity Enforcement":
  test "Full workflow - detect and enforce violations":
    var state = createTestGameState("house-test", colonyCount = 2, pbsInFleets = 5)

    let initialCount = countPlanetBreakersInFleets(state, "house-test")
    check initialCount == 5

    let actions = processCapacityEnforcement(state)

    check actions.len == 1
    check actions[0].actionType == "auto_scrap"
    check actions[0].affectedUnits.len == 3

    let finalCount = countPlanetBreakersInFleets(state, "house-test")
    check finalCount == 2  # Reduced to match colony count

  test "No enforcement when within capacity":
    var state = createTestGameState("house-test", colonyCount = 5, pbsInFleets = 3)

    let actions = processCapacityEnforcement(state)

    check actions.len == 0

suite "Can Build Planet Breaker Check":
  test "Can build when under capacity":
    var state = createTestGameState("house-test", colonyCount = 5, pbsInFleets = 3)
    check planet_breakers.canBuildPlanetBreaker(state, "house-test") == true

  test "Cannot build when at capacity":
    var state = createTestGameState("house-test", colonyCount = 3, pbsInFleets = 3)
    check planet_breakers.canBuildPlanetBreaker(state, "house-test") == false

  test "Cannot build when over capacity":
    var state = createTestGameState("house-test", colonyCount = 2, pbsInFleets = 5)
    check planet_breakers.canBuildPlanetBreaker(state, "house-test") == false

  test "Can build with no colonies and no PBs":
    var state = createTestGameState("house-test", colonyCount = 0, pbsInFleets = 0)
    check planet_breakers.canBuildPlanetBreaker(state, "house-test") == false  # Can't build with 0 colonies

when isMainModule:
  echo "Running planet-breaker capacity enforcement tests..."
