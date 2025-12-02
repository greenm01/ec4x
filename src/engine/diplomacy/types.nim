## Diplomacy System Types
##
## Type definitions for diplomatic relations per diplomacy.md:8.1
##
## Core diplomatic concepts:
## - DiplomaticState: Neutral, Ally, Enemy
## - Violations: Track pact violations and penalties
## - Dishonored Status: Reputational damage after violation

import std/tables
import ../../common/types/[core, diplomacy, units]
import ../prestige
import ../config/[prestige_config, prestige_multiplier, diplomacy_config]

export core.HouseId
export diplomacy.DiplomaticState
export prestige.PrestigeEvent
export diplomacy_config.globalDiplomacyConfig
export units.ShipClass

type
  ## Diplomatic Relations

  DiplomaticRelation* = object
    ## Bilateral relationship between two houses
    state*: DiplomaticState
    sinceTurn*: int  # When this state was established

  DiplomaticRelations* = object
    ## All diplomatic relations for a house
    ## Key is other HouseId, value is relation with that house
    relations*: Table[HouseId, DiplomaticRelation]

  ## Non-Aggression Pact Violations

  ViolationRecord* = object
    ## Record of non-aggression pact violation
    violator*: HouseId
    victim*: HouseId
    turn*: int
    description*: string

  DishonoredStatus* = object
    ## Track dishonored status after violation (diplomacy.md:8.1.2)
    active*: bool
    turnsRemaining*: int  # 3 turns of dishonored status
    violationTurn*: int   # When violation occurred

  DiplomaticIsolation* = object
    ## Track diplomatic isolation after violation (diplomacy.md:8.1.2)
    active*: bool
    turnsRemaining*: int  # 5 turns cannot form new pacts
    violationTurn*: int

  ViolationHistory* = object
    ## Track violation history for repeat offenses
    violations*: seq[ViolationRecord]
    dishonored*: DishonoredStatus
    isolation*: DiplomaticIsolation

  ## Diplomatic Events

  DiplomaticEvent* = object
    ## Diplomatic status change event
    houseId*: HouseId
    otherHouse*: HouseId
    oldState*: DiplomaticState
    newState*: DiplomaticState
    turn*: int
    reason*: string
    prestigeEvents*: seq[PrestigeEvent]  # Prestige changes from this event

  DiplomaticReport* = object
    ## Diplomacy phase report
    turn*: int
    events*: seq[DiplomaticEvent]
    violations*: seq[ViolationRecord]

  ## Fleet Classification for Escalation Rules

  FleetClassification* {.pure.} = enum
    ## Classify fleets for diplomatic escalation purposes
    ## Scout-only fleets trigger "Hostile" escalation
    ## Combat/mixed fleets trigger "Enemy" escalation
    ScoutOnly      # Only contains Scout squadrons (→ Hostile)
    Combat         # Contains combat squadrons (capital ships, escorts, raiders) (→ Enemy)
    Mixed          # Contains both scouts and combat squadrons (→ Enemy)

## Fleet Classification Helper

proc classifyFleet*(fleet: auto): FleetClassification =
  ## Classify a fleet based on squadron composition
  ## Used to determine appropriate diplomatic escalation level
  var hasScouts = false
  var hasCombat = false

  for squadron in fleet.squadrons:
    if squadron.flagship.shipClass == ShipClass.Scout:
      hasScouts = true
    else:
      hasCombat = true

  if hasScouts and hasCombat:
    return FleetClassification.Mixed
  elif hasScouts:
    return FleetClassification.ScoutOnly
  else:
    return FleetClassification.Combat

## Configuration accessors per diplomacy.md:8.1.2
## Values loaded from diplomacy.toml and prestige.toml

proc dishonoredDuration*(): int =
  ## Get dishonored status duration from config
  globalDiplomacyConfig.pact_violations.dishonored_status_turns

proc isolationDuration*(): int =
  ## Get diplomatic isolation duration from config
  globalDiplomacyConfig.pact_violations.diplomatic_isolation_turns

proc pactReinstatementCooldown*(): int =
  ## Get pact reinstatement cooldown from config
  globalDiplomacyConfig.pact_violations.pact_reinstatement_cooldown

proc violationRepeatWindow*(): int =
  ## Get repeat violation window from config
  globalDiplomacyConfig.pact_violations.repeat_violation_window

proc violationPrestigePenalty*(): int =
  ## Get violation prestige penalty from prestige config with dynamic scaling
  applyMultiplier(globalPrestigeConfig.diplomacy.pact_violation)

proc violationRepeatPenalty*(): int =
  ## Get repeat violation prestige penalty from prestige config with dynamic scaling
  applyMultiplier(globalPrestigeConfig.diplomacy.repeat_violation)

proc dishonoredBonusPrestige*(): int =
  ## Get dishonored bonus prestige from prestige config with dynamic scaling
  applyMultiplier(globalPrestigeConfig.diplomacy.dishonored_bonus)

## Helper Procs

proc initDiplomaticRelations*(): DiplomaticRelations =
  ## Initialize empty diplomatic relations
  result = DiplomaticRelations(
    relations: initTable[HouseId, DiplomaticRelation]()
  )

proc initViolationHistory*(): ViolationHistory =
  ## Initialize empty violation history
  result = ViolationHistory(
    violations: @[],
    dishonored: DishonoredStatus(
      active: false,
      turnsRemaining: 0,
      violationTurn: 0
    ),
    isolation: DiplomaticIsolation(
      active: false,
      turnsRemaining: 0,
      violationTurn: 0
    )
  )

proc getDiplomaticState*(relations: DiplomaticRelations, otherHouse: HouseId): DiplomaticState =
  ## Get diplomatic state with another house (defaults to Neutral)
  if otherHouse in relations.relations:
    return relations.relations[otherHouse].state
  return DiplomaticState.Neutral

proc setDiplomaticState*(relations: var DiplomaticRelations, otherHouse: HouseId,
                        state: DiplomaticState, turn: int) =
  ## Set diplomatic state with another house
  relations.relations[otherHouse] = DiplomaticRelation(
    state: state,
    sinceTurn: turn
  )

proc isInPact*(relations: DiplomaticRelations, otherHouse: HouseId): bool =
  ## Check if in non-aggression pact with house
  return getDiplomaticState(relations, otherHouse) == DiplomaticState.Ally

proc isEnemy*(relations: DiplomaticRelations, otherHouse: HouseId): bool =
  ## Check if house is enemy (open war)
  return getDiplomaticState(relations, otherHouse) == DiplomaticState.Enemy

proc isHostile*(relations: DiplomaticRelations, otherHouse: HouseId): bool =
  ## Check if house is hostile (tensions escalated)
  return getDiplomaticState(relations, otherHouse) == DiplomaticState.Hostile

proc isHostileOrEnemy*(relations: DiplomaticRelations, otherHouse: HouseId): bool =
  ## Check if house is hostile or enemy (any combat allowed)
  let state = getDiplomaticState(relations, otherHouse)
  return state in {DiplomaticState.Hostile, DiplomaticState.Enemy}

proc canFormPact*(history: ViolationHistory): bool =
  ## Check if house can form new non-aggression pacts (not isolated)
  return not history.isolation.active

proc canReinstatePact*(history: ViolationHistory, otherHouse: HouseId, currentTurn: int): bool =
  ## Check if can reinstate pact with specific house (5 turn cooldown)
  ## Per diplomacy.md:8.1.2
  for violation in history.violations:
    if violation.victim == otherHouse:
      let turnsSince = currentTurn - violation.turn
      if turnsSince < pactReinstatementCooldown():
        return false
  return true

proc countRecentViolations*(history: ViolationHistory, currentTurn: int): int =
  ## Count violations within repeat window
  result = 0
  for violation in history.violations:
    if currentTurn - violation.turn <= violationRepeatWindow():
      result += 1
