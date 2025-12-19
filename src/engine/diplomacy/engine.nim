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

