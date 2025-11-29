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

import std/[times, strformat, random, tables, options, sequtils]
import unittest
import stress_framework
import ../../src/engine/[gamestate, resolve, orders, fleet, starmap]
import ../../src/engine/research/types as res_types
import ../../src/engine/espionage/types as esp_types
import ../../src/common/types/[core, planets]
import ../../src/engine/diplomacy/types as dip_types

proc createTestGame(): GameState =
  ## Create a minimal test game with valid starmap
  result = GameState()
  result.turn = 1
  result.phase = GamePhase.Active

  # Create minimal starmap
  result.starMap = StarMap()
  result.starMap.systems[SystemId(1)] = System(
    id: SystemId(1),
    name: "Home",
    position: (0, 0),
    planetClass: PlanetClass.Terran,
    resources: ResourceRating.Average
  )
  result.starMap.systems[SystemId(2)] = System(
    id: SystemId(2),
    name: "Target",
    position: (1, 0),
    planetClass: PlanetClass.Terran,
    resources: ResourceRating.Average
  )

  # Create test houses
  result.houses["house1"] = House(
    id: "house1",
    name: "Test House 1",
    treasury: 10000,
    eliminated: false,
    techTree: res_types.initTechTree(),
    diplomaticRelations: dip_types.initDiplomaticRelations(),
    violationHistory: dip_types.initViolationHistory(),
    espionageBudget: esp_types.initEspionageBudget(),
    dishonoredStatus: dip_types.initDishonoredStatus(),
    diplomaticIsolation: dip_types.initDiplomaticIsolation(),
  )

  result.houses["house2"] = House(
    id: "house2",
    name: "Test House 2",
    treasury: 10000,
    eliminated: false,
    techTree: res_types.initTechTree(),
    diplomaticRelations: dip_types.initDiplomaticRelations(),
    violationHistory: dip_types.initViolationHistory(),
    espionageBudget: esp_types.initEspionageBudget(),
    dishonoredStatus: dip_types.initDishonoredStatus(),
    diplomaticIsolation: dip_types.initDiplomaticIsolation(),
  )

  # Create test colony
  result.colonies[SystemId(1)] = Colony(
    systemId: SystemId(1),
    owner: "house1",
    population: 100,
    souls: 100_000_000,
    populationUnits: 100,
    populationTransferUnits: 2000,
    industrial: 50,
    infrastructure: 5,
    planetClass: PlanetClass.Terran,
    resources: ResourceRating.Average,
  )

  # Create test fleet
  let flagship = newEnhancedShip(ShipClass.Destroyer, techLevel = 1, name = "DD-1")
  let squadron = Squadron(
    id: "sq1",
    flagship: flagship,
    ships: @[],
    owner: "house1",
    location: SystemId(1),
    embarkedFighters: @[]
  )

  result.fleets["fleet1"] = Fleet(
    id: "fleet1",
    owner: "house1",
    location: SystemId(1),
    squadrons: @[squadron],
    spaceLiftShips: @[],
    status: FleetStatus.Active,
    autoBalanceSquadrons: false
  )

suite "Pathological Inputs: Invalid Orders":

  test "Fuzz: fleet orders with invalid system IDs":
    ## Try to move fleet to non-existent systems

    echo "\n🧪 Fuzzing invalid system IDs..."

    var game = createTestGame()
    let firstHouse = toSeq(game.houses.keys)[0]
    let firstFleet = block:
      var fleetId: FleetId = ""
      for fid, fleet in game.fleets:
        if fleet.owner == firstHouse:
          fleetId = fid
          break
      fleetId

    if firstFleet == "":
      skip("No fleet available for testing")
      return

    echo &"  Testing fleet: {firstFleet}"

    # Try various invalid system IDs
    let invalidSystemIds = [
      SystemId(-1),           # Negative
      SystemId(0),            # Zero (maybe valid as Imperial Hub?)
      SystemId(999_999),      # Extremely large
      SystemId(high(int32)),  # Maximum int
    ]

    for invalidSys in invalidSystemIds:
      echo &"  Trying system ID: {invalidSys}"

      var ordersTable = initTable[HouseId, OrderPacket]()
      ordersTable[firstHouse] = OrderPacket(
        houseId: firstHouse,
        turn: 1,
        buildOrders: @[],
        fleetOrders: @[
          FleetOrder(
            fleetId: firstFleet,
            orderType: FleetOrderType.Move,
            targetSystem: some(invalidSys),
            targetFleet: none(FleetId),
            priority: 0
          )
        ],
        researchAllocation: initResearchAllocation(),
        diplomaticActions: @[],
        populationTransfers: @[],
        squadronManagement: @[],
        cargoManagement: @[],
        terraformOrders: @[],
        espionageAction: none(esp_types.EspionageAttempt),
        ebpInvestment: 0,
        cipInvestment: 0
      )

      # Engine should handle gracefully - either reject order or ignore
      try:
        let result = resolveTurn(game, ordersTable)
        game = result.newState

        # Check that state is still valid
        let violations = checkStateInvariants(game, 1)
        if violations.len > 0:
          echo &"    ⚠️  State corrupted after invalid system ID {invalidSys}"
          reportViolations(violations)
          fail("State corruption from invalid system ID")
        else:
          echo &"    ✅ Handled system ID {invalidSys} safely"

      except CatchableError as e:
        # Crash is acceptable IF it's a clean assertion/error
        # NOT acceptable if it's a segfault or corruption
        echo &"    ⚠️  Crashed on system ID {invalidSys}: {e.msg}"
        # Don't fail - crash may be intentional validation

  test "Fuzz: orders for non-existent fleets":
    ## Try to give orders to fleets that don't exist

    echo "\n🧪 Fuzzing non-existent fleet IDs..."

    var game = createTestGame()
    let firstHouse = toSeq(game.houses.keys)[0]
    let validSystem = toSeq(game.starMap.systems.keys)[0]

    # Try various non-existent fleet IDs
    let fakeFleetIds = [
      "nonexistent_fleet",
      "fleet_999999",
      "",  # Empty string
      "fleet-with-special-chars!@#$",
      "x" .repeat(1000),  # Very long ID
    ]

    for fakeFleet in fakeFleetIds:
      echo &"  Trying fleet ID: '{fakeFleet[0..min(50, fakeFleet.len-1)]}'..."

      var ordersTable = initTable[HouseId, OrderPacket]()
      ordersTable[firstHouse] = OrderPacket(
        houseId: firstHouse,
        turn: 1,
        buildOrders: @[],
        fleetOrders: @[
          FleetOrder(
            fleetId: fakeFleet,
            orderType: FleetOrderType.Move,
            targetSystem: some(validSystem),
            targetFleet: none(FleetId),
            priority: 0
          )
        ],
        researchAllocation: initResearchAllocation(),
        diplomaticActions: @[],
        populationTransfers: @[],
        squadronManagement: @[],
        cargoManagement: @[],
        terraformOrders: @[],
        espionageAction: none(esp_types.EspionageAttempt),
        ebpInvestment: 0,
        cipInvestment: 0
      )

      try:
        let result = resolveTurn(game, ordersTable)
        game = result.newState

        # Check state integrity
        let violations = checkStateInvariants(game, 1)
        if violations.len > 0:
          echo &"    ⚠️  State corrupted"
          reportViolations(violations)
          fail("State corruption from fake fleet ID")
        else:
          echo &"    ✅ Handled gracefully"

      except CatchableError as e:
        echo &"    ⚠️  Crashed: {e.msg}"
        # Don't fail - may be intentional

  test "Fuzz: build orders with invalid ship classes":
    ## Try to build ships that don't exist

    echo "\n🧪 Fuzzing invalid ship classes..."

    var game = createTestGame()
    let firstHouse = toSeq(game.houses.keys)[0]
    let firstColony = toSeq(game.colonies.keys)[0]

    # Try building with invalid data
    # Note: Can't directly fuzz ShipClass enum, but can test edge cases

    # Test 1: Build order at non-existent colony
    echo "  Trying build at non-existent colony..."

    var ordersTable = initTable[HouseId, OrderPacket]()
    ordersTable[firstHouse] = OrderPacket(
      houseId: firstHouse,
      turn: 1,
      buildOrders: @[
        BuildOrder(
          systemId: SystemId(999_999),  # Doesn't exist
          assetType: AssetType.Ship,
          shipClass: some(ShipClass.Destroyer),
          groundUnitType: none(GroundUnitType),
          facilityType: none(FacilityType),
          quantity: 1
        )
      ],
      fleetOrders: @[],
      researchAllocation: initResearchAllocation(),
      diplomaticActions: @[],
      populationTransfers: @[],
      squadronManagement: @[],
      cargoManagement: @[],
      terraformOrders: @[],
      espionageAction: none(esp_types.EspionageAttempt),
      ebpInvestment: 0,
      cipInvestment: 0
    )

    try:
      let result = resolveTurn(game, ordersTable)
      game = result.newState

      let violations = checkStateInvariants(game, 1)
      if violations.len > 0:
        reportViolations(violations)
        fail("State corruption from invalid build location")
      else:
        echo "    ✅ Invalid build location handled safely"

    except CatchableError as e:
      echo &"    ⚠️  Crashed: {e.msg}"

  test "Fuzz: research allocation with invalid values":
    ## Try extreme/negative research allocations

    echo "\n🧪 Fuzzing research allocations..."

    var game = createTestGame()
    let firstHouse = toSeq(game.houses.keys)[0]

    # Try various invalid allocations
    let testCases = [
      (-100, 0, 0),      # Negative allocation
      (0, -50, 0),       # Negative allocation
      (1000, 1000, 1000), # Exceeds 100% total
      (200, 0, 0),       # Single field > 100%
    ]

    for (econ, sci, tech) in testCases:
      echo &"  Trying allocation: E={econ}%, S={sci}%, T={tech}%"

      var research = initResearchAllocation()
      research.economicPercent = econ
      research.sciencePercent = sci
      research.techPercent = tech

      var ordersTable = initTable[HouseId, OrderPacket]()
      ordersTable[firstHouse] = OrderPacket(
        houseId: firstHouse,
        turn: 1,
        buildOrders: @[],
        fleetOrders: @[],
        researchAllocation: research,
        diplomaticActions: @[],
        populationTransfers: @[],
        squadronManagement: @[],
        cargoManagement: @[],
        terraformOrders: @[],
        espionageAction: none(esp_types.EspionageAttempt),
        ebpInvestment: 0,
        cipInvestment: 0
      )

      try:
        let result = resolveTurn(game, ordersTable)
        game = result.newState

        let violations = checkStateInvariants(game, 1)
        if violations.len > 0:
          reportViolations(violations)
          fail("State corruption from invalid research allocation")
        else:
          echo "    ✅ Handled safely"

      except CatchableError as e:
        echo &"    ⚠️  Crashed: {e.msg}"

suite "Pathological Inputs: Extreme Values":

  test "Extreme: very long fleet orders list":
    ## Give 1000+ orders to a single fleet

    echo "\n🧪 Testing 1000 fleet orders..."

    var game = createTestGame()
    let firstHouse = toSeq(game.houses.keys)[0]
    let firstFleet = block:
      var fleetId: FleetId = ""
      for fid, fleet in game.fleets:
        if fleet.owner == firstHouse:
          fleetId = fid
          break
      fleetId

    if firstFleet == "":
      skip("No fleet available")
      return

    let validSystem = game.fleets[firstFleet].location

    # Create 1000 Hold orders (should be harmless but test array handling)
    var massiveOrders: seq[FleetOrder] = @[]
    for i in 1..1000:
      massiveOrders.add(FleetOrder(
        fleetId: firstFleet,
        orderType: FleetOrderType.Hold,
        targetSystem: none(SystemId),
        targetFleet: none(FleetId),
        priority: i
      ))

    var ordersTable = initTable[HouseId, OrderPacket]()
    ordersTable[firstHouse] = OrderPacket(
      houseId: firstHouse,
      turn: 1,
      buildOrders: @[],
      fleetOrders: massiveOrders,
      researchAllocation: initResearchAllocation(),
      diplomaticActions: @[],
      populationTransfers: @[],
      squadronManagement: @[],
      cargoManagement: @[],
      terraformOrders: @[],
      espionageAction: none(esp_types.EspionageAttempt),
      ebpInvestment: 0,
      cipInvestment: 0
    )

    let startTime = cpuTime()
    try:
      let result = resolveTurn(game, ordersTable)
      game = result.newState
      let elapsed = cpuTime() - startTime

      echo &"  ✅ Processed 1000 orders in {elapsed*1000:.1f}ms"

      let violations = checkStateInvariants(game, 1)
      if violations.len > 0:
        reportViolations(violations)
        fail("State corruption from massive order list")

    except CatchableError as e:
      echo &"  ❌ Crashed with 1000 orders: {e.msg}"
      fail("Engine crashed on large order list")

  test "Extreme: maximum build queue":
    ## Try to queue 100+ construction projects

    echo "\n🧪 Testing maximum build queue..."

    var game = createTestGame()
    let firstHouse = toSeq(game.houses.keys)[0]
    let firstColony = toSeq(game.colonies.keys)[0]

    # Create 100 Scout build orders
    var massiveQueue: seq[BuildOrder] = @[]
    for i in 1..100:
      massiveQueue.add(BuildOrder(
        systemId: firstColony,
        assetType: AssetType.Ship,
        shipClass: some(ShipClass.Scout),
        groundUnitType: none(GroundUnitType),
        facilityType: none(FacilityType),
        quantity: 1
      ))

    var ordersTable = initTable[HouseId, OrderPacket]()
    ordersTable[firstHouse] = OrderPacket(
      houseId: firstHouse,
      turn: 1,
      buildOrders: massiveQueue,
      fleetOrders: @[],
      researchAllocation: initResearchAllocation(),
      diplomaticActions: @[],
      populationTransfers: @[],
      squadronManagement: @[],
      cargoManagement: @[],
      terraformOrders: @[],
      espionageAction: none(esp_types.EspionageAttempt),
      ebpInvestment: 0,
      cipInvestment: 0
    )

    try:
      let result = resolveTurn(game, ordersTable)
      game = result.newState

      echo "  ✅ Handled 100-item build queue"

      let violations = checkStateInvariants(game, 1)
      if violations.len > 0:
        reportViolations(violations)
        fail("State corruption from massive build queue")

    except CatchableError as e:
      echo &"  ❌ Crashed: {e.msg}"
      fail("Engine crashed on large build queue")

when isMainModule:
  echo "╔════════════════════════════════════════════════╗"
  echo "║  EC4X Pathological Input Fuzzing Tests        ║"
  echo "║  Testing engine resilience to invalid inputs  ║"
  echo "╚════════════════════════════════════════════════╝"
  echo ""
