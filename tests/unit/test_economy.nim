## Unit Tests for Economy System
##
## Tests core economic calculations per economy.md

import std/[unittest, math, options]
import ../../src/engine/economy/[types, production, income, construction]
import ../../src/common/types/[planets, units]

suite "GCO Calculation (economy.md:3.1)":
  test "RAW INDEX table lookup":
    # Eden planet with Abundant resources should be 100%
    check getRawIndex(PlanetClass.Eden, ResourceRating.Abundant) == 1.0

    # Extreme planet with Very Poor resources should be 60%
    check getRawIndex(PlanetClass.Extreme, ResourceRating.VeryPoor) == 0.60

    # Rich resources on Lush planet should be 105%
    check getRawIndex(PlanetClass.Lush, ResourceRating.Rich) == 1.05

    # Very Rich on Eden should be 140%
    check getRawIndex(PlanetClass.Eden, ResourceRating.VeryRich) == 1.40

  test "Population production component":
    var colony = initColony(
      systemId = 1,
      owner = "house-test",
      planetClass = PlanetClass.Eden,
      resources = ResourceRating.Abundant,
      startingPU = 100
    )

    # Eden + Abundant = 100% RAW INDEX
    # 100 PU × 1.0 = 100 population production
    let gco = calculateGrossOutput(colony, elTechLevel = 1)

    # Should be at least 100 from population (no IU yet)
    check gco >= 100

  test "Industrial production component":
    var colony = initColony(
      systemId = 1,
      owner = "house-test",
      planetClass = PlanetClass.Eden,
      resources = ResourceRating.Abundant,
      startingPU = 100
    )

    # Add 50 IU
    colony.industrial.units = 50

    # With EL1 (modifier ~1.1) and default tax 50% (PROD_GROWTH = 0)
    # IU component = 50 × 1.1 × 1.0 = 55
    let gco = calculateGrossOutput(colony, elTechLevel = 1)

    # Should include both population (100) and industrial (~55)
    check gco >= 150

  test "Economic Level modifier effect":
    # EL1 should give 5% bonus (per economy.md:4.2 - "5% per level")
    let elMod1 = getEconomicLevelModifier(1)
    check elMod1 == 1.05

    # EL5 should give 25% bonus (5% × 5 levels = 25%)
    let elMod5 = getEconomicLevelModifier(5)
    check elMod5 == 1.25

    # EL10 should give 50% bonus (maximum per spec)
    let elMod10 = getEconomicLevelModifier(10)
    check elMod10 == 1.50

  test "Tax rate affects productivity growth":
    # High tax (100%) should give negative growth
    let highTaxGrowth = getProductivityGrowth(100)
    check highTaxGrowth < 0.0

    # Low tax (0%) should give positive growth
    let lowTaxGrowth = getProductivityGrowth(0)
    check lowTaxGrowth > 0.0

    # Medium tax (50%) should be neutral
    let medTaxGrowth = getProductivityGrowth(50)
    check abs(medTaxGrowth) < 0.01  # Close to zero

suite "Net Colony Value (economy.md:3.3)":
  test "NCV = GCO × tax rate":
    let gco = 1000

    # 50% tax
    let ncv50 = calculateNetValue(gco, 50)
    check ncv50 == 500

    # 100% tax
    let ncv100 = calculateNetValue(gco, 100)
    check ncv100 == 1000

    # 0% tax
    let ncv0 = calculateNetValue(gco, 0)
    check ncv0 == 0

suite "Tax Policy (economy.md:3.2)":
  test "High tax penalty thresholds":
    # ≤50% = no penalty
    check calculateTaxPenalty(50) == 0

    # 51-60% = -1
    check calculateTaxPenalty(55) == -1

    # 71-80% = -4
    check calculateTaxPenalty(75) == -4

    # 91-100% = -11
    check calculateTaxPenalty(95) == -11

  test "Low tax prestige bonus":
    # 41-50% = no bonus (4 colonies)
    check calculateTaxBonus(45, 4) == 0

    # 21-30% = +1 per colony
    check calculateTaxBonus(25, 4) == 4

    # 0-10% = +3 per colony
    check calculateTaxBonus(5, 4) == 12

  test "Population growth multipliers":
    # 41-50% = 1.0x
    check getPopulationGrowthMultiplier(45) == 1.0

    # 31-40% = 1.05x
    check getPopulationGrowthMultiplier(35) == 1.05

    # 21-30% = 1.10x
    check getPopulationGrowthMultiplier(25) == 1.10

    # 0-10% = 1.20x
    check getPopulationGrowthMultiplier(5) == 1.20

  test "Rolling 6-turn average":
    # Test with 3 turns
    let avg3 = calculateRollingTaxAverage(@[60, 70, 80])
    check avg3 == 70  # (60+70+80)/3

    # Test with 7 turns (only last 6 count)
    let avg7 = calculateRollingTaxAverage(@[50, 60, 70, 80, 90, 100, 50])
    # Should average last 6: (60+70+80+90+100+50)/6 = 75
    check avg7 == 75

suite "Industrial Units (economy.md:3.4)":
  test "IU cost scaling by percentage of PU":
    var colony = initColony(
      systemId = 1,
      owner = "house-test",
      planetClass = PlanetClass.Eden,
      resources = ResourceRating.Abundant,
      startingPU = 100
    )

    # 0 IU = up to 50% of PU = 1.0x multiplier = 30 PP
    colony.industrial.units = 0
    check getIndustrialUnitCost(colony) == 30

    # 51 IU = 51% of PU = 1.2x multiplier = 36 PP
    colony.industrial.units = 51
    let cost51 = getIndustrialUnitCost(colony)
    check cost51 == 36

    # 76 IU = 76% of PU = 1.5x multiplier = 45 PP
    colony.industrial.units = 76
    let cost76 = getIndustrialUnitCost(colony)
    check cost76 == 45

suite "Ship Construction Costs":
  test "Fighter costs less than Battleship":
    let fighterCost = getShipConstructionCost(ShipClass.Fighter)
    let battleshipCost = getShipConstructionCost(ShipClass.Battleship)

    check fighterCost < battleshipCost
    check fighterCost > 0
    check battleshipCost > 0

  test "Build time scales with cost":
    let scoutTime = getShipBuildTime(ShipClass.Scout, cstLevel = 1)
    let carrierTime = getShipBuildTime(ShipClass.Carrier, cstLevel = 1)

    check carrierTime >= scoutTime

suite "Construction Advancement":
  test "Project completes after required turns":
    var colony = initColony(
      systemId = 1,
      owner = "house-test",
      planetClass = PlanetClass.Eden,
      resources = ResourceRating.Abundant,
      startingPU = 100
    )

    # Start scout construction (fast ship - 1 turn)
    let project = createShipProject(ShipClass.Scout)
    check startConstruction(colony, project) == true

    # Advance one turn
    let completed = advanceConstruction(colony)

    # Should complete after 1 turn
    check completed.isSome
    check completed.get().projectType == ConstructionType.Ship
    check colony.underConstruction.isNone  # Slot cleared

  test "Project continues when not enough turns passed":
    var colony = initColony(
      systemId = 1,
      owner = "house-test",
      planetClass = PlanetClass.Eden,
      resources = ResourceRating.Abundant,
      startingPU = 100
    )

    # Start cruiser construction (2 turns at CST 1)
    let project = createShipProject(ShipClass.Cruiser)
    discard startConstruction(colony, project)

    # Advance only 1 turn
    let completed = advanceConstruction(colony)

    # Should NOT complete yet
    check completed.isNone
    check colony.underConstruction.isSome  # Still building

  test "Cannot start second project while building":
    var colony = initColony(
      systemId = 1,
      owner = "house-test",
      planetClass = PlanetClass.Eden,
      resources = ResourceRating.Abundant,
      startingPU = 100
    )

    # Start first project
    let project1 = createShipProject(ShipClass.Cruiser)
    check startConstruction(colony, project1) == true

    # Try to start second
    let project2 = createShipProject(ShipClass.Destroyer)
    check startConstruction(colony, project2) == false

suite "Population Growth":
  test "Population grows with base rate":
    var colony = initColony(
      systemId = 1,
      owner = "house-test",
      planetClass = PlanetClass.Eden,
      resources = ResourceRating.Abundant,
      startingPU = 100
    )

    let startPU = colony.populationUnits

    # Apply growth at 50% tax (1.0x multiplier)
    # Base growth = 1.5%
    discard applyPopulationGrowth(colony, 50)

    # Should have grown
    check colony.populationUnits > startPU

  test "Low tax increases growth rate":
    var colony1 = initColony(
      systemId = 1,
      owner = "house-test",
      planetClass = PlanetClass.Eden,
      resources = ResourceRating.Abundant,
      startingPU = 100
    )

    var colony2 = colony1  # Copy

    # High tax (50%)
    discard applyPopulationGrowth(colony1, 50)

    # Low tax (10%)
    discard applyPopulationGrowth(colony2, 10)

    # Low tax colony should have higher population
    check colony2.populationUnits >= colony1.populationUnits
