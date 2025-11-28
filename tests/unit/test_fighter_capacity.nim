## Unit Tests for Fighter Squadron Capacity Enforcement
##
## Tests complete fighter capacity system per assets.md:2.4.1

import std/[unittest, tables, math]
import ../../src/engine/combat/fighter_capacity
import ../../src/engine/[gamestate, state_helpers]
import ../../src/common/types/core

proc createTestColony(pu: int, fdLevel: int = 1, fighters: int = 0, starbases: int = 0): Colony =
  result = Colony(
    systemId: "system-1",
    owner: "house-test",
    populationUnits: pu,
    fighterSquadrons: @[],
    starbases: @[],
    capacityViolation: CapacityViolationTracking()
  )

  # Add fighters
  for i in 1..fighters:
    result.fighterSquadrons.add(FighterSquadron(
      id: "FS-" & $i,
      commissionedTurn: i,
      isCrippled: false
    ))

  # Add starbases
  for i in 1..starbases:
    result.starbases.add(Starbase(
      id: "SB-" & $i,
      isCrippled: false
    ))

suite "Fighter Doctrine Multiplier":
  test "FD I multiplier":
    let mult = getFighterDoctrineMultiplier(1)
    check mult == 1.0

  test "FD II multiplier":
    let mult = getFighterDoctrineMultiplier(2)
    check mult == 1.5

  test "FD III multiplier":
    let mult = getFighterDoctrineMultiplier(3)
    check mult == 2.0

  test "Invalid FD level defaults to 1.0":
    let mult = getFighterDoctrineMultiplier(0)
    check mult == 1.0
    let mult2 = getFighterDoctrineMultiplier(99)
    check mult2 == 1.0

suite "Max Fighter Capacity Calculation":
  test "100 PU with FD I = 1 FS":
    # floor(100/100) × 1.0 = 1
    let cap = calculateMaxFighterCapacity(100, fdLevel=1)
    check cap == 1

  test "200 PU with FD I = 2 FS":
    let cap = calculateMaxFighterCapacity(200, fdLevel=1)
    check cap == 2

  test "99 PU with FD I = 0 FS":
    # floor(99/100) × 1.0 = 0
    let cap = calculateMaxFighterCapacity(99, fdLevel=1)
    check cap == 0

  test "100 PU with FD II = 1 FS":
    # floor(100/100) × 1.5 = 1 × 1.5 = 1
    let cap = calculateMaxFighterCapacity(100, fdLevel=2)
    check cap == 1

  test "200 PU with FD II = 3 FS":
    # floor(200/100) × 1.5 = 2 × 1.5 = 3
    let cap = calculateMaxFighterCapacity(200, fdLevel=2)
    check cap == 3

  test "300 PU with FD II = 4 FS":
    # floor(300/100) × 1.5 = 3 × 1.5 = 4 (floor)
    let cap = calculateMaxFighterCapacity(300, fdLevel=2)
    check cap == 4

  test "100 PU with FD III = 2 FS":
    # floor(100/100) × 2.0 = 2
    let cap = calculateMaxFighterCapacity(100, fdLevel=3)
    check cap == 2

  test "500 PU with FD III = 10 FS":
    # floor(500/100) × 2.0 = 10
    let cap = calculateMaxFighterCapacity(500, fdLevel=3)
    check cap == 10

suite "Required Starbases Calculation":
  test "0 fighters require 0 starbases":
    let required = calculateRequiredStarbases(0)
    check required == 0

  test "1 fighter requires 1 starbase":
    # ceil(1/5) = 1
    let required = calculateRequiredStarbases(1)
    check required == 1

  test "5 fighters require 1 starbase":
    # ceil(5/5) = 1
    let required = calculateRequiredStarbases(5)
    check required == 1

  test "6 fighters require 2 starbases":
    # ceil(6/5) = 2
    let required = calculateRequiredStarbases(6)
    check required == 2

  test "10 fighters require 2 starbases":
    # ceil(10/5) = 2
    let required = calculateRequiredStarbases(10)
    check required == 2

  test "11 fighters require 3 starbases":
    # ceil(11/5) = 3
    let required = calculateRequiredStarbases(11)
    check required == 3

suite "Capacity Analysis":
  test "No violation - within limits":
    var state = GameState()
    state.houses = initTable[HouseId, House]()
    state.houses["house-test"] = House(
      id: "house-test",
      techTree: TechTree(levels: TechLevels(fighterDoctrine: 1))
    )

    # 200 PU = 2 FS capacity, have 1 FS, need 1 SB, have 1 SB
    let colony = createTestColony(pu=200, fdLevel=1, fighters=1, starbases=1)
    let status = analyzeCapacity(state, colony, "house-test")

    check status.violationType == ViolationType.None
    check status.currentFighters == 1
    check status.maxCapacity == 2
    check status.excessFighters == 0

  test "Infrastructure violation - not enough starbases":
    var state = GameState()
    state.houses = initTable[HouseId, House]()
    state.houses["house-test"] = House(
      id: "house-test",
      techTree: TechTree(levels: TechLevels(fighterDoctrine: 1))
    )

    # Have 6 fighters, need 2 starbases, only have 1
    let colony = createTestColony(pu=1000, fdLevel=1, fighters=6, starbases=1)
    let status = analyzeCapacity(state, colony, "house-test")

    check status.violationType == ViolationType.Infrastructure
    check status.requiredStarbases == 2
    check status.operationalStarbases == 1
    # Excess = 6 - (1 × 5) = 1
    check status.excessFighters == 1

  test "Population violation - too many fighters for PU":
    var state = GameState()
    state.houses = initTable[HouseId, House]()
    state.houses["house-test"] = House(
      id: "house-test",
      techTree: TechTree(levels: TechLevels(fighterDoctrine: 1))
    )

    # 100 PU = 1 FS max, have 3 FS, have 1 SB (enough for 5)
    let colony = createTestColony(pu=100, fdLevel=1, fighters=3, starbases=1)
    let status = analyzeCapacity(state, colony, "house-test")

    check status.violationType == ViolationType.Population
    check status.maxCapacity == 1
    check status.currentFighters == 3
    check status.excessFighters == 2

  test "Infrastructure violation takes priority over population":
    var state = GameState()
    state.houses = initTable[HouseId, House]()
    state.houses["house-test"] = House(
      id: "house-test",
      techTree: TechTree(levels: TechLevels(fighterDoctrine: 1))
    )

    # Both violations: too many fighters AND not enough starbases
    # 100 PU = 1 FS max, have 10 FS, need 2 SB, have 0 SB
    let colony = createTestColony(pu=100, fdLevel=1, fighters=10, starbases=0)
    let status = analyzeCapacity(state, colony, "house-test")

    # Infrastructure should be checked first
    check status.violationType == ViolationType.Infrastructure

suite "Check Violations Batch":
  test "Find all violations across colonies":
    var state = GameState()
    state.houses = initTable[HouseId, House]()
    state.colonies = initTable[SystemId, Colony]()

    state.houses["house-test"] = House(
      id: "house-test",
      techTree: TechTree(levels: TechLevels(fighterDoctrine: 1))
    )

    # Colony 1: No violation
    var colony1 = createTestColony(pu=200, fdLevel=1, fighters=1, starbases=1)
    colony1.systemId = "system-1"
    colony1.owner = "house-test"
    state.colonies["system-1"] = colony1

    # Colony 2: Infrastructure violation
    var colony2 = createTestColony(pu=1000, fdLevel=1, fighters=10, starbases=1)
    colony2.systemId = "system-2"
    colony2.owner = "house-test"
    state.colonies["system-2"] = colony2

    # Colony 3: Population violation
    var colony3 = createTestColony(pu=100, fdLevel=1, fighters=3, starbases=1)
    colony3.systemId = "system-3"
    colony3.owner = "house-test"
    state.colonies["system-3"] = colony3

    let violations = checkViolations(state)

    check violations.len == 2  # Two violations found

suite "Violation Tracking":
  test "New violation starts grace period":
    var state = GameState()
    state.turn = 10
    state.houses = initTable[HouseId, House]()
    state.colonies = initTable[SystemId, Colony]()

    state.houses["house-test"] = House(
      id: "house-test",
      techTree: TechTree(levels: TechLevels(fighterDoctrine: 1))
    )

    var colony = createTestColony(pu=100, fdLevel=1, fighters=6, starbases=0)
    colony.systemId = "system-1"
    colony.owner = "house-test"
    state.colonies["system-1"] = colony

    let status = analyzeCapacity(state, colony, "house-test")
    updateViolationTracking(state, status)

    check state.colonies["system-1"].capacityViolation.active == true
    check state.colonies["system-1"].capacityViolation.turnsRemaining == 2
    check state.colonies["system-1"].capacityViolation.violationTurn == 10

  test "Existing violation decrements grace period":
    var state = GameState()
    state.turn = 10
    state.houses = initTable[HouseId, House]()
    state.colonies = initTable[SystemId, Colony]()

    state.houses["house-test"] = House(
      id: "house-test",
      techTree: TechTree(levels: TechLevels(fighterDoctrine: 1))
    )

    var colony = createTestColony(pu=100, fdLevel=1, fighters=6, starbases=0)
    colony.systemId = "system-1"
    colony.owner = "house-test"
    colony.capacityViolation.active = true
    colony.capacityViolation.turnsRemaining = 2
    state.colonies["system-1"] = colony

    let status = analyzeCapacity(state, colony, "house-test")
    updateViolationTracking(state, status)

    check state.colonies["system-1"].capacityViolation.turnsRemaining == 1

  test "Resolved violation clears tracking":
    var state = GameState()
    state.houses = initTable[HouseId, House]()
    state.colonies = initTable[SystemId, Colony]()

    state.houses["house-test"] = House(
      id: "house-test",
      techTree: TechTree(levels: TechLevels(fighterDoctrine: 1))
    )

    var colony = createTestColony(pu=200, fdLevel=1, fighters=1, starbases=1)
    colony.systemId = "system-1"
    colony.owner = "house-test"
    colony.capacityViolation.active = true
    colony.capacityViolation.turnsRemaining = 1
    state.colonies["system-1"] = colony

    let status = analyzeCapacity(state, colony, "house-test")
    updateViolationTracking(state, status)

    check state.colonies["system-1"].capacityViolation.active == false

suite "Enforcement Planning":
  test "Plan enforcement after grace period":
    var state = GameState()
    state.houses = initTable[HouseId, House]()
    state.colonies = initTable[SystemId, Colony]()

    state.houses["house-test"] = House(
      id: "house-test",
      techTree: TechTree(levels: TechLevels(fighterDoctrine: 1))
    )

    var colony = createTestColony(pu=100, fdLevel=1, fighters=6, starbases=1)
    colony.systemId = "system-1"
    colony.owner = "house-test"
    colony.capacityViolation.active = true
    colony.capacityViolation.turnsRemaining = 0  # Grace period expired
    state.colonies["system-1"] = colony

    let status = analyzeCapacity(state, colony, "house-test")
    let action = planEnforcement(state, status)

    check action.gracePeriodExpired == true
    check action.fightersToDisband.len == 1  # 1 excess fighter

  test "No enforcement during grace period":
    var state = GameState()
    state.houses = initTable[HouseId, House]()
    state.colonies = initTable[SystemId, Colony]()

    state.houses["house-test"] = House(
      id: "house-test",
      techTree: TechTree(levels: TechLevels(fighterDoctrine: 1))
    )

    var colony = createTestColony(pu=100, fdLevel=1, fighters=6, starbases=1)
    colony.systemId = "system-1"
    colony.owner = "house-test"
    colony.capacityViolation.active = true
    colony.capacityViolation.turnsRemaining = 1  # Still in grace period
    state.colonies["system-1"] = colony

    let status = analyzeCapacity(state, colony, "house-test")
    let action = planEnforcement(state, status)

    check action.gracePeriodExpired == false
    check action.fightersToDisband.len == 0

  test "Disband oldest fighters first":
    var state = GameState()
    state.houses = initTable[HouseId, House]()
    state.colonies = initTable[SystemId, Colony]()

    state.houses["house-test"] = House(
      id: "house-test",
      techTree: TechTree(levels: TechLevels(fighterDoctrine: 1))
    )

    var colony = Colony(
      systemId: "system-1",
      owner: "house-test",
      populationUnits: 100,
      fighterSquadrons: @[
        FighterSquadron(id: "FS-NEW", commissionedTurn: 10),  # Newest
        FighterSquadron(id: "FS-MID", commissionedTurn: 5),
        FighterSquadron(id: "FS-OLD", commissionedTurn: 1)    # Oldest
      ],
      starbases: @[Starbase(id: "SB-1", isCrippled: false)],
      capacityViolation: CapacityViolationTracking(
        active: true,
        turnsRemaining: 0
      )
    )
    state.colonies["system-1"] = colony

    let status = analyzeCapacity(state, colony, "house-test")
    let action = planEnforcement(state, status)

    # Should disband 2 fighters (capacity for 1, have 3)
    check action.fightersToDisband.len == 2
    check "FS-OLD" in action.fightersToDisband  # Oldest first
    check "FS-MID" in action.fightersToDisband  # Second oldest

suite "Enforcement Application":
  test "Apply enforcement disbands fighters":
    var state = GameState()
    state.houses = initTable[HouseId, House]()
    state.colonies = initTable[SystemId, Colony]()

    state.houses["house-test"] = House(
      id: "house-test",
      techTree: TechTree(levels: TechLevels(fighterDoctrine: 1))
    )

    var colony = createTestColony(pu=100, fdLevel=1, fighters=3, starbases=1)
    colony.systemId = "system-1"
    colony.owner = "house-test"
    colony.capacityViolation.active = true
    state.colonies["system-1"] = colony

    let action = EnforcementAction(
      colonyId: "system-1",
      fightersToDisband: @["FS-1", "FS-2"],
      violationType: ViolationType.Population,
      gracePeriodExpired: true
    )

    applyEnforcement(state, action)

    check state.colonies["system-1"].fighterSquadrons.len == 1
    check state.colonies["system-1"].capacityViolation.active == false

suite "Can Commission Fighter Check":
  test "Can commission when within capacity":
    var state = GameState()
    state.houses = initTable[HouseId, House]()
    state.houses["house-test"] = House(
      id: "house-test",
      techTree: TechTree(levels: TechLevels(fighterDoctrine: 1))
    )

    let colony = createTestColony(pu=200, fdLevel=1, fighters=1, starbases=1)

    check canCommissionFighter(state, colony) == true

  test "Cannot commission when at capacity":
    var state = GameState()
    state.houses = initTable[HouseId, House]()
    state.houses["house-test"] = House(
      id: "house-test",
      techTree: TechTree(levels: TechLevels(fighterDoctrine: 1))
    )

    let colony = createTestColony(pu=100, fdLevel=1, fighters=1, starbases=1)

    check canCommissionFighter(state, colony) == false

  test "Cannot commission when in violation":
    var state = GameState()
    state.houses = initTable[HouseId, House]()
    state.houses["house-test"] = House(
      id: "house-test",
      techTree: TechTree(levels: TechLevels(fighterDoctrine: 1))
    )

    var colony = createTestColony(pu=200, fdLevel=1, fighters=1, starbases=1)
    colony.capacityViolation.active = true

    check canCommissionFighter(state, colony) == false

when isMainModule:
  echo "Running fighter capacity enforcement tests..."
