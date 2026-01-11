## Simple Stress Test
## Demonstrates stress testing on actual engine code
##
## Updated for new engine architecture (2026-01)

import std/[times, strformat, random, tables, options, sequtils, math]
import unittest
import ../../src/engine/engine
import ../../src/engine/types/[core, command, fleet, house, tech, espionage]
import ../../src/engine/state/iterators
import ../../src/engine/turn_cycle/engine
import ./stress_framework

suite "Simple Stress: State Integrity":

  test "100-turn simulation maintains valid state":
    echo "\nRunning 100-turn simulation..."

    var game = newGame()
    var rng = initRand(42)
    var turnTimes: seq[float] = @[]
    var allViolations: seq[InvariantViolation] = @[]

    for turn in 1..100:
      if turn mod 10 == 0:
        echo &"  Turn {turn}/100..."

      let startTime = cpuTime()

      # Create empty commands (no-op turn)
      var commands = initTable[HouseId, CommandPacket]()
      for (houseId, house) in game.activeHousesWithId():
        commands[houseId] = CommandPacket(
          houseId: houseId,
          turn: turn.int32,
          fleetCommands: @[],
          buildCommands: @[],
          repairCommands: @[],
          scrapCommands: @[],
          researchAllocation: ResearchAllocation(),
          diplomaticCommand: @[],
          populationTransfers: @[],
          terraformCommands: @[],
          colonyManagement: @[],
          espionageActions: @[],
          ebpInvestment: 0,
          cipInvestment: 0
        )

      # Resolve turn
      try:
        let turnResult = game.resolveTurn(commands, rng)
        
        # Check for victory (game might end early)
        if turnResult.victoryCheck.victoryOccurred:
          echo &"  Victory achieved at turn {turn}: {turnResult.victoryCheck.status.description}"
          break
          
      except CatchableError as e:
        echo &"Turn {turn} crashed: {e.msg}"
        fail()
        break

      let elapsed = (cpuTime() - startTime) * 1000.0
      turnTimes.add(elapsed)

      # Check invariants each turn
      let violations = checkStateInvariants(game, turn)
      allViolations.add(violations)

    # Calculate statistics
    if turnTimes.len > 0:
      let avgTime = turnTimes.sum() / turnTimes.len.float
      let maxTime = turnTimes.max()
      let minTime = turnTimes.min()

      echo &"\nCompleted {turnTimes.len} turns"
      echo &"  Average turn time: {avgTime:.2f}ms"
      echo &"  Min: {minTime:.2f}ms, Max: {maxTime:.2f}ms"

    # Report any invariant violations
    if allViolations.len > 0:
      reportViolations(allViolations)

    # Basic sanity checks
    var houseCount = 0
    for _ in game.allHouses():
      houseCount += 1
    
    var colonyCount = 0
    for _ in game.allColonies():
      colonyCount += 1
    
    var fleetCount = 0
    for _ in game.allFleets():
      fleetCount += 1

    check houseCount > 0
    check colonyCount > 0
    echo &"  Final state: {houseCount} houses, {colonyCount} colonies, {fleetCount} fleets"

    # No critical violations
    let criticalViolations = allViolations.filterIt(
      it.severity == ViolationSeverity.Critical
    )
    check criticalViolations.len == 0

  test "Invalid fleet command handling":
    echo "\nTesting invalid fleet command..."

    var game = newGame()
    var rng = initRand(12345)

    # Get first house
    var firstHouseId: HouseId
    for (houseId, _) in game.activeHousesWithId():
      firstHouseId = houseId
      break

    # Create command with invalid target system
    var commands = initTable[HouseId, CommandPacket]()
    for (houseId, house) in game.activeHousesWithId():
      var packet = CommandPacket(
        houseId: houseId,
        turn: 1.int32,
        fleetCommands: @[],
        buildCommands: @[],
        repairCommands: @[],
        scrapCommands: @[],
        researchAllocation: ResearchAllocation(),
        diplomaticCommand: @[],
        populationTransfers: @[],
        terraformCommands: @[],
        colonyManagement: @[],
        espionageActions: @[],
        ebpInvestment: 0,
        cipInvestment: 0
      )

      # Add invalid command to first house
      if houseId == firstHouseId:
        packet.fleetCommands.add(FleetCommand(
          fleetId: FleetId(999999),  # Non-existent fleet
          commandType: FleetCommandType.Move,
          targetSystem: some(SystemId(999999)),  # Non-existent system
          targetFleet: none(FleetId),
          priority: 0,
          roe: none(int32)
        ))

      commands[houseId] = packet

    # Engine should handle gracefully (reject invalid command, continue)
    try:
      let turnResult = game.resolveTurn(commands, rng)
      echo "  Engine handled invalid fleet command gracefully"
      check turnResult.turnAdvanced
    except CatchableError as e:
      echo &"  Engine rejected invalid input: {e.msg}"
      # This is acceptable - engine validation caught it

when isMainModule:
  echo "========================================"
  echo "  Simple Stress Test - Engine Validation"
  echo "========================================"
  echo ""
