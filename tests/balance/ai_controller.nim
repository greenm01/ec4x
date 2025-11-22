## AI Controller for Balance Testing
##
## Implements strategic decision-making for different AI personalities
## to enable realistic game simulations

import std/[tables, options, random, sequtils, strformat, algorithm]
import ../../src/engine/[gamestate, orders, fleet, squadron, starmap]
import ../../src/common/types/[core, units, tech, planets]
import ../../src/engine/espionage/types as esp_types
import ../../src/engine/research/types as res_types
import ../../src/engine/diplomacy/types as dip_types

type
  AIStrategy* {.pure.} = enum
    ## Different AI play styles for balance testing
    Aggressive,      # Heavy military, early attacks
    Economic,        # Focus on growth and tech
    Espionage,       # Intelligence and sabotage
    Diplomatic,      # Pacts and manipulation
    Balanced,        # Mixed approach
    Turtle,          # Defensive, slow expansion
    Expansionist     # Rapid colonization

  AIPersonality* = object
    aggression*: float       # 0.0-1.0: How likely to attack
    riskTolerance*: float    # 0.0-1.0: Willingness to take risks
    economicFocus*: float    # 0.0-1.0: Priority on economy vs military
    expansionDrive*: float   # 0.0-1.0: How aggressively to expand
    diplomacyValue*: float   # 0.0-1.0: Value placed on alliances
    techPriority*: float     # 0.0-1.0: Research investment priority

  AIController* = object
    houseId*: HouseId
    strategy*: AIStrategy
    personality*: AIPersonality
    lastTurnReport*: string  ## Previous turn's report for context

# =============================================================================
# Strategy Profiles
# =============================================================================

proc getStrategyPersonality*(strategy: AIStrategy): AIPersonality =
  ## Get personality parameters for a strategy
  case strategy
  of AIStrategy.Aggressive:
    AIPersonality(
      aggression: 0.9,
      riskTolerance: 0.8,
      economicFocus: 0.3,
      expansionDrive: 0.7,
      diplomacyValue: 0.2,
      techPriority: 0.4
    )
  of AIStrategy.Economic:
    AIPersonality(
      aggression: 0.2,
      riskTolerance: 0.3,
      economicFocus: 0.9,
      expansionDrive: 0.5,
      diplomacyValue: 0.6,
      techPriority: 0.8
    )
  of AIStrategy.Espionage:
    AIPersonality(
      aggression: 0.5,
      riskTolerance: 0.6,
      economicFocus: 0.5,
      expansionDrive: 0.4,
      diplomacyValue: 0.4,
      techPriority: 0.6
    )
  of AIStrategy.Diplomatic:
    AIPersonality(
      aggression: 0.3,
      riskTolerance: 0.4,
      economicFocus: 0.6,
      expansionDrive: 0.5,
      diplomacyValue: 0.9,
      techPriority: 0.5
    )
  of AIStrategy.Balanced:
    AIPersonality(
      aggression: 0.5,
      riskTolerance: 0.5,
      economicFocus: 0.5,
      expansionDrive: 0.5,
      diplomacyValue: 0.5,
      techPriority: 0.5
    )
  of AIStrategy.Turtle:
    AIPersonality(
      aggression: 0.1,
      riskTolerance: 0.2,
      economicFocus: 0.7,
      expansionDrive: 0.2,
      diplomacyValue: 0.7,
      techPriority: 0.7
    )
  of AIStrategy.Expansionist:
    AIPersonality(
      aggression: 0.6,
      riskTolerance: 0.7,
      economicFocus: 0.4,
      expansionDrive: 0.95,
      diplomacyValue: 0.3,
      techPriority: 0.3
    )

proc newAIController*(houseId: HouseId, strategy: AIStrategy): AIController =
  ## Create a new AI controller for a house
  AIController(
    houseId: houseId,
    strategy: strategy,
    personality: getStrategyPersonality(strategy)
  )

# =============================================================================
# Helper Functions
# =============================================================================

proc getOwnedColonies(state: GameState, houseId: HouseId): seq[Colony] =
  ## Get all colonies owned by a house
  result = @[]
  for colony in state.colonies.values:
    if colony.owner == houseId:
      result.add(colony)

proc getOwnedFleets(state: GameState, houseId: HouseId): seq[Fleet] =
  ## Get all fleets owned by a house
  result = @[]
  for fleet in state.fleets.values:
    if fleet.owner == houseId:
      result.add(fleet)

proc getFleetStrength(fleet: Fleet): int =
  ## Calculate total attack strength of a fleet
  result = 0
  for squadron in fleet.squadrons:
    result += squadron.combatStrength()

proc findNearestUncolonizedSystem(state: GameState, fromSystem: SystemId): Option[SystemId] =
  ## Find nearest uncolonized system (simplified - just checks if colonized)
  var candidates: seq[SystemId] = @[]

  for systemId in state.starMap.systems.keys:
    if systemId notin state.colonies:
      candidates.add(systemId)

  if candidates.len > 0:
    # Return first candidate (TODO: actual distance calculation)
    return some(candidates[0])

  return none(SystemId)

proc findWeakestEnemyColony(state: GameState, houseId: HouseId, rng: var Rand): Option[SystemId] =
  ## Find an enemy colony to attack (prefer weaker targets)
  var targets: seq[tuple[systemId: SystemId, strength: int]] = @[]

  for systemId, colony in state.colonies:
    if colony.owner != houseId:
      # Calculate defensive strength (simplified)
      let defenseStr = colony.infrastructure * 10 + colony.groundBatteries * 20
      targets.add((systemId, defenseStr))

  if targets.len > 0:
    # Sort by strength (weakest first)
    targets.sort(proc(a, b: auto): int = cmp(a.strength, b.strength))
    return some(targets[0].systemId)

  return none(SystemId)

# =============================================================================
# Strategic Diplomacy Assessment
# =============================================================================

type
  DiplomaticAssessment* = object
    ## Assessment of diplomatic situation with target house
    targetHouse*: HouseId
    relativeMilitaryStrength*: float  # Our strength / their strength (1.0 = equal)
    relativeEconomicStrength*: float  # Our economy / their economy (1.0 = equal)
    mutualEnemies*: seq[HouseId]      # Houses both consider enemies
    geographicProximity*: int         # Number of neighboring systems
    violationRisk*: float             # 0.0-1.0: Risk they violate pact
    currentState*: dip_types.DiplomaticState
    recommendPact*: bool              # Should we propose/maintain pact?
    recommendBreak*: bool             # Should we break existing pact?
    recommendEnemy*: bool             # Should we declare enemy?

proc calculateMilitaryStrength(state: GameState, houseId: HouseId): int =
  ## Calculate total military strength for a house
  result = 0
  let fleets = getOwnedFleets(state, houseId)
  for fleet in fleets:
    result += getFleetStrength(fleet)

proc calculateEconomicStrength(state: GameState, houseId: HouseId): int =
  ## Calculate total economic strength for a house
  result = 0
  let house = state.houses[houseId]
  let colonies = getOwnedColonies(state, houseId)

  # Treasury value
  result += house.treasury

  # Colony production value
  for colony in colonies:
    result += colony.production * 10  # Weight production highly
    result += colony.infrastructure * 5

proc findMutualEnemies(state: GameState, houseA: HouseId, houseB: HouseId): seq[HouseId] =
  ## Find houses that both houseA and houseB consider enemies
  result = @[]
  let houseAData = state.houses[houseA]
  let houseBData = state.houses[houseB]

  for otherHouse in state.houses.keys:
    if otherHouse == houseA or otherHouse == houseB:
      continue

    let aIsEnemy = dip_types.isEnemy(houseAData.diplomaticRelations, otherHouse)
    let bIsEnemy = dip_types.isEnemy(houseBData.diplomaticRelations, otherHouse)

    if aIsEnemy and bIsEnemy:
      result.add(otherHouse)

proc estimateViolationRisk(state: GameState, targetHouse: HouseId): float =
  ## Estimate risk that target house will violate a pact (0.0-1.0)
  let targetData = state.houses[targetHouse]

  # Check violation history
  let recentViolations = dip_types.countRecentViolations(
    targetData.violationHistory,
    state.turn
  )

  # Base risk from history
  var risk = float(recentViolations) * 0.2  # +20% per recent violation

  # Check if dishonored
  if targetData.violationHistory.dishonored.active:
    risk += 0.3  # +30% if currently dishonored

  return min(risk, 0.9)  # Cap at 90% risk

proc assessDiplomaticSituation(controller: AIController, state: GameState,
                               targetHouse: HouseId): DiplomaticAssessment =
  ## Evaluate diplomatic relationship with target house
  ## Returns strategic assessment for decision making
  let myHouse = state.houses[controller.houseId]
  let theirHouse = state.houses[targetHouse]
  let p = controller.personality

  result.targetHouse = targetHouse
  result.currentState = dip_types.getDiplomaticState(
    myHouse.diplomaticRelations,
    targetHouse
  )

  # Calculate relative strengths
  let myMilitary = calculateMilitaryStrength(state, controller.houseId)
  let theirMilitary = calculateMilitaryStrength(state, targetHouse)
  result.relativeMilitaryStrength = if theirMilitary > 0:
    float(myMilitary) / float(theirMilitary)
  else:
    10.0  # They have no military

  let myEconomy = calculateEconomicStrength(state, controller.houseId)
  let theirEconomy = calculateEconomicStrength(state, targetHouse)
  result.relativeEconomicStrength = if theirEconomy > 0:
    float(myEconomy) / float(theirEconomy)
  else:
    10.0  # They have no economy

  # Find mutual enemies
  result.mutualEnemies = findMutualEnemies(state, controller.houseId, targetHouse)

  # Estimate violation risk
  result.violationRisk = estimateViolationRisk(state, targetHouse)

  # Strategic recommendations based on personality
  case result.currentState
  of dip_types.DiplomaticState.Neutral:
    # Should we propose a pact?
    var pactScore = 0.0

    # Stronger neighbor = want pact (defensive)
    if result.relativeMilitaryStrength < 0.8:
      pactScore += 0.3

    # Mutual enemies = want pact (alliance)
    pactScore += float(result.mutualEnemies.len) * 0.2

    # High diplomacy value = more likely to seek pacts
    pactScore += p.diplomacyValue * 0.4

    # Low violation risk = more likely to trust
    pactScore += (1.0 - result.violationRisk) * 0.2

    result.recommendPact = pactScore > 0.5

    # Should we declare enemy?
    var enemyScore = 0.0

    # Aggressive personality
    enemyScore += p.aggression * 0.5

    # Weaker target
    if result.relativeMilitaryStrength > 1.5:
      enemyScore += 0.3

    # Low diplomacy value
    enemyScore += (1.0 - p.diplomacyValue) * 0.3

    result.recommendEnemy = enemyScore > 0.6

  of dip_types.DiplomaticState.NonAggression:
    # Should we break the pact?
    var breakScore = 0.0

    # Aggressive strategy willing to violate
    if controller.strategy == AIStrategy.Aggressive:
      breakScore += 0.4

    # Much weaker target = tempting
    if result.relativeMilitaryStrength > 2.0:
      breakScore += 0.3

    # Low diplomacy value = less concerned with reputation
    breakScore += (1.0 - p.diplomacyValue) * 0.4

    # High risk tolerance
    breakScore += p.riskTolerance * 0.2

    result.recommendBreak = breakScore > 0.7  # High threshold for violation

  of dip_types.DiplomaticState.Enemy:
    # Should we normalize relations?
    var normalizeScore = 0.0

    # Much stronger enemy = want peace
    if result.relativeMilitaryStrength < 0.5:
      normalizeScore += 0.5

    # High diplomacy value
    normalizeScore += p.diplomacyValue * 0.4

    # Low aggression
    normalizeScore += (1.0 - p.aggression) * 0.3

    # Recommend neutral if score high enough
    if normalizeScore > 0.6:
      result.recommendEnemy = false
    else:
      result.recommendEnemy = true  # Stay enemies

# =============================================================================
# Order Generation
# =============================================================================

proc generateFleetOrders(controller: AIController, state: GameState, rng: var Rand): seq[FleetOrder] =
  ## Generate fleet orders based on strategy
  result = @[]
  let p = controller.personality
  let myFleets = getOwnedFleets(state, controller.houseId)

  for fleet in myFleets:
    var order: FleetOrder
    order.fleetId = fleet.id
    order.priority = 1

    # Decide action based on personality
    let aggressionRoll = rng.rand(1.0)
    let expansionRoll = rng.rand(1.0)

    if aggressionRoll < p.aggression and p.aggression > 0.6:
      # Attack enemy colony
      let targetOpt = findWeakestEnemyColony(state, controller.houseId, rng)
      if targetOpt.isSome:
        order.orderType = FleetOrderType.Move
        order.targetSystem = targetOpt
        order.targetFleet = none(FleetId)
      else:
        # No targets, patrol home
        order.orderType = FleetOrderType.Patrol
        order.targetSystem = some(fleet.location)
        order.targetFleet = none(FleetId)

    elif expansionRoll < p.expansionDrive and p.expansionDrive > 0.6:
      # Colonize new system
      let targetOpt = findNearestUncolonizedSystem(state, fleet.location)
      if targetOpt.isSome:
        order.orderType = FleetOrderType.Move
        order.targetSystem = targetOpt
        order.targetFleet = none(FleetId)
      else:
        # No empty systems, hold position
        order.orderType = FleetOrderType.Hold
        order.targetSystem = none(SystemId)
        order.targetFleet = none(FleetId)

    else:
      # Default: Patrol home system
      order.orderType = FleetOrderType.Patrol
      order.targetSystem = some(fleet.location)
      order.targetFleet = none(FleetId)

    result.add(order)

proc generateBuildOrders(controller: AIController, state: GameState, rng: var Rand): seq[BuildOrder] =
  ## Generate build orders based on strategy
  result = @[]
  let p = controller.personality
  let house = state.houses[controller.houseId]
  let myColonies = getOwnedColonies(state, controller.houseId)

  # Determine what to build based on treasury and strategy
  for colony in myColonies:
    if house.treasury < 100:
      continue  # Not enough funds

    # Build infrastructure if economic focus is high
    if p.economicFocus > 0.6 and colony.infrastructure < 10:
      result.add(BuildOrder(
        colonySystem: colony.systemId,
        buildType: BuildType.Infrastructure,
        quantity: 1,
        shipClass: none(ShipClass),
        buildingType: none(string),
        industrialUnits: 1
      ))

    # Build military ships if aggression is high
    elif p.aggression > 0.5:
      let shipClass = if rng.rand(1.0) > 0.5: ShipClass.Destroyer else: ShipClass.Cruiser
      result.add(BuildOrder(
        colonySystem: colony.systemId,
        buildType: BuildType.Ship,
        quantity: 1,
        shipClass: some(shipClass),
        buildingType: none(string),
        industrialUnits: 0
      ))

proc generateResearchAllocation(controller: AIController, state: GameState): res_types.ResearchAllocation =
  ## Allocate research PP based on strategy
  ## Per economy.md:4.0:
  ##   - Economic Level (EL) purchased with ERP
  ##   - Science Level (SL) purchased with SRP
  ##   - Technologies (CST, WEP, etc.) purchased with TRP
  result = res_types.ResearchAllocation(
    economic: 0,
    science: 0,
    technology: initTable[TechField, int]()
  )

  let p = controller.personality
  let house = state.houses[controller.houseId]

  # Calculate available PP budget from production
  # Get house's production from all colonies
  var totalProduction = 0
  for colony in state.colonies.values:
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

      # Remaining ~42% to technologies
      let techBudget = researchBudget - result.economic - result.science
      if p.aggression > 0.5:
        # Aggressive: focus on weapons
        result.technology[TechField.WeaponsTech] = techBudget div 2
        result.technology[TechField.ConstructionTech] = techBudget div 4
        result.technology[TechField.ElectronicIntelligence] = techBudget div 4
      else:
        # Peaceful: focus on infrastructure
        result.technology[TechField.ConstructionTech] = techBudget div 2
        result.technology[TechField.TerraformingTech] = techBudget div 4
        result.technology[TechField.CounterIntelligence] = techBudget div 4

    elif p.techPriority > 0.4:
      # Moderate research - focus on fundamentals (EL/SL)
      result.economic = researchBudget div 2        # 50% to EL
      result.science = researchBudget div 3         # 33% to SL

      # Remaining ~17% to one key tech
      let techBudget = researchBudget - result.economic - result.science
      if p.aggression > 0.5:
        result.technology[TechField.WeaponsTech] = techBudget
      else:
        result.technology[TechField.ConstructionTech] = techBudget
    else:
      # Minimal research - just EL for economic growth
      result.economic = researchBudget

proc generateDiplomaticActions(controller: AIController, state: GameState, rng: var Rand): seq[DiplomaticAction] =
  ## Generate diplomatic actions based on strategic assessment
  result = @[]
  let p = controller.personality
  let myHouse = state.houses[controller.houseId]

  # Assess all other houses
  var assessments: seq[DiplomaticAssessment] = @[]
  for otherHouseId in state.houses.keys:
    if otherHouseId == controller.houseId:
      continue
    assessments.add(assessDiplomaticSituation(controller, state, otherHouseId))

  # Priority 1: Break pacts if strategically advantageous (rare)
  for assessment in assessments:
    if assessment.recommendBreak and assessment.currentState == dip_types.DiplomaticState.NonAggression:
      # Double-check with random roll to avoid too frequent violations
      if rng.rand(1.0) < 0.2:  # Only 20% chance even when recommended
        result.add(DiplomaticAction(
          targetHouse: assessment.targetHouse,
          actionType: DiplomaticActionType.BreakPact
        ))
        return result  # Only one action per turn

  # Priority 2: Propose pacts with strategic partners
  for assessment in assessments:
    if assessment.recommendPact and assessment.currentState == dip_types.DiplomaticState.Neutral:
      # Check if we can form pacts (not isolated)
      if dip_types.canFormPact(myHouse.violationHistory):
        # Check if we can reinstate with this specific house
        if dip_types.canReinstatePact(myHouse.violationHistory, assessment.targetHouse, state.turn):
          result.add(DiplomaticAction(
            targetHouse: assessment.targetHouse,
            actionType: DiplomaticActionType.ProposeNonAggressionPact
          ))
          return result  # Only one action per turn

  # Priority 3: Declare enemy against weak/aggressive targets
  for assessment in assessments:
    if assessment.recommendEnemy and assessment.currentState == dip_types.DiplomaticState.Neutral:
      # Aggressive strategies more likely to declare enemies
      let declareChance = p.aggression * 0.5
      if rng.rand(1.0) < declareChance:
        result.add(DiplomaticAction(
          targetHouse: assessment.targetHouse,
          actionType: DiplomaticActionType.DeclareEnemy
        ))
        return result  # Only one action per turn

  # Priority 4: Normalize relations with dangerous enemies
  for assessment in assessments:
    if not assessment.recommendEnemy and assessment.currentState == dip_types.DiplomaticState.Enemy:
      # Only if we're significantly weaker
      if assessment.relativeMilitaryStrength < 0.6:
        result.add(DiplomaticAction(
          targetHouse: assessment.targetHouse,
          actionType: DiplomaticActionType.SetNeutral
        ))
        return result  # Only one action per turn

proc generateEspionageAction(controller: AIController, state: GameState, rng: var Rand): Option[esp_types.EspionageAttempt] =
  ## Generate espionage action based on strategy
  if controller.strategy != AIStrategy.Espionage:
    return none(esp_types.EspionageAttempt)

  # Find a target house
  var targetHouses: seq[HouseId] = @[]
  for houseId in state.houses.keys:
    if houseId != controller.houseId:
      targetHouses.add(houseId)

  if targetHouses.len == 0:
    return none(esp_types.EspionageAttempt)

  let target = targetHouses[rng.rand(targetHouses.len - 1)]

  # Simple espionage attempt (tech theft)
  return some(esp_types.EspionageAttempt(
    attacker: controller.houseId,
    target: target,
    action: esp_types.EspionageAction.TechTheft,
    targetSystem: none(SystemId)
  ))

# =============================================================================
# Main Order Generation
# =============================================================================

proc generateAIOrders*(controller: AIController, state: GameState, rng: var Rand): OrderPacket =
  ## Generate complete order packet for an AI player
  ##
  ## Context available:
  ## - controller.lastTurnReport: Previous turn's report (for AI learning)
  ## - state: Current game state
  ## - controller.personality: Strategic personality parameters
  ##
  ## Future enhancement: Parse lastTurnReport to:
  ## - React to combat losses (build replacements, retreat)
  ## - Respond to enemy fleet sightings (send reinforcements)
  ## - Adjust strategy based on economic situation
  ## - Learn from tech advances (prioritize synergistic research)
  let p = controller.personality
  let house = state.houses[controller.houseId]

  result = OrderPacket(
    houseId: controller.houseId,
    turn: state.turn,
    fleetOrders: generateFleetOrders(controller, state, rng),
    buildOrders: generateBuildOrders(controller, state, rng),
    researchAllocation: generateResearchAllocation(controller, state),
    diplomaticActions: generateDiplomaticActions(controller, state, rng),
    espionageAction: generateEspionageAction(controller, state, rng),
    ebpInvestment: 0,
    cipInvestment: 0
  )

  # Set espionage budget based on strategy
  case controller.strategy
  of AIStrategy.Espionage:
    result.ebpInvestment = min(house.treasury div 10, 200)
    result.cipInvestment = min(house.treasury div 20, 100)
  of AIStrategy.Aggressive:
    result.ebpInvestment = min(house.treasury div 20, 50)
  else:
    result.ebpInvestment = min(house.treasury div 40, 25)
    result.cipInvestment = min(house.treasury div 40, 25)

# =============================================================================
# Export
# =============================================================================

export AIStrategy, AIPersonality, AIController
export newAIController, generateAIOrders, getStrategyPersonality
