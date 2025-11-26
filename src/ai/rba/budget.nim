## Budget Allocation System for EC4X Rule-Based AI
##
## Multi-objective resource allocation based on game phase and personality.
## Prevents resource starvation by guaranteeing budget to each objective.
##
## Based on research:
## - MOEA for build order optimization (AAAI 2020)
## - Stellaris weight-based AI system
## - Priority-based task assignment (Game Developer 2015)

import std/[tables, options, algorithm, strformat]
import ../common/types
import ../../engine/[gamestate, orders, fleet, logger, fog_of_war]
import ../../engine/economy/construction  # For getShipConstructionCost
import ../../common/types/[core, units]

# =============================================================================
# Budget Allocation by Game Act
# =============================================================================

proc allocateBudget*(act: GameAct, personality: AIPersonality,
                     isUnderThreat: bool = false): BudgetAllocation =
  ## Calculate budget allocation percentages based on game act and personality
  ##
  ## Returns percentage allocation that sums to 1.0

  result = case act
    of GameAct.Act1_LandGrab:
      # Focus: Rapid expansion, minimal military
      {
        Expansion: 0.60,
        Defense: 0.10,
        Military: 0.10,
        Intelligence: 0.15,
        SpecialUnits: 0.05,
        Technology: 0.00
      }.toTable()

    of GameAct.Act2_RisingTensions:
      # CRITICAL TRANSITION: Military buildup begins
      # INVASION PREP: Need transports for aggressive AIs
      {
        Expansion: 0.20,     # Reduced: Colonization slowing down
        Defense: 0.15,
        Military: 0.35,      # Reduced from 40% to make room for transports
        Intelligence: 0.10,
        SpecialUnits: 0.15,  # ← INCREASED from 5% to 15% for transport production
        Technology: 0.05
      }.toTable()

    of GameAct.Act3_TotalWar:
      # Focus: Conquest and invasion
      {
        Expansion: 0.00,     # No more colonization
        Defense: 0.15,
        Military: 0.55,      # ← 55% to military + invasions
        Intelligence: 0.05,
        SpecialUnits: 0.15,  # Transports for invasions
        Technology: 0.10
      }.toTable()

    of GameAct.Act4_Endgame:
      # Focus: All-in for victory
      {
        Expansion: 0.00,
        Defense: 0.10,
        Military: 0.60,
        Intelligence: 0.05,
        SpecialUnits: 0.15,
        Technology: 0.10
      }.toTable()

  # Personality modifiers (max ±15% shift)
  let aggressionMod = (personality.aggression - 0.5) * 0.30  # -0.15 to +0.15
  let economicMod = (personality.economicFocus - 0.5) * 0.20  # -0.10 to +0.10

  # Aggressive personalities: More military, less expansion
  if aggressionMod > 0.0:
    result[Military] = min(0.80, result[Military] + aggressionMod)
    result[Expansion] = max(0.0, result[Expansion] - aggressionMod * 0.7)

  # Economic personalities: More expansion, less military (Act 1-2 only)
  if economicMod > 0.0 and act in {GameAct.Act1_LandGrab, GameAct.Act2_RisingTensions}:
    result[Expansion] = min(0.75, result[Expansion] + economicMod)
    result[Military] = max(0.10, result[Military] - economicMod * 0.5)

  # Under threat: Emergency military boost
  if isUnderThreat:
    let emergencyBoost = 0.20
    result[Military] = min(0.85, result[Military] + emergencyBoost)
    result[Expansion] = max(0.0, result[Expansion] - emergencyBoost * 0.7)
    result[SpecialUnits] = max(0.0, result[SpecialUnits] - emergencyBoost * 0.3)

  # Normalize to ensure sum = 1.0
  var total = 0.0
  for val in result.values:
    total += val

  if total != 1.0:
    for key in result.keys:
      result[key] = result[key] / total

proc calculateObjectiveBudgets*(treasury: int, allocation: BudgetAllocation): Table[BuildObjective, int] =
  ## Convert percentage allocation to actual PP budgets
  result = initTable[BuildObjective, int]()

  for objective, percentage in allocation:
    result[objective] = int(float(treasury) * percentage)

# =============================================================================
# Build Order Generation by Objective
# =============================================================================

proc buildExpansionOrders*(colony: Colony, budgetPP: int,
                          needETACs: bool, hasShipyard: bool): seq[BuildOrder] =
  ## Generate expansion-related build orders (ETACs, spaceports, shipyards)
  result = @[]
  var remaining = budgetPP

  if needETACs and hasShipyard:
    let etacCost = getShipConstructionCost(ShipClass.ETAC)
    while remaining >= etacCost and colony.production >= 50:
      result.add(BuildOrder(
        colonySystem: colony.systemId,
        buildType: BuildType.Ship,
        quantity: 1,
        shipClass: some(ShipClass.ETAC),
        buildingType: none(string),
        industrialUnits: 0
      ))
      remaining -= etacCost

proc buildDefenseOrders*(colony: Colony, budgetPP: int,
                        needDefenses: bool, hasStarbase: bool): seq[BuildOrder] =
  ## Generate defense-related build orders (starbases, ground batteries)
  result = @[]
  var remaining = budgetPP

  if needDefenses and not hasStarbase and remaining >= 300:
    result.add(BuildOrder(
      colonySystem: colony.systemId,
      buildType: BuildType.Ship,
      quantity: 1,
      shipClass: some(ShipClass.Starbase),
      buildingType: none(string),
      industrialUnits: 0
    ))
    remaining -= 300

  # Ground batteries (cheap defense)
  while remaining >= 20 and colony.groundBatteries < 5:
    result.add(BuildOrder(
      colonySystem: colony.systemId,
      buildType: BuildType.Building,
      quantity: 1,
      shipClass: none(ShipClass),
      buildingType: some("GroundBattery"),
      industrialUnits: 0
    ))
    remaining -= 20

proc buildMilitaryOrders*(colony: Colony, budgetPP: int,
                         militaryCount: int, canAffordMoreShips: bool,
                         atSquadronLimit: bool): seq[BuildOrder] =
  ## Generate military build orders (frigates, cruisers, dreadnoughts)
  result = @[]
  var remaining = budgetPP

  if not canAffordMoreShips or atSquadronLimit:
    return

  # Build based on available budget (cheapest to most expensive)
  while remaining >= 80:  # Frigate cost
    let shipClass =
      if remaining >= 200 and militaryCount > 8:
        ShipClass.Dreadnought  # Late-game heavy hitters
      elif remaining >= 120 and militaryCount > 4:
        ShipClass.Cruiser      # Mid-game workhorses
      else:
        ShipClass.Frigate      # Early-game backbone

    let cost = getShipConstructionCost(shipClass)
    if remaining >= cost:
      result.add(BuildOrder(
        colonySystem: colony.systemId,
        buildType: BuildType.Ship,
        quantity: 1,
        shipClass: some(shipClass),
        buildingType: none(string),
        industrialUnits: 0
      ))
      remaining -= cost
    else:
      break

proc buildIntelligenceOrders*(colony: Colony, budgetPP: int,
                              needScouts: bool, scoutCount: int): seq[BuildOrder] =
  ## Generate intelligence build orders (scouts)
  ##
  ## Intelligence budget guarantees scout production for reconnaissance.
  ## Scout targets scale with game progression:
  ## - Act 1: 2-3 scouts (exploration)
  ## - Act 2: 5 scouts (intelligence network for invasions)
  ## - Act 3-4: 7 scouts (ELI mesh for invasion support)
  ##
  ## CRITICAL: Build scouts based on budget availability, not external conditions.
  ## The MOEA system allocates 10-15% to Intelligence - use it!
  result = @[]
  var remaining = budgetPP

  # Use Intelligence budget to build scouts if we have budget available
  # This ensures scouts are built regardless of external "needScouts" condition
  if remaining > 0:
    let scoutCost = getShipConstructionCost(ShipClass.Scout)

    # Build scouts up to reasonable limits based on current count
    # Don't over-build - stop at ~10 scouts (more than Act 3 target)
    while remaining >= scoutCost and scoutCount + result.len < 10:
      logDebug(LogCategory.lcAI, &"Building scout at colony {colony.systemId} (budget={remaining}PP, scoutCount={scoutCount + result.len})")
      result.add(BuildOrder(
        colonySystem: colony.systemId,
        buildType: BuildType.Ship,
        quantity: 1,
        shipClass: some(ShipClass.Scout),
        buildingType: none(string),
        industrialUnits: 0
      ))
      remaining -= scoutCost

proc buildSpecialUnitsOrders*(colony: Colony, budgetPP: int,
                              needFighters: bool, needCarriers: bool,
                              needTransports: bool, needRaiders: bool,
                              canAffordMoreShips: bool): seq[BuildOrder] =
  ## Generate special unit orders (fighters, carriers, transports, raiders)
  result = @[]
  var remaining = budgetPP

  # Priority: Carriers → Transports → Raiders → Fighters
  # NOTE: Expensive ships (carriers, transports, raiders) require affordability check
  # Cheap fighters can always be built if budget allocated (like scouts)

  if canAffordMoreShips and needCarriers and remaining >= 150:
    result.add(BuildOrder(
      colonySystem: colony.systemId,
      buildType: BuildType.Ship,
      quantity: 1,
      shipClass: some(ShipClass.Carrier),
      buildingType: none(string),
      industrialUnits: 0
    ))
    remaining -= 150

  # Transports bypass canAffordMoreShips gate like scouts/fighters
  # They're strategic assets for invasion gameplay, controlled by budget allocation
  if needTransports and remaining >= 100:
    logDebug(LogCategory.lcAI, &"Building transport at colony {colony.systemId} (budget={remaining}PP)")
    result.add(BuildOrder(
      colonySystem: colony.systemId,
      buildType: BuildType.Ship,
      quantity: 1,
      shipClass: some(ShipClass.TroopTransport),
      buildingType: none(string),
      industrialUnits: 0
    ))
    remaining -= 100

  if canAffordMoreShips and needRaiders and remaining >= 100:
    result.add(BuildOrder(
      colonySystem: colony.systemId,
      buildType: BuildType.Ship,
      quantity: 1,
      shipClass: some(ShipClass.Raider),
      buildingType: none(string),
      industrialUnits: 0
    ))
    remaining -= 100

  # Fighters (cheap filler)
  if needFighters:
    let fighterCost = getShipConstructionCost(ShipClass.Fighter)
    while remaining >= fighterCost:
      logDebug(LogCategory.lcAI, &"Building fighter at colony {colony.systemId} (budget={remaining}PP)")
      result.add(BuildOrder(
        colonySystem: colony.systemId,
        buildType: BuildType.Ship,
        quantity: 1,
        shipClass: some(ShipClass.Fighter),
        buildingType: none(string),
        industrialUnits: 0
      ))
      remaining -= fighterCost

# =============================================================================
# Integrated Build Planning
# =============================================================================

import ./controller_types

proc generateBuildOrdersWithBudget*(controller: AIController,
                                   filtered: FilteredGameState,
                                   house: House,
                                   myColonies: seq[Colony],
                                   act: GameAct,
                                   personality: AIPersonality,
                                   # Context flags
                                   isUnderThreat: bool,
                                   needETACs: bool,
                                   needDefenses: bool,
                                   needScouts: bool,
                                   needFighters: bool,
                                   needCarriers: bool,
                                   needTransports: bool,
                                   needRaiders: bool,
                                   canAffordMoreShips: bool,
                                   atSquadronLimit: bool,
                                   militaryCount: int,
                                   scoutCount: int,
                                   availableBudget: int): seq[BuildOrder] =
  ## Generate build orders using budget allocation system
  ##
  ## This replaces the sequential priority system with multi-objective allocation
  ##
  ## IMPORTANT: availableBudget should be treasury AFTER maintenance costs
  ## Otherwise AI will overspend and enter maintenance death spiral

  # 1. Calculate budget allocation percentages
  let allocation = allocateBudget(act, personality, isUnderThreat)

  # 2. Convert to actual PP budgets (using available budget after maintenance)
  let budgets = calculateObjectiveBudgets(availableBudget, allocation)

  # 3. Log budget allocation for diagnostics
  logInfo(LogCategory.lcAI, &"{controller.houseId} Act {act} Budget Allocation: " &
          &"Expansion={budgets[Expansion]}PP ({allocation[Expansion]*100:.0f}%), " &
          &"Military={budgets[Military]}PP ({allocation[Military]*100:.0f}%), " &
          &"Defense={budgets[Defense]}PP ({allocation[Defense]*100:.0f}%), " &
          &"Intelligence={budgets[Intelligence]}PP ({allocation[Intelligence]*100:.0f}%), " &
          &"SpecialUnits={budgets[SpecialUnits]}PP ({allocation[SpecialUnits]*100:.0f}%), " &
          &"Technology={budgets[Technology]}PP ({allocation[Technology]*100:.0f}%)")

  # 4. Generate orders for each objective within budget
  result = @[]

  # Sort colonies by production (build at most productive first)
  var coloniesToBuild = myColonies
  coloniesToBuild.sort(proc(a, b: Colony): int = cmp(b.production, a.production))

  for colony in coloniesToBuild:
    let hasShipyard = colony.shipyards.len > 0
    let hasStarbase = colony.starbases.len > 0

    if not hasShipyard:
      continue  # Can't build ships without shipyard

    # Build queue system allows multiple simultaneous projects per colony
    # Each objective can submit orders up to its allocated budget
    # Engine will enforce dock capacity limits (spaceports: 5, shipyards: 10)

    # Generate orders for all objectives (engine will queue them)
    result.add(buildExpansionOrders(colony, budgets[Expansion], needETACs, hasShipyard))
    result.add(buildDefenseOrders(colony, budgets[Defense], needDefenses, hasStarbase))
    result.add(buildMilitaryOrders(colony, budgets[Military], militaryCount, canAffordMoreShips, atSquadronLimit))
    result.add(buildIntelligenceOrders(colony, budgets[Intelligence], needScouts, scoutCount))
    result.add(buildSpecialUnitsOrders(colony, budgets[SpecialUnits], needFighters, needCarriers,
                                      needTransports, needRaiders, canAffordMoreShips))
