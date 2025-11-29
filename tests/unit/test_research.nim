## Unit Tests for Research System
##
## Tests R&D calculations per economy.md:4.0

import std/[unittest, math, options, tables, random]
import ../../src/engine/research/[types, costs, advancement]
import ../../src/common/types/tech

suite "Research Point Costs (economy.md:4.2)":
  test "ERP cost scales with GHO":
    # Small economy (GHO=100)
    let cost100 = calculateERPCost(100)
    # GHO=100: 5 + log10(100) = 5 + 2 = 7 PP per ERP
    check abs(cost100 - 7.0) < 0.01

    # Large economy (GHO=10000)
    let cost10k = calculateERPCost(10000)
    # GHO=10000: 5 + log10(10000) = 5 + 4 = 9 PP per ERP
    check abs(cost10k - 9.0) < 0.01

  test "PP to ERP conversion":
    # 70 PP with GHO=100 (7 PP/ERP) = 10 ERP
    let erp = convertPPToERP(70, 100)
    check erp == 10

  test "EL upgrade costs":
    # EL1: 40 + 1*10 = 50 ERP
    check getELUpgradeCost(1) == 50

    # EL5: 40 + 5*10 = 90 ERP
    check getELUpgradeCost(5) == 90

    # EL6: 90 + 15 = 105 ERP (higher tier)
    check getELUpgradeCost(6) == 105

    # EL10: 90 + 5*15 = 165 ERP
    check getELUpgradeCost(10) == 165

  test "EL modifier":
    # EL1: 1.0 + 0.05 = 1.05
    let el1 = getELModifier(1)
    check abs(el1 - 1.05) < 0.01

    # EL5: 1.0 + 0.25 = 1.25
    let el5 = getELModifier(5)
    check abs(el5 - 1.25) < 0.01

    # EL10: 1.0 + 0.50 = 1.50 (max)
    let el10 = getELModifier(10)
    check abs(el10 - 1.50) < 0.01

    # EL12 should cap at 1.50
    let el12 = getELModifier(12)
    check abs(el12 - 1.50) < 0.01

suite "Tech Advancement (economy.md:4.1)":
  test "Upgrade turns are first and seventh month":
    # Turn 1 = month 1
    check isUpgradeTurn(1) == true

    # Turn 7 = month 7
    check isUpgradeTurn(7) == true

    # Turn 5 = month 5 (not upgrade turn)
    check isUpgradeTurn(5) == false

    # Turn 14 = month 1 of year 2
    check isUpgradeTurn(14) == true

  test "EL advancement requires enough ERP":
    var tree = initTechTree(TechLevel(
      economicLevel: 1,
      scienceLevel: 1,
      constructionTech: 1,
      weaponsTech: 1,
      terraformingTech: 1,
      electronicIntelligence: 1,
      cloakingTech: 1,
      shieldTech: 1,
      counterIntelligence: 1,
      fighterDoctrine: 1,
      advancedCarrierOps: 1
    ))

    # Not enough ERP (need 50 for EL1->EL2)
    tree.accumulated.economic = 49
    let noAdvance = attemptELAdvancement(tree, 1)
    check noAdvance.isNone

    # Enough ERP
    tree.accumulated.economic = 50
    let advance = attemptELAdvancement(tree, 1)
    check advance.isSome
    check advance.get().advancementType == AdvancementType.EconomicLevel
    check advance.get().elToLevel == 2

  test "Tech advancement requires enough TRP":
    var tree = initTechTree(TechLevel(
      economicLevel: 1,
      scienceLevel: 1,
      constructionTech: 1,
      weaponsTech: 1,
      terraformingTech: 1,
      electronicIntelligence: 1,
      cloakingTech: 1,
      shieldTech: 1,
      counterIntelligence: 1,
      fighterDoctrine: 1,
      advancedCarrierOps: 1
    ))

    # Add some TRP for WEP
    tree.accumulated.technology[TechField.WeaponsTech] = 100

    # Try to advance (cost = 50 + 1*1*10 = 60)
    let advance = attemptTechAdvancement(tree, TechField.WeaponsTech)
    check advance.isSome
    check tree.levels.weaponsTech == 2

suite "Research Breakthroughs (economy.md:4.1.1)":
  test "Breakthrough base chance is 10%":
    var rng = initRand(12345)
    var successes = 0

    # Run 100 trials with 0 RP invested
    for i in 0..<100:
      let result = rollBreakthrough(0, rng)
      if result.isSome:
        successes += 1

    # Should be around 10 successes (10%)
    # Allow 3-17 range for randomness
    check successes >= 3 and successes <= 17

  test "Investment bonus increases breakthrough chance":
    var rng1 = initRand(12345)
    var rng2 = initRand(12345)  # Same seed for comparison

    # 0 RP invested
    var successes0 = 0
    for i in 0..<100:
      if rollBreakthrough(0, rng1).isSome:
        successes0 += 1

    # 300 RP invested = 6% bonus (10% base + 6% = 16% total)
    var successes300 = 0
    for i in 0..<100:
      if rollBreakthrough(300, rng2).isSome:
        successes300 += 1

    # Higher investment should have more breakthroughs
    # (Note: Same seed means same random sequence, so this is deterministic)
    check successes300 >= successes0

suite "Research Allocation":
  test "Allocate PP to multiple categories":
    let allocation = ResearchAllocation(
      economic: 100,
      science: 50,
      technology: {TechField.WeaponsTech: 75}.toTable
    )

    let rp = allocateResearch(
      allocation = allocation,
      gho = 1000,
      slLevel = 1
    )

    # Should have some RP in each category
    check rp.economic > 0
    check rp.science > 0
    check TechField.WeaponsTech in rp.technology

  test "Total RP invested calculation":
    let allocation = ResearchAllocation(
      economic: 100,
      science: 50,
      technology: {TechField.WeaponsTech: 75, TechField.ConstructionTech: 25}.toTable
    )

    let total = calculateTotalRPInvested(allocation)
    check total == 250  # 100 + 50 + 75 + 25
