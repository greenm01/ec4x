## Diplomatic Assessment Module for EC4X Rule-Based AI
##
## Handles diplomatic situation analysis and pact recommendations
## Respects fog-of-war - estimates based on visible information

import std/[tables, options]
import ../common/types
import ../../engine/[gamestate, fog_of_war, fleet, squadron]
import ../../engine/diplomacy/types as dip_types
import ../../common/types/core

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

import ./controller_types

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
      result += colony.infrastructure * 5
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

proc estimateViolationRisk*(filtered: FilteredGameState, targetHouse: HouseId): float =
  ## Estimate risk that target house will violate a pact (0.0-1.0)
  ## RESPECTS FOG-OF-WAR: Can't see other houses' violation history
  ## Returns a conservative default estimate

  # Without access to violation history, use a moderate default risk
  # TODO: Could enhance with intelligence reports if available
  return 0.3  # 30% baseline risk

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
