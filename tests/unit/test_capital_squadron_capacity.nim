## Unit Tests for Capital Squadron Capacity Enforcement
##
## Tests complete capital squadron capacity system per reference.md Table 10.5
## Formula: max(8, floor(Total_House_IU ÷ 100) × 2)

import std/[unittest, tables, options, math]
import ../../src/engine/economy/capacity/capital_squadrons
import ../../src/engine/economy/capacity/types
import ../../src/engine/economy/types as econ_types
import ../../src/engine/[gamestate, fleet, squadron]
import ../../src/common/types/core
import ../../src/common/types/units

proc createTestHouse(id: string): House =
  result = House(
    id: id,
    name: "Test House " & id,
    treasury: 10000,
    techTree: TechTree(),
    eliminated: false
  )

proc createTestGameState(houseId: HouseId, coloniesWithIU: seq[int], capitalShips: seq[ShipClass] = @[]): GameState =
  var state = GameState(
    turn: 10,
    houses: initTable[HouseId, House](),
    colonies: initTable[SystemId, Colony](),
    fleets: initTable[FleetId, Fleet]()
  )

  # Add house
  state.houses[houseId] = createTestHouse(houseId)

  # Add colonies with specified IU
  for i, iu in coloniesWithIU:
    let systemId = SystemId(i + 1)
    state.colonies[systemId] = Colony(
      systemId: systemId,
      owner: houseId,
      populationUnits: 100,
      population: 100,
      infrastructure: iu div 10,  # Approximate infrastructure
      industrial: econ_types.IndustrialUnits(
        units: iu
      )
    )

  # Add capital ships in fleets if requested
  if capitalShips.len > 0:
    for i, shipClass in capitalShips:
      let fleetId = FleetId($houseId & "_fleet" & $(i + 1))
      let ship = newEnhancedShip(shipClass, techLevel = 1)
      let squadron = newSquadron(ship, $houseId & "_sq" & $(i + 1), houseId, SystemId(1))

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

suite "Capital Ship Detection":
  test "Heavy Cruiser is capital ship (CR=7)":
    check isCapitalShip(ShipClass.HeavyCruiser) == true

  test "Battle Cruiser is capital ship (CR=8)":
    check isCapitalShip(ShipClass.BattleCruiser) == true

  test "Battleship is capital ship (CR=10)":
    check isCapitalShip(ShipClass.Battleship) == true

  test "Dreadnought is capital ship (CR=12)":
    check isCapitalShip(ShipClass.Dreadnought) == true

  test "Super Dreadnought is capital ship (CR=14)":
    check isCapitalShip(ShipClass.SuperDreadnought) == true

  test "Carrier is capital ship (CR=8)":
    check isCapitalShip(ShipClass.Carrier) == true

  test "Super Carrier is capital ship (CR=10)":
    check isCapitalShip(ShipClass.SuperCarrier) == true

  test "Raider is capital ship (CR=8)":
    check isCapitalShip(ShipClass.Raider) == true

  test "Light Cruiser is NOT capital ship (CR=6)":
    check isCapitalShip(ShipClass.LightCruiser) == false

  test "Destroyer is NOT capital ship (CR=4)":
    check isCapitalShip(ShipClass.Destroyer) == false

  test "Fighter is NOT capital ship":
    check isCapitalShip(ShipClass.Fighter) == false

  test "Scout is NOT capital ship":
    check isCapitalShip(ShipClass.Scout) == false

suite "Max Capacity Calculation":
  test "Formula: max(8, floor(IU/100) × 2)":
    check calculateMaxCapitalSquadrons(0) == 8      # Minimum
    check calculateMaxCapitalSquadrons(50) == 8     # Below minimum
    check calculateMaxCapitalSquadrons(100) == 8    # At minimum
    check calculateMaxCapitalSquadrons(400) == 8    # Still at minimum (400/100*2 = 8)
    check calculateMaxCapitalSquadrons(500) == 10   # Above minimum (500/100*2 = 10)
    check calculateMaxCapitalSquadrons(1000) == 20  # 1000/100*2 = 20
    check calculateMaxCapitalSquadrons(1500) == 30  # 1500/100*2 = 30
    check calculateMaxCapitalSquadrons(2500) == 50  # 2500/100*2 = 50

  test "Formula uses floor for fractional IU":
    check calculateMaxCapitalSquadrons(449) == 8    # floor(449/100)*2 = 8
    check calculateMaxCapitalSquadrons(450) == 8    # floor(450/100)*2 = 8
    check calculateMaxCapitalSquadrons(499) == 8    # floor(499/100)*2 = 8
    check calculateMaxCapitalSquadrons(550) == 10   # floor(550/100)*2 = 10
    check calculateMaxCapitalSquadrons(599) == 10   # floor(599/100)*2 = 10

suite "Total House IU Calculation":
  test "Sum IU across all colonies":
    let state = createTestGameState("house-test", @[100, 200, 300])
    let totalIU = getTotalHouseIndustrialUnits(state, "house-test")
    check totalIU == 600

  test "Single colony":
    let state = createTestGameState("house-test", @[500])
    let totalIU = getTotalHouseIndustrialUnits(state, "house-test")
    check totalIU == 500

  test "No colonies = 0 IU":
    let state = createTestGameState("house-test", @[])
    let totalIU = getTotalHouseIndustrialUnits(state, "house-test")
    check totalIU == 0

  test "Excludes other house colonies":
    var state = createTestGameState("house-test", @[500])
    # Add colony for different house
    state.colonies[SystemId(99)] = Colony(
      systemId: SystemId(99),
      owner: "house-other",
      populationUnits: 100,
      population: 100,
      infrastructure: 50,
    )
    let totalIU = getTotalHouseIndustrialUnits(state, "house-test")
    check totalIU == 500  # Should not include other house's 1000 IU

suite "Count Capital Squadrons in Fleets":
  test "Count capital ships only":
    let state = createTestGameState("house-test", @[1000],
      @[ShipClass.Battleship, ShipClass.HeavyCruiser, ShipClass.Carrier])
    let count = countCapitalSquadronsInFleets(state, "house-test")
    check count == 3

  test "Exclude non-capital ships":
    var state = createTestGameState("house-test", @[1000],
      @[ShipClass.Battleship, ShipClass.LightCruiser, ShipClass.Destroyer])
    let count = countCapitalSquadronsInFleets(state, "house-test")
    check count == 1  # Only Battleship

  test "Exclude fighters and scouts":
    var state = createTestGameState("house-test", @[1000],
      @[ShipClass.Battleship, ShipClass.Fighter, ShipClass.Scout])
    let count = countCapitalSquadronsInFleets(state, "house-test")
    check count == 1  # Only Battleship

  test "Count Raider as capital ship":
    let state = createTestGameState("house-test", @[1000],
      @[ShipClass.Raider])
    let count = countCapitalSquadronsInFleets(state, "house-test")
    check count == 1

  test "Exclude other house capital ships":
    var state = createTestGameState("house-test", @[1000],
      @[ShipClass.Battleship])

    # Add capital ship for different house
    let fleetId = FleetId("house-other_fleet1")
    let ship = newEnhancedShip(ShipClass.Dreadnought, techLevel = 1)
    let squadron = newSquadron(ship, "house-other_sq1", "house-other", SystemId(1))

    state.fleets[fleetId] = Fleet(
      id: fleetId,
      owner: "house-other",
      location: SystemId(1),
      squadrons: @[squadron],
      spaceLiftShips: @[],
      status: FleetStatus.Active,
      autoBalanceSquadrons: true
    )

    let count = countCapitalSquadronsInFleets(state, "house-test")
    check count == 1  # Should not count other house's Dreadnought

suite "Capacity Analysis":
  test "No violation - within capacity":
    let state = createTestGameState("house-test", @[1000],  # 1000 IU = 20 cap
      @[ShipClass.Battleship, ShipClass.HeavyCruiser])  # 2 ships
    let status = analyzeCapacity(state, "house-test")

    check status.capacityType == CapacityType.CapitalSquadron
    check status.current == 2
    check status.maximum == 20
    check status.excess == 0
    check status.severity == ViolationSeverity.None

  test "At capacity - no violation":
    let state = createTestGameState("house-test", @[400],  # 400 IU = 8 cap (minimum)
      @[ShipClass.Battleship, ShipClass.HeavyCruiser, ShipClass.BattleCruiser,
        ShipClass.Carrier, ShipClass.Dreadnought, ShipClass.Raider,
        ShipClass.SuperDreadnought, ShipClass.SuperCarrier])  # 8 ships
    let status = analyzeCapacity(state, "house-test")

    check status.current == 8
    check status.maximum == 8
    check status.excess == 0
    check status.severity == ViolationSeverity.None

  test "Over capacity - critical violation":
    let state = createTestGameState("house-test", @[400],  # 400 IU = 8 cap
      @[ShipClass.Battleship, ShipClass.HeavyCruiser, ShipClass.BattleCruiser,
        ShipClass.Carrier, ShipClass.Dreadnought, ShipClass.Raider,
        ShipClass.SuperDreadnought, ShipClass.SuperCarrier,
        ShipClass.Battleship, ShipClass.Battleship])  # 10 ships
    let status = analyzeCapacity(state, "house-test")

    check status.current == 10
    check status.maximum == 8
    check status.excess == 2
    check status.severity == ViolationSeverity.Critical

  test "Lost all IU but have capital ships":
    let state = createTestGameState("house-test", @[],  # 0 IU = 8 cap (minimum)
      @[ShipClass.Battleship, ShipClass.HeavyCruiser, ShipClass.BattleCruiser,
        ShipClass.Carrier, ShipClass.Dreadnought, ShipClass.Raider,
        ShipClass.SuperDreadnought, ShipClass.SuperCarrier,
        ShipClass.Battleship, ShipClass.Battleship])  # 10 ships
    let status = analyzeCapacity(state, "house-test")

    check status.current == 10
    check status.maximum == 8  # Minimum is always 8
    check status.excess == 2
    check status.severity == ViolationSeverity.Critical

suite "Check Violations Batch":
  test "Find violations across multiple houses":
    var state = GameState(
      turn: 10,
      houses: initTable[HouseId, House](),
      colonies: initTable[SystemId, Colony](),
      fleets: initTable[FleetId, Fleet]()
    )

    # House 1: No violation (1000 IU = 20 cap, 5 ships)
    state.houses["house1"] = createTestHouse("house1")
    state.colonies[SystemId(1)] = Colony(
      systemId: SystemId(1), owner: "house1",
      populationUnits: 100, population: 100, infrastructure: 100,
    )

    for i in 1..5:
      let fleetId = FleetId("house1_fleet" & $i)
      let ship = newEnhancedShip(ShipClass.Battleship, techLevel = 1)
      let squadron = newSquadron(ship, "house1_sq" & $i, "house1", SystemId(1))
      state.fleets[fleetId] = Fleet(
        id: fleetId, owner: "house1", location: SystemId(1),
        squadrons: @[squadron], spaceLiftShips: @[],
        status: FleetStatus.Active, autoBalanceSquadrons: true
      )

    # House 2: Violation (400 IU = 8 cap, 12 ships)
    state.houses["house2"] = createTestHouse("house2")
    state.colonies[SystemId(10)] = Colony(
      systemId: SystemId(10), owner: "house2",
      populationUnits: 100, population: 100, infrastructure: 40,
    )

    for i in 1..12:
      let fleetId = FleetId("house2_fleet" & $i)
      let ship = newEnhancedShip(ShipClass.HeavyCruiser, techLevel = 1)
      let squadron = newSquadron(ship, "house2_sq" & $i, "house2", SystemId(10))
      state.fleets[fleetId] = Fleet(
        id: fleetId, owner: "house2", location: SystemId(10),
        squadrons: @[squadron], spaceLiftShips: @[],
        status: FleetStatus.Active, autoBalanceSquadrons: true
      )

    let violations = checkViolations(state)

    check violations.len == 1
    check violations[0].entityId == "house2"
    check violations[0].excess == 4

suite "Squadron Prioritization":
  test "Crippled ships removed first":
    var state = createTestGameState("house-test", @[400],  # 8 cap
      @[ShipClass.Battleship, ShipClass.HeavyCruiser, ShipClass.Carrier,
        ShipClass.Dreadnought, ShipClass.Raider])  # 5 ships

    # Cripple the Raider and Carrier
    for fleetId, fleet in state.fleets.mpairs:
      for squadron in fleet.squadrons.mitems:
        if squadron.flagship.shipClass == ShipClass.Raider or
           squadron.flagship.shipClass == ShipClass.Carrier:
          squadron.flagship.isCrippled = true

    # Reduce IU to force violation (200 IU = 4 cap, need to remove 1)
    state.colonies[SystemId(1)].industrial.units = 200

    let violation = analyzeCapacity(state, "house-test")
    check violation.excess == 1

    let action = planEnforcement(state, violation)
    check action.affectedUnits.len == 1
    # Should be one of the crippled ships
    var foundCrippled = false
    for fleetId, fleet in state.fleets:
      for squadron in fleet.squadrons:
        if squadron.id in action.affectedUnits:
          check squadron.flagship.isCrippled == true
          foundCrippled = true
    check foundCrippled == true

  test "Lowest AS removed among non-crippled":
    var state = createTestGameState("house-test", @[300],  # 6 cap
      @[ShipClass.HeavyCruiser,    # AS=12
        ShipClass.Battleship,       # AS=20
        ShipClass.Dreadnought])     # AS=28

    # Reduce IU to force violation (150 IU = 2 cap, need to remove 1)
    state.colonies[SystemId(1)].industrial.units = 150

    let violation = analyzeCapacity(state, "house-test")
    check violation.excess == 1

    let action = planEnforcement(state, violation)
    check action.affectedUnits.len == 1

    # Should remove HeavyCruiser (lowest AS=12)
    var foundHeavyCruiser = false
    for fleetId, fleet in state.fleets:
      for squadron in fleet.squadrons:
        if squadron.id in action.affectedUnits:
          check squadron.flagship.shipClass == ShipClass.HeavyCruiser
          foundHeavyCruiser = true
    check foundHeavyCruiser == true

suite "Salvage Value Calculation":
  test "50% of build cost":
    # Battleship build cost = 150
    let salvage = calculateSalvageValue(ShipClass.Battleship)
    check salvage == 75  # 50% of 150

  test "Various ship classes":
    # HeavyCruiser build cost = 80
    check calculateSalvageValue(ShipClass.HeavyCruiser) == 40

    # Dreadnought build cost = 200
    check calculateSalvageValue(ShipClass.Dreadnought) == 100

    # Carrier build cost = 120
    check calculateSalvageValue(ShipClass.Carrier) == 60

suite "Enforcement Planning":
  test "Plan enforcement for violation":
    let state = createTestGameState("house-test", @[200],  # 4 cap
      @[ShipClass.Battleship, ShipClass.HeavyCruiser, ShipClass.BattleCruiser,
        ShipClass.Carrier, ShipClass.Dreadnought, ShipClass.Raider])  # 6 ships
    let violation = analyzeCapacity(state, "house-test")
    let action = planEnforcement(state, violation)

    check action.actionType == "auto_scrap"
    check action.affectedUnits.len == 2  # 2 excess ships
    check action.entityId == "house-test"

  test "No enforcement when within capacity":
    let state = createTestGameState("house-test", @[1000],  # 20 cap
      @[ShipClass.Battleship, ShipClass.HeavyCruiser])  # 2 ships
    let violation = analyzeCapacity(state, "house-test")
    let action = planEnforcement(state, violation)

    check action.actionType == ""
    check action.affectedUnits.len == 0

suite "Enforcement Application":
  test "Apply enforcement scraps capital squadrons":
    var state = createTestGameState("house-test", @[200],  # 4 cap
      @[ShipClass.Battleship, ShipClass.HeavyCruiser, ShipClass.BattleCruiser,
        ShipClass.Carrier, ShipClass.Dreadnought])  # 5 ships

    let violation = analyzeCapacity(state, "house-test")
    check violation.excess == 1

    let action = planEnforcement(state, violation)
    applyEnforcement(state, action)

    # Should have scrapped 1 ship, leaving 4
    let remaining = countCapitalSquadronsInFleets(state, "house-test")
    check remaining == 4

  test "Apply enforcement credits salvage to treasury":
    var state = createTestGameState("house-test", @[200],  # 4 cap
      @[ShipClass.Battleship, ShipClass.HeavyCruiser, ShipClass.BattleCruiser,
        ShipClass.Carrier, ShipClass.Dreadnought])  # 5 ships

    let initialTreasury = state.houses["house-test"].treasury

    let violation = analyzeCapacity(state, "house-test")
    let action = planEnforcement(state, violation)
    applyEnforcement(state, action)

    let finalTreasury = state.houses["house-test"].treasury
    check finalTreasury > initialTreasury  # Should have received salvage

  test "Apply enforcement removes from multiple fleets":
    var state = createTestGameState("house-test", @[200],  # 4 cap
      @[])

    # Add 6 ships across 6 fleets
    for i in 1..6:
      let fleetId = FleetId("house-test_fleet" & $i)
      let ship = newEnhancedShip(ShipClass.HeavyCruiser, techLevel = 1)
      let squadron = newSquadron(ship, "house-test_sq" & $i, "house-test", SystemId(1))

      state.fleets[fleetId] = Fleet(
        id: fleetId,
        owner: "house-test",
        location: SystemId(1),
        squadrons: @[squadron],
        spaceLiftShips: @[],
        status: FleetStatus.Active,
        autoBalanceSquadrons: true
      )

    let violation = analyzeCapacity(state, "house-test")
    let action = planEnforcement(state, violation)
    applyEnforcement(state, action)

    let remaining = countCapitalSquadronsInFleets(state, "house-test")
    check remaining == 4

suite "Process Capacity Enforcement":
  test "Full workflow - detect and enforce violations":
    var state = createTestGameState("house-test", @[200],  # 4 cap
      @[ShipClass.Battleship, ShipClass.HeavyCruiser, ShipClass.BattleCruiser,
        ShipClass.Carrier, ShipClass.Dreadnought, ShipClass.Raider])  # 6 ships

    let initialCount = countCapitalSquadronsInFleets(state, "house-test")
    check initialCount == 6

    let actions = processCapacityEnforcement(state)

    check actions.len == 1
    check actions[0].actionType == "auto_scrap"
    check actions[0].affectedUnits.len == 2

    let finalCount = countCapitalSquadronsInFleets(state, "house-test")
    check finalCount == 4  # Reduced to match capacity

  test "No enforcement when within capacity":
    var state = createTestGameState("house-test", @[1000],  # 20 cap
      @[ShipClass.Battleship, ShipClass.HeavyCruiser])  # 2 ships

    let actions = processCapacityEnforcement(state)

    check actions.len == 0

suite "Can Build Capital Ship Check":
  test "Can build when under capacity":
    var state = createTestGameState("house-test", @[1000],  # 20 cap
      @[ShipClass.Battleship, ShipClass.HeavyCruiser])  # 2 ships
    check canBuildCapitalShip(state, "house-test") == true

  test "Cannot build when at capacity":
    let ships = @[ShipClass.Battleship, ShipClass.HeavyCruiser, ShipClass.BattleCruiser,
                  ShipClass.Carrier, ShipClass.Dreadnought, ShipClass.Raider,
                  ShipClass.SuperDreadnought, ShipClass.SuperCarrier]  # 8 ships
    var state = createTestGameState("house-test", @[400], ships)  # 8 cap
    check canBuildCapitalShip(state, "house-test") == false

  test "Cannot build when over capacity":
    let ships = @[ShipClass.Battleship, ShipClass.HeavyCruiser, ShipClass.BattleCruiser,
                  ShipClass.Carrier, ShipClass.Dreadnought, ShipClass.Raider,
                  ShipClass.SuperDreadnought, ShipClass.SuperCarrier,
                  ShipClass.Battleship, ShipClass.Battleship]  # 10 ships
    var state = createTestGameState("house-test", @[400], ships)  # 8 cap
    check canBuildCapitalShip(state, "house-test") == false

  test "Can build with no IU if under minimum":
    var state = createTestGameState("house-test", @[],  # 0 IU = 8 cap (minimum)
      @[ShipClass.Battleship])  # 1 ship
    check canBuildCapitalShip(state, "house-test") == true

suite "Fleet Safety":
  test "Empty fleets remain valid after squadron removal":
    var state = createTestGameState("house-test", @[200],  # 4 cap
      @[])

    # Add 6 ships, each in its own fleet
    for i in 1..6:
      let fleetId = FleetId("house-test_fleet" & $i)
      let ship = newEnhancedShip(ShipClass.HeavyCruiser, techLevel = 1)
      let squadron = newSquadron(ship, "house-test_sq" & $i, "house-test", SystemId(1))

      state.fleets[fleetId] = Fleet(
        id: fleetId,
        owner: "house-test",
        location: SystemId(1),
        squadrons: @[squadron],
        spaceLiftShips: @[],
        status: FleetStatus.Active,
        autoBalanceSquadrons: true
      )

    # This should remove 2 ships, leaving 4
    discard processCapacityEnforcement(state)

    # Verify fleets still exist (some may be empty)
    var emptyFleetCount = 0
    for fleetId, fleet in state.fleets:
      if fleet.squadrons.len == 0:
        emptyFleetCount += 1

    check emptyFleetCount == 2  # 2 fleets should now be empty

when isMainModule:
  echo "Running capital squadron capacity enforcement tests..."
