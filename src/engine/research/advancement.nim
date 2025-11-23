## Research Advancement
##
## Tech level progression and breakthroughs per economy.md:4.1
##
## Advancement rules:
## - Levels purchased on turns 1 and 7 (bi-annual)
## - Sequential order only (must buy level N before N+1)
## - One level per field per upgrade cycle
## - Breakthroughs rolled bi-annually (10% base + investment bonus)

import std/[random, tables, options]
import types, costs
import ../../common/types/tech
import ../prestige
import ../config/[prestige_config, tech_config]

export types.TechAdvancement, types.BreakthroughEvent, types.TechTree

## Upgrade Cycles (economy.md:4.1)

proc isUpgradeTurn*(turn: int): bool =
  ## Check if current turn is an upgrade turn
  ## Per economy.md:4.1: Turns 1 and 7 of each year (months 1 and 7)
  let month = ((turn - 1) mod 13) + 1
  return month in RESEARCH_UPGRADE_TURNS

## Research Breakthroughs (economy.md:4.1.1)

proc rollBreakthrough*(investedRP: int, rng: var Rand): Option[BreakthroughType] =
  ## Roll for research breakthrough
  ## Per economy.md:4.1.1
  ##
  ## Base chance: 10%
  ## +1% per 50 RP invested (last 6 turns)

  let bonusChance = float(investedRP div 50) * BREAKTHROUGH_BONUS_PER_50RP
  let totalChance = BASE_BREAKTHROUGH_CHANCE + bonusChance

  # Roll d10 (0-9)
  let roll = rng.rand(9)
  let threshold = int(totalChance * 10.0)

  if roll < threshold:
    # Success! Roll for breakthrough type
    let typeRoll = rng.rand(9)

    if typeRoll <= 4:
      return some(BreakthroughType.Minor)
    elif typeRoll <= 6:
      return some(BreakthroughType.Moderate)
    elif typeRoll <= 8:
      return some(BreakthroughType.Major)
    else:
      return some(BreakthroughType.Revolutionary)

  return none(BreakthroughType)

proc applyBreakthrough*(tree: var TechTree, breakthrough: BreakthroughType,
                       allocation: ResearchAllocation): BreakthroughEvent =
  ## Apply breakthrough effect to tech tree
  ## Returns event for reporting

  result = BreakthroughEvent(
    houseId: "",  # Set by caller
    turn: 0,      # Set by caller
    breakthroughType: breakthrough,
    category: ResearchCategory.Economic,  # Default, may vary
    amount: 0,
    costReduction: 1.0,
    autoAdvance: false,
    revolutionary: none(RevolutionaryTech)
  )

  case breakthrough
  of BreakthroughType.Minor:
    # +10 RP to highest investment category
    if allocation.economic > allocation.science:
      tree.accumulated.economic += 10
      result.category = ResearchCategory.Economic
    else:
      tree.accumulated.science += 10
      result.category = ResearchCategory.Science
    result.amount = 10

  of BreakthroughType.Moderate:
    # 20% cost reduction for next tech upgrade
    # TODO: Apply to next TRP purchase
    result.costReduction = 0.8

  of BreakthroughType.Major:
    # Auto-advance EL or SL
    if allocation.economic > allocation.science:
      tree.levels.economicLevel += 1  # TODO: Should be EL not energy
      result.category = ResearchCategory.Economic
    else:
      tree.levels.shieldLevel += 1  # TODO: Should be SL not shield
      result.category = ResearchCategory.Science
    result.autoAdvance = true

  of BreakthroughType.Revolutionary:
    # Roll for revolutionary tech
    # TODO: Implement revolutionary tech effects
    result.revolutionary = some(RevolutionaryTech.QuantumComputing)

## Tech Level Advancement

proc attemptELAdvancement*(tree: var TechTree, currentEL: int): Option[TechAdvancement] =
  ## Attempt to advance Economic Level
  ## Returns advancement if successful

  let cost = getELUpgradeCost(currentEL)

  if tree.accumulated.economic >= cost:
    # Spend RP
    tree.accumulated.economic -= cost

    # Advance level
    # TODO: Proper EL field (currently using economicLevel as placeholder)
    tree.levels.economicLevel = currentEL + 1

    # Create prestige event
    let config = globalPrestigeConfig
    let prestigeEvent = createPrestigeEvent(
      PrestigeSource.TechAdvancement,
      config.economic.tech_advancement,
      "Economic Level " & $currentEL & " → " & $(currentEL + 1)
    )

    return some(TechAdvancement(
      houseId: "",  # Set by caller
      field: TechField.EconomicLevel,  # TODO: Separate EL from tech fields
      fromLevel: currentEL,
      toLevel: currentEL + 1,
      cost: cost,
      prestigeEvent: some(prestigeEvent)
    ))

  return none(TechAdvancement)

proc attemptSLAdvancement*(tree: var TechTree, currentSL: int): Option[TechAdvancement] =
  ## Attempt to advance Science Level
  ## Returns advancement if successful

  let cost = getSLUpgradeCost(currentSL)

  if tree.accumulated.science >= cost:
    # Spend SRP
    tree.accumulated.science -= cost

    # Advance level
    # TODO: Proper SL field (currently using shieldLevel as placeholder)
    tree.levels.shieldLevel = currentSL + 1

    # Create prestige event
    let config = globalPrestigeConfig
    let prestigeEvent = createPrestigeEvent(
      PrestigeSource.TechAdvancement,
      config.economic.tech_advancement,
      "Science Level " & $currentSL & " → " & $(currentSL + 1)
    )

    return some(TechAdvancement(
      houseId: "",  # Set by caller
      field: TechField.ShieldLevel,  # TODO: Separate SL from tech fields
      fromLevel: currentSL,
      toLevel: currentSL + 1,
      cost: cost,
      prestigeEvent: some(prestigeEvent)
    ))

  return none(TechAdvancement)

proc attemptTechAdvancement*(tree: var TechTree, field: TechField): Option[TechAdvancement] =
  ## Attempt to advance specific tech field
  ## Returns advancement if successful

  let currentLevel = case field
    of TechField.EconomicLevel:
      tree.levels.economicLevel
    of TechField.ShieldLevel:
      tree.levels.shieldLevel
    of TechField.ConstructionTech:
      tree.levels.constructionTech
    of TechField.WeaponsTech:
      tree.levels.weaponsTech
    of TechField.TerraformingTech:
      tree.levels.terraformingTech
    of TechField.ElectronicIntelligence:
      tree.levels.electronicIntelligence
    of TechField.CounterIntelligence:
      tree.levels.counterIntelligence

  let cost = getTechUpgradeCost(field, currentLevel)

  # Check if enough TRP accumulated
  if field notin tree.accumulated.technology or tree.accumulated.technology[field] < cost:
    return none(TechAdvancement)

  # Spend TRP
  tree.accumulated.technology[field] -= cost

  # Advance level
  case field
  of TechField.EconomicLevel:
    tree.levels.economicLevel += 1
  of TechField.ShieldLevel:
    tree.levels.shieldLevel += 1
  of TechField.ConstructionTech:
    tree.levels.constructionTech += 1
  of TechField.WeaponsTech:
    tree.levels.weaponsTech += 1
  of TechField.TerraformingTech:
    tree.levels.terraformingTech += 1
  of TechField.ElectronicIntelligence:
    tree.levels.electronicIntelligence += 1
  of TechField.CounterIntelligence:
    tree.levels.counterIntelligence += 1

  # Create prestige event
  let config = globalPrestigeConfig
  let fieldName = $field
  let prestigeEvent = createPrestigeEvent(
    PrestigeSource.TechAdvancement,
    config.economic.tech_advancement,
    fieldName & " " & $currentLevel & " → " & $(currentLevel + 1)
  )

  return some(TechAdvancement(
    houseId: "",  # Set by caller
    field: field,
    fromLevel: currentLevel,
    toLevel: currentLevel + 1,
    cost: cost,
    prestigeEvent: some(prestigeEvent)
  ))
