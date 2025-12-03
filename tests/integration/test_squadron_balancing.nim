## Squadron Balancing Tests
##
## Tests the auto-balance feature for optimizing squadron composition within fleets
## Covers:
## - Basic balancing between squadrons
## - Command capacity optimization
## - Edge cases (no escorts, single squadron, capacity overflow)

import std/[unittest, tables, options]
import ../../src/engine/[gamestate, orders, resolve, fleet, squadron]
import ../../src/engine/research/types as res_types
import ../../src/engine/espionage/types as esp_types
import ../../src/common/types/[core, units]

suite "Squadron Auto-Balancing":

  proc createBalancingTestState(): GameState =
    ## Create a test state with fleets for balancing tests
    result = GameState()
    result.turn = 1
    result.phase = GamePhase.Active

    # Create house
    result.houses["house1"] = House(
      id: "house1",
      name: "Test House",
      treasury: 10000,
      eliminated: false,
      techTree: res_types.initTechTree(),
    )

  proc createTestShip(shipClass: ShipClass): EnhancedShip =
    ## Create a test ship with appropriate stats
    let stats = getShipStats(shipClass)
    EnhancedShip(
      shipClass: shipClass,
      shipType: if shipClass in [ShipClass.ETAC, ShipClass.TroopTransport]: ShipType.Spacelift else: ShipType.Military,
      stats: stats,
      isCrippled: false,
      name: $shipClass
    )

  test "Balance two battleship squadrons with uneven escort distribution":
    var state = createBalancingTestState()

    # Create two battleship flagships
    let bb1 = createTestShip(ShipClass.Battleship)  # CR=15
    let bb2 = createTestShip(ShipClass.Battleship)  # CR=15

    # Create squadrons
    var squad1 = newSquadron(bb1, "sq1", "house1", 1)
    var squad2 = newSquadron(bb2, "sq2", "house1", 1)

    # Add 5 destroyers to squad1 (CC=3 each = 15 total, FULL)
    for i in 0..<5:
      let dd = createTestShip(ShipClass.Destroyer)
      discard squad1.addShip(dd)

    # Squad2 has no escorts (0/15 used)

    # Create fleet with autoBalanceSquadrons enabled
    var fleet = newFleet(
      squadrons = @[squad1, squad2],
      id = "fleet1",
      owner = "house1",
      location = 1,
      autoBalanceSquadrons = true
    )

    # Balance the fleet
    fleet.balanceSquadrons()

    # After balancing: each squadron should have ~2-3 destroyers
    # Squad1: 15 CR, should fit 2-3 destroyers (6-9 CC used)
    # Squad2: 15 CR, should fit 2-3 destroyers (6-9 CC used)
    check fleet.squadrons[0].ships.len > 0
    check fleet.squadrons[1].ships.len > 0
    check fleet.squadrons[0].ships.len + fleet.squadrons[1].ships.len == 5  # Total escorts preserved

    # Check that capacity is better utilized (both squadrons should have ships)
    let squad1Usage = fleet.squadrons[0].totalCommandCost()
    let squad2Usage = fleet.squadrons[1].totalCommandCost()
    check squad1Usage > 0
    check squad2Usage > 0

  test "Balance three squadrons with mixed ship types":
    var state = createBalancingTestState()

    # Create three capital ship flagships with different command ratings
    let bb = createTestShip(ShipClass.Battleship)     # CR=15
    let ca = createTestShip(ShipClass.HeavyCruiser)   # CR=8
    let cl = createTestShip(ShipClass.Cruiser)        # CR=5

    var squad1 = newSquadron(bb, "sq1", "house1", 1)
    var squad2 = newSquadron(ca, "sq2", "house1", 1)
    var squad3 = newSquadron(cl, "sq3", "house1", 1)

    # Add mixed escorts to squad1 only
    discard squad1.addShip(createTestShip(ShipClass.Destroyer))  # CC=3
    discard squad1.addShip(createTestShip(ShipClass.Destroyer))  # CC=3
    discard squad1.addShip(createTestShip(ShipClass.Frigate))    # CC=2
    discard squad1.addShip(createTestShip(ShipClass.Frigate))    # CC=2
    # Total: 10 CC in squad1, 0 in squad2, 0 in squad3

    var fleet = newFleet(
      squadrons = @[squad1, squad2, squad3],
      id = "fleet1",
      owner = "house1",
      location = 1,
      autoBalanceSquadrons = true
    )

    fleet.balanceSquadrons()

    # Check all escorts are preserved
    let totalEscorts = fleet.squadrons[0].ships.len +
                       fleet.squadrons[1].ships.len +
                       fleet.squadrons[2].ships.len
    check totalEscorts == 4

    # Check that multiple squadrons got escorts (better distribution)
    var squadronsWithEscorts = 0
    for sq in fleet.squadrons:
      if sq.ships.len > 0:
        squadronsWithEscorts += 1
    check squadronsWithEscorts >= 2  # At least 2 squadrons should have escorts

  test "No balancing needed for fleet with single squadron":
    var state = createBalancingTestState()

    let bb = createTestShip(ShipClass.Battleship)
    var squad = newSquadron(bb, "sq1", "house1", 1)
    discard squad.addShip(createTestShip(ShipClass.Destroyer))
    discard squad.addShip(createTestShip(ShipClass.Destroyer))

    var fleet = newFleet(
      squadrons = @[squad],
      id = "fleet1",
      owner = "house1",
      location = 1,
      autoBalanceSquadrons = true
    )

    let beforeCount = fleet.squadrons[0].ships.len
    fleet.balanceSquadrons()
    let afterCount = fleet.squadrons[0].ships.len

    # Nothing should change with only one squadron
    check beforeCount == afterCount

  test "Fleet with no escorts remains unchanged":
    var state = createBalancingTestState()

    # Create squadrons with only flagships (no escorts)
    let bb1 = createTestShip(ShipClass.Battleship)
    let bb2 = createTestShip(ShipClass.Battleship)

    var squad1 = newSquadron(bb1, "sq1", "house1", 1)
    var squad2 = newSquadron(bb2, "sq2", "house1", 1)

    var fleet = newFleet(
      squadrons = @[squad1, squad2],
      id = "fleet1",
      owner = "house1",
      location = 1,
      autoBalanceSquadrons = true
    )

    fleet.balanceSquadrons()

    # Both squadrons should still have no escorts
    check fleet.squadrons[0].ships.len == 0
    check fleet.squadrons[1].ships.len == 0

  test "Large escorts are distributed efficiently":
    var state = createBalancingTestState()

    # Create squadrons with moderate command capacity
    let ca1 = createTestShip(ShipClass.HeavyCruiser)  # CR=8
    let ca2 = createTestShip(ShipClass.HeavyCruiser)  # CR=8

    var squad1 = newSquadron(ca1, "sq1", "house1", 1)
    var squad2 = newSquadron(ca2, "sq2", "house1", 1)

    # Add large escorts to squad1 (Light Cruisers, CC=4 each)
    discard squad1.addShip(createTestShip(ShipClass.LightCruiser))  # CC=4
    discard squad1.addShip(createTestShip(ShipClass.LightCruiser))  # CC=4
    # Total: 8 CC in squad1 (FULL), 0 in squad2

    var fleet = newFleet(
      squadrons = @[squad1, squad2],
      id = "fleet1",
      owner = "house1",
      location = 1,
      autoBalanceSquadrons = true
    )

    fleet.balanceSquadrons()

    # After balancing: each squadron should have 1 light cruiser
    # This tests the greedy bin packing with large items
    check fleet.squadrons[0].ships.len == 1
    check fleet.squadrons[1].ships.len == 1

  test "Auto-balance triggers during turn resolution":
    var state = createBalancingTestState()

    # Create unbalanced fleet
    let bb1 = createTestShip(ShipClass.Battleship)
    let bb2 = createTestShip(ShipClass.Battleship)

    var squad1 = newSquadron(bb1, "sq1", "house1", 1)
    var squad2 = newSquadron(bb2, "sq2", "house1", 1)

    # All escorts in squad1
    for i in 0..<4:
      discard squad1.addShip(createTestShip(ShipClass.Destroyer))

    # Create fleet with autoBalanceSquadrons enabled
    let fleetId = "house1_fleet1"
    state.fleets[fleetId] = Fleet(
      id: fleetId,
      squadrons: @[squad1, squad2],
      spaceLiftShips: @[],
      owner: "house1",
      location: 1,
      status: FleetStatus.Active,
      autoBalanceSquadrons: true  # Enable auto-balancing
    )

    # Create empty orders (no fleet orders - fleet is stationary)
    var orders = initTable[HouseId, OrderPacket]()
    orders["house1"] = OrderPacket(
      houseId: "house1",
      turn: 1,
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

    # Resolve turn - auto-balance should trigger
    let result = resolveTurn(state, orders)

    # Check that fleet was balanced during resolution
    let balancedFleet = result.newState.fleets[fleetId]
    check balancedFleet.squadrons[0].ships.len > 0
    check balancedFleet.squadrons[1].ships.len > 0
    # Total escorts should be preserved
    check balancedFleet.squadrons[0].ships.len + balancedFleet.squadrons[1].ships.len == 4

  test "Fleet with autoBalanceSquadrons=false is not balanced":
    var state = createBalancingTestState()

    let bb1 = createTestShip(ShipClass.Battleship)
    let bb2 = createTestShip(ShipClass.Battleship)

    var squad1 = newSquadron(bb1, "sq1", "house1", 1)
    var squad2 = newSquadron(bb2, "sq2", "house1", 1)

    # All escorts in squad1
    for i in 0..<4:
      discard squad1.addShip(createTestShip(ShipClass.Destroyer))

    let fleetId = "house1_fleet1"
    state.fleets[fleetId] = Fleet(
      id: fleetId,
      squadrons: @[squad1, squad2],
      spaceLiftShips: @[],
      owner: "house1",
      location: 1,
      status: FleetStatus.Active,
      autoBalanceSquadrons: false  # DISABLED
    )

    var orders = initTable[HouseId, OrderPacket]()
    orders["house1"] = OrderPacket(
      houseId: "house1",
      turn: 1,
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

    let result = resolveTurn(state, orders)

    # Fleet should NOT be balanced (squad2 should still have 0 escorts)
    let unchangedFleet = result.newState.fleets[fleetId]
    check unchangedFleet.squadrons[0].ships.len == 4
    check unchangedFleet.squadrons[1].ships.len == 0

  test "Performance: Already balanced fleet skips expensive sort":
    var state = createBalancingTestState()

    # Create fleet with already-balanced squadrons
    let bb1 = createTestShip(ShipClass.Battleship)
    let bb2 = createTestShip(ShipClass.Battleship)

    var squad1 = newSquadron(bb1, "sq1", "house1", 1)
    var squad2 = newSquadron(bb2, "sq2", "house1", 1)

    # Each squadron has 2 escorts (balanced within 1 of each other)
    discard squad1.addShip(createTestShip(ShipClass.Destroyer))
    discard squad1.addShip(createTestShip(ShipClass.Destroyer))
    discard squad2.addShip(createTestShip(ShipClass.Destroyer))
    discard squad2.addShip(createTestShip(ShipClass.Destroyer))

    var fleet = newFleet(
      squadrons = @[squad1, squad2],
      id = "fleet1",
      owner = "house1",
      location = 1,
      autoBalanceSquadrons = true
    )

    # Balance should be a no-op (squadrons already within 1 escort of each other)
    fleet.balanceSquadrons()

    # Check that nothing changed
    check fleet.squadrons[0].ships.len == 2
    check fleet.squadrons[1].ships.len == 2

when isMainModule:
  echo "╔════════════════════════════════════════════════╗"
  echo "║  Squadron Auto-Balancing Tests                ║"
  echo "║  Tests fleet squadron optimization            ║"
  echo "╚════════════════════════════════════════════════╝"
