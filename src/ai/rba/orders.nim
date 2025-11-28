## RBA Orders Module
##
## Main entry point for generating complete order packets from RBA AI

import std/[tables, options, random, sequtils, sets, strformat]
import ../../common/types/[core, tech, units]
import ../../engine/[gamestate, fog_of_war, orders, logger, fleet]
import ../../engine/economy/construction  # For getShipConstructionCost
import ../../engine/research/types as res_types
import ../../engine/research/advancement  # For max tech level constants
import ../common/types as ai_types  # For getCurrentGameAct, GameAct
import ./[controller_types, budget, espionage, economic, tactical, strategic, diplomacy, intelligence, logistics, standing_orders_manager, admiral]
import ./config  # RBA configuration system

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

proc generateResearchAllocation*(controller: AIController, filtered: FilteredGameState, researchBudget: int): res_types.ResearchAllocation =
  ## Generate research allocation based on personality
  ## Uses pre-calculated research budget from projected treasury (not raw treasury)
  result = res_types.ResearchAllocation(
    economic: 0,
    science: 0,
    technology: initTable[TechField, int]()
  )

  let p = controller.personality

  # DEBUG: Log research budget allocation
  logDebug(LogCategory.lcAI,
           &"{controller.houseId} Research Budget: {researchBudget}PP " &
           &"(from projected treasury, techPriority={p.techPriority:.2f})")

  if researchBudget > 0:
    # Get current tech levels to check for maxed EL/SL
    let currentEL = filtered.ownHouse.techTree.levels.economicLevel
    let currentSL = filtered.ownHouse.techTree.levels.scienceLevel

    # Check if EL/SL are at maximum levels (caps from advancement.nim)
    let elMaxed = currentEL >= maxEconomicLevel  # EL caps at 11
    let slMaxed = currentSL >= maxScienceLevel   # SL caps at 8

    # Log max level detection for diagnostics
    if elMaxed or slMaxed:
      logInfo(LogCategory.lcAI,
              &"{controller.houseId} Tech caps reached - EL={currentEL}/{maxEconomicLevel} " &
              &"(maxed={elMaxed}), SL={currentSL}/{maxScienceLevel} (maxed={slMaxed})")

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

    # REALLOCATION LOGIC: Redirect budget from maxed EL/SL to TRP
    # This prevents AI from wasting RP on technologies that cannot advance
    var redirectedBudget = 0

    # If EL is maxed, redirect ERP to TRP (Construction priority)
    if elMaxed and result.economic > 0:
      redirectedBudget += result.economic
      logInfo(LogCategory.lcAI,
              &"{controller.houseId} Redirecting {result.economic}PP from maxed EL to TRP")
      result.economic = 0

    # If SL is maxed, redirect SRP to TRP (Weapons priority for aggressive, Construction otherwise)
    if slMaxed and result.science > 0:
      redirectedBudget += result.science
      logInfo(LogCategory.lcAI,
              &"{controller.houseId} Redirecting {result.science}PP from maxed SL to TRP")
      result.science = 0

    # Distribute redirected budget to TRP fields based on personality
    if redirectedBudget > 0:
      if p.aggression > 0.5:
        # Aggressive: prioritize weapons and construction
        result.technology[TechField.WeaponsTech] = result.technology.getOrDefault(TechField.WeaponsTech) + (redirectedBudget * 2 div 3)
        result.technology[TechField.ConstructionTech] = result.technology.getOrDefault(TechField.ConstructionTech) + (redirectedBudget div 3)
      else:
        # Peaceful/Economic: prioritize construction and terraforming
        result.technology[TechField.ConstructionTech] = result.technology.getOrDefault(TechField.ConstructionTech) + (redirectedBudget * 2 div 3)
        result.technology[TechField.TerraformingTech] = result.technology.getOrDefault(TechField.TerraformingTech) + (redirectedBudget div 3)

      logInfo(LogCategory.lcAI,
              &"{controller.houseId} Redirected {redirectedBudget}PP total to TRP fields")

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
  # CRITICAL FIX: Cap research at 25% to leave budget for builds (scouts, ships, facilities)
  # Previous bug: techPriority=0.8 → 80% to research, only 20% for builds → no scouts!
  # Fixed: Max 25% to research, min 75% for builds → scouts affordable
  let researchPct = min(p.techPriority * 0.30, globalRBAConfig.orders.research_max_percent)  # Scale down and cap
  let researchBudget = int(float(remainingTreasury) * researchPct)
  result.researchAllocation = generateResearchAllocation(controller, filtered, researchBudget)
  remainingTreasury -= researchBudget
  reservedBudgets["research"] = researchBudget

  logDebug(LogCategory.lcAI,
           &"{controller.houseId} Treasury reservation: Research={researchBudget}PP ({int(researchPct*100)}%), " &
           &"remaining={remainingTreasury}PP")

  # ==========================================================================
  # 2. ESPIONAGE CLAIMS SECOND (from ORIGINAL treasury, not remaining)
  # ==========================================================================
  # CRITICAL FIX: Calculate espionage from ORIGINAL treasury, not remaining!
  # Previous bug: Espionage got 2-5% of remaining treasury (after research took 50-100%) = ~0 PP
  # Now: Espionage gets 2-5% of ORIGINAL treasury, guaranteeing meaningful budget
  #
  # Example: Treasury=500, Research=60%=300, Espionage=3% of REMAINING=6 (0 EBP!) ❌
  # Fixed:   Treasury=500, Research=60%=300, Espionage=3% of ORIGINAL=15 (7 EBP) ✓
  let projectedTreasury = calculateProjectedTreasury(filtered)  # Cache original value
  let espionageInvestmentPct = globalRBAConfig.orders.espionage_investment_percent

  let espionageTotalInvestment = int(float(projectedTreasury) * espionageInvestmentPct)
  let espionageEBPInvestment = espionageTotalInvestment div 2  # Half to offensive EBP
  let espionageCIPInvestment = espionageTotalInvestment div 2  # Half to defensive CIP
  remainingTreasury -= espionageTotalInvestment
  reservedBudgets["espionage"] = espionageTotalInvestment

  logInfo(LogCategory.lcAI,
          &"DIAGNOSTIC: {controller.houseId} Espionage budget BEFORE builds: " &
          &"treasury={filtered.ownHouse.treasury}, investment={espionageTotalInvestment}PP " &
          &"({int(espionageInvestmentPct * 100)}%), EBP={espionageEBPInvestment}, CIP={espionageCIPInvestment}, " &
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
  # 3. BUILD ORDERS CLAIM THIRD (from remaining treasury after research and espionage)
  let availableBudget = remainingTreasury  # Use remaining after research and espionage, not full treasury!

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

  let canAffordMoreShips = availableBudget >= 50  # Allow even cheap corvettes (50 PP)
  let atSquadronLimit = false  # Engine manages squadron limits, we just build

  # Log affordability decision for diagnostics
  logDebug(LogCategory.lcAI,
    &"Build affordability: budget={availableBudget}PP, threshold=50PP, canAfford={canAffordMoreShips}")

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
  # INCREASED THRESHOLDS: Target 5-7 scouts for robust ELI mesh coverage
  let needScouts = case currentAct
    of GameAct.Act1_LandGrab:
      scoutCount < globalRBAConfig.orders.scout_count_act1  # 5 scouts minimum for exploration & early intel
    of GameAct.Act2_RisingTensions:
      scoutCount < globalRBAConfig.orders.scout_count_act2  # 7 scouts for intelligence network (ELI mesh preparation)
    else:
      scoutCount < globalRBAConfig.orders.scout_count_act3_plus  # Act 3+: 9 scouts for full ELI mesh + espionage support

  logInfo(LogCategory.lcAI,
          &"DIAGNOSTIC: {controller.houseId} Scout decision - Act={currentAct}, " &
          &"scoutCount={scoutCount}, needScouts={needScouts}")

  # ==========================================================================
  # ADMIRAL MODULE (Strategic Fleet Rebalancing & Requirements Generation)
  # ==========================================================================
  # Admiral MUST run BEFORE build orders to generate requirements for this turn
  # Order is critical:
  #   1. Admiral analyzes fleet state
  #   2. Admiral generates build requirements
  #   3. Build system executes requirements (this turn, not next turn!)
  #
  # Admiral provides strategic oversight:
  # - Distributes Defender fleets across colonies (fixes Unknown-Unknown #3)
  # - Generates requirements-driven build orders (Phase 3)
  # - Act-aware fleet reorganization (split in Act 1, merge in Act 2+)
  # - Defensive consolidation under threat
  # - Opportunistic counter-attacks
  #
  # NOTE: Admiral generates standing order updates + build requirements
  logInfo(LogCategory.lcAI,
          &"{controller.houseId} === Admiral Strategic Analysis ===")

  # Build empty tactical orders table (Admiral runs before tactical)
  var emptyTacticalOrders = initTable[FleetId, FleetOrder]()

  let admiralOrders = generateAdmiralOrders(
    controller,
    filtered,
    currentAct,
    emptyTacticalOrders  # Empty because tactical hasn't run yet
  )

  # Merge Admiral's standing order updates into controller state
  updateStandingOrdersWithAdmiralChanges(controller, admiralOrders)

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Admiral: Applied {admiralOrders.len} strategic reassignments")

  # ==========================================================================
  # BUILD ORDERS (Execute Admiral Requirements + Standard Builds)
  # ==========================================================================
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
    atSquadronLimit, militaryCount, scoutCount, planetBreakerCount, availableBudget,
    controller.admiralRequirements  # Phase 3: Pass Admiral requirements to build system
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
  # STANDING ORDERS ASSIGNMENT (QoL Integration)
  # ==========================================================================
  # Assign standing orders BEFORE tactical so Tactical can skip fleets with standing orders
  # Standing orders provide consistent behavior for routine tasks:
  # - Damaged fleets automatically return to shipyard (AutoRepair)
  # - ETAC fleets automatically colonize (AutoColonize)
  # - Defensive fleets guard homeworld (DefendSystem)
  # - Risk-averse scouts retreat when outnumbered (AutoEvade)
  logInfo(LogCategory.lcAI,
          &"{controller.houseId} === Standing Orders Assignment ===")

  let standingOrders = assignStandingOrders(controller, filtered, filtered.turn)

  # Update controller immediately so Tactical can see these assignments
  controller.standingOrders = standingOrders

  # ==========================================================================
  # STRATEGIC STANDING ORDERS → EXPLICIT FLEET ORDERS
  # ==========================================================================
  # Convert DefendSystem and other strategic standing orders to explicit FleetOrders
  # These are strategic commitments that should not be overridden by Tactical
  logInfo(LogCategory.lcAI,
          &"{controller.houseId} === Converting Strategic Standing Orders ===")

  var strategicOrdersConverted = 0
  for fleetId, standingOrder in standingOrders:
    # Only convert strategic standing orders (DefendSystem, AutoRepair)
    if standingOrder.orderType in {StandingOrderType.DefendSystem, StandingOrderType.AutoRepair}:
      # Find fleet
      var fleetOpt: Option[Fleet] = none(Fleet)
      for f in filtered.ownFleets:
        if f.id == fleetId:
          fleetOpt = some(f)
          break

      if fleetOpt.isSome:
        let fleet = fleetOpt.get()
        let orderOpt = convertStandingOrderToFleetOrder(standingOrder, fleet, filtered)

        if orderOpt.isSome:
          result.fleetOrders.add(orderOpt.get())
          strategicOrdersConverted += 1
          logDebug(LogCategory.lcAI,
                   &"{controller.houseId} Fleet {fleetId}: Converted {standingOrder.orderType} " &
                   &"to explicit FleetOrder (strategic commitment)")

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Converted {strategicOrdersConverted} strategic standing orders to explicit FleetOrders")

  # ==========================================================================
  # FLEET ORDERS (Using RBA Tactical Module)
  # ==========================================================================
  # Generate tactical fleet orders (strategic priorities inform tactical decisions)
  # NOTE: Tactical can now skip fleets with DefendSystem standing orders
  let tacticalOrders = generateFleetOrders(controller, filtered, rng)

  # Add tactical orders to result (will be filtered by logistics later if needed)
  for order in tacticalOrders:
    result.fleetOrders.add(order)

  # Mark systems for intelligence updates based on fleet movements
  # Intelligence will be gathered when fleets arrive at destination systems
  for order in result.fleetOrders:
    if order.orderType == FleetOrderType.Move and order.targetSystem.isSome:
      # Note: Intel update happens automatically during resolution when fleet arrives
      # This comment documents the expected behavior
      discard

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
  # ESPIONAGE ACTION GENERATION (Budget already reserved above)
  # ==========================================================================
  # Calculate projected EBP/CIP (current + investment)
  # This is the budget available THIS TURN for espionage actions
  let projectedEBP = filtered.ownHouse.espionageBudget.ebpPoints + espionageEBPInvestment
  let projectedCIP = filtered.ownHouse.espionageBudget.cipPoints + espionageCIPInvestment

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Turn {filtered.turn}: Espionage budget - " &
          &"investment={espionageTotalInvestment}PP, projected EBP={projectedEBP}, projected CIP={projectedCIP}")

  # Generate espionage action using projected budget
  result.espionageAction = generateEspionageAction(controller, filtered, projectedEBP, projectedCIP, rng)

  # Store investment in order packet (will be processed by engine)
  result.ebpInvestment = espionageEBPInvestment
  result.cipInvestment = espionageCIPInvestment

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
  # FALLBACK STANDING ORDERS EXECUTION
  # ==========================================================================
  # Convert fallback standing orders to executable FleetOrders for fleets without explicit orders
  # NOTE: Strategic standing orders (DefendSystem, AutoRepair) already converted earlier
  # Build set of fleets that already have explicit orders (tactical or logistics or strategic)
  var fleetsWithExplicitOrders = initHashSet[FleetId]()
  for order in result.fleetOrders:
    fleetsWithExplicitOrders.incl(order.fleetId)

  # Convert fallback standing orders for fleets without explicit orders
  var fallbackOrdersExecuted = 0
  for fleetId, standingOrder in standingOrders:
    # Skip strategic orders (already converted earlier)
    if standingOrder.orderType in {StandingOrderType.DefendSystem, StandingOrderType.AutoRepair}:
      continue

    if fleetId notin fleetsWithExplicitOrders:
      # This fleet has no explicit order, execute its fallback standing order
      var fleetOpt: Option[Fleet] = none(Fleet)
      for f in filtered.ownFleets:
        if f.id == fleetId:
          fleetOpt = some(f)
          break

      if fleetOpt.isSome:
        let fleet = fleetOpt.get()
        let orderOpt = convertStandingOrderToFleetOrder(standingOrder, fleet, filtered)

        if orderOpt.isSome:
          result.fleetOrders.add(orderOpt.get())
          fallbackOrdersExecuted += 1
          logDebug(LogCategory.lcAI,
                   &"{controller.houseId} Fleet {fleetId}: Executing fallback standing order " &
                   &"{standingOrder.orderType} → {orderOpt.get.orderType}")
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
          &"{strategicOrdersConverted} strategic converted, {fallbackOrdersExecuted} fallback executed, " &
          &"{fleetsWithExplicitOrders.len} total explicit orders")

  # NOTE: Standing orders already stored in controller earlier (before Tactical)
