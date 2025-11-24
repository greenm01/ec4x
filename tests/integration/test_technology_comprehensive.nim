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
import ../../src/common/types/tech

suite "Technology System: Comprehensive Tests":

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
    # Formula: 40 + EL(10)
    check getELUpgradeCost(0) == 40   # EL0 -> EL1: 40 ERP
    check getELUpgradeCost(1) == 50   # EL1 -> EL2: 50 ERP
    check getELUpgradeCost(2) == 60   # EL2 -> EL3: 60 ERP
    check getELUpgradeCost(3) == 70   # EL3 -> EL4: 70 ERP
    check getELUpgradeCost(4) == 80   # EL4 -> EL5: 80 ERP
    check getELUpgradeCost(5) == 90   # EL5 -> EL6: 90 ERP

  test "EL upgrade costs: EL6+ scaling":
    # Formula: 90 + 15 per level above 5
    check getELUpgradeCost(6) == 105  # EL6 -> EL7: 105 ERP
    check getELUpgradeCost(7) == 120  # EL7 -> EL8: 120 ERP
    check getELUpgradeCost(8) == 135  # EL8 -> EL9: 135 ERP
    check getELUpgradeCost(9) == 150  # EL9 -> EL10: 150 ERP

  test "EL modifier: +5% per level, capped at 50%":
    check getELModifier(0) == 1.0   # No bonus
    check getELModifier(1) == 1.05  # +5%
    check getELModifier(5) == 1.25  # +25%
    check getELModifier(10) == 1.50 # +50% (capped)
    check getELModifier(15) == 1.50 # Still capped at 50%

  test "EL advancement: successful upgrade":
    var tree = initTechTree(TechLevel())
    tree.accumulated.economic = 100  # Enough for EL0 -> EL1 (40 ERP)

    let advancement = attemptELAdvancement(tree, currentEL = 0)

    check advancement.isSome
    check advancement.get().fromLevel == 0
    check advancement.get().toLevel == 1
    check advancement.get().cost == 40
    check tree.accumulated.economic == 60  # 100 - 40 = 60 remaining
    check tree.levels.economicLevel == 1

  test "EL advancement: insufficient ERP":
    var tree = initTechTree(TechLevel())
    tree.accumulated.economic = 30  # Not enough (need 40)

    let advancement = attemptELAdvancement(tree, currentEL = 0)

    check advancement.isNone
    check tree.accumulated.economic == 30  # Unchanged
    check tree.levels.economicLevel == 0

  # ==========================================================================
  # Science Level (SL) Tests
  # ==========================================================================

  test "SL upgrade costs: SL1-5 scaling":
    # Formula: 20 + SL(5)
    check getSLUpgradeCost(0) == 20   # SL0 -> SL1: 20 SRP
    check getSLUpgradeCost(1) == 25   # SL1 -> SL2: 25 SRP
    check getSLUpgradeCost(2) == 30   # SL2 -> SL3: 30 SRP
    check getSLUpgradeCost(3) == 35   # SL3 -> SL4: 35 SRP
    check getSLUpgradeCost(4) == 40   # SL4 -> SL5: 40 SRP
    check getSLUpgradeCost(5) == 45   # SL5 -> SL6: 45 SRP

  test "SL upgrade costs: SL6+ scaling":
    # SL6+: Increases by 10 per level
    check getSLUpgradeCost(6) == 55   # SL6 -> SL7: 55 SRP
    check getSLUpgradeCost(7) == 65   # SL7 -> SL8: 65 SRP
    check getSLUpgradeCost(8) == 75   # SL8 -> SL9: 75 SRP
    check getSLUpgradeCost(9) == 85   # SL9 -> SL10: 85 SRP

  test "SL advancement: successful upgrade":
    var tree = initTechTree(TechLevel())
    tree.accumulated.science = 50  # Enough for SL0 -> SL1 (20 SRP)

    let advancement = attemptSLAdvancement(tree, currentSL = 0)

    check advancement.isSome
    check advancement.get().fromLevel == 0
    check advancement.get().toLevel == 1
    check advancement.get().cost == 20
    check tree.accumulated.science == 30  # 50 - 20 = 30 remaining
    check tree.levels.scienceLevel == 1

  test "SL advancement: insufficient SRP":
    var tree = initTechTree(TechLevel())
    tree.accumulated.science = 15  # Not enough (need 20)

    let advancement = attemptSLAdvancement(tree, currentSL = 0)

    check advancement.isNone
    check tree.accumulated.science == 15  # Unchanged
    check tree.levels.scienceLevel == 0

  # ==========================================================================
  # Technology Field Advancement Tests
  # ==========================================================================

  test "Tech advancement: WEP (Weapons Tech)":
    var tree = initTechTree(TechLevel())
    let cost = getTechUpgradeCost(TechField.WeaponsTech, 0)
    tree.accumulated.technology[TechField.WeaponsTech] = cost + 10

    let advancement = attemptTechAdvancement(tree, TechField.WeaponsTech)

    check advancement.isSome
    check advancement.get().field == TechField.WeaponsTech
    check advancement.get().fromLevel == 0
    check advancement.get().toLevel == 1
    check tree.levels.weaponsTech == 1
    check tree.accumulated.technology[TechField.WeaponsTech] == 10

  test "Tech advancement: ELI (Electronic Intelligence)":
    var tree = initTechTree(TechLevel())
    let cost = getTechUpgradeCost(TechField.ElectronicIntelligence, 0)
    tree.accumulated.technology[TechField.ElectronicIntelligence] = cost + 5

    let advancement = attemptTechAdvancement(tree, TechField.ElectronicIntelligence)

    check advancement.isSome
    check advancement.get().field == TechField.ElectronicIntelligence
    check tree.levels.electronicIntelligence == 1

  test "Tech advancement: CLK (Cloaking Tech)":
    var tree = initTechTree(TechLevel())
    let cost = getTechUpgradeCost(TechField.CloakingTech, 0)
    tree.accumulated.technology[TechField.CloakingTech] = cost

    let advancement = attemptTechAdvancement(tree, TechField.CloakingTech)

    check advancement.isSome
    check advancement.get().field == TechField.CloakingTech
    check tree.levels.cloakingTech == 1

  test "Tech advancement: SLD (Shield Tech)":
    var tree = initTechTree(TechLevel())
    let cost = getTechUpgradeCost(TechField.ShieldTech, 0)
    tree.accumulated.technology[TechField.ShieldTech] = cost

    let advancement = attemptTechAdvancement(tree, TechField.ShieldTech)

    check advancement.isSome
    check advancement.get().field == TechField.ShieldTech
    check tree.levels.shieldTech == 1

  test "Tech advancement: CST (Construction Tech)":
    var tree = initTechTree(TechLevel())
    let cost = getTechUpgradeCost(TechField.ConstructionTech, 0)
    tree.accumulated.technology[TechField.ConstructionTech] = cost

    let advancement = attemptTechAdvancement(tree, TechField.ConstructionTech)

    check advancement.isSome
    check advancement.get().field == TechField.ConstructionTech
    check tree.levels.constructionTech == 1

  test "Tech advancement: TER (Terraforming Tech)":
    var tree = initTechTree(TechLevel())
    let cost = getTechUpgradeCost(TechField.TerraformingTech, 0)
    tree.accumulated.technology[TechField.TerraformingTech] = cost

    let advancement = attemptTechAdvancement(tree, TechField.TerraformingTech)

    check advancement.isSome
    check advancement.get().field == TechField.TerraformingTech
    check tree.levels.terraformingTech == 1

  test "Tech advancement: CIC (Counter Intelligence)":
    var tree = initTechTree(TechLevel())
    let cost = getTechUpgradeCost(TechField.CounterIntelligence, 0)
    tree.accumulated.technology[TechField.CounterIntelligence] = cost

    let advancement = attemptTechAdvancement(tree, TechField.CounterIntelligence)

    check advancement.isSome
    check advancement.get().field == TechField.CounterIntelligence
    check tree.levels.counterIntelligence == 1

  test "Tech advancement: FD (Fighter Doctrine)":
    var tree = initTechTree(TechLevel())
    let cost = getTechUpgradeCost(TechField.FighterDoctrine, 0)
    tree.accumulated.technology[TechField.FighterDoctrine] = cost

    let advancement = attemptTechAdvancement(tree, TechField.FighterDoctrine)

    check advancement.isSome
    check advancement.get().field == TechField.FighterDoctrine
    check tree.levels.fighterDoctrine == 1

  test "Tech advancement: ACO (Advanced Carrier Ops)":
    var tree = initTechTree(TechLevel())
    let cost = getTechUpgradeCost(TechField.AdvancedCarrierOps, 0)
    tree.accumulated.technology[TechField.AdvancedCarrierOps] = cost

    let advancement = attemptTechAdvancement(tree, TechField.AdvancedCarrierOps)

    check advancement.isSome
    check advancement.get().field == TechField.AdvancedCarrierOps
    check tree.levels.advancedCarrierOps == 1

  test "Tech advancement: insufficient TRP":
    var tree = initTechTree(TechLevel())
    let cost = getTechUpgradeCost(TechField.WeaponsTech, 0)
    tree.accumulated.technology[TechField.WeaponsTech] = cost - 10

    let advancement = attemptTechAdvancement(tree, TechField.WeaponsTech)

    check advancement.isNone
    check tree.levels.weaponsTech == 0

  # ==========================================================================
  # Research Breakthrough Tests
  # ==========================================================================

  test "Breakthrough: base 10% chance":
    # With 0 RP invested, chance is 10% (threshold = 1)
    # Roll 0 should succeed, roll 1+ should fail

    var rng = initRand(42)
    var successCount = 0
    var totalRolls = 100

    for i in 0..<totalRolls:
      let result = rollBreakthrough(investedRP = 0, rng)
      if result.isSome:
        successCount += 1

    # Should be around 10% (allow some variance)
    check successCount >= 5 and successCount <= 20

  test "Breakthrough: investment bonus (+1% per 50 RP)":
    # 500 RP invested = +10% bonus = 20% total chance

    var rng = initRand(123)
    var successCount = 0
    var totalRolls = 100

    for i in 0..<totalRolls:
      let result = rollBreakthrough(investedRP = 500, rng)
      if result.isSome:
        successCount += 1

    # Should be around 20% (allow variance)
    check successCount >= 10 and successCount <= 35

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
    var tree = initTechTree(TechLevel())
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
    var tree = initTechTree(TechLevel())
    let allocation = ResearchAllocation(
      economic: 100,
      science: 0,
      technology: initTable[TechField, int]()
    )

    let event = applyBreakthrough(tree, BreakthroughType.Moderate, allocation)

    check event.breakthroughType == BreakthroughType.Moderate
    check event.costReduction == 0.8  # 20% reduction = 0.8 multiplier

  test "Breakthrough: Major auto-advances EL or SL":
    var tree = initTechTree(TechLevel())
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
    var tree = initTechTree(TechLevel())
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

  test "Upgrade turns: turns 1 and 7 (bi-annual)":
    # Turns 1 and 7 of each year (months 1 and 7)
    check isUpgradeTurn(1) == true   # Turn 1 (month 1)
    check isUpgradeTurn(7) == true   # Turn 7 (month 7)
    check isUpgradeTurn(14) == true  # Turn 14 (month 1 of year 2)
    check isUpgradeTurn(20) == true  # Turn 20 (month 7 of year 2)

    # Non-upgrade turns
    check isUpgradeTurn(2) == false
    check isUpgradeTurn(6) == false
    check isUpgradeTurn(8) == false
    check isUpgradeTurn(13) == false

  test "Upgrade cycle: only specific turns allow advancement":
    # This ensures upgrades are restricted to bi-annual cycles
    var upgradeTurns: seq[int] = @[]

    for turn in 1..26:  # 2 full years
      if isUpgradeTurn(turn):
        upgradeTurns.add(turn)

    # Should have exactly 4 upgrade turns in 2 years
    check upgradeTurns.len == 4
    check 1 in upgradeTurns
    check 7 in upgradeTurns
    check 14 in upgradeTurns
    check 20 in upgradeTurns

  # ==========================================================================
  # Tech Cost Scaling Tests
  # ==========================================================================

  test "Tech costs: exponential scaling with level":
    # Costs should increase as tech level increases
    let cost0 = getTechUpgradeCost(TechField.WeaponsTech, 0)
    let cost1 = getTechUpgradeCost(TechField.WeaponsTech, 1)
    let cost2 = getTechUpgradeCost(TechField.WeaponsTech, 2)
    let cost5 = getTechUpgradeCost(TechField.WeaponsTech, 5)

    check cost1 > cost0
    check cost2 > cost1
    check cost5 > cost2

  test "Multiple tech advancements: independent progression":
    var tree = initTechTree(TechLevel())

    # Fund multiple tech fields
    tree.accumulated.technology[TechField.WeaponsTech] = 1000
    tree.accumulated.technology[TechField.ShieldTech] = 1000

    # Advance WEP
    let advWep = attemptTechAdvancement(tree, TechField.WeaponsTech)
    check advWep.isSome
    check tree.levels.weaponsTech == 1

    # Advance SLD
    let advSld = attemptTechAdvancement(tree, TechField.ShieldTech)
    check advSld.isSome
    check tree.levels.shieldTech == 1

    # Both should be independent
    check tree.levels.weaponsTech == 1
    check tree.levels.shieldTech == 1

  # ==========================================================================
  # Integration Tests
  # ==========================================================================

  test "Full research cycle: allocation -> conversion -> advancement":
    var tree = initTechTree(TechLevel())

    # Allocate PP (need more due to conversion cost)
    # Formula: 1 ERP = (5 + log(1000)) = 8 PP
    # Need 40 ERP, so need ~320 PP
    let allocation = ResearchAllocation(
      economic: 400,  # Increased to ensure we have enough after conversion
      science: 0,
      technology: initTable[TechField, int]()
    )

    # Convert to RP
    let rp = allocateResearch(allocation, gho = 1000, slLevel = 0)
    tree.accumulated.economic += rp.economic

    # Should have enough to advance EL (need 40 ERP)
    check tree.accumulated.economic >= 40

    # Attempt advancement
    let advancement = attemptELAdvancement(tree, currentEL = 0)

    check advancement.isSome
    check tree.levels.economicLevel == 1

  test "Prestige awarded for tech advancement":
    var tree = initTechTree(TechLevel())
    tree.accumulated.economic = 100

    let advancement = attemptELAdvancement(tree, currentEL = 0)

    check advancement.isSome
    check advancement.get().prestigeEvent.isSome
    check advancement.get().prestigeEvent.get().amount > 0

  test "Tech tree initialization: all levels start at 0":
    let startLevels = TechLevel(
      economicLevel: 0,
      scienceLevel: 0,
      constructionTech: 0,
      weaponsTech: 0,
      terraformingTech: 0,
      electronicIntelligence: 0,
      cloakingTech: 0,
      shieldTech: 0,
      counterIntelligence: 0,
      fighterDoctrine: 0,
      advancedCarrierOps: 0
    )

    let tree = initTechTree(startLevels)

    check tree.levels.economicLevel == 0
    check tree.levels.scienceLevel == 0
    check tree.levels.weaponsTech == 0
    check tree.accumulated.economic == 0
    check tree.accumulated.science == 0
