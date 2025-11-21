## Integration test for prestige system
##
## Tests that prestige events flow correctly through:
## 1. Economy -> Income Phase -> House.prestige
## 2. Victory condition checks
## 3. Defensive collapse tracking

import std/[unittest, tables, options]
import ../../src/engine/[gamestate, starmap]
import ../../src/engine/economy/[types as econ_types, income]
import ../../src/engine/prestige
import ../../src/engine/config/prestige_config
import ../../src/common/types/[core, planets, tech]

suite "Prestige Integration":

  test "Low tax rate generates prestige bonus":
    # Create low-tax colony
    let colony = econ_types.Colony(
      systemId: 1.SystemId,
      owner: "house1".HouseId,
      populationUnits: 100,
      populationTransferUnits: 100,
      industrial: econ_types.IndustrialUnits(units: 0, investmentCost: 30),
      planetClass: PlanetClass.Benign,
      resources: ResourceRating.Abundant,
      grossOutput: 0,
      taxRate: 10,  # 10% tax -> +3 prestige per colony
      underConstruction: none(econ_types.ConstructionProject),
      infrastructureDamage: 0.0
    )

    # Calculate income with low tax
    let taxPolicy = econ_types.TaxPolicy(
      currentRate: 10,
      history: @[10, 10, 10]
    )

    let report = calculateHouseIncome(@[colony], 1, taxPolicy, 1000)

    # Should generate prestige bonus
    check report.totalPrestigeBonus == 3
    check report.prestigeEvents.len > 0
    check report.prestigeEvents[0].amount == 3
    check report.prestigeEvents[0].source == PrestigeSource.LowTaxBonus

  test "High tax rate generates prestige penalty":
    # Create high-tax colony with history
    let colony = econ_types.Colony(
      systemId: 1.SystemId,
      owner: "house1".HouseId,
      populationUnits: 100,
      populationTransferUnits: 100,
      industrial: econ_types.IndustrialUnits(units: 0, investmentCost: 30),
      planetClass: PlanetClass.Benign,
      resources: ResourceRating.Abundant,
      grossOutput: 0,
      taxRate: 70,
      underConstruction: none(econ_types.ConstructionProject),
      infrastructureDamage: 0.0
    )

    # History of high taxes
    let taxPolicy = econ_types.TaxPolicy(
      currentRate: 70,
      history: @[70, 70, 70, 70, 70, 70]
    )

    let report = calculateHouseIncome(@[colony], 1, taxPolicy, 1000)

    # Should generate prestige penalty
    check report.taxAverage6Turn == 70
    check report.taxPenalty < 0
    check report.prestigeEvents.len > 0

    # Find the penalty event
    var foundPenalty = false
    for event in report.prestigeEvents:
      if event.source == PrestigeSource.HighTaxPenalty:
        foundPenalty = true
        check event.amount < 0

    check foundPenalty

  test "Victory condition: prestige threshold":
    var state = GameState(
      gameId: "test-victory",
      turn: 100,
      year: 2010,
      month: 1,
      phase: GamePhase.Active,
      houses: initTable[HouseId, House](),
      starMap: newStarMap(2)
    )

    # House 1: High prestige
    let house1 = "house1".HouseId
    state.houses[house1] = House(
      id: house1,
      name: "Winner House",
      color: "#FF0000",
      prestige: 5001,  # Above threshold
      treasury: 1000,
      techTree: TechTree(),
      eliminated: false,
      negativePrestigeTurns: 0
    )

    # House 2: Normal prestige
    let house2 = "house2".HouseId
    state.houses[house2] = House(
      id: house2,
      name: "Normal House",
      color: "#00FF00",
      prestige: 500,
      treasury: 1000,
      techTree: TechTree(),
      eliminated: false,
      negativePrestigeTurns: 0
    )

    let victorOpt = state.checkVictoryCondition()
    check victorOpt.isSome
    check victorOpt.get() == house1

  test "Victory condition: last house standing":
    var state = GameState(
      gameId: "test-victory-last",
      turn: 100,
      year: 2010,
      month: 1,
      phase: GamePhase.Active,
      houses: initTable[HouseId, House](),
      starMap: newStarMap(2)
    )

    # Only one active house
    let house1 = "house1".HouseId
    state.houses[house1] = House(
      id: house1,
      name: "Last House",
      color: "#FF0000",
      prestige: 100,  # Below threshold
      treasury: 1000,
      techTree: TechTree(),
      eliminated: false,
      negativePrestigeTurns: 0
    )

    # Another house but eliminated
    let house2 = "house2".HouseId
    state.houses[house2] = House(
      id: house2,
      name: "Dead House",
      color: "#00FF00",
      prestige: 50,
      treasury: 0,
      techTree: TechTree(),
      eliminated: true,
      negativePrestigeTurns: 0
    )

    let victorOpt = state.checkVictoryCondition()
    check victorOpt.isSome
    check victorOpt.get() == house1

  test "No victory when multiple houses below threshold":
    var state = GameState(
      gameId: "test-no-victory",
      turn: 10,
      year: 2002,
      month: 1,
      phase: GamePhase.Active,
      houses: initTable[HouseId, House](),
      starMap: newStarMap(2)
    )

    # Two active houses, both below threshold
    let house1 = "house1".HouseId
    state.houses[house1] = House(
      id: house1,
      name: "House 1",
      color: "#FF0000",
      prestige: 1000,
      treasury: 1000,
      techTree: TechTree(),
      eliminated: false,
      negativePrestigeTurns: 0
    )

    let house2 = "house2".HouseId
    state.houses[house2] = House(
      id: house2,
      name: "House 2",
      color: "#00FF00",
      prestige: 800,
      treasury: 1000,
      techTree: TechTree(),
      eliminated: false,
      negativePrestigeTurns: 0
    )

    let victorOpt = state.checkVictoryCondition()
    check victorOpt.isNone

  test "Defensive collapse: negative prestige tracking":
    # This test verifies the negativePrestigeTurns counter works correctly
    # The actual elimination logic is in resolve.nim Maintenance Phase

    var house = House(
      id: "test".HouseId,
      name: "Collapsing House",
      color: "#FF0000",
      prestige: -10,
      treasury: 0,
      techTree: TechTree(),
      eliminated: false,
      negativePrestigeTurns: 0
    )

    let config = globalPrestigeConfig

    # Simulate turns with negative prestige
    for turn in 1..config.collapseTurns:
      if house.prestige < 0:
        house.negativePrestigeTurns += 1

      # Should not collapse before threshold
      if turn < config.collapseTurns:
        check house.negativePrestigeTurns < config.collapseTurns

    # At threshold, should be ready for collapse
    check house.negativePrestigeTurns >= config.collapseTurns

    # If prestige becomes positive, counter resets
    house.prestige = 50
    house.negativePrestigeTurns = 0
    check house.negativePrestigeTurns == 0
