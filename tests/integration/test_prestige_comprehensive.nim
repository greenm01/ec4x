## Comprehensive Prestige System Tests
##
## Tests all prestige mechanics from gameplay.md:1.1 and reference.md:9.4
## - Prestige sources (military, economic, tech, diplomatic)
## - Prestige penalties (taxes, blockades, maintenance)
## - Victory conditions (5000 prestige threshold)
## - Defensive collapse (< 0 prestige for 3 turns)
## - Morale modifiers from prestige
## - Combat prestige awards
## - Tax prestige bonuses/penalties
## - Tech advancement prestige

import std/[unittest, tables, options, strutils]
import ../../src/engine/prestige
import ../../src/engine/config/prestige_config
import ../../src/common/types/core

suite "Prestige System: Comprehensive Tests":

  # ==========================================================================
  # Prestige Source Values Tests
  # ==========================================================================

  test "Prestige values: combat victory":
    let value = getPrestigeValue(PrestigeSource.CombatVictory)
    check value > 0
    check value == globalPrestigeConfig.military.fleet_victory

  test "Prestige values: task force destroyed":
    let value = getPrestigeValue(PrestigeSource.TaskForceDestroyed)
    check value > 0
    check value == globalPrestigeConfig.military.fleet_victory

  test "Prestige values: fleet retreated":
    let value = getPrestigeValue(PrestigeSource.FleetRetreated)
    check value > 0
    check value == globalPrestigeConfig.military.force_retreat

  test "Prestige values: squadron destroyed":
    let value = getPrestigeValue(PrestigeSource.SquadronDestroyed)
    check value > 0
    check value == globalPrestigeConfig.military.destroy_squadron

  test "Prestige values: colony seized":
    let value = getPrestigeValue(PrestigeSource.ColonySeized)
    check value > 0
    check value == globalPrestigeConfig.military.invade_planet

  test "Prestige values: colony established":
    let value = getPrestigeValue(PrestigeSource.ColonyEstablished)
    check value > 0
    check value == globalPrestigeConfig.economic.establish_colony

  test "Prestige values: tech advancement":
    let value = getPrestigeValue(PrestigeSource.TechAdvancement)
    check value > 0
    check value == globalPrestigeConfig.economic.tech_advancement

  test "Prestige values: house eliminated":
    let value = getPrestigeValue(PrestigeSource.Eliminated)
    check value > 0
    check value == globalPrestigeConfig.military.eliminate_house

  test "Prestige values: blockade penalty":
    let value = getPrestigeValue(PrestigeSource.BlockadePenalty)
    check value < 0  # Penalty should be negative
    check value == globalPrestigeConfig.penalties.blockade_penalty

  test "Prestige values: pact violation":
    let value = getPrestigeValue(PrestigeSource.PactViolation)
    check value < 0  # Penalty should be negative
    check value == globalPrestigeConfig.diplomacy.pact_violation

  # ==========================================================================
  # Prestige Event Creation Tests
  # ==========================================================================

  test "Create prestige event: positive amount":
    let event = createPrestigeEvent(
      PrestigeSource.CombatVictory,
      50,
      "Test victory"
    )

    check event.source == PrestigeSource.CombatVictory
    check event.amount == 50
    check event.description == "Test victory"

  test "Create prestige event: negative amount (penalty)":
    let event = createPrestigeEvent(
      PrestigeSource.HighTaxPenalty,
      -10,
      "Tax penalty"
    )

    check event.source == PrestigeSource.HighTaxPenalty
    check event.amount == -10
    check event.description == "Tax penalty"

  test "Calculate prestige change: multiple events":
    let events = @[
      createPrestigeEvent(PrestigeSource.CombatVictory, 50, "Victory"),
      createPrestigeEvent(PrestigeSource.SquadronDestroyed, 10, "Squadron"),
      createPrestigeEvent(PrestigeSource.HighTaxPenalty, -5, "Tax penalty")
    ]

    let change = calculatePrestigeChange(events)
    check change == 55  # 50 + 10 - 5

  test "Calculate prestige change: empty events":
    let events: seq[PrestigeEvent] = @[]
    let change = calculatePrestigeChange(events)
    check change == 0

  # ==========================================================================
  # Combat Prestige Tests
  # ==========================================================================

  test "Combat prestige: basic victory":
    let events = awardCombatPrestige(
      victor = "house1",
      defeated = "house2",
      taskForceDestroyed = false,
      squadronsDestroyed = 0,
      forcedRetreat = false
    )

    # Should have exactly 1 event for combat victory
    check events.len == 1
    check events[0].source == PrestigeSource.CombatVictory
    check events[0].amount == getPrestigeValue(PrestigeSource.CombatVictory)

  test "Combat prestige: victory with task force destroyed":
    let events = awardCombatPrestige(
      victor = "house1",
      defeated = "house2",
      taskForceDestroyed = true,
      squadronsDestroyed = 0,
      forcedRetreat = false
    )

    # Should have 2 events: victory + task force destroyed
    check events.len == 2
    check events[0].source == PrestigeSource.CombatVictory
    check events[1].source == PrestigeSource.TaskForceDestroyed

  test "Combat prestige: victory with squadrons destroyed":
    let events = awardCombatPrestige(
      victor = "house1",
      defeated = "house2",
      taskForceDestroyed = false,
      squadronsDestroyed = 3,
      forcedRetreat = false
    )

    # Should have 2 events: victory + squadrons
    check events.len == 2
    check events[0].source == PrestigeSource.CombatVictory
    check events[1].source == PrestigeSource.SquadronDestroyed

    # Squadron prestige = base value * count
    let expectedAmount = getPrestigeValue(PrestigeSource.SquadronDestroyed) * 3
    check events[1].amount == expectedAmount

  test "Combat prestige: victory with forced retreat":
    let events = awardCombatPrestige(
      victor = "house1",
      defeated = "house2",
      taskForceDestroyed = false,
      squadronsDestroyed = 0,
      forcedRetreat = true
    )

    # Should have 2 events: victory + retreat
    check events.len == 2
    check events[0].source == PrestigeSource.CombatVictory
    check events[1].source == PrestigeSource.FleetRetreated

  test "Combat prestige: total victory (all bonuses)":
    let events = awardCombatPrestige(
      victor = "house1",
      defeated = "house2",
      taskForceDestroyed = true,
      squadronsDestroyed = 5,
      forcedRetreat = true
    )

    # Should have 4 events: victory + task force + squadrons + retreat
    check events.len == 4
    check events[0].source == PrestigeSource.CombatVictory
    check events[1].source == PrestigeSource.TaskForceDestroyed
    check events[2].source == PrestigeSource.SquadronDestroyed
    check events[3].source == PrestigeSource.FleetRetreated

  # ==========================================================================
  # Tax Prestige Tests
  # ==========================================================================

  test "Tax prestige: 0-10% rate (+3 per colony)":
    let event = applyTaxPrestige("house1", colonyCount = 5, taxRate = 5)

    check event.source == PrestigeSource.LowTaxBonus
    check event.amount == 15  # 3 per colony * 5 colonies

  test "Tax prestige: 11-20% rate (+2 per colony)":
    let event = applyTaxPrestige("house1", colonyCount = 3, taxRate = 15)

    check event.source == PrestigeSource.LowTaxBonus
    check event.amount == 6  # 2 per colony * 3 colonies

  test "Tax prestige: 21-30% rate (+1 per colony)":
    let event = applyTaxPrestige("house1", colonyCount = 4, taxRate = 25)

    check event.source == PrestigeSource.LowTaxBonus
    check event.amount == 4  # 1 per colony * 4 colonies

  test "Tax prestige: 31-40% rate (0 bonus)":
    let event = applyTaxPrestige("house1", colonyCount = 10, taxRate = 35)

    check event.source == PrestigeSource.LowTaxBonus
    check event.amount == 0

  test "Tax prestige: 41%+ rate (0 bonus)":
    let event = applyTaxPrestige("house1", colonyCount = 10, taxRate = 50)

    check event.source == PrestigeSource.LowTaxBonus
    check event.amount == 0

  test "Tax prestige: boundary at 10%":
    let event10 = applyTaxPrestige("house1", 1, 10)
    let event11 = applyTaxPrestige("house1", 1, 11)

    check event10.amount == 3
    check event11.amount == 2

  test "Tax prestige: boundary at 20%":
    let event20 = applyTaxPrestige("house1", 1, 20)
    let event21 = applyTaxPrestige("house1", 1, 21)

    check event20.amount == 2
    check event21.amount == 1

  test "Tax prestige: boundary at 30%":
    let event30 = applyTaxPrestige("house1", 1, 30)
    let event31 = applyTaxPrestige("house1", 1, 31)

    check event30.amount == 1
    check event31.amount == 0

  # ==========================================================================
  # High Tax Penalty Tests
  # ==========================================================================

  test "High tax penalty: 0-50% average (no penalty)":
    let event = applyHighTaxPenalty("house1", avgTaxRate = 45)

    check event.source == PrestigeSource.HighTaxPenalty
    check event.amount == 0

  test "High tax penalty: 51-60% average (-1)":
    let event = applyHighTaxPenalty("house1", avgTaxRate = 55)

    check event.source == PrestigeSource.HighTaxPenalty
    check event.amount == -1

  test "High tax penalty: 61-70% average (-2)":
    let event = applyHighTaxPenalty("house1", avgTaxRate = 65)

    check event.source == PrestigeSource.HighTaxPenalty
    check event.amount == -2

  test "High tax penalty: 71-80% average (-4)":
    let event = applyHighTaxPenalty("house1", avgTaxRate = 75)

    check event.source == PrestigeSource.HighTaxPenalty
    check event.amount == -4

  test "High tax penalty: 81-90% average (-7)":
    let event = applyHighTaxPenalty("house1", avgTaxRate = 85)

    check event.source == PrestigeSource.HighTaxPenalty
    check event.amount == -7

  test "High tax penalty: 91-100% average (-11)":
    let event = applyHighTaxPenalty("house1", avgTaxRate = 95)

    check event.source == PrestigeSource.HighTaxPenalty
    check event.amount == -11

  test "High tax penalty: maximum at 100%":
    let event = applyHighTaxPenalty("house1", avgTaxRate = 100)

    check event.source == PrestigeSource.HighTaxPenalty
    check event.amount == -11

  # ==========================================================================
  # Blockade Penalty Tests
  # ==========================================================================

  test "Blockade penalty: single colony":
    let event = applyBlockadePenalty("house1", blockadedColonies = 1)

    check event.source == PrestigeSource.BlockadePenalty
    check event.amount < 0  # Penalty is negative
    check event.amount == getPrestigeValue(PrestigeSource.BlockadePenalty)

  test "Blockade penalty: multiple colonies":
    let event = applyBlockadePenalty("house1", blockadedColonies = 3)

    let basePenalty = getPrestigeValue(PrestigeSource.BlockadePenalty)
    check event.amount == basePenalty * 3

  test "Blockade penalty: no blockades":
    let event = applyBlockadePenalty("house1", blockadedColonies = 0)

    check event.amount == 0

  # ==========================================================================
  # Colony Prestige Tests
  # ==========================================================================

  test "Colony prestige: established":
    let event = awardColonyPrestige("house1", colonyType = "established")

    check event.source == PrestigeSource.ColonyEstablished
    check event.amount == getPrestigeValue(PrestigeSource.ColonyEstablished)
    check event.amount > 0

  test "Colony prestige: seized":
    let event = awardColonyPrestige("house1", colonyType = "seized")

    check event.source == PrestigeSource.ColonySeized
    check event.amount == getPrestigeValue(PrestigeSource.ColonySeized)
    check event.amount > 0

  # ==========================================================================
  # Tech Prestige Tests
  # ==========================================================================

  test "Tech prestige: advancement":
    let event = awardTechPrestige("house1", techField = "WEP", level = 5)

    check event.source == PrestigeSource.TechAdvancement
    check event.amount == getPrestigeValue(PrestigeSource.TechAdvancement)
    check event.amount > 0
    check event.description.contains("WEP")
    check event.description.contains("5")

  # ==========================================================================
  # Victory Condition Tests
  # ==========================================================================

  test "Victory: 5000 prestige threshold":
    check checkPrestigeVictory(5000) == true
    check checkPrestigeVictory(5001) == true
    check checkPrestigeVictory(10000) == true

  test "Victory: below threshold":
    check checkPrestigeVictory(4999) == false
    check checkPrestigeVictory(1000) == false
    check checkPrestigeVictory(0) == false

  test "Victory: threshold constant":
    check prestigeVictoryThreshold == 5000

  # ==========================================================================
  # Defensive Collapse Tests
  # ==========================================================================

  test "Defensive collapse: requires 3 turns below 0":
    # Not collapsed: positive prestige
    check checkDefensiveCollapse(100, turnsBelow = 3) == false

    # Not collapsed: negative but not 3 turns
    check checkDefensiveCollapse(-10, turnsBelow = 2) == false

    # Collapsed: negative for 3 turns
    check checkDefensiveCollapse(-10, turnsBelow = 3) == true

    # Collapsed: negative for more than 3 turns
    check checkDefensiveCollapse(-50, turnsBelow = 5) == true

  test "Defensive collapse: requires consecutive turns":
    # This test validates the tracking requirement
    # The actual consecutive tracking is done in gamestate
    check checkDefensiveCollapse(-5, turnsBelow = 0) == false
    check checkDefensiveCollapse(-5, turnsBelow = 1) == false
    check checkDefensiveCollapse(-5, turnsBelow = 2) == false
    check checkDefensiveCollapse(-5, turnsBelow = 3) == true

  test "Defensive collapse: exactly 0 prestige doesn't trigger":
    check checkDefensiveCollapse(0, turnsBelow = 3) == false

  # ==========================================================================
  # Morale ROE Modifier Tests
  # ==========================================================================

  test "Morale ROE: crisis (prestige <= 0)":
    check getMoraleROEModifier(-10) == -2
    check getMoraleROEModifier(0) == -2

  test "Morale ROE: low (prestige 1-20)":
    check getMoraleROEModifier(1) == -1
    check getMoraleROEModifier(10) == -1
    check getMoraleROEModifier(20) == -1

  test "Morale ROE: average/good (prestige 21-60)":
    check getMoraleROEModifier(21) == 0
    check getMoraleROEModifier(40) == 0
    check getMoraleROEModifier(60) == 0

  test "Morale ROE: high (prestige 61-80)":
    check getMoraleROEModifier(61) == +1
    check getMoraleROEModifier(70) == +1
    check getMoraleROEModifier(80) == +1

  test "Morale ROE: elite (prestige 81+)":
    check getMoraleROEModifier(81) == +2
    check getMoraleROEModifier(100) == +2
    check getMoraleROEModifier(1000) == +2

  test "Morale CER: same as ROE":
    # CER modifier uses same thresholds as ROE
    check getMoraleCERModifier(-10) == getMoraleROEModifier(-10)
    check getMoraleCERModifier(50) == getMoraleROEModifier(50)
    check getMoraleCERModifier(100) == getMoraleROEModifier(100)

  # ==========================================================================
  # Prestige Report Tests
  # ==========================================================================

  test "Prestige report: calculates ending prestige":
    let events = @[
      createPrestigeEvent(PrestigeSource.CombatVictory, 50, "Victory"),
      createPrestigeEvent(PrestigeSource.HighTaxPenalty, -10, "Tax")
    ]

    let report = createPrestigeReport("house1", startingPrestige = 1000, events)

    check report.houseId == "house1"
    check report.startingPrestige == 1000
    check report.events.len == 2
    check report.endingPrestige == 1040  # 1000 + 50 - 10

  test "Prestige report: no events":
    let events: seq[PrestigeEvent] = @[]
    let report = createPrestigeReport("house1", startingPrestige = 500, events)

    check report.startingPrestige == 500
    check report.endingPrestige == 500
    check report.events.len == 0

  test "Prestige report: negative ending prestige":
    let events = @[
      createPrestigeEvent(PrestigeSource.HighTaxPenalty, -100, "Major penalty")
    ]

    let report = createPrestigeReport("house1", startingPrestige = 50, events)

    check report.endingPrestige == -50

  # ==========================================================================
  # Integration Tests
  # ==========================================================================

  test "Full prestige cycle: combat to victory":
    var currentPrestige = 4950

    # Win a major battle
    let combatEvents = awardCombatPrestige(
      victor = "house1",
      defeated = "house2",
      taskForceDestroyed = true,
      squadronsDestroyed = 3,
      forcedRetreat = true
    )

    let combatChange = calculatePrestigeChange(combatEvents)
    currentPrestige += combatChange

    # Should push over 5000 threshold
    check currentPrestige >= 5000
    check checkPrestigeVictory(currentPrestige) == true

  test "Tax effects: low tax bonus offsets penalties":
    # Low tax bonus
    let bonus = applyTaxPrestige("house1", colonyCount = 10, taxRate = 10)
    check bonus.amount == 30  # +3 per colony

    # Small penalty from other source
    let penalty = createPrestigeEvent(PrestigeSource.BlockadePenalty, -10, "Blockade")

    let total = bonus.amount + penalty.amount
    check total == 20  # Net positive

  test "Defensive collapse scenario":
    var prestige = 100
    var turnsBelow = 0

    # Massive losses
    let events = @[
      createPrestigeEvent(PrestigeSource.HighTaxPenalty, -50, "Tax"),
      createPrestigeEvent(PrestigeSource.BlockadePenalty, -30, "Blockade"),
      createPrestigeEvent(PrestigeSource.MaintenanceShortfall, -40, "Maintenance")
    ]

    # Turn 1
    prestige += calculatePrestigeChange(events)
    check prestige < 0
    turnsBelow += 1
    check checkDefensiveCollapse(prestige, turnsBelow) == false

    # Turn 2
    prestige += calculatePrestigeChange(events)
    turnsBelow += 1
    check checkDefensiveCollapse(prestige, turnsBelow) == false

    # Turn 3 - collapse!
    prestige += calculatePrestigeChange(events)
    turnsBelow += 1
    check checkDefensiveCollapse(prestige, turnsBelow) == true
