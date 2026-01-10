## Diplomacy Operations (Entity-Specific Mutators)
##
## Handles direct modifications to diplomatic relations within the GameState.
## Per docs/architecture.md, these are low-level, index-aware mutators.

import std/tables
import ../types/[core, diplomacy, game_state]

proc setDiplomaticRelation*(
    state: GameState,
    sourceHouse: HouseId,
    targetHouse: HouseId,
    newState: DiplomaticState,
    sinceTurn: int32,
): DiplomaticRelation =
  ## Sets or updates a diplomatic relation between two houses.
  ## This is an entity-specific mutator, directly manipulating GameState.
  let key = (sourceHouse, targetHouse)
  let newRelation = DiplomaticRelation(
    sourceHouse: sourceHouse,
    targetHouse: targetHouse,
    state: newState,
    sinceTurn: sinceTurn,
  )
  state.diplomaticRelation[key] = newRelation
  return newRelation
