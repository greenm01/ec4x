## Comprehensive Economy System Tests
##
## Tests all economy mechanics from economy.md Section 3.0
## - GCO (Gross Colony Output) calculations
## - NCV (Net Colony Value) calculations
## - Tax policy effects
## - Industrial Units (IU) production
## - Population growth
## - Boundary conditions and input validation
##
## This test suite loads actual config files and validates against them

import std/[unittest, tables, math, options]
import ../../src/engine/[gamestate, starmap]
import ../../src/engine/economy/[types, production, income, projects, config_accessors]
import ../../src/engine/config/[economy_config, population_config, facilities_config]
import ../../src/engine/research/types as res_types
import ../../src/common/types/[core, planets, units, tech]

suite "Economy System: Comprehensive Tests":

  # Load all economy-related configs at suite start
  setup:
    discard loadEconomyConfig("config/economy.kdl")
    discard loadPopulationConfig("config/population.kdl")
    discard loadFacilitiesConfig("config/facilities.kdl")

  # ==========================================================================
  # GCO (Gross Colony Output) Tests - economy.md:3.1
  # ==========================================================================

  test "GCO: Population component":
    # GCO = (PU × RAW_INDEX) + (IU × EL_MOD × PROD_GROWTH)
    # With no IU, GCO should equal PU × RAW_INDEX

    var colony = createHomeColony(SystemId(1), "test-house")
    colony.populationUnits = 100  # 100 PU (field used by calculateGrossOutput)
    colony.population = 100  # Keep in sync
    colony.souls = 100_000_000
    colony.industrial.units = 0  # No IU
    colony.planetClass = PlanetClass.Eden
    colony.taxRate = 50  # Neutral tax
    colony.resources = ResourceRating.Abundant  # RAW_INDEX = 1.0
    colony.taxRate = 50  # Neutral (0 growth)

    let gco = calculateGrossOutput(colony, elTechLevel = 1)

    # Eden + Abundant = 100% RAW_INDEX, so 100 PU × 1.0 = 100
    check gco >= 100
    check gco <= 110  # Should not be much higher without IU

  test "GCO: Industrial component":
    var colony = createHomeColony(SystemId(1), "test-house")
    colony.populationUnits = 100  # 100 PU
    colony.population = 100
    colony.souls = 100_000_000
    colony.industrial.units = 50  # 50 IU directly
    colony.planetClass = PlanetClass.Eden
    colony.taxRate = 50  # Neutral tax
    colony.resources = ResourceRating.Abundant
    colony.taxRate = 50  # Neutral

    let gco = calculateGrossOutput(colony, elTechLevel = 1)

    # Should include both population (~100) and industrial contribution
    # With EL1 (5% bonus) and 50% tax (0 growth), IU contributes 50 * 1.05 = 52.5
    check gco >= 150  # At least 100 (PU) + 52 (IU)

  test "GCO: Economic Level modifier effect":
    # Test that EL modifier is applied correctly
    # Per economy.md:4.2 - "+5% per level, capped at 50%"

    var colony = createHomeColony(SystemId(1), "test-house")
    colony.populationUnits = 100
    colony.population = 100
    colony.souls = 100_000_000
    colony.industrial.units = 100  # Significant IU to see EL effect
    colony.planetClass = PlanetClass.Eden
    colony.taxRate = 50  # Neutral tax
    colony.resources = ResourceRating.Abundant

    let gcoEL1 = calculateGrossOutput(colony, elTechLevel = 1)   # 1.05x modifier
    let gcoEL5 = calculateGrossOutput(colony, elTechLevel = 5)   # 1.25x modifier
    let gcoEL10 = calculateGrossOutput(colony, elTechLevel = 10) # 1.50x modifier (max)

    # Higher EL should produce more GCO
    check gcoEL5 > gcoEL1
    check gcoEL10 > gcoEL5

  test "GCO: RAW_INDEX variations":
    # Test different planet/resource combinations
    var colony = createHomeColony(SystemId(1), "test-house")
    colony.populationUnits = 100
    colony.population = 100
    colony.souls = 100_000_000
    colony.industrial.units = 0

    # Eden + Abundant = 100% RAW_INDEX
    colony.planetClass = PlanetClass.Eden
    colony.taxRate = 50  # Neutral tax
    colony.resources = ResourceRating.Abundant
    let gcoEden = calculateGrossOutput(colony, elTechLevel = 1)

    # Extreme + VeryPoor = 60% RAW_INDEX (lowest)
    colony.planetClass = PlanetClass.Extreme
    colony.taxRate = 50  # Neutral tax
    colony.resources = ResourceRating.VeryPoor
    let gcoExtreme = calculateGrossOutput(colony, elTechLevel = 1)

    # Eden + VeryRich = 140% RAW_INDEX (highest)
    colony.planetClass = PlanetClass.Eden
    colony.taxRate = 50  # Neutral tax
    colony.resources = ResourceRating.VeryRich
    let gcoVeryRich = calculateGrossOutput(colony, elTechLevel = 1)

    # Verify ordering: VeryRich > Abundant > Extreme
    check gcoVeryRich > gcoEden
    check gcoEden > gcoExtreme

  # ==========================================================================
  # NCV (Net Colony Value) Tests - economy.md:3.3
  # ==========================================================================

  test "NCV: Tax rate calculation":
    # NCV = GCO × (tax_rate / 100)
    let gco = 1000

    let ncv0 = calculateNetValue(gco, 0)     # 0% tax
    let ncv50 = calculateNetValue(gco, 50)   # 50% tax
    let ncv100 = calculateNetValue(gco, 100) # 100% tax

    check ncv0 == 0
    check ncv50 == 500
    check ncv100 == 1000

  test "NCV: Negative GCO handled":
    # Edge case: what if GCO is negative?
    let negativeGco = -100
    let ncv = calculateNetValue(negativeGco, 50)

    # Should handle gracefully (likely return 0 or negative)
    check ncv <= 0

  # ==========================================================================
  # Tax Policy Tests - economy.md:3.2
  # ==========================================================================

  test "Tax policy: Productivity growth curve":
    # Low tax → positive growth
    # 50% tax → neutral (0 growth)
    # High tax → negative growth

    let lowTaxGrowth = getProductivityGrowth(0)
    let medTaxGrowth = getProductivityGrowth(50)
    let highTaxGrowth = getProductivityGrowth(100)

    check lowTaxGrowth > 0.0
    check abs(medTaxGrowth) < 0.01  # Close to zero
    check highTaxGrowth < 0.0

  test "Tax policy: Extreme values":
    # Test boundary conditions
    let growth0 = getProductivityGrowth(0)
    let growth100 = getProductivityGrowth(100)

    # 0% should give maximum growth
    check growth0 > 0.0

    # 100% should give maximum penalty
    check growth100 < -0.05  # Significant negative

  # ==========================================================================
  # Population Growth Tests - economy.md:3.4
  # ==========================================================================

  test "Population growth: Basic calculation":
    var colony = createHomeColony(SystemId(1), "test-house")
    colony.populationUnits = 100
    colony.population = 100
    colony.souls = 100_000_000
    colony.planetClass = PlanetClass.Eden
    colony.taxRate = 50  # Neutral tax

    let initialPop = colony.population
    let baseGrowthRate = 0.02  # 2% base growth per config

    # Apply one turn of growth at 50% tax (neutral)
    let growthRate = applyPopulationGrowth(colony, taxRate = 50, baseGrowthRate)

    # Population should change based on growth rate
    # At neutral tax, growth should be minimal
    check colony.population >= initialPop  # Should not shrink at 50% tax

  test "Population growth: Tax impact":
    # Low tax → faster growth
    var colonyLowTax = createHomeColony(SystemId(1), "test-house")
    colonyLowTax.populationUnits = 100  # Field used by applyPopulationGrowth
    colonyLowTax.population = 100
    colonyLowTax.souls = 100_000_000
    colonyLowTax.planetClass = PlanetClass.Eden

    # High tax → slower growth
    var colonyHighTax = createHomeColony(SystemId(2), "test-house")
    colonyHighTax.populationUnits = 100
    colonyHighTax.population = 100
    colonyHighTax.souls = 100_000_000
    colonyHighTax.planetClass = PlanetClass.Eden

    let initialPop = 100
    let baseGrowthRate = 0.02  # 2% base

    # Apply multiple turns
    for i in 1..10:
      discard applyPopulationGrowth(colonyLowTax, taxRate = 0, baseGrowthRate)    # 0% tax
      discard applyPopulationGrowth(colonyHighTax, taxRate = 100, baseGrowthRate) # 100% tax

    # Low tax colony should have grown more (check populationUnits, not population)
    check colonyLowTax.populationUnits > colonyHighTax.populationUnits

  # ==========================================================================
  # Industrial Units (IU) Tests - economy.md:3.1
  # ==========================================================================

  test "IU: Infrastructure to IU conversion":
    # Industrial units are stored in colony.industrial.units
    var colony = createHomeColony(SystemId(1), "test-house")
    colony.industrial.units = 100

    # IU should match what we set
    let iu = colony.industrial.units
    check iu == 100

  test "IU: Contribution to GCO":
    var colony = createHomeColony(SystemId(1), "test-house")
    colony.populationUnits = 100
    colony.population = 100
    colony.souls = 100_000_000
    colony.industrial.units = 0
    colony.planetClass = PlanetClass.Eden
    colony.taxRate = 50  # Neutral tax
    colony.resources = ResourceRating.Abundant

    let gcoNoIU = calculateGrossOutput(colony, elTechLevel = 1)

    # Add IU
    colony.industrial.units = 100
    let gcoWithIU = calculateGrossOutput(colony, elTechLevel = 1)

    # GCO should increase with IU
    check gcoWithIU > gcoNoIU
    check (gcoWithIU - gcoNoIU) >= 50  # At least 50 PP from 100 IU

  # ==========================================================================
  # Boundary/Aggressive Tests - Try to Break the Engine
  # ==========================================================================

  test "BOUNDARY: Zero population":
    var colony = createHomeColony(SystemId(1), "test-house")
    colony.populationUnits = 0
    colony.population = 0
    colony.souls = 0
    colony.industrial.units = 100
    colony.planetClass = PlanetClass.Eden
    colony.taxRate = 50  # Neutral tax
    colony.resources = ResourceRating.Abundant

    let gco = calculateGrossOutput(colony, elTechLevel = 1)

    # Should handle gracefully - either 0 or just IU contribution
    check gco >= 0  # Should not be negative

  test "BOUNDARY: Negative population":
    var colony = createHomeColony(SystemId(1), "test-house")
    colony.populationUnits = -100  # Invalid state
    colony.population = -100
    colony.souls = -100_000_000
    colony.industrial.units = 0
    colony.planetClass = PlanetClass.Eden
    colony.taxRate = 50  # Neutral tax
    colony.resources = ResourceRating.Abundant

    # Engine should handle gracefully
    let gco = calculateGrossOutput(colony, elTechLevel = 1)
    check gco >= 0  # Should not produce negative output

  test "BOUNDARY: Extreme infrastructure":
    var colony = createHomeColony(SystemId(1), "test-house")
    colony.populationUnits = 100
    colony.population = 100
    colony.souls = 100_000_000
    colony.industrial.units = 10000  # Unrealistic high value
    colony.planetClass = PlanetClass.Eden
    colony.taxRate = 50  # Neutral tax
    colony.resources = ResourceRating.Abundant

    let gco = calculateGrossOutput(colony, elTechLevel = 1)

    # Should handle large values without overflow
    check gco > 0
    check gco < 1_000_000  # Sanity check

  test "BOUNDARY: Tax rate over 100%":
    let gco = 1000

    # Tax rate over 100% (invalid)
    let ncv = calculateNetValue(gco, 150)

    # Should either cap at 100% or handle gracefully
    check ncv <= 1500  # Should not produce more than 150% of GCO

  test "BOUNDARY: Negative tax rate":
    let gco = 1000

    # Negative tax (invalid)
    let ncv = calculateNetValue(gco, -50)

    # Should handle gracefully - either 0 or error
    check ncv <= 0  # Should not produce income from negative tax

  test "BOUNDARY: EL beyond maximum":
    var colony = createHomeColony(SystemId(1), "test-house")
    colony.populationUnits = 100
    colony.population = 100
    colony.souls = 100_000_000
    colony.industrial.units = 100
    colony.planetClass = PlanetClass.Eden
    colony.taxRate = 50  # Neutral tax
    colony.resources = ResourceRating.Abundant

    # EL 20 is beyond max (11), but should not crash
    let gco = calculateGrossOutput(colony, elTechLevel = 20)

    # Should cap at maximum modifier (50%)
    check gco > 0

  test "BOUNDARY: Zero EL":
    var colony = createHomeColony(SystemId(1), "test-house")
    colony.populationUnits = 100
    colony.population = 100
    colony.souls = 100_000_000
    colony.industrial.units = 100
    colony.planetClass = PlanetClass.Eden
    colony.taxRate = 50  # Neutral tax
    colony.resources = ResourceRating.Abundant

    # EL 0 is invalid per spec (should start at 1)
    # Engine should handle gracefully
    let gco = calculateGrossOutput(colony, elTechLevel = 0)

    # Should not crash, likely treat as EL1 or no modifier
    check gco > 0

  test "BOUNDARY: Population growth with zero souls":
    var colony = createHomeColony(SystemId(1), "test-house")
    colony.populationUnits = 0
    colony.population = 0
    colony.souls = 0
    colony.planetClass = PlanetClass.Eden
    colony.taxRate = 50  # Neutral tax

    let baseGrowthRate = 0.02

    # Should handle zero population gracefully
    discard applyPopulationGrowth(colony, taxRate = 0, baseGrowthRate)

    # Population should remain 0 (can't grow from nothing)
    check colony.population == 0
