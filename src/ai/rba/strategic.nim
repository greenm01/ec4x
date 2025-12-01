## Strategic Planning Module for EC4X Rule-Based AI
##
## Handles combat assessment, invasion planning, and strategic decision-making
## Respects fog-of-war - uses only visible tactical information

import std/[options, sequtils]
import ../common/types
import ../../engine/[gamestate, fog_of_war, fleet, squadron]
import ../../engine/diplomacy/types as dip_types
import ../../common/types/[core, planets, units]

import ./controller_types
import ./config  # RBA configuration system
import ./intelligence  # For isSystemColonized, getColony
import ./protostrator/assessment  # For getFleetStrength
import ./shared/colony_assessment  # Shared defense assessment

# =============================================================================
# Helper Functions
# =============================================================================

# isSystemColonized - moved to intelligence.nim to avoid duplication
# getColony - moved to intelligence.nim to avoid duplication
# getFleetStrength - moved to diplomacy.nim to avoid duplication

# =============================================================================
# Combat Assessment (using shared colony_assessment module)
# =============================================================================

proc calculateDefensiveStrength*(filtered: FilteredGameState, systemId: SystemId): int =
  ## Calculate total defensive strength of a colony
  ## Uses shared colony_assessment module for consistent calculations
  if not isSystemColonized(filtered, systemId):
    return 0

  let colonyOpt = getColony(filtered, systemId)
  if colonyOpt.isNone:
    return 0

  let colony = colonyOpt.get()
  return colony_assessment.calculateDefensiveStrength(colony)

proc calculateFleetStrengthAtSystem*(filtered: FilteredGameState, systemId: SystemId,
                                     houseId: HouseId): int =
  ## Calculate fleet strength for a specific house at a system
  result = 0
  for fleet in filtered.ownFleets:
    if fleet.owner == houseId and fleet.location == systemId:
      result += getFleetStrength(fleet)

proc estimateColonyValue*(filtered: FilteredGameState, systemId: SystemId): int =
  ## Estimate strategic value of a colony
  ## Uses shared colony_assessment module for consistent calculations
  if not isSystemColonized(filtered, systemId):
    return 0

  let colonyOpt = getColony(filtered, systemId)
  if colonyOpt.isNone:
    return 0

  let colony = colonyOpt.get()
  return colony_assessment.assessStrategicValue(colony)

proc assessCombatSituation*(controller: AIController, filtered: FilteredGameState,
                            targetSystem: SystemId): CombatAssessment =
  ## Evaluate combat situation for attacking a target system
  result.targetSystem = targetSystem

  if not isSystemColonized(filtered, targetSystem):
    result.recommendAttack = false
    return

  let targetColonyOpt = getColony(filtered, targetSystem)
  if targetColonyOpt.isNone:
    result.recommendAttack = false
    return
  let targetColony = targetColonyOpt.get()
  result.targetOwner = targetColony.owner

  if result.targetOwner == controller.houseId:
    result.recommendAttack = false
    return

  let myHouse = filtered.ownHouse
  let dipState = dip_types.getDiplomaticState(
    myHouse.diplomaticRelations,
    result.targetOwner
  )
  result.violatesPact = dipState == dip_types.DiplomaticState.Ally

  result.attackerFleetStrength = calculateFleetStrengthAtSystem(
    filtered, targetSystem, controller.houseId
  )
  result.defenderFleetStrength = calculateFleetStrengthAtSystem(
    filtered, targetSystem, result.targetOwner
  )

  result.starbaseStrength = 0
  result.groundBatteryCount = targetColony.groundBatteries
  result.planetaryShieldLevel = targetColony.planetaryShieldLevel
  result.groundForces = targetColony.armies + targetColony.marines

  for starbase in targetColony.starbases:
    if not starbase.isCrippled:
      result.starbaseStrength += 100

  let totalDefense = result.defenderFleetStrength +
                     calculateDefensiveStrength(filtered, targetSystem)

  if result.attackerFleetStrength == 0:
    result.estimatedCombatOdds = 0.0
  elif totalDefense == 0:
    result.estimatedCombatOdds = 1.0
  else:
    let ratio = float(result.attackerFleetStrength) / float(totalDefense)
    result.estimatedCombatOdds = ratio / (ratio + 0.8)
    result.estimatedCombatOdds = min(result.estimatedCombatOdds, 0.95)

  let expectedLossRate = 1.0 - result.estimatedCombatOdds
  result.expectedCasualties = int(
    float(result.attackerFleetStrength) * expectedLossRate * 0.3
  )

  result.strategicValue = estimateColonyValue(filtered, targetSystem)

  if result.starbaseStrength > 0:
    result.strategicValue += 50

  let p = controller.personality
  var attackThreshold = globalRBAConfig.strategic.attack_threshold

  if controller.strategy == AIStrategy.Aggressive:
    attackThreshold = globalRBAConfig.strategic.aggressive_attack_threshold
  elif p.riskTolerance > 0.7:
    attackThreshold = 0.5
  elif p.aggression < 0.3:
    attackThreshold = 0.8

  if result.starbaseStrength > 0 and attackThreshold > 0.5:
    attackThreshold -= 0.1

  if result.violatesPact:
    result.recommendAttack = false
  else:
    result.recommendAttack = result.estimatedCombatOdds >= attackThreshold

  result.recommendReinforce = (
    result.attackerFleetStrength > 0 and
    result.estimatedCombatOdds < attackThreshold and
    result.estimatedCombatOdds > globalRBAConfig.strategic.retreat_threshold
  )

  result.recommendRetreat = (
    result.attackerFleetStrength > 0 and
    result.estimatedCombatOdds < globalRBAConfig.strategic.retreat_threshold
  )

proc assessInvasionViability*(controller: AIController, filtered: FilteredGameState,
                              fleet: Fleet, targetSystem: SystemId): InvasionViability =
  ## 3-phase invasion viability assessment
  let combat = assessCombatSituation(controller, filtered, targetSystem)
  let targetColonyOpt = getColony(filtered, targetSystem)
  if targetColonyOpt.isNone:
    result.invasionViable = false
    return
  let targetColony = targetColonyOpt.get()
  let p = controller.personality

  # Space Combat Assessment
  let spaceAttackStrength = fleet.squadrons.foldl(a + b.combatStrength(), 0)
  let spaceDefenseStrength = combat.defenderFleetStrength

  if spaceDefenseStrength == 0:
    result.spaceOdds = 1.0
    result.canWinSpaceCombat = true
  else:
    let spaceRatio = float(spaceAttackStrength) / float(spaceDefenseStrength)
    result.spaceOdds = spaceRatio / (spaceRatio + 0.8)
    result.canWinSpaceCombat = result.spaceOdds >= 0.5

  # Starbase Assault Assessment
  if combat.starbaseStrength == 0:
    result.starbaseOdds = 1.0
    result.canDestroyStarbases = true
  else:
    let starbaseRatio = float(spaceAttackStrength) / float(combat.starbaseStrength)
    result.starbaseOdds = starbaseRatio / (starbaseRatio + 1.2)
    result.canDestroyStarbases = result.starbaseOdds >= 0.4

  # Ground Combat Assessment
  result.defenderGroundForces = combat.groundForces + combat.groundBatteryCount

  var marineCount = 0
  for spaceLiftShip in fleet.spaceLiftShips:
    if spaceLiftShip.shipClass == ShipClass.TroopTransport and not spaceLiftShip.isCrippled:
      if spaceLiftShip.cargo.cargoType == CargoType.Marines:
        marineCount += spaceLiftShip.cargo.quantity

  result.attackerGroundForces = marineCount

  if result.defenderGroundForces == 0:
    result.groundOdds = 1.0
    result.canWinGroundCombat = true
  elif result.attackerGroundForces == 0:
    result.groundOdds = 0.0
    result.canWinGroundCombat = false
  else:
    let groundRatio = float(result.attackerGroundForces) / float(result.defenderGroundForces)
    result.groundOdds = groundRatio / (groundRatio + 1.5)
    result.canWinGroundCombat = result.groundOdds >= 0.5

  # Overall Assessment
  result.invasionViable = (
    result.canWinSpaceCombat and
    result.canDestroyStarbases and
    result.canWinGroundCombat
  )

  result.strategicValue = combat.strategicValue

  # Decision: Invade, Blitz, Blockade, or Move
  let invasionThreshold = if p.riskTolerance > 0.6: 0.5 else: 0.65
  let blitzThreshold = if p.aggression > 0.6: 0.4 else: 0.5

  if result.invasionViable:
    result.recommendInvade = true
    result.recommendBlitz = false
    result.recommendBlockade = false
  elif result.canWinSpaceCombat and result.canDestroyStarbases:
    result.recommendInvade = false
    result.recommendBlitz = true
    result.recommendBlockade = false
  elif result.canWinSpaceCombat and result.spaceOdds >= 0.6:
    result.recommendInvade = false
    result.recommendBlitz = false
    result.recommendBlockade = (p.aggression < 0.5)
  else:
    result.recommendInvade = false
    result.recommendBlitz = false
    result.recommendBlockade = false
