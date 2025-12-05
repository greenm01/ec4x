## Comprehensive Resolution Engine Tests
##
## Tests the complete operational lifecycle of game units:
## - Ship commissioning (construction → squadrons)
## - Auto-assignment (unassignedSquadrons → fleets)
## - Fleet operations (active orders: Move, Hold, Patrol, Guard, etc.)
## - Standing orders (persistent behaviors)
## - Squadron management (transfers, merges)
## - Fleet status changes (Active, Reserve, Mothballed)
##
## This validates the full Build → Commission → Assign → Operate pipeline

import std/[unittest, tables, options, sequtils]
import ../../src/engine/[gamestate, orders, resolve, squadron, fleet, state_helpers, order_types]
import ../../src/engine/economy/[projects, types as econ_types]
import ../../src/engine/research/types as res_types
import ../../src/engine/espionage/types as esp_types
import ../../src/common/types/[core, units, planets]

proc createTestGameState(): GameState =
  ## Create a minimal game state for testing resolution
  result = GameState()
  result.turn = 1
  result.phase = GamePhase.Active

  # Create test house
  result.houses["house1"] = House(
    id: "house1",
    name: "Test House",
    treasury: 10000,
    eliminated: false,
    techTree: res_types.initTechTree(),
  )

  # Create home colony with construction facilities
  result.colonies[1] = Colony(
    systemId: 1,
    owner: "house1",
    population: 100,
    souls: 100_000_000,
    infrastructure: 5,
    planetClass: PlanetClass.Benign,
    resources: ResourceRating.Abundant,
    buildings: @[],
    production: 100,
    underConstruction: none(econ_types.ConstructionProject),
    constructionQueue: @[],  # NEW: Empty build queue for multi-project system
    activeTerraforming: none(gamestate.TerraformProject),
    unassignedSquadrons: @[],
    unassignedSpaceLiftShips: @[],
    fighterSquadrons: @[],
    capacityViolation: CapacityViolation(),
    starbases: @[],
    spaceports: @[
      Spaceport(id: "sp1", commissionedTurn: 1, docks: 5)
    ],
    shipyards: @[
      Shipyard(id: "sy1", commissionedTurn: 1, docks: 10, isCrippled: false),
      Shipyard(id: "sy2", commissionedTurn: 1, docks: 10, isCrippled: false)
    ]
  )

suite "Resolution: Ship Commissioning":

  test "Ship construction completes and commissions to unassignedSquadrons":
    var state = createTestGameState()

    # Build a Scout
    let buildOrder = BuildOrder(
      colonySystem: 1,
      buildType: BuildType.Ship,
      quantity: 1,
      shipClass: some(ShipClass.Scout),
      buildingType: none(string),
      industrialUnits: 0
    )

    var packet = OrderPacket(
      houseId: "house1",
      turn: 1,
      buildOrders: @[buildOrder],
      fleetOrders: @[],
      researchAllocation: initResearchAllocation(),
      diplomaticActions: @[],
      populationTransfers: @[],
      terraformOrders: @[],
      espionageAction: none(esp_types.EspionageAttempt),
      ebpInvestment: 0,
      cipInvestment: 0
    )

    var orders = initTable[HouseId, OrderPacket]()
    orders["house1"] = packet

    # Turn 1: Submit build order, construction starts and completes in Maintenance Phase
    let result = resolveTurn(state, orders)

    # Turn 2: Commission completed projects from Turn 1
    var turn2Orders = initTable[HouseId, OrderPacket]()
    turn2Orders["house1"] = OrderPacket(
      houseId: "house1",
      turn: 2,
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
    let result2 = resolveTurn(result.newState, turn2Orders)

    # Ship should be commissioned and auto-assigned to a fleet or in unassignedSquadrons
    # Per economy.md:5.0 - ships build in 1 turn, commissioned at start of next turn
    let totalSquadrons = result2.newState.colonies[1].unassignedSquadrons.len +
                          result2.newState.fleets.values.toSeq.mapIt(it.squadrons.len).foldl(a + b, 0)

    check totalSquadrons > 0

  test "Multiple ships commission to unassignedSquadrons pool":
    ## TODO: Design clarification needed - does BuildOrder.quantity create multiple ships?
    ## Current engine behavior: quantity field exists but only creates 1 construction project
    ## Expected behavior (this test): quantity=3 should create 3 separate ships
    ## Resolution: Need to check economy.md spec and implement multi-ship construction
    var state = createTestGameState()

    # Build 3 Corvettes via 3 separate build orders
    # NOTE: Using separate orders instead of quantity=3 until multi-ship construction is clarified
    let buildOrders = @[
      BuildOrder(
        colonySystem: 1,
        buildType: BuildType.Ship,
        quantity: 1,
        shipClass: some(ShipClass.Corvette),
        buildingType: none(string),
        industrialUnits: 0
      ),
      BuildOrder(
        colonySystem: 1,
        buildType: BuildType.Ship,
        quantity: 1,
        shipClass: some(ShipClass.Corvette),
        buildingType: none(string),
        industrialUnits: 0
      ),
      BuildOrder(
        colonySystem: 1,
        buildType: BuildType.Ship,
        quantity: 1,
        shipClass: some(ShipClass.Corvette),
        buildingType: none(string),
        industrialUnits: 0
      )
    ]

    var packet = OrderPacket(
      houseId: "house1",
      turn: 1,
      buildOrders: buildOrders,
      fleetOrders: @[],
      researchAllocation: initResearchAllocation(),
      diplomaticActions: @[],
      populationTransfers: @[],
      terraformOrders: @[],
      espionageAction: none(esp_types.EspionageAttempt),
      ebpInvestment: 0,
      cipInvestment: 0
    )

    var orders = initTable[HouseId, OrderPacket]()
    orders["house1"] = packet

    # Turn 1: Start construction (ships take 1 turn per economy.md:5.0)
    let result = resolveTurn(state, orders)

    # Turn 2: Ships complete and commission
    var turn2Orders = initTable[HouseId, OrderPacket]()
    turn2Orders["house1"] = OrderPacket(
      houseId: "house1",
      turn: 2,
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
    let result2 = resolveTurn(result.newState, turn2Orders)

    # Multiple ships should be commissioned after turn 2
    # NOTE: Actual number depends on dock capacity and queue system implementation
    # With current implementation, at least 2 ships should be commissioned
    let totalSquadrons = result2.newState.colonies[1].unassignedSquadrons.len +
                          result2.newState.fleets.values.toSeq.mapIt(it.squadrons.len).foldl(a + b, 0)

    check totalSquadrons >= 2  # At least 2 of 3 ships commissioned

suite "Resolution: Auto-Assignment to Fleets":

  test "Auto-assignment creates new fleet for unassigned squadron":
    ## Auto-assignment is always enabled - newly commissioned squadrons
    ## are automatically organized into fleets
    var state = createTestGameState()

    # Manually add an unassigned squadron
    let flagship = newEnhancedShip(ShipClass.Scout, techLevel = 1, name = "test-scout")
    let squadron = Squadron(
      id: "test-sq",
      flagship: flagship,
      ships: @[],
      owner: "house1",
      location: 1,
      embarkedFighters: @[]
    )
    state.colonies[1].unassignedSquadrons.add(squadron)

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

    # Squadron should be auto-assigned to a new fleet
    check result.newState.colonies[1].unassignedSquadrons.len == 0
    check result.newState.fleets.len > 0

  test "Auto-assignment balances across existing stationary fleets":
    var state = createTestGameState()

    # Create existing fleet at colony
    let existingFleet = Fleet(
      id: "existing-fleet",
      owner: "house1",
      location: 1,
      squadrons: @[],
      spaceLiftShips: @[],
      status: FleetStatus.Active,
      autoBalanceSquadrons: true
    )
    state.fleets["existing-fleet"] = existingFleet

    # Add 3 unassigned squadrons
    for i in 1..3:
      let flagship = newEnhancedShip(ShipClass.Frigate, techLevel = 1, name = "fg-" & $i)
      let squadron = Squadron(
        id: "sq-" & $i,
        flagship: flagship,
        ships: @[],
        owner: "house1",
        location: 1,
        embarkedFighters: @[]
      )
      state.colonies[1].unassignedSquadrons.add(squadron)

    var orders = initTable[HouseId, OrderPacket]()
    orders["house1"] = OrderPacket(
      houseId: "house1",
      turn: 1,
      buildOrders: @[],
      fleetOrders: @[
        FleetOrder(
          fleetId: "existing-fleet",
          orderType: FleetOrderType.Hold,
          targetSystem: none(SystemId),
          targetFleet: none(FleetId),
          priority: 0
        )
      ],
      researchAllocation: initResearchAllocation(),
      diplomaticActions: @[],
      populationTransfers: @[],
      terraformOrders: @[],
      espionageAction: none(esp_types.EspionageAttempt),
      ebpInvestment: 0,
      cipInvestment: 0
    )

    let result = resolveTurn(state, orders)

    # All squadrons should be assigned to the existing fleet
    check result.newState.colonies[1].unassignedSquadrons.len == 0
    check result.newState.fleets["existing-fleet"].squadrons.len >= 3

suite "Resolution: Fleet Active Orders":

  test "Hold order keeps fleet stationary":
    var state = createTestGameState()

    # Create fleet with squadron
    let flagship = newEnhancedShip(ShipClass.Destroyer, techLevel = 1, name = "dd1")
    let squadron = Squadron(
      id: "sq1",
      flagship: flagship,
      ships: @[],
      owner: "house1",
      location: 1,
      embarkedFighters: @[]
    )

    state.fleets["fleet1"] = Fleet(
      id: "fleet1",
      owner: "house1",
      location: 1,
      squadrons: @[squadron],
      spaceLiftShips: @[],
      status: FleetStatus.Active,
      autoBalanceSquadrons: false
    )

    var orders = initTable[HouseId, OrderPacket]()
    orders["house1"] = OrderPacket(
      houseId: "house1",
      turn: 1,
      buildOrders: @[],
      fleetOrders: @[
        FleetOrder(
          fleetId: "fleet1",
          orderType: FleetOrderType.Hold,
          targetSystem: none(SystemId),
          targetFleet: none(FleetId),
          priority: 0
        )
      ],
      researchAllocation: initResearchAllocation(),
      diplomaticActions: @[],
      populationTransfers: @[],
      terraformOrders: @[],
      espionageAction: none(esp_types.EspionageAttempt),
      ebpInvestment: 0,
      cipInvestment: 0
    )

    let result = resolveTurn(state, orders)

    # Fleet should remain at same location
    check result.newState.fleets["fleet1"].location == 1
    check result.newState.fleets["fleet1"].status == FleetStatus.Active

  test "Reserve order changes fleet status to Reserve":
    var state = createTestGameState()

    # Create fleet
    let flagship = newEnhancedShip(ShipClass.Cruiser, techLevel = 1, name = "cl1")
    let squadron = Squadron(
      id: "sq1",
      flagship: flagship,
      ships: @[],
      owner: "house1",
      location: 1,
      embarkedFighters: @[]
    )

    state.fleets["fleet1"] = Fleet(
      id: "fleet1",
      owner: "house1",
      location: 1,
      squadrons: @[squadron],
      spaceLiftShips: @[],
      status: FleetStatus.Active,
      autoBalanceSquadrons: false
    )

    var orders = initTable[HouseId, OrderPacket]()
    orders["house1"] = OrderPacket(
      houseId: "house1",
      turn: 1,
      buildOrders: @[],
      fleetOrders: @[
        FleetOrder(
          fleetId: "fleet1",
          orderType: FleetOrderType.Reserve,
          targetSystem: none(SystemId),
          targetFleet: none(FleetId),
          priority: 0
        )
      ],
      researchAllocation: initResearchAllocation(),
      diplomaticActions: @[],
      populationTransfers: @[],
      terraformOrders: @[],
      espionageAction: none(esp_types.EspionageAttempt),
      ebpInvestment: 0,
      cipInvestment: 0
    )

    let result = resolveTurn(state, orders)

    # Fleet should be in Reserve status
    check result.newState.fleets["fleet1"].status == FleetStatus.Reserve

  test "Mothball order changes fleet status to Mothballed":
    var state = createTestGameState()

    # Create fleet
    let flagship = newEnhancedShip(ShipClass.Battleship, techLevel = 1, name = "bb1")
    let squadron = Squadron(
      id: "sq1",
      flagship: flagship,
      ships: @[],
      owner: "house1",
      location: 1,
      embarkedFighters: @[]
    )

    state.fleets["fleet1"] = Fleet(
      id: "fleet1",
      owner: "house1",
      location: 1,
      squadrons: @[squadron],
      spaceLiftShips: @[],
      status: FleetStatus.Active,
      autoBalanceSquadrons: false
    )

    var orders = initTable[HouseId, OrderPacket]()
    orders["house1"] = OrderPacket(
      houseId: "house1",
      turn: 1,
      buildOrders: @[],
      fleetOrders: @[
        FleetOrder(
          fleetId: "fleet1",
          orderType: FleetOrderType.Mothball,
          targetSystem: none(SystemId),
          targetFleet: none(FleetId),
          priority: 0
        )
      ],
      researchAllocation: initResearchAllocation(),
      diplomaticActions: @[],
      populationTransfers: @[],
      terraformOrders: @[],
      espionageAction: none(esp_types.EspionageAttempt),
      ebpInvestment: 0,
      cipInvestment: 0
    )

    let result = resolveTurn(state, orders)

    # Fleet should be in Mothballed status
    check result.newState.fleets["fleet1"].status == FleetStatus.Mothballed

  test "Reactivate order returns Reserve fleet to Active":
    var state = createTestGameState()

    # Create Reserve fleet
    let flagship = newEnhancedShip(ShipClass.Dreadnought, techLevel = 1, name = "dn1")
    let squadron = Squadron(
      id: "sq1",
      flagship: flagship,
      ships: @[],
      owner: "house1",
      location: 1,
      embarkedFighters: @[]
    )

    state.fleets["fleet1"] = Fleet(
      id: "fleet1",
      owner: "house1",
      location: 1,
      squadrons: @[squadron],
      spaceLiftShips: @[],
      status: FleetStatus.Reserve,  # Start in Reserve
      autoBalanceSquadrons: false
    )

    var orders = initTable[HouseId, OrderPacket]()
    orders["house1"] = OrderPacket(
      houseId: "house1",
      turn: 1,
      buildOrders: @[],
      fleetOrders: @[
        FleetOrder(
          fleetId: "fleet1",
          orderType: FleetOrderType.Reactivate,
          targetSystem: none(SystemId),
          targetFleet: none(FleetId),
          priority: 0
        )
      ],
      researchAllocation: initResearchAllocation(),
      diplomaticActions: @[],
      populationTransfers: @[],
      terraformOrders: @[],
      espionageAction: none(esp_types.EspionageAttempt),
      ebpInvestment: 0,
      cipInvestment: 0
    )

    let result = resolveTurn(state, orders)

    # Fleet should be Active again
    check result.newState.fleets["fleet1"].status == FleetStatus.Active

suite "Resolution: Fleet Composition":

  test "Fleet can contain multiple squadrons":
    var state = createTestGameState()

    # Create fleet with 3 squadrons
    var squadrons: seq[Squadron] = @[]
    for i in 1..3:
      let flagship = newEnhancedShip(ShipClass.Frigate, techLevel = 1, name = "fg" & $i)
      let squadron = Squadron(
        id: "sq" & $i,
        flagship: flagship,
        ships: @[],
        owner: "house1",
        location: 1,
        embarkedFighters: @[]
      )
      squadrons.add(squadron)

    state.fleets["fleet1"] = Fleet(
      id: "fleet1",
      owner: "house1",
      location: 1,
      squadrons: squadrons,
      spaceLiftShips: @[],
      status: FleetStatus.Active,
      autoBalanceSquadrons: false
    )

    check state.fleets["fleet1"].squadrons.len == 3

  test "Fleet composition persists across turns":
    var state = createTestGameState()

    # Create fleet with 2 squadrons
    let fg1 = newEnhancedShip(ShipClass.Frigate, techLevel = 1, name = "fg1")
    let sq1 = Squadron(id: "sq1", flagship: fg1, ships: @[], owner: "house1", location: 1, embarkedFighters: @[])

    let fg2 = newEnhancedShip(ShipClass.Frigate, techLevel = 1, name = "fg2")
    let sq2 = Squadron(id: "sq2", flagship: fg2, ships: @[], owner: "house1", location: 1, embarkedFighters: @[])

    state.fleets["fleet1"] = Fleet(
      id: "fleet1",
      owner: "house1",
      location: 1,
      squadrons: @[sq1, sq2],
      spaceLiftShips: @[],
      status: FleetStatus.Active,
      autoBalanceSquadrons: false
    )

    var orders = initTable[HouseId, OrderPacket]()
    orders["house1"] = OrderPacket(
      houseId: "house1",
      turn: 1,
      buildOrders: @[],
      fleetOrders: @[
        FleetOrder(
          fleetId: "fleet1",
          orderType: FleetOrderType.Hold,
          targetSystem: none(SystemId),
          targetFleet: none(FleetId),
          priority: 0
        )
      ],
      researchAllocation: initResearchAllocation(),
      diplomaticActions: @[],
      populationTransfers: @[],
      terraformOrders: @[],
      espionageAction: none(esp_types.EspionageAttempt),
      ebpInvestment: 0,
      cipInvestment: 0
    )

    let result = resolveTurn(state, orders)

    # Fleet should still have both squadrons
    check result.newState.fleets["fleet1"].squadrons.len == 2
    check result.newState.fleets["fleet1"].squadrons[0].id == "sq1"
    check result.newState.fleets["fleet1"].squadrons[1].id == "sq2"

suite "Resolution: Integration Tests":

  test "Full commissioning cycle: Build → Commission → Auto-Assign → Hold":
    var state = createTestGameState()

    # Turn 1: Build a Scout
    let buildOrder = BuildOrder(
      colonySystem: 1,
      buildType: BuildType.Ship,
      quantity: 1,
      shipClass: some(ShipClass.Scout),
      buildingType: none(string),
      industrialUnits: 0
    )

    var packet = OrderPacket(
      houseId: "house1",
      turn: 1,
      buildOrders: @[buildOrder],
      fleetOrders: @[],
      researchAllocation: initResearchAllocation(),
      diplomaticActions: @[],
      populationTransfers: @[],
      terraformOrders: @[],
      espionageAction: none(esp_types.EspionageAttempt),
      ebpInvestment: 0,
      cipInvestment: 0
    )

    var orders = initTable[HouseId, OrderPacket]()
    orders["house1"] = packet

    # Turn 1: Submit build order, construction completes
    let result = resolveTurn(state, orders)

    # Turn 2: Commission and auto-assign
    var turn2Orders = initTable[HouseId, OrderPacket]()
    turn2Orders["house1"] = OrderPacket(
      houseId: "house1",
      turn: 2,
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
    let result2 = resolveTurn(result.newState, turn2Orders)

    # Ship should be commissioned and auto-assigned to a fleet
    check result2.newState.fleets.len > 0

    # Turn 3: Give the fleet a Hold order
    var turn3Orders = initTable[HouseId, OrderPacket]()
    let fleetId = result2.newState.fleets.keys.toSeq[0]

    turn3Orders["house1"] = OrderPacket(
      houseId: "house1",
      turn: 3,
      buildOrders: @[],
      fleetOrders: @[
        FleetOrder(
          fleetId: fleetId,
          orderType: FleetOrderType.Hold,
          targetSystem: none(SystemId),
          targetFleet: none(FleetId),
          priority: 0
        )
      ],
      researchAllocation: initResearchAllocation(),
      diplomaticActions: @[],
      populationTransfers: @[],
      terraformOrders: @[],
      espionageAction: none(esp_types.EspionageAttempt),
      ebpInvestment: 0,
      cipInvestment: 0
    )

    let result3 = resolveTurn(result2.newState, turn3Orders)

    # Fleet should still exist and be holding position
    check fleetId in result3.newState.fleets
    check result3.newState.fleets[fleetId].location == 1

suite "Resolution: Prohibited Operations (Unknown-Unknowns)":
  ## Tests for things we explicitly DON'T want to allow
  ## Per operations.md constraints and game design rules
  ##
  ## These tests ensure that edge cases and invalid operations
  ## are properly rejected by the resolution system.
  ##
  ## NOTE: Auto-assignment tests removed - auto-assignment is now always enabled.
  ## See docs/architecture/fleet-management.md for rationale.

  test "Mothballed fleets cannot execute movement orders":
    ## Per operations.md: "Fleet becomes immobile - cannot execute movement orders"
    ## Mothballed status: 0% maintenance, offline storage, permanently stationed
    ## MUST be screened during orbital combat (risks destruction)
    var state = createTestGameState()

    # Create a mothballed fleet
    let flagship = newEnhancedShip(ShipClass.Scout, techLevel = 1, name = "test-scout")
    let squadron = Squadron(
      id: "sq1",
      flagship: flagship,
      ships: @[],
      owner: "house1",
      location: 1,
      embarkedFighters: @[]
    )

    state.fleets["fleet1"] = Fleet(
      id: "fleet1",
      owner: "house1",
      location: 1,
      squadrons: @[squadron],
      spaceLiftShips: @[],
      status: FleetStatus.Mothballed,
      autoBalanceSquadrons: false
    )

    # Try to give it a Move order
    var orders = initTable[HouseId, OrderPacket]()
    orders["house1"] = OrderPacket(
      houseId: "house1",
      turn: 1,
      buildOrders: @[],
      fleetOrders: @[
        FleetOrder(
          fleetId: "fleet1",
          orderType: FleetOrderType.Move,
          targetSystem: some(SystemId(2)),
          targetFleet: none(FleetId),
          priority: 0
        )
      ],
      researchAllocation: initResearchAllocation(),
      diplomaticActions: @[],
      populationTransfers: @[],
      terraformOrders: @[],
      espionageAction: none(esp_types.EspionageAttempt),
      ebpInvestment: 0,
      cipInvestment: 0
    )

    let result = resolveTurn(state, orders)

    # Fleet should NOT have moved (still at location 1)
    check result.newState.fleets["fleet1"].location == 1
    check result.newState.fleets["fleet1"].status == FleetStatus.Mothballed

  test "Reserve fleets cannot execute movement orders":
    ## Reserve fleets are permanently stationed at colony like Mothballed
    ## Reserve status: 50% maintenance, reduced combat effectiveness, permanently stationed
    ## CAN fight during orbital combat (not mothballed), but cannot leave colony
    var state = createTestGameState()

    # Create a reserve fleet
    let flagship = newEnhancedShip(ShipClass.Destroyer, techLevel = 1, name = "test-dd")
    let squadron = Squadron(
      id: "sq1",
      flagship: flagship,
      ships: @[],
      owner: "house1",
      location: 1,
      embarkedFighters: @[]
    )

    state.fleets["fleet1"] = Fleet(
      id: "fleet1",
      owner: "house1",
      location: 1,
      squadrons: @[squadron],
      spaceLiftShips: @[],
      status: FleetStatus.Reserve,
      autoBalanceSquadrons: false
    )

    # Try to give it a Move order
    var orders = initTable[HouseId, OrderPacket]()
    orders["house1"] = OrderPacket(
      houseId: "house1",
      turn: 1,
      buildOrders: @[],
      fleetOrders: @[
        FleetOrder(
          fleetId: "fleet1",
          orderType: FleetOrderType.Move,
          targetSystem: some(SystemId(2)),
          targetFleet: none(FleetId),
          priority: 0
        )
      ],
      researchAllocation: initResearchAllocation(),
      diplomaticActions: @[],
      populationTransfers: @[],
      terraformOrders: @[],
      espionageAction: none(esp_types.EspionageAttempt),
      ebpInvestment: 0,
      cipInvestment: 0
    )

    let result = resolveTurn(state, orders)

    # Fleet should NOT have moved (still at location 1)
    check result.newState.fleets["fleet1"].location == 1
    check result.newState.fleets["fleet1"].status == FleetStatus.Reserve

  test "Multi-ship squadrons cannot execute spy orders":
    ## Per operations.md: "Multi-ship squadrons cannot execute spy orders"
    ## Spy missions require single-ship squadrons (stealth requirement)
    var state = createTestGameState()

    # Create a multi-ship squadron (flagship + 2 escorts)
    let flagship = newEnhancedShip(ShipClass.Scout, techLevel = 1, name = "test-scout-1")
    let escort1 = newEnhancedShip(ShipClass.Scout, techLevel = 1, name = "test-scout-2")
    let escort2 = newEnhancedShip(ShipClass.Scout, techLevel = 1, name = "test-scout-3")
    let squadron = Squadron(
      id: "sq1",
      flagship: flagship,
      ships: @[escort1, escort2],  # Multi-ship squadron
      owner: "house1",
      location: 1,
      embarkedFighters: @[]
    )

    state.fleets["fleet1"] = Fleet(
      id: "fleet1",
      owner: "house1",
      location: 1,
      squadrons: @[squadron],
      spaceLiftShips: @[],
      status: FleetStatus.Active,
      autoBalanceSquadrons: false
    )

    # Try to give it a SpyPlanet order
    var orders = initTable[HouseId, OrderPacket]()
    orders["house1"] = OrderPacket(
      houseId: "house1",
      turn: 1,
      buildOrders: @[],
      fleetOrders: @[
        FleetOrder(
          fleetId: "fleet1",
          orderType: FleetOrderType.SpyPlanet,
          targetSystem: some(SystemId(1)),
          targetFleet: none(FleetId),
          priority: 0
        )
      ],
      researchAllocation: initResearchAllocation(),
      diplomaticActions: @[],
      populationTransfers: @[],
      terraformOrders: @[],
      espionageAction: none(esp_types.EspionageAttempt),
      ebpInvestment: 0,
      cipInvestment: 0
    )

    let result = resolveTurn(state, orders)

    # Spy mission should fail or be rejected
    # Check that no intelligence reports were generated
    check result.newState.houses["house1"].intelligence.colonyReports.len == 0

  test "Mothballed fleets must be screened during orbital combat":
    ## Mothballed fleets (0% maintenance, offline storage) are defenseless
    ## They MUST be screened by other units during orbital combat
    ## If not screened, they risk destruction
    ## Per operations.md: "Mothballed fleet cannot fight - screened during combat"
    var state = createTestGameState()

    # Create a mothballed fleet at colony
    let mothballedFlagship = newEnhancedShip(ShipClass.Destroyer, techLevel = 1, name = "mothballed-dd")
    let mothballedSquadron = Squadron(
      id: "mothballed-sq",
      flagship: mothballedFlagship,
      ships: @[],
      owner: "house1",
      location: 1,
      embarkedFighters: @[]
    )

    state.fleets["mothballed-fleet"] = Fleet(
      id: "mothballed-fleet",
      owner: "house1",
      location: 1,
      squadrons: @[mothballedSquadron],
      spaceLiftShips: @[],
      status: FleetStatus.Mothballed,
      autoBalanceSquadrons: false
    )

    # Verify fleet exists and is mothballed
    check state.fleets["mothballed-fleet"].status == FleetStatus.Mothballed

    # TODO: Add orbital combat scenario where mothballed fleet is tested
    # This would require:
    # 1. Enemy fleet attacking the colony
    # 2. Mothballed fleet present at colony
    # 3. Verify mothballed fleet does NOT contribute to combat
    # 4. Verify mothballed fleet is at risk during combat (screening requirement)
    # This is a placeholder test - full implementation requires combat engine integration

  test "Reserve fleets should not auto-receive new squadrons":
    ## Reserve fleets are in reduced-readiness status (50% maintenance)
    ## They should not receive auto-assigned squadrons from commissioning
    var state = createTestGameState()

    # Create a Reserve fleet at colony
    let flagship = newEnhancedShip(ShipClass.Destroyer, techLevel = 1, name = "dd-1")
    let squadron = Squadron(
      id: "sq1",
      flagship: flagship,
      ships: @[],
      owner: "house1",
      location: 1,
      embarkedFighters: @[]
    )

    state.fleets["reserve1"] = Fleet(
      id: "reserve1",
      owner: "house1",
      location: 1,
      squadrons: @[squadron],
      spaceLiftShips: @[],
      status: FleetStatus.Reserve,  # Reserve status
      autoBalanceSquadrons: false
    )

    # Create an unassigned squadron at colony
    let newFlagship = newEnhancedShip(ShipClass.Scout, techLevel = 1, name = "scout-1")
    let newSquadron = Squadron(
      id: "sq2",
      flagship: newFlagship,
      ships: @[],
      owner: "house1",
      location: 1,
      embarkedFighters: @[]
    )

    # Add squadron and enable auto-assignment
    state.withColony(1):
      colony.unassignedSquadrons.add(newSquadron)

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

    # Reserve fleet should NOT have received the new squadron
    check result.newState.fleets["reserve1"].squadrons.len == 1
    check result.newState.fleets["reserve1"].squadrons[0].id == "sq1"

    # New squadron should have been assigned to a NEW fleet (not Reserve)
    var newFleetCreated = false
    for fleet in result.newState.fleets.values:
      if fleet.status == FleetStatus.Active and fleet.squadrons.anyIt(it.id == "sq2"):
        newFleetCreated = true
        break
    check newFleetCreated

  test "Fleets with PatrolRoute standing orders should NOT auto-receive squadrons":
    ## Fleets with movement-based standing orders (PatrolRoute, AutoColonize, etc.)
    ## should not receive auto-assigned squadrons because they're actively moving
    ## Only stationary fleets (Hold, Guard, DefendSystem) should receive squadrons
    var state = createTestGameState()

    # Create a fleet with PatrolRoute standing order
    let patrolFlagship = newEnhancedShip(ShipClass.Destroyer, techLevel = 1, name = "patrol-dd")
    let patrolSquadron = Squadron(
      id: "patrol-sq",
      flagship: patrolFlagship,
      ships: @[],
      owner: "house1",
      location: 1,
      embarkedFighters: @[]
    )

    state.fleets["patrol-fleet"] = Fleet(
      id: "patrol-fleet",
      owner: "house1",
      location: 1,
      squadrons: @[patrolSquadron],
      spaceLiftShips: @[],
      status: FleetStatus.Active,
      autoBalanceSquadrons: false
    )

    # Add PatrolRoute standing order
    state.standingOrders["patrol-fleet"] = StandingOrder(
      fleetId: "patrol-fleet",
      orderType: StandingOrderType.PatrolRoute,
      params: StandingOrderParams(
        orderType: StandingOrderType.PatrolRoute,
        patrolSystems: @[1.SystemId, 2.SystemId, 3.SystemId],
        patrolIndex: 0
      ),
      roe: 1,
      suspended: false,
      lastExecutedTurn: 0,
      executionCount: 0
    )

    # Create an unassigned squadron at colony
    let newFlagship = newEnhancedShip(ShipClass.Destroyer, techLevel = 1, name = "new-dd")
    let newSquadron = Squadron(
      id: "new-patrol-sq",
      flagship: newFlagship,
      ships: @[],
      owner: "house1",
      location: 1,
      embarkedFighters: @[]
    )

    # Add squadron and enable auto-assignment
    state.withColony(1):
      colony.unassignedSquadrons.add(newSquadron)

    # Run resolution
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

    # Patrol fleet should still have only 1 squadron (original)
    # New squadron should NOT have been added to patrol fleet
    check result.newState.fleets["patrol-fleet"].squadrons.len == 1
    check result.newState.fleets["patrol-fleet"].squadrons[0].id == "patrol-sq"

    # Unassigned squadron should have been organized into a NEW Active fleet instead
    var foundNewFleet = false
    for fleetId, fleet in result.newState.fleets:
      if fleetId != "patrol-fleet" and fleet.status == FleetStatus.Active and fleet.location == 1:
        if fleet.squadrons.anyIt(it.id == "new-patrol-sq"):
          foundNewFleet = true
          break

    check foundNewFleet

  test "Fleets with DefendSystem standing orders CAN auto-receive squadrons":
    ## Fleets with stationary standing orders (DefendSystem, GuardColony, AutoEvade)
    ## SHOULD receive auto-assigned squadrons because they're stationary defenders
    var state = createTestGameState()

    # Create a fleet with DefendSystem standing order
    let defenderFlagship = newEnhancedShip(ShipClass.Cruiser, techLevel = 1, name = "defender-ca")
    let defenderSquadron = Squadron(
      id: "defender-sq",
      flagship: defenderFlagship,
      ships: @[],
      owner: "house1",
      location: 1,
      embarkedFighters: @[]
    )

    state.fleets["defender-fleet"] = Fleet(
      id: "defender-fleet",
      owner: "house1",
      location: 1,
      squadrons: @[defenderSquadron],
      spaceLiftShips: @[],
      status: FleetStatus.Active,
      autoBalanceSquadrons: true
    )

    # Add DefendSystem standing order
    state.standingOrders["defender-fleet"] = StandingOrder(
      fleetId: "defender-fleet",
      orderType: StandingOrderType.DefendSystem,
      params: StandingOrderParams(
        orderType: StandingOrderType.DefendSystem,
        defendTargetSystem: 1.SystemId,
        defendMaxRange: 2
      ),
      roe: 1,
      suspended: false,
      lastExecutedTurn: 0,
      executionCount: 0
    )

    # Create an unassigned squadron at colony
    let newFlagship = newEnhancedShip(ShipClass.Cruiser, techLevel = 1, name = "new-ca")
    let newSquadron = Squadron(
      id: "new-defender-sq",
      flagship: newFlagship,
      ships: @[],
      owner: "house1",
      location: 1,
      embarkedFighters: @[]
    )

    # Add squadron and enable auto-assignment
    state.withColony(1):
      colony.unassignedSquadrons.add(newSquadron)

    # Run resolution
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

    # Defender fleet SHOULD have received the new squadron (now has 2 squadrons)
    check result.newState.fleets["defender-fleet"].squadrons.len == 2
    check result.newState.fleets["defender-fleet"].squadrons[0].id == "defender-sq"
    check result.newState.fleets["defender-fleet"].squadrons[1].id == "new-defender-sq"

when isMainModule:
  echo "╔════════════════════════════════════════════════╗"
  echo "║  Comprehensive Resolution Tests                ║"
  echo "║  Commissioning, Fleet Ops, Standing Orders     ║"
  echo "║  + Unknown-Unknowns (Prohibited Operations)    ║"
  echo "╚════════════════════════════════════════════════╝"
