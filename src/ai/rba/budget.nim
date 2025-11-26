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
  ## Generate military build orders with COMPLETE capital ship progression
  ## Uses BudgetTracker to prevent overspending
  ##
  ## Tech-gated ship unlocks by CST level:
  ## - CST 1: Corvette (20PP), Frigate (30PP), Destroyer (40PP), Cruiser (60PP)
  ## - CST 2: Heavy Cruiser (80PP)
  ## - CST 3: Battle Cruiser (100PP)
  ## - CST 4: Battleship (150PP)
  ## - CST 5: Dreadnought (200PP)
  ## - CST 6: Super Dreadnought (250PP)
  ##
  ## Build strategy: Choose strongest affordable ship within tech/budget limits
  ##
  ## Note: LightCruiser removed from progression (Cruiser is superior: better CR, same cost)
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
      # Cruiser vs LightCruiser decision (both 60PP, AS 8)
      # Cruiser: Better command (CR 6 vs 4), slightly better defense
      # LightCruiser: Lower command cost (CC 2 vs 3)
      # Prefer Cruiser for stronger squadron leadership
      shipClass = ShipClass.Cruiser           # CST 1: Standard mid-game cruiser
      cost = getShipConstructionCost(shipClass)
    elif remaining >= 40 and militaryCount > 2:
      shipClass = ShipClass.Destroyer         # CST 1: Early-mid bridge
      cost = getShipConstructionCost(shipClass)
    elif remaining >= 30 and militaryCount > 1:
      shipClass = ShipClass.Frigate           # CST 1: Early backbone
      cost = getShipConstructionCost(shipClass)
    elif remaining >= 20:
      shipClass = ShipClass.Corvette          # CST 1: Cheapest warship (early game filler)
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
  ## - Act 1: 3 scouts minimum (exploration)
  ## - Act 2: 6 scouts (intelligence network for invasions)
  ## - Act 3-4: 8 scouts (ELI mesh for invasion support)
  ##
  ## CRITICAL FIX: Build based on needScouts flag and budget, not global count check!
  ## Previous bug: scoutCount + result.len < 10 prevented ANY scout building
  ## Now: Build if needScouts=true AND we have intelligence budget
  result = @[]

  # Only build scouts if we actually need them
  if not needScouts:
    logDebug(LogCategory.lcAI,
             &"{tracker.houseId} Colony {colony.systemId}: Skipping scout build (needScouts=false, have {scoutCount} scouts)")
    return

  # Use Intelligence budget to build scouts
  let scoutCost = getShipConstructionCost(ShipClass.Scout)
  var scoutsBuilt = 0

  # Log budget availability for diagnostics
  let remaining = tracker.getRemainingBudget(Intelligence)
  logDebug(LogCategory.lcAI,
           &"{tracker.houseId} Colony {colony.systemId}: Scout build check - " &
           &"needScouts={needScouts}, scoutCount={scoutCount}, remaining={remaining}PP, cost={scoutCost}PP")

  # Cap: 2 scouts per colony per turn (prevents runaway loops)
  # Combined with BudgetTracker, ensures sustainable scout production
  while tracker.canAfford(Intelligence, scoutCost) and scoutsBuilt < 2:
    logInfo(LogCategory.lcAI,
            &"{tracker.houseId} Colony {colony.systemId}: Building scout " &
            &"(scout #{scoutCount + scoutsBuilt + 1}, remaining={tracker.getRemainingBudget(Intelligence)}PP)")
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

  if scoutsBuilt == 0 and needScouts:
    logDebug(LogCategory.lcAI,
             &"{tracker.houseId} Colony {colony.systemId}: No scouts built " &
             &"(insufficient budget: {remaining}PP < {scoutCost}PP)")

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
  elif canAffordMoreShips and needCarriers and cstLevel >= 2:  # Lowered from CST 3 to 2
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
# Budget Reporting for Transparency
# =============================================================================

type
  BudgetReport* = object
    ## Budget utilization report for economic transparency
    houseId*: HouseId
    turn*: int
    totalBudget*: int
    allocations*: Table[BuildObjective, int]
    commitments*: Table[BuildObjective, int]
    utilization*: Table[BuildObjective, float]
    warnings*: seq[string]

proc generateBudgetReport*(tracker: BudgetTracker, turn: int): BudgetReport =
  ## Generate budget utilization report
  ## Shows allocation vs actual spending for each objective
  result = BudgetReport(
    houseId: tracker.houseId,
    turn: turn,
    totalBudget: tracker.totalBudget,
    allocations: tracker.allocated,
    commitments: tracker.spent,
    utilization: initTable[BuildObjective, float](),
    warnings: @[]
  )

  # Calculate utilization rates and generate warnings
  for objective in BuildObjective:
    let allocated = tracker.allocated[objective]
    let spent = tracker.spent[objective]

    # Calculate utilization percentage
    if allocated > 0:
      result.utilization[objective] = float(spent) / float(allocated)
    else:
      result.utilization[objective] = 0.0

    # Generate warnings for problematic budget patterns
    if spent > allocated:
      # Overspending (should never happen with proper coordination)
      result.warnings.add(&"{objective}: OVERSPENT by {spent - allocated}PP " &
                         &"(spent {spent}PP of {allocated}PP allocated)")
    elif allocated > 0 and spent == 0:
      # Budget allocated but nothing built
      result.warnings.add(&"{objective}: Allocated {allocated}PP but spent nothing " &
                         &"(may indicate missing build logic or exhausted production capacity)")
    elif result.utilization[objective] < 0.3 and allocated > 100:
      # Significant underutilization
      let pct = int(result.utilization[objective] * 100)
      result.warnings.add(&"{objective}: Low utilization {pct}% " &
                         &"(spent {spent}PP of {allocated}PP allocated, {allocated - spent}PP wasted)")

proc logBudgetReport*(report: BudgetReport) =
  ## Log budget report for turn results
  logInfo(LogCategory.lcAI,
          &"")
  logInfo(LogCategory.lcAI,
          &"=== Budget Report: {report.houseId} (Turn {report.turn}) ===")
  logInfo(LogCategory.lcAI,
          &"Total Budget: {report.totalBudget}PP")
  logInfo(LogCategory.lcAI,
          &"")

  # Log per-objective utilization
  for objective in BuildObjective:
    let allocated = report.allocations[objective]
    let spent = report.commitments[objective]
    let remaining = allocated - spent
    let pct = if allocated > 0: int(report.utilization[objective] * 100) else: 0

    var status = ""
    if spent == 0 and allocated > 0:
      status = " [UNUSED]"
    elif report.utilization[objective] > 0.95:
      status = " [EXHAUSTED]"
    elif report.utilization[objective] < 0.5 and allocated > 100:
      status = " [UNDERUTILIZED]"

    logInfo(LogCategory.lcAI,
            &"  {objective:15} {spent:4}/{allocated:4}PP ({pct:3}%) {remaining:4}PP remaining{status}")

  # Log warnings
  if report.warnings.len > 0:
    logInfo(LogCategory.lcAI, &"")
    logInfo(LogCategory.lcAI, &"Budget Warnings:")
    for warning in report.warnings:
      logWarn(LogCategory.lcAI, &"  ⚠ {warning}")

  logInfo(LogCategory.lcAI,
          &"===========================================")

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
                                   planetBreakerCount: int,
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

  # PROJECTED STATE TRACKING
  # Track units built THIS TURN to avoid double-counting
  # Example: Colony A builds 2 scouts, Colony B sees projected count = 2 (not 0!)
  var projectedScoutCount = scoutCount
  var projectedMilitaryCount = militaryCount
  var projectedPlanetBreakerCount = planetBreakerCount

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Starting build generation: " &
          &"scouts={scoutCount}, military={militaryCount}, PBs={planetBreakerCount}")

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

    # DYNAMIC NEED RECALCULATION
    # Recalculate need flags using PROJECTED counts (current + built this turn)
    let projectedNeedScouts = case act
      of GameAct.Act1_LandGrab:
        projectedScoutCount < 3
      of GameAct.Act2_RisingTensions:
        projectedScoutCount < 6
      else:
        projectedScoutCount < 8

    # Generate orders for all objectives using shared BudgetTracker
    # CRITICAL: tracker is var parameter - gets modified by each build function
    # CRITICAL: Use PROJECTED counts to avoid double-building
    result.add(buildExpansionOrders(colony, tracker, needETACs, hasShipyard))
    result.add(buildDefenseOrders(colony, tracker, needDefenses, hasStarbase))

    let militaryOrders = buildMilitaryOrders(colony, tracker, projectedMilitaryCount,
                                            canAffordMoreShips, atSquadronLimit, cstLevel, act)
    result.add(militaryOrders)
    projectedMilitaryCount += militaryOrders.len  # Update projected count

    let intelligenceOrders = buildIntelligenceOrders(colony, tracker, projectedNeedScouts, projectedScoutCount)
    result.add(intelligenceOrders)
    projectedScoutCount += intelligenceOrders.len  # Update projected count

    result.add(buildSpecialUnitsOrders(colony, tracker, needFighters, needCarriers,
                                      needTransports, needRaiders, canAffordMoreShips, cstLevel))

    let siegeOrders = buildSiegeOrders(colony, tracker, projectedPlanetBreakerCount,
                                       colonyCount, cstLevel, needSiege)
    result.add(siegeOrders)
    # Count Planet-Breakers in siege orders
    for order in siegeOrders:
      if order.shipClass.isSome and order.shipClass.get() == ShipClass.PlanetBreaker:
        projectedPlanetBreakerCount += order.quantity

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Build generation complete: " &
          &"built {projectedScoutCount - scoutCount} scouts, " &
          &"{projectedMilitaryCount - militaryCount} military, " &
          &"{projectedPlanetBreakerCount - planetBreakerCount} PBs")

  # Log final budget summary
  tracker.logBudgetSummary()

  # Generate and log budget report for transparency
  let report = generateBudgetReport(tracker, filtered.turn)
  logBudgetReport(report)
