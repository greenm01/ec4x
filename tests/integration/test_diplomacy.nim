## Integration test for diplomacy system
##
## Tests diplomatic relations and pact violations

import std/[unittest, tables, options]
import ../../src/engine/diplomacy/[types, engine]
import ../../src/engine/prestige
import ../../src/engine/config/prestige_config
import ../../src/common/types/[core, diplomacy]

suite "Diplomacy System":

  test "Initialize diplomatic relations (default neutral)":
    let relations = initDiplomaticRelations()
    let otherHouse = "house2".HouseId

    let state = getDiplomaticState(relations, otherHouse)
    check state == DiplomaticState.Neutral

  test "Establish alliance pact":
    var relations = initDiplomaticRelations()
    let history = initViolationHistory()
    let otherHouse = "house2".HouseId

    let eventOpt = proposePact(relations, otherHouse, history, turn = 1)

    check eventOpt.isSome
    let event = eventOpt.get()
    check event.newState == DiplomaticState.Ally
    check event.oldState == DiplomaticState.Neutral
    check isInPact(relations, otherHouse)

  test "Cannot form pact when isolated":
    var relations = initDiplomaticRelations()
    var history = initViolationHistory()

    # Activate isolation
    history.isolation = DiplomaticIsolation(
      active: true,
      turnsRemaining: 5,
      violationTurn: 1
    )

    let otherHouse = "house2".HouseId
    let eventOpt = proposePact(relations, otherHouse, history, turn = 2)

    check eventOpt.isNone

  test "Declare war changes state to Enemy":
    var relations = initDiplomaticRelations()
    let otherHouse = "house2".HouseId

    # First establish pact
    setDiplomaticState(relations, otherHouse, DiplomaticState.Ally, turn = 1)

    # Then declare war
    let event = declareWar(relations, otherHouse, turn = 2)

    check event.newState == DiplomaticState.Enemy
    check event.oldState == DiplomaticState.Ally
    check isEnemy(relations, otherHouse)

  test "Pact violation records violation and activates penalties":
    var history = initViolationHistory()
    let violator = "house1".HouseId
    let victim = "house2".HouseId

    let violation = recordViolation(history, violator, victim, turn = 5, "Attack during pact")

    check violation.violator == violator
    check violation.victim == victim
    check violation.turn == 5

    # Check dishonored status activated
    check history.dishonored.active
    check history.dishonored.turnsRemaining == dishonoredDuration()

    # Check isolation activated
    check history.isolation.active
    check history.isolation.turnsRemaining == isolationDuration()

  test "Pact violation applies prestige penalties":
    var history = initViolationHistory()
    let violator = "house1".HouseId
    let victim = "house2".HouseId

    discard recordViolation(history, violator, victim, turn = 1, "First violation")

    let events = applyViolationPenalties(violator, victim, history, turn = 1)

    # Should have at least base penalty
    check events.len >= 1
    check events[0].source == PrestigeSource.PactViolation
    check events[0].amount == violationPrestigePenalty()  # -5

  test "Repeat violations incur additional penalties":
    var history = initViolationHistory()
    let violator = "house1".HouseId

    # First violation
    discard recordViolation(history, violator, "house2".HouseId, turn = 1, "First")
    # Second violation
    discard recordViolation(history, violator, "house3".HouseId, turn = 3, "Second")

    let events = applyViolationPenalties(violator, "house3".HouseId, history, turn = 3)

    # Should have base penalty + repeat penalty
    check events.len == 2
    check events[0].amount == violationPrestigePenalty()  # -5
    check events[1].amount == violationRepeatPenalty()   # -3 (1 repeat)

  test "Combat violation automatically converts to Enemy":
    var relations = initDiplomaticRelations()
    var history = initViolationHistory()
    let violator = "house1".HouseId
    let victim = "house2".HouseId

    # Establish pact first
    setDiplomaticState(relations, victim, DiplomaticState.Ally, turn = 1)

    # Violate during combat
    let event = handleCombatViolation(relations, history, violator, victim, turn = 5)

    # Should automatically become Enemy
    check event.newState == DiplomaticState.Enemy
    check event.oldState == DiplomaticState.Ally
    check isEnemy(relations, victim)

    # Should record violation
    check history.violations.len == 1
    check history.dishonored.active
    check history.isolation.active

    # Should have prestige penalties
    check event.prestigeEvents.len >= 1

  test "Dishonored status provides bonus prestige for attackers":
    var history = initViolationHistory()
    let violator = "house1".HouseId
    let attacker = "house3".HouseId

    # Record violation to activate dishonored status
    discard recordViolation(history, violator, "house2".HouseId, turn = 1, "Violation")

    # Attacker gets bonus
    let bonusOpt = getDishonoredBonus(attacker, violator, history)

    check bonusOpt.isSome
    let bonus = bonusOpt.get()
    check bonus.amount == dishonoredBonusPrestige()  # +1
    check bonus.source == PrestigeSource.CombatVictory

  test "Diplomatic status updates each turn":
    var history = initViolationHistory()

    # Activate both statuses
    history.dishonored = DishonoredStatus(
      active: true,
      turnsRemaining: 2,
      violationTurn: 1
    )
    history.isolation = DiplomaticIsolation(
      active: true,
      turnsRemaining: 3,
      violationTurn: 1
    )

    # Update once
    updateDiplomaticStatus(history)
    check history.dishonored.turnsRemaining == 1
    check history.isolation.turnsRemaining == 2

    # Update again
    updateDiplomaticStatus(history)
    check history.dishonored.turnsRemaining == 0
    check history.dishonored.active == false  # Should deactivate
    check history.isolation.turnsRemaining == 1
    check history.isolation.active == true  # Still active

  test "Pact reinstatement cooldown":
    var history = initViolationHistory()
    let violator = "house1".HouseId
    let victim = "house2".HouseId

    # Record violation
    discard recordViolation(history, violator, victim, turn = 1, "Violation")

    # Cannot reinstate immediately
    check canReinstatePact(history, victim, currentTurn = 2) == false
    check canReinstatePact(history, victim, currentTurn = 4) == false

    # Can reinstate after cooldown (5 turns)
    check canReinstatePact(history, victim, currentTurn = 7) == true

  test "Count recent violations within window":
    var history = initViolationHistory()
    let violator = "house1".HouseId

    # Add violations at different times
    discard recordViolation(history, violator, "house2".HouseId, turn = 1, "V1")
    discard recordViolation(history, violator, "house3".HouseId, turn = 3, "V2")
    discard recordViolation(history, violator, "house4".HouseId, turn = 15, "V3")

    # At turn 12, first two should be within window (10 turns)
    check countRecentViolations(history, currentTurn = 12) == 2

    # At turn 20, only last one should be in window
    check countRecentViolations(history, currentTurn = 20) == 1
