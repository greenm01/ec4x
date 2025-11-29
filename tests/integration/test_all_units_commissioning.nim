## Comprehensive Unit Commissioning Tests
##
## Tests that ALL 19 ship types commission correctly:
## - Combat ships → squadrons in unassignedSquadrons
## - Spacelift ships → unassignedSpaceLiftShips
## - Fighters → fighterSquadrons
## - Correct ship stats and squadron formation
##
## This test suite verifies the commissioning pipeline works for every ship type.
## After construction completes (1 turn), ships should be properly commissioned.
##
## Spec References:
## - Ships: docs/specs/reference.md:10.1
## - Commissioning: docs/specs/assets.md:2.2.3

import std/[unittest, tables, options, strformat]
import ../../src/engine/[gamestate, orders, resolve]
import ../../src/engine/economy/types as econ_types
import ../../src/engine/research/types as res_types
import ../../src/engine/espionage/types as esp_types
import ../../src/common/types/[core, units, planets]

# =============================================================================
# Test Setup Utilities
# =============================================================================

proc createTestState(cstLevel: int = 10): GameState =
  ## Create a test game state with a colony capable of building any unit
  result = GameState()
  result.turn = 1
  result.phase = GamePhase.Active

  # Create house with high CST and sufficient treasury
  result.houses["house1"] = House(
    id: "house1",
    name: "Test House",
    treasury: 100000,
    eliminated: false,
    techTree: res_types.initTechTree(),
  )

  # Set tech levels (all maxed for testing)
  result.houses["house1"].techTree.levels.constructionTech = cstLevel
  result.houses["house1"].techTree.levels.weaponsTech = 10
  result.houses["house1"].techTree.levels.fighterDoctrine = 3
  result.houses["house1"].techTree.levels.advancedCarrierOps = 3

  # Create colony using helper
  result.colonies[1] = createHomeColony(SystemId(1), "house1")

  # Add facilities for construction
  result.colonies[1].shipyards.add(
    Shipyard(id: "sy1", commissionedTurn: 1, docks: 20, isCrippled: false)
  )
  result.colonies[1].spaceports.add(
    Spaceport(id: "sp1", commissionedTurn: 1, docks: 10)
  )

proc buildAndCommissionShip(state: var GameState, shipClass: ShipClass): GameState =
  ## Build a ship and advance turns until it commissions
  ## Returns the new state after commissioning

  let buildOrder = BuildOrder(
    colonySystem: 1,
    buildType: BuildType.Ship,
    quantity: 1,
    shipClass: some(shipClass),
    buildingType: none(string),
    industrialUnits: 0
  )

  var packet = OrderPacket(
    houseId: "house1",
    turn: state.turn,
    buildOrders: @[buildOrder],
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

  var orders = initTable[HouseId, OrderPacket]()
  orders["house1"] = packet

  # Resolve turn (construction completes instantly per reference.md:10.1.1)
  let result = resolveTurn(state, orders)
  return result.newState

# =============================================================================
# Combat Ships - Should Commission as Squadrons
# =============================================================================

suite "Combat Ship Commissioning - All Types":

  test "Fighter Squadron commissions to fighterSquadrons":
    var state = createTestState(cstLevel = 3)
    state = buildAndCommissionShip(state, ShipClass.Fighter)

    # Fighter squadrons go to colony.fighterSquadrons, not regular squadrons
    check state.colonies[1].fighterSquadrons.len > 0
    check state.colonies[1].unassignedSquadrons.len == 0

  test "Corvette commissions as squadron":
    var state = createTestState(cstLevel = 1)
    state = buildAndCommissionShip(state, ShipClass.Corvette)

    check state.colonies[1].unassignedSquadrons.len > 0
    let squad = state.colonies[1].unassignedSquadrons[0]
    check squad.ships.len == 1
    check squad.ships[0].shipClass == ShipClass.Corvette

  test "Frigate commissions as squadron":
    var state = createTestState(cstLevel = 1)
    state = buildAndCommissionShip(state, ShipClass.Frigate)

    check state.colonies[1].unassignedSquadrons.len > 0
    check state.colonies[1].unassignedSquadrons[0].ships[0].shipClass == ShipClass.Frigate

  test "Destroyer commissions as squadron":
    var state = createTestState(cstLevel = 1)
    state = buildAndCommissionShip(state, ShipClass.Destroyer)

    check state.colonies[1].unassignedSquadrons.len > 0
    check state.colonies[1].unassignedSquadrons[0].ships[0].shipClass == ShipClass.Destroyer

  test "Light Cruiser commissions as squadron":
    var state = createTestState(cstLevel = 1)
    state = buildAndCommissionShip(state, ShipClass.LightCruiser)

    check state.colonies[1].unassignedSquadrons.len > 0
    check state.colonies[1].unassignedSquadrons[0].ships[0].shipClass == ShipClass.LightCruiser

  test "Heavy Cruiser commissions as squadron":
    var state = createTestState(cstLevel = 2)
    state = buildAndCommissionShip(state, ShipClass.HeavyCruiser)

    check state.colonies[1].unassignedSquadrons.len > 0
    check state.colonies[1].unassignedSquadrons[0].ships[0].shipClass == ShipClass.HeavyCruiser

  test "Battle Cruiser commissions as squadron":
    var state = createTestState(cstLevel = 3)
    state = buildAndCommissionShip(state, ShipClass.Battlecruiser)

    check state.colonies[1].unassignedSquadrons.len > 0
    check state.colonies[1].unassignedSquadrons[0].ships[0].shipClass == ShipClass.Battlecruiser

  test "Battleship commissions as squadron":
    var state = createTestState(cstLevel = 4)
    state = buildAndCommissionShip(state, ShipClass.Battleship)

    check state.colonies[1].unassignedSquadrons.len > 0
    check state.colonies[1].unassignedSquadrons[0].ships[0].shipClass == ShipClass.Battleship

  test "Dreadnought commissions as squadron":
    var state = createTestState(cstLevel = 5)
    state = buildAndCommissionShip(state, ShipClass.Dreadnought)

    check state.colonies[1].unassignedSquadrons.len > 0
    check state.colonies[1].unassignedSquadrons[0].ships[0].shipClass == ShipClass.Dreadnought

  test "Super Dreadnought commissions as squadron":
    var state = createTestState(cstLevel = 6)
    state = buildAndCommissionShip(state, ShipClass.SuperDreadnought)

    check state.colonies[1].unassignedSquadrons.len > 0
    check state.colonies[1].unassignedSquadrons[0].ships[0].shipClass == ShipClass.SuperDreadnought

  test "Planet-Breaker commissions as squadron":
    var state = createTestState(cstLevel = 10)
    state = buildAndCommissionShip(state, ShipClass.PlanetBreaker)

    check state.colonies[1].unassignedSquadrons.len > 0
    check state.colonies[1].unassignedSquadrons[0].ships[0].shipClass == ShipClass.PlanetBreaker

  test "Carrier commissions as squadron":
    var state = createTestState(cstLevel = 3)
    state = buildAndCommissionShip(state, ShipClass.Carrier)

    check state.colonies[1].unassignedSquadrons.len > 0
    let squad = state.colonies[1].unassignedSquadrons[0]
    check squad.ships[0].shipClass == ShipClass.Carrier
    # Carriers should have carryLimit set (3 for CV per reference.md)
    check squad.ships[0].stats.carryLimit == 3

  test "Super Carrier commissions as squadron":
    var state = createTestState(cstLevel = 5)
    state = buildAndCommissionShip(state, ShipClass.SuperCarrier)

    check state.colonies[1].unassignedSquadrons.len > 0
    let squad = state.colonies[1].unassignedSquadrons[0]
    check squad.ships[0].shipClass == ShipClass.SuperCarrier
    # Super Carriers should have carryLimit set (5 for CX per reference.md)
    check squad.ships[0].stats.carryLimit == 5

  test "Raider commissions as squadron":
    var state = createTestState(cstLevel = 3)
    state = buildAndCommissionShip(state, ShipClass.Raider)

    check state.colonies[1].unassignedSquadrons.len > 0
    check state.colonies[1].unassignedSquadrons[0].ships[0].shipClass == ShipClass.Raider

  test "Scout commissions as squadron":
    var state = createTestState(cstLevel = 1)
    state = buildAndCommissionShip(state, ShipClass.Scout)

    check state.colonies[1].unassignedSquadrons.len > 0
    check state.colonies[1].unassignedSquadrons[0].ships[0].shipClass == ShipClass.Scout

# =============================================================================
# Spacelift Ships - Should Commission to unassignedSpaceLiftShips
# =============================================================================

suite "Spacelift Ship Commissioning":

  test "ETAC commissions to unassignedSpaceLiftShips":
    var state = createTestState(cstLevel = 1)
    state = buildAndCommissionShip(state, ShipClass.ETAC)

    # ETAC is a spacelift ship, should go to unassignedSpaceLiftShips
    check state.colonies[1].unassignedSpaceLiftShips.len > 0
    check state.colonies[1].unassignedSpaceLiftShips[0].shipClass == ShipClass.ETAC
    # Should NOT be in regular squadrons
    check state.colonies[1].unassignedSquadrons.len == 0

  test "Troop Transport commissions to unassignedSpaceLiftShips":
    var state = createTestState(cstLevel = 1)
    state = buildAndCommissionShip(state, ShipClass.TroopTransport)

    check state.colonies[1].unassignedSpaceLiftShips.len > 0
    let transport = state.colonies[1].unassignedSpaceLiftShips[0]
    check transport.shipClass == ShipClass.TroopTransport
    # Troop Transports should have capacity (1 marine unit per reference.md)
    check transport.cargo.capacity == 1
    check state.colonies[1].unassignedSquadrons.len == 0

# =============================================================================
# Special Cases
# =============================================================================

suite "Special Commissioning Cases":

  test "Starbase does NOT commission as squadron":
    var state = createTestState(cstLevel = 3)
    state = buildAndCommissionShip(state, ShipClass.Starbase)

    # Starbases are facilities, not mobile units
    # They should be added to colony.starbases, not squadrons
    check state.colonies[1].starbases.len > 0
    check state.colonies[1].unassignedSquadrons.len == 0

  test "Multiple ships commission in same turn":
    var state = createTestState(cstLevel = 3)

    # Build 3 different ships
    state = buildAndCommissionShip(state, ShipClass.Destroyer)
    let afterFirst = state.colonies[1].unassignedSquadrons.len

    state = buildAndCommissionShip(state, ShipClass.Cruiser)
    let afterSecond = state.colonies[1].unassignedSquadrons.len

    state = buildAndCommissionShip(state, ShipClass.Frigate)
    let afterThird = state.colonies[1].unassignedSquadrons.len

    # Each ship should increment squadron count
    check afterSecond > afterFirst
    check afterThird > afterSecond

  test "Commissioned squadron has correct stats":
    var state = createTestState(cstLevel = 4)
    state = buildAndCommissionShip(state, ShipClass.Battleship)

    check state.colonies[1].unassignedSquadrons.len > 0
    let squad = state.colonies[1].unassignedSquadrons[0]
    check squad.ships.len == 1

    let ship = squad.ships[0]
    # Battleship stats from reference.md:10.1
    check ship.shipClass == ShipClass.Battleship
    check ship.stats.attackStrength == 20
    check ship.stats.defenseStrength == 25
    # Command stats are in squadron, not individual ship

when isMainModule:
  echo "╔════════════════════════════════════════════════╗"
  echo "║  All Units Commissioning Tests                ║"
  echo "║  Tests all 19 ship types commission correctly ║"
  echo "╚════════════════════════════════════════════════╝"
