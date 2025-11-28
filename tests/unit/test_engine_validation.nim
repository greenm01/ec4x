## Unit Tests for Engine Validation System
##
## Tests centralized validation functions for game state operations

import std/[unittest, tables, options]
import ../../src/engine/[validation, gamestate]
import ../../src/common/types/[core, planets, units]

# Helper to create minimal test game state
proc createTestGameState(): GameState =
  result = GameState()
  result.turn = 1
  result.houses = initTable[HouseId, House]()
  result.colonies = initTable[SystemId, Colony]()
  result.fleets = initTable[FleetId, Fleet]()
  result.starMap = StarMap(
    systems: initTable[SystemId, System]()
  )

  # Add test house
  let testHouse = House(
    id: "house-test",
    name: "Test House",
    treasury: 1000,
    prestige: 100,
    eliminated: false
  )
  result.houses["house-test"] = testHouse

  # Add test colony
  let testSystem = System(
    id: "system-1",
    name: "Test System",
    position: HexCoord(q: 0, r: 0)
  )
  result.starMap.systems["system-1"] = testSystem

  let testColony = Colony(
    systemId: "system-1",
    owner: "house-test",
    planetClass: PlanetClass.Eden,
    populationUnits: 100,
    industrial: IndustrialUnits(units: 50),
    blockaded: false,
    constructionQueue: @[]
  )
  result.colonies["system-1"] = testColony

  # Add test fleet
  let testFleet = Fleet(
    id: "fleet-1",
    owner: "house-test",
    location: "system-1"
  )
  result.fleets["fleet-1"] = testFleet

suite "Validation Result Constructors":
  test "success() creates valid result":
    let vr = success()
    check vr.valid == true
    check vr.errorMessage == ""
    check vr.isValid()

  test "failure() creates invalid result with message":
    let vr = failure("Test error message")
    check vr.valid == false
    check vr.errorMessage == "Test error message"
    check not vr.isValid()
    check vr.getError() == "Test error message"

suite "House Validation":
  test "validateHouseExists - existing house":
    let state = createTestGameState()
    let vr = validateHouseExists(state, "house-test")
    check vr.valid == true

  test "validateHouseExists - non-existent house":
    let state = createTestGameState()
    let vr = validateHouseExists(state, "house-nonexistent")
    check vr.valid == false
    check "does not exist" in vr.errorMessage

  test "validateHouseActive - active house":
    let state = createTestGameState()
    let vr = validateHouseActive(state, "house-test")
    check vr.valid == true

  test "validateHouseActive - eliminated house":
    var state = createTestGameState()
    state.houses["house-test"].eliminated = true
    let vr = validateHouseActive(state, "house-test")
    check vr.valid == false
    check "eliminated" in vr.errorMessage

  test "validateHouseTreasury - sufficient funds":
    let state = createTestGameState()
    let vr = validateHouseTreasury(state, "house-test", 500)
    check vr.valid == true

  test "validateHouseTreasury - insufficient funds":
    let state = createTestGameState()
    let vr = validateHouseTreasury(state, "house-test", 2000)
    check vr.valid == false
    check "Insufficient funds" in vr.errorMessage

suite "Colony Validation":
  test "validateColonyExists - existing colony":
    let state = createTestGameState()
    let vr = validateColonyExists(state, "system-1")
    check vr.valid == true

  test "validateColonyExists - non-existent colony":
    let state = createTestGameState()
    let vr = validateColonyExists(state, "system-99")
    check vr.valid == false
    check "No colony" in vr.errorMessage

  test "validateColonyOwnership - owned colony":
    let state = createTestGameState()
    let vr = validateColonyOwnership(state, "system-1", "house-test")
    check vr.valid == true

  test "validateColonyOwnership - not owned":
    var state = createTestGameState()
    state.colonies["system-1"].owner = "house-other"
    let vr = validateColonyOwnership(state, "system-1", "house-test")
    check vr.valid == false
    check "not owned" in vr.errorMessage

  test "validateColonyNotBlockaded - not blockaded":
    let state = createTestGameState()
    let vr = validateColonyNotBlockaded(state, "system-1")
    check vr.valid == true

  test "validateColonyNotBlockaded - blockaded":
    var state = createTestGameState()
    state.colonies["system-1"].blockaded = true
    let vr = validateColonyNotBlockaded(state, "system-1")
    check vr.valid == false
    check "blockaded" in vr.errorMessage

  test "validateColonyPopulation - sufficient population":
    let state = createTestGameState()
    let vr = validateColonyPopulation(state, "system-1", 50)
    check vr.valid == true

  test "validateColonyPopulation - insufficient population":
    let state = createTestGameState()
    let vr = validateColonyPopulation(state, "system-1", 200)
    check vr.valid == false
    check "Insufficient population" in vr.errorMessage

suite "Fleet Validation":
  test "validateFleetExists - existing fleet":
    let state = createTestGameState()
    let vr = validateFleetExists(state, "fleet-1")
    check vr.valid == true

  test "validateFleetExists - non-existent fleet":
    let state = createTestGameState()
    let vr = validateFleetExists(state, "fleet-99")
    check vr.valid == false
    check "does not exist" in vr.errorMessage

  test "validateFleetOwnership - owned fleet":
    let state = createTestGameState()
    let vr = validateFleetOwnership(state, "fleet-1", "house-test")
    check vr.valid == true

  test "validateFleetOwnership - not owned":
    var state = createTestGameState()
    state.fleets["fleet-1"].owner = "house-other"
    let vr = validateFleetOwnership(state, "fleet-1", "house-test")
    check vr.valid == false
    check "not owned" in vr.errorMessage

  test "validateFleetAtSystem - fleet at system":
    let state = createTestGameState()
    let vr = validateFleetAtSystem(state, "fleet-1", "system-1")
    check vr.valid == true

  test "validateFleetAtSystem - fleet at different system":
    var state = createTestGameState()
    state.fleets["fleet-1"].location = "system-2"
    let vr = validateFleetAtSystem(state, "fleet-1", "system-1")
    check vr.valid == false
    check "not at system" in vr.errorMessage

suite "System Validation":
  test "validateSystemExists - existing system":
    let state = createTestGameState()
    let vr = validateSystemExists(state, "system-1")
    check vr.valid == true

  test "validateSystemExists - non-existent system":
    let state = createTestGameState()
    let vr = validateSystemExists(state, "system-99")
    check vr.valid == false
    check "does not exist" in vr.errorMessage

  test "validatePathExists - same system":
    let state = createTestGameState()
    let vr = validatePathExists(state, "system-1", "system-1")
    check vr.valid == true

suite "Resource Validation":
  test "validateConstructionQueue - queue not full":
    let state = createTestGameState()
    let vr = validateConstructionQueue(state, "system-1", 5)
    check vr.valid == true

  test "validateConstructionQueue - queue full":
    var state = createTestGameState()
    for i in 1..5:
      state.colonies["system-1"].constructionQueue.add(ConstructionProject())
    let vr = validateConstructionQueue(state, "system-1", 5)
    check vr.valid == false
    check "full" in vr.errorMessage

  test "validateIndustrialCapacity - sufficient IU":
    let state = createTestGameState()
    let vr = validateIndustrialCapacity(state, "system-1", 30)
    check vr.valid == true

  test "validateIndustrialCapacity - insufficient IU":
    let state = createTestGameState()
    let vr = validateIndustrialCapacity(state, "system-1", 100)
    check vr.valid == false
    check "Insufficient industrial" in vr.errorMessage

suite "Composite Validations":
  test "validateCanBuildAtColony - all checks pass":
    let state = createTestGameState()
    let vr = validateCanBuildAtColony(state, "house-test", "system-1", 500)
    check vr.valid == true

  test "validateCanBuildAtColony - house eliminated":
    var state = createTestGameState()
    state.houses["house-test"].eliminated = true
    let vr = validateCanBuildAtColony(state, "house-test", "system-1", 500)
    check vr.valid == false
    check "eliminated" in vr.errorMessage

  test "validateCanBuildAtColony - insufficient funds":
    let state = createTestGameState()
    let vr = validateCanBuildAtColony(state, "house-test", "system-1", 2000)
    check vr.valid == false
    check "Insufficient funds" in vr.errorMessage

  test "validateCanTransferPopulation - valid transfer":
    var state = createTestGameState()
    state.starMap.systems["system-2"] = System(
      id: "system-2",
      name: "Target System",
      position: HexCoord(q: 1, r: 0)
    )
    let vr = validateCanTransferPopulation(
      state, "house-test", "system-1", "system-2", 50, minRetainedPU=1
    )
    check vr.valid == true

  test "validateCanTransferPopulation - insufficient population":
    var state = createTestGameState()
    state.starMap.systems["system-2"] = System(
      id: "system-2",
      name: "Target System",
      position: HexCoord(q: 1, r: 0)
    )
    let vr = validateCanTransferPopulation(
      state, "house-test", "system-1", "system-2", 100, minRetainedPU=1
    )
    check vr.valid == false
    check "must retain" in vr.errorMessage

  test "validateCanMoveFleet - valid move":
    let state = createTestGameState()
    let vr = validateCanMoveFleet(state, "house-test", "fleet-1", "system-1")
    check vr.valid == true

  test "validateCanMoveFleet - wrong owner":
    var state = createTestGameState()
    state.fleets["fleet-1"].owner = "house-other"
    let vr = validateCanMoveFleet(state, "house-test", "fleet-1", "system-1")
    check vr.valid == false
    check "not owned" in vr.errorMessage

suite "Helper Functions":
  test "validateAll - all pass":
    let checks = @[
      success(),
      success(),
      success()
    ]
    let vr = validateAll(checks)
    check vr.valid == true

  test "validateAll - first fails":
    let checks = @[
      failure("First error"),
      success(),
      success()
    ]
    let vr = validateAll(checks)
    check vr.valid == false
    check vr.errorMessage == "First error"

  test "validateAll - middle fails":
    let checks = @[
      success(),
      failure("Middle error"),
      success()
    ]
    let vr = validateAll(checks)
    check vr.valid == false
    check vr.errorMessage == "Middle error"

  test "validateAll - empty list":
    let checks: seq[ValidationResult] = @[]
    let vr = validateAll(checks)
    check vr.valid == true

when isMainModule:
  echo "Running engine validation tests..."
