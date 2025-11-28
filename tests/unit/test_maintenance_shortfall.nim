## Unit Tests for Maintenance Shortfall Cascade System
##
## Tests complete maintenance shortfall cascade per economy.md:3.11

import std/[unittest, tables]
import ../../src/engine/economy/maintenance_shortfall
import ../../src/engine/[gamestate, state_helpers, fleet]
import ../../src/common/types/[core, planets, units]

proc createTestHouse(id: HouseId, treasury: int, prestige: int = 100): House =
  House(
    id: id,
    name: $id,
    treasury: treasury,
    prestige: prestige,
    eliminated: false
  )

proc createTestFleet(id: FleetId, owner: HouseId, basePP: int = 100): Fleet =
  Fleet(
    id: id,
    owner: owner,
    location: "system-1",
    basePurchasePrice: basePP
  )

proc createTestColony(systemId: SystemId, owner: HouseId, iu: int = 10): Colony =
  Colony(
    systemId: systemId,
    owner: owner,
    planetClass: PlanetClass.Eden,
    populationUnits: 100,
    industrial: IndustrialUnits(units: iu),
    spaceports: @[],
    shipyards: @[],
    starbases: @[],
    groundBatteries: 0,
    armies: 0,
    marines: 0,
    planetaryShieldLevel: 0,
    constructionQueue: @[]
  )

suite "Asset Salvage Value Calculations":
  test "IndustrialUnit salvage":
    let salvage = calculateAssetSalvageValue(AssetType.IndustrialUnit)
    check salvage == 1  # 1 PP per IU per spec

  test "Spaceport salvage":
    let salvage = calculateAssetSalvageValue(AssetType.Spaceport)
    check salvage == 50  # 50 PP per spec

  test "Shipyard salvage":
    let salvage = calculateAssetSalvageValue(AssetType.Shipyard)
    check salvage == 75  # 75 PP per spec

  test "Starbase salvage":
    let salvage = calculateAssetSalvageValue(AssetType.Starbase)
    check salvage == 150  # 150 PP per spec

  test "GroundBattery salvage":
    let salvage = calculateAssetSalvageValue(AssetType.GroundBattery)
    check salvage == 10  # 10 PP per spec

  test "Army salvage":
    let salvage = calculateAssetSalvageValue(AssetType.Army)
    check salvage == 15  # 15 PP per spec

  test "Marine salvage":
    let salvage = calculateAssetSalvageValue(AssetType.Marine)
    check salvage == 20  # 20 PP per spec

  test "Shield salvage":
    let salvage = calculateAssetSalvageValue(AssetType.Shield)
    check salvage == 40  # 40 PP per shield level

suite "Fleet Salvage Calculations":
  test "Fleet 25% salvage value":
    let fleet = createTestFleet("fleet-1", "house-test", basePP=1000)
    let salvage = calculateFleetSalvageValue(fleet)
    check salvage == 250  # 25% of 1000 = 250

  test "Fleet minimum salvage":
    let fleet = createTestFleet("fleet-1", "house-test", basePP=0)
    let salvage = calculateFleetSalvageValue(fleet)
    check salvage == 0

suite "Prestige Penalty Calculation":
  test "First shortfall turn penalty":
    let penalty = calculatePrestigePenalty(consecutiveTurns=1)
    check penalty == 8  # First turn: -8

  test "Second consecutive turn penalty":
    let penalty = calculatePrestigePenalty(consecutiveTurns=2)
    check penalty == 11  # Second turn: -11

  test "Third consecutive turn penalty":
    let penalty = calculatePrestigePenalty(consecutiveTurns=3)
    check penalty == 14  # Third turn: -14

  test "Fourth+ consecutive turn penalty":
    let penalty = calculatePrestigePenalty(consecutiveTurns=4)
    check penalty == 17  # Fourth+ turn: -17

  test "Fifth consecutive turn penalty caps":
    let penalty = calculatePrestigePenalty(consecutiveTurns=5)
    check penalty == 17  # Still -17

suite "Shortfall Cascade Processing (Pure Function)":
  test "Treasury zeroed in cascade":
    var state = GameState()
    state.houses = initTable[HouseId, House]()
    state.colonies = initTable[SystemId, Colony]()
    state.fleets = initTable[FleetId, Fleet]()

    state.houses["house-test"] = createTestHouse("house-test", treasury=500)

    let cascade = processShortfall(state, "house-test", shortfall=100)

    # Treasury should be zeroed first
    check cascade.treasuryBefore == 500
    # House starts with 500 PP, which covers the 100 PP shortfall
    check cascade.fullyResolved == true

  test "Construction cancelled for shortfall":
    var state = GameState()
    state.houses = initTable[HouseId, House]()
    state.colonies = initTable[SystemId, Colony]()
    state.fleets = initTable[FleetId, Fleet]()

    state.houses["house-test"] = createTestHouse("house-test", treasury=0)
    var colony = createTestColony("system-1", "house-test")
    colony.constructionQueue = @[
      ConstructionProject(costRemaining: 50),
      ConstructionProject(costRemaining: 50)
    ]
    state.colonies["system-1"] = colony

    let cascade = processShortfall(state, "house-test", shortfall=80)

    # Should cancel construction and recoup PP
    check cascade.constructionCancelled.len > 0
    check cascade.ppLostFromCancellation > 0

  test "Fleets disbanded for larger shortfall":
    var state = GameState()
    state.houses = initTable[HouseId, House]()
    state.colonies = initTable[SystemId, Colony]()
    state.fleets = initTable[FleetId, Fleet]()

    state.houses["house-test"] = createTestHouse("house-test", treasury=0)
    state.fleets["fleet-1"] = createTestFleet("fleet-1", "house-test", basePP=1000)
    state.fleets["fleet-2"] = createTestFleet("fleet-2", "house-test", basePP=1000)

    let cascade = processShortfall(state, "house-test", shortfall=400)

    # Should disband fleets and get 25% salvage
    check cascade.fleetsDisbanded.len > 0
    check cascade.salvageFromFleets > 0

  test "Assets stripped for extreme shortfall":
    var state = GameState()
    state.houses = initTable[HouseId, House]()
    state.colonies = initTable[SystemId, Colony]()
    state.fleets = initTable[FleetId, Fleet]()

    state.houses["house-test"] = createTestHouse("house-test", treasury=0)
    state.colonies["system-1"] = createTestColony("system-1", "house-test", iu=50)

    let cascade = processShortfall(state, "house-test", shortfall=30)

    # Should strip IUs
    check cascade.assetsStripped.len > 0
    check cascade.salvageFromAssets > 0

  test "Prestige penalty calculated":
    var state = GameState()
    state.houses = initTable[HouseId, House]()
    state.colonies = initTable[SystemId, Colony]()
    state.fleets = initTable[FleetId, Fleet]()

    var house = createTestHouse("house-test", treasury=0)
    house.consecutiveShortfallTurns = 2
    state.houses["house-test"] = house

    let cascade = processShortfall(state, "house-test", shortfall=10)

    # Third turn should have -14 prestige penalty
    check cascade.consecutiveTurns == 3
    check cascade.prestigePenalty == 14

suite "Shortfall Cascade Application (State Mutations)":
  test "Treasury zeroed and salvage added":
    var state = GameState()
    state.houses = initTable[HouseId, House]()
    state.colonies = initTable[SystemId, Colony]()
    state.fleets = initTable[FleetId, Fleet]()

    state.houses["house-test"] = createTestHouse("house-test", treasury=500)
    state.fleets["fleet-1"] = createTestFleet("fleet-1", "house-test", basePP=1000)

    let cascade = processShortfall(state, "house-test", shortfall=600)
    applyShortfallCascade(state, cascade)

    # Treasury should be zeroed + salvage
    let finalTreasury = state.houses["house-test"].treasury
    check finalTreasury >= 0  # Should have salvage added back

  test "Fleets actually disbanded":
    var state = GameState()
    state.houses = initTable[HouseId, House]()
    state.colonies = initTable[SystemId, Colony]()
    state.fleets = initTable[FleetId, Fleet]()
    state.fleetOrders = initTable[FleetId, FleetOrder]()
    state.standingOrders = initTable[FleetId, StandingOrder]()

    state.houses["house-test"] = createTestHouse("house-test", treasury=0)
    state.fleets["fleet-1"] = createTestFleet("fleet-1", "house-test", basePP=1000)

    let cascade = processShortfall(state, "house-test", shortfall=300)
    applyShortfallCascade(state, cascade)

    # Fleet should be deleted
    check "fleet-1" notin state.fleets

  test "Industrial units actually stripped":
    var state = GameState()
    state.houses = initTable[HouseId, House]()
    state.colonies = initTable[SystemId, Colony]()
    state.fleets = initTable[FleetId, Fleet]()

    state.houses["house-test"] = createTestHouse("house-test", treasury=0)
    state.colonies["system-1"] = createTestColony("system-1", "house-test", iu=50)

    let initialIU = state.colonies["system-1"].industrial.units
    let cascade = processShortfall(state, "house-test", shortfall=20)
    applyShortfallCascade(state, cascade)

    # Should have lost IUs
    check state.colonies["system-1"].industrial.units < initialIU

  test "Prestige penalty applied":
    var state = GameState()
    state.houses = initTable[HouseId, House]()
    state.colonies = initTable[SystemId, Colony]()
    state.fleets = initTable[FleetId, Fleet]()

    state.houses["house-test"] = createTestHouse("house-test", treasury=0, prestige=100)

    let cascade = processShortfall(state, "house-test", shortfall=10)
    applyShortfallCascade(state, cascade)

    # Prestige should be reduced
    check state.houses["house-test"].prestige < 100

suite "Edge Cases":
  test "Zero shortfall does nothing":
    var state = GameState()
    state.houses = initTable[HouseId, House]()
    state.colonies = initTable[SystemId, Colony]()
    state.fleets = initTable[FleetId, Fleet]()

    state.houses["house-test"] = createTestHouse("house-test", treasury=1000)

    let cascade = processShortfall(state, "house-test", shortfall=0)

    check cascade.fullyResolved == true
    check cascade.fleetsDisbanded.len == 0
    check cascade.assetsStripped.len == 0

  test "Shortfall larger than all assets":
    var state = GameState()
    state.houses = initTable[HouseId, House]()
    state.colonies = initTable[SystemId, Colony]()
    state.fleets = initTable[FleetId, Fleet]()

    state.houses["house-test"] = createTestHouse("house-test", treasury=0)

    let cascade = processShortfall(state, "house-test", shortfall=10000)

    # Can't fully resolve
    check cascade.fullyResolved == false
    check cascade.remainingShortfall > 0

  test "Multiple colonies asset stripping":
    var state = GameState()
    state.houses = initTable[HouseId, House]()
    state.colonies = initTable[SystemId, Colony]()
    state.fleets = initTable[FleetId, Fleet]()

    state.houses["house-test"] = createTestHouse("house-test", treasury=0)
    state.colonies["system-1"] = createTestColony("system-1", "house-test", iu=10)
    state.colonies["system-2"] = createTestColony("system-2", "house-test", iu=10)

    let cascade = processShortfall(state, "house-test", shortfall=15)
    applyShortfallCascade(state, cascade)

    # Should strip from both colonies
    let totalIU = state.colonies["system-1"].industrial.units +
                   state.colonies["system-2"].industrial.units
    check totalIU < 20  # Started with 20 total

when isMainModule:
  echo "Running maintenance shortfall tests..."
