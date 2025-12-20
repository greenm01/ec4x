## Diplomacy Engine
##
## Diplomatic operations and state changes per diplomacy.md:8.1
## 3-state system: Neutral → Hostile → Enemy

import std/options
import ../../types/diplomacy as types
import ../../../common/types/[core, diplomacy]
import ../prestige/main as prestige

export types

## Diplomatic State Changes

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

proc setHostile*(relations: var DiplomaticRelations, otherHouse: HouseId,
                turn: int): DiplomaticEvent =
  ## Set diplomatic state to hostile
  let oldState = getDiplomaticState(relations, otherHouse)
  setDiplomaticState(relations, otherHouse, DiplomaticState.Hostile, turn)

  return DiplomaticEvent(
    houseId: "",  # Set by caller
    otherHouse: otherHouse,
    oldState: oldState,
    newState: DiplomaticState.Hostile,
    turn: turn,
    reason: "Diplomatic status set to Hostile",
    prestigeEvents: @[]
  )

## Helper Procs

proc initDiplomaticRelations*(): DiplomaticRelations =
  ## Initialize empty diplomatic relations
  result = DiplomaticRelations(
    relations: initTable[HouseId, DiplomaticRelation]()
  )

proc initViolationHistory*(): ViolationHistory =
  ## Initialize empty violation history
  result = ViolationHistory(
    violations: @[]
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

# isInPact is removed as there are no "pacts" in the new 3-state system.
# proc isInPact*(relations: DiplomaticRelations, otherHouse: HouseId): bool = ...

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
