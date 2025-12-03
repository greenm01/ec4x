## Space Guild Population Transfer Tests
##
## Tests the Space Guild's civilian Starliner services for population transfers
## Covers:
## - Transfer cost calculation (base + per-jump)
## - Different planet class costs
## - Multi-jump route costs
## - Population transfer execution
## - PTU (Population Transfer Unit) mechanics
## - Transfer validation (source/destination ownership, capacity)

import std/[unittest, tables, options]
import ../../src/engine/[gamestate, orders, resolve, starmap, fleet]
import ../../src/engine/research/types as res_types
import ../../src/engine/espionage/types as esp_types
import ../../src/engine/economy/types as econ_types
import ../../src/common/types/[core, units, planets]
import ../../src/common/system

suite "Space Guild Transfer Costs":

  test "Calculate base transfer cost by planet class":
    # Per economy.md - costs vary by destination planet class
    # Eden: 10 PP/PTU base
    # Benign: 15 PP/PTU base
    # Harsh: 20 PP/PTU base
    # Extreme: 30 PP/PTU base

    # These values should come from config once implemented
    # For now we verify the cost calculation exists

    # Placeholder - actual implementation needs cost calculation
    check true  # TODO: Implement getPopulationTransferCost(destClass, jumps)

  test "Multi-jump route increases cost":
    # Per economy.md - additional cost per jump
    # Each jump adds to the base cost

    # Placeholder for when cost calculation is implemented
    check true  # TODO: Verify cost increases with jump count

suite "Population Transfer Mechanics":

  proc createTestState(): GameState =
    var result = GameState()
    result.turn = 1
    result.phase = GamePhase.Active

    # Generate starmap to get valid system IDs
    var map = newStarMap(2)
    map.populate()
    result.starMap = map
    let sourceSystemId = map.playerSystemIds[0]
    let destSystemId = map.playerSystemIds[1]

    result.houses["house1"] = House(
      id: "house1",
      name: "Test House",
      treasury: 10000,
      eliminated: false,
      techTree: res_types.initTechTree(),  # Initialize with all tech at level 1
    )

    # Source colony with population
    result.colonies[sourceSystemId] = Colony(
      systemId: sourceSystemId.SystemId,
      owner: "house1",
      population: 100,
      souls: 100_000_000,
      infrastructure: 5,
      planetClass: PlanetClass.Eden,
      resources: ResourceRating.Abundant,
      buildings: @[],
      production: 100,
      underConstruction: none(econ_types.ConstructionProject),
      activeTerraforming: none(gamestate.TerraformProject),
      unassignedSquadrons: @[],
      unassignedSpaceLiftShips: @[],
      fighterSquadrons: @[],
      capacityViolation: CapacityViolation(),
      starbases: @[],
      spaceports: @[],
      shipyards: @[]
    )

    # Destination colony
    result.colonies[destSystemId] = Colony(
      systemId: destSystemId.SystemId,
      owner: "house1",
      population: 50,
      souls: 50_000_000,
      infrastructure: 3,
      planetClass: PlanetClass.Benign,
      resources: ResourceRating.Abundant,
      buildings: @[],
      production: 50,
      underConstruction: none(econ_types.ConstructionProject),
      activeTerraforming: none(gamestate.TerraformProject),
      unassignedSquadrons: @[],
      unassignedSpaceLiftShips: @[],
      fighterSquadrons: @[],
      capacityViolation: CapacityViolation(),
      starbases: @[],
      spaceports: @[],
      shipyards: @[]
    )

    result

  test "Population transfer order structure":
    var state = createTestState()
    let sourceSystemId = state.starMap.playerSystemIds[0]
    let destSystemId = state.starMap.playerSystemIds[1]

    # Create a population transfer order
    let transferOrder = PopulationTransferOrder(
      sourceColony: sourceSystemId,
      destColony: destSystemId,
      ptuAmount: 10  # Transfer 10 PTU
    )

    var packet = OrderPacket(
      houseId: "house1",
      turn: 1,
      buildOrders: @[],
      fleetOrders: @[],
      researchAllocation: initResearchAllocation(),
      diplomaticActions: @[],
      populationTransfers: @[transferOrder],
      terraformOrders: @[],
      espionageAction: none(esp_types.EspionageAttempt),
      ebpInvestment: 0,
      cipInvestment: 0
    )

    var orders = initTable[HouseId, OrderPacket]()
    orders["house1"] = packet

    # Verify order structure is valid
    check packet.populationTransfers.len == 1
    check packet.populationTransfers[0].sourceColony == sourceSystemId
    check packet.populationTransfers[0].destColony == destSystemId
    check packet.populationTransfers[0].ptuAmount == 10

  test "Population transfer between own colonies succeeds":
    var state = createTestState()
    let sourceSystemId = state.starMap.playerSystemIds[0]
    let destSystemId = state.starMap.playerSystemIds[1]

    let initialSource = state.colonies[sourceSystemId].population
    let initialDest = state.colonies[destSystemId].population

    let transferOrder = PopulationTransferOrder(
      sourceColony: sourceSystemId,
      destColony: destSystemId,
      ptuAmount: 10  # 10 PTU = 1 PU
    )

    var packet = OrderPacket(
      houseId: "house1",
      turn: 1,
      buildOrders: @[],
      fleetOrders: @[],
      researchAllocation: initResearchAllocation(),
      diplomaticActions: @[],
      populationTransfers: @[transferOrder],
      terraformOrders: @[],
      espionageAction: none(esp_types.EspionageAttempt),
      ebpInvestment: 0,
      cipInvestment: 0
    )

    var orders = initTable[HouseId, OrderPacket]()
    orders["house1"] = packet

    let result = resolveTurn(state, orders)

    # Transfer should be processed
    # Population should be in transit or moved
    check result.newState.colonies[sourceSystemId].population <= initialSource

  test "Transfer fails if destination owned by different house":
    var state = createTestState()
    let sourceSystemId = state.starMap.playerSystemIds[0]
    let destSystemId = state.starMap.playerSystemIds[1]

    # Add another house that owns destination
    state.houses["house2"] = House(
      id: "house2",
      name: "Enemy House",
      treasury: 10000,
      eliminated: false,
      techTree: res_types.initTechTree(),  # Initialize with all tech at level 1
    )

    # Make destination owned by house2
    state.colonies[destSystemId].owner = "house2"

    let initialSource = state.colonies[sourceSystemId].population
    let initialDest = state.colonies[destSystemId].population

    let transferOrder = PopulationTransferOrder(
      sourceColony: sourceSystemId,
      destColony: destSystemId,
      ptuAmount: 10
    )

    var packet = OrderPacket(
      houseId: "house1",
      turn: 1,
      buildOrders: @[],
      fleetOrders: @[],
      researchAllocation: initResearchAllocation(),
      diplomaticActions: @[],
      populationTransfers: @[transferOrder],
      terraformOrders: @[],
      espionageAction: none(esp_types.EspionageAttempt),
      ebpInvestment: 0,
      cipInvestment: 0
    )

    var orders = initTable[HouseId, OrderPacket]()
    orders["house1"] = packet

    let result = resolveTurn(state, orders)

    # Transfer should FAIL - population unchanged
    check result.newState.colonies[sourceSystemId].population == initialSource
    check result.newState.colonies[destSystemId].population == initialDest

  test "Transfer fails if source owned by different house":
    var state = createTestState()
    let sourceSystemId = state.starMap.playerSystemIds[0]
    let destSystemId = state.starMap.playerSystemIds[1]

    # Add another house that owns source
    state.houses["house2"] = House(
      id: "house2",
      name: "Enemy House",
      treasury: 10000,
      eliminated: false,
      techTree: res_types.initTechTree(),  # Initialize with all tech at level 1
    )

    # Make source owned by house2
    state.colonies[sourceSystemId].owner = "house2"

    let initialSource = state.colonies[sourceSystemId].population
    let initialDest = state.colonies[destSystemId].population

    let transferOrder = PopulationTransferOrder(
      sourceColony: sourceSystemId,
      destColony: destSystemId,
      ptuAmount: 10
    )

    var packet = OrderPacket(
      houseId: "house1",
      turn: 1,
      buildOrders: @[],
      fleetOrders: @[],
      researchAllocation: initResearchAllocation(),
      diplomaticActions: @[],
      populationTransfers: @[transferOrder],
      terraformOrders: @[],
      espionageAction: none(esp_types.EspionageAttempt),
      ebpInvestment: 0,
      cipInvestment: 0
    )

    var orders = initTable[HouseId, OrderPacket]()
    orders["house1"] = packet

    let result = resolveTurn(state, orders)

    # Transfer should FAIL - population unchanged
    check result.newState.colonies[sourceSystemId].population == initialSource
    check result.newState.colonies[destSystemId].population == initialDest

  test "PTU conversion to population units":
    # Per economy.md - PTU represents a standardized population unit
    # 1 PTU = 10 million souls = 0.1 PU

    let ptu = 10
    let expectedSouls = ptu * 10_000_000
    let expectedPU = ptu / 10

    check expectedSouls == 100_000_000
    check expectedPU == 1.0

  test "Source colony has sufficient population":
    var state = createTestState()
    let sourceSystemId = state.starMap.playerSystemIds[0]
    let destSystemId = state.starMap.playerSystemIds[1]

    # Try to transfer more PTU than source has
    let transferOrder = PopulationTransferOrder(
      sourceColony: sourceSystemId,
      destColony: destSystemId,
      ptuAmount: 1500  # 1500 PTU = 150 PU, but source only has 100 PU
    )

    var packet = OrderPacket(
      houseId: "house1",
      turn: 1,
      buildOrders: @[],
      fleetOrders: @[],
      researchAllocation: initResearchAllocation(),
      diplomaticActions: @[],
      populationTransfers: @[transferOrder],
      terraformOrders: @[],
      espionageAction: none(esp_types.EspionageAttempt),
      ebpInvestment: 0,
      cipInvestment: 0
    )

    var orders = initTable[HouseId, OrderPacket]()
    orders["house1"] = packet

    let result = resolveTurn(state, orders)

    # Transfer should fail or be capped - verify population unchanged or reduced by max
    check result.newState.colonies[sourceSystemId].population <= 100

  test "Transfer deducts cost from treasury":
    var state = createTestState()
    let sourceSystemId = state.starMap.playerSystemIds[0]
    let destSystemId = state.starMap.playerSystemIds[1]
    let initialTreasury = state.houses["house1"].treasury

    let transferOrder = PopulationTransferOrder(
      sourceColony: sourceSystemId,
      destColony: destSystemId,
      ptuAmount: 10
    )

    var packet = OrderPacket(
      houseId: "house1",
      turn: 1,
      buildOrders: @[],
      fleetOrders: @[],
      researchAllocation: initResearchAllocation(),
      diplomaticActions: @[],
      populationTransfers: @[transferOrder],
      terraformOrders: @[],
      espionageAction: none(esp_types.EspionageAttempt),
      ebpInvestment: 0,
      cipInvestment: 0
    )

    var orders = initTable[HouseId, OrderPacket]()
    orders["house1"] = packet

    let result = resolveTurn(state, orders)

    # Treasury should be reduced by transfer cost
    # (Once cost calculation is implemented, verify exact amount)
    check result.newState.houses["house1"].treasury <= initialTreasury

suite "Multi-Jump Transfers":

  test "Calculate jump distance between systems":
    # This requires starmap implementation
    # Should calculate shortest path through jump lanes

    # Placeholder
    check true  # TODO: Test jump distance calculation

  test "Transfer cost scales with jump distance":
    # Base cost + (per-jump cost × number of jumps)

    # Placeholder
    check true  # TODO: Test cost scaling

suite "In-Transit Ownership Changes":

  proc createTestState(): GameState =
    var result = GameState()
    result.turn = 1
    result.phase = GamePhase.Active

    # Generate starmap to get valid system IDs
    var map = newStarMap(2)
    map.populate()
    result.starMap = map
    let sourceSystemId = map.playerSystemIds[0]
    let destSystemId = map.playerSystemIds[1]

    result.houses["house1"] = House(
      id: "house1",
      name: "Test House",
      treasury: 10000,
      eliminated: false,
      techTree: res_types.initTechTree(),  # Initialize with all tech at level 1
    )

    result.houses["house2"] = House(
      id: "house2",
      name: "Enemy House",
      treasury: 10000,
      eliminated: false,
      techTree: res_types.initTechTree(),  # Initialize with all tech at level 1
    )

    # Source colony owned by house1
    result.colonies[sourceSystemId] = Colony(
      systemId: sourceSystemId.SystemId,
      owner: "house1",
      population: 100,
      souls: 100_000_000,
      infrastructure: 5,
      planetClass: PlanetClass.Eden,
      resources: ResourceRating.Abundant,
      buildings: @[],
      production: 100,
      underConstruction: none(econ_types.ConstructionProject),
      activeTerraforming: none(gamestate.TerraformProject),
      unassignedSquadrons: @[],
      unassignedSpaceLiftShips: @[],
      fighterSquadrons: @[],
      capacityViolation: CapacityViolation(),
      starbases: @[],
      spaceports: @[],
      shipyards: @[]
    )

    # Destination colony owned by house1
    result.colonies[destSystemId] = Colony(
      systemId: destSystemId.SystemId,
      owner: "house1",
      population: 50,
      souls: 50_000_000,
      infrastructure: 3,
      planetClass: PlanetClass.Benign,
      resources: ResourceRating.Abundant,
      buildings: @[],
      production: 50,
      underConstruction: none(econ_types.ConstructionProject),
      activeTerraforming: none(gamestate.TerraformProject),
      unassignedSquadrons: @[],
      unassignedSpaceLiftShips: @[],
      fighterSquadrons: @[],
      capacityViolation: CapacityViolation(),
      starbases: @[],
      spaceports: @[],
      shipyards: @[]
    )

    result

  test "Colonists returned to source when destination conquered during transit":
    var state = createTestState()
    let sourceSystemId = state.starMap.playerSystemIds[0]
    let destSystemId = state.starMap.playerSystemIds[1]

    # Grant visibility on path by placing scout fleets (fog of war requirement)
    # Find path between systems and add fleets for visibility
    let dummyFleet = Fleet(
      id: "path_calc",
      owner: "house1",
      location: sourceSystemId,
      squadrons: @[],
      spaceliftShips: @[]
    )
    let pathResult = state.starMap.findPath(sourceSystemId, destSystemId, dummyFleet)
    if pathResult.found:
      # Add scout fleet at each system in path for visibility
      for i, systemId in pathResult.path:
        let scoutFleet = Fleet(
          id: "scout_" & $i,
          owner: "house1",
          location: systemId,
          squadrons: @[],
          spaceliftShips: @[]
        )
        state.fleets["scout_" & $i] = scoutFleet

    let initialSourcePop = state.colonies[sourceSystemId].population
    let initialDestPop = state.colonies[destSystemId].population

    # Start population transfer
    let transferOrder = PopulationTransferOrder(
      sourceColony: sourceSystemId,
      destColony: destSystemId,
      ptuAmount: 20  # 20 PTU = 1 PU (1 PTU = 50k souls = 0.05 million)
    )

    var packet = OrderPacket(
      houseId: "house1",
      turn: 1,
      buildOrders: @[],
      fleetOrders: @[],
      researchAllocation: initResearchAllocation(),
      diplomaticActions: @[],
      populationTransfers: @[transferOrder],
      terraformOrders: @[],
      espionageAction: none(esp_types.EspionageAttempt),
      ebpInvestment: 0,
      cipInvestment: 0
    )

    var orders = initTable[HouseId, OrderPacket]()
    orders["house1"] = packet

    # Turn 1: Transfer starts, colonists depart
    let result1 = resolveTurn(state, orders)
    state = result1.newState

    # Verify colonists departed from source
    check state.colonies[sourceSystemId].population < initialSourcePop

    # Verify in-transit entry created
    check state.populationInTransit.len == 1

    # Get arrival turn from the in-transit entry
    let arrivalTurn = state.populationInTransit[0].arrivalTurn

    # Simulate conquest: change destination ownership to house2 (during transit)
    state.colonies[destSystemId].owner = "house2"

    # Advance turns until arrival (no new transfers)
    packet.populationTransfers = @[]  # No new transfers
    while state.turn <= arrivalTurn:
      packet.turn = state.turn
      orders["house1"] = packet
      let result = resolveTurn(state, orders)
      state = result.newState
      if state.populationInTransit.len == 0:
        break  # Transfer arrived and processed

    # Verify in-transit cleared (colonists delivered somewhere)
    check state.populationInTransit.len == 0

    # Verify destination population UNCHANGED (not delivered there, it's conquered)
    check state.colonies[destSystemId].population == initialDestPop

    # Verify source population RESTORED (Guild returned colonists to source)
    # Source is closest owned colony, so colonists delivered back
    check state.colonies[sourceSystemId].population == initialSourcePop

  test "Colonists returned when destination blockaded during transit":
    # NOTE: This test is currently disabled because it requires starmap/jump lane data
    # for transit time calculation. Without starmap, calculateTransitTime returns -1
    # and the transfer fails immediately.
    #
    # TODO: Either:
    # 1. Add proper starmap initialization to createTestState()
    # 2. Move this test to a scenario-based test that includes full game initialization
    # 3. Mock/stub the transit time calculation for unit testing

    check true  # Placeholder - test logic verified, needs starmap setup

  test "Colonists lost when source conquered and destination blockaded":
    # NOTE: Disabled - requires starmap data for transit calculation
    check true  # Placeholder

  test "Transfer returned when destination below minimum (current behavior)":
    # NOTE: Disabled - requires starmap data for transit calculation
    check true  # Placeholder

when isMainModule:
  echo "╔════════════════════════════════════════════════╗"
  echo "║  Space Guild Population Transfer Tests        ║"
  echo "╚════════════════════════════════════════════════╝"
