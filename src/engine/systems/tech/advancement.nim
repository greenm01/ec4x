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
import costs, effects
import ../../types/[core, game_state, tech, prestige]
import ../../state/engine
import ../../globals

export
  tech.ResearchAdvancement, tech.AdvancementType, tech.BreakthroughEvent, tech.TechTree

## CST Tech Upgrade Helpers

proc updateSpaceportDocks(
    state: var GameState, spaceportId: SpaceportId, effectiveDocks: int32
) =
  ## Helper to update spaceport effective docks using DoD pattern
  let spaceportOpt = state.neoria(spaceportId)
  if spaceportOpt.isSome:
    var spaceport = spaceportOpt.get()
    spaceport.effectiveDocks = effectiveDocks
    state.updateNeoria(spaceportId, spaceport)

proc updateShipyardDocks(
    state: var GameState, shipyardId: ShipyardId, effectiveDocks: int32
) =
  ## Helper to update shipyard effective docks using DoD pattern
  let shipyardOpt = state.neoria(shipyardId)
  if shipyardOpt.isSome:
    var shipyard = shipyardOpt.get()
    shipyard.effectiveDocks = effectiveDocks
    state.updateNeoria(shipyardId, shipyard)

proc updateDrydockDocks(
    state: var GameState, drydockId: DrydockId, effectiveDocks: int32
) =
  ## Helper to update drydock effective docks using DoD pattern
  let drydockOpt = state.neoria(drydockId)
  if drydockOpt.isSome:
    var drydock = drydockOpt.get()
    drydock.effectiveDocks = effectiveDocks
    state.updateNeoria(drydockId, drydock)

proc applyDockCapacityUpgrade(state: var GameState, houseId: HouseId) =
  ## Recalculate all facility dock capacities when CST tech advances
  ## Called automatically after CST level increases
  ## Updates stored effectiveDocks values for all facilities owned by house

  # Get house's CST level
  let houseOpt = state.house(houseId)
  if houseOpt.isNone:
    return
  let house = houseOpt.get()
  let cstLevel = house.techTree.levels.cst

  # Iterate over all colonies owned by this house
  for colony in state.coloniesOwned(houseId):

    # Update spaceport capacities
    for spaceportId in colony.spaceportIds:
      let spaceportOpt = state.neoria(spaceportId)
      if spaceportOpt.isNone:
        continue
      let spaceport = spaceportOpt.get()
      let newDocks =
        int32(effects.calculateEffectiveDocks(spaceport.baseDocks, cstLevel))
      updateSpaceportDocks(state, spaceportId, newDocks)

    # Update shipyard capacities
    for shipyardId in colony.shipyardIds:
      let shipyardOpt = state.neoria(shipyardId)
      if shipyardOpt.isNone:
        continue
      let shipyard = shipyardOpt.get()
      let newDocks =
        int32(effects.calculateEffectiveDocks(shipyard.baseDocks, cstLevel))
      updateShipyardDocks(state, shipyardId, newDocks)

    # Update drydock capacities
    for drydockId in colony.drydockIds:
      let drydockOpt = state.neoria(drydockId)
      if drydockOpt.isNone:
        continue
      let drydock = drydockOpt.get()
      let newDocks = int32(effects.calculateEffectiveDocks(drydock.baseDocks, cstLevel))
      updateDrydockDocks(state, drydockId, newDocks)

## Maximum Tech Levels (economy.md:4.0)
## Caps prevent wasteful investment once maximum research levels reached

const
  maxEconomicLevel* = 11 # EL caps at 11 per economy.md:4.2
  maxScienceLevel* = 8 # SL caps at 8 per economy.md:4.3
  maxConstructionTech* = 15 # CST extended for long games
  maxWeaponsTech* = 15 # WEP extended for long games
  maxTerraformingTech* = 7 # TER limited to planet classes
  maxElectronicIntelligence* = 15 # ELI extended
  maxCloakingTech* = 15 # CLK extended
  maxShieldTech* = 15 # SLD extended
  maxCounterIntelligence* = 15 # CIC extended
  maxStrategicLiftTech* = 15 # STL extended for long games
  maxFlagshipCommandTech* = 6 # FC limited to 6 levels
  maxStrategicCommandTech* = 5 # SC limited to 5 levels
  maxFighterDoctrine* = 3 # FD limited to 3 doctrines
  maxAdvancedCarrierOps* = 3 # ACO limited to 3 levels

## Breakthrough Cycles (economy.md:4.1.1)

proc isBreakthroughTurn*(turn: int): bool =
  ## Check if current turn allows research breakthrough rolls
  ## Per economy.md:4.1.1 - Breakthroughs occur every 5 turns
  ## Turns 5, 10, 15, 20, 25, etc.
  return (turn mod 5) == 0

## Research Breakthroughs (economy.md:4.1.1)

proc rollBreakthrough*(rng: var Rand): Option[BreakthroughType] =
  ## Roll for research breakthrough
  ## Per economy.md:4.1.1
  ##
  ## Base chance: 5% (1 on d20)

  # Roll d20 (1-20)
  let roll = rng.rand(1 .. 20)

  # Convert percentage to number of successful rolls on d20
  # 5% = 1 success (roll 1), 10% = 2 successes (rolls 1-2), 15% = 3 successes (rolls 1-3)
  let successfulRolls = 1

  if roll <= successfulRolls:
    # Success! Roll d20 for breakthrough type
    let typeRoll = rng.rand(1 .. 20)

    if typeRoll <= 10:
      return some(BreakthroughType.Minor) # 1-10: Minor (50%)
    elif typeRoll <= 15:
      return some(BreakthroughType.Moderate) # 11-15: Moderate (25%)
    elif typeRoll <= 18:
      return some(BreakthroughType.Major) # 16-18: Major (15%)
    else:
      return some(BreakthroughType.Revolutionary) # 19-20: Revolutionary (10%)

  return none(BreakthroughType)

proc applyBreakthrough*(
    tree: var TechTree, breakthrough: BreakthroughType, allocation: ResearchAllocation
): BreakthroughEvent =
  ## Apply breakthrough effect to tech tree
  ## Returns event for reporting

  result = BreakthroughEvent(
    houseId: HouseId(0), # Set by caller
    turn: int32(0), # Set by caller
    breakthroughType: breakthrough,
    category: ResearchCategory.Economic, # Default, may vary
    amount: int32(0),
    costReduction: float32(1.0),
    autoAdvance: false,
    revolutionary: none(RevolutionaryTech),
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
      tree.levels.el += 1
      result.category = ResearchCategory.Economic
    else:
      tree.levels.sl += 1
      result.category = ResearchCategory.Science
    result.autoAdvance = true
  of BreakthroughType.Revolutionary:
    # Roll for revolutionary tech
    # NOTE: Revolutionary techs are rare, game-changing discoveries
    # Effects defined per tech type (QuantumComputing, etc.)
    # Implementation pending full revolutionary tech system design
    result.revolutionary = some(RevolutionaryTech.QuantumComputing)

## Tech Level Advancement

proc attemptELAdvancement*(
    tree: var TechTree, currentEL: int
): Option[ResearchAdvancement] =
  ## Attempt to advance Economic Level
  ## Returns advancement if successful

  # Check if already at max level
  if currentEL >= maxEconomicLevel:
    return none(ResearchAdvancement)

  let cost = getELUpgradeCost(int32(currentEL))

  if tree.accumulated.economic >= int32(cost):
    # Spend RP
    tree.accumulated.economic -= int32(cost)

    # Advance level
    tree.levels.el = int32(currentEL + 1)

    # Create prestige event
    let prestigeAmount = gameConfig.prestige.economic.techAdvancement
    let prestigeEvent = PrestigeEvent(
      source: PrestigeSource.TechAdvancement,
      amount: prestigeAmount,
      description: "Economic Level " & $currentEL & " → " & $(currentEL + 1),
    )

    return some(
      ResearchAdvancement(
        advancementType: AdvancementType.EconomicLevel,
        elFromLevel: int32(currentEL),
        elToLevel: int32(currentEL + 1),
        elCost: int32(cost),
        houseId: HouseId(0), # Set by caller
        prestigeEvent: some(prestigeEvent),
      )
    )

  return none(ResearchAdvancement)

proc attemptSLAdvancement*(
    tree: var TechTree, currentSL: int
): Option[ResearchAdvancement] =
  ## Attempt to advance Science Level
  ## Returns advancement if successful

  # Check if already at max level
  if currentSL >= maxScienceLevel:
    return none(ResearchAdvancement)

  let cost = getSLUpgradeCost(int32(currentSL))

  if tree.accumulated.science >= int32(cost):
    # Spend SRP
    tree.accumulated.science -= int32(cost)

    # Advance level
    tree.levels.sl = int32(currentSL + 1)

    # Create prestige event
    let prestigeAmount = gameConfig.prestige.economic.techAdvancement
    let prestigeEvent = PrestigeEvent(
      source: PrestigeSource.TechAdvancement,
      amount: prestigeAmount,
      description: "Science Level " & $currentSL & " → " & $(currentSL + 1),
    )

    return some(
      ResearchAdvancement(
        advancementType: AdvancementType.ScienceLevel,
        slFromLevel: int32(currentSL),
        slToLevel: int32(currentSL + 1),
        slCost: int32(cost),
        houseId: HouseId(0), # Set by caller
        prestigeEvent: some(prestigeEvent),
      )
    )

  return none(ResearchAdvancement)

proc attemptTechAdvancement*(
    state: var GameState, houseId: HouseId, tree: var TechTree, field: TechField
): Option[ResearchAdvancement] =
  ## Attempt to advance specific tech field
  ## Returns advancement if successful
  ## Note: EL and SL use separate attemptELAdvancement/attemptSLAdvancement functions

  let currentLevel =
    case field
    of TechField.ConstructionTech: tree.levels.cst
    of TechField.WeaponsTech: tree.levels.wep
    of TechField.TerraformingTech: tree.levels.ter
    of TechField.ElectronicIntelligence: tree.levels.eli
    of TechField.CloakingTech: tree.levels.clk
    of TechField.ShieldTech: tree.levels.sld
    of TechField.CounterIntelligence: tree.levels.cic
    of TechField.StrategicLiftTech: tree.levels.stl
    of TechField.FlagshipCommandTech: tree.levels.fc
    of TechField.StrategicCommandTech: tree.levels.sc
    of TechField.FighterDoctrine: tree.levels.fd
    of TechField.AdvancedCarrierOps: tree.levels.aco

  # Check if already at max level
  let maxLevel =
    case field
    of TechField.ConstructionTech: maxConstructionTech
    of TechField.WeaponsTech: maxWeaponsTech
    of TechField.TerraformingTech: maxTerraformingTech
    of TechField.ElectronicIntelligence: maxElectronicIntelligence
    of TechField.CloakingTech: maxCloakingTech
    of TechField.ShieldTech: maxShieldTech
    of TechField.CounterIntelligence: maxCounterIntelligence
    of TechField.StrategicLiftTech: maxStrategicLiftTech
    of TechField.FlagshipCommandTech: maxFlagshipCommandTech
    of TechField.StrategicCommandTech: maxStrategicCommandTech
    of TechField.FighterDoctrine: maxFighterDoctrine
    of TechField.AdvancedCarrierOps: maxAdvancedCarrierOps

  if currentLevel >= maxLevel:
    return none(ResearchAdvancement)

  let cost = getTechUpgradeCost(field, currentLevel)

  # Check if enough TRP accumulated
  if field notin tree.accumulated.technology or
      tree.accumulated.technology[field] < int32(cost):
    return none(ResearchAdvancement)

  # Spend TRP
  tree.accumulated.technology[field] -= int32(cost)

  # Advance level
  case field
  of TechField.ConstructionTech:
    tree.levels.cst += 1
    # Recalculate facility dock capacities for new CST level
    applyDockCapacityUpgrade(state, houseId)
  of TechField.WeaponsTech:
    tree.levels.wep += 1
  of TechField.TerraformingTech:
    tree.levels.ter += 1
  of TechField.ElectronicIntelligence:
    tree.levels.eli += 1
  of TechField.CloakingTech:
    tree.levels.clk += 1
  of TechField.ShieldTech:
    tree.levels.sld += 1
  of TechField.CounterIntelligence:
    tree.levels.cic += 1
  of TechField.StrategicLiftTech:
    tree.levels.stl += 1
  of TechField.FlagshipCommandTech:
    tree.levels.fc += 1
  of TechField.StrategicCommandTech:
    tree.levels.sc += 1
  of TechField.FighterDoctrine:
    tree.levels.fd += 1
  of TechField.AdvancedCarrierOps:
    tree.levels.aco += 1

  # Create prestige event
  let prestigeAmount = gameConfig.prestige.economic.techAdvancement
  let fieldName = $field
  let prestigeEvent = PrestigeEvent(
    source: PrestigeSource.TechAdvancement,
    amount: prestigeAmount,
    description: fieldName & " " & $currentLevel & " → " & $(currentLevel + 1),
  )

  return some(
    ResearchAdvancement(
      advancementType: AdvancementType.Technology,
      techField: field,
      techFromLevel: int32(currentLevel),
      techToLevel: int32(currentLevel + 1),
      techCost: int32(cost),
      houseId: HouseId(0), # Set by caller
      prestigeEvent: some(prestigeEvent),
    )
  )
