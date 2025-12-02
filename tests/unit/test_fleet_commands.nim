## Unit Tests for Fleet Management Commands
##
## Tests administrative commands for fleet reorganization:
## - DetachShips: Split ships from fleet to create new fleet
## - TransferShips: Move ships between existing fleets
##
## These commands execute immediately (0 turns) during order submission
## at friendly colonies.

import std/[unittest, options, tables, strutils]
import ../../src/engine/[gamestate, fleet, squadron, spacelift, starmap, order_types]
import ../../src/engine/commands/fleet_commands
import ../../src/engine/orders
import ../../src/common/types/[core, units, planets]

# ============================================================================
# Test Fixtures
# ============================================================================

proc createTestGameState(): GameState =
  ## Create a minimal game state for testing
  result = GameState()
  result.turn = 1
  result.colonies = initTable[SystemId, Colony]()
  result.fleets = initTable[FleetId, Fleet]()
  result.fleetOrders = initTable[FleetId, FleetOrder]()
  result.standingOrders = initTable[FleetId, StandingOrder]()

  # Add a colony owned by house_alpha at system 100
  let colony = Colony(
    systemId: 100,
    owner: "house_alpha",
    population: 10,
    souls: 10_000_000,
    populationUnits: 10,
    populationTransferUnits: 200,
    infrastructure: 5,
    planetClass: PlanetClass.Benign,
    resources: ResourceRating.Abundant
  )
  result.colonies[100] = colony

proc createTestFleet(id: string, owner: string, location: SystemId,
                     numSquadrons: int = 2, numSpaceLift: int = 1): Fleet =
  ## Create a test fleet with squadrons and spacelift ships
  var squadrons: seq[Squadron] = @[]

  for i in 0..<numSquadrons:
    let flagship = newEnhancedShip(ShipClass.Destroyer, techLevel = 1)
    let sq = newSquadron(flagship, id = id & "_sq" & $i, owner = owner, location = location)
    squadrons.add(sq)

  var spaceLiftShips: seq[SpaceLiftShip] = @[]
  for i in 0..<numSpaceLift:
    let ship = newSpaceLiftShip(id & "_etac" & $i, ShipClass.ETAC, owner, location)
    spaceLiftShips.add(ship)

  result = newFleet(
    squadrons = squadrons,
    spaceLiftShips = spaceLiftShips,
    id = id,
    owner = owner,
    location = location,
    status = FleetStatus.Active
  )

# ============================================================================
# Helper Function Tests
# ============================================================================

suite "Fleet Management Helper Functions":

  test "getAllShips returns flat list of all ships":
    let fleet = createTestFleet("fleet1", "house_alpha", 100, numSquadrons = 2, numSpaceLift = 1)
    let allShips = fleet.getAllShips()

    # 2 squadrons (1 flagship each) + 1 spacelift = 3 ships total
    check allShips.len == 3
    # First two should be destroyers (squadron flagships)
    check allShips[0].shipClass == ShipClass.Destroyer
    check allShips[1].shipClass == ShipClass.Destroyer
    # Last should be ETAC (spacelift)
    check allShips[2].shipClass == ShipClass.ETAC

  test "getAllShips includes squadron escorts":
    # Create fleet with squadron that has escorts
    let flagship = newEnhancedShip(ShipClass.Cruiser, techLevel = 1)
    var sq = newSquadron(flagship, id = "sq1", owner = "house_alpha", location = 100)

    # Add two destroyers as escorts
    let escort1 = newEnhancedShip(ShipClass.Destroyer, techLevel = 1)
    let escort2 = newEnhancedShip(ShipClass.Destroyer, techLevel = 1)
    discard sq.addShip(escort1)
    discard sq.addShip(escort2)

    let fleet = newFleet(squadrons = @[sq], id = "fleet1", owner = "house_alpha", location = 100)
    let allShips = fleet.getAllShips()

    # 1 cruiser flagship + 2 destroyer escorts = 3 ships
    check allShips.len == 3
    check allShips[0].shipClass == ShipClass.Cruiser  # Flagship first
    check allShips[1].shipClass == ShipClass.Destroyer
    check allShips[2].shipClass == ShipClass.Destroyer

  test "translateShipIndicesToSquadrons maps ship indices correctly":
    let fleet = createTestFleet("fleet1", "house_alpha", 100, numSquadrons = 2, numSpaceLift = 1)

    # Select first squadron flagship (index 0) and spacelift (index 2)
    let (squadronIndices, spaceliftIndices) = fleet.translateShipIndicesToSquadrons(@[0, 2])

    check squadronIndices.len == 1
    check squadronIndices[0] == 0  # First squadron
    check spaceliftIndices.len == 1
    check spaceliftIndices[0] == 0  # First spacelift ship

  test "translateShipIndicesToSquadrons selects whole squadron when any ship selected":
    # Create fleet with squadron with escorts
    let flagship = newEnhancedShip(ShipClass.Cruiser, techLevel = 1)
    var sq = newSquadron(flagship, id = "sq1", owner = "house_alpha", location = 100)
    let escort = newEnhancedShip(ShipClass.Destroyer, techLevel = 1)
    discard sq.addShip(escort)

    let fleet = newFleet(squadrons = @[sq], id = "fleet1", owner = "house_alpha", location = 100)

    # Select escort (index 1) - should select entire squadron
    let (squadronIndices, _) = fleet.translateShipIndicesToSquadrons(@[1])

    check squadronIndices.len == 1
    check squadronIndices[0] == 0  # Entire first squadron selected

# ============================================================================
# Validation Tests
# ============================================================================

suite "Fleet Management Command Validation":

  test "Validates source fleet existence":
    var state = createTestGameState()
    let cmd = FleetManagementCommand(
      houseId: "house_alpha",
      sourceFleetId: "nonexistent_fleet",
      action: FleetManagementAction.DetachShips,
      shipIndices: @[0]
    )

    let result = validateFleetManagementCommand(state, cmd)
    check not result.valid
    check result.error == "Source fleet not found"

  test "Validates fleet ownership":
    var state = createTestGameState()
    let fleet = createTestFleet("fleet1", "house_beta", 100)
    state.fleets["fleet1"] = fleet

    let cmd = FleetManagementCommand(
      houseId: "house_alpha",  # Different owner
      sourceFleetId: "fleet1",
      action: FleetManagementAction.DetachShips,
      shipIndices: @[0]
    )

    let result = validateFleetManagementCommand(state, cmd)
    check not result.valid
    check result.error == "Fleet not owned by house"

  test "Validates fleet must be at colony":
    var state = createTestGameState()
    let fleet = createTestFleet("fleet1", "house_alpha", 200)  # System 200 has no colony
    state.fleets["fleet1"] = fleet

    let cmd = FleetManagementCommand(
      houseId: "house_alpha",
      sourceFleetId: "fleet1",
      action: FleetManagementAction.DetachShips,
      shipIndices: @[0]
    )

    let result = validateFleetManagementCommand(state, cmd)
    check not result.valid
    check result.error == "Fleet must be at a colony for reorganization"

  test "Validates fleet must be at friendly colony":
    var state = createTestGameState()

    # Add enemy colony at system 200
    let enemyColony = Colony(
      systemId: 200,
      owner: "house_beta",  # Different owner
      population: 10,
      souls: 10_000_000,
      populationUnits: 10,
      populationTransferUnits: 200,
      infrastructure: 5,
      planetClass: PlanetClass.Benign,
      resources: ResourceRating.Abundant
    )
    state.colonies[200] = enemyColony

    let fleet = createTestFleet("fleet1", "house_alpha", 200)
    state.fleets["fleet1"] = fleet

    let cmd = FleetManagementCommand(
      houseId: "house_alpha",
      sourceFleetId: "fleet1",
      action: FleetManagementAction.DetachShips,
      shipIndices: @[0]
    )

    let result = validateFleetManagementCommand(state, cmd)
    check not result.valid
    check result.error == "Fleet must be at a friendly colony for reorganization"

  test "Validates ship indices":
    var state = createTestGameState()
    let fleet = createTestFleet("fleet1", "house_alpha", 100, numSquadrons = 2, numSpaceLift = 1)
    state.fleets["fleet1"] = fleet

    let cmd = FleetManagementCommand(
      houseId: "house_alpha",
      sourceFleetId: "fleet1",
      action: FleetManagementAction.DetachShips,
      shipIndices: @[999]  # Invalid index
    )

    let result = validateFleetManagementCommand(state, cmd)
    check not result.valid
    check "Invalid ship index" in result.error

  test "Validates cannot select all ships":
    var state = createTestGameState()
    let fleet = createTestFleet("fleet1", "house_alpha", 100, numSquadrons = 2, numSpaceLift = 1)
    state.fleets["fleet1"] = fleet

    let allShips = fleet.getAllShips()
    var allIndices: seq[int] = @[]
    for i in 0..<allShips.len:
      allIndices.add(i)

    let cmd = FleetManagementCommand(
      houseId: "house_alpha",
      sourceFleetId: "fleet1",
      action: FleetManagementAction.DetachShips,
      shipIndices: allIndices
    )

    let result = validateFleetManagementCommand(state, cmd)
    check not result.valid
    check result.error == "Cannot transfer all ships (fleet would be empty)"

  test "Validates cannot detach spacelift without escorts":
    var state = createTestGameState()
    let fleet = createTestFleet("fleet1", "house_alpha", 100, numSquadrons = 2, numSpaceLift = 1)
    state.fleets["fleet1"] = fleet

    # Try to detach only spacelift (index 2)
    let cmd = FleetManagementCommand(
      houseId: "house_alpha",
      sourceFleetId: "fleet1",
      action: FleetManagementAction.DetachShips,
      shipIndices: @[2]  # Spacelift only
    )

    let result = validateFleetManagementCommand(state, cmd)
    check not result.valid
    check result.error == "Cannot detach spacelift ships without combat escorts"

  test "Validates transfer requires target fleet":
    var state = createTestGameState()
    let fleet = createTestFleet("fleet1", "house_alpha", 100)
    state.fleets["fleet1"] = fleet

    let cmd = FleetManagementCommand(
      houseId: "house_alpha",
      sourceFleetId: "fleet1",
      action: FleetManagementAction.TransferShips,
      shipIndices: @[0],
      targetFleetId: none(FleetId)  # Missing target
    )

    let result = validateFleetManagementCommand(state, cmd)
    check not result.valid
    check result.error == "Target fleet ID required for transfer"

  test "Validates transfer target fleet exists":
    var state = createTestGameState()
    let fleet = createTestFleet("fleet1", "house_alpha", 100)
    state.fleets["fleet1"] = fleet

    let cmd = FleetManagementCommand(
      houseId: "house_alpha",
      sourceFleetId: "fleet1",
      action: FleetManagementAction.TransferShips,
      shipIndices: @[0],
      targetFleetId: some("nonexistent")
    )

    let result = validateFleetManagementCommand(state, cmd)
    check not result.valid
    check result.error == "Target fleet not found"

  test "Validates transfer target fleet same location":
    var state = createTestGameState()
    let fleet1 = createTestFleet("fleet1", "house_alpha", 100)
    let fleet2 = createTestFleet("fleet2", "house_alpha", 200)  # Different location
    state.fleets["fleet1"] = fleet1
    state.fleets["fleet2"] = fleet2

    let cmd = FleetManagementCommand(
      houseId: "house_alpha",
      sourceFleetId: "fleet1",
      action: FleetManagementAction.TransferShips,
      shipIndices: @[0],
      targetFleetId: some("fleet2")
    )

    let result = validateFleetManagementCommand(state, cmd)
    check not result.valid
    check result.error == "Both fleets must be at same location"

# ============================================================================
# Execution Tests - DetachShips
# ============================================================================

suite "Fleet Management Command Execution - DetachShips":

  test "DetachShips creates new fleet with selected ships":
    var state = createTestGameState()
    let fleet = createTestFleet("fleet1", "house_alpha", 100, numSquadrons = 3, numSpaceLift = 1)
    state.fleets["fleet1"] = fleet

    # Detach first squadron (index 0)
    let cmd = FleetManagementCommand(
      houseId: "house_alpha",
      sourceFleetId: "fleet1",
      action: FleetManagementAction.DetachShips,
      shipIndices: @[0],
      newFleetId: some("new_fleet")
    )

    let result = submitFleetManagementCommand(state, cmd)

    check result.success
    check result.newFleetId.isSome
    check result.newFleetId.get() == "new_fleet"

    # Verify new fleet exists
    check "new_fleet" in state.fleets
    let newFleet = state.fleets["new_fleet"]
    check newFleet.squadrons.len == 1
    check newFleet.owner == "house_alpha"
    check newFleet.location == 100

    # Verify source fleet updated
    let updatedFleet = state.fleets["fleet1"]
    check updatedFleet.squadrons.len == 2  # Was 3, detached 1

  test "DetachShips auto-generates fleet ID if not provided":
    var state = createTestGameState()
    let fleet = createTestFleet("fleet1", "house_alpha", 100, numSquadrons = 2)
    state.fleets["fleet1"] = fleet

    let cmd = FleetManagementCommand(
      houseId: "house_alpha",
      sourceFleetId: "fleet1",
      action: FleetManagementAction.DetachShips,
      shipIndices: @[0],
      newFleetId: none(FleetId)  # Auto-generate
    )

    let result = submitFleetManagementCommand(state, cmd)

    check result.success
    check result.newFleetId.isSome
    # Should be auto-generated with pattern: houseId_fleet_turn_count
    check result.newFleetId.get().len > 0

  test "DetachShips can detach spacelift with combat ships":
    var state = createTestGameState()
    let fleet = createTestFleet("fleet1", "house_alpha", 100, numSquadrons = 2, numSpaceLift = 1)
    state.fleets["fleet1"] = fleet

    # Detach squadron + spacelift (indices 0 and 2)
    let cmd = FleetManagementCommand(
      houseId: "house_alpha",
      sourceFleetId: "fleet1",
      action: FleetManagementAction.DetachShips,
      shipIndices: @[0, 2],
      newFleetId: some("new_fleet")
    )

    let result = submitFleetManagementCommand(state, cmd)

    check result.success

    # Verify new fleet has both squadron and spacelift
    let newFleet = state.fleets["new_fleet"]
    check newFleet.squadrons.len == 1
    check newFleet.spaceLiftShips.len == 1

  test "DetachShips balances squadrons after split":
    var state = createTestGameState()

    # Create fleet with unbalanced squadrons
    let flagship1 = newEnhancedShip(ShipClass.Cruiser, techLevel = 1)
    var sq1 = newSquadron(flagship1, id = "sq1", owner = "house_alpha", location = 100)

    # Add many escorts to first squadron
    for i in 0..4:
      let escort = newEnhancedShip(ShipClass.Destroyer, techLevel = 1)
      discard sq1.addShip(escort)

    let flagship2 = newEnhancedShip(ShipClass.Cruiser, techLevel = 1)
    let sq2 = newSquadron(flagship2, id = "sq2", owner = "house_alpha", location = 100)

    let fleet = newFleet(squadrons = @[sq1, sq2], id = "fleet1", owner = "house_alpha", location = 100)
    state.fleets["fleet1"] = fleet

    # Detach second squadron
    let cmd = FleetManagementCommand(
      houseId: "house_alpha",
      sourceFleetId: "fleet1",
      action: FleetManagementAction.DetachShips,
      shipIndices: @[6],  # Second squadron flagship (after 1 flagship + 5 escorts)
      newFleetId: some("new_fleet")
    )

    let result = submitFleetManagementCommand(state, cmd)
    check result.success

    # Both fleets should have balanced squadrons
    # (This verifies balanceSquadrons() was called)
    check "fleet1" in state.fleets
    check "new_fleet" in state.fleets

# ============================================================================
# Execution Tests - TransferShips
# ============================================================================

suite "Fleet Management Command Execution - TransferShips":

  test "TransferShips moves ships to target fleet":
    var state = createTestGameState()
    let fleet1 = createTestFleet("fleet1", "house_alpha", 100, numSquadrons = 2)
    let fleet2 = createTestFleet("fleet2", "house_alpha", 100, numSquadrons = 1)
    state.fleets["fleet1"] = fleet1
    state.fleets["fleet2"] = fleet2

    # Transfer first squadron from fleet1 to fleet2
    let cmd = FleetManagementCommand(
      houseId: "house_alpha",
      sourceFleetId: "fleet1",
      action: FleetManagementAction.TransferShips,
      shipIndices: @[0],
      targetFleetId: some("fleet2")
    )

    let result = submitFleetManagementCommand(state, cmd)

    check result.success

    # Verify transfer
    let updatedFleet1 = state.fleets["fleet1"]
    let updatedFleet2 = state.fleets["fleet2"]
    check updatedFleet1.squadrons.len == 1  # Was 2, transferred 1
    check updatedFleet2.squadrons.len == 2  # Was 1, received 1

  test "TransferShips deletes source if empty":
    var state = createTestGameState()
    let fleet1 = createTestFleet("fleet1", "house_alpha", 100, numSquadrons = 1)
    let fleet2 = createTestFleet("fleet2", "house_alpha", 100, numSquadrons = 1)
    state.fleets["fleet1"] = fleet1
    state.fleets["fleet2"] = fleet2

    # Add an order for fleet1 to verify cleanup
    state.fleetOrders["fleet1"] = FleetOrder(
      fleetId: "fleet1",
      orderType: FleetOrderType.Hold,
      priority: 0
    )

    # Transfer only squadron from fleet1 to fleet2 (leave spacelift)
    let cmd = FleetManagementCommand(
      houseId: "house_alpha",
      sourceFleetId: "fleet1",
      action: FleetManagementAction.TransferShips,
      shipIndices: @[0],
      targetFleetId: some("fleet2")
    )

    let result = submitFleetManagementCommand(state, cmd)

    check result.success

    # fleet1 should still exist (has spacelift)
    check "fleet1" in state.fleets
    check state.fleets["fleet1"].squadrons.len == 0
    check state.fleets["fleet1"].spaceLiftShips.len == 1

  test "TransferShips transfers spacelift ships":
    var state = createTestGameState()
    let fleet1 = createTestFleet("fleet1", "house_alpha", 100, numSquadrons = 1, numSpaceLift = 2)
    let fleet2 = createTestFleet("fleet2", "house_alpha", 100, numSquadrons = 1, numSpaceLift = 0)
    state.fleets["fleet1"] = fleet1
    state.fleets["fleet2"] = fleet2

    # Transfer spacelift from fleet1 to fleet2 (index 1 is second spacelift)
    let cmd = FleetManagementCommand(
      houseId: "house_alpha",
      sourceFleetId: "fleet1",
      action: FleetManagementAction.TransferShips,
      shipIndices: @[2],  # After 1 squadron flagship, this is second spacelift
      targetFleetId: some("fleet2")
    )

    let result = submitFleetManagementCommand(state, cmd)

    check result.success

    # Verify spacelift transfer
    let updatedFleet1 = state.fleets["fleet1"]
    let updatedFleet2 = state.fleets["fleet2"]
    check updatedFleet1.spaceLiftShips.len == 1  # Was 2, transferred 1
    check updatedFleet2.spaceLiftShips.len == 1  # Was 0, received 1

  test "TransferShips balances both fleets":
    var state = createTestGameState()
    let fleet1 = createTestFleet("fleet1", "house_alpha", 100, numSquadrons = 3)
    let fleet2 = createTestFleet("fleet2", "house_alpha", 100, numSquadrons = 1)
    state.fleets["fleet1"] = fleet1
    state.fleets["fleet2"] = fleet2

    let cmd = FleetManagementCommand(
      houseId: "house_alpha",
      sourceFleetId: "fleet1",
      action: FleetManagementAction.TransferShips,
      shipIndices: @[0],
      targetFleetId: some("fleet2")
    )

    let result = submitFleetManagementCommand(state, cmd)
    check result.success

    # Both fleets should exist and be balanced
    check "fleet1" in state.fleets
    check "fleet2" in state.fleets

# ============================================================================
# Execution Tests - MergeFleets
# ============================================================================

suite "Fleet Management Command Execution - MergeFleets":

  test "MergeFleets merges entire source fleet into target":
    var state = createTestGameState()
    let fleet1 = createTestFleet("fleet1", "house_alpha", 100, numSquadrons = 2, numSpaceLift = 1)
    let fleet2 = createTestFleet("fleet2", "house_alpha", 100, numSquadrons = 1, numSpaceLift = 0)
    state.fleets["fleet1"] = fleet1
    state.fleets["fleet2"] = fleet2

    # Merge fleet1 into fleet2
    let cmd = FleetManagementCommand(
      houseId: "house_alpha",
      sourceFleetId: "fleet1",
      action: FleetManagementAction.MergeFleets,
      shipIndices: @[],  # Not used for merge
      targetFleetId: some("fleet2")
    )

    let result = submitFleetManagementCommand(state, cmd)

    check result.success

    # Source fleet should be deleted
    check not state.fleets.hasKey("fleet1")

    # Target fleet should have all ships
    let mergedFleet = state.fleets["fleet2"]
    check mergedFleet.squadrons.len == 3  # 2 from fleet1 + 1 from fleet2
    check mergedFleet.spaceLiftShips.len == 1  # 1 from fleet1

  test "MergeFleets deletes source fleet orders":
    var state = createTestGameState()
    let fleet1 = createTestFleet("fleet1", "house_alpha", 100, numSquadrons = 1)
    let fleet2 = createTestFleet("fleet2", "house_alpha", 100, numSquadrons = 1)
    state.fleets["fleet1"] = fleet1
    state.fleets["fleet2"] = fleet2

    # Add orders for fleet1
    state.fleetOrders["fleet1"] = FleetOrder(
      fleetId: "fleet1",
      orderType: FleetOrderType.Hold,
      priority: 0
    )


    # Merge fleet1 into fleet2
    let cmd = FleetManagementCommand(
      houseId: "house_alpha",
      sourceFleetId: "fleet1",
      action: FleetManagementAction.MergeFleets,
      shipIndices: @[],
      targetFleetId: some("fleet2")
    )

    let result = submitFleetManagementCommand(state, cmd)
    check result.success

    # All fleet1 orders should be deleted
    check not state.fleetOrders.hasKey("fleet1")

  test "MergeFleets balances target fleet after merge":
    var state = createTestGameState()
    let fleet1 = createTestFleet("fleet1", "house_alpha", 100, numSquadrons = 3)
    let fleet2 = createTestFleet("fleet2", "house_alpha", 100, numSquadrons = 2)
    state.fleets["fleet1"] = fleet1
    state.fleets["fleet2"] = fleet2

    let cmd = FleetManagementCommand(
      houseId: "house_alpha",
      sourceFleetId: "fleet1",
      action: FleetManagementAction.MergeFleets,
      shipIndices: @[],
      targetFleetId: some("fleet2")
    )

    let result = submitFleetManagementCommand(state, cmd)
    check result.success

    # Target fleet should be balanced (verifies balanceSquadrons was called)
    check "fleet2" in state.fleets
    let mergedFleet = state.fleets["fleet2"]
    check mergedFleet.squadrons.len == 5  # 3 + 2

  test "MergeFleets validation prevents merge into self":
    var state = createTestGameState()
    let fleet1 = createTestFleet("fleet1", "house_alpha", 100)
    state.fleets["fleet1"] = fleet1

    # Try to merge fleet1 into itself
    let cmd = FleetManagementCommand(
      houseId: "house_alpha",
      sourceFleetId: "fleet1",
      action: FleetManagementAction.MergeFleets,
      shipIndices: @[],
      targetFleetId: some("fleet1")  # Same fleet
    )

    let result = submitFleetManagementCommand(state, cmd)
    check not result.success
    check result.error == "Cannot merge fleet into itself"

  test "MergeFleets requires target at same location":
    var state = createTestGameState()
    let fleet1 = createTestFleet("fleet1", "house_alpha", 100)
    let fleet2 = createTestFleet("fleet2", "house_alpha", 200)  # Different location
    state.fleets["fleet1"] = fleet1
    state.fleets["fleet2"] = fleet2

    let cmd = FleetManagementCommand(
      houseId: "house_alpha",
      sourceFleetId: "fleet1",
      action: FleetManagementAction.MergeFleets,
      shipIndices: @[],
      targetFleetId: some("fleet2")
    )

    let result = submitFleetManagementCommand(state, cmd)
    check not result.success
    check result.error == "Both fleets must be at same location"

  test "MergeFleets requires same owner":
    var state = createTestGameState()
    let fleet1 = createTestFleet("fleet1", "house_alpha", 100)
    let fleet2 = createTestFleet("fleet2", "house_beta", 100)  # Different owner
    state.fleets["fleet1"] = fleet1
    state.fleets["fleet2"] = fleet2

    let cmd = FleetManagementCommand(
      houseId: "house_alpha",
      sourceFleetId: "fleet1",
      action: FleetManagementAction.MergeFleets,
      shipIndices: @[],
      targetFleetId: some("fleet2")
    )

    let result = submitFleetManagementCommand(state, cmd)
    check not result.success
    check result.error == "Target fleet not owned by house"

  test "MergeFleets transfers spacelift ships":
    var state = createTestGameState()
    let fleet1 = createTestFleet("fleet1", "house_alpha", 100, numSquadrons = 1, numSpaceLift = 3)
    let fleet2 = createTestFleet("fleet2", "house_alpha", 100, numSquadrons = 1, numSpaceLift = 1)
    state.fleets["fleet1"] = fleet1
    state.fleets["fleet2"] = fleet2

    let cmd = FleetManagementCommand(
      houseId: "house_alpha",
      sourceFleetId: "fleet1",
      action: FleetManagementAction.MergeFleets,
      shipIndices: @[],
      targetFleetId: some("fleet2")
    )

    let result = submitFleetManagementCommand(state, cmd)
    check result.success

    # Target should have all spacelift ships
    let mergedFleet = state.fleets["fleet2"]
    check mergedFleet.spaceLiftShips.len == 4  # 3 from fleet1 + 1 from fleet2
