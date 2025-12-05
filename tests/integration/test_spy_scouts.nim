## Integration test for spy scout intelligence gathering operations
## Tests orders 09, 10, and 11 (Spy on Planet, Hack Starbase, Spy on System)

import std/[unittest, tables, options, strutils]
import ../../src/engine/[gamestate, orders, fleet, squadron, starmap, resolve]
import ../../src/engine/research/types as res_types
import ../../src/engine/espionage/types as esp_types
import ../../src/engine/commands/executor
import ../../src/common/types/[core, units, combat, planets]
import ../../src/common/[hex, system]

suite "Spy Scout Intelligence Operations":

  setup:
    # Create a minimal star map
    var state = GameState()
    state.turn = 1
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

    # Create jump lanes connecting systems 0 -> 1 -> 2 -> 3 -> 4 -> 5
    for i in 0u..4u:
      state.starMap.lanes.add(JumpLane(
        source: i,
        destination: i + 1,
        laneType: LaneType.Major
      ))
      # Update adjacency for pathfinding
      if i notin state.starMap.adjacency:
        state.starMap.adjacency[i] = @[]
      if (i + 1) notin state.starMap.adjacency:
        state.starMap.adjacency[i + 1] = @[]
      state.starMap.adjacency[i].add(i + 1)
      state.starMap.adjacency[i + 1].add(i)

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

    # Give each house a colony with marines to prevent elimination
    state.colonies[0u] = createHomeColony(SystemId(0u), "house1")
    state.colonies[0u].marines = 1
    state.colonies[1u] = createHomeColony(SystemId(1u), "house2")
    state.colonies[1u].marines = 1

  test "Order 09: Deploy scout for planet intelligence gathering":
    # Create a fleet with one Scout
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
    check result.message.contains("deployed")
    check result.message.contains("traveling")

    # Verify fleet was removed (empty fleets are automatically deleted)
    check "fleet1" notin state.fleets

    # Verify spy scout was created and is traveling
    check state.spyScouts.len == 1
    for scoutId, spyScout in state.spyScouts:
      check spyScout.owner == "house1"
      check spyScout.targetSystem == 1u
      check spyScout.mission == SpyMissionType.SpyOnPlanet
      check spyScout.detected == false

  test "Order 10: Deploy scout to hack starbase":
    # Create a colony with starbase at system 2 (owned by house2)
    var colony = createHomeColony(2.SystemId, "house2")
    colony.starbases = @[Starbase(id: "sb1", commissionedTurn: 0, isCrippled: false)]
    colony.marines = 1
    state.colonies[2] = colony

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
    check result.message.contains("deployed")
    check result.message.contains("traveling")

    # Verify fleet was removed
    check "fleet1" notin state.fleets

    # Verify spy scout was created
    check state.spyScouts.len == 1
    for scoutId, spyScout in state.spyScouts:
      check spyScout.owner == "house1"
      check spyScout.targetSystem == 2u
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
    check result.message.contains("deployed")
    check result.message.contains("traveling")

    # Verify fleet was removed
    check "fleet1" notin state.fleets

    # Verify spy scout was created
    check state.spyScouts.len == 1
    for scoutId, spyScout in state.spyScouts:
      check spyScout.owner == "house1"
      check spyScout.targetSystem == 3u
      check spyScout.mission == SpyMissionType.SpyOnSystem
      check spyScout.detected == false

  test "Multiple scout squadrons gain mesh network bonuses":
    # Create a fleet with 3 scout squadrons for mesh network bonus (+1 ELI)
    var squadrons: seq[Squadron] = @[]
    for i in 0..2:
      let scout = newEnhancedShip(ShipClass.Scout, techLevel = 2)
      var squadron = newSquadron(scout, "sq" & $i, "house1", 0u)
      squadrons.add(squadron)

    var fleet = newFleet(squadrons = squadrons, id = "fleet1", owner = "house1", location = 0u)
    state.fleets["fleet1"] = fleet

    # Deploy spy mission with 3 scouts
    let order = FleetOrder(
      fleetId: "fleet1",
      orderType: FleetOrderType.SpyPlanet,
      targetSystem: some(1u),
      priority: 10
    )

    # Execute order - should succeed
    let result = executeFleetOrder(state, "house1", order)

    check result.success == true
    check result.message.contains("deployed")

    # Verify spy scout was created with merged scout count = 3
    check state.spyScouts.len == 1
    for scoutId, spyScout in state.spyScouts:
      check spyScout.mergedScoutCount == 3  # All 3 scouts merged
      check spyScout.owner == "house1"
      check spyScout.targetSystem == 1u

  test "Spy scouts travel to target over multiple turns":
    # Deploy a spy scout from system 0 to system 3 (3 jumps away)
    let scout = newEnhancedShip(ShipClass.Scout, techLevel = 2)
    var squadron = newSquadron(scout, "sq1", "house1", 0u)
    var fleet1 = newFleet(squadrons = @[squadron], id = "fleet1", owner = "house1", location = 0u)
    state.fleets["fleet1"] = fleet1

    let order = FleetOrder(
      fleetId: "fleet1",
      orderType: FleetOrderType.SpyPlanet,
      targetSystem: some(3u),
      priority: 10
    )

    discard executeFleetOrder(state, "house1", order)

    # Scout should be created and traveling
    check state.spyScouts.len == 1

    # Get the spy scout ID (format: spy-house1-1-3)
    var spyScout: SpyScout
    for id, scout in state.spyScouts:
      spyScout = scout
      check scout.targetSystem == 3u
      check scout.state == SpyScoutState.Traveling
      check scout.travelPath.len > 0
      check scout.mergedScoutCount == 1

  test "Spy scout survives when no rival ELI present":
    # Deploy a spy scout from house1 to system 1 (no rival scouts there)
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

    let result = executeFleetOrder(state, "house1", order)

    # Spy scout should be created successfully
    check result.success == true
    check state.spyScouts.len == 1

    # Verify spy scout properties
    for scoutId, spyScout in state.spyScouts:
      check spyScout.detected == false
      check spyScout.owner == "house1"
      check spyScout.targetSystem == 1u
      check spyScout.mergedScoutCount == 1

  test "Multiple spy scouts can operate simultaneously":
    # Deploy two spy scouts from house1 to different systems
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

      let result = executeFleetOrder(state, "house1", order)
      check result.success == true

    # Should have 2 spy scouts
    check state.spyScouts.len == 2

    # Verify both scouts are operational
    var scoutCount = 0
    for scoutId, spyScout in state.spyScouts:
      check spyScout.owner == "house1"
      check spyScout.detected == false
      check spyScout.state == SpyScoutState.Traveling
      check spyScout.mergedScoutCount == 1
      scoutCount += 1

    check scoutCount == 2
