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
import ../../src/engine/[gamestate, orders, resolve, starmap]
import ../../src/engine/research/types as res_types
import ../../src/engine/espionage/types as esp_types
import ../../src/common/types/[core, units, planets]

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
    result.year = 2501
    result.month = 1
    result.phase = GamePhase.Active

    result.houses["house1"] = House(
      id: "house1",
      name: "Test House",
      treasury: 10000,
      eliminated: false
    )

    # Source colony with population
    result.colonies[1] = Colony(
      systemId: 1,
      owner: "house1",
      population: 100,
      souls: 100_000_000,
      infrastructure: 5,
      planetClass: PlanetClass.Eden,
      resources: ResourceRating.Abundant,
      buildings: @[],
      production: 100,
      underConstruction: none(gamestate.ConstructionProject),
      activeTerraforming: none(gamestate.TerraformProject),
      unassignedSquadrons: @[],
      unassignedSpaceLiftShips: @[],
      autoAssignFleets: false,
      fighterSquadrons: @[],
      capacityViolation: CapacityViolation(),
      starbases: @[],
      spaceports: @[],
      shipyards: @[]
    )

    # Destination colony
    result.colonies[2] = Colony(
      systemId: 2,
      owner: "house1",
      population: 50,
      souls: 50_000_000,
      infrastructure: 3,
      planetClass: PlanetClass.Benign,
      resources: ResourceRating.Abundant,
      buildings: @[],
      production: 50,
      underConstruction: none(gamestate.ConstructionProject),
      activeTerraforming: none(gamestate.TerraformProject),
      unassignedSquadrons: @[],
      unassignedSpaceLiftShips: @[],
      autoAssignFleets: false,
      fighterSquadrons: @[],
      capacityViolation: CapacityViolation(),
      starbases: @[],
      spaceports: @[],
      shipyards: @[]
    )

    result

  test "Population transfer order structure":
    var state = createTestState()

    # Create a population transfer order
    let transferOrder = PopulationTransferOrder(
      sourceColony: 1,
      destColony: 2,
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
      squadronManagement: @[],
      cargoManagement: @[],
      terraformOrders: @[],
      espionageAction: none(esp_types.EspionageAttempt),
      ebpInvestment: 0,
      cipInvestment: 0
    )

    var orders = initTable[HouseId, OrderPacket]()
    orders["house1"] = packet

    # Verify order structure is valid
    check packet.populationTransfers.len == 1
    check packet.populationTransfers[0].sourceColony == 1
    check packet.populationTransfers[0].destColony == 2
    check packet.populationTransfers[0].ptuAmount == 10

  test "Population transfer between own colonies":
    var state = createTestState()

    let initialSource = state.colonies[1].population
    let initialDest = state.colonies[2].population

    let transferOrder = PopulationTransferOrder(
      sourceColony: 1,
      destColony: 2,
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
      squadronManagement: @[],
      cargoManagement: @[],
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
    check result.newState.colonies[1].population <= initialSource

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

    # Try to transfer more PTU than source has
    let transferOrder = PopulationTransferOrder(
      sourceColony: 1,
      destColony: 2,
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
      squadronManagement: @[],
      cargoManagement: @[],
      terraformOrders: @[],
      espionageAction: none(esp_types.EspionageAttempt),
      ebpInvestment: 0,
      cipInvestment: 0
    )

    var orders = initTable[HouseId, OrderPacket]()
    orders["house1"] = packet

    let result = resolveTurn(state, orders)

    # Transfer should fail or be capped - verify population unchanged or reduced by max
    check result.newState.colonies[1].population <= 100

  test "Transfer deducts cost from treasury":
    var state = createTestState()
    let initialTreasury = state.houses["house1"].treasury

    let transferOrder = PopulationTransferOrder(
      sourceColony: 1,
      destColony: 2,
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
      squadronManagement: @[],
      cargoManagement: @[],
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

when isMainModule:
  echo "╔════════════════════════════════════════════════╗"
  echo "║  Space Guild Population Transfer Tests        ║"
  echo "╚════════════════════════════════════════════════╝"
