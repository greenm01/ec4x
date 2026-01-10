## Diplomacy Engine
##
## Diplomatic operations and state changes per diplomacy.md:8.1
## 3-state system: Neutral → Hostile → Enemy

import std/tables
import ../../types/[core, diplomacy, game_state]
import ../../entities/diplomacy_ops

export
  diplomacy.DiplomaticRelation, diplomacy.DiplomaticEvent, diplomacy.DiplomaticState

## Diplomatic State Changes

proc declareWar*(
    state: GameState, sourceHouse: HouseId, targetHouse: HouseId, turn: int32
): DiplomaticEvent =
  ## Declare war on another house
  let key = (sourceHouse, targetHouse)
  let oldState: DiplomaticState =
    if state.diplomaticRelation.hasKey(key):
      let relation = state.diplomaticRelation[key]
      relation.state
    else:
      DiplomaticState.Neutral

  # Update diplomatic relation
  discard setDiplomaticRelation(
    state,
    sourceHouse,
    targetHouse,
    DiplomaticState.Enemy,
    turn,
  )

  return DiplomaticEvent(
    houseId: sourceHouse,
    otherHouse: targetHouse,
    oldState: oldState,
    newState: DiplomaticState.Enemy,
    turn: turn,
    reason: "War declared",
    prestigeEvents: @[],
  )

proc setNeutral*(
    state: GameState, sourceHouse: HouseId, targetHouse: HouseId, turn: int32
): DiplomaticEvent =
  ## Set diplomatic state to neutral (peace/ceasefire)
  let key = (sourceHouse, targetHouse)
  let oldState: DiplomaticState =
    if state.diplomaticRelation.hasKey(key):
      let relation = state.diplomaticRelation[key]
      relation.state
    else:
      DiplomaticState.Neutral

  # Update diplomatic relation
  discard setDiplomaticRelation(
    state,
    sourceHouse,
    targetHouse,
    DiplomaticState.Neutral,
    turn,
  )

  return DiplomaticEvent(
    houseId: sourceHouse,
    otherHouse: targetHouse,
    oldState: oldState,
    newState: DiplomaticState.Neutral,
    turn: turn,
    reason: "Diplomatic status set to Neutral",
    prestigeEvents: @[],
  )

proc setHostile*(
    state: GameState, sourceHouse: HouseId, targetHouse: HouseId, turn: int32
): DiplomaticEvent =
  ## Set diplomatic state to hostile
  let key = (sourceHouse, targetHouse)
  let oldState: DiplomaticState =
    if state.diplomaticRelation.hasKey(key):
      let relation = state.diplomaticRelation[key]
      relation.state
    else:
      DiplomaticState.Neutral

  # Update diplomatic relation
  discard setDiplomaticRelation(
    state,
    sourceHouse,
    targetHouse,
    DiplomaticState.Hostile,
    turn,
  )

  return DiplomaticEvent(
    houseId: sourceHouse,
    otherHouse: targetHouse,
    oldState: oldState,
    newState: DiplomaticState.Hostile,
    turn: turn,
    reason: "Diplomatic status set to Hostile",
    prestigeEvents: @[],
  )
