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
import ../../src/engine/economy/construction

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

proc newAIControllerWithPersonality*(houseId: HouseId, personality: AIPersonality): AIController =
  ## Create a new AI controller with a custom personality (for genetic algorithm)
  AIController(
    houseId: houseId,
    strategy: AIStrategy.Balanced,  # Strategy field is unused with custom personality
    personality: personality
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
  ## Find nearest uncolonized system using cube distance
  ## Returns closest uncolonized system to avoid all AIs targeting the same one
  type SystemDist = tuple[systemId: SystemId, distance: int]
  var candidates: seq[SystemDist] = @[]

  let fromCoords = state.starMap.systems[fromSystem].coords

  for systemId, system in state.starMap.systems:
    if systemId notin state.colonies:
      # Calculate cube distance (Manhattan distance in hex coordinates)
      let dx = abs(system.coords.q - fromCoords.q)
      let dy = abs(system.coords.r - fromCoords.r)
      let dz = abs((system.coords.q + system.coords.r) - (fromCoords.q + fromCoords.r))
      let distance = (dx + dy + dz) div 2
      let item: SystemDist = (systemId: systemId, distance: distance)
      candidates.add(item)

  if candidates.len > 0:
    # Sort by distance and return closest
    candidates.sort(proc(a, b: SystemDist): int = cmp(a.distance, b.distance))
    return some(candidates[0].systemId)

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
# Strategic Military Assessment
# =============================================================================

type
  CombatAssessment* = object
    ## Assessment of combat situation for attacking a target system
    targetSystem*: SystemId
    targetOwner*: HouseId

    # Fleet strengths
    attackerFleetStrength*: int    # Our attack power
    defenderFleetStrength*: int    # Enemy fleet defense at target

    # Defensive installations
    starbaseStrength*: int         # Starbase attack/defense
    groundBatteryCount*: int       # Ground batteries
    planetaryShieldLevel*: int     # Shield level (0-6)
    groundForces*: int             # Armies + marines

    # Combat odds
    estimatedCombatOdds*: float    # 0.0-1.0: Probability of victory
    expectedCasualties*: int       # Expected ship losses

    # Strategic factors
    violatesPact*: bool            # Would attack violate non-aggression pact?
    strategicValue*: int           # Value of target (production, resources)

    # Recommendations
    recommendAttack*: bool         # Should we attack?
    recommendReinforce*: bool      # Should we send reinforcements?
    recommendRetreat*: bool        # Should we retreat from system?

proc calculateDefensiveStrength(state: GameState, systemId: SystemId): int =
  ## Calculate total defensive strength of a colony
  if systemId notin state.colonies:
    return 0

  let colony = state.colonies[systemId]
  result = 0

  # Starbase strength (each starbase adds attack + defense strength)
  for starbase in colony.starbases:
    if not starbase.isCrippled:
      # Starbases are powerful defensive assets
      result += 100  # Simplified: each starbase worth 100 defense points

  # Ground batteries
  result += colony.groundBatteries * 20

  # Planetary shields (reduce attacker effectiveness)
  result += colony.planetaryShieldLevel * 15

  # Ground forces (armies + marines)
  result += (colony.armies + colony.marines) * 10

proc calculateFleetStrengthAtSystem(state: GameState, systemId: SystemId,
                                   houseId: HouseId): int =
  ## Calculate fleet strength for a specific house at a system
  result = 0
  for fleet in state.fleets.values:
    if fleet.owner == houseId and fleet.location == systemId:
      result += getFleetStrength(fleet)

proc estimateColonyValue(state: GameState, systemId: SystemId): int =
  ## Estimate strategic value of a colony
  if systemId notin state.colonies:
    return 0

  let colony = state.colonies[systemId]
  result = 0

  # Production value
  result += colony.production * 10

  # Infrastructure value
  result += colony.infrastructure * 20

  # Resource rating bonus
  case colony.resources
  of ResourceRating.VeryRich:
    result += 70
  of ResourceRating.Rich:
    result += 50
  of ResourceRating.Abundant:
    result += 30
  of ResourceRating.Poor:
    result += 10
  of ResourceRating.VeryPoor:
    result += 0

proc assessCombatSituation(controller: AIController, state: GameState,
                          targetSystem: SystemId): CombatAssessment =
  ## Evaluate combat situation for attacking a target system
  ## Returns strategic assessment for attack decision

  result.targetSystem = targetSystem

  # Check if system has a colony
  if targetSystem notin state.colonies:
    result.recommendAttack = false
    return

  let targetColony = state.colonies[targetSystem]
  result.targetOwner = targetColony.owner

  # Don't attack our own colonies
  if result.targetOwner == controller.houseId:
    result.recommendAttack = false
    return

  # Check diplomatic status
  let myHouse = state.houses[controller.houseId]
  let dipState = dip_types.getDiplomaticState(
    myHouse.diplomaticRelations,
    result.targetOwner
  )
  result.violatesPact = dipState == dip_types.DiplomaticState.NonAggression

  # Calculate military strengths
  result.attackerFleetStrength = calculateFleetStrengthAtSystem(
    state, targetSystem, controller.houseId
  )
  result.defenderFleetStrength = calculateFleetStrengthAtSystem(
    state, targetSystem, result.targetOwner
  )

  # Calculate defensive installations
  result.starbaseStrength = 0
  result.groundBatteryCount = targetColony.groundBatteries
  result.planetaryShieldLevel = targetColony.planetaryShieldLevel
  result.groundForces = targetColony.armies + targetColony.marines

  for starbase in targetColony.starbases:
    if not starbase.isCrippled:
      result.starbaseStrength += 100

  # Total defensive strength
  let totalDefense = result.defenderFleetStrength +
                     calculateDefensiveStrength(state, targetSystem)

  # Estimate combat odds
  # Simple model: odds = attacker / (attacker + defender)
  # Attacker needs advantage to have good odds
  if result.attackerFleetStrength == 0:
    result.estimatedCombatOdds = 0.0
  elif totalDefense == 0:
    result.estimatedCombatOdds = 1.0
  else:
    let ratio = float(result.attackerFleetStrength) / float(totalDefense)
    # Apply sigmoid-like curve: need ~2:1 advantage for 75% odds
    result.estimatedCombatOdds = ratio / (ratio + 0.8)
    result.estimatedCombatOdds = min(result.estimatedCombatOdds, 0.95)

  # Estimate casualties (% of attacker strength lost)
  let expectedLossRate = 1.0 - result.estimatedCombatOdds
  result.expectedCasualties = int(
    float(result.attackerFleetStrength) * expectedLossRate * 0.3
  )

  # Calculate strategic value
  result.strategicValue = estimateColonyValue(state, targetSystem)

  # Make recommendations based on personality and odds
  let p = controller.personality

  # Attack recommendation
  var attackThreshold = 0.6  # Base: 60% odds needed

  # Adjust threshold by personality
  if controller.strategy == AIStrategy.Aggressive:
    attackThreshold = 0.4  # Aggressive: attack at 40% odds
  elif p.riskTolerance > 0.7:
    attackThreshold = 0.5  # High risk tolerance
  elif p.aggression < 0.3:
    attackThreshold = 0.8  # Cautious: need 80% odds

  # Don't attack if it violates pact (unless we're deciding to break it)
  if result.violatesPact:
    result.recommendAttack = false
  else:
    result.recommendAttack = result.estimatedCombatOdds >= attackThreshold

  # Reinforce recommendation (we have fleet there but odds not good enough)
  result.recommendReinforce = (
    result.attackerFleetStrength > 0 and
    result.estimatedCombatOdds < attackThreshold and
    result.estimatedCombatOdds > 0.2  # But not hopeless
  )

  # Retreat recommendation (we're outmatched)
  result.recommendRetreat = (
    result.attackerFleetStrength > 0 and
    result.estimatedCombatOdds < 0.3  # Less than 30% odds
  )

# =============================================================================
# Order Generation
# =============================================================================

proc generateFleetOrders(controller: AIController, state: GameState, rng: var Rand): seq[FleetOrder] =
  ## Generate fleet orders based on strategic military assessment
  result = @[]
  let p = controller.personality
  let myFleets = getOwnedFleets(state, controller.houseId)

  for fleet in myFleets:
    var order: FleetOrder
    order.fleetId = fleet.id
    order.priority = 1

    # Check current location for combat situation
    let currentCombat = assessCombatSituation(
      controller, state, fleet.location
    )

    # Priority 1: Retreat if we're in a losing battle
    if currentCombat.recommendRetreat:
      # Find nearest friendly colony to retreat to
      var nearestFriendly: Option[SystemId] = none(SystemId)
      for systemId, colony in state.colonies:
        if colony.owner == controller.houseId and systemId != fleet.location:
          nearestFriendly = some(systemId)
          break

      if nearestFriendly.isSome:
        order.orderType = FleetOrderType.Move
        order.targetSystem = nearestFriendly
        order.targetFleet = none(FleetId)
        result.add(order)
        continue
      # If no friendly colonies, hold and hope for the best
      order.orderType = FleetOrderType.Hold
      order.targetSystem = none(SystemId)
      order.targetFleet = none(FleetId)
      result.add(order)
      continue

    # Priority 2: Attack if we have good odds
    if currentCombat.recommendAttack:
      # We're already at an enemy system with good odds
      # Stay and fight (patrol to maintain presence)
      order.orderType = FleetOrderType.Patrol
      order.targetSystem = some(fleet.location)
      order.targetFleet = none(FleetId)
      result.add(order)
      continue

    # Priority 3: Find targets to attack based on aggression
    if p.aggression > 0.5:
      # Look for vulnerable enemy colonies
      var bestTarget: Option[SystemId] = none(SystemId)
      var bestOdds = 0.0

      for systemId, colony in state.colonies:
        if colony.owner == controller.houseId:
          continue  # Skip our own colonies

        let combat = assessCombatSituation(controller, state, systemId)
        if combat.recommendAttack and combat.estimatedCombatOdds > bestOdds:
          bestOdds = combat.estimatedCombatOdds
          bestTarget = some(systemId)

      if bestTarget.isSome:
        order.orderType = FleetOrderType.Move
        order.targetSystem = bestTarget
        order.targetFleet = none(FleetId)
        result.add(order)
        continue

    # Priority 4: Expansion and Exploration
    # Check if this fleet has an ETAC (colony ship)
    var hasETAC = false
    for squadron in fleet.squadrons:
      if squadron.flagship.shipClass == ShipClass.ETAC:
        hasETAC = true
        break
      for ship in squadron.ships:
        if ship.shipClass == ShipClass.ETAC:
          hasETAC = true
          break

    if hasETAC:
      # ETAC fleets: Always seek uncolonized systems
      let targetOpt = findNearestUncolonizedSystem(state, fleet.location)
      if targetOpt.isSome:
        order.orderType = FleetOrderType.Move
        order.targetSystem = targetOpt
        order.targetFleet = none(FleetId)
        result.add(order)
        continue
    elif p.expansionDrive > 0.3:
      # Non-ETAC fleets with expansion drive: Scout uncolonized systems
      let targetOpt = findNearestUncolonizedSystem(state, fleet.location)
      if targetOpt.isSome:
        order.orderType = FleetOrderType.Move
        order.targetSystem = targetOpt
        order.targetFleet = none(FleetId)
        result.add(order)
        continue

    # Priority 5: Defend home colonies (patrol)
    # Find a colony that needs defense
    var needsDefense: Option[SystemId] = none(SystemId)
    for systemId, colony in state.colonies:
      if colony.owner == controller.houseId:
        # Check if there are enemy fleets nearby (simplified: just check this colony)
        let hasEnemyFleets = calculateFleetStrengthAtSystem(
          state, systemId, colony.owner
        ) < getFleetStrength(fleet)
        if hasEnemyFleets or colony.blockaded:
          needsDefense = some(systemId)
          break

    if needsDefense.isSome:
      order.orderType = FleetOrderType.Move
      order.targetSystem = needsDefense
      order.targetFleet = none(FleetId)
    else:
      # Priority 6: Exploration - send fleets to unknown systems
      # Instead of sitting idle, explore uncolonized systems
      if p.expansionDrive > 0.2 or rng.rand(1.0) < 0.3:
        let exploreTarget = findNearestUncolonizedSystem(state, fleet.location)
        if exploreTarget.isSome:
          order.orderType = FleetOrderType.Move
          order.targetSystem = exploreTarget
          order.targetFleet = none(FleetId)
          result.add(order)
          continue

      # Default: Patrol current location
      order.orderType = FleetOrderType.Patrol
      order.targetSystem = some(fleet.location)
      order.targetFleet = none(FleetId)

    result.add(order)

proc generateBuildOrders(controller: AIController, state: GameState, rng: var Rand): seq[BuildOrder] =
  ## Generate build orders based on 4X strategic needs and combat assessment
  ## Intelligently builds: Scouts, ETACs, Transports, and Military ships
  result = @[]
  let p = controller.personality
  let house = state.houses[controller.houseId]
  let myColonies = getOwnedColonies(state, controller.houseId)

  # Count what ships we already have
  var scoutCount = 0
  var etacCount = 0
  var transportCount = 0
  var militaryCount = 0

  for fleet in state.fleets.values:
    if fleet.owner == controller.houseId:
      for squadron in fleet.squadrons:
        case squadron.flagship.shipClass:
        of ShipClass.Scout:
          scoutCount += 1
        of ShipClass.ETAC:
          etacCount += 1
        of ShipClass.TroopTransport:
          transportCount += 1
        else:
          if squadron.flagship.shipType == ShipType.Military:
            militaryCount += 1

        for ship in squadron.ships:
          case ship.shipClass:
          of ShipClass.Scout:
            scoutCount += 1
          of ShipClass.ETAC:
            etacCount += 1
          of ShipClass.TroopTransport:
            transportCount += 1
          else:
            if ship.shipType == ShipType.Military:
              militaryCount += 1

  # Assess military situation
  let myMilitaryStrength = calculateMilitaryStrength(state, controller.houseId)
  var totalEnemyStrength = 0
  for otherHouse in state.houses.keys:
    if otherHouse != controller.houseId:
      let dipState = dip_types.getDiplomaticState(
        house.diplomaticRelations,
        otherHouse
      )
      if dipState == dip_types.DiplomaticState.Enemy:
        totalEnemyStrength += calculateMilitaryStrength(state, otherHouse)

  let militaryRatio = if totalEnemyStrength > 0:
    float(myMilitaryStrength) / float(totalEnemyStrength)
  else:
    2.0  # No enemies, we're doing fine

  # Check for threatened colonies
  var threatenedColonies = 0
  for colony in myColonies:
    let combat = assessCombatSituation(controller, state, colony.systemId)
    if combat.recommendRetreat or combat.recommendReinforce:
      threatenedColonies += 1

  # 4X PRIORITIES: What does this AI need right now?
  let needScouts = scoutCount < 1  # Always need at least 1 scout for exploration
  let needETACs = (etacCount < 1 and p.expansionDrive > 0.3 and
                   findNearestUncolonizedSystem(state, myColonies[0].systemId).isSome)
  let needTransports = (transportCount < 1 and p.aggression > 0.5 and militaryCount > 2)
  let needMilitary = (
    militaryRatio < 0.8 or  # Weaker than enemies
    threatenedColonies > 0 or  # Colonies under threat
    p.aggression > 0.6 or  # Aggressive strategy
    militaryCount < 2  # Minimum defense force
  )

  # Build at most productive colonies first
  var coloniesToBuild = myColonies
  coloniesToBuild.sort(proc(a, b: Colony): int = cmp(b.production, a.production))

  for colony in coloniesToBuild:
    if house.treasury < 50:
      break  # Not enough funds

    # Check if colony has shipyard for ship construction
    let hasShipyard = colony.shipyards.len > 0

    if not hasShipyard:
      # Can't build ships without shipyard
      continue

    # ========================================================================
    # 4X SHIP BUILDING PRIORITIES
    # ========================================================================

    # Priority 1: EXPLORE - Build scouts for exploration
    if needScouts:
      let scoutCost = getShipConstructionCost(ShipClass.Scout)
      if house.treasury >= scoutCost:
        result.add(BuildOrder(
          colonySystem: colony.systemId,
          buildType: BuildType.Ship,
          quantity: 1,
          shipClass: some(ShipClass.Scout),
          buildingType: none(string),
          industrialUnits: 0
        ))
        break  # One ship per turn

    # Priority 2: EXPAND - Build colony ships (ETACs)
    elif needETACs:
      let etacCost = getShipConstructionCost(ShipClass.ETAC)
      if house.treasury >= etacCost:
        result.add(BuildOrder(
          colonySystem: colony.systemId,
          buildType: BuildType.Ship,
          quantity: 1,
          shipClass: some(ShipClass.ETAC),
          buildingType: none(string),
          industrialUnits: 0
        ))
        break  # One ship per turn

    # Priority 3: EXTERMINATE - Build troop transports for invasion
    elif needTransports:
      let transportCost = getShipConstructionCost(ShipClass.TroopTransport)
      if house.treasury >= transportCost:
        result.add(BuildOrder(
          colonySystem: colony.systemId,
          buildType: BuildType.Ship,
          quantity: 1,
          shipClass: some(ShipClass.TroopTransport),
          buildingType: none(string),
          industrialUnits: 0
        ))
        break  # One ship per turn

    # Priority 4: COMBAT - Build military ships
    elif needMilitary:
      # Choose ship class based on strategy and treasury
      # Per economy.md:5.0 - must have FULL upfront cost in treasury
      var shipClass: ShipClass

      if house.treasury > 1000 and p.aggression > 0.7:
        # Rich and aggressive: build capital ships
        shipClass = if rng.rand(1.0) > 0.5: ShipClass.Battlecruiser else: ShipClass.Battleship
      elif house.treasury > 500:
        # Medium wealth: build cruisers
        shipClass = if rng.rand(1.0) > 0.5: ShipClass.Cruiser else: ShipClass.HeavyCruiser
      else:
        # Low funds: build lighter ships
        shipClass = if rng.rand(1.0) > 0.5: ShipClass.Destroyer else: ShipClass.LightCruiser

      # Check if we can actually afford this ship (upfront payment model)
      let shipCost = getShipConstructionCost(shipClass)
      if house.treasury >= shipCost:
        result.add(BuildOrder(
          colonySystem: colony.systemId,
          buildType: BuildType.Ship,
          quantity: 1,
          shipClass: some(shipClass),
          buildingType: none(string),
          industrialUnits: 0
        ))

        # Only one ship build per turn (expensive)
        break
      # else: Not enough funds for this ship, try other priorities

    # Priority 5: EXPLOIT - Build infrastructure for economic growth
    elif p.economicFocus > 0.6 and colony.infrastructure < 10 and house.treasury >= 150:
      result.add(BuildOrder(
        colonySystem: colony.systemId,
        buildType: BuildType.Infrastructure,
        quantity: 1,
        shipClass: none(ShipClass),
        buildingType: none(string),
        industrialUnits: 1
      ))

    # Priority 6: Build defenses for threatened colonies
    elif threatenedColonies > 0:
      # Build ground batteries at threatened colony
      if colony.groundBatteries < 5:
        let batteryCost = getBuildingCost("GroundBattery")
        if house.treasury >= batteryCost:
          result.add(BuildOrder(
            colonySystem: colony.systemId,
            buildType: BuildType.Building,
            quantity: 1,
            shipClass: none(ShipClass),
            buildingType: some("GroundBattery"),
            industrialUnits: 0
          ))
          break

    # Priority 7: Build shipyards if we don't have them (CRITICAL)
    elif not hasShipyard and p.aggression > 0.4:
      let shipyardCost = getBuildingCost("Shipyard")
      if house.treasury >= shipyardCost:
        result.add(BuildOrder(
          colonySystem: colony.systemId,
          buildType: BuildType.Building,
          quantity: 1,
          shipClass: none(ShipClass),
          buildingType: some("Shipyard"),
          industrialUnits: 0
        ))
        break

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
  ## Generate espionage action based on strategy and personality
  ## Use personality weights to determine if we should use espionage
  let p = controller.personality
  let house = state.houses[controller.houseId]

  # Check if we have EBP to use espionage (need at least 5 EBP for basic actions)
  if house.espionageBudget.ebpPoints < 5:
    return none(esp_types.EspionageAttempt)

  # Use espionage based on personality rather than strategy enum
  # High risk tolerance + low aggression = espionage focus
  let espionageChance = p.riskTolerance * 0.5 + (1.0 - p.aggression) * 0.3 + p.techPriority * 0.2

  if rng.rand(1.0) > espionageChance:
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

  # Set espionage budget based on personality (not strategy enum)
  # Use riskTolerance + (1-aggression) as proxy for espionage focus
  let espionageFocus = (p.riskTolerance + (1.0 - p.aggression)) / 2.0

  # Invest percentage of treasury, not absolute amounts
  # This prevents over-investment early game and scales with economy
  let ebpCost = 15  # PP per EBP (from config/espionage.toml)
  let cipCost = 15  # PP per CIP (from config/espionage.toml)

  if espionageFocus > 0.6:
    # High espionage focus - invest up to 15% of treasury
    let budget = house.treasury * 15 div 100
    result.ebpInvestment = min(budget div ebpCost, 50)
    result.cipInvestment = min(budget div (ebpCost * 2), 25)
  elif espionageFocus > 0.4:
    # Moderate espionage focus - invest up to 8% of treasury
    let budget = house.treasury * 8 div 100
    result.ebpInvestment = min(budget div ebpCost, 20)
    result.cipInvestment = min(budget div (ebpCost * 2), 10)
  else:
    # Low espionage focus - invest up to 3% of treasury
    let budget = house.treasury * 3 div 100
    result.ebpInvestment = min(budget div ebpCost, 10)
    result.cipInvestment = min(budget div (ebpCost * 2), 10)

# =============================================================================
# Export
# =============================================================================

export AIStrategy, AIPersonality, AIController
export newAIController, generateAIOrders, getStrategyPersonality
