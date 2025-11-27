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
        Reconnaissance: 0.15,
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
        Reconnaissance: 0.10,
        SpecialUnits: 0.05,  # Transports for aggressive AIs
        Technology: 0.05
      }.toTable()

    of GameAct.Act3_TotalWar:
      # Focus: Conquest and invasion
      {
        Expansion: 0.00,     # No more colonization
        Defense: 0.15,
        Military: 0.55,      # ← 55% to military + invasions
        Reconnaissance: 0.05,
        SpecialUnits: 0.15,  # Transports for invasions
        Technology: 0.10
      }.toTable()

    of GameAct.Act4_Endgame:
      # Focus: All-in for victory
      {
        Expansion: 0.00,
        Defense: 0.10,
        Military: 0.60,
        Reconnaissance: 0.05,
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

proc buildFacilityOrders*(colony: Colony, tracker: var BudgetTracker): seq[BuildOrder] =
  ## Generate facility build orders (Spaceport, Shipyard)
  ## Uses BudgetTracker to prevent overspending from Expansion budget
  ##
  ## **CRITICAL**: This function enables production scaling!
  ## Without facilities at new colonies, production caps at 3 ships/turn (homeworld only)
  ##
  ## **COST EFFICIENCY** (per economy.md:5.1, 5.3):
  ## - Spaceport: 100 PP, 1 turn, 5 docks, but ships cost **2x** (100% PC penalty)
  ## - Shipyard: 150 PP, 2 turns, 10 docks, **normal cost** (no penalty), requires Spaceport
  ##
  ## **Priority: SHIPYARD UPGRADES > NEW SPACEPORTS**
  ## Shipyards eliminate 2x cost penalty, making them FAR more efficient than Spaceports.
  ## Example: 3 Cruisers = 180 PP (shipyard) vs 360 PP (spaceport) - saves 180 PP!
  ##
  ## Strategy:
  ## - Priority 1: Upgrade Spaceport → Shipyard (removes 2x penalty, huge savings)
  ## - Priority 2: Build Spaceport at colonies without facilities (prerequisite)
  result = @[]

  let hasSpaceport = colony.spaceports.len > 0
  let hasShipyard = colony.shipyards.len > 0

  # Priority 1: UPGRADE SPACEPORT TO SHIPYARD (first Shipyard)
  # This is THE most cost-effective investment: eliminates 2x ship construction penalty
  # Shipyards pay for themselves after just 2-3 ships due to 50% cost savings
  if hasSpaceport and not hasShipyard:
    let shipyardCost = 150  # from facilities.toml
    if tracker.canAfford(Expansion, shipyardCost):
      logInfo(LogCategory.lcAI,
              &"{tracker.houseId} Colony {colony.systemId}: Building Shipyard #1 (eliminates 2x spaceport penalty)")
      result.add(BuildOrder(
        colonySystem: colony.systemId,
        buildType: BuildType.Building,
        quantity: 1,
        shipClass: none(ShipClass),
        buildingType: some("Shipyard"),
        industrialUnits: 0
      ))
      tracker.recordSpending(Expansion, shipyardCost)
      return  # One facility per colony per turn

  # Priority 2: Build ADDITIONAL Shipyards (2nd, 3rd, 4th+) to scale production
  # Each Shipyard = 10 docks = 10 parallel construction projects
  # Build more Shipyards at high-production colonies to maximize fleet building
  if hasShipyard and hasSpaceport:
    let currentShipyards = colony.shipyards.len
    # Build additional Shipyards until we have good dock capacity
    # Target: 2-3 Shipyards per colony (20-30 docks) for healthy production scaling
    if currentShipyards < 3:
      let shipyardCost = 150  # from facilities.toml
      if tracker.canAfford(Expansion, shipyardCost):
        logInfo(LogCategory.lcAI,
                &"{tracker.houseId} Colony {colony.systemId}: Building Shipyard #{currentShipyards + 1} " &
                &"(scaling production capacity: {currentShipyards * 10} → {(currentShipyards + 1) * 10} docks)")
        result.add(BuildOrder(
          colonySystem: colony.systemId,
          buildType: BuildType.Building,
          quantity: 1,
          shipClass: none(ShipClass),
          buildingType: some("Shipyard"),
          industrialUnits: 0
        ))
        tracker.recordSpending(Expansion, shipyardCost)
        return  # One facility per colony per turn

  # Priority 3: Build Spaceport if colony has no facilities
  # Required prerequisite for Shipyard, enables ship production (but at 2x cost)
  if not hasSpaceport and not hasShipyard:
    let spaceportCost = 100  # from facilities.toml
    if tracker.canAfford(Expansion, spaceportCost):
      logInfo(LogCategory.lcAI,
              &"{tracker.houseId} Colony {colony.systemId}: Building Spaceport (prerequisite for Shipyard)")
      result.add(BuildOrder(
        colonySystem: colony.systemId,
        buildType: BuildType.Building,
        quantity: 1,
        shipClass: none(ShipClass),
        buildingType: some("Spaceport"),
        industrialUnits: 0
      ))
      tracker.recordSpending(Expansion, spaceportCost)
      return  # One facility per colony per turn

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

type
  FleetComposition* = object
    ## Tracks fleet composition by ship category
    capitals*: int        # Dreadnought, SuperDreadnought, Battleship, Battlecruiser
    escorts*: int         # HeavyCruiser, Cruiser, LightCruiser, Destroyer, Frigate, Corvette
    specialists*: int     # Fighter, Carrier, Raider, Transport, Scout, ETAC, PlanetBreaker
    total*: int

  CompositionDoctrine* = object
    ## Target composition ratios (0.0-1.0)
    capitalRatio*: float
    escortRatio*: float
    specialistRatio*: float

proc analyzeFleetComposition(fleets: seq[Fleet]): FleetComposition =
  ## Analyze current fleet composition across all fleets
  ## Categorizes ships into capitals, escorts, and specialists
  result = FleetComposition(capitals: 0, escorts: 0, specialists: 0, total: 0)

  for fleet in fleets:
    for squadron in fleet.squadrons:
      # Count flagship
      case squadron.flagship.shipClass
      of ShipClass.SuperDreadnought, ShipClass.Dreadnought, ShipClass.Battleship, ShipClass.Battlecruiser:
        result.capitals += 1
      of ShipClass.HeavyCruiser, ShipClass.Cruiser, ShipClass.LightCruiser, ShipClass.Destroyer, ShipClass.Frigate, ShipClass.Corvette:
        result.escorts += 1
      of ShipClass.Fighter, ShipClass.Carrier, ShipClass.SuperCarrier, ShipClass.Raider, ShipClass.TroopTransport, ShipClass.Scout, ShipClass.ETAC, ShipClass.PlanetBreaker:
        result.specialists += 1
      else:
        result.specialists += 1  # Starbase and other special ships
      result.total += 1

      # Count wing ships
      for ship in squadron.ships:
        case ship.shipClass
        of ShipClass.SuperDreadnought, ShipClass.Dreadnought, ShipClass.Battleship, ShipClass.Battlecruiser:
          result.capitals += 1
        of ShipClass.HeavyCruiser, ShipClass.Cruiser, ShipClass.LightCruiser, ShipClass.Destroyer, ShipClass.Frigate, ShipClass.Corvette:
          result.escorts += 1
        of ShipClass.Fighter, ShipClass.Carrier, ShipClass.SuperCarrier, ShipClass.Raider, ShipClass.TroopTransport, ShipClass.Scout, ShipClass.ETAC, ShipClass.PlanetBreaker:
          result.specialists += 1
        else:
          result.specialists += 1
        result.total += 1

proc getCompositionDoctrine(personality: AIPersonality): CompositionDoctrine =
  ## Get target fleet composition based on personality
  ## Returns desired ratios for capitals, escorts, and specialists

  # Aggressive: Capital-heavy doctrine (overwhelming firepower)
  if personality.aggression >= 0.7:
    result = CompositionDoctrine(
      capitalRatio: 0.60,    # 60% capitals
      escortRatio: 0.25,     # 25% escorts
      specialistRatio: 0.15  # 15% specialists
    )

  # Economic: Escort-heavy doctrine (cost-efficient numbers)
  elif personality.economicFocus >= 0.7:
    result = CompositionDoctrine(
      capitalRatio: 0.30,    # 30% capitals
      escortRatio: 0.50,     # 50% escorts
      specialistRatio: 0.20  # 20% specialists (fighters!)
    )

  # Balanced: Mixed doctrine
  else:
    result = CompositionDoctrine(
      capitalRatio: 0.45,    # 45% capitals
      escortRatio: 0.40,     # 40% escorts
      specialistRatio: 0.15  # 15% specialists
    )

proc assessAggregateThreat(intelligence: Table[SystemId, IntelligenceReport],
                          personality: AIPersonality): float =
  ## Assess overall enemy threat level from intelligence reports
  ## Returns threat modifier (0.8-1.2) for strategic adjustment
  ##
  ## Phase 4: Counter-Strategy Adaptation (Simplified)
  ## Uses aggregate threat assessment due to fog-of-war limitations

  var totalThreat = 0
  var threatenedSystemCount = 0

  # Aggregate enemy fleet strength across all intel reports
  for systemId, report in intelligence:
    if report.estimatedFleetStrength > 0 and report.owner.isSome:
      totalThreat += report.estimatedFleetStrength
      threatenedSystemCount += 1

  # No significant threats detected
  if totalThreat < 100:
    return 1.0  # Neutral - maintain current strategy

  # Calculate average threat per system
  let avgThreatPerSystem = if threatenedSystemCount > 0:
    float(totalThreat) / float(threatenedSystemCount)
  else:
    0.0

  # Strategic adjustments based on personality and threat level
  # High aggression: More aggressive when threatened (build more capitals)
  # High risk tolerance: Less reactive to threats
  # Low aggression: More defensive when threatened (build more escorts)

  if personality.aggression >= 0.7:
    # Aggressive: Escalate in response to threats (build bigger ships)
    if avgThreatPerSystem > 200:
      return 1.15  # 15% boost to capital preference
    elif avgThreatPerSystem > 100:
      return 1.08  # 8% boost
    else:
      return 1.0

  elif personality.riskTolerance < 0.3:
    # Risk-averse: Build defensive escorts when threatened
    if avgThreatPerSystem > 150:
      return 0.85  # 15% penalty to capitals (favor escorts)
    elif avgThreatPerSystem > 100:
      return 0.92  # 8% penalty
    else:
      return 1.0

  else:
    # Balanced: Slight escalation under pressure
    if avgThreatPerSystem > 200:
      return 1.10
    elif avgThreatPerSystem > 150:
      return 1.05
    else:
      return 1.0

proc calculateShipPreference(personality: AIPersonality, shipClass: ShipClass): float =
  ## Calculate personality-based preference weight for ship types
  ## Returns multiplier (0.5x to 1.5x) based on personality traits
  ##
  ## Aggressive AIs prefer capitals, Economic AIs prefer cost-efficient escorts,
  ## Tech-focused AIs prefer cutting-edge ships
  result = 1.0  # Neutral weight

  # Aggressive personality: Prefer capital ships, avoid weak escorts
  if personality.aggression >= 0.7:
    case shipClass
    of ShipClass.SuperDreadnought:
      result = 1.39
    of ShipClass.Dreadnought:
      result = 1.33
    of ShipClass.Battleship:
      result = 1.30
    of ShipClass.Battlecruiser:
      result = 1.27
    of ShipClass.HeavyCruiser:
      result = 1.08
    of ShipClass.Cruiser:
      result = 0.91
    of ShipClass.Destroyer:
      result = 0.83
    of ShipClass.Frigate:
      result = 0.75
    of ShipClass.Corvette:
      result = 0.65
    else:
      result = 1.0

  # Economic personality: Prefer cost-efficient ships, avoid expensive capitals
  elif personality.economicFocus >= 0.7:
    case shipClass
    of ShipClass.SuperDreadnought:
      result = 0.83
    of ShipClass.Dreadnought:
      result = 0.88
    of ShipClass.Battleship:
      result = 0.93
    of ShipClass.Battlecruiser:
      result = 1.05  # Best efficiency
    of ShipClass.HeavyCruiser:
      result = 1.11
    of ShipClass.Cruiser:
      result = 1.18  # Cost-efficient workhorse
    of ShipClass.Destroyer:
      result = 1.24
    of ShipClass.Frigate:
      result = 1.25
    of ShipClass.Corvette:
      result = 1.25  # Low maintenance
    else:
      result = 1.0

  # Tech-focused personality: Prefer cutting-edge ships
  elif personality.techPriority >= 0.7:
    case shipClass
    of ShipClass.SuperDreadnought:
      result = 1.30  # CST 6 pinnacle
    of ShipClass.Dreadnought:
      result = 1.25  # CST 5
    of ShipClass.Battleship:
      result = 1.20  # CST 4
    of ShipClass.Battlecruiser:
      result = 1.15  # CST 3
    of ShipClass.HeavyCruiser:
      result = 1.10  # CST 3
    of ShipClass.Cruiser:
      result = 1.00
    of ShipClass.Destroyer:
      result = 0.90
    of ShipClass.Frigate:
      result = 0.80
    of ShipClass.Corvette:
      result = 0.70
    else:
      result = 1.0

  # Balanced personality: No strong preferences (default weights)

proc buildMilitaryOrders*(colony: Colony, tracker: var BudgetTracker,
                         militaryCount: int, canAffordMoreShips: bool,
                         atSquadronLimit: bool, cstLevel: int, act: GameAct,
                         personality: AIPersonality,
                         composition: FleetComposition,
                         intelligence: Table[SystemId, IntelligenceReport]): seq[BuildOrder] =
  ## Generate military build orders with PERSONALITY-DRIVEN ship preferences
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
  ## Build strategy: WEIGHTED SELECTION based on personality preferences
  ## - Aggressive AIs prefer capitals (Dreadnoughts, Battleships)
  ## - Economic AIs prefer cost-efficient escorts (Cruisers, Destroyers)
  ## - Tech-focused AIs prefer cutting-edge ships (highest CST requirement)
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

    # Choose ship based on CST tech, available budget, game phase, AND personality
    # WEIGHTED SELECTION: Build ship with highest (base_priority × personality_weight)
    let remaining = tracker.getRemainingBudget(Military)

    # Build list of affordable candidate ships within tech limits
    type ShipCandidate = object
      shipClass: ShipClass
      cost: int
      basePriority: float  # Higher = preferred (based on cost/power)
      personalityWeight: float

    var candidates: seq[ShipCandidate] = @[]

    # Super Dreadnought (CST 6, 250PP)
    if remaining >= 250 and cstLevel >= 6 and act >= GameAct.Act4_Endgame:
      candidates.add(ShipCandidate(
        shipClass: ShipClass.SuperDreadnought,
        cost: getShipConstructionCost(ShipClass.SuperDreadnought),
        basePriority: 9.0,
        personalityWeight: calculateShipPreference(personality, ShipClass.SuperDreadnought)
      ))

    # Dreadnought (CST 5, 200PP)
    if remaining >= 200 and cstLevel >= 5:
      candidates.add(ShipCandidate(
        shipClass: ShipClass.Dreadnought,
        cost: getShipConstructionCost(ShipClass.Dreadnought),
        basePriority: 8.0,
        personalityWeight: calculateShipPreference(personality, ShipClass.Dreadnought)
      ))

    # Battleship (CST 4, 150PP)
    if remaining >= 150 and cstLevel >= 4:
      candidates.add(ShipCandidate(
        shipClass: ShipClass.Battleship,
        cost: getShipConstructionCost(ShipClass.Battleship),
        basePriority: 7.0,
        personalityWeight: calculateShipPreference(personality, ShipClass.Battleship)
      ))

    # Battlecruiser (CST 3, 100PP)
    if remaining >= 100 and cstLevel >= 3:
      candidates.add(ShipCandidate(
        shipClass: ShipClass.Battlecruiser,
        cost: getShipConstructionCost(ShipClass.Battlecruiser),
        basePriority: 6.0,
        personalityWeight: calculateShipPreference(personality, ShipClass.Battlecruiser)
      ))

    # Heavy Cruiser (CST 2, 80PP)
    if remaining >= 80 and cstLevel >= 2:
      candidates.add(ShipCandidate(
        shipClass: ShipClass.HeavyCruiser,
        cost: getShipConstructionCost(ShipClass.HeavyCruiser),
        basePriority: 5.0,
        personalityWeight: calculateShipPreference(personality, ShipClass.HeavyCruiser)
      ))

    # Cruiser (CST 1, 60PP) - militaryCount gate for early game pacing
    if remaining >= 60 and militaryCount > 3:
      candidates.add(ShipCandidate(
        shipClass: ShipClass.Cruiser,
        cost: getShipConstructionCost(ShipClass.Cruiser),
        basePriority: 4.0,
        personalityWeight: calculateShipPreference(personality, ShipClass.Cruiser)
      ))

    # Destroyer (CST 1, 40PP)
    if remaining >= 40 and militaryCount > 2:
      candidates.add(ShipCandidate(
        shipClass: ShipClass.Destroyer,
        cost: getShipConstructionCost(ShipClass.Destroyer),
        basePriority: 3.0,
        personalityWeight: calculateShipPreference(personality, ShipClass.Destroyer)
      ))

    # Frigate (CST 1, 30PP)
    if remaining >= 30 and militaryCount > 1:
      candidates.add(ShipCandidate(
        shipClass: ShipClass.Frigate,
        cost: getShipConstructionCost(ShipClass.Frigate),
        basePriority: 2.0,
        personalityWeight: calculateShipPreference(personality, ShipClass.Frigate)
      ))

    # Corvette (CST 1, 20PP) - fallback option
    if remaining >= 20:
      candidates.add(ShipCandidate(
        shipClass: ShipClass.Corvette,
        cost: getShipConstructionCost(ShipClass.Corvette),
        basePriority: 1.0,
        personalityWeight: calculateShipPreference(personality, ShipClass.Corvette)
      ))

    if candidates.len == 0:
      break  # Not enough budget for any ship

    # PHASE 3: COMPOSITION DOCTRINE ADJUSTMENTS
    # Apply composition-based modifiers to maintain doctrine ratios
    let doctrine = getCompositionDoctrine(personality)
    var compositionModifier = 1.0

    # Calculate current composition ratios (avoid division by zero)
    let currentCapitalRatio = if composition.total > 0: float(composition.capitals) / float(composition.total) else: 0.0
    let currentEscortRatio = if composition.total > 0: float(composition.escorts) / float(composition.total) else: 0.0
    let currentSpecialistRatio = if composition.total > 0: float(composition.specialists) / float(composition.total) else: 0.0

    # PHASE 4: COUNTER-STRATEGY ADAPTATION
    # Assess aggregate threat and apply strategic modifiers
    let threatModifier = assessAggregateThreat(intelligence, personality)

    # Select ship with highest weighted score (personality × composition × threat)
    var bestScore = 0.0
    var bestCandidate: ShipCandidate
    for candidate in candidates:
      # Determine ship category for composition adjustment
      case candidate.shipClass
      of ShipClass.SuperDreadnought, ShipClass.Dreadnought, ShipClass.Battleship, ShipClass.Battlecruiser:
        # Capital ship: Boost if under target ratio
        compositionModifier = if currentCapitalRatio < doctrine.capitalRatio: 1.3 else: 1.0
        # Apply threat modifier to capitals (aggressive AIs escalate, defensive avoid)
        compositionModifier *= threatModifier
      of ShipClass.HeavyCruiser, ShipClass.Cruiser, ShipClass.LightCruiser, ShipClass.Destroyer, ShipClass.Frigate, ShipClass.Corvette:
        # Escort: Boost if under target ratio
        compositionModifier = if currentEscortRatio < doctrine.escortRatio: 1.3 else: 1.0
        # Inverse threat modifier for escorts (defensive AIs build more when threatened)
        if threatModifier < 1.0:
          compositionModifier *= (2.0 - threatModifier)  # Convert 0.85 to 1.15, etc.
      else:
        # Specialist: No adjustment for military orders (handled in special units)
        compositionModifier = 1.0

      let score = candidate.basePriority * candidate.personalityWeight * compositionModifier
      if score > bestScore:
        bestScore = score
        bestCandidate = candidate

    shipClass = bestCandidate.shipClass
    cost = bestCandidate.cost

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

proc buildReconnaissanceOrders*(colony: Colony, tracker: var BudgetTracker,
                                needScouts: bool, scoutCount: int): seq[BuildOrder] =
  ## Generate reconnaissance build orders (scouts)
  ## Uses BudgetTracker to prevent overspending
  ##
  ## Reconnaissance budget guarantees scout production for exploration and intel gathering.
  ## Scout targets scale with game progression:
  ## - Act 1: 3 scouts minimum (exploration)
  ## - Act 2: 6 scouts (reconnaissance network for invasions)
  ## - Act 3-4: 8 scouts (ELI mesh for invasion support)
  ##
  ## CRITICAL FIX: Build based on needScouts flag and budget, not global count check!
  ## Previous bug: scoutCount + result.len < 10 prevented ANY scout building
  ## Now: Build if needScouts=true AND we have reconnaissance budget
  result = @[]

  # Only build scouts if we actually need them
  if not needScouts:
    logDebug(LogCategory.lcAI,
             &"{tracker.houseId} Colony {colony.systemId}: Skipping scout build (needScouts=false, have {scoutCount} scouts)")
    return

  # Use Reconnaissance budget to build scouts
  let scoutCost = getShipConstructionCost(ShipClass.Scout)
  var scoutsBuilt = 0

  # Log budget availability for diagnostics
  let remaining = tracker.getRemainingBudget(Reconnaissance)
  logDebug(LogCategory.lcAI,
           &"{tracker.houseId} Colony {colony.systemId}: Scout build check - " &
           &"needScouts={needScouts}, scoutCount={scoutCount}, remaining={remaining}PP, cost={scoutCost}PP")

  # Cap: 2 scouts per colony per turn (prevents runaway loops)
  # Combined with BudgetTracker, ensures sustainable scout production
  while tracker.canAfford(Reconnaissance, scoutCost) and scoutsBuilt < 2:
    logInfo(LogCategory.lcAI,
            &"{tracker.houseId} Colony {colony.systemId}: Building scout " &
            &"(scout #{scoutCount + scoutsBuilt + 1}, remaining={tracker.getRemainingBudget(Reconnaissance)}PP)")
    result.add(BuildOrder(
      colonySystem: colony.systemId,
      buildType: BuildType.Ship,
      quantity: 1,
      shipClass: some(ShipClass.Scout),
      buildingType: none(string),
      industrialUnits: 0
    ))
    tracker.recordSpending(Reconnaissance, scoutCost)
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

      # Auto-build fighters to fill the Super Carrier (Phase 2: Fighter/Carrier Integration)
      # Super Carriers have 5-8 capacity, aim for 5 fighters (100 PP total)
      let fighterCost = getShipConstructionCost(ShipClass.Fighter)
      var fightersBuilt = 0
      while fightersBuilt < 5 and tracker.canAfford(SpecialUnits, fighterCost):
        result.add(BuildOrder(
          colonySystem: colony.systemId,
          buildType: BuildType.Ship,
          quantity: 1,
          shipClass: some(ShipClass.Fighter),
          buildingType: none(string),
          industrialUnits: 0
        ))
        tracker.recordSpending(SpecialUnits, fighterCost)
        fightersBuilt += 1

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

      # Auto-build fighters to fill the Carrier (Phase 2: Fighter/Carrier Integration)
      # Carriers have 3-5 capacity, aim for 3 fighters (60 PP total)
      let fighterCost = getShipConstructionCost(ShipClass.Fighter)
      var fightersBuilt = 0
      while fightersBuilt < 3 and tracker.canAfford(SpecialUnits, fighterCost):
        result.add(BuildOrder(
          colonySystem: colony.systemId,
          buildType: BuildType.Ship,
          quantity: 1,
          shipClass: some(ShipClass.Fighter),
          buildingType: none(string),
          industrialUnits: 0
        ))
        tracker.recordSpending(SpecialUnits, fighterCost)
        fightersBuilt += 1

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

  # Sort colonies prioritizing shipyards over spaceports (economy.md:5.1, 5.3)
  # Shipyard construction has no penalty, spaceport construction has 100% PC increase
  # Even though penalty isn't implemented in engine yet, prefer shipyards as best practice
  var coloniesToBuild = myColonies
  coloniesToBuild.sort(proc(a, b: Colony): int =
    let aHasShipyard = a.shipyards.len > 0
    let bHasShipyard = b.shipyards.len > 0

    # Primary sort: Shipyards before spaceports
    if aHasShipyard and not bHasShipyard:
      return -1  # a comes first
    elif bHasShipyard and not aHasShipyard:
      return 1   # b comes first

    # Tie-breaker: Sort by production (most productive first)
    return cmp(b.production, a.production)
  )

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

  # PHASE 3: FLEET COMPOSITION ANALYSIS
  # Analyze current fleet composition to maintain doctrine ratios
  let currentComposition = analyzeFleetComposition(filtered.ownFleets)

  # Process all colonies for build orders
  # IMPORTANT: Some build orders require facilities, others don't:
  # - Fighters: Planet-side only, NO facilities required (economy.md:3.10)
  # - Defense buildings: Planet-side, NO shipyard/spaceport required
  # - Ships (except fighters): Require shipyard OR spaceport
  for colony in coloniesToBuild:
    let hasShipyard = colony.shipyards.len > 0
    let hasSpaceport = colony.spaceports.len > 0
    let hasStarbase = colony.starbases.len > 0
    let canBuildShips = hasShipyard or hasSpaceport

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

    # Defense orders: Available at ALL colonies (planet-side construction)
    result.add(buildDefenseOrders(colony, tracker, needDefenses, hasStarbase))

    # Special units: Fighters available at ALL colonies (planet-side, no facilities)
    # Carriers/Transports/Raiders require shipyard/spaceport
    result.add(buildSpecialUnitsOrders(colony, tracker, needFighters, needCarriers,
                                      needTransports, needRaiders, canAffordMoreShips, cstLevel))

    # Facility orders: Build Spaceports at colonies without facilities
    # CRITICAL: This scales ship production from 3/turn (homeworld only) to 3N/turn (N colonies)
    # Without this, military budget remains massively underutilized (40-60% wasted)
    result.add(buildFacilityOrders(colony, tracker))

    # Ship build orders: Only for colonies with shipyard/spaceport
    if canBuildShips:
      # Generate orders for all objectives using shared BudgetTracker
      # CRITICAL: tracker is var parameter - gets modified by each build function
      # CRITICAL: Use PROJECTED counts to avoid double-building
      result.add(buildExpansionOrders(colony, tracker, needETACs, hasShipyard))

      let militaryOrders = buildMilitaryOrders(colony, tracker, projectedMilitaryCount,
                                              canAffordMoreShips, atSquadronLimit, cstLevel, act, personality, currentComposition, controller.intelligence)
      result.add(militaryOrders)
      projectedMilitaryCount += militaryOrders.len  # Update projected count

      let reconnaissanceOrders = buildReconnaissanceOrders(colony, tracker, projectedNeedScouts, projectedScoutCount)
      result.add(reconnaissanceOrders)
      projectedScoutCount += reconnaissanceOrders.len  # Update projected count

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
