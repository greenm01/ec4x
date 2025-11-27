## Diplomacy Engine
##
## Diplomatic operations and state changes per diplomacy.md:8.1

import std/[tables, options]
import types
import ../../common/types/[core, diplomacy]
import ../prestige
import ../config/prestige_config

export types

## Diplomatic State Changes

proc proposePact*(relations: var DiplomaticRelations, otherHouse: HouseId,
                 history: ViolationHistory, turn: int): Option[DiplomaticEvent] =
  ## Propose non-aggression pact with another house
  ## Returns event if successful, none if blocked

  # Check diplomatic isolation
  if not canFormPact(history):
    return none(DiplomaticEvent)

  # Check reinstatement cooldown
  if not canReinstatePact(history, otherHouse, turn):
    return none(DiplomaticEvent)

  # Check current state
  let currentState = getDiplomaticState(relations, otherHouse)
  if currentState == DiplomaticState.NonAggression:
    return none(DiplomaticEvent)  # Already in pact

  # Establish pact
  let oldState = currentState
  setDiplomaticState(relations, otherHouse, DiplomaticState.NonAggression, turn)

  return some(DiplomaticEvent(
    houseId: "",  # Set by caller
    otherHouse: otherHouse,
    oldState: oldState,
    newState: DiplomaticState.NonAggression,
    turn: turn,
    reason: "Non-Aggression Pact established",
    prestigeEvents: @[]
  ))

proc declareWar*(relations: var DiplomaticRelations, otherHouse: HouseId,
                turn: int): DiplomaticEvent =
  ## Declare war on another house
  let oldState = getDiplomaticState(relations, otherHouse)
  setDiplomaticState(relations, otherHouse, DiplomaticState.Enemy, turn)

  return DiplomaticEvent(
    houseId: "",  # Set by caller
    otherHouse: otherHouse,
    oldState: oldState,
    newState: DiplomaticState.Enemy,
    turn: turn,
    reason: "War declared",
    prestigeEvents: @[]
  )

proc setNeutral*(relations: var DiplomaticRelations, otherHouse: HouseId,
                turn: int): DiplomaticEvent =
  ## Set diplomatic state to neutral (peace/ceasefire)
  let oldState = getDiplomaticState(relations, otherHouse)
  setDiplomaticState(relations, otherHouse, DiplomaticState.Neutral, turn)

  return DiplomaticEvent(
    houseId: "",  # Set by caller
    otherHouse: otherHouse,
    oldState: oldState,
    newState: DiplomaticState.Neutral,
    turn: turn,
    reason: "Diplomatic status set to Neutral",
    prestigeEvents: @[]
  )

## Violation Handling

proc recordViolation*(history: var ViolationHistory, violator: HouseId,
                     victim: HouseId, turn: int, description: string): ViolationRecord =
  ## Record non-aggression pact violation
  ## Per diplomacy.md:8.1.2

  result = ViolationRecord(
    violator: violator,
    victim: victim,
    turn: turn,
    description: description
  )

  history.violations.add(result)

  # Activate dishonored status
  history.dishonored = DishonoredStatus(
    active: true,
    turnsRemaining: dishonoredDuration(),
    violationTurn: turn
  )

  # Activate diplomatic isolation
  history.isolation = DiplomaticIsolation(
    active: true,
    turnsRemaining: isolationDuration(),
    violationTurn: turn
  )

proc applyViolationPenalties*(violator: HouseId, victim: HouseId,
                              history: ViolationHistory, turn: int): seq[PrestigeEvent] =
  ## Calculate prestige penalties for pact violation
  ## Per diplomacy.md:8.1.2
  var events: seq[PrestigeEvent] = @[]

  # Base violation penalty
  events.add(createPrestigeEvent(
    PrestigeSource.PactViolation,
    violationPrestigePenalty(),
    "Violated Non-Aggression Pact with " & $victim
  ))

  # Repeat violation penalties
  let repeatCount = countRecentViolations(history, turn) - 1  # -1 for current violation
  if repeatCount > 0:
    let repeatPenalty = violationRepeatPenalty() * repeatCount
    events.add(createPrestigeEvent(
      PrestigeSource.PactViolation,
      repeatPenalty,
      "Repeat pact violation (" & $repeatCount & " prior violations)"
    ))

  return events

proc handleCombatViolation*(violatorRelations: var DiplomaticRelations,
                           violatorHistory: var ViolationHistory,
                           violator: HouseId, victim: HouseId,
                           turn: int): DiplomaticEvent =
  ## Handle pact violation detected during combat
  ## Per diplomacy.md:8.1.2
  ## Automatically converts to Enemy status

  # Record violation
  discard recordViolation(
    violatorHistory,
    violator,
    victim,
    turn,
    "Attack during Non-Aggression Pact"
  )

  # Calculate prestige penalties
  let prestigeEvents = applyViolationPenalties(violator, victim, violatorHistory, turn)

  # Automatically convert to Enemy
  setDiplomaticState(violatorRelations, victim, DiplomaticState.Enemy, turn)

  return DiplomaticEvent(
    houseId: violator,
    otherHouse: victim,
    oldState: DiplomaticState.NonAggression,
    newState: DiplomaticState.Enemy,
    turn: turn,
    reason: "Non-Aggression Pact violated (automatic war declaration)",
    prestigeEvents: prestigeEvents
  )

## Maintenance & Status Updates

proc updateDiplomaticStatus*(history: var ViolationHistory) =
  ## Update dishonored and isolation status (call each turn)
  ## Decrements turn counters

  # Update dishonored status
  if history.dishonored.active:
    history.dishonored.turnsRemaining -= 1
    if history.dishonored.turnsRemaining <= 0:
      history.dishonored.active = false

  # Update isolation status
  if history.isolation.active:
    history.isolation.turnsRemaining -= 1
    if history.isolation.turnsRemaining <= 0:
      history.isolation.active = false

proc getDishonoredBonus*(attackerHouse: HouseId, defenderHouse: HouseId,
                        defenderHistory: ViolationHistory): Option[PrestigeEvent] =
  ## Get prestige bonus for attacking dishonored house
  ## Per diplomacy.md:8.1.2: +1 prestige when attacking violator during dishonored status

  if defenderHistory.dishonored.active:
    return some(createPrestigeEvent(
      PrestigeSource.CombatVictory,
      dishonoredBonusPrestige(),
      "Attacked dishonored house " & $defenderHouse
    ))

  return none(PrestigeEvent)
