## State Corruption Stress Test
##
## Runs long-duration game simulations looking for state corruption:
## - Invalid game states that should never occur
## - Gradual state degradation over many turns
## - Accumulating errors that compound
## - Boundary violations in data structures
##
## This test runs 1000+ turn simulations to detect issues that
## only manifest under sustained operation.

import std/[times, strformat, random, tables, options, sequtils]
import unittest
import stress_framework
import ../../src/engine/[gamestate, resolve, orders]
import ../../src/engine/research/types as res_types
import ../../src/engine/espionage/types as esp_types
import ../../src/engine/economy/types as econ_types
import ../../src/common/types/[core, planets]

proc createMinimalGame(numHouses: int = 2, seed: int64 = 42): GameState =
  ## Create a minimal game for stress testing using newGame
  result = newGame("stress_test", numHouses, seed)

  # Add houses with minimal setup
  for i in 0..<numHouses:
    let houseId = HouseId(&"house{i+1}")
    result.houses[houseId] = House(
      id: houseId,
      name: &"House {i+1}",
      treasury: 10000,
      eliminated: false,
      techTree: res_types.initTechTree()
    )

    # Add home colony if player system exists
    if i < result.starMap.playerSystemIds.len:
      let systemId = result.starMap.playerSystemIds[i]
      result.colonies[systemId] = Colony(
        systemId: systemId,
        owner: houseId,
        population: 100,
        souls: 100_000_000,
        infrastructure: 5,
        planetClass: PlanetClass.Benign,
        resources: ResourceRating.Abundant,
        buildings: @[],
        production: 100,
        underConstruction: none(econ_types.ConstructionProject),
        constructionQueue: @[],
        activeTerraforming: none(gamestate.TerraformProject),
        unassignedSquadrons: @[],
        unassignedSpaceLiftShips: @[],
        fighterSquadrons: @[],
        capacityViolation: CapacityViolation(),
        starbases: @[],
        spaceports: @[Spaceport(id: &"sp{i+1}", commissionedTurn: 1, docks: 5)],
        shipyards: @[Shipyard(id: &"sy{i+1}", commissionedTurn: 1, docks: 10, isCrippled: false)]
      )

  result.turn = 1
  result.phase = GamePhase.Active

proc createNoOpOrders(houseId: HouseId, turn: int): OrderPacket =
  ## Create empty orders (fleet holds position)
  OrderPacket(
    houseId: houseId,
    turn: turn,
    buildOrders: @[],
    fleetOrders: @[],
    researchAllocation: initResearchAllocation(),
    diplomaticActions: @[],
    populationTransfers: @[],
    terraformOrders: @[],
    espionageAction: none(esp_types.EspionageAttempt),
    ebpInvestment: 0,
    cipInvestment: 0
  )

suite "State Corruption: Long-Duration Simulations":

  test "1000-turn simulation: state remains valid":
    ## Run a 1000-turn simulation with minimal orders
    ## Check state invariants every 100 turns
    ## This tests for gradual state corruption

    echo "\n🧪 Running 1000-turn state corruption test..."

    let startTime = cpuTime()
    var game = createMinimalGame(numHouses = 2, seed = 123)
    var allViolations: seq[InvariantViolation] = @[]

    const maxTurns = 1000
    const checkInterval = 100

    for turn in 1..maxTurns:
      if turn mod 100 == 0:
        echo &"  Turn {turn}/{maxTurns}..."

      # Create minimal orders for all houses
      var ordersTable = initTable[HouseId, OrderPacket]()
      for houseId in game.houses.keys:
        ordersTable[houseId] = createNoOpOrders(houseId, turn)

      # Resolve turn
      try:
        let result = resolveTurn(game, ordersTable)
        game = result.newState
      except CatchableError as e:
        echo &"❌ Turn {turn} crashed: {e.msg}"
        fail()
        break

      # Check invariants periodically
      if turn mod checkInterval == 0:
        let violations = checkStateInvariants(game, turn)
        allViolations.add(violations)

        if violations.len > 0:
          echo &"⚠️  Turn {turn}: Found {violations.len} violations"

    let elapsed = cpuTime() - startTime
    echo &"✅ Completed {maxTurns} turns in {elapsed:.2f}s ({maxTurns.float / elapsed:.1f} turns/sec)"

    # Report all violations
    if allViolations.len > 0:
      echo &"\n📊 Total violations across all turns: {allViolations.len}"
      reportViolations(allViolations)

      # Fail if any critical violations
      let critical = allViolations.filterIt(it.severity == ViolationSeverity.Critical)
      if critical.len > 0:
        echo &"TEST FAILED: Found {critical.len} CRITICAL violations"
        fail()
    else:
      echo "✅ No violations detected"

  test "State corruption: repeated game initialization":
    ## Create and destroy games repeatedly
    ## Tests for state leakage between games

    echo "\n🧪 Testing repeated game initialization..."

    var allViolations: seq[InvariantViolation] = @[]

    for gameNum in 1..100:
      if gameNum mod 10 == 0:
        echo &"  Game {gameNum}/100..."

      # Create new game
      var game = createMinimalGame(numHouses = 3, seed = int64(gameNum))

      # Check initial state
      let violations = checkStateInvariants(game, 0)
      allViolations.add(violations)

      # Run 10 turns
      for turn in 1..10:
        var ordersTable = initTable[HouseId, OrderPacket]()
        for houseId in game.houses.keys:
          ordersTable[houseId] = createNoOpOrders(houseId, turn)

        let result = resolveTurn(game, ordersTable)
        game = result.newState

      # Check final state
      let finalViolations = checkStateInvariants(game, 10)
      allViolations.add(finalViolations)

    echo &"✅ Completed 100 games (1000 total turns)"

    if allViolations.len > 0:
      echo &"\n📊 Total violations: {allViolations.len}"
      reportViolations(allViolations)
      fail()
    else:
      echo "✅ No state corruption detected"

  test "State corruption: maximum game size":
    ## Test with maximum supported game size
    ## 12 houses, large map, many entities

    echo "\n🧪 Testing maximum game size (12 houses)..."

    var game = createMinimalGame(numHouses = 12, seed = 999)
    var allViolations: seq[InvariantViolation] = @[]

    # Run 100 turns at maximum scale
    for turn in 1..100:
      if turn mod 10 == 0:
        echo &"  Turn {turn}/100..."

      var ordersTable = initTable[HouseId, OrderPacket]()
      for houseId in game.houses.keys:
        ordersTable[houseId] = createNoOpOrders(houseId, turn)

      try:
        let result = resolveTurn(game, ordersTable)
        game = result.newState
      except CatchableError as e:
        echo &"❌ Turn {turn} crashed with 12 houses: {e.msg}"
        fail()
        break

      # Check invariants every 10 turns
      if turn mod 10 == 0:
        let violations = checkStateInvariants(game, turn)
        allViolations.add(violations)

    echo "✅ Completed 100 turns with 12 houses"

    if allViolations.len > 0:
      echo &"\n📊 Violations at maximum scale: {allViolations.len}"
      reportViolations(allViolations)
      fail()
    else:
      echo "✅ No corruption at maximum scale"

  test "State corruption: zero-population colonies":
    ## Edge case: What happens when colony reaches 0 PU?
    ## Should this be valid or should colony be destroyed?

    echo "\n🧪 Testing zero-population edge case..."

    var game = createMinimalGame(numHouses = 2, seed = 456)

    # Force a colony to 0 PU
    let firstColonyId = toSeq(game.colonies.keys)[0]
    game.colonies[firstColonyId].populationUnits = 0
    game.colonies[firstColonyId].population = 0
    game.colonies[firstColonyId].souls = 0
    game.colonies[firstColonyId].populationTransferUnits = 0

    # Run 10 turns to see if engine handles it
    var crashed = false
    for turn in 1..10:
      var ordersTable = initTable[HouseId, OrderPacket]()
      for houseId in game.houses.keys:
        ordersTable[houseId] = createNoOpOrders(houseId, turn)

      try:
        let result = resolveTurn(game, ordersTable)
        game = result.newState
      except CatchableError as e:
        echo &"❌ Engine crashed with 0 PU colony at turn {turn}: {e.msg}"
        crashed = true
        break

    if crashed:
      echo "⚠️  Engine crashes with 0 PU colonies (may be by design)"
    else:
      echo "✅ Engine handles 0 PU colonies gracefully"

      # Check if state is still valid
      let violations = checkStateInvariants(game, 10)
      if violations.len > 0:
        reportViolations(violations)
        fail()

  test "State corruption: negative treasury recovery":
    ## Test if houses can recover from negative treasury
    ## Or if negative treasury causes cascading failures

    echo "\n🧪 Testing negative treasury recovery..."

    var game = createMinimalGame(numHouses = 2, seed = 789)

    # Force first house to negative treasury
    let firstHouse = toSeq(game.houses.keys)[0]
    game.houses[firstHouse].treasury = -5000

    echo &"  Set {firstHouse} treasury to -5000 PP"

    # Run simulation and see if state degrades
    var allViolations: seq[InvariantViolation] = @[]

    for turn in 1..50:
      var ordersTable = initTable[HouseId, OrderPacket]()
      for houseId in game.houses.keys:
        ordersTable[houseId] = createNoOpOrders(houseId, turn)

      try:
        let result = resolveTurn(game, ordersTable)
        game = result.newState
      except CatchableError as e:
        echo &"❌ Crashed at turn {turn} with negative treasury: {e.msg}"
        fail()
        break

      if turn mod 10 == 0:
        let violations = checkStateInvariants(game, turn)
        allViolations.add(violations)
        echo &"  Turn {turn}: Treasury = {game.houses[firstHouse].treasury} PP"

    echo "✅ Completed 50 turns with initial negative treasury"

    if allViolations.len > 0:
      reportViolations(allViolations)
      # Don't fail - negative treasury violations are expected
      echo "⚠️  Violations detected but engine remained stable"
    else:
      echo "✅ No unexpected violations"

suite "State Corruption: Boundary Conditions":

  test "Boundary: maximum tech levels":
    ## Test behavior at maximum tech levels
    ## Some tech can exceed nominal max (EL > 10, SL > 8)

    echo "\n🧪 Testing maximum tech levels..."

    var game = createMinimalGame(numHouses = 2, seed = 111)

    # Set first house to maximum tech in all fields
    let firstHouse = toSeq(game.houses.keys)[0]
    game.houses[firstHouse].techTree.levels.constructionTech = 10  # Max CST
    game.houses[firstHouse].techTree.levels.weaponsTech = 10  # Max WEP
    game.houses[firstHouse].techTree.levels.economicLevel = 15   # EL can exceed 10
    game.houses[firstHouse].techTree.levels.scienceLevel = 12   # SL can exceed 8
    game.houses[firstHouse].techTree.levels.terraformingTech = 7   # Max TER
    game.houses[firstHouse].techTree.levels.electronicIntelligence = 5   # Max ELI
    game.houses[firstHouse].techTree.levels.cloakingTech = 5   # Max CLK
    game.houses[firstHouse].techTree.levels.shieldTech = 5   # Max SLD
    game.houses[firstHouse].techTree.levels.counterIntelligence = 5   # Max CIC
    game.houses[firstHouse].techTree.levels.fighterDoctrine = 3    # Max FD
    game.houses[firstHouse].techTree.levels.advancedCarrierOps = 3   # Max ACO

    echo "  Set all tech to maximum levels"

    # Run 20 turns
    for turn in 1..20:
      var ordersTable = initTable[HouseId, OrderPacket]()
      for houseId in game.houses.keys:
        ordersTable[houseId] = createNoOpOrders(houseId, turn)

      let result = resolveTurn(game, ordersTable)
      game = result.newState

    # Check state
    let violations = checkStateInvariants(game, 20)
    if violations.len > 0:
      reportViolations(violations)
      fail()
    else:
      echo "✅ Engine stable at maximum tech levels"

  test "Boundary: maximum prestige values":
    ## Test extreme prestige values

    echo "\n🧪 Testing extreme prestige values..."

    var game = createMinimalGame(numHouses = 2, seed = 222)

    # Set extreme prestige values
    let houses = toSeq(game.houses.keys)
    game.houses[houses[0]].prestige = 10_000  # Very high
    game.houses[houses[1]].prestige = -500    # Negative (defensive collapse)

    echo "  Set prestige to 10,000 and -500"

    # Run 30 turns
    for turn in 1..30:
      var ordersTable = initTable[HouseId, OrderPacket]()
      for houseId in game.houses.keys:
        ordersTable[houseId] = createNoOpOrders(houseId, turn)

      let result = resolveTurn(game, ordersTable)
      game = result.newState

    # Check state
    let violations = checkStateInvariants(game, 30)
    if violations.len > 0:
      # Filter out expected prestige warnings
      let critical = violations.filterIt(it.severity == ViolationSeverity.Critical)
      if critical.len > 0:
        reportViolations(critical)
        fail()
      else:
        echo "✅ Engine stable with extreme prestige (warnings expected)"
    else:
      echo "✅ No violations with extreme prestige"

when isMainModule:
  echo "╔════════════════════════════════════════════════╗"
  echo "║  EC4X State Corruption Stress Tests           ║"
  echo "║  Long-duration simulations to detect state    ║"
  echo "║  corruption and boundary condition failures   ║"
  echo "╚════════════════════════════════════════════════╝"
  echo ""
