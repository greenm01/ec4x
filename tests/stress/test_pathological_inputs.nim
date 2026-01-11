## Pathological Input Fuzzing
##
## Tests engine behavior with invalid, malformed, and adversarial inputs:
## - Invalid system IDs
## - Non-existent fleet references
## - Negative values where positive expected
## - Out-of-bounds array access
## - Type mismatches and edge cases
##
## The engine should either:
## 1. Reject invalid inputs gracefully
## 2. Handle them without crashing
## 3. NOT corrupt game state
##
## Updated for new engine architecture (2026-01)

import std/[times, strformat, random, tables, options, sequtils, strutils]
import unittest
import stress_framework
import ../../src/engine/engine
import ../../src/engine/types/[core, command, fleet, house, tech, espionage, production, ship, facilities]
import ../../src/engine/state/[engine, iterators]
import ../../src/engine/turn_cycle/engine

proc createNoOpCommands(
    game: GameState, turn: int
): Table[HouseId, CommandPacket] =
  ## Create empty commands for all houses
  result = initTable[HouseId, CommandPacket]()
  for (houseId, house) in game.activeHousesWithId():
    result[houseId] = CommandPacket(
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

suite "Pathological Inputs: Invalid Orders":

  test "Fuzz: fleet commands with invalid system IDs":
    ## Try to move fleet to non-existent systems

    echo "\nFuzzing invalid system IDs..."

    var game = newGame()
    var rng = initRand(42)

    # Get first house and fleet
    var firstHouseId: HouseId
    var firstFleetId: FleetId
    var foundFleet = false

    for (houseId, _) in game.activeHousesWithId():
      firstHouseId = houseId
      break

    for (fleetId, fleet) in game.allFleetsWithId():
      if fleet.houseId == firstHouseId:
        firstFleetId = fleetId
        foundFleet = true
        break

    if not foundFleet:
      echo "  No fleets found, skipping"
      skip()

    echo &"  Testing fleet: {firstFleetId}"

    # Try various invalid system IDs
    let invalidSystemIds = [
      SystemId(0),            # Zero
      SystemId(999_999),      # Extremely large
      SystemId(high(uint32)), # Maximum uint32
    ]

    for invalidSys in invalidSystemIds:
      echo &"  Trying system ID: {invalidSys}"

      var commands = createNoOpCommands(game, 1)

      # Add invalid fleet command
      commands[firstHouseId].fleetCommands = @[
        FleetCommand(
          fleetId: firstFleetId,
          commandType: FleetCommandType.Move,
          targetSystem: some(invalidSys),
          targetFleet: none(FleetId),
          priority: 0,
          roe: none(int32)
        )
      ]

      # Engine should handle gracefully
      try:
        let turnResult = game.resolveTurn(commands, rng)

        # Check that state is still valid
        let violations = checkStateInvariants(game, 1)
        if violations.len > 0:
          echo &"    State corrupted after invalid system ID {invalidSys}"
          reportViolations(violations)
          fail()
        else:
          echo &"    Handled system ID {invalidSys} safely"

      except CatchableError as e:
        # Crash with clean error is acceptable
        echo &"    Rejected system ID {invalidSys}: {e.msg}"

  test "Fuzz: commands for non-existent fleets":
    ## Try to give commands to fleets that don't exist

    echo "\nFuzzing non-existent fleet IDs..."

    var game = newGame()
    var rng = initRand(43)

    var firstHouseId: HouseId
    for (houseId, _) in game.activeHousesWithId():
      firstHouseId = houseId
      break

    # Get a valid system to target
    var validSystemId: SystemId
    for (systemId, _) in game.allSystemsWithId():
      validSystemId = systemId
      break

    # Try various non-existent fleet IDs
    let fakeFleetIds = [
      FleetId(0),
      FleetId(999_999),
      FleetId(high(uint32)),
    ]

    for fakeFleetId in fakeFleetIds:
      echo &"  Trying fleet ID: {fakeFleetId}"

      var commands = createNoOpCommands(game, 1)
      commands[firstHouseId].fleetCommands = @[
        FleetCommand(
          fleetId: fakeFleetId,
          commandType: FleetCommandType.Move,
          targetSystem: some(validSystemId),
          targetFleet: none(FleetId),
          priority: 0,
          roe: none(int32)
        )
      ]

      try:
        let turnResult = game.resolveTurn(commands, rng)

        let violations = checkStateInvariants(game, 1)
        if violations.len > 0:
          echo "    State corrupted"
          reportViolations(violations)
          fail()
        else:
          echo "    Handled gracefully"

      except CatchableError as e:
        echo &"    Rejected: {e.msg}"

  test "Fuzz: build commands with invalid colony IDs":
    ## Try to build at non-existent colonies

    echo "\nFuzzing invalid colony IDs in build commands..."

    var game = newGame()
    var rng = initRand(44)

    var firstHouseId: HouseId
    for (houseId, _) in game.activeHousesWithId():
      firstHouseId = houseId
      break

    let invalidColonyIds = [
      ColonyId(0),
      ColonyId(999_999),
      ColonyId(high(uint32)),
    ]

    for invalidColony in invalidColonyIds:
      echo &"  Trying colony ID: {invalidColony}"

      var commands = createNoOpCommands(game, 1)
      commands[firstHouseId].buildCommands = @[
        BuildCommand(
          colonyId: invalidColony,
          buildType: BuildType.Ship,
          quantity: 1,
          shipClass: some(ShipClass.Scout),
          facilityClass: none(FacilityClass),
          industrialUnits: 0
        )
      ]

      try:
        let turnResult = game.resolveTurn(commands, rng)

        let violations = checkStateInvariants(game, 1)
        if violations.len > 0:
          reportViolations(violations)
          fail()
        else:
          echo "    Invalid build location handled safely"

      except CatchableError as e:
        echo &"    Rejected: {e.msg}"

  test "Fuzz: research allocation with invalid values":
    ## Try extreme/negative research allocations

    echo "\nFuzzing research allocations..."

    var game = newGame()
    var rng = initRand(45)

    var firstHouseId: HouseId
    for (houseId, _) in game.activeHousesWithId():
      firstHouseId = houseId
      break

    # Try various invalid allocations
    let testCases = [
      (-100'i32, 0'i32),      # Negative economic
      (0'i32, -50'i32),       # Negative science
      (1000'i32, 1000'i32),   # Exceeds 100% total
      (200'i32, 0'i32),       # Single field > 100%
    ]

    for (econ, sci) in testCases:
      echo &"  Trying allocation: E={econ}, S={sci}"

      var commands = createNoOpCommands(game, 1)
      commands[firstHouseId].researchAllocation = ResearchAllocation(
        economic: econ,
        science: sci,
        technology: initTable[TechField, int32]()
      )

      try:
        let turnResult = game.resolveTurn(commands, rng)

        let violations = checkStateInvariants(game, 1)
        if violations.len > 0:
          reportViolations(violations)
          fail()
        else:
          echo "    Handled safely"

      except CatchableError as e:
        echo &"    Rejected: {e.msg}"

suite "Pathological Inputs: Extreme Values":

  test "Extreme: very long fleet commands list":
    ## Give 1000+ commands (should be deduplicated per fleet)

    echo "\nTesting 1000 fleet commands..."

    var game = newGame()
    var rng = initRand(50)

    var firstHouseId: HouseId
    var firstFleetId: FleetId
    var foundFleet = false

    for (houseId, _) in game.activeHousesWithId():
      firstHouseId = houseId
      break

    for (fleetId, fleet) in game.allFleetsWithId():
      if fleet.houseId == firstHouseId:
        firstFleetId = fleetId
        foundFleet = true
        break

    if not foundFleet:
      skip()

    # Create 1000 Hold commands (should be mostly ignored/deduplicated)
    var massiveCommands: seq[FleetCommand] = @[]
    for i in 1..1000:
      massiveCommands.add(FleetCommand(
        fleetId: firstFleetId,
        commandType: FleetCommandType.Hold,
        targetSystem: none(SystemId),
        targetFleet: none(FleetId),
        priority: i.int32,
        roe: none(int32)
      ))

    var commands = createNoOpCommands(game, 1)
    commands[firstHouseId].fleetCommands = massiveCommands

    let startTime = cpuTime()
    try:
      let turnResult = game.resolveTurn(commands, rng)
      let elapsed = cpuTime() - startTime

      echo &"  Processed 1000 commands in {elapsed*1000:.1f}ms"

      let violations = checkStateInvariants(game, 1)
      if violations.len > 0:
        reportViolations(violations)
        fail()

    except CatchableError as e:
      echo &"  Crashed with 1000 commands: {e.msg}"
      fail()

  test "Extreme: maximum build queue":
    ## Try to queue 100+ construction projects

    echo "\nTesting maximum build queue..."

    var game = newGame()
    var rng = initRand(51)

    var firstHouseId: HouseId
    var firstColonyId: ColonyId
    var foundColony = false

    for (houseId, _) in game.activeHousesWithId():
      firstHouseId = houseId
      break

    for (colonyId, colony) in game.allColoniesWithId():
      if colony.owner == firstHouseId:
        firstColonyId = colonyId
        foundColony = true
        break

    if not foundColony:
      skip()

    # Create 100 Scout build commands
    var massiveQueue: seq[BuildCommand] = @[]
    for i in 1..100:
      massiveQueue.add(BuildCommand(
        colonyId: firstColonyId,
        buildType: BuildType.Ship,
        quantity: 1,
        shipClass: some(ShipClass.Scout),
        facilityClass: none(FacilityClass),
        industrialUnits: 0
      ))

    var commands = createNoOpCommands(game, 1)
    commands[firstHouseId].buildCommands = massiveQueue

    try:
      let turnResult = game.resolveTurn(commands, rng)
      echo "  Handled 100-item build queue"

      let violations = checkStateInvariants(game, 1)
      if violations.len > 0:
        reportViolations(violations)
        fail()

    except CatchableError as e:
      echo &"  Crashed: {e.msg}"
      fail()

  test "Extreme: orders from wrong house":
    ## Try to give orders for entities you don't own

    echo "\nTesting cross-house command attempts..."

    var game = newGame()
    var rng = initRand(52)

    # Get two different houses
    var houseIds: seq[HouseId] = @[]
    for (houseId, _) in game.activeHousesWithId():
      houseIds.add(houseId)
      if houseIds.len >= 2:
        break

    if houseIds.len < 2:
      echo "  Need at least 2 houses, skipping"
      skip()

    let house1 = houseIds[0]
    let house2 = houseIds[1]

    # Find a fleet belonging to house2
    var house2Fleet: FleetId
    var foundFleet = false
    for (fleetId, fleet) in game.allFleetsWithId():
      if fleet.houseId == house2:
        house2Fleet = fleetId
        foundFleet = true
        break

    if not foundFleet:
      echo "  No fleet for house2, skipping"
      skip()

    # House1 tries to command House2's fleet
    var commands = createNoOpCommands(game, 1)
    commands[house1].fleetCommands = @[
      FleetCommand(
        fleetId: house2Fleet,  # Not owned by house1!
        commandType: FleetCommandType.Hold,
        targetSystem: none(SystemId),
        targetFleet: none(FleetId),
        priority: 0,
        roe: none(int32)
      )
    ]

    try:
      let turnResult = game.resolveTurn(commands, rng)
      echo "  Engine accepted cross-house command (should be ignored)"

      # The fleet should NOT have changed
      let violations = checkStateInvariants(game, 1)
      if violations.len > 0:
        reportViolations(violations)
        fail()

    except CatchableError as e:
      echo &"  Engine rejected cross-house command: {e.msg}"

when isMainModule:
  echo "========================================"
  echo "  EC4X Pathological Input Fuzzing"
  echo "  Testing engine input validation"
  echo "========================================"
  echo ""
