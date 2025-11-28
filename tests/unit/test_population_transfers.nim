## Unit Tests for Space Guild Population Transfer System
##
## Tests complete population transfer system per economy.md:3.7

import std/[unittest, tables, options]
import ../../src/engine/population/[transfers, types as pop_types]
import ../../src/engine/[gamestate, state_helpers, starmap]
import ../../src/common/types/[core, planets]

proc createTestStarMap(): StarMap =
  result = StarMap(systems: initTable[SystemId, System]())

  result.systems["system-1"] = System(
    id: "system-1",
    name: "System 1",
    position: HexCoord(q: 0, r: 0)
  )

  result.systems["system-2"] = System(
    id: "system-2",
    name: "System 2",
    position: HexCoord(q: 1, r: 0)
  )

  result.systems["system-3"] = System(
    id: "system-3",
    name: "System 3",
    position: HexCoord(q: 2, r: 0)
  )

  # Add connections
  result.systems["system-1"].connections = @["system-2"]
  result.systems["system-2"].connections = @["system-1", "system-3"]
  result.systems["system-3"].connections = @["system-2"]

proc createTestGameState(): GameState =
  result = GameState()
  result.turn = 1
  result.houses = initTable[HouseId, House]()
  result.colonies = initTable[SystemId, Colony]()
  result.populationInTransit = @[]
  result.starMap = createTestStarMap()

  # Add test house
  result.houses["house-test"] = House(
    id: "house-test",
    name: "Test House",
    treasury: 1000,
    prestige: 100,
    eliminated: false
  )

  # Add test colonies
  result.colonies["system-1"] = Colony(
    systemId: "system-1",
    owner: "house-test",
    planetClass: PlanetClass.Eden,
    populationUnits: 100,
    population: 100
  )

  result.colonies["system-2"] = Colony(
    systemId: "system-2",
    owner: "house-test",
    planetClass: PlanetClass.Lush,
    populationUnits: 50,
    population: 50,
    blockaded: false
  )

suite "Planet Class Base Cost":
  test "Eden base cost":
    let cost = getPlanetClassBaseCost(PlanetClass.Eden)
    check cost == 4

  test "Lush base cost":
    let cost = getPlanetClassBaseCost(PlanetClass.Lush)
    check cost == 5

  test "Benign base cost":
    let cost = getPlanetClassBaseCost(PlanetClass.Benign)
    check cost == 6

  test "Harsh base cost":
    let cost = getPlanetClassBaseCost(PlanetClass.Harsh)
    check cost == 8

  test "Hostile base cost":
    let cost = getPlanetClassBaseCost(PlanetClass.Hostile)
    check cost == 10

  test "Desolate base cost":
    let cost = getPlanetClassBaseCost(PlanetClass.Desolate)
    check cost == 12

  test "Extreme base cost":
    let cost = getPlanetClassBaseCost(PlanetClass.Extreme)
    check cost == 15

suite "Transfer Cost Calculation":
  test "Same planet class, 1 jump":
    # Eden to Eden, 1 jump, 10 PTU
    # (4+4)/2 = 4, distance mult = 1.0
    # 4 × 10 × 1.0 = 40 PP
    let cost = calculateTransferCost(
      PlanetClass.Eden, PlanetClass.Eden,
      distance=1, ptuAmount=10
    )
    check cost == 40

  test "Different planet classes averaged":
    # Eden (4) to Extreme (15), 1 jump, 10 PTU
    # (4+15)/2 = 9 (integer division)
    # 9 × 10 × 1.0 = 90 PP
    let cost = calculateTransferCost(
      PlanetClass.Eden, PlanetClass.Extreme,
      distance=1, ptuAmount=10
    )
    check cost == 90

  test "Distance modifier for 2 jumps":
    # Eden to Eden, 2 jumps, 10 PTU
    # Base = 4, mult = 1 + 0.2×(2-1) = 1.2
    # 4 × 10 × 1.2 = 48 PP
    let cost = calculateTransferCost(
      PlanetClass.Eden, PlanetClass.Eden,
      distance=2, ptuAmount=10
    )
    check cost == 48

  test "Distance modifier for 5 jumps":
    # Eden to Eden, 5 jumps, 10 PTU
    # mult = 1 + 0.2×(5-1) = 1.8
    # 4 × 10 × 1.8 = 72 PP
    let cost = calculateTransferCost(
      PlanetClass.Eden, PlanetClass.Eden,
      distance=5, ptuAmount=10
    )
    check cost == 72

  test "Large population transfer cost":
    # Lush to Benign, 3 jumps, 50 PTU
    # (5+6)/2 = 5, mult = 1 + 0.2×2 = 1.4
    # 5 × 50 × 1.4 = 350 PP
    let cost = calculateTransferCost(
      PlanetClass.Lush, PlanetClass.Benign,
      distance=3, ptuAmount=50
    )
    check cost == 350

suite "PTU to PU Conversion":
  test "1 PTU = 1 PU":
    check ptuToPu(1) == 1
    check ptuToPu(10) == 10
    check ptuToPu(100) == 100

suite "Find Nearest Owned Colony":
  test "Find nearest colony":
    var state = createTestGameState()
    # Add third colony at system-3
    state.colonies["system-3"] = Colony(
      systemId: "system-3",
      owner: "house-test",
      planetClass: PlanetClass.Benign,
      populationUnits: 30
    )

    # From system-1, system-2 should be closer than system-3
    let nearest = findNearestOwnedColony(state, "system-1", "house-test")
    check nearest.isSome
    check nearest.get() == "system-2"

  test "No owned colonies returns none":
    var state = createTestGameState()
    # Remove all colonies
    state.colonies.clear()

    let nearest = findNearestOwnedColony(state, "system-1", "house-test")
    check nearest.isNone

  test "Excludes source system":
    var state = createTestGameState()
    # Only have colony at system-1
    state.colonies.del("system-2")

    let nearest = findNearestOwnedColony(state, "system-1", "house-test")
    # Should not return system-1 itself
    check nearest.isNone or nearest.get() != "system-1"

suite "Initiate Transfer Validation":
  test "Successful transfer initiation":
    var state = createTestGameState()

    let (success, msg) = initiateTransfer(
      state, "house-test", "system-1", "system-2", ptuAmount=10
    )

    check success == true
    check state.populationInTransit.len == 1
    check state.houses["house-test"].treasury < 1000  # Cost deducted
    check state.colonies["system-1"].populationUnits == 90  # Population removed

  test "Cannot transfer more than 5 concurrent":
    var state = createTestGameState()

    # Add 5 transfers
    for i in 1..5:
      state.populationInTransit.add(pop_types.PopulationInTransit(
        id: $i,
        houseId: "house-test",
        sourceSystem: "system-1",
        destSystem: "system-2",
        ptuAmount: 10,
        costPaid: 100,
        arrivalTurn: 10
      ))

    let (success, msg) = initiateTransfer(
      state, "house-test", "system-1", "system-2", ptuAmount=10
    )

    check success == false
    check "concurrent" in msg or "Maximum" in msg

  test "Cannot transfer from non-owned colony":
    var state = createTestGameState()
    state.colonies["system-1"].owner = "house-other"

    let (success, msg) = initiateTransfer(
      state, "house-test", "system-1", "system-2", ptuAmount=10
    )

    check success == false
    check "owned" in msg or "not owned" in msg

  test "Must retain 1 PU at source":
    var state = createTestGameState()

    let (success, msg) = initiateTransfer(
      state, "house-test", "system-1", "system-2", ptuAmount=100
    )

    check success == false
    check "retain" in msg

  test "Insufficient treasury fails":
    var state = createTestGameState()
    state.houses["house-test"].treasury = 1  # Very low funds

    let (success, msg) = initiateTransfer(
      state, "house-test", "system-1", "system-2", ptuAmount=50
    )

    check success == false
    check "funds" in msg or "Insufficient" in msg

suite "Transfer Arrival Processing":
  test "Delivered to destination":
    var state = createTestGameState()

    let transfer = pop_types.PopulationInTransit(
      id: "transfer-1",
      houseId: "house-test",
      sourceSystem: "system-1",
      destSystem: "system-2",
      ptuAmount: 10,
      costPaid: 50,
      arrivalTurn: 2
    )

    let completion = processArrivingTransfer(state, transfer)

    check completion.result == TransferResult.Delivered
    check completion.actualDestination.isSome
    check completion.actualDestination.get() == "system-2"

  test "Redirected when destination blockaded":
    var state = createTestGameState()
    state.colonies["system-2"].blockaded = true

    # Add alternative colony
    state.colonies["system-3"] = Colony(
      systemId: "system-3",
      owner: "house-test",
      planetClass: PlanetClass.Benign,
      populationUnits: 50
    )

    let transfer = pop_types.PopulationInTransit(
      id: "transfer-1",
      houseId: "house-test",
      sourceSystem: "system-1",
      destSystem: "system-2",
      ptuAmount: 10,
      costPaid: 50,
      arrivalTurn: 2
    )

    let completion = processArrivingTransfer(state, transfer)

    check completion.result == TransferResult.Redirected
    check completion.actualDestination.isSome
    # Should redirect to system-3 (nearest owned colony)

  test "Redirected when destination conquered":
    var state = createTestGameState()
    state.colonies["system-2"].owner = "house-enemy"

    # Add alternative colony
    state.colonies["system-3"] = Colony(
      systemId: "system-3",
      owner: "house-test",
      planetClass: PlanetClass.Benign,
      populationUnits: 50
    )

    let transfer = pop_types.PopulationInTransit(
      id: "transfer-1",
      houseId: "house-test",
      sourceSystem: "system-1",
      destSystem: "system-2",
      ptuAmount: 10,
      costPaid: 50,
      arrivalTurn: 2
    )

    let completion = processArrivingTransfer(state, transfer)

    check completion.result == TransferResult.Redirected

  test "Lost when no owned colonies exist":
    var state = createTestGameState()
    # Remove all colonies for this house
    state.colonies.clear()

    let transfer = pop_types.PopulationInTransit(
      id: "transfer-1",
      houseId: "house-test",
      sourceSystem: "system-1",
      destSystem: "system-2",
      ptuAmount: 10,
      costPaid: 50,
      arrivalTurn: 2
    )

    let completion = processArrivingTransfer(state, transfer)

    check completion.result == TransferResult.Lost
    check completion.actualDestination.isNone

suite "Transfer Completion Application":
  test "Delivered transfer adds population":
    var state = createTestGameState()
    let initialPop = state.colonies["system-2"].populationUnits

    let completion = TransferCompletion(
      transfer: pop_types.PopulationInTransit(
        id: "transfer-1",
        houseId: "house-test",
        sourceSystem: "system-1",
        destSystem: "system-2",
        ptuAmount: 10,
        costPaid: 50,
        arrivalTurn: 2
      ),
      result: TransferResult.Delivered,
      actualDestination: some(SystemId("system-2"))
    )

    applyTransferCompletion(state, completion)

    check state.colonies["system-2"].populationUnits == initialPop + 10

  test "Lost transfer does not add population":
    var state = createTestGameState()

    let completion = TransferCompletion(
      transfer: pop_types.PopulationInTransit(
        id: "transfer-1",
        houseId: "house-test",
        sourceSystem: "system-1",
        destSystem: "system-2",
        ptuAmount: 10,
        costPaid: 50,
        arrivalTurn: 2
      ),
      result: TransferResult.Lost,
      actualDestination: none(SystemId)
    )

    let allColonies = state.colonies
    applyTransferCompletion(state, completion)

    # No colonies should change
    for systemId, colony in allColonies:
      check state.colonies[systemId].populationUnits == colony.populationUnits

suite "Process Transfers Batch":
  test "Process arriving transfer":
    var state = createTestGameState()
    state.turn = 5

    state.populationInTransit.add(pop_types.PopulationInTransit(
      id: "transfer-1",
      houseId: "house-test",
      sourceSystem: "system-1",
      destSystem: "system-2",
      ptuAmount: 10,
      costPaid: 50,
      arrivalTurn: 5  # Arrives this turn
    ))

    let initialPop = state.colonies["system-2"].populationUnits
    let completions = processTransfers(state)

    check completions.len == 1
    check state.populationInTransit.len == 0  # Removed from transit
    check state.colonies["system-2"].populationUnits == initialPop + 10

  test "Do not process future transfers":
    var state = createTestGameState()
    state.turn = 5

    state.populationInTransit.add(pop_types.PopulationInTransit(
      id: "transfer-1",
      houseId: "house-test",
      sourceSystem: "system-1",
      destSystem: "system-2",
      ptuAmount: 10,
      costPaid: 50,
      arrivalTurn: 10  # Arrives in the future
    ))

    let completions = processTransfers(state)

    check completions.len == 0
    check state.populationInTransit.len == 1  # Still in transit

  test "Process multiple transfers in same turn":
    var state = createTestGameState()
    state.turn = 5

    state.colonies["system-3"] = Colony(
      systemId: "system-3",
      owner: "house-test",
      planetClass: PlanetClass.Benign,
      populationUnits: 30
    )

    state.populationInTransit.add(pop_types.PopulationInTransit(
      id: "transfer-1",
      houseId: "house-test",
      sourceSystem: "system-1",
      destSystem: "system-2",
      ptuAmount: 10,
      costPaid: 50,
      arrivalTurn: 5
    ))

    state.populationInTransit.add(pop_types.PopulationInTransit(
      id: "transfer-2",
      houseId: "house-test",
      sourceSystem: "system-1",
      destSystem: "system-3",
      ptuAmount: 5,
      costPaid: 30,
      arrivalTurn: 5
    ))

    let completions = processTransfers(state)

    check completions.len == 2
    check state.populationInTransit.len == 0

when isMainModule:
  echo "Running population transfer tests..."
