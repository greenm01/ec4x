## Research Advancement
##
## Tech level progression and breakthroughs per economy.md:4.1
##
## Tech Upgrade Rules:
## - Can be purchased EVERY TURN if player has enough RP
## - Sequential order only (must buy level N before N+1)
## - No turn restrictions on purchases
##
## Research Breakthrough Rules:
## - Breakthrough rolls occur every 5 turns (turns 5, 10, 15, 20, etc.)
## - Base 5% chance (1 on d20) + 1% per 100 RP invested (last 5 turns)
## - Maximum 15% breakthrough chance (capped)
## - If successful, second d20 roll determines breakthrough type
## - Provides bonus RP, cost reductions, or free level advancements

import std/[random, tables, options]
import types, costs
import ../../common/types/tech
import ../prestige
import ../config/prestige_config

export types.ResearchAdvancement, types.AdvancementType, types.BreakthroughEvent, types.TechTree

## Maximum Tech Levels (economy.md:4.0)
## Caps prevent wasteful investment once maximum research levels reached

const
  maxEconomicLevel* = 11      # EL caps at 11 per economy.md:4.2
  maxScienceLevel* = 8        # SL caps at 8 per economy.md:4.3
  maxConstructionTech* = 15   # CST extended for long games
  maxWeaponsTech* = 15        # WEP extended for long games
  maxTerraformingTech* = 7    # TER limited to planet classes
  maxElectronicIntelligence* = 15  # ELI extended
  maxCloakingTech* = 15       # CLK extended
  maxShieldTech* = 15         # SLD extended
  maxCounterIntelligence* = 15  # CIC extended
  maxFighterDoctrine* = 3     # FD limited to 3 doctrines
  maxAdvancedCarrierOps* = 3  # ACO limited to 3 levels

## Breakthrough Cycles (economy.md:4.1.1)

proc isBreakthroughTurn*(turn: int): bool =
  ## Check if current turn allows research breakthrough rolls
  ## Per economy.md:4.1.1 - Breakthroughs occur every 5 turns
  ## Turns 5, 10, 15, 20, 25, etc.
  return (turn mod 5) == 0

## Research Breakthroughs (economy.md:4.1.1)

proc rollBreakthrough*(investedRP: int, rng: var Rand): Option[BreakthroughType] =
  ## Roll for research breakthrough
  ## Per economy.md:4.1.1
  ##
  ## Base chance: 5% (1 on d20)
  ## +1% per 100 RP invested (last 5 turns)
  ## Maximum 15% (capped)

  # Validate input - negative RP should not provide bonus
  let validRP = max(0, investedRP)

  # Calculate bonus and total chance
  let bonusPercent = float(validRP div 100)
  let totalPercent = min(5.0 + bonusPercent, 15.0)  # Cap at 15%

  # Roll d20 (1-20)
  let roll = rng.rand(1..20)

  # Convert percentage to number of successful rolls on d20
  # 5% = 1 success (roll 1), 10% = 2 successes (rolls 1-2), 15% = 3 successes (rolls 1-3)
  let successfulRolls = int(totalPercent / 5.0)  # Each 5% = 1 roll on d20

  if roll <= successfulRolls:
    # Success! Roll d20 for breakthrough type
    let typeRoll = rng.rand(1..20)

    if typeRoll <= 10:
      return some(BreakthroughType.Minor)        # 1-10: Minor (50%)
    elif typeRoll <= 15:
      return some(BreakthroughType.Moderate)     # 11-15: Moderate (25%)
    elif typeRoll <= 18:
      return some(BreakthroughType.Major)        # 16-18: Major (15%)
    else:
      return some(BreakthroughType.Revolutionary) # 19-20: Revolutionary (10%)

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
    # Applied via breakthrough.costReduction field (tracked in ResearchBreakthrough)
    # Caller applies this discount to next tech purchase
    result.costReduction = 0.8

  of BreakthroughType.Major:
    # Auto-advance EL or SL
    if allocation.economic > allocation.science:
      tree.levels.economicLevel += 1
      result.category = ResearchCategory.Economic
    else:
      tree.levels.scienceLevel += 1
      result.category = ResearchCategory.Science
    result.autoAdvance = true

  of BreakthroughType.Revolutionary:
    # Roll for revolutionary tech
    # NOTE: Revolutionary techs are rare, game-changing discoveries
    # Effects defined per tech type (QuantumComputing, etc.)
    # Implementation pending full revolutionary tech system design
    result.revolutionary = some(RevolutionaryTech.QuantumComputing)

## Tech Level Advancement

proc attemptELAdvancement*(tree: var TechTree, currentEL: int): Option[ResearchAdvancement] =
  ## Attempt to advance Economic Level
  ## Returns advancement if successful

  # Check if already at max level
  if currentEL >= maxEconomicLevel:
    return none(ResearchAdvancement)

  let cost = getELUpgradeCost(currentEL)

  if tree.accumulated.economic >= cost:
    # Spend RP
    tree.accumulated.economic -= cost

    # Advance level
    tree.levels.economicLevel = currentEL + 1

    # Create prestige event
    let config = globalPrestigeConfig
    let prestigeEvent = createPrestigeEvent(
      PrestigeSource.TechAdvancement,
      config.economic.tech_advancement,
      "Economic Level " & $currentEL & " → " & $(currentEL + 1)
    )

    return some(ResearchAdvancement(
      advancementType: AdvancementType.EconomicLevel,
      elFromLevel: currentEL,
      elToLevel: currentEL + 1,
      elCost: cost,
      houseId: "",  # Set by caller
      prestigeEvent: some(prestigeEvent)
    ))

  return none(ResearchAdvancement)

proc attemptSLAdvancement*(tree: var TechTree, currentSL: int): Option[ResearchAdvancement] =
  ## Attempt to advance Science Level
  ## Returns advancement if successful

  # Check if already at max level
  if currentSL >= maxScienceLevel:
    return none(ResearchAdvancement)

  let cost = getSLUpgradeCost(currentSL)

  if tree.accumulated.science >= cost:
    # Spend SRP
    tree.accumulated.science -= cost

    # Advance level
    tree.levels.scienceLevel = currentSL + 1

    # Create prestige event
    let config = globalPrestigeConfig
    let prestigeEvent = createPrestigeEvent(
      PrestigeSource.TechAdvancement,
      config.economic.tech_advancement,
      "Science Level " & $currentSL & " → " & $(currentSL + 1)
    )

    return some(ResearchAdvancement(
      advancementType: AdvancementType.ScienceLevel,
      slFromLevel: currentSL,
      slToLevel: currentSL + 1,
      slCost: cost,
      houseId: "",  # Set by caller
      prestigeEvent: some(prestigeEvent)
    ))

  return none(ResearchAdvancement)

proc attemptTechAdvancement*(tree: var TechTree, field: TechField): Option[ResearchAdvancement] =
  ## Attempt to advance specific tech field
  ## Returns advancement if successful
  ## Note: EL and SL use separate attemptELAdvancement/attemptSLAdvancement functions

  let currentLevel = case field
    of TechField.ConstructionTech:
      tree.levels.constructionTech
    of TechField.WeaponsTech:
      tree.levels.weaponsTech
    of TechField.TerraformingTech:
      tree.levels.terraformingTech
    of TechField.ElectronicIntelligence:
      tree.levels.electronicIntelligence
    of TechField.CloakingTech:
      tree.levels.cloakingTech
    of TechField.ShieldTech:
      tree.levels.shieldTech
    of TechField.CounterIntelligence:
      tree.levels.counterIntelligence
    of TechField.FighterDoctrine:
      tree.levels.fighterDoctrine
    of TechField.AdvancedCarrierOps:
      tree.levels.advancedCarrierOps

  # Check if already at max level
  let maxLevel = case field
    of TechField.ConstructionTech: maxConstructionTech
    of TechField.WeaponsTech: maxWeaponsTech
    of TechField.TerraformingTech: maxTerraformingTech
    of TechField.ElectronicIntelligence: maxElectronicIntelligence
    of TechField.CloakingTech: maxCloakingTech
    of TechField.ShieldTech: maxShieldTech
    of TechField.CounterIntelligence: maxCounterIntelligence
    of TechField.FighterDoctrine: maxFighterDoctrine
    of TechField.AdvancedCarrierOps: maxAdvancedCarrierOps

  if currentLevel >= maxLevel:
    return none(ResearchAdvancement)

  let cost = getTechUpgradeCost(field, currentLevel)

  # Check if enough TRP accumulated
  if field notin tree.accumulated.technology or tree.accumulated.technology[field] < cost:
    return none(ResearchAdvancement)

  # Spend TRP
  tree.accumulated.technology[field] -= cost

  # Advance level
  case field
  of TechField.ConstructionTech:
    tree.levels.constructionTech += 1
  of TechField.WeaponsTech:
    tree.levels.weaponsTech += 1
  of TechField.TerraformingTech:
    tree.levels.terraformingTech += 1
  of TechField.ElectronicIntelligence:
    tree.levels.electronicIntelligence += 1
  of TechField.CloakingTech:
    tree.levels.cloakingTech += 1
  of TechField.ShieldTech:
    tree.levels.shieldTech += 1
  of TechField.CounterIntelligence:
    tree.levels.counterIntelligence += 1
  of TechField.FighterDoctrine:
    tree.levels.fighterDoctrine += 1
  of TechField.AdvancedCarrierOps:
    tree.levels.advancedCarrierOps += 1

  # Create prestige event
  let config = globalPrestigeConfig
  let fieldName = $field
  let prestigeEvent = createPrestigeEvent(
    PrestigeSource.TechAdvancement,
    config.economic.tech_advancement,
    fieldName & " " & $currentLevel & " → " & $(currentLevel + 1)
  )

  return some(ResearchAdvancement(
    advancementType: AdvancementType.Technology,
    techField: field,
    techFromLevel: currentLevel,
    techToLevel: currentLevel + 1,
    techCost: cost,
    houseId: "",  # Set by caller
    prestigeEvent: some(prestigeEvent)
  ))
