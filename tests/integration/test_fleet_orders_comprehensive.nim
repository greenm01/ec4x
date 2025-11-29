## Comprehensive Fleet Order Integration Tests
##
## Tests all 19 fleet orders from operations.md Section 6.2
## This file provides validation, integration, and mechanics testing for all fleet orders

import std/[unittest, tables, options, strformat, strutils]
import ../../src/engine/[gamestate, starmap, fleet, ship, squadron, orders, resolve]
import ../../src/engine/commands/executor
import ../../src/common/types/[core, units, combat]
import ../../src/common/[hex, system]

suite "Fleet Orders: Complete Integration Tests":

  proc createTestGameState(): GameState =
    ## Create a game state with multiple systems for comprehensive testing
    result = GameState()
    result.turn = 1
    result.phase = GamePhase.Active

    # Create starmap with 5 systems
    result.starMap = StarMap(
      systems: initTable[uint, System](),
      lanes: @[],
      adjacency: initTable[uint, seq[uint]](),
      playerCount: 2,
      numRings: 5,
      hubId: 0,
      playerSystemIds: @[]
    )

    # Add 5 systems
    for i in 1u..5u:
      let playerOwner =
        if i <= 2: some(0u)
        elif i <= 4: some(1u)
        else: none(uint)

      result.starMap.systems[i] = System(
        id: i,
        coords: hex(int(i), 0),
        ring: uint32(i),
        player: playerOwner
      )

    # Add major lanes connecting systems
    for i in 1u..4u:
      result.starMap.lanes.add(JumpLane(
        source: i,
        destination: i + 1,
        laneType: LaneType.Major
      ))

      # Update adjacency
      if i notin result.starMap.adjacency:
        result.starMap.adjacency[i] = @[]
      if (i + 1) notin result.starMap.adjacency:
        result.starMap.adjacency[i + 1] = @[]
      result.starMap.adjacency[i].add(i + 1)
      result.starMap.adjacency[i + 1].add(i)

    # Create two houses
    result.houses[HouseId("house1")] = House(
      id: "house1",
      name: "House Alpha",
      treasury: 10000,
      eliminated: false
    )

    result.houses[HouseId("house2")] = House(
      id: "house2",
      name: "House Beta",
      treasury: 10000,
      eliminated: false
    )

    # House 1 owns systems 1, 2
    for sysId in 1u..2u:
      result.colonies[sysId] = Colony(
        systemId: sysId,
        owner: "house1",
        population: 100,
        infrastructure: 50,
        spaceports: @[Spaceport(
          id: fmt"spaceport-{sysId}",
          commissionedTurn: 1,
          docks: 5
        )]
      )

    # House 2 owns systems 3, 4
    for sysId in 3u..4u:
      result.colonies[sysId] = Colony(
        systemId: sysId,
        owner: "house2",
        population: 100,
        infrastructure: 50,
        spaceports: @[Spaceport(
          id: fmt"spaceport-{sysId}",
          commissionedTurn: 1,
          docks: 5
        )]
      )

  # ==========================================================================
  # Order 00: Hold Position
  # ==========================================================================

  test "Order 00: Hold - basic validation":
    var state = createTestGameState()

    # Create test fleet
    let destroyer = newEnhancedShip(ShipClass.Destroyer)
    var sq = newSquadron(destroyer)
    let testFleet = Fleet(
      id: "fleet-1",
      squadrons: @[sq],
      spaceLiftShips: @[],
      owner: "house1",
      location: 1,
      status: FleetStatus.Active
    )
    state.fleets["fleet-1"] = testFleet

    let order = FleetOrder(
      fleetId: "fleet-1",
      orderType: FleetOrderType.Hold,
      targetSystem: none(uint),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)
    check result.success == true
    check result.message.contains("holding")

  # ==========================================================================
  # Order 01: Move Fleet
  # ==========================================================================

  test "Order 01: Move - basic movement":
    var state = createTestGameState()

    let destroyer = newEnhancedShip(ShipClass.Destroyer)
    var sq = newSquadron(destroyer)
    let testFleet = Fleet(
      id: "fleet-1",
      squadrons: @[sq],
      spaceLiftShips: @[],
      owner: "house1",
      location: 1,
      status: FleetStatus.Active
    )
    state.fleets["fleet-1"] = testFleet

    let order = FleetOrder(
      fleetId: "fleet-1",
      orderType: FleetOrderType.Move,
      targetSystem: some(2u),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)
    check result.success == true

  # ==========================================================================
  # Order 02: Seek Home
  # ==========================================================================

  test "Order 02: SeekHome - finds closest friendly colony":
    var state = createTestGameState()

    let destroyer = newEnhancedShip(ShipClass.Destroyer)
    var sq = newSquadron(destroyer)
    let testFleet = Fleet(
      id: "fleet-1",
      squadrons: @[sq],
      spaceLiftShips: @[],
      owner: "house1",
      location: 3, # At enemy territory
      status: FleetStatus.Active
    )
    state.fleets["fleet-1"] = testFleet

    let order = FleetOrder(
      fleetId: "fleet-1",
      orderType: FleetOrderType.SeekHome,
      targetSystem: none(uint),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)
    check result.success == true
    check result.message.contains("seeking home")

  # ==========================================================================
  # Order 03: Patrol System
  # ==========================================================================

  test "Order 03: Patrol - sets patrol status":
    var state = createTestGameState()

    let destroyer = newEnhancedShip(ShipClass.Destroyer)
    var sq = newSquadron(destroyer)
    let testFleet = Fleet(
      id: "fleet-1",
      squadrons: @[sq],
      spaceLiftShips: @[],
      owner: "house1",
      location: 1,
      status: FleetStatus.Active
    )
    state.fleets["fleet-1"] = testFleet

    let order = FleetOrder(
      fleetId: "fleet-1",
      orderType: FleetOrderType.Patrol,
      targetSystem: some(1u),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)
    check result.success == true
    check result.message.contains("patrolling")

  # ==========================================================================
  # Order 04: Guard Starbase
  # ==========================================================================

  test "Order 04: GuardStarbase - requires combat ships":
    var state = createTestGameState()

    let destroyer = newEnhancedShip(ShipClass.Destroyer)
    var sq = newSquadron(destroyer)
    let testFleet = Fleet(
      id: "fleet-1",
      squadrons: @[sq],
      spaceLiftShips: @[],
      owner: "house1",
      location: 1,
      status: FleetStatus.Active
    )
    state.fleets["fleet-1"] = testFleet

    let order = FleetOrder(
      fleetId: "fleet-1",
      orderType: FleetOrderType.GuardStarbase,
      targetSystem: some(1u),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)
    check result.success == true
    check result.message.contains("guarding starbase")

  # ==========================================================================
  # Order 05: Guard/Blockade Planet
  # ==========================================================================

  test "Order 05: GuardPlanet - defends colony":
    var state = createTestGameState()

    let destroyer = newEnhancedShip(ShipClass.Destroyer)
    var sq = newSquadron(destroyer)
    let testFleet = Fleet(
      id: "fleet-1",
      squadrons: @[sq],
      spaceLiftShips: @[],
      owner: "house1",
      location: 1,
      status: FleetStatus.Active
    )
    state.fleets["fleet-1"] = testFleet

    let order = FleetOrder(
      fleetId: "fleet-1",
      orderType: FleetOrderType.GuardPlanet,
      targetSystem: some(1u),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)
    check result.success == true
    check result.message.contains("guarding planet")

  test "Order 05: BlockadePlanet - blockades enemy colony":
    var state = createTestGameState()

    let destroyer = newEnhancedShip(ShipClass.Destroyer)
    var sq = newSquadron(destroyer)
    let testFleet = Fleet(
      id: "fleet-1",
      squadrons: @[sq],
      spaceLiftShips: @[],
      owner: "house1",
      location: 3, # Enemy colony
      status: FleetStatus.Active
    )
    state.fleets["fleet-1"] = testFleet

    let order = FleetOrder(
      fleetId: "fleet-1",
      orderType: FleetOrderType.BlockadePlanet,
      targetSystem: some(3u),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)
    check result.success == true
    check result.message.contains("blockading")

  # ==========================================================================
  # Order 06: Bombard Planet
  # ==========================================================================

  test "Order 06: Bombard - requires combat ships":
    var state = createTestGameState()

    let destroyer = newEnhancedShip(ShipClass.Destroyer)
    var sq = newSquadron(destroyer)
    let testFleet = Fleet(
      id: "fleet-1",
      squadrons: @[sq],
      spaceLiftShips: @[],
      owner: "house1",
      location: 3,
      status: FleetStatus.Active
    )
    state.fleets["fleet-1"] = testFleet

    let order = FleetOrder(
      fleetId: "fleet-1",
      orderType: FleetOrderType.Bombard,
      targetSystem: some(3u),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)
    check result.success == true
    check result.message.contains("bombardment")

  # ==========================================================================
  # Order 07: Invade Planet
  # ==========================================================================

  test "Order 07: Invade - requires combat ships and transports":
    var state = createTestGameState()

    let destroyer = newEnhancedShip(ShipClass.Destroyer)
    var sq = newSquadron(destroyer)

    # Add troop transport as spacelift ship
    let transport = SpaceLiftShip(
      id: "transport-1",
      shipClass: ShipClass.TroopTransport,
      owner: "house1",
      location: 3,
      isCrippled: false,
      cargo: SpaceLiftCargo(
        cargoType: CargoType.Marines,
        quantity: 10
      )
    )

    let testFleet = Fleet(
      id: "fleet-1",
      squadrons: @[sq],
      spaceLiftShips: @[transport],
      owner: "house1",
      location: 3,
      status: FleetStatus.Active
    )
    state.fleets["fleet-1"] = testFleet

    let order = FleetOrder(
      fleetId: "fleet-1",
      orderType: FleetOrderType.Invade,
      targetSystem: some(3u),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)
    check result.success == true
    check result.message.contains("invasion")

  # ==========================================================================
  # Order 08: Blitz Planet
  # ==========================================================================

  test "Order 08: Blitz - requires loaded transports":
    var state = createTestGameState()

    let transport = SpaceLiftShip(
      id: "transport-2",
      shipClass: ShipClass.TroopTransport,
      owner: "house1",
      location: 3,
      isCrippled: false,
      cargo: SpaceLiftCargo(
        cargoType: CargoType.Marines,
        quantity: 10
      )
    )

    let testFleet = Fleet(
      id: "fleet-1",
      squadrons: @[],
      spaceLiftShips: @[transport],
      owner: "house1",
      location: 3,
      status: FleetStatus.Active
    )
    state.fleets["fleet-1"] = testFleet

    let order = FleetOrder(
      fleetId: "fleet-1",
      orderType: FleetOrderType.Blitz,
      targetSystem: some(3u),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)
    check result.success == true
    check result.message.contains("blitz")

  # ==========================================================================
  # Order 09: Spy Planet
  # ==========================================================================

  test "Order 09: SpyPlanet - requires scout squadron":
    var state = createTestGameState()

    let scout = newEnhancedShip(ShipClass.Scout)
    var sq = newSquadron(scout)
    let testFleet = Fleet(
      id: "fleet-1",
      squadrons: @[sq],
      spaceLiftShips: @[],
      owner: "house1",
      location: 3,
      status: FleetStatus.Active
    )
    state.fleets["fleet-1"] = testFleet

    let order = FleetOrder(
      fleetId: "fleet-1",
      orderType: FleetOrderType.SpyPlanet,
      targetSystem: some(3u),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)
    check result.success == true
    check result.message.contains("spy")

  # ==========================================================================
  # Order 10: Hack Starbase
  # ==========================================================================

  test "Order 10: HackStarbase - requires scout squadron":
    var state = createTestGameState()

    let scout = newEnhancedShip(ShipClass.Scout)
    var sq = newSquadron(scout)
    let testFleet = Fleet(
      id: "fleet-1",
      squadrons: @[sq],
      spaceLiftShips: @[],
      owner: "house1",
      location: 3,
      status: FleetStatus.Active
    )
    state.fleets["fleet-1"] = testFleet

    let order = FleetOrder(
      fleetId: "fleet-1",
      orderType: FleetOrderType.HackStarbase,
      targetSystem: some(3u),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)
    check result.success == true
    check result.message.contains("infiltrating")

  # ==========================================================================
  # Order 11: Spy System
  # ==========================================================================

  test "Order 11: SpySystem - requires scout squadron":
    var state = createTestGameState()

    let scout = newEnhancedShip(ShipClass.Scout)
    var sq = newSquadron(scout)
    let testFleet = Fleet(
      id: "fleet-1",
      squadrons: @[sq],
      spaceLiftShips: @[],
      owner: "house1",
      location: 3,
      status: FleetStatus.Active
    )
    state.fleets["fleet-1"] = testFleet

    let order = FleetOrder(
      fleetId: "fleet-1",
      orderType: FleetOrderType.SpySystem,
      targetSystem: some(3u),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)
    check result.success == true
    check result.message.contains("spy on system")

  # ==========================================================================
  # Order 12: Colonize
  # ==========================================================================

  test "Order 12: Colonize - requires ETAC":
    var state = createTestGameState()

    let etac = SpaceLiftShip(
      id: "etac-1",
      shipClass: ShipClass.ETAC,
      owner: "house1",
      location: 5,
      isCrippled: false,
      cargo: SpaceLiftCargo(
        cargoType: CargoType.Colonists,
        quantity: 1
      )
    )

    let testFleet = Fleet(
      id: "fleet-1",
      squadrons: @[],
      spaceLiftShips: @[etac],
      owner: "house1",
      location: 5, # Unoccupied system
      status: FleetStatus.Active
    )
    state.fleets["fleet-1"] = testFleet

    let order = FleetOrder(
      fleetId: "fleet-1",
      orderType: FleetOrderType.Colonize,
      targetSystem: some(5u),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)
    check result.success == true
    check result.message.contains("colonizing")

  # ==========================================================================
  # Order 13: Join Fleet
  # ==========================================================================

  test "Order 13: JoinFleet - merges fleets at same location":
    var state = createTestGameState()

    let destroyer1 = newEnhancedShip(ShipClass.Destroyer)
    var sq1 = newSquadron(destroyer1)
    let fleet1 = Fleet(
      id: "fleet-1",
      squadrons: @[sq1],
      spaceLiftShips: @[],
      owner: "house1",
      location: 1,
      status: FleetStatus.Active
    )

    let destroyer2 = newEnhancedShip(ShipClass.Destroyer)
    var sq2 = newSquadron(destroyer2)
    let fleet2 = Fleet(
      id: "fleet-2",
      squadrons: @[sq2],
      spaceLiftShips: @[],
      owner: "house1",
      location: 1,
      status: FleetStatus.Active
    )

    state.fleets["fleet-1"] = fleet1
    state.fleets["fleet-2"] = fleet2

    let order = FleetOrder(
      fleetId: "fleet-1",
      orderType: FleetOrderType.JoinFleet,
      targetSystem: none(uint),
      targetFleet: some(FleetId("fleet-2")),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)
    check result.success == true
    check result.message.contains("joining")

  # ==========================================================================
  # Order 14: Rendezvous
  # ==========================================================================

  test "Order 14: Rendezvous - coordinates fleet movement":
    var state = createTestGameState()

    let destroyer = newEnhancedShip(ShipClass.Destroyer)
    var sq = newSquadron(destroyer)
    let testFleet = Fleet(
      id: "fleet-1",
      squadrons: @[sq],
      spaceLiftShips: @[],
      owner: "house1",
      location: 1,
      status: FleetStatus.Active
    )
    state.fleets["fleet-1"] = testFleet

    let order = FleetOrder(
      fleetId: "fleet-1",
      orderType: FleetOrderType.Rendezvous,
      targetSystem: some(2u),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)
    check result.success == true

  # ==========================================================================
  # Order 15: Salvage
  # ==========================================================================

  test "Order 15: Salvage - recovers 50% PC at friendly colony":
    var state = createTestGameState()

    let destroyer = newEnhancedShip(ShipClass.Destroyer)
    var sq = newSquadron(destroyer)
    let testFleet = Fleet(
      id: "fleet-1",
      squadrons: @[sq],
      spaceLiftShips: @[],
      owner: "house1",
      location: 1,
      status: FleetStatus.Active
    )
    state.fleets["fleet-1"] = testFleet

    let order = FleetOrder(
      fleetId: "fleet-1",
      orderType: FleetOrderType.Salvage,
      targetSystem: none(uint),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)
    check result.success == true
    check result.message.contains("salvaged")

  # ==========================================================================
  # Order 16: Reserve
  # ==========================================================================

  test "Order 16: Reserve - places fleet on reserve status":
    var state = createTestGameState()

    let destroyer = newEnhancedShip(ShipClass.Destroyer)
    var sq = newSquadron(destroyer)
    let testFleet = Fleet(
      id: "fleet-1",
      squadrons: @[sq],
      spaceLiftShips: @[],
      owner: "house1",
      location: 1,
      status: FleetStatus.Active
    )
    state.fleets["fleet-1"] = testFleet

    let order = FleetOrder(
      fleetId: "fleet-1",
      orderType: FleetOrderType.Reserve,
      targetSystem: none(uint),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)
    check result.success == true
    check result.message.contains("reserve")
    check result.message.contains("50% maint")

  test "Order 16: Reserve - must be at friendly colony":
    var state = createTestGameState()

    let destroyer = newEnhancedShip(ShipClass.Destroyer)
    var sq = newSquadron(destroyer)
    let testFleet = Fleet(
      id: "fleet-1",
      squadrons: @[sq],
      spaceLiftShips: @[],
      owner: "house1",
      location: 5, # Neutral system
      status: FleetStatus.Active
    )
    state.fleets["fleet-1"] = testFleet

    let order = FleetOrder(
      fleetId: "fleet-1",
      orderType: FleetOrderType.Reserve,
      targetSystem: none(uint),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)
    check result.success == false
    check result.message.contains("must be at a colony")

  # ==========================================================================
  # Order 17: Mothball
  # ==========================================================================

  test "Order 17: Mothball - requires spaceport":
    var state = createTestGameState()

    let destroyer = newEnhancedShip(ShipClass.Destroyer)
    var sq = newSquadron(destroyer)
    let testFleet = Fleet(
      id: "fleet-1",
      squadrons: @[sq],
      spaceLiftShips: @[],
      owner: "house1",
      location: 1,
      status: FleetStatus.Active
    )
    state.fleets["fleet-1"] = testFleet

    let order = FleetOrder(
      fleetId: "fleet-1",
      orderType: FleetOrderType.Mothball,
      targetSystem: none(uint),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)
    check result.success == true
    check result.message.contains("mothballed")
    check result.message.contains("0% maint")

  # ==========================================================================
  # Order 18: Reactivate
  # ==========================================================================

  test "Order 18: Reactivate - returns reserve fleet to active":
    var state = createTestGameState()

    let destroyer = newEnhancedShip(ShipClass.Destroyer)
    var sq = newSquadron(destroyer)
    var testFleet = Fleet(
      id: "fleet-1",
      squadrons: @[sq],
      spaceLiftShips: @[],
      owner: "house1",
      location: 1,
      status: FleetStatus.Reserve
    )
    state.fleets["fleet-1"] = testFleet

    let order = FleetOrder(
      fleetId: "fleet-1",
      orderType: FleetOrderType.Reactivate,
      targetSystem: none(uint),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)
    check result.success == true
    check result.message.contains("active duty")

  test "Order 18: Reactivate - returns mothballed fleet to active":
    var state = createTestGameState()

    let destroyer = newEnhancedShip(ShipClass.Destroyer)
    var sq = newSquadron(destroyer)
    var testFleet = Fleet(
      id: "fleet-1",
      squadrons: @[sq],
      spaceLiftShips: @[],
      owner: "house1",
      location: 1,
      status: FleetStatus.Mothballed
    )
    state.fleets["fleet-1"] = testFleet

    let order = FleetOrder(
      fleetId: "fleet-1",
      orderType: FleetOrderType.Reactivate,
      targetSystem: none(uint),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)
    check result.success == true
    check result.message.contains("active duty")

  # ==========================================================================
  # Fleet Status Restrictions
  # ==========================================================================

  test "Reserve fleet cannot move":
    var state = createTestGameState()

    let destroyer = newEnhancedShip(ShipClass.Destroyer)
    var sq = newSquadron(destroyer)
    var testFleet = Fleet(
      id: "fleet-1",
      squadrons: @[sq],
      spaceLiftShips: @[],
      owner: "house1",
      location: 1,
      status: FleetStatus.Reserve
    )
    state.fleets["fleet-1"] = testFleet

    let order = FleetOrder(
      fleetId: "fleet-1",
      orderType: FleetOrderType.Move,
      targetSystem: some(2u),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)
    check result.success == false
    check result.message.contains("Reserve fleets cannot move")

  test "Mothballed fleet cannot move":
    var state = createTestGameState()

    let destroyer = newEnhancedShip(ShipClass.Destroyer)
    var sq = newSquadron(destroyer)
    var testFleet = Fleet(
      id: "fleet-1",
      squadrons: @[sq],
      spaceLiftShips: @[],
      owner: "house1",
      location: 1,
      status: FleetStatus.Mothballed
    )
    state.fleets["fleet-1"] = testFleet

    let order = FleetOrder(
      fleetId: "fleet-1",
      orderType: FleetOrderType.Move,
      targetSystem: some(2u),
      targetFleet: none(FleetId),
      priority: 0
    )

    let result = executeFleetOrder(state, "house1", order)
    check result.success == false
    check result.message.contains("Mothballed fleets cannot move")
