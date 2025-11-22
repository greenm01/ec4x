## AI Controller for Balance Testing
##
## Implements strategic decision-making for different AI personalities
## to enable realistic game simulations

import std/[tables, options, random, sequtils, strformat, algorithm]
import ../../src/engine/[gamestate, orders, fleet, squadron, starmap]
import ../../src/common/types/[core, units, tech, planets]
import ../../src/engine/espionage/types as esp_types

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

proc generateResearchAllocation(controller: AIController, state: GameState): Table[TechField, int] =
  ## Allocate research points based on strategy
  ## Research costs PP (production), not IU (treasury)
  result = initTable[TechField, int]()
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
    # Distribute research across fields based on strategy
    if p.techPriority > 0.6:
      # Heavy research investment - distribute across multiple fields
      result[TechField.EnergyLevel] = researchBudget div 3
      result[TechField.WeaponsTech] = if p.aggression > 0.5: researchBudget div 3 else: researchBudget div 6
      result[TechField.ShieldLevel] = researchBudget div 6
      result[TechField.ConstructionTech] = researchBudget div 6
    elif p.techPriority > 0.4:
      # Moderate research - focus on key fields
      result[TechField.EnergyLevel] = researchBudget div 2
      result[TechField.WeaponsTech] = if p.aggression > 0.5: researchBudget div 2 else: 0
    else:
      # Minimal research - just energy
      result[TechField.EnergyLevel] = researchBudget

proc generateDiplomaticActions(controller: AIController, state: GameState, rng: var Rand): seq[DiplomaticAction] =
  ## Generate diplomatic actions based on strategy
  result = @[]
  let p = controller.personality

  if p.diplomacyValue < 0.4:
    return result  # Low diplomacy value, skip

  # Find potential allies
  for otherHouseId in state.houses.keys:
    if otherHouseId == controller.houseId:
      continue

    # Diplomatic AI seeks pacts
    if controller.strategy == AIStrategy.Diplomatic and rng.rand(1.0) < 0.3:
      result.add(DiplomaticAction(
        targetHouse: otherHouseId,
        actionType: DiplomaticActionType.ProposeNonAggressionPact
      ))
      break  # Only one diplomatic action per turn

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
