## Budget Allocation System for EC4X Rule-Based AI
##
## Multi-objective resource allocation based on game phase and personality.
## Prevents resource starvation by guaranteeing budget to each objective.
##
## Based on research:
## - MOEA for build order optimization (AAAI 2020)
## - Stellaris weight-based AI system
## - Priority-based task assignment (Game Developer 2015)

import std/[tables, options, algorithm, strformat, sequtils]
import ../common/types
import ../../engine/[gamestate, orders, fleet, logger, fog_of_war]
import ../../engine/economy/construction  # For getShipConstructionCost
import ../../common/types/[core, units]

# =============================================================================
# Budget Tracker - Running Budget Management
# =============================================================================

type
  BudgetTracker* = object
    ## Tracks budget allocation and spending across objectives
    ## Prevents overspending by maintaining running totals
    ##
    ## CRITICAL: Prevents budget collapse from runaway spending loops
    ## Example: Without tracking, 3 colonies × 550 PP = 1650 PP spent (house only had 1000!)
    houseId*: HouseId
    totalBudget*: int                         # Total treasury available after maintenance
    allocated*: Table[BuildObjective, int]    # Planned allocation per objective
    spent*: Table[BuildObjective, int]        # Actual spending per objective
    ordersGenerated*: int                     # Count of build orders created

proc initBudgetTracker*(houseId: HouseId, treasury: int,
                       allocation: BudgetAllocation): BudgetTracker =
  ## Create new budget tracker with allocation percentages
  result = BudgetTracker(
    houseId: houseId,
    totalBudget: treasury,
    allocated: initTable[BuildObjective, int](),
    spent: initTable[BuildObjective, int](),
    ordersGenerated: 0
  )

  # Convert percentages to PP budgets
  for objective, percentage in allocation:
    result.allocated[objective] = int(float(treasury) * percentage)
    result.spent[objective] = 0

  logInfo(LogCategory.lcAI,
          &"{houseId} Budget Tracker initialized: {treasury} PP total, " &
          &"Expansion={result.allocated[Expansion]}PP, " &
          &"Military={result.allocated[Military]}PP, " &
          &"Defense={result.allocated[Defense]}PP")

proc canAfford*(tracker: BudgetTracker, objective: BuildObjective, cost: int): bool =
  ## Check if objective has budget remaining for this purchase
  let remaining = tracker.allocated[objective] - tracker.spent[objective]
  result = remaining >= cost

  if not result:
    logDebug(LogCategory.lcAI,
             &"{tracker.houseId} Cannot afford {cost}PP for {objective}: " &
             &"allocated={tracker.allocated[objective]}PP, " &
             &"spent={tracker.spent[objective]}PP, " &
             &"remaining={remaining}PP")

proc recordSpending*(tracker: var BudgetTracker, objective: BuildObjective, cost: int) =
  ## Record spending against objective budget
  ## CRITICAL: Must be var parameter to modify tracker
  tracker.spent[objective] += cost
  tracker.ordersGenerated += 1

  let remaining = tracker.allocated[objective] - tracker.spent[objective]
  logDebug(LogCategory.lcAI,
           &"{tracker.houseId} Recorded {cost}PP spending for {objective}: " &
           &"spent={tracker.spent[objective]}PP, remaining={remaining}PP")

proc getRemainingBudget*(tracker: BudgetTracker, objective: BuildObjective): int =
  ## Get remaining budget for objective
  result = tracker.allocated[objective] - tracker.spent[objective]

proc getTotalSpent*(tracker: BudgetTracker): int =
  ## Get total spending across all objectives
  result = 0
  for spent in tracker.spent.values:
    result += spent

proc getTotalRemaining*(tracker: BudgetTracker): int =
  ## Get total unspent budget across all objectives
  result = tracker.totalBudget - tracker.getTotalSpent()

proc logBudgetSummary*(tracker: BudgetTracker) =
  ## Log budget allocation and spending summary
  logInfo(LogCategory.lcAI,
          &"{tracker.houseId} Budget Summary: " &
          &"Total={tracker.totalBudget}PP, " &
          &"Spent={tracker.getTotalSpent()}PP, " &
          &"Remaining={tracker.getTotalRemaining()}PP, " &
          &"Orders={tracker.ordersGenerated}")

  for objective in BuildObjective:
    let allocated = tracker.allocated[objective]
    let spent = tracker.spent[objective]
    let remaining = allocated - spent
    let pct = if allocated > 0: (spent * 100 div allocated) else: 0

    logInfo(LogCategory.lcAI,
            &"  {objective}: {spent}/{allocated}PP ({pct}%), {remaining}PP remaining")

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
      # INCREASED Defense from 0.10 to 0.15 - colonies need ground batteries!
      {
        Expansion: 0.55,
        Defense: 0.15,
        Military: 0.10,
        Intelligence: 0.15,
        SpecialUnits: 0.05,
        Technology: 0.00
      }.toTable()

    of GameAct.Act2_RisingTensions:
      # CRITICAL TRANSITION: Military buildup begins while continuing expansion
      # Act 2 should maintain momentum from Act 1, not collapse expansion
      # INCREASED Defense from 0.15 to 0.20 - protect growing empire
      {
        Expansion: 0.30,     # Reduced slightly to fund defenses
        Defense: 0.20,
        Military: 0.30,      # Military buildup
        Intelligence: 0.10,
        SpecialUnits: 0.05,  # Transports for aggressive AIs
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

proc buildExpansionOrders*(colony: Colony, tracker: var BudgetTracker,
                          needETACs: bool, hasShipyard: bool): seq[BuildOrder] =
  ## Generate expansion-related build orders (ETACs, spaceports, shipyards)
  ## Uses BudgetTracker to prevent overspending
  result = @[]

  if needETACs and hasShipyard:
    let etacCost = getShipConstructionCost(ShipClass.ETAC)
    var etacsBuilt = 0
    # CRITICAL CAP: Maximum 2 ETACs per colony per turn
    # Prevents runaway loops that build 5-10 ETACs from single colony
    # Combined with BudgetTracker, this ensures sustainable ETAC production
    while tracker.canAfford(Expansion, etacCost) and etacsBuilt < 2:
      result.add(BuildOrder(
        colonySystem: colony.systemId,
        buildType: BuildType.Ship,
        quantity: 1,
        shipClass: some(ShipClass.ETAC),
        buildingType: none(string),
        industrialUnits: 0
      ))
      tracker.recordSpending(Expansion, etacCost)
      etacsBuilt += 1

proc buildDefenseOrders*(colony: Colony, tracker: var BudgetTracker,
                        needDefenses: bool, hasStarbase: bool): seq[BuildOrder] =
  ## Generate defense-related build orders (starbases, ground batteries)
  ## Uses BudgetTracker to prevent overspending
  result = @[]

  if needDefenses and not hasStarbase:
    let starbaseCost = 300
    if tracker.canAfford(Defense, starbaseCost):
      result.add(BuildOrder(
        colonySystem: colony.systemId,
        buildType: BuildType.Ship,
        quantity: 1,
        shipClass: some(ShipClass.Starbase),
        buildingType: none(string),
        industrialUnits: 0
      ))
      tracker.recordSpending(Defense, starbaseCost)

  # Ground batteries (cheap defense)
  let groundBatteryCost = 20
  while tracker.canAfford(Defense, groundBatteryCost) and colony.groundBatteries < 5:
    result.add(BuildOrder(
      colonySystem: colony.systemId,
      buildType: BuildType.Building,
      quantity: 1,
      shipClass: none(ShipClass),
      buildingType: some("GroundBattery"),
      industrialUnits: 0
    ))
    tracker.recordSpending(Defense, groundBatteryCost)

proc buildMilitaryOrders*(colony: Colony, tracker: var BudgetTracker,
                         militaryCount: int, canAffordMoreShips: bool,
                         atSquadronLimit: bool, cstLevel: int, act: GameAct): seq[BuildOrder] =
  ## Generate military build orders with full capital ship progression
  ## Uses BudgetTracker to prevent overspending
  ##
  ## Tech-gated ship unlocks by CST level:
  ## - CST 1: Corvette, Frigate, Destroyer, Light Cruiser
  ## - CST 2: Heavy Cruiser
  ## - CST 3: Battle Cruiser
  ## - CST 4: Battleship
  ## - CST 5: Dreadnought
  ## - CST 6: Super Dreadnought
  ##
  ## Build strategy: Choose best ship affordable within tech limits
  result = @[]
  var shipsBuilt = 0

  if not canAffordMoreShips or atSquadronLimit:
    return

  # Cap: 3 military ships per colony per turn (prevents runaway loops)
  # This allows reasonable fleet buildup without budget collapse
  while shipsBuilt < 3:  # Maximum 3 ships per colony
    var shipClass: ShipClass
    var cost: int

    # Choose ship based on CST tech, available budget, and game phase
    # Priority: Build strongest affordable ship within tech limits
    let remaining = tracker.getRemainingBudget(Military)

    if remaining >= 250 and cstLevel >= 6 and act >= GameAct.Act4_Endgame and militaryCount > 10:
      shipClass = ShipClass.SuperDreadnought  # CST 6: Ultimate capital ship
      cost = getShipConstructionCost(shipClass)
    elif remaining >= 200 and cstLevel >= 5 and militaryCount > 8:
      shipClass = ShipClass.Dreadnought       # CST 5: Late-game heavy hitter
      cost = getShipConstructionCost(shipClass)
    elif remaining >= 150 and cstLevel >= 4 and militaryCount > 6:
      shipClass = ShipClass.Battleship        # CST 4: Mid-late game backbone
      cost = getShipConstructionCost(shipClass)
    elif remaining >= 100 and cstLevel >= 3:
      shipClass = ShipClass.Battlecruiser     # CST 3: Mid-game workhorse
      cost = getShipConstructionCost(shipClass)
    elif remaining >= 80 and cstLevel >= 2:
      shipClass = ShipClass.HeavyCruiser      # CST 2: Early-mid heavy
      cost = getShipConstructionCost(shipClass)
    elif remaining >= 60 and militaryCount > 3:
      shipClass = ShipClass.LightCruiser      # CST 1: Cost-effective mid
      cost = getShipConstructionCost(shipClass)
    elif remaining >= 40 and militaryCount > 2:
      shipClass = ShipClass.Destroyer         # CST 1: Early-mid bridge
      cost = getShipConstructionCost(shipClass)
    elif remaining >= 30:
      shipClass = ShipClass.Frigate           # CST 1: Early backbone
      cost = getShipConstructionCost(shipClass)
    else:
      break  # Not enough budget for any ship

    if tracker.canAfford(Military, cost):
      result.add(BuildOrder(
        colonySystem: colony.systemId,
        buildType: BuildType.Ship,
        quantity: 1,
        shipClass: some(shipClass),
        buildingType: none(string),
        industrialUnits: 0
      ))
      tracker.recordSpending(Military, cost)
      shipsBuilt += 1
    else:
      break

proc buildIntelligenceOrders*(colony: Colony, tracker: var BudgetTracker,
                              needScouts: bool, scoutCount: int): seq[BuildOrder] =
  ## Generate intelligence build orders (scouts)
  ## Uses BudgetTracker to prevent overspending
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

  # Use Intelligence budget to build scouts if we have budget available
  # This ensures scouts are built regardless of external "needScouts" condition
  let scoutCost = getShipConstructionCost(ShipClass.Scout)
  var scoutsBuilt = 0

  # Cap: 2 scouts per colony per turn (prevents runaway loops)
  # Combined with BudgetTracker, ensures sustainable scout production
  while tracker.canAfford(Intelligence, scoutCost) and scoutCount + result.len < 10 and scoutsBuilt < 2:
    logDebug(LogCategory.lcAI,
             &"Building scout at colony {colony.systemId} " &
             &"(remaining={tracker.getRemainingBudget(Intelligence)}PP, scoutCount={scoutCount + result.len})")
    result.add(BuildOrder(
      colonySystem: colony.systemId,
      buildType: BuildType.Ship,
      quantity: 1,
      shipClass: some(ShipClass.Scout),
      buildingType: none(string),
      industrialUnits: 0
    ))
    tracker.recordSpending(Intelligence, scoutCost)
    scoutsBuilt += 1

proc buildSpecialUnitsOrders*(colony: Colony, tracker: var BudgetTracker,
                              needFighters: bool, needCarriers: bool,
                              needTransports: bool, needRaiders: bool,
                              canAffordMoreShips: bool, cstLevel: int): seq[BuildOrder] =
  ## Generate special unit orders (fighters, carriers, transports, raiders)
  ## Uses BudgetTracker to prevent overspending
  ##
  ## Tech-gated unlocks:
  ## - CST 3: Carrier, Raider
  ## - CST 5: Super Carrier (better fighter capacity)
  result = @[]

  # Priority: Super Carriers → Carriers → Transports → Raiders → Fighters
  # NOTE: Expensive ships (carriers, transports, raiders) require affordability check
  # Cheap fighters can always be built if budget allocated (like scouts)

  # Prefer Super Carriers (CST 5) over regular Carriers when available
  if canAffordMoreShips and needCarriers and cstLevel >= 5:
    let superCarrierCost = 200
    if tracker.canAfford(SpecialUnits, superCarrierCost):
      result.add(BuildOrder(
        colonySystem: colony.systemId,
        buildType: BuildType.Ship,
        quantity: 1,
        shipClass: some(ShipClass.SuperCarrier),  # CST 5: 5-8 fighter capacity
        buildingType: none(string),
        industrialUnits: 0
      ))
      tracker.recordSpending(SpecialUnits, superCarrierCost)
  elif canAffordMoreShips and needCarriers and cstLevel >= 3:
    let carrierCost = 120
    if tracker.canAfford(SpecialUnits, carrierCost):
      result.add(BuildOrder(
        colonySystem: colony.systemId,
        buildType: BuildType.Ship,
        quantity: 1,
        shipClass: some(ShipClass.Carrier),  # CST 3: 3-5 fighter capacity
        buildingType: none(string),
        industrialUnits: 0
      ))
      tracker.recordSpending(SpecialUnits, carrierCost)

  # Transports bypass canAffordMoreShips gate like scouts/fighters
  # They're strategic assets for invasion gameplay, controlled by budget allocation
  if needTransports:
    let transportCost = 100
    if tracker.canAfford(SpecialUnits, transportCost):
      logDebug(LogCategory.lcAI,
               &"Building transport at colony {colony.systemId} " &
               &"(remaining={tracker.getRemainingBudget(SpecialUnits)}PP)")
      result.add(BuildOrder(
        colonySystem: colony.systemId,
        buildType: BuildType.Ship,
        quantity: 1,
        shipClass: some(ShipClass.TroopTransport),
        buildingType: none(string),
        industrialUnits: 0
      ))
      tracker.recordSpending(SpecialUnits, transportCost)

  if canAffordMoreShips and needRaiders:
    let raiderCost = 100
    if tracker.canAfford(SpecialUnits, raiderCost):
      result.add(BuildOrder(
        colonySystem: colony.systemId,
        buildType: BuildType.Ship,
        quantity: 1,
        shipClass: some(ShipClass.Raider),
        buildingType: none(string),
        industrialUnits: 0
      ))
      tracker.recordSpending(SpecialUnits, raiderCost)

  # Fighters (cheap filler)
  if needFighters:
    let fighterCost = getShipConstructionCost(ShipClass.Fighter)
    while tracker.canAfford(SpecialUnits, fighterCost):
      logDebug(LogCategory.lcAI,
               &"Building fighter at colony {colony.systemId} " &
               &"(remaining={tracker.getRemainingBudget(SpecialUnits)}PP)")
      result.add(BuildOrder(
        colonySystem: colony.systemId,
        buildType: BuildType.Ship,
        quantity: 1,
        shipClass: some(ShipClass.Fighter),
        buildingType: none(string),
        industrialUnits: 0
      ))
      tracker.recordSpending(SpecialUnits, fighterCost)

proc buildSiegeOrders*(colony: Colony, tracker: var BudgetTracker,
                      planetBreakerCount: int, colonyCount: int,
                      cstLevel: int, needSiege: bool): seq[BuildOrder] =
  ## Generate siege weapon orders (Planet-Breakers)
  ## Uses BudgetTracker to prevent overspending
  ##
  ## Planet-Breakers are late-game superweapons that bypass planetary shields.
  ##
  ## Requirements per assets.md#2.4.8:
  ## - CST 10 (highest tier construction tech)
  ## - 400 PP construction cost
  ## - Maximum 1 per owned colony (lose colony = lose its PB, no salvage)
  ##
  ## Strategic use:
  ## - Break through SLD4-6 shield stalemates
  ## - Essential for conquering heavily fortified colonies
  ## - Fragile (AS 50, DS 20) - requires strong escorts
  result = @[]

  # Only build if:
  # 1. We need siege capability (planning invasions of fortified colonies)
  # 2. We have CST 10 (highest tech requirement in game)
  # 3. We haven't hit the 1-per-colony ownership limit
  # 4. We can afford it (400 PP is expensive - 2x Dreadnought cost)
  if not needSiege or cstLevel < 10 or planetBreakerCount >= colonyCount:
    return

  let planetBreakerCost = 400
  if tracker.canAfford(SpecialUnits, planetBreakerCost):
    logDebug(LogCategory.lcAI,
             &"Building Planet-Breaker at colony {colony.systemId} " &
             &"(count={planetBreakerCount}/{colonyCount})")
    result.add(BuildOrder(
      colonySystem: colony.systemId,
      buildType: BuildType.Ship,
      quantity: 1,
      shipClass: some(ShipClass.PlanetBreaker),
      buildingType: none(string),
      industrialUnits: 0
    ))
    tracker.recordSpending(SpecialUnits, planetBreakerCost)

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

  # 2. Initialize BudgetTracker with full house budget
  # CRITICAL: Single tracker prevents overspending across all colonies
  # Previous bug: Per-colony budgets → 3 colonies × 550 PP = 1650 PP spent (house only had 1000!)
  # Now: Single tracker enforces house-wide budget limit
  var tracker = initBudgetTracker(controller.houseId, availableBudget, allocation)

  # 3. Generate orders for each objective within budget
  result = @[]

  # Sort colonies by production (build at most productive first)
  var coloniesToBuild = myColonies
  coloniesToBuild.sort(proc(a, b: Colony): int = cmp(b.production, a.production))

  # Get tech levels for gating ship unlocks
  let cstLevel = house.techTree.levels.constructionTech
  let colonyCount = myColonies.len
  let planetBreakerCount = house.planetBreakerCount

  # Determine if we need siege capability (Planet-Breakers)
  # Build PBs when: CST 10 unlocked, fighting heavily fortified enemies, Act 3+
  let needSiege = act >= GameAct.Act3_TotalWar and cstLevel >= 10

  # Build from all colonies with shipyards, using shared budget tracker
  # BudgetTracker automatically prevents overspending
  for colony in coloniesToBuild:
    let hasShipyard = colony.shipyards.len > 0
    let hasStarbase = colony.starbases.len > 0

    if not hasShipyard:
      continue  # Can't build ships without shipyard

    # Build queue system allows multiple simultaneous projects per colony
    # BudgetTracker prevents overspending across ALL colonies
    # Engine will enforce dock capacity limits (spaceports: 5, shipyards: 10)

    # Generate orders for all objectives using shared BudgetTracker
    # CRITICAL: tracker is var parameter - gets modified by each build function
    result.add(buildExpansionOrders(colony, tracker, needETACs, hasShipyard))
    result.add(buildDefenseOrders(colony, tracker, needDefenses, hasStarbase))
    result.add(buildMilitaryOrders(colony, tracker, militaryCount, canAffordMoreShips, atSquadronLimit, cstLevel, act))
    result.add(buildIntelligenceOrders(colony, tracker, needScouts, scoutCount))
    result.add(buildSpecialUnitsOrders(colony, tracker, needFighters, needCarriers,
                                      needTransports, needRaiders, canAffordMoreShips, cstLevel))
    result.add(buildSiegeOrders(colony, tracker, planetBreakerCount, colonyCount, cstLevel, needSiege))

  # Log final budget summary
  tracker.logBudgetSummary()
