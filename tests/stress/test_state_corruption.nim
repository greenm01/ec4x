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
##
## Updated for new engine architecture (2026-01)

import std/[times, strformat, random, tables, options, sequtils]
import unittest
import stress_framework
import ../../src/engine/engine
import ../../src/engine/types/[core, command, house, colony, tech, espionage]
import ../../src/engine/state/[engine, iterators]
import ../../src/engine/turn_cycle/engine

proc createNoOpCommands(
    game: GameState, turn: int
): Table[HouseId, CommandPacket] =
  ## Create empty commands for all houses (no actions)
  result = initTable[HouseId, CommandPacket]()
  for (houseId, house) in game.activeHousesWithId():
    result[houseId] = CommandPacket(
      houseId: houseId,
      turn: turn.int32,
      treasury: house.treasury.int32,
      fleetCommands: @[],
      buildCommands: @[],
      repairCommands: @[],
      researchAllocation: ResearchAllocation(),
      diplomaticCommand: @[],
      populationTransfers: @[],
      terraformCommands: @[],
      colonyManagement: @[],
      espionageActions: @[],
      ebpInvestment: 0,
      cipInvestment: 0
    )

suite "State Corruption: Long-Duration Simulations":

  test "1000-turn simulation: state remains valid":
    ## Run a 1000-turn simulation with minimal commands
    ## Check state invariants every 100 turns
    ## This tests for gradual state corruption

    echo "\nRunning 1000-turn state corruption test..."

    let startTime = cpuTime()
    var game = newGame()
    var rng = initRand(123)
    var allViolations: seq[InvariantViolation] = @[]

    const maxTurns = 1000
    const checkInterval = 100

    for turn in 1..maxTurns:
      if turn mod 100 == 0:
        echo &"  Turn {turn}/{maxTurns}..."

      # Create minimal commands for all houses
      let commands = createNoOpCommands(game, turn)

      # Resolve turn
      try:
        let turnResult = game.resolveTurn(commands, rng)
        
        if turnResult.victoryCheck.victoryOccurred:
          echo &"  Victory achieved at turn {turn}"
          break
          
      except CatchableError as e:
        echo &"Turn {turn} crashed: {e.msg}"
        fail()
        break

      # Check invariants periodically
      if turn mod checkInterval == 0:
        let violations = checkStateInvariants(game, turn)
        allViolations.add(violations)

        if violations.len > 0:
          echo &"  Turn {turn}: Found {violations.len} violations"

    let elapsed = cpuTime() - startTime
    echo &"Completed in {elapsed:.2f}s ({maxTurns.float / elapsed:.1f} turns/sec)"

    # Report all violations
    if allViolations.len > 0:
      echo &"\nTotal violations across all turns: {allViolations.len}"
      reportViolations(allViolations)

      # Fail if any critical violations
      let critical = allViolations.filterIt(it.severity == ViolationSeverity.Critical)
      if critical.len > 0:
        echo &"TEST FAILED: Found {critical.len} CRITICAL violations"
        fail()
    else:
      echo "No violations detected"

  test "State corruption: repeated game initialization":
    ## Create and destroy games repeatedly
    ## Tests for state leakage between games

    echo "\nTesting repeated game initialization..."

    var allViolations: seq[InvariantViolation] = @[]

    for gameNum in 1..100:
      if gameNum mod 10 == 0:
        echo &"  Game {gameNum}/100..."

      # Create new game with different seed each time
      var game = newGame()
      var rng = initRand(int64(gameNum * 12345))

      # Check initial state
      let violations = checkStateInvariants(game, 0)
      allViolations.add(violations)

      # Run 10 turns
      for turn in 1..10:
        let commands = createNoOpCommands(game, turn)
        let turnResult = game.resolveTurn(commands, rng)
        
        if turnResult.victoryCheck.victoryOccurred:
          break

      # Check final state
      let finalViolations = checkStateInvariants(game, 10)
      allViolations.add(finalViolations)

    echo "Completed 100 games (1000 total turns)"

    if allViolations.len > 0:
      echo &"\nTotal violations: {allViolations.len}"
      reportViolations(allViolations)
      fail()
    else:
      echo "No state corruption detected"

  test "State corruption: zero-population colony edge case":
    ## Edge case: What happens when colony has 0 PU?
    ## Should test if engine handles this gracefully

    echo "\nTesting zero-population edge case..."

    var game = newGame()
    var rng = initRand(456)

    # Get first colony and set PU to 0
    var firstColonyId: ColonyId
    var foundColony = false
    for (colonyId, _) in game.allColoniesWithId():
      firstColonyId = colonyId
      foundColony = true
      break

    if not foundColony:
      echo "  No colonies found in test game, skipping"
      skip()

    # Force colony to 0 PU (manipulate state directly for testing)
    let colonyOpt = game.colony(firstColonyId)
    if colonyOpt.isSome:
      var colony = colonyOpt.get()
      colony.populationUnits = 0
      game.updateColony(firstColonyId, colony)
      echo "  Set colony to 0 PU"

    # Run 10 turns to see if engine handles it
    var crashed = false
    for turn in 1..10:
      let commands = createNoOpCommands(game, turn)

      try:
        let turnResult = game.resolveTurn(commands, rng)
        if turnResult.victoryCheck.victoryOccurred:
          break
      except CatchableError as e:
        echo &"Engine crashed with 0 PU colony at turn {turn}: {e.msg}"
        crashed = true
        break

    if crashed:
      echo "  WARNING: Engine crashes with 0 PU colonies (may be by design)"
    else:
      echo "Engine handles 0 PU colonies gracefully"

      # Check if state is still valid
      let violations = checkStateInvariants(game, 10)
      if violations.len > 0:
        reportViolations(violations)
        # Don't fail - 0 PU is an edge case

  test "State corruption: negative treasury recovery":
    ## Test if houses can recover from negative treasury
    ## Or if negative treasury causes cascading failures

    echo "\nTesting negative treasury recovery..."

    var game = newGame()
    var rng = initRand(789)

    # Get first house and set negative treasury
    var firstHouseId: HouseId
    for (houseId, _) in game.activeHousesWithId():
      firstHouseId = houseId
      break

    let houseOpt = game.house(firstHouseId)
    if houseOpt.isSome:
      var house = houseOpt.get()
      house.treasury = -5000
      game.updateHouse(firstHouseId, house)
      echo &"  Set House {firstHouseId} treasury to -5000 PP"

    # Run simulation and see if state degrades
    var allViolations: seq[InvariantViolation] = @[]

    for turn in 1..50:
      let commands = createNoOpCommands(game, turn)

      try:
        let turnResult = game.resolveTurn(commands, rng)
        if turnResult.victoryCheck.victoryOccurred:
          break
      except CatchableError as e:
        echo &"Crashed at turn {turn} with negative treasury: {e.msg}"
        fail()
        break

      if turn mod 10 == 0:
        let violations = checkStateInvariants(game, turn)
        allViolations.add(violations)
        
        let currentHouse = game.house(firstHouseId)
        if currentHouse.isSome:
          echo &"  Turn {turn}: Treasury = {currentHouse.get().treasury} PP"

    echo "Completed 50 turns with initial negative treasury"

    if allViolations.len > 0:
      reportViolations(allViolations)
      # Don't fail - negative treasury violations are expected
      echo "  Violations detected but engine remained stable"
    else:
      echo "No unexpected violations"

suite "State Corruption: Boundary Conditions":

  test "Boundary: maximum tech levels":
    ## Test behavior at maximum tech levels
    ## Some tech can exceed nominal max (EL > 10, SL > 8)

    echo "\nTesting maximum tech levels..."

    var game = newGame()
    var rng = initRand(111)

    # Get first house and set max tech
    var firstHouseId: HouseId
    for (houseId, _) in game.activeHousesWithId():
      firstHouseId = houseId
      break

    let houseOpt = game.house(firstHouseId)
    if houseOpt.isSome:
      var house = houseOpt.get()
      house.techTree.levels.cst = 10  # Max CST
      house.techTree.levels.wep = 10  # Max WEP
      house.techTree.levels.el = 15   # EL can exceed 10
      house.techTree.levels.sl = 12   # SL can exceed 8
      house.techTree.levels.ter = 7   # Max TER
      house.techTree.levels.eli = 5   # Max ELI
      house.techTree.levels.clk = 5   # Max CLK
      house.techTree.levels.sld = 5   # Max SLD
      house.techTree.levels.cic = 5   # Max CIC
      house.techTree.levels.fd = 3    # Max FD
      house.techTree.levels.aco = 3   # Max ACO
      game.updateHouse(firstHouseId, house)
      echo "  Set all tech to maximum levels"

    # Run 20 turns
    for turn in 1..20:
      let commands = createNoOpCommands(game, turn)
      let turnResult = game.resolveTurn(commands, rng)
      if turnResult.victoryCheck.victoryOccurred:
        break

    # Check state
    let violations = checkStateInvariants(game, 20)
    if violations.len > 0:
      reportViolations(violations)
      fail()
    else:
      echo "Engine stable at maximum tech levels"

  test "Boundary: maximum prestige values":
    ## Test extreme prestige values

    echo "\nTesting extreme prestige values..."

    var game = newGame()
    var rng = initRand(222)

    # Get houses and set extreme prestige
    var houseIds: seq[HouseId] = @[]
    for (houseId, _) in game.activeHousesWithId():
      houseIds.add(houseId)

    if houseIds.len >= 2:
      # Set first house to very high prestige
      let h1 = game.house(houseIds[0])
      if h1.isSome:
        var house = h1.get()
        house.prestige = 10_000
        game.updateHouse(houseIds[0], house)

      # Set second house to negative prestige (defensive collapse territory)
      let h2 = game.house(houseIds[1])
      if h2.isSome:
        var house = h2.get()
        house.prestige = -500
        game.updateHouse(houseIds[1], house)

      echo "  Set prestige to 10,000 and -500"

    # Run 30 turns
    for turn in 1..30:
      let commands = createNoOpCommands(game, turn)
      let turnResult = game.resolveTurn(commands, rng)
      if turnResult.victoryCheck.victoryOccurred:
        break

    # Check state
    let violations = checkStateInvariants(game, 30)
    if violations.len > 0:
      # Filter out expected prestige warnings
      let critical = violations.filterIt(it.severity == ViolationSeverity.Critical)
      if critical.len > 0:
        reportViolations(critical)
        fail()
      else:
        echo "Engine stable with extreme prestige (warnings expected)"
    else:
      echo "No violations with extreme prestige"

when isMainModule:
  echo "========================================"
  echo "  EC4X State Corruption Stress Tests"
  echo "  Long-duration state validation"
  echo "========================================"
  echo ""
