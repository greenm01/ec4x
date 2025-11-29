## Integration test for research prestige
##
## Tests that tech advancements generate prestige events

import std/[unittest, tables, options, strutils]
import ../../src/engine/research/[types, advancement, costs]
import ../../src/engine/prestige
import ../../src/engine/config/[prestige_config, prestige_multiplier]
import ../../src/common/types/tech

suite "Research Prestige Integration":

  test "Economic Level advancement generates prestige":
    var tree = initTechTree()  # Uses initDefaultTechLevel() - all tech starts at 1

    # Add enough ERP for EL2
    let cost = getELUpgradeCost(1)
    tree.accumulated.economic = cost

    # Attempt advancement
    let advOpt = attemptELAdvancement(tree, 1)

    check advOpt.isSome
    let adv = advOpt.get()
    check adv.advancementType == AdvancementType.EconomicLevel
    check adv.elFromLevel == 1
    check adv.elToLevel == 2
    check adv.prestigeEvent.isSome

    let prestigeEvent = adv.prestigeEvent.get()
    check prestigeEvent.source == PrestigeSource.TechAdvancement
    check prestigeEvent.amount == applyMultiplier(globalPrestigeConfig.economic.tech_advancement)
    check prestigeEvent.description.contains("Economic Level")

  test "Science Level advancement generates prestige":
    var tree = initTechTree()  # Uses initDefaultTechLevel() - all tech starts at 1

    # Add enough SRP for SL2
    let cost = getSLUpgradeCost(1)
    tree.accumulated.science = cost

    # Attempt advancement
    let advOpt = attemptSLAdvancement(tree, 1)

    check advOpt.isSome
    let adv = advOpt.get()
    check adv.advancementType == AdvancementType.ScienceLevel
    check adv.slFromLevel == 1
    check adv.slToLevel == 2
    check adv.prestigeEvent.isSome

    let prestigeEvent = adv.prestigeEvent.get()
    check prestigeEvent.source == PrestigeSource.TechAdvancement
    check prestigeEvent.amount == applyMultiplier(globalPrestigeConfig.economic.tech_advancement)
    check prestigeEvent.description.contains("Science Level")

  test "Tech field advancement generates prestige":
    var tree = initTechTree()  # Uses initDefaultTechLevel() - all tech starts at 1

    # Add enough TRP for WEP2 (advancing from 1 to 2)
    let field = TechField.WeaponsTech
    let cost = getTechUpgradeCost(field, 1)
    tree.accumulated.technology[field] = cost

    # Attempt advancement
    let advOpt = attemptTechAdvancement(tree, field)

    check advOpt.isSome
    let adv = advOpt.get()
    check adv.advancementType == AdvancementType.Technology
    check adv.techField == field
    check adv.techFromLevel == 1
    check adv.techToLevel == 2
    check adv.prestigeEvent.isSome

    let prestigeEvent = adv.prestigeEvent.get()
    check prestigeEvent.source == PrestigeSource.TechAdvancement
    check prestigeEvent.amount == applyMultiplier(globalPrestigeConfig.economic.tech_advancement)
    check prestigeEvent.description.contains("WeaponsTech")

  test "Multiple tech advancements accumulate prestige":
    var tree = initTechTree()  # Uses initDefaultTechLevel() - all tech starts at 1

    var totalPrestige = 0
    let config = globalPrestigeConfig

    # Advance EL
    tree.accumulated.economic = getELUpgradeCost(1)
    let elAdv = attemptELAdvancement(tree, 1)
    if elAdv.isSome and elAdv.get().prestigeEvent.isSome:
      totalPrestige += elAdv.get().prestigeEvent.get().amount

    # Advance SL
    tree.accumulated.science = getSLUpgradeCost(1)
    let slAdv = attemptSLAdvancement(tree, 1)
    if slAdv.isSome and slAdv.get().prestigeEvent.isSome:
      totalPrestige += slAdv.get().prestigeEvent.get().amount

    # Advance WEP (from 1 to 2)
    tree.accumulated.technology[TechField.WeaponsTech] = getTechUpgradeCost(TechField.WeaponsTech, 1)
    let wepAdv = attemptTechAdvancement(tree, TechField.WeaponsTech)
    if wepAdv.isSome and wepAdv.get().prestigeEvent.isSome:
      totalPrestige += wepAdv.get().prestigeEvent.get().amount

    # Should have 3 advancements × prestige each (with multiplier applied)
    check totalPrestige == applyMultiplier(config.economic.tech_advancement) * 3

  test "No advancement when insufficient RP":
    var tree = initTechTree()  # Uses initDefaultTechLevel() - all tech starts at 1

    # Not enough ERP
    tree.accumulated.economic = 10

    let advOpt = attemptELAdvancement(tree, 1)
    check advOpt.isNone
