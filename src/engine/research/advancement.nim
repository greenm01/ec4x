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
import ../config/prestige_config

export types.TechAdvancement, types.BreakthroughEvent, types.TechTree

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

## Upgrade Cycles (economy.md:4.1)

proc isUpgradeTurn*(turn: int): bool =
  ## Check if current turn is a research breakthrough cycle
  ## Breakthroughs occur every 6 strategic cycles
  return (turn mod 6) == 0

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
      tree.levels.economicLevel += 1
      result.category = ResearchCategory.Economic
    else:
      tree.levels.scienceLevel += 1
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

  # Check if already at max level
  if currentEL >= maxEconomicLevel:
    return none(TechAdvancement)

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

  # Check if already at max level
  if currentSL >= maxScienceLevel:
    return none(TechAdvancement)

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

    return some(TechAdvancement(
      houseId: "",  # Set by caller
      field: TechField.ScienceLevel,
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
    of TechField.ScienceLevel:
      tree.levels.scienceLevel
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
    of TechField.EconomicLevel: maxEconomicLevel
    of TechField.ScienceLevel: maxScienceLevel
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
    return none(TechAdvancement)

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
  of TechField.ScienceLevel:
    tree.levels.scienceLevel += 1
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

  return some(TechAdvancement(
    houseId: "",  # Set by caller
    field: field,
    fromLevel: currentLevel,
    toLevel: currentLevel + 1,
    cost: cost,
    prestigeEvent: some(prestigeEvent)
  ))
