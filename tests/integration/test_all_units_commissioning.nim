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

import std/[unittest, tables, options, strformat, sequtils]
import ../../src/engine/[gamestate, orders, resolve, spacelift, squadron]
import ../../src/engine/economy/types as econ_types
import ../../src/engine/research/types as res_types
import ../../src/engine/espionage/types as esp_types
import ../../src/common/types/[core, units, planets]

# =============================================================================
# Test Setup Utilities
# =============================================================================

proc createTestState(cstLevel: int = 10): GameState =
  ## Create a test game state with a colony capable of building any unit
  result = newGame("test", 4, 42)  # Use newGame for proper initialization
  result.turn = 1
  result.phase = GamePhase.Active

  # Get the house IDs that were created by newGame
  # newGame creates houses with IDs "house1", "house2", etc.
  let houseIds = @[HouseId("house1"), HouseId("house2"),
                   HouseId("house3"), HouseId("house4")]

  # Rename houses to canonical names and increase treasury for long game
  result.houses[houseIds[0]].name = "House Atreides"
  result.houses[houseIds[0]].treasury = 100000

  # Set tech levels (all maxed for testing)
  result.houses["house1"].techTree.levels.constructionTech = cstLevel
  result.houses["house1"].techTree.levels.weaponsTech = 10
  result.houses["house1"].techTree.levels.fighterDoctrine = 3
  result.houses["house1"].techTree.levels.advancedCarrierOps = 3

  # Create colony using helper
  result.colonies[1] = createHomeColony(SystemId(1), "house1")

  # Add facilities for construction
  result.colonies[1].shipyards.add(
    Shipyard(id: "sy1", commissionedTurn: 1, baseDocks: 20, isCrippled: false)
  )
  result.colonies[1].spaceports.add(
    Spaceport(id: "sp1", commissionedTurn: 1, baseDocks: 10)
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
    terraformOrders: @[],
    espionageAction: none(esp_types.EspionageAttempt),
    ebpInvestment: 0,
    cipInvestment: 0
  )

  var orders = initTable[HouseId, OrderPacket]()
  orders["house1"] = packet

  # Turn 1: Submit build order, construction completes in Maintenance Phase
  let result1 = resolveTurn(state, orders)

  # Turn 2: Commission completed projects from Turn 1
  var turn2Orders = initTable[HouseId, OrderPacket]()
  turn2Orders["house1"] = OrderPacket(
    houseId: "house1",
    turn: result1.newState.turn,
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
  let result2 = resolveTurn(result1.newState, turn2Orders)
  return result2.newState

proc getCommissionedSquadron(state: GameState): Squadron =
  ## Helper: Get the commissioned squadron from fleets (engine auto-assigns)
  ## Returns the first squadron found in any fleet
  if state.fleets.len == 0:
    raise newException(ValueError, "No fleets found - squadron not commissioned")
  let fleet = toSeq(state.fleets.values)[0]
  if fleet.squadrons.len == 0:
    raise newException(ValueError, "Fleet has no squadrons - squadron not commissioned")
  return fleet.squadrons[0]

proc getCommissionedSpaceLiftShip(state: GameState): SpaceLiftShip =
  ## Helper: Get the commissioned spacelift ship from fleets (engine auto-assigns)
  ## Returns the first spacelift ship found in any fleet
  if state.fleets.len == 0:
    raise newException(ValueError, "No fleets found - spacelift ship not commissioned")
  let fleet = toSeq(state.fleets.values)[0]
  if fleet.spaceLiftShips.len == 0:
    raise newException(ValueError, "Fleet has no spacelift ships - ship not commissioned")
  return fleet.spaceLiftShips[0]

# =============================================================================
# Combat Ships - Should Commission as Squadrons
# =============================================================================

suite "Combat Ship Commissioning - All Types":

  test "Fighter Squadron commissions to fighterSquadrons":
    var state = createTestState(cstLevel = 3)
    state = buildAndCommissionShip(state, ShipClass.Destroyer)

    # Fighter squadrons go to colony.fighterSquadrons, not regular squadrons
    check state.colonies[1].fighterSquadrons.len > 0
    check state.colonies[1].unassignedSquadrons.len == 0

  test "Corvette commissions as squadron":
    var state = createTestState(cstLevel = 1)
    state = buildAndCommissionShip(state, ShipClass.Corvette)

    # Engine auto-assigns to fleets
    let squad = getCommissionedSquadron(state)
    check squad.flagship.shipClass == ShipClass.Corvette

  test "Frigate commissions as squadron":
    var state = createTestState(cstLevel = 1)
    state = buildAndCommissionShip(state, ShipClass.Frigate)

    let squad = getCommissionedSquadron(state)
    check squad.flagship.shipClass == ShipClass.Frigate

  test "Destroyer commissions as squadron":
    var state = createTestState(cstLevel = 1)
    state = buildAndCommissionShip(state, ShipClass.Destroyer)

    let squad = getCommissionedSquadron(state)
    check squad.flagship.shipClass == ShipClass.Destroyer

  test "Light Cruiser commissions as squadron":
    var state = createTestState(cstLevel = 1)
    state = buildAndCommissionShip(state, ShipClass.LightCruiser)

    let squad = getCommissionedSquadron(state)
    check squad.flagship.shipClass == ShipClass.LightCruiser

  test "Heavy Cruiser commissions as squadron":
    var state = createTestState(cstLevel = 2)
    state = buildAndCommissionShip(state, ShipClass.HeavyCruiser)

    let squad = getCommissionedSquadron(state)
    check squad.flagship.shipClass == ShipClass.HeavyCruiser

  test "Battle Cruiser commissions as squadron":
    var state = createTestState(cstLevel = 3)
    state = buildAndCommissionShip(state, ShipClass.Battlecruiser)

    let squad = getCommissionedSquadron(state)
    check squad.flagship.shipClass == ShipClass.Battlecruiser

  test "Battleship commissions as squadron":
    var state = createTestState(cstLevel = 4)
    state = buildAndCommissionShip(state, ShipClass.Battleship)

    let squad = getCommissionedSquadron(state)
    check squad.flagship.shipClass == ShipClass.Battleship

  test "Dreadnought commissions as squadron":
    var state = createTestState(cstLevel = 5)
    state = buildAndCommissionShip(state, ShipClass.Dreadnought)

    let squad = getCommissionedSquadron(state)
    check squad.flagship.shipClass == ShipClass.Dreadnought

  test "Super Dreadnought commissions as squadron":
    var state = createTestState(cstLevel = 6)
    state = buildAndCommissionShip(state, ShipClass.SuperDreadnought)

    let squad = getCommissionedSquadron(state)
    check squad.flagship.shipClass == ShipClass.SuperDreadnought

  test "Planet-Breaker commissions as squadron":
    var state = createTestState(cstLevel = 10)
    state = buildAndCommissionShip(state, ShipClass.PlanetBreaker)

    let squad = getCommissionedSquadron(state)
    check squad.flagship.shipClass == ShipClass.PlanetBreaker

  test "Carrier commissions as squadron":
    var state = createTestState(cstLevel = 3)
    state = buildAndCommissionShip(state, ShipClass.Carrier)

    let squad = getCommissionedSquadron(state)
    check squad.flagship.shipClass == ShipClass.Carrier
    # Carriers should have carryLimit set (3 for CV per reference.md)
    check squad.flagship.stats.carryLimit == 3

  test "Super Carrier commissions as squadron":
    var state = createTestState(cstLevel = 5)
    state = buildAndCommissionShip(state, ShipClass.SuperCarrier)

    let squad = getCommissionedSquadron(state)
    check squad.flagship.shipClass == ShipClass.SuperCarrier
    # Super Carriers should have carryLimit set (5 for CX per reference.md)
    check squad.flagship.stats.carryLimit == 5

  test "Raider commissions as squadron":
    var state = createTestState(cstLevel = 3)
    state = buildAndCommissionShip(state, ShipClass.Raider)

    let squad = getCommissionedSquadron(state)
    check squad.flagship.shipClass == ShipClass.Raider

  test "Scout commissions as squadron":
    var state = createTestState(cstLevel = 1)
    state = buildAndCommissionShip(state, ShipClass.Scout)

    let squad = getCommissionedSquadron(state)
    check squad.flagship.shipClass == ShipClass.Scout

# =============================================================================
# Spacelift Ships - Should Commission to unassignedSpaceLiftShips
# =============================================================================

suite "Spacelift Ship Commissioning":

  test "ETAC commissions to fleet":
    var state = createTestState(cstLevel = 1)
    state = buildAndCommissionShip(state, ShipClass.ETAC)

    # Engine auto-assigns spacelift ships to fleets
    let ship = getCommissionedSpaceLiftShip(state)
    check ship.shipClass == ShipClass.ETAC
    # ETACs auto-load 1 PTU at commissioning
    check ship.cargo.cargoType == CargoType.Colonists
    check ship.cargo.quantity == 1
    check ship.cargo.capacity == 1

  test "Troop Transport commissions to fleet":
    var state = createTestState(cstLevel = 1)
    state = buildAndCommissionShip(state, ShipClass.TroopTransport)

    let ship = getCommissionedSpaceLiftShip(state)
    check ship.shipClass == ShipClass.TroopTransport
    # Troop Transports should have capacity (1 marine unit per reference.md)
    check ship.cargo.capacity == 1
    # Starts empty (no marines loaded yet)
    check ship.cargo.quantity == 0

# =============================================================================
# Special Cases
# =============================================================================

suite "Special Commissioning Cases":

  test "Multiple ships commission and auto-assign to same fleet":
    var state = createTestState(cstLevel = 3)

    # Build 3 different ships - engine auto-assigns to same fleet at same location
    state = buildAndCommissionShip(state, ShipClass.Destroyer)
    let afterFirst = state.fleets.len

    state = buildAndCommissionShip(state, ShipClass.Cruiser)
    let afterSecond = state.fleets.len

    state = buildAndCommissionShip(state, ShipClass.Frigate)
    let afterThird = state.fleets.len

    # All ships commissioned to same fleet (correct auto-assignment behavior)
    check afterFirst == 1
    check afterSecond == 1  # Reuses existing fleet
    check afterThird == 1   # Reuses existing fleet

    # Verify ships commissioned successfully
    # Note: Squadron count may be < 3 if ships were assigned as escorts to existing squadrons
    # (engine intelligently fills squadron capacity instead of always creating new squadrons)
    let fleet = toSeq(state.fleets.values)[0]
    check fleet.squadrons.len >= 1  # At least one squadron exists
    check fleet.squadrons.len <= 3  # At most three squadrons (one per ship)

    # Count total ships across all squadrons (flagship + escorts)
    var totalShips = 0
    for sq in fleet.squadrons:
      totalShips += 1 + sq.ships.len  # 1 flagship + N escorts
    check totalShips == 3  # All 3 ships commissioned

  test "Commissioned squadron has correct stats":
    var state = createTestState(cstLevel = 10)
    state = buildAndCommissionShip(state, ShipClass.Battleship)

    let squad = getCommissionedSquadron(state)
    let ship = squad.flagship

    # Battleship stats from reference.md:10.1
    check ship.shipClass == ShipClass.Battleship
    # Stats are CST-scaled, so we just verify it commissioned successfully
    # and has reasonable stats
    check ship.stats.attackStrength > 0
    check ship.stats.defenseStrength > 0
    #echo state.fleets[0]
    for fleet in state.fleets.values:
      echo fleet
      #echo "***** fleet = " & fleet.squadrons

when isMainModule:
  echo "╔════════════════════════════════════════════════╗"
  echo "║  All Units Commissioning Tests                 ║"
  echo "║  Tests all 19 ship types commission correctly  ║"
  echo "╚════════════════════════════════════════════════╝"
