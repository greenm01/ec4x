## Protostrator Assessment Module
##
## Byzantine Protostrator - Master of Ceremonies and Foreign Protocol
##
## Handles diplomatic situation analysis and pact recommendations
## Respects fog-of-war - estimates based on visible information

import std/[tables, options, sets, algorithm, strformat]
import ../../common/types
import ../../../engine/[gamestate, fog_of_war, fleet, squadron]
import ../../../engine/diplomacy/types as dip_types
import ../../../common/types/core
import ../shared/intelligence_types  # Phase 8.1: Intelligence-driven diplomacy
import ../config  # For globalRBAConfig

# =============================================================================
# Helper Functions
# =============================================================================

proc getOwnedFleets*(filtered: FilteredGameState, houseId: HouseId): seq[Fleet] =
  ## Get all fleets owned by a house
  result = @[]
  for fleet in filtered.ownFleets:
    if fleet.owner == houseId:
      result.add(fleet)

proc getFleetStrength*(fleet: Fleet): int =
  ## Calculate total strength of a fleet
  result = 0
  for squadron in fleet.squadrons:
    result += squadron.combatStrength()

import ../controller_types

# =============================================================================
# Strength Calculations
# =============================================================================

proc calculateMilitaryStrength*(filtered: FilteredGameState, houseId: HouseId): int =
  ## Calculate total military strength for a house
  result = 0
  let fleets = getOwnedFleets(filtered, houseId)
  for fleet in fleets:
    result += getFleetStrength(fleet)

proc calculateEconomicStrength*(filtered: FilteredGameState, houseId: HouseId): int =
  ## Calculate total economic strength for a house
  ## RESPECTS FOG-OF-WAR: Can only see own house's full details
  result = 0

  if houseId == filtered.viewingHouse:
    # Own house - full details
    let house = filtered.ownHouse
    let colonies = filtered.ownColonies

    # Treasury value
    result += house.treasury

    # Colony production value
    for colony in colonies:
      result += colony.production * 10  # Weight production highly
      result += colony.infrastructure * globalRBAConfig.protostrator.infrastructure_value_per_point
  else:
    # Enemy house - estimate from visible colonies only
    for visCol in filtered.visibleColonies:
      if visCol.owner == houseId:
        if visCol.production.isSome:
          result += visCol.production.get() * 10
        # Can't see infrastructure for enemy colonies

proc findMutualEnemies*(filtered: FilteredGameState, houseA: HouseId, houseB: HouseId): seq[HouseId] =
  ## Find houses that both houseA and houseB consider enemies
  ## RESPECTS FOG-OF-WAR: Can only see our own house's diplomatic relations
  result = @[]

  # Can only determine mutual enemies if we are houseA
  if houseA != filtered.viewingHouse:
    return result  # Can't see other house's diplomatic relations

  let ourHouse = filtered.ownHouse

  for otherHouse in filtered.housePrestige.keys:
    if otherHouse == houseA or otherHouse == houseB:
      continue

    # We can see our own enemies
    let weAreEnemies = dip_types.isEnemy(ourHouse.diplomaticRelations, otherHouse)
    # Assume houseB has similar enemies (imperfect information)
    if weAreEnemies:
      result.add(otherHouse)

# =============================================================================
# Phase 8.1: Intelligence-Driven Alliance Opportunities
# =============================================================================

proc findMutualEnemiesWithIntelligence*(
  filtered: FilteredGameState,
  houseA: HouseId,
  houseB: HouseId,
  intelSnapshot: IntelligenceSnapshot
): seq[HouseId] =
  ## Phase 8.1: Find confirmed mutual enemies using diplomatic intelligence
  ## Uses espionage intelligence on enemy wars and hostilities
  result = @[]

  # Can only determine mutual enemies if we are houseA
  if houseA != filtered.viewingHouse:
    return result

  let ourHouse = filtered.ownHouse
  var ourEnemies = initHashSet[HouseId]()
  var houseBEnemies = initHashSet[HouseId]()

  # Our confirmed enemies from diplomatic relations
  for otherHouse in filtered.housePrestige.keys:
    if otherHouse != houseA:
      if dip_types.isEnemy(ourHouse.diplomaticRelations, otherHouse):
        ourEnemies.incl(otherHouse)

  # HouseB's enemies from intelligence (diplomatic events)
  for event in intelSnapshot.diplomatic.recentDiplomaticEvents:
    if houseB in event.houses:
      case event.eventType
      of DiplomaticEventType.WarDeclared:
        # HouseB is at war - find the other party
        for house in event.houses:
          if house != houseB and house != houseA:
            houseBEnemies.incl(house)
      of DiplomaticEventType.DiplomaticBreak:
        # Broken relations - potential hostility
        for house in event.houses:
          if house != houseB and house != houseA:
            houseBEnemies.incl(house)
      else:
        discard

  # Also check hostility intelligence
  for house, hostility in intelSnapshot.diplomatic.observedHostility:
    if house == houseB:
      continue
    # If we observe houseB as hostile to others, add them
    # (This requires additional intel data not yet available - skip for now)

  # Intersection: houses that are enemies to both
  for enemy in ourEnemies:
    if enemy in houseBEnemies:
      result.add(enemy)

proc identifyEnemiesUnderPressure*(
  filtered: FilteredGameState,
  intelSnapshot: IntelligenceSnapshot
): seq[tuple[houseId: HouseId, distractedBy: seq[HouseId], opportunityScore: float]] =
  ## Phase 8.1: Identify enemy houses that are also fighting others (distracted)
  ## Useful for:
  ## - Domestikos: Target distracted enemies for attack
  ## - Drungarius: Opportunistic espionage when enemies are busy
  ## - Protostrator: Diplomatic escalation timing
  result = @[]

  let ourHouse = filtered.ownHouse
  let ourHouseId = filtered.viewingHouse

  # Analyze our enemies
  for houseId in filtered.housePrestige.keys:
    if houseId == ourHouseId:
      continue

    # Only analyze houses that are hostile or enemy to us
    if not (dip_types.isEnemy(ourHouse.diplomaticRelations, houseId) or
            dip_types.isHostile(ourHouse.diplomaticRelations, houseId)):
      continue

    var opportunityScore = 0.0
    var distractedBy: seq[HouseId] = @[]

    # Check combat lessons for fights involving this enemy
    for lesson in intelSnapshot.military.combatLessonsLearned:
      if lesson.enemyHouse == houseId:
        # This enemy fought someone (could be us or others)
        let recentCombat = (filtered.turn - lesson.turn) <= globalRBAConfig.protostrator.combat_freshness_turns
        if recentCombat:
          opportunityScore += globalRBAConfig.protostrator.opportunity_score_recent_combat  # Recent combat = distracted

      # Check if they're fighting someone else (not us)
      # (This requires checking if the combat was against another house)
      # For now, we can infer from diplomatic events

    # Check diplomatic events for wars/conflicts
    for event in intelSnapshot.diplomatic.recentDiplomaticEvents:
      if houseId in event.houses:
        case event.eventType
        of DiplomaticEventType.WarDeclared:
          # This enemy is at war with someone
          for house in event.houses:
            if house != houseId and house != ourHouseId:
              if house notin distractedBy:
                distractedBy.add(house)
                opportunityScore += globalRBAConfig.protostrator.opportunity_score_at_war  # At war with others = vulnerable
        of DiplomaticEventType.DiplomaticBreak:
          # Diplomatic tensions
          for house in event.houses:
            if house != houseId and house != ourHouseId:
              opportunityScore += globalRBAConfig.protostrator.opportunity_score_tensions  # Tensions = potential distraction
        else:
          discard

    # Check hostility levels - if enemy is hostile to many houses
    var hostileToCount = 0
    for otherHouse in filtered.housePrestige.keys:
      if otherHouse == houseId or otherHouse == ourHouseId:
        continue
      # Check if enemy has hostile relations (from intel)
      if intelSnapshot.diplomatic.observedHostility.hasKey(houseId):
        hostileToCount += 1

    if hostileToCount >= 2:
      opportunityScore += globalRBAConfig.protostrator.opportunity_score_multiple_fronts  # Fighting on multiple fronts = vulnerable

    # Only include if there's an opportunity
    if opportunityScore > 0.0 or distractedBy.len > 0:
      result.add((houseId: houseId, distractedBy: distractedBy, opportunityScore: opportunityScore))

  # Sort by opportunity score (highest first)
  result.sort do (a, b: auto) -> int:
    if a.opportunityScore > b.opportunityScore: -1
    elif a.opportunityScore < b.opportunityScore: 1
    else: 0

proc estimateViolationRisk*(filtered: FilteredGameState, targetHouse: HouseId): float =
  ## Estimate risk that target house will violate a pact (0.0-1.0)
  ## RESPECTS FOG-OF-WAR: Can't see other houses' violation history
  ## Returns a conservative default estimate

  # Without access to violation history, use a moderate default risk
  # TODO: Could enhance with intelligence reports if available
  return globalRBAConfig.protostrator.baseline_risk  # Baseline risk

# =============================================================================
# Phase 8.2: Impending Attack Detection
# =============================================================================

type
  DiplomaticUrgency* {.pure.} = enum
    ## Urgency level for diplomatic action
    None,      # No immediate threats
    Low,       # Minor tensions
    Moderate,  # Concerning indicators
    High,      # Multiple warning signs
    Critical   # Imminent attack likely

  ThreatIndicator* = object
    ## Indicator of potential hostile action
    source*: HouseId
    urgency*: DiplomaticUrgency
    indicators*: seq[string]  # Specific warning signs
    recommendedAction*: string

proc assessDiplomaticUrgency*(
  filtered: FilteredGameState,
  intelSnapshot: IntelligenceSnapshot
): seq[ThreatIndicator] =
  ## Phase 8.2: Assess urgency of diplomatic threats based on intelligence
  ## Detects warning signs of impending attacks:
  ## 1. Enemy fleet buildup near borders
  ## 2. Recent scouting activity (war preparation)
  ## 3. Espionage activity (hostile intentions)
  ## 4. Rapid military capability growth
  result = @[]

  let ourHouseId = filtered.viewingHouse
  let ourHouse = filtered.ownHouse

  # Analyze each house for threat indicators
  for houseId in filtered.housePrestige.keys:
    if houseId == ourHouseId:
      continue

    var indicators: seq[string] = @[]
    var urgencyScore = 0

    # 1. Fleet buildup near our borders (CRITICAL indicator)
    var nearbyFleetStrength = 0
    for fleet in intelSnapshot.military.knownEnemyFleets:
      if fleet.owner == houseId:
        # Check if fleet is near our colonies (within 2 jumps)
        for colony in filtered.ownColonies:
          # Simplified distance check (would need proper pathfinding)
          # For now, check if in same system or adjacent
          if fleet.lastKnownLocation == colony.systemId:
            nearbyFleetStrength += fleet.estimatedStrength
            indicators.add(&"Fleet strength {fleet.estimatedStrength} detected at {colony.systemId}")

    if nearbyFleetStrength > 50:
      urgencyScore += globalRBAConfig.protostrator.urgency_critical_threats
      indicators.add(&"Large fleet presence near borders ({nearbyFleetStrength} total)")

    # 2. Recent scouting activity (war preparation indicator)
    var recentScoutingCount = 0
    for lesson in intelSnapshot.military.combatLessonsLearned:
      if lesson.enemyHouse == houseId:
        let turnsSinceContact = filtered.turn - lesson.turn
        if turnsSinceContact <= 3:
          recentScoutingCount += 1

    if recentScoutingCount >= 2:
      urgencyScore += globalRBAConfig.protostrator.urgency_border_tension
      indicators.add(&"Increased military contact ({recentScoutingCount} encounters in last 3 turns)")

    # 3. Espionage activity (hostile intentions indicator)
    if intelSnapshot.espionage.detectionRisks.hasKey(houseId):
      let risk = intelSnapshot.espionage.detectionRisks[houseId]
      case risk
      of DetectionRiskLevel.High, DetectionRiskLevel.Critical:
        urgencyScore += globalRBAConfig.protostrator.urgency_diplomatic_isolation
        indicators.add(&"Heavy espionage activity detected (risk: {$risk})")
      of DetectionRiskLevel.Moderate:
        urgencyScore += 1
        indicators.add("Moderate espionage activity detected")
      else:
        discard

    # 4. Military capability growth (rapid buildup = threat)
    if intelSnapshot.military.enemyMilitaryCapability.hasKey(houseId):
      let capability = intelSnapshot.military.enemyMilitaryCapability[houseId]
      if capability.estimatedFleetStrength > 100:
        urgencyScore += globalRBAConfig.protostrator.urgency_economic_pressure
        indicators.add(&"Strong military capability (estimated strength: {capability.estimatedFleetStrength})")

    # 5. Check diplomatic hostility escalation
    if intelSnapshot.diplomatic.observedHostility.hasKey(houseId):
      let hostility = intelSnapshot.diplomatic.observedHostility[houseId]
      case hostility
      of HostilityLevel.Aggressive:
        urgencyScore += globalRBAConfig.protostrator.urgency_prestige_threat
        indicators.add("Aggressive diplomatic posture observed")
      of HostilityLevel.Hostile:
        urgencyScore += 1
        indicators.add("Hostile diplomatic posture")
      else:
        discard

    # 6. Existing diplomatic state
    if dip_types.isEnemy(ourHouse.diplomaticRelations, houseId):
      urgencyScore += 1  # Already at war - baseline urgency

    # Determine urgency level and recommended action
    if indicators.len > 0:
      let urgency = if urgencyScore >= 6: DiplomaticUrgency.Critical
                    elif urgencyScore >= 4: DiplomaticUrgency.High
                    elif urgencyScore >= 2: DiplomaticUrgency.Moderate
                    else: DiplomaticUrgency.Low

      let action = case urgency
        of DiplomaticUrgency.Critical:
          "URGENT: Prepare defenses, consider preemptive strike"
        of DiplomaticUrgency.High:
          "High priority: Reinforce borders, diplomatic engagement"
        of DiplomaticUrgency.Moderate:
          "Monitor closely, position defensive fleets"
        of DiplomaticUrgency.Low:
          "Maintain surveillance, standard defensive posture"
        else:
          ""

      result.add(ThreatIndicator(
        source: houseId,
        urgency: urgency,
        indicators: indicators,
        recommendedAction: action
      ))

  # Sort by urgency (most urgent first)
  result.sort do (a, b: ThreatIndicator) -> int:
    if ord(a.urgency) > ord(b.urgency): -1
    elif ord(a.urgency) < ord(b.urgency): 1
    else: 0

# =============================================================================
# Diplomatic Assessment
# =============================================================================

proc assessDiplomaticSituation*(controller: AIController, filtered: FilteredGameState,
                                targetHouse: HouseId): DiplomaticAssessment =
  ## Evaluate diplomatic relationship with target house
  ## Returns strategic assessment for decision making
  ## RESPECTS FOG-OF-WAR: Uses only available information
  let myHouse = filtered.ownHouse
  let p = controller.personality

  result.targetHouse = targetHouse
  result.currentState = dip_types.getDiplomaticState(
    myHouse.diplomaticRelations,
    targetHouse
  )

  # Calculate relative strengths
  let myMilitary = calculateMilitaryStrength(filtered, controller.houseId)
  let theirMilitary = calculateMilitaryStrength(filtered, targetHouse)
  result.relativeMilitaryStrength = if theirMilitary > 0:
    float(myMilitary) / float(theirMilitary)
  else:
    10.0  # They have no military

  let myEconomy = calculateEconomicStrength(filtered, controller.houseId)
  let theirEconomy = calculateEconomicStrength(filtered, targetHouse)
  result.relativeEconomicStrength = if theirEconomy > 0:
    float(myEconomy) / float(theirEconomy)
  else:
    10.0  # They have no economy

  # Find mutual enemies
  if controller.intelligenceSnapshot.isSome:
    result.mutualEnemies = findMutualEnemiesWithIntelligence(filtered, controller.houseId, targetHouse, controller.intelligenceSnapshot.get())
  else:
    # Fallback to non-intel version if snapshot is not available
    result.mutualEnemies = findMutualEnemies(filtered, controller.houseId, targetHouse)

  # Estimate violation risk
  result.violationRisk = estimateViolationRisk(filtered, targetHouse)

  # Strategic recommendations based on personality
  case result.currentState
  of dip_types.DiplomaticState.Neutral:
    # Should we propose a pact?
    var pactScore = 0.0

    # Stronger neighbor = want pact (defensive)
    if result.relativeMilitaryStrength < 0.8:
      pactScore += globalRBAConfig.protostrator_pact_assessment.shared_enemies_weight

    # Mutual enemies = want pact (alliance)
    pactScore += float(result.mutualEnemies.len) * globalRBAConfig.protostrator_pact_assessment.mutual_enemies_weight

    # High diplomacy value = more likely to seek pacts
    pactScore += p.diplomacyValue * globalRBAConfig.protostrator_pact_assessment.diplomacy_trait_weight

    # Low violation risk = more likely to trust
    pactScore += (1.0 - result.violationRisk) * globalRBAConfig.protostrator_pact_assessment.trust_weight

    result.recommendPact = pactScore > globalRBAConfig.protostrator_pact_assessment.recommendation_threshold

    # Should we escalate to Hostile or Enemy?
    var hostileScore = 0.0
    var enemyScore = 0.0

    # Aggressive personality
    hostileScore += p.aggression * globalRBAConfig.protostrator_stance_recommendations.aggression_hostile_weight
    enemyScore += p.aggression * globalRBAConfig.protostrator_stance_recommendations.aggression_enemy_weight

    # Weaker target
    if result.relativeMilitaryStrength > 1.5:
      hostileScore += globalRBAConfig.protostrator_stance_recommendations.opportunity_hostile_weight
      enemyScore += globalRBAConfig.protostrator_stance_recommendations.opportunity_enemy_weight

    # Low diplomacy value
    hostileScore += (1.0 - p.diplomacyValue) * globalRBAConfig.protostrator_stance_recommendations.opportunity_hostile_weight
    enemyScore += (1.0 - p.diplomacyValue) * globalRBAConfig.protostrator_stance_recommendations.opportunity_enemy_weight

    result.recommendHostile = hostileScore > globalRBAConfig.protostrator_stance_recommendations.hostile_threshold
    result.recommendEnemy = enemyScore > globalRBAConfig.protostrator_stance_recommendations.enemy_threshold


  of dip_types.DiplomaticState.Hostile:
    # Hostile state - tensions escalated, should we escalate to war or de-escalate?
    var escalateScore = 0.0
    var deescalateScore = 0.0

    # Aggressive personality wants war
    escalateScore += p.aggression * globalRBAConfig.protostrator_stance_recommendations.aggression_enemy_weight

    # Weaker target = escalate
    if result.relativeMilitaryStrength > 1.3:
      escalateScore += globalRBAConfig.protostrator_stance_recommendations.opportunity_enemy_weight

    # Much stronger enemy = de-escalate
    if result.relativeMilitaryStrength < 0.6:
      deescalateScore += 0.5

    # High diplomacy value = prefer de-escalation
    deescalateScore += p.diplomacyValue * globalRBAConfig.protostrator_stance_recommendations.diplomacy_deescalate_weight

    result.recommendEnemy = escalateScore > globalRBAConfig.protostrator_stance_recommendations.escalate_threshold
    result.recommendNeutral = deescalateScore > globalRBAConfig.protostrator_stance_recommendations.deescalate_threshold

  of dip_types.DiplomaticState.Enemy:
    # Should we normalize relations?
    var normalizeScore = 0.0

    # Much stronger enemy = want peace
    if result.relativeMilitaryStrength < 0.5:
      normalizeScore += 0.5

    # High diplomacy value
    normalizeScore += p.diplomacyValue * globalRBAConfig.protostrator_stance_recommendations.diplomacy_normalize_weight

    # Low aggression
    normalizeScore += (1.0 - p.aggression) * globalRBAConfig.protostrator_stance_recommendations.peace_bias_weight

    # Recommend neutral if score high enough
    if normalizeScore > globalRBAConfig.protostrator_stance_recommendations.normalize_threshold:
      result.recommendEnemy = false
    else:
      result.recommendEnemy = true  # Stay enemies
