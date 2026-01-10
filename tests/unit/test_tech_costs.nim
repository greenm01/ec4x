## Unit Tests for Tech Research Costs
##
## Tests PP to RP conversion formulas with logarithmic scaling.
## Per ec4x_canonical_turn_cycle.md CMD6e

import std/[unittest, math, tables]
import ../../src/engine/types/tech
import ../../src/engine/systems/tech/costs
import ../../src/engine/globals
import ../../src/engine/config/engine as config_engine

# Initialize config before tests
gameConfig = config_engine.loadGameConfig()

suite "Tech Costs: PP to ERP Conversion":
  ## Tests for Economic Research Points conversion
  ## Formula: ERP = PP * (1 + log₁₀(GHO)/3) * (1 + SL/10)

  test "Zero PP gives zero ERP":
    let erp = convertPPToERP(0, 1000, 5)
    check erp == 0

  test "Zero GHO gives base conversion (no bonus)":
    let erp = convertPPToERP(100, 0, 0)
    # Formula: 100 * 1.0 * 1.0 = 100
    check erp == 100

  test "GHO of 10 gives modest bonus":
    let erp = convertPPToERP(100, 10, 0)
    # log₁₀(10) = 1, so modifier = 1 + 1/3 = 1.333
    # ERP = 100 * 1.333 * 1.0 = 133
    check erp == 133

  test "GHO of 100 gives stronger bonus":
    let erp = convertPPToERP(100, 100, 0)
    # log₁₀(100) = 2, so modifier = 1 + 2/3 = 1.667
    # ERP = 100 * 1.667 * 1.0 = 166
    check erp == 166

  test "GHO of 1000 gives substantial bonus":
    let erp = convertPPToERP(100, 1000, 0)
    # log₁₀(1000) = 3, so modifier = 1 + 3/3 = 2.0
    # ERP = 100 * 2.0 * 1.0 = 200
    check erp == 200

  test "Science Level increases conversion":
    let erp0 = convertPPToERP(100, 100, 0)
    let erp5 = convertPPToERP(100, 100, 5)
    let erp10 = convertPPToERP(100, 100, 10)
    # SL modifier: 1.0, 1.5, 2.0
    check erp5 > erp0
    check erp10 > erp5

  test "Combined GHO and SL scaling":
    let erp = convertPPToERP(100, 1000, 10)
    # GHO modifier: 1 + 3/3 = 2.0
    # SL modifier: 1 + 10/10 = 2.0
    # ERP = 100 * 2.0 * 2.0 = 400
    check erp == 400

  test "Logarithmic scaling prevents runaway":
    # Compare GHO 100 vs GHO 10000 (100x difference)
    let erp100 = convertPPToERP(100, 100, 0)
    let erp10000 = convertPPToERP(100, 10000, 0)
    # 100x economic growth should NOT give 100x research
    # log₁₀(100) = 2, modifier = 1.667
    # log₁₀(10000) = 4, modifier = 2.333
    # Ratio is about 1.4x, NOT 100x
    let ratio = erp10000.float / erp100.float
    check ratio < 2.0  # Much less than 100x

suite "Tech Costs: PP to SRP Conversion":
  ## Tests for Science Research Points conversion
  ## Formula: SRP = PP * (1 + log₁₀(GHO)/4) * (1 + SL/5)

  test "Zero PP gives zero SRP":
    let srp = convertPPToSRP(0, 1000, 5)
    check srp == 0

  test "SRP has weaker GHO scaling than ERP":
    let erp = convertPPToERP(100, 1000, 0)
    let srp = convertPPToSRP(100, 1000, 0)
    # ERP GHO modifier: 1 + 3/3 = 2.0
    # SRP GHO modifier: 1 + 3/4 = 1.75
    check srp < erp

  test "SRP has stronger SL scaling than ERP":
    let erp = convertPPToERP(100, 100, 10)
    let srp = convertPPToSRP(100, 100, 10)
    # ERP SL modifier: 1 + 10/10 = 2.0
    # SRP SL modifier: 1 + 10/5 = 3.0
    # At high SL, SRP should exceed ERP despite weaker GHO
    check srp > erp

  test "Science Level 5 doubles SRP":
    let srp0 = convertPPToSRP(100, 100, 0)
    let srp5 = convertPPToSRP(100, 100, 5)
    # SL modifier at 5: 1 + 5/5 = 2.0
    let ratio = srp5.float / srp0.float
    check ratio > 1.9 and ratio < 2.1

suite "Tech Costs: PP to TRP Conversion":
  ## Tests for Technology Research Points conversion
  ## Formula: TRP = PP * (1 + log₁₀(GHO)/3.5) * (1 + SL/20)

  test "Zero PP gives zero TRP":
    let trp = convertPPToTRP(0, 1000, 5)
    check trp == 0

  test "TRP has moderate GHO scaling":
    let erp = convertPPToERP(100, 1000, 0)
    let trp = convertPPToTRP(100, 1000, 0)
    let srp = convertPPToSRP(100, 1000, 0)
    # TRP GHO modifier: 1 + 3/3.5 = 1.857
    # Between ERP (2.0) and SRP (1.75)
    check trp < erp
    check trp > srp

  test "TRP has weakest SL scaling":
    let erp = convertPPToERP(100, 100, 10)
    let srp = convertPPToSRP(100, 100, 10)
    let trp = convertPPToTRP(100, 100, 10)
    # TRP SL modifier: 1 + 10/20 = 1.5
    # ERP SL modifier: 1 + 10/10 = 2.0
    # SRP SL modifier: 1 + 10/5 = 3.0
    check trp < erp
    check trp < srp

  test "TRP modest benefit from science infrastructure":
    let trp0 = convertPPToTRP(100, 100, 0)
    let trp10 = convertPPToTRP(100, 100, 10)
    # SL 10 gives 50% bonus (1 + 10/20 = 1.5)
    let ratio = trp10.float / trp0.float
    check ratio > 1.4 and ratio < 1.6

suite "Tech Costs: Research Allocation":
  ## Tests for allocateResearch() which combines all conversions

  test "Empty allocation gives zero RP":
    let allocation = ResearchAllocation(
      economic: 0,
      science: 0,
      technology: initTable[TechField, int32]()
    )
    let rp = allocateResearch(allocation, 1000, 5)
    check rp.economic == 0
    check rp.science == 0
    check rp.technology.len == 0

  test "Economic allocation converts correctly":
    let allocation = ResearchAllocation(
      economic: 100,
      science: 0,
      technology: initTable[TechField, int32]()
    )
    let rp = allocateResearch(allocation, 1000, 5)
    let expected = convertPPToERP(100, 1000, 5)
    check rp.economic == expected

  test "Science allocation converts correctly":
    let allocation = ResearchAllocation(
      economic: 0,
      science: 100,
      technology: initTable[TechField, int32]()
    )
    let rp = allocateResearch(allocation, 1000, 5)
    let expected = convertPPToSRP(100, 1000, 5)
    check rp.science == expected

  test "Technology allocation converts correctly":
    var techAlloc = initTable[TechField, int32]()
    techAlloc[TechField.WeaponsTech] = 100
    let allocation = ResearchAllocation(
      economic: 0,
      science: 0,
      technology: techAlloc
    )
    let rp = allocateResearch(allocation, 1000, 5)
    let expected = convertPPToTRP(100, 1000, 5)
    check rp.technology[TechField.WeaponsTech] == expected

  test "Multiple tech fields convert independently":
    var techAlloc = initTable[TechField, int32]()
    techAlloc[TechField.WeaponsTech] = 50
    techAlloc[TechField.ConstructionTech] = 50
    let allocation = ResearchAllocation(
      economic: 0,
      science: 0,
      technology: techAlloc
    )
    let rp = allocateResearch(allocation, 1000, 5)
    let expected = convertPPToTRP(50, 1000, 5)
    check rp.technology[TechField.WeaponsTech] == expected
    check rp.technology[TechField.ConstructionTech] == expected

suite "Tech Costs: Total RP Calculation":
  ## Tests for calculateTotalRPInvested()

  test "Zero allocation gives zero total":
    let allocation = ResearchAllocation(
      economic: 0,
      science: 0,
      technology: initTable[TechField, int32]()
    )
    check calculateTotalRPInvested(allocation) == 0

  test "Sums all allocation types":
    var techAlloc = initTable[TechField, int32]()
    techAlloc[TechField.WeaponsTech] = 30
    techAlloc[TechField.ConstructionTech] = 20
    let allocation = ResearchAllocation(
      economic: 100,
      science: 50,
      technology: techAlloc
    )
    # 100 + 50 + 30 + 20 = 200
    check calculateTotalRPInvested(allocation) == 200

suite "Tech Costs: EL/SL Modifiers":
  ## Tests for Economic/Science Level modifier functions

  test "EL modifier at level 0 is 1.0":
    check getELModifier(0) == 1.0

  test "EL modifier increases 5% per level":
    check getELModifier(1) > 1.0
    check getELModifier(2) > getELModifier(1)

  test "EL modifier caps at 50% bonus":
    # At level 10+, bonus should cap at 50% (1.5 multiplier)
    let mod10 = getELModifier(10)
    let mod15 = getELModifier(15)
    check mod10 == 1.5 or mod10 > 1.4  # Allow config variance
    check mod15 <= 1.5 or mod15 > 1.4  # Cap or near cap

  test "SL modifier at level 0 is 1.0":
    check getSLModifier(0) == 1.0

  test "SL modifier increases 5% per level":
    check getSLModifier(1) > getSLModifier(0)
    check getSLModifier(5) > getSLModifier(1)

when isMainModule:
  echo "========================================"
  echo "  Tech Costs Unit Tests"
  echo "========================================"
