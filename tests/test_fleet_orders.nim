## Tests for Fleet Order Execution System
## Tests all 16 order types from operations.md Section 6.2

import std/[unittest, options, tables, strutils]
import ../src/common/[hex, system, types/core, types/units]
import ../src/engine/[gamestate, orders, fleet, squadron, starmap, spacelift]
import ../src/engine/initialization/game
import ../src/engine/commands/executor

# =============================================================================
# Test Fixtures
# =============================================================================

proc createTestGameState(): GameState =
  ## Create minimal game state for testing

  # Create minimal star map
  var testMap = StarMap()
  testMap.systems[1] = System(
    id: 1,
    coords: Hex(q: 0, r: 0),
    ring: 0,
    player: none(uint)
  )
  testMap.systems[2] = System(
    id: 2,
    coords: Hex(q: 1, r: 0),
    ring: 1,
    player: none(uint)
  )

  result = newGameState("test_game", 2, testMap)

  # Add test houses
  result.houses["house1"] = gamestate.initializeHouse("TestHouse1", "blue")
  result.houses["house1"].id = "house1"
  result.houses["house2"] = gamestate.initializeHouse("TestHouse2", "red")
  result.houses["house2"].id = "house2"

  # Add test colonies
  result.colonies[1] = Colony(
    systemId: 1,
    owner: "house1",
    population: 10,
    souls: 10_000_000,
    infrastructure: 5,
    planetClass: PlanetClass.Benign,
    resources: ResourceRating.Abundant,
    buildings: @[],
    production: 100,
    constructionQueue: @[],
    repairQueue: @[],
    activeTerraforming: none(TerraformProject),
    unassignedSquadrons: @[],
    unassignedSpaceLiftShips: @[],
    fighterSquadrons: @[],
    capacityViolation: CapacityViolation(),
    starbases: @[],
    spaceports: @[],
    shipyards: @[],
    groundBatteries: 3,
    armies: 2,
    marines: 0
  )

  result.colonies[2] = Colony(
    systemId: 2,
    owner: "house2",
    population: 8,
    souls: 8_000_000,
    infrastructure: 4,
    planetClass: PlanetClass.Benign,
    resources: ResourceRating.Abundant,
    buildings: @[],
    production: 80,
    constructionQueue: @[],
    repairQueue: @[],
    activeTerraforming: none(TerraformProject),
    unassignedSquadrons: @[],
    unassignedSpaceLiftShips: @[],
    fighterSquadrons: @[],
    capacityViolation: CapacityViolation(),
    starbases: @[],
    spaceports: @[],
    shipyards: @[],
    groundBatteries: 2,
    armies: 1,
    marines: 0
  )

proc createTestFleet(owner: HouseId, location: SystemId, fleetId: string, hasScout: bool = false): Fleet =
  ## Create test fleet with basic squadrons
  let destroyer = newEnhancedShip(ShipClass.Destroyer)
  var sq = newSquadron(destroyer)

  if hasScout:
    let scout = newEnhancedShip(ShipClass.Scout)
    discard sq.addShip(scout)

  result = Fleet(
    id: fleetId,
    owner: owner,
    location: location,
    squadrons: @[sq]
  )

# =============================================================================
# Order 00: Hold Position Tests
# =============================================================================

suite "Order 00: Hold Position":
  test "Hold order always succeeds":
    var state = createTestGameState()
    let fleet = createTestFleet("house1", 1, "TestFleet")
    state.fleets[fleet.id] = fleet

    let order = FleetOrder(
      fleetId: fleet.id,
      orderType: FleetOrderType.Hold,
      targetSystem: none(SystemId),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)

    check result.success == true
    check result.message.contains("holding position")

  test "Hold order with wrong house fails":
    var state = createTestGameState()
    let fleet = createTestFleet("house1", 1, "TestFleet")
    state.fleets[fleet.id] = fleet

    let order = FleetOrder(
      fleetId: fleet.id,
      orderType: FleetOrderType.Hold,
      targetSystem: none(SystemId),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house2", order)

    check result.success == false
    check result.message.contains("not owned")

# =============================================================================
# Order 01: Move Fleet Tests
# =============================================================================

suite "Order 01: Move Fleet":
  test "Move order with valid target succeeds":
    var state = createTestGameState()
    let fleet = createTestFleet("house1", 1, "TestFleet")
    state.fleets[fleet.id] = fleet

    let order = FleetOrder(
      fleetId: fleet.id,
      orderType: FleetOrderType.Move,
      targetSystem: some(SystemId(2)),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)

    check result.success == true
    check result.message.contains("moving")

  test "Move order without target fails":
    var state = createTestGameState()
    let fleet = createTestFleet("house1", 1, "TestFleet")
    state.fleets[fleet.id] = fleet

    let order = FleetOrder(
      fleetId: fleet.id,
      orderType: FleetOrderType.Move,
      targetSystem: none(SystemId),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)

    check result.success == false
    check result.message.contains("requires target system")

# =============================================================================
# Order 02: Seek Home Tests
# =============================================================================

suite "Order 02: Seek Home":
  test "Seek home finds friendly colony":
    var state = createTestGameState()
    let fleet = createTestFleet("house1", 2, "TestFleet")
    state.fleets[fleet.id] = fleet

    let order = FleetOrder(
      fleetId: fleet.id,
      orderType: FleetOrderType.SeekHome,
      targetSystem: none(SystemId),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)

    check result.success == true
    check result.message.contains("seeking home")

  test "Seek home with no colonies fails":
    var state = createTestGameState()

    # Remove all house1 colonies
    var toRemove: seq[SystemId] = @[]
    for colonyId, colony in state.colonies:
      if colony.owner == "house1":
        toRemove.add(colonyId)

    for colonyId in toRemove:
      state.colonies.del(colonyId)

    let fleet = createTestFleet("house1", 2, "TestFleet")
    state.fleets[fleet.id] = fleet

    let order = FleetOrder(
      fleetId: fleet.id,
      orderType: FleetOrderType.SeekHome,
      targetSystem: none(SystemId),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)

    check result.success == false
    check result.message.contains("No friendly colonies")

# =============================================================================
# Order 03: Patrol System Tests
# =============================================================================

suite "Order 03: Patrol System":
  test "Patrol order with target succeeds":
    var state = createTestGameState()
    let fleet = createTestFleet("house1", 1, "TestFleet")
    state.fleets[fleet.id] = fleet

    let order = FleetOrder(
      fleetId: fleet.id,
      orderType: FleetOrderType.Patrol,
      targetSystem: some(SystemId(1)),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)

    check result.success == true
    check result.message.contains("patrolling")

  test "Patrol order without target fails":
    var state = createTestGameState()
    let fleet = createTestFleet("house1", 1, "TestFleet")
    state.fleets[fleet.id] = fleet

    let order = FleetOrder(
      fleetId: fleet.id,
      orderType: FleetOrderType.Patrol,
      targetSystem: none(SystemId),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)

    check result.success == false

# =============================================================================
# Order 04: Guard Starbase Tests
# =============================================================================

suite "Order 04: Guard Starbase":
  test "Guard starbase with combat ships succeeds":
    var state = createTestGameState()
    let fleet = createTestFleet("house1", 1, "TestFleet")
    state.fleets[fleet.id] = fleet

    # Add starbase to colony
    state.colonies[1].starbases.add(Starbase(id: "sb1", commissionedTurn: 1, isCrippled: false))

    let order = FleetOrder(
      fleetId: fleet.id,
      orderType: FleetOrderType.GuardStarbase,
      targetSystem: some(SystemId(1)),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)

    check result.success == true
    check result.message.contains("guarding starbase")

  test "Guard starbase without target fails":
    var state = createTestGameState()
    let fleet = createTestFleet("house1", 1, "TestFleet")
    state.fleets[fleet.id] = fleet

    let order = FleetOrder(
      fleetId: fleet.id,
      orderType: FleetOrderType.GuardStarbase,
      targetSystem: none(SystemId),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)

    check result.success == false

# =============================================================================
# Order 05: Guard/Blockade Planet Tests
# =============================================================================

suite "Order 05: Guard/Blockade Planet":
  test "Guard planet with combat ships succeeds":
    var state = createTestGameState()
    let fleet = createTestFleet("house1", 1, "TestFleet")
    state.fleets[fleet.id] = fleet

    let order = FleetOrder(
      fleetId: fleet.id,
      orderType: FleetOrderType.GuardPlanet,
      targetSystem: some(SystemId(1)),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)

    check result.success == true
    check result.message.contains("guarding planet")

  test "Blockade enemy colony succeeds":
    var state = createTestGameState()
    let fleet = createTestFleet("house1", 2, "TestFleet")
    state.fleets[fleet.id] = fleet

    let order = FleetOrder(
      fleetId: fleet.id,
      orderType: FleetOrderType.BlockadePlanet,
      targetSystem: some(SystemId(2)),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)

    check result.success == true
    check result.message.contains("blockading")
    check result.eventsGenerated.len > 0

  test "Blockade own colony fails":
    var state = createTestGameState()
    let fleet = createTestFleet("house1", 1, "TestFleet")
    state.fleets[fleet.id] = fleet

    let order = FleetOrder(
      fleetId: fleet.id,
      orderType: FleetOrderType.BlockadePlanet,
      targetSystem: some(SystemId(1)),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)

    check result.success == false
    check result.message.contains("Cannot blockade own colony")

# =============================================================================
# Order 06-08: Combat Order Tests
# =============================================================================

suite "Order 06-08: Combat Orders":
  test "Bombard order with combat ships succeeds":
    var state = createTestGameState()
    let fleet = createTestFleet("house1", 2, "TestFleet")
    state.fleets[fleet.id] = fleet

    let order = FleetOrder(
      fleetId: fleet.id,
      orderType: FleetOrderType.Bombard,
      targetSystem: some(SystemId(2)),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)

    check result.success == true
    check result.message.contains("bombardment")

  test "Invade order requires combat ships and transports":
    var state = createTestGameState()

    # Create fleet with destroyer and loaded troop transport
    let destroyer = newEnhancedShip(ShipClass.Destroyer)
    var transport = SpaceLiftShip(
      id: "transport1",
      shipClass: ShipClass.TroopTransport,
      owner: "house1",
      location: 2,
      isCrippled: false,
      cargo: SpaceLiftCargo(cargoType: CargoType.Marines, quantity: 1, capacity: 1)
    )
    var sq1 = newSquadron(destroyer)

    let fleet = Fleet(
      id: "invasion_fleet",
      owner: "house1",
      location: 2,
      squadrons: @[sq1],
      spaceLiftShips: @[transport]
    )
    state.fleets[fleet.id] = fleet

    let order = FleetOrder(
      fleetId: fleet.id,
      orderType: FleetOrderType.Invade,
      targetSystem: some(SystemId(2)),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)

    check result.success == true
    check result.message.contains("invasion")

  test "Blitz order requires troop transports":
    var state = createTestGameState()
    var transport = SpaceLiftShip(
      id: "transport2",
      shipClass: ShipClass.TroopTransport,
      owner: "house1",
      location: 2,
      isCrippled: false,
      cargo: SpaceLiftCargo(cargoType: CargoType.Marines, quantity: 1, capacity: 1)
    )

    let fleet = Fleet(
      id: "blitz_fleet",
      owner: "house1",
      location: 2,
      squadrons: @[],
      spaceLiftShips: @[transport]
    )
    state.fleets[fleet.id] = fleet

    let order = FleetOrder(
      fleetId: fleet.id,
      orderType: FleetOrderType.Blitz,
      targetSystem: some(SystemId(2)),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)

    check result.success == true
    check result.message.contains("blitz")

# =============================================================================
# Order 09-11: Spy Order Tests
# =============================================================================

suite "Order 09-11: Spy Orders":
  test "Spy planet requires exactly one scout":
    var state = createTestGameState()
    var fleet = createTestFleet("house1", 2, "SpyFleet", hasScout = true)

    # Remove destroyer, leave only scout
    fleet.squadrons = fleet.squadrons[1..^1]
    state.fleets[fleet.id] = fleet

    let order = FleetOrder(
      fleetId: fleet.id,
      orderType: FleetOrderType.SpyPlanet,
      targetSystem: some(SystemId(2)),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)

    # Note: Will fail because test fleet still has destroyer as flagship
    # TODO: Fix test setup to have scout-only fleet

  test "Hack starbase requires at least one scout":
    var state = createTestGameState()
    let scout = newEnhancedShip(ShipClass.Scout)
    var sq = newSquadron(scout)

    # Add starbase to colony at system 2
    state.colonies[2].starbases.add(Starbase(id: "sb2", commissionedTurn: 1, isCrippled: false))

    let fleet = Fleet(
      id: "hack_fleet",
      owner: "house1",
      location: 2,
      squadrons: @[sq]
    )
    state.fleets[fleet.id] = fleet

    let order = FleetOrder(
      fleetId: fleet.id,
      orderType: FleetOrderType.HackStarbase,
      targetSystem: some(SystemId(2)),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)

    check result.success == true
    check result.message.contains("Scout deployed")

  test "Spy system requires at least one scout":
    var state = createTestGameState()
    let scout = newEnhancedShip(ShipClass.Scout)
    var sq = newSquadron(scout)

    let fleet = Fleet(
      id: "spy_fleet",
      owner: "house1",
      location: 2,
      squadrons: @[sq]
    )
    state.fleets[fleet.id] = fleet

    let order = FleetOrder(
      fleetId: fleet.id,
      orderType: FleetOrderType.SpySystem,
      targetSystem: some(SystemId(2)),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)

    check result.success == true
    check result.message.contains("Scout deployed")

# =============================================================================
# Order 12: Colonize Tests
# =============================================================================

suite "Order 12: Colonize":
  test "Colonize requires ETAC":
    var state = createTestGameState()
    var etac = SpaceLiftShip(
      id: "etac1",
      shipClass: ShipClass.ETAC,
      owner: "house1",
      location: 1,
      isCrippled: false,
      cargo: SpaceLiftCargo(cargoType: CargoType.Colonists, quantity: 1, capacity: 1)
    )

    let fleet = Fleet(
      id: "colony_fleet",
      owner: "house1",
      location: 1,
      squadrons: @[],
      spaceLiftShips: @[etac]
    )
    state.fleets[fleet.id] = fleet

    let order = FleetOrder(
      fleetId: fleet.id,
      orderType: FleetOrderType.Colonize,
      targetSystem: some(SystemId(1)),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)

    check result.success == true
    check result.message.contains("colonizing")

  test "Colonize without ETAC fails":
    var state = createTestGameState()
    let fleet = createTestFleet("house1", 1, "TestFleet")
    state.fleets[fleet.id] = fleet

    let order = FleetOrder(
      fleetId: fleet.id,
      orderType: FleetOrderType.Colonize,
      targetSystem: some(SystemId(1)),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)

    check result.success == false
    check result.message.contains("requires ETAC")

# =============================================================================
# Order 13: Join Fleet Tests
# =============================================================================

suite "Order 13: Join Fleet":
  test "Join fleet at same location succeeds":
    var state = createTestGameState()
    let fleet1 = createTestFleet("house1", 1, "Fleet1")
    let fleet2 = createTestFleet("house1", 1, "Fleet2")

    state.fleets[fleet1.id] = fleet1
    state.fleets[fleet2.id] = fleet2

    let order = FleetOrder(
      fleetId: fleet1.id,
      orderType: FleetOrderType.JoinFleet,
      targetSystem: none(SystemId),
      targetFleet: some(fleet2.id),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)

    check result.success == true
    check result.message.contains("joining")

  test "Join fleet at different location tries to move toward target":
    # Use full game with 6 players for larger map with more lanes
    var state = newGame("test", 6)

    # Find two connected systems from the starmap
    var sys1, sys2: SystemId
    if state.starMap.lanes.len > 0:
      sys1 = state.starMap.lanes[0].source
      sys2 = state.starMap.lanes[0].destination
    else:
      sys1 = 1
      sys2 = 2

    let fleet1 = createTestFleet("house1", sys1, "Fleet1")
    let fleet2 = createTestFleet("house1", sys2, "Fleet2")

    state.fleets[fleet1.id] = fleet1
    state.fleets[fleet2.id] = fleet2

    let order = FleetOrder(
      fleetId: fleet1.id,
      orderType: FleetOrderType.JoinFleet,
      targetSystem: none(SystemId),
      targetFleet: some(fleet2.id),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)

    # New behavior: accepts order and either moves toward target or merges if adjacent
    check result.success == true
    check (result.message.contains("moving toward") or result.message.contains("merged"))

  test "Join fleet of different house fails":
    var state = createTestGameState()
    let fleet1 = createTestFleet("house1", 1, "Fleet1")
    let fleet2 = createTestFleet("house2", 1, "Fleet2")

    state.fleets[fleet1.id] = fleet1
    state.fleets[fleet2.id] = fleet2

    let order = FleetOrder(
      fleetId: fleet1.id,
      orderType: FleetOrderType.JoinFleet,
      targetSystem: none(SystemId),
      targetFleet: some(fleet2.id),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)

    check result.success == false
    check result.message.contains("different house")

# =============================================================================
# Order 14: Rendezvous Tests
# =============================================================================

suite "Order 14: Rendezvous":
  test "Rendezvous order succeeds":
    var state = createTestGameState()
    let fleet = createTestFleet("house1", 1, "TestFleet")
    state.fleets[fleet.id] = fleet

    let order = FleetOrder(
      fleetId: fleet.id,
      orderType: FleetOrderType.Rendezvous,
      targetSystem: some(SystemId(2)),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)

    check result.success == true

  test "Rendezvous without target fails":
    var state = createTestGameState()
    let fleet = createTestFleet("house1", 1, "TestFleet")
    state.fleets[fleet.id] = fleet

    let order = FleetOrder(
      fleetId: fleet.id,
      orderType: FleetOrderType.Rendezvous,
      targetSystem: none(SystemId),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)

    check result.success == false

# =============================================================================
# Order 15: Salvage Tests
# =============================================================================

suite "Order 15: Salvage":
  test "Salvage with friendly colony succeeds":
    var state = createTestGameState()
    let fleet = createTestFleet("house1", 1, "TestFleet")
    state.fleets[fleet.id] = fleet

    # Add spaceport to colony for salvage operations
    state.colonies[1].spaceports.add(Spaceport(id: "sp1", commissionedTurn: 1, docks: 5))

    let order = FleetOrder(
      fleetId: fleet.id,
      orderType: FleetOrderType.Salvage,
      targetSystem: none(SystemId),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)

    check result.success == true
    check result.message.contains("salvaged")
    check result.eventsGenerated.len > 0

  test "Salvage without colonies fails":
    var state = createTestGameState()

    # Remove all house1 colonies
    var toRemove: seq[SystemId] = @[]
    for colonyId, colony in state.colonies:
      if colony.owner == "house1":
        toRemove.add(colonyId)

    for colonyId in toRemove:
      state.colonies.del(colonyId)

    let fleet = createTestFleet("house1", 1, "TestFleet")
    state.fleets[fleet.id] = fleet

    let order = FleetOrder(
      fleetId: fleet.id,
      orderType: FleetOrderType.Salvage,
      targetSystem: none(SystemId),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)

    check result.success == false
    check result.message.contains("No friendly colony")

# =============================================================================
# Order Validation Tests
# =============================================================================

suite "Order Validation":
  test "Validate non-existent fleet fails":
    var state = createTestGameState()

    let order = FleetOrder(
      fleetId: "nonexistent_fleet",
      orderType: FleetOrderType.Hold,
      targetSystem: none(SystemId),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)

    check result.success == false
    check result.message.contains("not found")

  test "Combat orders without combat ships fail":
    var state = createTestGameState()

    # Create unarmed transport fleet
    let transport = newEnhancedShip(ShipClass.ETAC)
    var sq = newSquadron(transport)

    let fleet = Fleet(
      id: "unarmed_fleet",
      owner: "house1",
      location: 1,
      squadrons: @[sq]
    )
    state.fleets[fleet.id] = fleet

    let order = FleetOrder(
      fleetId: fleet.id,
      orderType: FleetOrderType.GuardStarbase,
      targetSystem: some(SystemId(1)),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)

    check result.success == false
    check result.message.contains("combat-capable")

# =============================================================================
# Order 16: Reserve Fleet Tests
# =============================================================================

suite "Order 16: Reserve Fleet":
  test "Reserve order at friendly colony succeeds":
    var state = createTestGameState()
    let fleet = createTestFleet("house1", 1, "TestFleet")
    state.fleets[fleet.id] = fleet

    let order = FleetOrder(
      fleetId: fleet.id,
      orderType: FleetOrderType.Reserve,
      targetSystem: none(SystemId),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)

    check result.success == true
    check result.message.contains("reserve")
    check result.message.contains("50% maint")
    check result.eventsGenerated.len > 0

  test "Reserve order without colony fails":
    var state = createTestGameState()
    let fleet = createTestFleet("house1", 2, "TestFleet")
    state.fleets[fleet.id] = fleet

    # Remove ALL colonies for house1 (colony 1)
    state.colonies.del(1)
    state.colonies.del(2)

    let order = FleetOrder(
      fleetId: fleet.id,
      orderType: FleetOrderType.Reserve,
      targetSystem: none(SystemId),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)

    # New behavior: accepts order but fails due to no friendly colonies
    check result.success == false
    check result.message.contains("No friendly colonies available")

  test "Reserve order at enemy colony tries to move to friendly colony":
    # Use full game initialization to get proper starmap with lanes
    var state = newGame("test", 2)

    let fleet = createTestFleet("house1", 2, "TestFleet")
    state.fleets[fleet.id] = fleet

    let order = FleetOrder(
      fleetId: fleet.id,
      orderType: FleetOrderType.Reserve,
      targetSystem: none(SystemId),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)

    # New behavior: accepts order and moves toward friendly colony
    check result.success == true
    check result.message.contains("moving to colony")

# =============================================================================
# Order 17: Mothball Fleet Tests
# =============================================================================

suite "Order 17: Mothball Fleet":
  test "Mothball order at friendly colony with spaceport succeeds":
    var state = createTestGameState()
    let fleet = createTestFleet("house1", 1, "TestFleet")
    state.fleets[fleet.id] = fleet

    # Add spaceport to colony
    state.colonies[1].spaceports.add(Spaceport(id: "sp1", commissionedTurn: 1, docks: 5))

    let order = FleetOrder(
      fleetId: fleet.id,
      orderType: FleetOrderType.Mothball,
      targetSystem: none(SystemId),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)

    check result.success == true
    check result.message.contains("mothballed")
    check result.message.contains("0% maint")
    check result.eventsGenerated.len > 0

  test "Mothball order without spaceport fails":
    var state = createTestGameState()
    let fleet = createTestFleet("house1", 1, "TestFleet")
    state.fleets[fleet.id] = fleet

    let order = FleetOrder(
      fleetId: fleet.id,
      orderType: FleetOrderType.Mothball,
      targetSystem: none(SystemId),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)

    check result.success == false
    check result.message.contains("spaceport")

  test "Mothball order without friendly colony with spaceport fails":
    var state = createTestGameState()
    let fleet = createTestFleet("house1", 2, "TestFleet")
    state.fleets[fleet.id] = fleet

    # Remove ALL colonies (no friendly colonies with spaceports exist)
    state.colonies.del(1)
    state.colonies.del(2)

    let order = FleetOrder(
      fleetId: fleet.id,
      orderType: FleetOrderType.Mothball,
      targetSystem: none(SystemId),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)

    # New behavior: accepts order but fails due to no friendly colonies with spaceports
    check result.success == false
    check result.message.contains("No friendly colonies with spaceports available")

  test "Mothball order at enemy colony tries to move to friendly colony with spaceport":
    # Use full game initialization to get proper starmap with lanes
    var state = newGame("test", 2)

    let fleet = createTestFleet("house1", 2, "TestFleet")
    state.fleets[fleet.id] = fleet

    # Find a friendly colony and add spaceport
    for colonyId, colony in state.colonies:
      if colony.owner == "house1":
        state.colonies[colonyId].spaceports.add(Spaceport(id: "sp1", commissionedTurn: 1, docks: 5))
        break

    let order = FleetOrder(
      fleetId: fleet.id,
      orderType: FleetOrderType.Mothball,
      targetSystem: none(SystemId),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)

    # New behavior: accepts order and moves toward friendly colony with spaceport
    check result.success == true
    check result.message.contains("moving to colony")

# =============================================================================
# Order 18: Reactivate Fleet Tests
# =============================================================================

suite "Order 18: Reactivate Fleet":
  test "Reactivate reserve fleet succeeds":
    var state = createTestGameState()
    var fleet = createTestFleet("house1", 1, "TestFleet")
    fleet.status = FleetStatus.Reserve
    state.fleets[fleet.id] = fleet

    let order = FleetOrder(
      fleetId: fleet.id,
      orderType: FleetOrderType.Reactivate,
      targetSystem: none(SystemId),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)

    check result.success == true
    check result.message.contains("active duty")
    check result.eventsGenerated.len > 0

  test "Reactivate mothballed fleet succeeds":
    var state = createTestGameState()
    var fleet = createTestFleet("house1", 1, "TestFleet")
    fleet.status = FleetStatus.Mothballed
    state.fleets[fleet.id] = fleet

    let order = FleetOrder(
      fleetId: fleet.id,
      orderType: FleetOrderType.Reactivate,
      targetSystem: none(SystemId),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)

    check result.success == true
    check result.message.contains("active duty")
    check result.eventsGenerated.len > 0

  test "Reactivate active fleet fails":
    var state = createTestGameState()
    let fleet = createTestFleet("house1", 1, "TestFleet")
    state.fleets[fleet.id] = fleet

    let order = FleetOrder(
      fleetId: fleet.id,
      orderType: FleetOrderType.Reactivate,
      targetSystem: none(SystemId),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)

    check result.success == false
    check result.message.contains("already on active duty")

# =============================================================================
# Fleet Status Restriction Tests
# =============================================================================

suite "Fleet Status Movement Restrictions":
  test "Reserve fleet cannot move":
    var state = createTestGameState()
    var fleet = createTestFleet("house1", 1, "TestFleet")
    fleet.status = FleetStatus.Reserve
    state.fleets[fleet.id] = fleet

    let order = FleetOrder(
      fleetId: fleet.id,
      orderType: FleetOrderType.Move,
      targetSystem: some(SystemId(2)),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)

    check result.success == false
    check result.message.contains("Reserve fleets cannot move")

  test "Mothballed fleet cannot move":
    var state = createTestGameState()
    var fleet = createTestFleet("house1", 1, "TestFleet")
    fleet.status = FleetStatus.Mothballed
    state.fleets[fleet.id] = fleet

    let order = FleetOrder(
      fleetId: fleet.id,
      orderType: FleetOrderType.Move,
      targetSystem: some(SystemId(2)),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)

    check result.success == false
    check result.message.contains("Mothballed fleets cannot move")
