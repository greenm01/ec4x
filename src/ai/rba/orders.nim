## RBA Orders Module
##
## Main entry point for generating complete order packets from RBA AI

import std/[tables, options, random, sequtils]
import ../../common/types/[core, tech, units]
import ../../engine/[gamestate, fog_of_war, orders]
import ../../engine/research/types as res_types
import ../common/types as ai_types  # For getCurrentGameAct, GameAct
import ./[controller_types, budget, espionage, economic, tactical, strategic, diplomacy, intelligence]

export core, orders

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

  let house = filtered.ownHouse
  let p = controller.personality

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
  let currentAct = ai_types.getCurrentGameAct(filtered.turn)
  let myColonies = getOwnedColonies(filtered, controller.houseId)

  # Calculate context flags for build decision-making
  # These are simple heuristics - budget module makes the final decisions
  let availableBudget = house.treasury

  # Count military vs scout squadrons
  var militaryCount = 0
  var scoutCount = 0
  for fleet in filtered.ownFleets:
    for squadron in fleet.squadrons:
      if squadron.flagship.shipClass == ShipClass.Scout:
        scoutCount += 1
      else:
        militaryCount += 1

  let canAffordMoreShips = availableBudget >= 200  # Basic affordability check
  let atSquadronLimit = false  # Engine manages squadron limits, we just build

  # Simple threat assessment
  let isUnderThreat = filtered.visibleFleets.anyIt(it.owner != controller.houseId)

  # Build needs based on what we have
  let needScouts = scoutCount < myColonies.len  # Want at least 1 scout per colony
  let needETACs = militaryCount < 2  # Need some military presence
  let needDefenses = currentAct >= ai_types.GameAct.Act2_RisingTensions
  let needFighters = currentAct >= ai_types.GameAct.Act2_RisingTensions and p.aggression > 0.3
  let needCarriers = needFighters  # Carriers support fighters
  let needTransports = currentAct >= ai_types.GameAct.Act2_RisingTensions and p.aggression > 0.4
  let needRaiders = p.aggression > 0.6 and currentAct >= ai_types.GameAct.Act2_RisingTensions

  result.buildOrders = generateBuildOrdersWithBudget(
    controller, filtered, house, myColonies, currentAct, p,
    isUnderThreat, needETACs, needDefenses, needScouts, needFighters,
    needCarriers, needTransports, needRaiders, canAffordMoreShips,
    atSquadronLimit, militaryCount, scoutCount, availableBudget
  )

  # ==========================================================================
  # FLEET ORDERS (Using RBA Tactical Module)
  # ==========================================================================
  result.fleetOrders = generateFleetOrders(controller, filtered, rng)

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
  result.espionageAction = generateEspionageAction(controller, filtered, rng)

  # Calculate espionage investment (2-5% of treasury)
  let espionageInvestment = if p.riskTolerance > 0.6:
    0.05  # High risk tolerance: 5% investment
  elif p.economicFocus > 0.7:
    0.02  # Economic focus: 2% investment (minimal)
  else:
    0.03  # Balanced: 3% investment

  let totalInvestment = int(float(house.treasury) * espionageInvestment)
  result.ebpInvestment = totalInvestment div 2  # Half to offensive EBP
  result.cipInvestment = totalInvestment div 2  # Half to defensive CIP

  # ==========================================================================
  # ECONOMIC ORDERS (Using RBA Economic Module)
  # ==========================================================================
  result.populationTransfers = generatePopulationTransfers(controller, filtered, rng)
  result.terraformOrders = generateTerraformOrders(controller, filtered, rng)

  # ==========================================================================
  # SQUADRON & CARGO MANAGEMENT
  # ==========================================================================
  # Leave empty - engine auto-commissions squadrons
  # AI can add manual management here if needed for advanced tactics
  result.squadronManagement = @[]
  result.cargoManagement = @[]
