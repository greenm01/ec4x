## Integration test for research prestige
##
## Tests that tech advancements generate prestige events

import std/[unittest, tables, options, strutils]
import ../../src/engine/research/[types, advancement, costs]
import ../../src/engine/prestige
import ../../src/engine/config/prestige_config
import ../../src/common/types/tech

suite "Research Prestige Integration":

  test "Economic Level advancement generates prestige":
    var tree = initTechTree(TechLevel(
      economicLevel: 1,
      shieldLevel: 1,
      constructionTech: 0,
      weaponsTech: 0,
      terraformingTech: 0,
      electronicIntelligence: 0,
      counterIntelligence: 0
    ))

    # Add enough ERP for EL2
    let cost = getELUpgradeCost(1)
    tree.accumulated.economic = cost

    # Attempt advancement
    let advOpt = attemptELAdvancement(tree, 1)

    check advOpt.isSome
    let adv = advOpt.get()
    check adv.fromLevel == 1
    check adv.toLevel == 2
    check adv.prestigeEvent.isSome

    let prestigeEvent = adv.prestigeEvent.get()
    check prestigeEvent.source == PrestigeSource.TechAdvancement
    check prestigeEvent.amount == globalPrestigeConfig.economic.tech_advancement
    check prestigeEvent.description.contains("Economic Level")

  test "Science Level advancement generates prestige":
    var tree = initTechTree(TechLevel(
      economicLevel: 1,
      shieldLevel: 1,
      constructionTech: 0,
      weaponsTech: 0,
      terraformingTech: 0,
      electronicIntelligence: 0,
      counterIntelligence: 0
    ))

    # Add enough SRP for SL2
    let cost = getSLUpgradeCost(1)
    tree.accumulated.science = cost

    # Attempt advancement
    let advOpt = attemptSLAdvancement(tree, 1)

    check advOpt.isSome
    let adv = advOpt.get()
    check adv.fromLevel == 1
    check adv.toLevel == 2
    check adv.prestigeEvent.isSome

    let prestigeEvent = adv.prestigeEvent.get()
    check prestigeEvent.source == PrestigeSource.TechAdvancement
    check prestigeEvent.amount == globalPrestigeConfig.economic.tech_advancement
    check prestigeEvent.description.contains("Science Level")

  test "Tech field advancement generates prestige":
    var tree = initTechTree(TechLevel(
      economicLevel: 1,
      shieldLevel: 1,
      constructionTech: 0,
      weaponsTech: 0,
      terraformingTech: 0,
      electronicIntelligence: 0,
      counterIntelligence: 0
    ))

    # Add enough TRP for WEP1
    let field = TechField.WeaponsTech
    let cost = getTechUpgradeCost(field, 0)
    tree.accumulated.technology[field] = cost

    # Attempt advancement
    let advOpt = attemptTechAdvancement(tree, field)

    check advOpt.isSome
    let adv = advOpt.get()
    check adv.field == field
    check adv.fromLevel == 0
    check adv.toLevel == 1
    check adv.prestigeEvent.isSome

    let prestigeEvent = adv.prestigeEvent.get()
    check prestigeEvent.source == PrestigeSource.TechAdvancement
    check prestigeEvent.amount == globalPrestigeConfig.economic.tech_advancement
    check prestigeEvent.description.contains("WeaponsTech")

  test "Multiple tech advancements accumulate prestige":
    var tree = initTechTree(TechLevel(
      economicLevel: 1,
      shieldLevel: 1,
      constructionTech: 0,
      weaponsTech: 0,
      terraformingTech: 0,
      electronicIntelligence: 0,
      counterIntelligence: 0
    ))

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

    # Advance WEP
    tree.accumulated.technology[TechField.WeaponsTech] = getTechUpgradeCost(TechField.WeaponsTech, 0)
    let wepAdv = attemptTechAdvancement(tree, TechField.WeaponsTech)
    if wepAdv.isSome and wepAdv.get().prestigeEvent.isSome:
      totalPrestige += wepAdv.get().prestigeEvent.get().amount

    # Should have 3 advancements × 2 prestige each
    check totalPrestige == config.economic.tech_advancement * 3

  test "No advancement when insufficient RP":
    var tree = initTechTree(TechLevel(
      economicLevel: 1,
      shieldLevel: 1,
      constructionTech: 0,
      weaponsTech: 0,
      terraformingTech: 0,
      electronicIntelligence: 0,
      counterIntelligence: 0
    ))

    # Not enough ERP
    tree.accumulated.economic = 10

    let advOpt = attemptELAdvancement(tree, 1)
    check advOpt.isNone
