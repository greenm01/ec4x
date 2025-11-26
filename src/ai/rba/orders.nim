## RBA Orders Module
##
## Main entry point for generating complete order packets from RBA AI

import std/[tables, options, random, sequtils, sets, strformat]
import ../../common/types/[core, tech, units]
import ../../engine/[gamestate, fog_of_war, orders, logger]
import ../../engine/research/types as res_types
import ../common/types as ai_types  # For getCurrentGameAct, GameAct
import ./[controller_types, budget, espionage, economic, tactical, strategic, diplomacy, intelligence, logistics, standing_orders_manager]

export core, orders, standing_orders_manager

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

  # Calculate available PP budget from production
  var totalProduction = 0
  for colony in filtered.ownColonies:
    if colony.owner == controller.houseId:
      totalProduction += colony.production

  # Allocate percentage of production to research based on tech priority
  let researchBudget = int(float(totalProduction) * p.techPriority)

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

proc generateAIOrders*(controller: var AIController, filtered: FilteredGameState, rng: var Rand): OrderPacket =
  ## Generate complete order packet using all RBA subsystems
  ##
  ## This is the main entry point for RBA AI order generation.
  ## It coordinates all subsystems to produce a coherent strategic plan.

  result = OrderPacket(
    houseId: controller.houseId,
    turn: filtered.turn,
    fleetOrders: @[],
    buildOrders: @[],
    researchAllocation: generateResearchAllocation(controller, filtered),
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
  # LOGISTICS (Asset Lifecycle Management) - CALLED FIRST!
  # ==========================================================================
  # Philosophy: Use what you have before building more
  # Logistics handles: cargo loading, PTU transfers, fleet rebalancing, mothballing
  let logisticsOrders = logistics.generateLogisticsOrders(controller, filtered, currentAct)

  result.cargoManagement = logisticsOrders.cargo
  result.populationTransfers = logisticsOrders.population
  result.squadronManagement = logisticsOrders.squadrons
  # NOTE: Fleet orders from logistics will be added AFTER tactical orders to avoid conflicts

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
  let availableBudget = filtered.ownHouse.treasury

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
  let needFighters = cst >= 3 and p.aggression > 0.3  # Fighter squadrons require CST 3
  let needCarriers = cst >= 3 and needFighters  # Carriers support fighters (CST 3)
  let needTransports = cst >= 1 and p.aggression > 0.4  # Troop transports (CST 1)
  let needRaiders = cst >= 3 and p.aggression > 0.6  # Raiders require CST 3

  result.buildOrders = generateBuildOrdersWithBudget(
    controller, filtered, filtered.ownHouse, myColonies, currentAct, p,
    isUnderThreat, needETACs, needDefenses, needScouts, needFighters,
    needCarriers, needTransports, needRaiders, canAffordMoreShips,
    atSquadronLimit, militaryCount, scoutCount, planetBreakerCount, availableBudget
  )

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
  # Build set of fleets that logistics wants to manage (lifecycle operations)
  var logisticsControlledFleets: HashSet[FleetId]
  for order in logisticsOrders.fleetOrders:
    logisticsControlledFleets.incl(order.fleetId)

  # Generate tactical fleet orders (tactical will check logistics control)
  # TODO: Pass logisticsControlledFleets to tactical so it can skip those fleets
  let tacticalOrders = generateFleetOrders(controller, filtered, rng)

  # Add tactical orders first (active operations take priority)
  for order in tacticalOrders:
    # Skip if logistics is managing this fleet (Reserve/Mothball/Salvage/Reactivate)
    if order.fleetId notin logisticsControlledFleets:
      result.fleetOrders.add(order)
    else:
      logInfo(LogCategory.lcAI, &"{controller.houseId} Fleet {order.fleetId}: Logistics override (lifecycle management)")

  # Add logistics lifecycle orders (for fleets tactical doesn't control)
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
  # PHASE 1: Calculate espionage investment (2-5% of treasury)
  # This determines how many EBP/CIP points we'll have THIS TURN
  let espionageInvestment = if p.riskTolerance > 0.6:
    0.05  # High risk tolerance: 5% investment
  elif p.economicFocus > 0.7:
    0.02  # Economic focus: 2% investment (minimal)
  else:
    0.03  # Balanced: 3% investment

  let totalInvestment = int(float(filtered.ownHouse.treasury) * espionageInvestment)
  let ebpInvestment = totalInvestment div 2  # Half to offensive EBP
  let cipInvestment = totalInvestment div 2  # Half to defensive CIP

  # PHASE 2: Calculate projected EBP/CIP (current + investment)
  # This is the budget available THIS TURN for espionage actions
  let projectedEBP = filtered.ownHouse.espionageBudget.ebpPoints + ebpInvestment
  let projectedCIP = filtered.ownHouse.espionageBudget.cipPoints + cipInvestment

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Turn {filtered.turn}: Espionage budget - " &
          &"treasury={filtered.ownHouse.treasury}PP, investment={totalInvestment}PP, " &
          &"projected EBP={projectedEBP}, projected CIP={projectedCIP}")

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
  result.terraformOrders = generateTerraformOrders(controller, filtered, rng)

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

  # Log summary
  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Standing Orders: {standingOrders.len} assigned, " &
          &"{filtered.ownFleets.len - standingOrders.len} under tactical control")

  # Store standing orders in controller for next turn
  # NOTE: These will be applied to GameState during order execution
  controller.standingOrders = standingOrders
