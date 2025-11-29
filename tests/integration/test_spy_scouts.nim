## Integration test for spy scout intelligence gathering operations
## Tests orders 09, 10, and 11 (Spy on Planet, Hack Starbase, Spy on System)

import std/[unittest, tables, options, strutils]
import ../../src/engine/[gamestate, orders, fleet, squadron, starmap, resolve]
import ../../src/engine/research/types as res_types
import ../../src/engine/commands/executor
import ../../src/engine/intelligence/detection
import ../../src/common/types/[core, units, combat]
import ../../src/common/[hex, system]

suite "Spy Scout Intelligence Operations":

  setup:
    # Create a minimal star map
    var state = GameState()
    state.turn = 1
    state.year = 2501
    state.month = 1
    state.phase = GamePhase.Active

    # Create a simple starmap with 6 systems
    state.starMap = StarMap(
      systems: initTable[uint, System](),
      lanes: @[],
      adjacency: initTable[uint, seq[uint]](),
      playerCount: 2,
      numRings: 3,
      hubId: 0,
      playerSystemIds: @[]
    )

    # Add 6 systems
    for i in 0u..5u:
      state.starMap.systems[i] = System(
        id: i,
        coords: hex(int(i), 0),
        ring: uint32(i div 2),
        player: none(uint)
      )

    # Initialize houses
    state.houses["house1"] = initializeHouse("House Alpha", "blue")
    state.houses["house2"] = initializeHouse("House Beta", "red")

    # Give houses some starting resources
    state.houses["house1"].treasury = 5000
    state.houses["house2"].treasury = 5000

    # Initialize empty tables
    state.fleets = initTable[FleetId, Fleet]()
    state.colonies = initTable[SystemId, Colony]()
    state.spyScouts = initTable[string, SpyScout]()

  test "Order 09: Deploy scout for planet intelligence gathering":
    # Create a fleet with one Scout
    # TODO: ELI level should come from house tech tree, not ship techLevel
    let scout = newEnhancedShip(ShipClass.Scout, techLevel = 1)
    var squadron = newSquadron(scout, "sq1", "house1", 0u)
    var fleet = newFleet(squadrons = @[squadron], id = "fleet1", owner = "house1", location = 0u)

    state.fleets["fleet1"] = fleet

    # Create spy planet order
    let order = FleetOrder(
      fleetId: "fleet1",
      orderType: FleetOrderType.SpyPlanet,
      targetSystem: some(1u),
      priority: 10
    )

    # Execute order
    let result = executeFleetOrder(state, "house1", order)

    check result.success == true
    check result.message.contains("spy on planet")

    # Verify scout was removed from fleet
    check state.fleets["fleet1"].squadrons.len == 0

    # Verify spy scout was created
    check state.spyScouts.len == 1
    for scoutId, spyScout in state.spyScouts:
      check spyScout.owner == "house1"
      check spyScout.location == 1u
      check spyScout.eliLevel == 1  # Currently uses ship's base tech level
      check spyScout.mission == SpyMissionType.SpyOnPlanet
      check spyScout.detected == false

  test "Order 10: Deploy scout to hack starbase":
    # Create a fleet with one Scout
    let scout = newEnhancedShip(ShipClass.Scout, techLevel = 1)
    var squadron = newSquadron(scout, "sq1", "house1", 0u)
    var fleet = newFleet(squadrons = @[squadron], id = "fleet1", owner = "house1", location = 0u)

    state.fleets["fleet1"] = fleet

    # Create hack starbase order
    let order = FleetOrder(
      fleetId: "fleet1",
      orderType: FleetOrderType.HackStarbase,
      targetSystem: some(2u),
      priority: 10
    )

    # Execute order
    let result = executeFleetOrder(state, "house1", order)

    check result.success == true
    check result.message.contains("infiltrating starbase")

    # Verify scout was removed from fleet
    check state.fleets["fleet1"].squadrons.len == 0

    # Verify spy scout was created
    check state.spyScouts.len == 1
    for scoutId, spyScout in state.spyScouts:
      check spyScout.owner == "house1"
      check spyScout.location == 2u
      check spyScout.eliLevel == 1
      check spyScout.mission == SpyMissionType.HackStarbase
      check spyScout.detected == false

  test "Order 11: Deploy scout for system surveillance":
    # Create a fleet with one Scout
    let scout = newEnhancedShip(ShipClass.Scout, techLevel = 1)
    var squadron = newSquadron(scout, "sq1", "house1", 0u)
    var fleet = newFleet(squadrons = @[squadron], id = "fleet1", owner = "house1", location = 0u)

    state.fleets["fleet1"] = fleet

    # Create spy system order
    let order = FleetOrder(
      fleetId: "fleet1",
      orderType: FleetOrderType.SpySystem,
      targetSystem: some(3u),
      priority: 10
    )

    # Execute order
    let result = executeFleetOrder(state, "house1", order)

    check result.success == true
    check result.message.contains("spy on system")

    # Verify scout was removed from fleet
    check state.fleets["fleet1"].squadrons.len == 0

    # Verify spy scout was created
    check state.spyScouts.len == 1
    for scoutId, spyScout in state.spyScouts:
      check spyScout.owner == "house1"
      check spyScout.location == 3u
      check spyScout.eliLevel == 1
      check spyScout.mission == SpyMissionType.SpyOnSystem
      check spyScout.detected == false

  test "Spy scout requires exactly one scout":
    # Create a fleet with two scouts
    let scout1 = newEnhancedShip(ShipClass.Scout, techLevel = 2)
    let scout2 = newEnhancedShip(ShipClass.Scout, techLevel = 2)
    var squadron1 = newSquadron(scout1, "sq1", "house1", 0u)
    var squadron2 = newSquadron(scout2, "sq2", "house1", 0u)
    var fleet = newFleet(squadrons = @[squadron1, squadron2], id = "fleet1", owner = "house1", location = 0u)

    state.fleets["fleet1"] = fleet

    # Try to create spy planet order
    let order = FleetOrder(
      fleetId: "fleet1",
      orderType: FleetOrderType.SpyPlanet,
      targetSystem: some(1u),
      priority: 10
    )

    # Execute order - should fail
    let result = executeFleetOrder(state, "house1", order)

    check result.success == false
    check result.message.contains("exactly one Scout")
    check result.message.contains("found 2")

  test "Spy scout detection by rival fleet with scouts":
    # Deploy a spy scout from house1
    let scout = newEnhancedShip(ShipClass.Scout, techLevel = 2)
    var squadron = newSquadron(scout, "sq1", "house1", 0u)
    var fleet1 = newFleet(squadrons = @[squadron], id = "fleet1", owner = "house1", location = 0u)
    state.fleets["fleet1"] = fleet1

    let order = FleetOrder(
      fleetId: "fleet1",
      orderType: FleetOrderType.SpyPlanet,
      targetSystem: some(1u),
      priority: 10
    )

    discard executeFleetOrder(state, "house1", order)

    # Create a house2 fleet at the target system with higher ELI scouts
    let detector1 = newEnhancedShip(ShipClass.Scout, techLevel = 4)
    let detector2 = newEnhancedShip(ShipClass.Scout, techLevel = 4)
    var detectorSq1 = newSquadron(detector1, "sq2", "house2", 1u)
    var detectorSq2 = newSquadron(detector2, "sq3", "house2", 1u)
    var fleet2 = newFleet(squadrons = @[detectorSq1, detectorSq2], id = "fleet2", owner = "house2", location = 1u)
    state.fleets["fleet2"] = fleet2

    # Resolve turn - should attempt detection
    var orders = initTable[HouseId, OrderPacket]()
    let result = resolveTurn(state, orders)

    # Spy scout may be detected (probabilistic)
    # With ELI 4 detectors vs ELI 2 spy, detection is likely
    # Just verify the system processes without errors
    check result.newState.turn == state.turn + 1

  test "Spy scout survives when no rival ELI present":
    # Deploy a spy scout from house1
    let scout = newEnhancedShip(ShipClass.Scout, techLevel = 2)
    var squadron = newSquadron(scout, "sq1", "house1", 0u)
    var fleet1 = newFleet(squadrons = @[squadron], id = "fleet1", owner = "house1", location = 0u)
    state.fleets["fleet1"] = fleet1

    let order = FleetOrder(
      fleetId: "fleet1",
      orderType: FleetOrderType.SpyPlanet,
      targetSystem: some(1u),
      priority: 10
    )

    discard executeFleetOrder(state, "house1", order)

    # No rival fleets at target system - scout should survive
    var orders = initTable[HouseId, OrderPacket]()
    let result = resolveTurn(state, orders)

    # Spy scout should still exist
    check result.newState.spyScouts.len == 1
    for scoutId, spyScout in result.newState.spyScouts:
      check spyScout.detected == false
      check spyScout.owner == "house1"

  test "Multiple spy scouts can operate simultaneously":
    # Deploy two spy scouts from house1
    for i in 0..1:
      let scout = newEnhancedShip(ShipClass.Scout, techLevel = 2)
      var squadron = newSquadron(scout, "sq" & $i, "house1", 0u)
      var fleet = newFleet(squadrons = @[squadron], id = "fleet" & $i, owner = "house1", location = 0u)
      state.fleets["fleet" & $i] = fleet

      let order = FleetOrder(
        fleetId: "fleet" & $i,
        orderType: FleetOrderType.SpyPlanet,
        targetSystem: some(uint(i + 1)),
        priority: 10
      )

      discard executeFleetOrder(state, "house1", order)

    # Should have 2 spy scouts
    check state.spyScouts.len == 2

    # Resolve turn
    var orders = initTable[HouseId, OrderPacket]()
    let result = resolveTurn(state, orders)

    # Both scouts should survive (no rivals)
    check result.newState.spyScouts.len == 2
