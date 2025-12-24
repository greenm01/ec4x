## Retreat and ROE Evaluation System
##
## Implements Rules of Engagement evaluation,
## retreat decisions, and morale modifiers
## (Section 7.3.4, 7.3.5)

import std/[algorithm, strutils, options]
import ../../types/combat as combat_types

export combat_types

## ROE Evaluation (Section 7.1.1 and 7.3.4)

const roeThresholds* = [
  (roe: 0, threshold: 0.0, description: "Avoid all hostile forces"),
  (roe: 1, threshold: 999.0, description: "Engage only defenseless"),
  (roe: 2, threshold: 4.0, description: "Engage with 4:1 advantage"),
  (roe: 3, threshold: 3.0, description: "Engage with 3:1 advantage"),
  (roe: 4, threshold: 2.0, description: "Engage with 2:1 advantage"),
  (roe: 5, threshold: 1.5, description: "Engage with 3:2 advantage"),
  (roe: 6, threshold: 1.0, description: "Engage equal or inferior"),
  (roe: 7, threshold: 0.67, description: "Engage even if outgunned 3:2"),
  (roe: 8, threshold: 0.5, description: "Engage even if outgunned 2:1"),
  (roe: 9, threshold: 0.33, description: "Engage even if outgunned 3:1"),
  (roe: 10, threshold: 0.0, description: "Engage regardless of size")
]

proc getMoraleROEModifier*(prestige: int): int =
  ## Get ROE modifier based on House prestige/morale
  ## Section 7.3.4: Morale ROE Modifier table
  if prestige <= 0:
    return -2  # Crisis: retreat much more readily
  elif prestige <= 20:
    return -1  # Low: retreat more readily
  elif prestige <= 60:
    return 0   # Average/Good: no modification
  elif prestige <= 80:
    return +1  # High: fight more aggressively
  else:
    return +2  # Elite (81+): fight much more aggressively

proc evaluateRetreat*(
  taskForce: TaskForce,
  allTaskForces: seq[TaskForce],
  prestige: int
): RetreatEvaluation =
  ## Evaluate whether Task Force wants to retreat
  ## Section 7.3.4: Multi-Faction Retreat Evaluation
  ##
  ## Returns evaluation with decision and reasoning

  result = RetreatEvaluation(
    taskForce: taskForce.house,
    wantsToRetreat: false,
    effectiveROE: taskForce.roe,
    ourStrength: 0,
    enemyStrength: 0,
    strengthRatio: 0.0,
    reason: ""
  )

  # Homeworld defense exception - NEVER retreat
  if taskForce.isDefendingHomeworld:
    result.reason = "Defending homeworld - never retreat"
    return result

  # Calculate our strength
  result.ourStrength = taskForce.totalAS()

  if result.ourStrength == 0:
    result.wantsToRetreat = true
    result.reason = "All squadrons destroyed"
    return result

  # Calculate total hostile strength (all other Task Forces)
  for tf in allTaskForces:
    if tf.house != taskForce.house:
      result.enemyStrength += tf.totalAS()

  if result.enemyStrength == 0:
    result.reason = "No hostile forces remaining"
    return result

  # Calculate strength ratio (our AS / enemy AS)
  result.strengthRatio = float(result.ourStrength) / float(result.enemyStrength)

  # Apply morale modifier to effective ROE
  let moraleModifier = getMoraleROEModifier(prestige)
  result.effectiveROE = taskForce.roe + moraleModifier

  # Clamp to valid range
  if result.effectiveROE < 0:
    result.effectiveROE = 0
  if result.effectiveROE > 10:
    result.effectiveROE = 10

  # Get threshold for effective ROE
  let threshold = roeThresholds[result.effectiveROE].threshold

  # Decide whether to retreat
  if result.strengthRatio < threshold:
    result.wantsToRetreat = true
    result.reason = "Strength ratio $# below ROE $# threshold $#" % [
      $result.strengthRatio,
      $result.effectiveROE,
      $threshold
    ]
  else:
    result.reason = "Strength ratio $# meets ROE $# threshold $#" % [
      $result.strengthRatio,
      $result.effectiveROE,
      $threshold
    ]

## Multi-House Retreat Priority (Section 7.3.4)

proc getRetreatPriority*(taskForces: seq[TaskForce]): seq[HouseId] =
  ## Determine retreat order when multiple houses retreat simultaneously
  ## Section 7.3.4: weakest first, then by house ID

  type TFStrength = tuple[house: HouseId, strength: int]
  var strengths: seq[TFStrength] = @[]

  for tf in taskForces:
    strengths.add((tf.house, tf.totalAS()))

  # Sort by strength ascending (weakest first), then by house ID
  strengths.sort(proc(a, b: TFStrength): int =
    if a.strength != b.strength:
      return cmp(a.strength, b.strength)
    else:
      return cmp(a.house, b.house)
  )

  result = @[]
  for entry in strengths:
    result.add(entry.house)

## Combat Termination Check (Section 7.3.4)

proc checkCombatTermination*(
  taskForces: seq[TaskForce],
  consecutiveRoundsNoChange: int
): tuple[shouldEnd: bool, reason: string, victor: Option[HouseId]] =
  ## Check if combat should end
  ## Returns (shouldEnd, reason, victor)

  # Count alive Task Forces
  var aliveHouses: seq[HouseId] = @[]
  for tf in taskForces:
    if not tf.isEliminated():
      aliveHouses.add(tf.house)

  # Only one side remains
  if aliveHouses.len == 1:
    return (true, "Only one Task Force remains", some(aliveHouses[0]))

  # All eliminated
  if aliveHouses.len == 0:
    return (true, "All Task Forces eliminated", none(HouseId))

  # Stalemate after 20 rounds without progress
  if consecutiveRoundsNoChange >= 20:
    return (true, "Stalemate after 20 rounds without progress", none(HouseId))

  # Combat continues
  return (false, "", none(HouseId))

## Round Progress Tracking

proc hasProgressThisRound*(roundResults: seq[RoundResult]): bool =
  ## Check if any state changes occurred this round
  ## Used to detect stalemates
  for phaseResult in roundResults:
    if phaseResult.stateChanges.len > 0:
      return true
  return false

## Retreat Execution Helpers

proc canRetreat*(taskForce: TaskForce, roundNumber: int): bool =
  ## Check if Task Force can retreat this round
  ## Section 7.3.5: Can only retreat after first round

  if roundNumber == 1:
    return false

  # Homeworld defense exception
  if taskForce.isDefendingHomeworld:
    return false

  return true

proc executeRetreat*(taskForces: var seq[TaskForce], houseId: HouseId) =
  ## Remove Task Force from battle (retreat to fallback system)
  ## In actual game, this would trigger movement to fallback system
  ## For combat simulation, we just mark as retreated

  for i in countdown(taskForces.len - 1, 0):
    if taskForces[i].house == houseId:
      taskForces.delete(i)
      break

## String formatting

proc `$`*(eval: RetreatEvaluation): string =
  ## Pretty print retreat evaluation
  result = "House " & eval.taskForce & ": "
  if eval.wantsToRetreat:
    result &= "RETREAT"
  else:
    result &= "FIGHT"
  result &= " (ROE=$#, AS=$#, Enemy=$#, Ratio=$#) - $#" % [
    $eval.effectiveROE,
    $eval.ourStrength,
    $eval.enemyStrength,
    formatFloat(eval.strengthRatio, precision = 2),
    eval.reason
  ]
