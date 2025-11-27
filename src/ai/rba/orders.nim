## RBA Orders Module
##
## Main entry point for generating complete order packets from RBA AI

import std/[tables, options, random, sequtils, sets, strformat]
import ../../common/types/[core, tech, units]
import ../../engine/[gamestate, fog_of_war, orders, logger, fleet]
import ../../engine/economy/construction  # For getShipConstructionCost
import ../../engine/research/types as res_types
import ../common/types as ai_types  # For getCurrentGameAct, GameAct
import ./[controller_types, budget, espionage, economic, tactical, strategic, diplomacy, intelligence, logistics, standing_orders_manager]

export core, orders, standing_orders_manager

proc calculateProjectedTreasury*(filtered: FilteredGameState): int =
  ## Calculate projected treasury for AI planning
  ## Treasury projection = current + expected income - expected maintenance
  ##
  ## CRITICAL: AI generates orders BEFORE income/maintenance phase in turn resolution
  ## But build orders are processed AFTER income is added. Without projection,
  ## AI sees treasury=2 PP, makes no builds, then economy has 52 PP available.
  let currentTreasury = filtered.ownHouse.treasury

  # Calculate expected income from all owned colonies
  var expectedIncome = 0
  for colony in filtered.ownColonies:
    # Income = GCO × tax rate
    # GCO (Gross Colonial Output) is the total economic output
    expectedIncome += (colony.grossOutput * filtered.ownHouse.taxPolicy.currentRate) div 100

  # Calculate expected maintenance from fleets
  var expectedMaintenance = 0
  for fleet in filtered.ownFleets:
    # Each fleet costs ~2 PP maintenance (simplified)
    expectedMaintenance += 2

  result = currentTreasury + expectedIncome - expectedMaintenance
  result = max(result, 0)  # Can't go negative

  logDebug(LogCategory.lcAI,
           &"{filtered.viewingHouse} Projected treasury: current={currentTreasury}PP, " &
           &"income≈{expectedIncome}PP, maintenance≈{expectedMaintenance}PP, " &
           &"projected={result}PP")

proc generateResearchAllocation*(controller: AIController, filtered: FilteredGameState): res_types.ResearchAllocation =
  ## Generate research allocation based on personality
  ## Allocates PP to research based on total production and tech priority
  result = res_types.ResearchAllocation(
    economic: 0,
    science: 0,
    technology: initTable[TechField, int]()
  )

  let p = controller.personality
  let house = filtered.ownHouse

  # Calculate research budget from treasury (not production)
  # Research competes with builds for treasury resources
  let researchBudget = int(float(house.treasury) * p.techPriority)

  # DEBUG: Log research budget calculation
  logDebug(LogCategory.lcAI,
           &"{controller.houseId} Research Budget: {researchBudget}PP " &
           &"(treasury={house.treasury}, techPriority={p.techPriority:.2f})")

  if researchBudget > 0:
    # Distribute research budget across EL/SL/TRP based on strategy
    if p.techPriority > 0.6:
      # Heavy research investment - balance across all three categories
      result.economic = researchBudget div 3        # 33% to EL
      result.science = researchBudget div 4         # 25% to SL
      let techBudget = researchBudget - result.economic - result.science

      if p.aggression > 0.5:
        # Aggressive: weapons + cloaking + construction
        result.technology[TechField.WeaponsTech] = techBudget * 2 div 5
        result.technology[TechField.CloakingTech] = techBudget div 5
        result.technology[TechField.ConstructionTech] = techBudget div 5
        result.technology[TechField.ElectronicIntelligence] = techBudget div 5
      else:
        # Peaceful: infrastructure + counter-intel for defense
        result.technology[TechField.ConstructionTech] = techBudget div 2
        result.technology[TechField.TerraformingTech] = techBudget div 4
        result.technology[TechField.ElectronicIntelligence] = techBudget div 4
    elif p.economicFocus > 0.7:
      # Economic focus: prioritize EL/SL for growth
      result.economic = researchBudget * 2 div 5   # 40% to EL
      result.science = researchBudget * 2 div 5    # 40% to SL
      let techBudget = researchBudget - result.economic - result.science
      result.technology[TechField.ConstructionTech] = techBudget div 2
      result.technology[TechField.TerraformingTech] = techBudget div 2
    elif p.aggression > 0.7:
      # Aggressive: minimal EL/SL, focus on military tech
      result.economic = researchBudget div 5       # 20% to EL
      result.science = researchBudget div 5        # 20% to SL
      let techBudget = researchBudget - result.economic - result.science
      result.technology[TechField.WeaponsTech] = techBudget div 2
      result.technology[TechField.ConstructionTech] = techBudget div 2
    else:
      # Balanced
      result.economic = researchBudget div 3
      result.science = researchBudget div 3
      let techBudget = researchBudget - result.economic - result.science
      result.technology[TechField.ConstructionTech] = techBudget div 2
      result.technology[TechField.WeaponsTech] = techBudget div 2

proc calculateTotalCost(buildOrders: seq[BuildOrder]): int =
  ## Calculate total PP cost of all build orders
  result = 0
  for order in buildOrders:
    case order.buildType
    of BuildType.Ship:
      if order.shipClass.isSome:
        result += getShipConstructionCost(order.shipClass.get()) * order.quantity
    of BuildType.Building:
      # Building costs vary by type, skip for now as we don't have cost lookup
      discard
    of BuildType.Infrastructure:
      # Infrastructure costs are handled separately, skip for now
      discard

proc generateAIOrders*(controller: var AIController, filtered: FilteredGameState, rng: var Rand): OrderPacket =
  ## Generate complete order packet using all RBA subsystems
  ##
  ## This is the main entry point for RBA AI order generation.
  ## It coordinates all subsystems to produce a coherent strategic plan.

  result = OrderPacket(
    houseId: controller.houseId,
    turn: filtered.turn,
    treasury: filtered.ownHouse.treasury,  # Capture treasury at AI planning time
    fleetOrders: @[],
    buildOrders: @[],
    researchAllocation: res_types.ResearchAllocation(
      economic: 0,
      science: 0,
      technology: initTable[TechField, int]()
    ),  # Will be set below with treasury reservation
    diplomaticActions: @[],
    populationTransfers: @[],
    squadronManagement: @[],
    cargoManagement: @[],
    terraformOrders: @[],
    espionageAction: none(EspionageAttempt),
    ebpInvestment: 0,
    cipInvestment: 0
  )

  let p = controller.personality
  let currentAct = ai_types.getCurrentGameAct(filtered.turn)

  # ==========================================================================
  # TREASURY RESERVATION SYSTEM
  # ==========================================================================
  # Sequential allocation prevents race condition where research, builds, and
  # espionage all independently claim percentages of the same full treasury
  #
  # CRITICAL: Use PROJECTED treasury (current + income - maintenance) because:
  # - AI generates orders BEFORE income/maintenance phase
  # - Orders are processed AFTER income is added
  # - Without projection, AI sees 2 PP, makes no builds, economy has 52 PP available
  var remainingTreasury = calculateProjectedTreasury(filtered)
  var reservedBudgets = initTable[string, int]()

  # 1. RESEARCH CLAIMS FIRST (highest priority)
  let researchBudget = int(float(remainingTreasury) * p.techPriority)
  result.researchAllocation = generateResearchAllocation(controller, filtered)
  remainingTreasury -= researchBudget
  reservedBudgets["research"] = researchBudget

  logDebug(LogCategory.lcAI,
           &"{controller.houseId} Treasury reservation: Research={researchBudget}PP, " &
           &"remaining={remainingTreasury}PP")

  # ==========================================================================
  # STRATEGIC PLANNING
  # ==========================================================================
  # NOTE: Strategic assessment is implicitly done by tactical/strategic modules
  # when they evaluate targets and threats. No explicit "updateStrategicAssessment" needed.

  # NOTE: Intelligence gathering is done by the intelligence module's functions
  # as needed during target selection and threat assessment

  # ==========================================================================
  # BUILD ORDERS (Using RBA Budget Module)
  # ==========================================================================
  # Generate build orders using multi-objective budget allocation
  let myColonies = getOwnedColonies(filtered, controller.houseId)

  # Calculate context flags for build decision-making
  # These are simple heuristics - budget module makes the final decisions
  # 2. BUILD ORDERS CLAIM SECOND (from remaining treasury)
  let availableBudget = remainingTreasury  # Use remaining after research, not full treasury!

  # Count military vs scout squadrons and special units
  var militaryCount = 0
  var scoutCount = 0
  var planetBreakerCount = 0
  for fleet in filtered.ownFleets:
    for squadron in fleet.squadrons:
      if squadron.flagship.shipClass == ShipClass.Scout:
        scoutCount += 1
      elif squadron.flagship.shipClass == ShipClass.PlanetBreaker:
        planetBreakerCount += 1
      else:
        militaryCount += 1

  let canAffordMoreShips = availableBudget >= 200  # Basic affordability check
  let atSquadronLimit = false  # Engine manages squadron limits, we just build

  # Simple threat assessment
  let isUnderThreat = filtered.visibleFleets.anyIt(it.owner != controller.houseId)

  # Build needs based on what we have (gated by CST tech level)
  let cst = filtered.ownHouse.techTree.levels.constructionTech

  # Act-aware build needs (4-act structure from DECISION_FRAMEWORK.md)
  # Act 1: 70-80% expansion (ETACs), 10-20% military (minimal), 10% intel (scouts)
  # Act 2: 30-40% expansion (opportunistic), 50-60% military, 10% tech
  # Act 3+: 0-10% expansion (conquest only), 80-90% military

  # Count enemy colonies visible to us (for scout targeting)
  var knownEnemyColonies = 0
  for visCol in filtered.visibleColonies:
    if visCol.owner != controller.houseId:
      knownEnemyColonies += 1

  # ETACs: Colonization ships (NOT military!)
  let needETACs = case currentAct
    of GameAct.Act1_LandGrab:
      true  # ALWAYS build ETACs in Act 1 (land grab phase)
    of GameAct.Act2_RisingTensions:
      myColonies.len < 8  # Opportunistic colonization in Act 2
    else:
      false  # Zero colonization in Act 3-4 (conquest only)

  # Scouts: For intelligence gathering and ELI mesh
  # CRITICAL FIX: Build scouts BEFORE we find enemies (not after!)
  # Scouts are needed to FIND enemy colonies, so can't wait for knownEnemyColonies > 0
  let needScouts = case currentAct
    of GameAct.Act1_LandGrab:
      scoutCount < 3  # 3 scouts minimum for exploration & early intel
    of GameAct.Act2_RisingTensions:
      scoutCount < 6  # 6 scouts for intelligence network (ELI mesh preparation)
    else:
      scoutCount < 8  # Act 3+: 8 scouts for full ELI mesh + espionage support

  # CRITICAL FIX: Build defenses earlier! Ground batteries need CST 1, not CST 3
  # Old logic required CST 3, leaving 59% of colonies undefended
  let needDefenses = cst >= 1  # Ground batteries at CST 1, starbases at CST 3
  let needFighters = cst >= 2 and p.aggression > 0.3  # Fighter squadrons (lowered from CST 3 to 2)
  let needCarriers = cst >= 2 and needFighters  # Carriers support fighters (lowered from CST 3 to 2)
  let needTransports = cst >= 1 and p.aggression > 0.3  # Troop transports (lowered aggression from 0.4 to 0.3)
  let needRaiders = cst >= 2 and p.aggression > 0.5  # Raiders (lowered CST from 3 to 2, aggression from 0.6 to 0.5)

  result.buildOrders = generateBuildOrdersWithBudget(
    controller, filtered, filtered.ownHouse, myColonies, currentAct, p,
    isUnderThreat, needETACs, needDefenses, needScouts, needFighters,
    needCarriers, needTransports, needRaiders, canAffordMoreShips,
    atSquadronLimit, militaryCount, scoutCount, planetBreakerCount, availableBudget
  )

  # Calculate total build cost and reserve from treasury
  let totalBuildCost = calculateTotalCost(result.buildOrders)
  remainingTreasury -= totalBuildCost
  reservedBudgets["builds"] = totalBuildCost

  logDebug(LogCategory.lcAI,
           &"{controller.houseId} Treasury reservation: Builds={totalBuildCost}PP, " &
           &"remaining={remainingTreasury}PP")

  # ==========================================================================
  # STRATEGIC OPERATIONS PLANNING
  # ==========================================================================
  # Identify invasion opportunities and plan coordinated operations
  # This populates controller.operations which are then executed in fleet orders
  # Strategic planning happens in ALL acts - personality determines invasion timing
  if p.aggression > 0.4:
    let invasionTargets = identifyInvasionOpportunities(controller, filtered)

    # Plan invasions for all viable targets (no artificial limit)
    for targetSystem in invasionTargets:
      # Check if we already have an operation targeting this system
      var alreadyTargeted = false
      for op in controller.operations:
        if op.targetSystem == targetSystem:
          alreadyTargeted = true
          break

      if not alreadyTargeted:
        planCoordinatedInvasion(controller, filtered, targetSystem, filtered.turn)

  # ==========================================================================
  # FLEET ORDERS (Using RBA Tactical Module)
  # ==========================================================================
  # Generate tactical fleet orders (strategic priorities inform tactical decisions)
  let tacticalOrders = generateFleetOrders(controller, filtered, rng)

  # Add tactical orders to result (will be filtered by logistics later if needed)
  for order in tacticalOrders:
    result.fleetOrders.add(order)

  # ==========================================================================
  # LOGISTICS (Asset Lifecycle Management)
  # ==========================================================================
  # Philosophy: Optimize what you have after strategic/tactical decisions made
  # Logistics handles: cargo loading, PTU transfers, fleet rebalancing, mothballing
  # NOTE: Logistics runs AFTER tactical so it can optimize based on tactical assignments
  # NOTE: Logistics does not consume treasury, it's purely asset optimization
  logInfo(LogCategory.lcAI,
          &"{controller.houseId} === Logistics Optimization (post-tactical) ===")

  let logisticsOrders = logistics.generateLogisticsOrders(controller, filtered, currentAct)

  result.cargoManagement = logisticsOrders.cargo
  result.populationTransfers = logisticsOrders.population
  result.squadronManagement = logisticsOrders.squadrons

  # Build set of fleets that logistics wants to manage (lifecycle operations)
  var logisticsControlledFleets: HashSet[FleetId]
  for order in logisticsOrders.fleetOrders:
    logisticsControlledFleets.incl(order.fleetId)

  # Remove tactical orders for fleets that logistics is managing (lifecycle takes priority)
  var filteredTacticalOrders: seq[FleetOrder] = @[]
  for order in result.fleetOrders:
    if order.fleetId notin logisticsControlledFleets:
      filteredTacticalOrders.add(order)
    else:
      logInfo(LogCategory.lcAI,
              &"{controller.houseId} Fleet {order.fleetId}: Logistics override " &
              &"(lifecycle management)")

  # Replace fleet orders with filtered tactical + logistics lifecycle orders
  result.fleetOrders = filteredTacticalOrders
  result.fleetOrders.add(logisticsOrders.fleetOrders)

  # ==========================================================================
  # DIPLOMATIC ACTIONS (Using RBA Diplomacy Module)
  # ==========================================================================
  # TODO: Diplomatic actions need full implementation
  # The diplomacy module has assessment functions but needs action generation
  # Required features:
  # - Alliance proposals based on mutual enemies and relative strength
  # - Trade agreements based on economic needs
  # - Non-aggression pacts for defensive players
  # - Break alliance when advantageous
  result.diplomaticActions = @[]

  # ==========================================================================
  # ESPIONAGE (Using RBA Espionage Module)
  # ==========================================================================
  # 3. ESPIONAGE CLAIMS THIRD (from remaining treasury after research and builds)
  # PHASE 1: Calculate espionage investment (2-5% of treasury)
  # This determines how many EBP/CIP points we'll have THIS TURN
  let espionageInvestment = if p.riskTolerance > 0.6:
    0.05  # High risk tolerance: 5% investment
  elif p.economicFocus > 0.7:
    0.02  # Economic focus: 2% investment (minimal)
  else:
    0.03  # Balanced: 3% investment

  let totalInvestment = int(float(remainingTreasury) * espionageInvestment)  # Use remaining, not full treasury!
  let ebpInvestment = totalInvestment div 2  # Half to offensive EBP
  let cipInvestment = totalInvestment div 2  # Half to defensive CIP
  remainingTreasury -= totalInvestment
  reservedBudgets["espionage"] = totalInvestment

  # PHASE 2: Calculate projected EBP/CIP (current + investment)
  # This is the budget available THIS TURN for espionage actions
  let projectedEBP = filtered.ownHouse.espionageBudget.ebpPoints + ebpInvestment
  let projectedCIP = filtered.ownHouse.espionageBudget.cipPoints + cipInvestment

  logDebug(LogCategory.lcAI,
           &"{controller.houseId} Treasury reservation: Espionage={totalInvestment}PP, " &
           &"remaining={remainingTreasury}PP")

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Turn {filtered.turn}: Espionage budget - " &
          &"investment={totalInvestment}PP, projected EBP={projectedEBP}, projected CIP={projectedCIP}")

  # PHASE 3: Generate espionage action using projected budget
  result.espionageAction = generateEspionageAction(controller, filtered, projectedEBP, projectedCIP, rng)

  # PHASE 4: Store investment in order packet (will be processed by engine)
  result.ebpInvestment = ebpInvestment
  result.cipInvestment = cipInvestment

  # ==========================================================================
  # ECONOMIC ORDERS (Using RBA Economic Module)
  # ==========================================================================
  # NOTE: populationTransfers already handled by logistics module above
  # NOTE: squadronManagement already handled by logistics module above
  # NOTE: cargoManagement already handled by logistics module above
  # 4. TERRAFORM ONLY IF SUFFICIENT REMAINS (>800 PP threshold)
  if remainingTreasury > 800:
    result.terraformOrders = generateTerraformOrders(controller, filtered, rng)
  else:
    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Skipping terraform: only {remainingTreasury}PP remaining")

  # FINAL TREASURY ALLOCATION LOGGING
  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Treasury allocation complete: " &
          &"Research={reservedBudgets[\"research\"]}PP, " &
          &"Builds={reservedBudgets[\"builds\"]}PP, " &
          &"Espionage={reservedBudgets[\"espionage\"]}PP, " &
          &"remaining={remainingTreasury}PP")

  # ==========================================================================
  # STANDING ORDERS (QoL Integration)
  # ==========================================================================
  # Assign standing orders to fleets without explicit tactical orders
  # Standing orders provide consistent behavior for routine tasks:
  # - Damaged fleets automatically return to shipyard (AutoRepair)
  # - ETAC fleets automatically colonize (AutoColonize)
  # - Defensive fleets guard homeworld (DefendSystem)
  # - Risk-averse scouts retreat when outnumbered (AutoEvade)
  #
  # NOTE: Standing orders only execute when no explicit order is given
  # Tactical orders take priority, standing orders handle the rest
  logInfo(LogCategory.lcAI,
          &"{controller.houseId} === Standing Orders Assignment ===")

  let standingOrders = assignStandingOrders(controller, filtered, filtered.turn)

  # ==========================================================================
  # STANDING ORDERS EXECUTION
  # ==========================================================================
  # Convert standing orders to executable FleetOrders for fleets without explicit orders
  # Build set of fleets that already have explicit orders (tactical or logistics)
  var fleetsWithExplicitOrders = initHashSet[FleetId]()
  for order in result.fleetOrders:
    fleetsWithExplicitOrders.incl(order.fleetId)

  # Convert standing orders to FleetOrders for fleets without explicit orders
  var standingOrdersExecuted = 0
  for fleetId, standingOrder in standingOrders:
    if fleetId notin fleetsWithExplicitOrders:
      # This fleet has no tactical/logistics order, execute its standing order
      # Find the fleet in our filtered state
      var fleet: Option[Fleet] = none(Fleet)
      for f in filtered.ownFleets:
        if f.id == fleetId:
          fleet = some(f)
          break

      if fleet.isSome:
        # Convert standing order to executable FleetOrder
        let fleetOrder = convertStandingOrderToFleetOrder(
          standingOrder,
          fleet.get,
          filtered
        )

        if fleetOrder.isSome:
          result.fleetOrders.add(fleetOrder.get)
          standingOrdersExecuted += 1
          logDebug(LogCategory.lcAI,
                   &"{controller.houseId} Fleet {fleetId}: Executing standing order " &
                   &"{standingOrder.orderType} → {fleetOrder.get.orderType}")
        else:
          logDebug(LogCategory.lcAI,
                   &"{controller.houseId} Fleet {fleetId}: Standing order " &
                   &"{standingOrder.orderType} cannot execute (no valid target)")
      else:
        logWarn(LogCategory.lcAI,
                &"{controller.houseId} Fleet {fleetId}: Standing order assigned but fleet not found")

  # Log summary
  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Standing Orders: {standingOrders.len} assigned, " &
          &"{standingOrdersExecuted} executed, " &
          &"{fleetsWithExplicitOrders.len} under tactical/logistics control")

  # Store standing orders in controller for next turn
  controller.standingOrders = standingOrders
