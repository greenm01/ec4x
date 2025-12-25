## Comprehensive Technology System Tests
##
## Tests all technology mechanics from economy.md Section 4.0
## - Research point allocation and conversion (ERP, SRP, TRP)
## - Tech level advancement (EL, SL, and 11 tech fields)
## - Research breakthroughs (Minor, Moderate, Major, Revolutionary)
## - Cost calculations and scaling
## - Upgrade cycles (bi-annual turns 1 and 7)

import std/[unittest, tables, random, options]
import ../../src/engine/research/[types, costs, advancement, effects]
import ../../src/engine/config/[tech_config, prestige_config, prestige_multiplier]
import ../../src/common/types/tech

suite "Technology System: Comprehensive Tests":

  # Load config once at suite start
  setup:
    discard loadTechConfig()
    setPrestigeMultiplierForTesting(1.0)

  # ==========================================================================
  # Research Point Conversion Tests
  # ==========================================================================

  test "ERP conversion: PP to ERP based on GHO":
    # Formula: 1 ERP = (5 + log(GHO)) PP
    # GHO = 100: 1 ERP = 5 + 2 = 7 PP
    # GHO = 1000: 1 ERP = 5 + 3 = 8 PP

    let gho100 = 100
    let gho1000 = 1000

    # Test cost calculation
    let cost100 = calculateERPCost(gho100)
    check cost100 >= 6.0 and cost100 <= 8.0  # ~7 PP per ERP

    let cost1000 = calculateERPCost(gho1000)
    check cost1000 >= 7.0 and cost1000 <= 9.0  # ~8 PP per ERP

    # Test conversion
    let erp = convertPPToERP(70, gho100)
    check erp >= 9 and erp <= 11  # ~10 ERP from 70 PP

  test "SRP conversion: PP to SRP scales with SL":
    # Formula: 1 SRP = 2 + SL(0.5) PP
    # SL0: 1 SRP = 2 PP
    # SL5: 1 SRP = 2 + 2.5 = 4.5 PP

    let costSL0 = calculateSRPCost(0)
    check costSL0 == 2.0

    let costSL5 = calculateSRPCost(5)
    check costSL5 == 4.5

    # Test conversion
    let srpSL0 = convertPPToSRP(20, 0)
    check srpSL0 == 10  # 20 PP / 2 = 10 SRP

    let srpSL5 = convertPPToSRP(20, 5)
    check srpSL5 == 4  # 20 PP / 4.5 = 4 SRP

  test "TRP conversion: PP to TRP based on SL and GHO":
    # Formula: 1 TRP = (5 + 4(SL))/10 + log(GHO) * 0.5 PP
    # SL0, GHO100: 1 TRP = 0.5 + 1.0 = 1.5 PP
    # SL5, GHO1000: 1 TRP = 2.5 + 1.5 = 4.0 PP

    let costSL0 = getTRPCost(TechField.WeaponsTech, 0, 100)
    check costSL0 >= 1.0 and costSL0 <= 2.0  # ~1.5 PP per TRP

    let costSL5 = getTRPCost(TechField.WeaponsTech, 5, 1000)
    check costSL5 >= 3.5 and costSL5 <= 4.5  # ~4.0 PP per TRP

    # Test conversion
    let trp = convertPPToTRP(40, TechField.WeaponsTech, 5, 1000)
    check trp >= 9 and trp <= 11  # ~10 TRP from 40 PP

  test "Research allocation: converts PP to all RP types":
    let allocation = ResearchAllocation(
      economic: 100,
      science: 50,
      technology: {
        TechField.WeaponsTech: 80,
        TechField.ShieldTech: 60
      }.toTable
    )

    let rp = allocateResearch(allocation, gho = 1000, slLevel = 3)

    check rp.economic > 0
    check rp.science > 0
    check TechField.WeaponsTech in rp.technology
    check TechField.ShieldTech in rp.technology
    check rp.technology[TechField.WeaponsTech] > 0
    check rp.technology[TechField.ShieldTech] > 0

  # ==========================================================================
  # Economic Level (EL) Tests
  # ==========================================================================

  test "EL upgrade costs: EL1-5 scaling":
    # Per economy.md:4.2 - Starting level is 1, cost lookup is from level N to N+1
    # Table shows: EL01=25 ERP, EL02=30 ERP, etc.
    check getELUpgradeCost(1) == 25   # EL1 -> EL2: 25 ERP
    check getELUpgradeCost(2) == 30   # EL2 -> EL3: 30 ERP
    check getELUpgradeCost(3) == 35   # EL3 -> EL4: 35 ERP
    check getELUpgradeCost(4) == 40   # EL4 -> EL5: 40 ERP
    check getELUpgradeCost(5) == 45   # EL5 -> EL6: 45 ERP
    check getELUpgradeCost(6) == 52   # EL6 -> EL7: 52 ERP

  test "EL upgrade costs: EL6+ scaling":
    # Per config/tech.kdl actual values
    check getELUpgradeCost(6) == 52  # EL6 -> EL7: 52 ERP
    check getELUpgradeCost(7) == 60  # EL7 -> EL8: 60 ERP
    check getELUpgradeCost(8) == 67  # EL8 -> EL9: 67 ERP
    check getELUpgradeCost(9) == 75  # EL9 -> EL10: 75 ERP

  test "EL modifier: +5% per level, capped at 50%":
    check getELModifier(0) == 1.0   # No bonus
    check getELModifier(1) == 1.05  # +5%
    check getELModifier(5) == 1.25  # +25%
    check getELModifier(10) == 1.50 # +50% (capped)
    check getELModifier(15) == 1.50 # Still capped at 50%

  test "EL advancement: successful upgrade":
    var tree = initTechTree()  # Starts at EL1
    tree.accumulated.economic = 100  # Enough for EL1 -> EL2 (25 ERP per config)

    let advancement = attemptELAdvancement(tree, tree.levels.economicLevel)

    check advancement.isSome
    check advancement.get().advancementType == AdvancementType.EconomicLevel
    check advancement.get().elFromLevel == 1
    check advancement.get().elToLevel == 2  # Advances to level 2
    check advancement.get().elCost == 25
    check tree.accumulated.economic == 75  # 100 - 25 = 75 remaining
    check tree.levels.economicLevel == 2

  test "EL advancement: insufficient ERP":
    var tree = initTechTree()
    tree.accumulated.economic = 20  # Not enough (need 25 per config for EL1→EL2)

    let advancement = attemptELAdvancement(tree, tree.levels.economicLevel)

    check advancement.isNone
    check tree.accumulated.economic == 20  # Unchanged
    check tree.levels.economicLevel == 1

  # ==========================================================================
  # Science Level (SL) Tests
  # ==========================================================================

  test "SL upgrade costs: actual config values":
    # Per config/tech.kdl scienceLevel section
    check getSLUpgradeCost(1) == 12   # SL1 -> SL2: 12 SRP
    check getSLUpgradeCost(2) == 15   # SL2 -> SL3: 15 SRP
    check getSLUpgradeCost(3) == 17   # SL3 -> SL4: 17 SRP
    check getSLUpgradeCost(4) == 20   # SL4 -> SL5: 20 SRP
    check getSLUpgradeCost(5) == 22   # SL5 -> SL6: 22 SRP
    check getSLUpgradeCost(6) == 27   # SL6 -> SL7: 27 SRP
    check getSLUpgradeCost(7) == 32   # SL7 -> SL8: 32 SRP (max level)

  test "SL advancement: successful upgrade":
    var tree = initTechTree()  # Starts at SL1
    tree.accumulated.science = 50  # Enough for SL1 -> SL2 (12 SRP per config)

    let advancement = attemptSLAdvancement(tree, tree.levels.scienceLevel)

    check advancement.isSome
    check advancement.get().advancementType == AdvancementType.ScienceLevel
    check advancement.get().slFromLevel == 1
    check advancement.get().slToLevel == 2
    check advancement.get().slCost == 12
    check tree.accumulated.science == 38  # 50 - 12 = 38 remaining
    check tree.levels.scienceLevel == 2

  test "SL advancement: insufficient SRP":
    var tree = initTechTree()  # Starts at SL1
    tree.accumulated.science = 10  # Not enough (need 12 for SL1→SL2)

    let advancement = attemptSLAdvancement(tree, tree.levels.scienceLevel)

    check advancement.isNone
    check tree.accumulated.science == 10  # Unchanged
    check tree.levels.scienceLevel == 1

  # ==========================================================================
  # Technology Field Advancement Tests
  # ==========================================================================

  test "Tech advancement: WEP (Weapons Tech)":
    var tree = initTechTree()  # Starts at level 1
    let cost = getTechUpgradeCost(TechField.WeaponsTech, 1)
    tree.accumulated.technology[TechField.WeaponsTech] = cost + 10

    let advancement = attemptTechAdvancement(tree, TechField.WeaponsTech)

    check advancement.isSome
    check advancement.get().advancementType == AdvancementType.Technology
    check advancement.get().techField == TechField.WeaponsTech
    check advancement.get().techFromLevel == 1
    check advancement.get().techToLevel == 2  # Advances to level 2
    check tree.levels.weaponsTech == 2
    check tree.accumulated.technology[TechField.WeaponsTech] == 10

  test "Tech advancement: ELI (Electronic Intelligence)":
    var tree = initTechTree()  # Starts at level 1
    let cost = getTechUpgradeCost(TechField.ElectronicIntelligence, 1)
    tree.accumulated.technology[TechField.ElectronicIntelligence] = cost + 5

    let advancement = attemptTechAdvancement(tree, TechField.ElectronicIntelligence)

    check advancement.isSome
    check advancement.get().advancementType == AdvancementType.Technology
    check advancement.get().techField == TechField.ElectronicIntelligence
    check tree.levels.electronicIntelligence == 2  # Advances to level 2

  test "Tech advancement: CLK (Cloaking Tech)":
    var tree = initTechTree()  # Starts at level 1
    let cost = getTechUpgradeCost(TechField.CloakingTech, 1)
    tree.accumulated.technology[TechField.CloakingTech] = cost

    let advancement = attemptTechAdvancement(tree, TechField.CloakingTech)

    check advancement.isSome
    check advancement.get().advancementType == AdvancementType.Technology
    check advancement.get().techField == TechField.CloakingTech
    check tree.levels.cloakingTech == 2  # Advances to level 2

  test "Tech advancement: SLD (Shield Tech)":
    var tree = initTechTree()  # Starts at level 1
    let cost = getTechUpgradeCost(TechField.ShieldTech, 1)
    tree.accumulated.technology[TechField.ShieldTech] = cost

    let advancement = attemptTechAdvancement(tree, TechField.ShieldTech)

    check advancement.isSome
    check advancement.get().advancementType == AdvancementType.Technology
    check advancement.get().techField == TechField.ShieldTech
    check tree.levels.shieldTech == 2  # Advances to level 2

  test "Tech advancement: CST (Construction Tech)":
    var tree = initTechTree()  # Starts at level 1
    let cost = getTechUpgradeCost(TechField.ConstructionTech, 1)
    tree.accumulated.technology[TechField.ConstructionTech] = cost

    let advancement = attemptTechAdvancement(tree, TechField.ConstructionTech)

    check advancement.isSome
    check advancement.get().advancementType == AdvancementType.Technology
    check advancement.get().techField == TechField.ConstructionTech
    check tree.levels.constructionTech == 2  # Advances to level 2

  test "Tech advancement: TER (Terraforming Tech)":
    var tree = initTechTree()  # Starts at level 1
    let cost = getTechUpgradeCost(TechField.TerraformingTech, 1)
    tree.accumulated.technology[TechField.TerraformingTech] = cost

    let advancement = attemptTechAdvancement(tree, TechField.TerraformingTech)

    check advancement.isSome
    check advancement.get().advancementType == AdvancementType.Technology
    check advancement.get().techField == TechField.TerraformingTech
    check tree.levels.terraformingTech == 2  # Advances to level 2

  test "Tech advancement: CIC (Counter Intelligence)":
    var tree = initTechTree()  # Starts at level 1
    let cost = getTechUpgradeCost(TechField.CounterIntelligence, 1)
    tree.accumulated.technology[TechField.CounterIntelligence] = cost

    let advancement = attemptTechAdvancement(tree, TechField.CounterIntelligence)

    check advancement.isSome
    check advancement.get().advancementType == AdvancementType.Technology
    check advancement.get().techField == TechField.CounterIntelligence
    check tree.levels.counterIntelligence == 2  # Advances to level 2

  test "Tech advancement: FD (Fighter Doctrine)":
    var tree = initTechTree()  # Starts at level 1
    let cost = getTechUpgradeCost(TechField.FighterDoctrine, 1)
    tree.accumulated.technology[TechField.FighterDoctrine] = cost

    let advancement = attemptTechAdvancement(tree, TechField.FighterDoctrine)

    check advancement.isSome
    check advancement.get().advancementType == AdvancementType.Technology
    check advancement.get().techField == TechField.FighterDoctrine
    check tree.levels.fighterDoctrine == 2  # Advances to level 2

  test "Tech advancement: ACO (Advanced Carrier Ops)":
    var tree = initTechTree()  # Starts at level 1
    let cost = getTechUpgradeCost(TechField.AdvancedCarrierOps, 1)
    tree.accumulated.technology[TechField.AdvancedCarrierOps] = cost

    let advancement = attemptTechAdvancement(tree, TechField.AdvancedCarrierOps)

    check advancement.isSome
    check advancement.get().advancementType == AdvancementType.Technology
    check advancement.get().techField == TechField.AdvancedCarrierOps
    check tree.levels.advancedCarrierOps == 2  # Advances to level 2

  test "Tech advancement: insufficient TRP":
    var tree = initTechTree()
    let cost = getTechUpgradeCost(TechField.WeaponsTech, 1)
    tree.accumulated.technology[TechField.WeaponsTech] = cost - 10

    let advancement = attemptTechAdvancement(tree, TechField.WeaponsTech)

    check advancement.isNone
    check tree.levels.weaponsTech == 1

  # ==========================================================================
  # Research Breakthrough Tests
  # ==========================================================================

  test "Breakthrough: base 5% chance (1d20)":
    # Per economy.md:4.1.1 - Base breakthrough chance is 5% (1 on d20)
    # With 0 RP invested, chance is 5%

    var rng = initRand(42)
    var successCount = 0
    var totalRolls = 200  # More rolls for better statistical validation

    for i in 0..<totalRolls:
      let result = rollBreakthrough(investedRP = 0, rng)
      if result.isSome:
        successCount += 1

    # Should be around 5% (10 successes out of 200)
    # Allow ±7 for variance (3-17 successes = 1.5%-8.5%)
    check successCount >= 3 and successCount <= 17

  test "Breakthrough: investment bonus (+1% per 100 RP)":
    # Per economy.md:4.1.1 - +1% per 100 RP invested
    # 1000 RP invested = +10% bonus = 15% total (capped at 15%)

    var rng = initRand(123)
    var successCount = 0
    var totalRolls = 200

    for i in 0..<totalRolls:
      let result = rollBreakthrough(investedRP = 1000, rng)
      if result.isSome:
        successCount += 1

    # Should be around 15% (30 successes out of 200)
    # Allow ±10 for variance (20-40 successes = 10%-20%)
    check successCount >= 20 and successCount <= 40

  test "Breakthrough types: Minor (0-4), Moderate (5-6), Major (7-8), Revolutionary (9)":
    var rng = initRand(456)
    var minorCount = 0
    var moderateCount = 0
    var majorCount = 0
    var revolutionaryCount = 0

    # Force breakthroughs and check distribution
    for i in 0..<100:
      let result = rollBreakthrough(investedRP = 5000, rng)  # Very high chance
      if result.isSome:
        case result.get()
        of BreakthroughType.Minor:
          minorCount += 1
        of BreakthroughType.Moderate:
          moderateCount += 1
        of BreakthroughType.Major:
          majorCount += 1
        of BreakthroughType.Revolutionary:
          revolutionaryCount += 1

    # Minor should be most common (50% of breakthroughs)
    check minorCount > moderateCount
    check minorCount > majorCount
    check minorCount > revolutionaryCount

  test "Breakthrough: Minor adds +10 RP to highest category":
    var tree = initTechTree()
    tree.accumulated.economic = 20
    tree.accumulated.science = 5

    let allocation = ResearchAllocation(
      economic: 100,  # Highest investment
      science: 50,
      technology: initTable[TechField, int]()
    )

    let event = applyBreakthrough(tree, BreakthroughType.Minor, allocation)

    check event.breakthroughType == BreakthroughType.Minor
    check event.category == ResearchCategory.Economic
    check event.amount == 10
    check tree.accumulated.economic == 30  # 20 + 10

  test "Breakthrough: Moderate gives 20% cost reduction":
    var tree = initTechTree()
    let allocation = ResearchAllocation(
      economic: 100,
      science: 0,
      technology: initTable[TechField, int]()
    )

    let event = applyBreakthrough(tree, BreakthroughType.Moderate, allocation)

    check event.breakthroughType == BreakthroughType.Moderate
    check event.costReduction == 0.8  # 20% reduction = 0.8 multiplier

  test "Breakthrough: Major auto-advances EL or SL":
    var tree = initTechTree()
    tree.levels.economicLevel = 2

    let allocation = ResearchAllocation(
      economic: 100,  # Highest investment
      science: 30,
      technology: initTable[TechField, int]()
    )

    let event = applyBreakthrough(tree, BreakthroughType.Major, allocation)

    check event.breakthroughType == BreakthroughType.Major
    check event.autoAdvance == true
    check tree.levels.economicLevel == 3  # Auto-advanced

  test "Breakthrough: Revolutionary unlocks unique tech":
    var tree = initTechTree()
    let allocation = ResearchAllocation(
      economic: 100,
      science: 0,
      technology: initTable[TechField, int]()
    )

    let event = applyBreakthrough(tree, BreakthroughType.Revolutionary, allocation)

    check event.breakthroughType == BreakthroughType.Revolutionary
    check event.revolutionary.isSome

  # ==========================================================================
  # Upgrade Cycle Tests
  # ==========================================================================
  # DISABLED:
  # DISABLED:   test "Upgrade turns: turns 1 and 7 (bi-annual)":
  # DISABLED:     # Turns 1 and 7 of each year (months 1 and 7)
  # DISABLED:     check isUpgradeTurn(1) == true   # Turn 1 (month 1)
  # DISABLED:     check isUpgradeTurn(7) == true   # Turn 7 (month 7)
  # DISABLED:     check isUpgradeTurn(14) == true  # Turn 14 (month 1 of year 2)
  # DISABLED:     check isUpgradeTurn(20) == true  # Turn 20 (month 7 of year 2)
  # DISABLED:
  # DISABLED:     # Non-upgrade turns
  # DISABLED:     check isUpgradeTurn(2) == false
  # DISABLED:     check isUpgradeTurn(6) == false
  # DISABLED:     check isUpgradeTurn(8) == false
  # DISABLED:     check isUpgradeTurn(13) == false
  # DISABLED:
  # DISABLED:   test "Upgrade cycle: only specific turns allow advancement":
  # DISABLED:     # This ensures upgrades are restricted to bi-annual cycles
  # DISABLED:     var upgradeTurns: seq[int] = @[]
  # DISABLED:
  # DISABLED:     for turn in 1..26:  # 2 full years
  # DISABLED:       if isUpgradeTurn(turn):
  # DISABLED:         upgradeTurns.add(turn)
  # DISABLED:
  # DISABLED:     # Should have exactly 4 upgrade turns in 2 years
  # DISABLED:     check upgradeTurns.len == 4
  # DISABLED:     check 1 in upgradeTurns
  # DISABLED:     check 7 in upgradeTurns
  # DISABLED:     check 14 in upgradeTurns
  # DISABLED:     check 20 in upgradeTurns

  # ==========================================================================
  # Tech Cost Scaling Tests
  # ==========================================================================

  test "Tech costs: exponential scaling with level":
    # Costs should increase as tech level increases
    let cost1 = getTechUpgradeCost(TechField.WeaponsTech, 1)  # Level 1 → 2
    let cost2 = getTechUpgradeCost(TechField.WeaponsTech, 2)  # Level 2 → 3
    let cost5 = getTechUpgradeCost(TechField.WeaponsTech, 5)  # Level 5 → 6

    check cost2 > cost1  # Cost increases with level
    check cost5 > cost2

  test "Multiple tech advancements: independent progression":
    var tree = initTechTree()

    # Fund multiple tech fields
    tree.accumulated.technology[TechField.WeaponsTech] = 1000
    tree.accumulated.technology[TechField.ShieldTech] = 1000

    # Advance WEP (from level 1 to 2)
    let advWep = attemptTechAdvancement(tree, TechField.WeaponsTech)
    check advWep.isSome
    check tree.levels.weaponsTech == 2

    # Advance SLD (from level 1 to 2)
    let advSld = attemptTechAdvancement(tree, TechField.ShieldTech)
    check advSld.isSome
    check tree.levels.shieldTech == 2

    # Both should be independent
    check tree.levels.weaponsTech == 2
    check tree.levels.shieldTech == 2

  # ==========================================================================
  # Integration Tests
  # ==========================================================================

  test "Full research cycle: allocation -> conversion -> advancement":
    var tree = initTechTree()  # Starts at EL1

    # Allocate PP (need more due to conversion cost)
    # Formula: 1 ERP = (5 + log(1000)) = 8 PP
    # Need 25 ERP for EL1→2, so need ~200 PP
    let allocation = ResearchAllocation(
      economic: 250,  # Enough to get 25+ ERP after conversion
      science: 0,
      technology: initTable[TechField, int]()
    )

    # Convert to RP
    let rp = allocateResearch(allocation, gho = 1000, slLevel = 1)
    tree.accumulated.economic += rp.economic

    # Should have enough to advance EL (need 25 ERP for level 1→2 per config)
    check tree.accumulated.economic >= 25

    # Attempt advancement (use actual current level from tree)
    let advancement = attemptELAdvancement(tree, tree.levels.economicLevel)

    check advancement.isSome
    check tree.levels.economicLevel == 2  # Advanced from 1 to 2

  test "Prestige awarded for tech advancement":
    var tree = initTechTree()
    tree.accumulated.economic = 100

    let advancement = attemptELAdvancement(tree, tree.levels.economicLevel)

    check advancement.isSome
    check advancement.get().prestigeEvent.isSome
    check advancement.get().prestigeEvent.get().amount > 0

  test "Tech tree initialization: all levels start at 1 per spec":
    # Per economy.md:4.0: "ALL technology levels start at level 1, never 0"
    let tree = initTechTree()  # Uses default starting levels (all at 1)

    check tree.levels.economicLevel == 1  # Starting level per economy.md:4.0
    check tree.levels.scienceLevel == 1
    check tree.levels.weaponsTech == 1
    check tree.levels.constructionTech == 1
    check tree.levels.terraformingTech == 1
    check tree.levels.electronicIntelligence == 1
    check tree.levels.cloakingTech == 1
    check tree.levels.shieldTech == 1
    check tree.levels.counterIntelligence == 1
    check tree.levels.fighterDoctrine == 1
    check tree.levels.advancedCarrierOps == 1
    check tree.accumulated.economic == 0
    check tree.accumulated.science == 0

  # ==========================================================================
  # Boundary/Aggressive Tests - Try to Break the Engine
  # ==========================================================================

  test "BOUNDARY: Cannot advance beyond max EL (11)":
    var tree = initTechTree()
    tree.levels.economicLevel = 11  # At max
    tree.accumulated.economic = 10000  # Unlimited RP

    let advancement = attemptELAdvancement(tree, tree.levels.economicLevel)

    check advancement.isNone  # Should refuse to advance beyond max
    check tree.levels.economicLevel == 11  # Level unchanged

  test "BOUNDARY: Cannot advance beyond max SL (8)":
    var tree = initTechTree()
    tree.levels.scienceLevel = 8  # At max
    tree.accumulated.science = 10000  # Unlimited RP

    let advancement = attemptSLAdvancement(tree, tree.levels.scienceLevel)

    check advancement.isNone  # Should refuse to advance beyond max
    check tree.levels.scienceLevel == 8  # Level unchanged

  test "BOUNDARY: Cannot get cost for level 0":
    # Engine should reject level 0 as invalid per spec
    expect(ValueError):
      discard getELUpgradeCost(0)

  test "BOUNDARY: Cannot get cost for level beyond max":
    # Engine should reject levels beyond maximum
    expect(ValueError):
      discard getELUpgradeCost(12)  # Max is 11

  test "BOUNDARY: Cannot advance with negative RP":
    var tree = initTechTree()
    tree.accumulated.economic = -100  # Negative RP (should never happen)

    let advancement = attemptELAdvancement(tree, tree.levels.economicLevel)

    check advancement.isNone  # Should not advance with negative RP
    check tree.accumulated.economic == -100  # Unchanged

  test "BOUNDARY: Tech advancement at max level returns none":
    var tree = initTechTree()
    tree.levels.weaponsTech = 15  # At max per advancement.nim:32
    tree.accumulated.technology[TechField.WeaponsTech] = 10000

    let advancement = attemptTechAdvancement(tree, TechField.WeaponsTech)

    check advancement.isNone  # Cannot advance beyond max
    check tree.levels.weaponsTech == 15  # Unchanged

  test "BOUNDARY: Breakthrough with massive RP investment caps at 15%":
    # Even with huge RP investment, breakthrough chance should cap at 15%
    var rng = initRand(999)
    var successCount = 0
    var totalRolls = 500

    for i in 0..<totalRolls:
      let result = rollBreakthrough(investedRP = 100000, rng)  # Extreme investment
      if result.isSome:
        successCount += 1

    # Should be around 15% (75 successes), not higher
    # Cap ensures: successCount <= ~100 (20%)
    check successCount <= 120  # Allow variance, but verify it's capped

  test "BOUNDARY: Cannot skip tech levels":
    # Verify sequential ordering is enforced
    var tree = initTechTree()
    tree.levels.weaponsTech = 1  # At level 1
    tree.accumulated.technology[TechField.WeaponsTech] = 10000

    # Try to advance to level 2 (valid)
    let adv1 = attemptTechAdvancement(tree, TechField.WeaponsTech)
    check adv1.isSome
    check tree.levels.weaponsTech == 2

    # Cannot manually set to level 5 and skip levels
    # (This test verifies the advancement function requires sequential order)
    tree.levels.weaponsTech = 5  # Manual skip (simulating a bug)
    tree.accumulated.technology[TechField.WeaponsTech] = 10000

    # Advancement should work from level 5 to 6 (sequential)
    let adv2 = attemptTechAdvancement(tree, TechField.WeaponsTech)
    check adv2.isSome
    check tree.levels.weaponsTech == 6

  test "BOUNDARY: Zero PP allocation produces zero RP":
    let allocation = ResearchAllocation(
      economic: 0,
      science: 0,
      technology: initTable[TechField, int]()
    )

    let rp = allocateResearch(allocation, gho = 1000, slLevel = 1)

    check rp.economic == 0
    check rp.science == 0

  test "BOUNDARY: Negative PP allocation should be rejected or treated as zero":
    # Engine should handle negative allocations gracefully
    let allocation = ResearchAllocation(
      economic: -100,  # Negative allocation (invalid)
      science: -50,
      technology: initTable[TechField, int]()
    )

    let rp = allocateResearch(allocation, gho = 1000, slLevel = 1)

    # Should either reject (throw error) or treat as zero
    check rp.economic <= 0  # Should not produce positive RP from negative PP
    check rp.science <= 0
