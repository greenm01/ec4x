## Fog of War System
##
## Provides visibility helper and re-exports createPlayerState()

import std/options
import ../types/[core, game_state]
import ./[engine, iterators, player_state as player_state_module]

export player_state_module.createPlayerState

proc hasVisibilityOn*(state: GameState, systemId: SystemId, houseId: HouseId): bool =
  ## Check if a house has visibility on a system (fog of war)
  ## A house can see a system if:
  ## - They own a colony there
  ## - They have a fleet present
  ## - They have a spy scout present
  ##
  ## Used by Space Guild for transfer path validation

  # Check if house owns colony in this system
  let colonyOpt = state.colonyBySystem(systemId)
  if colonyOpt.isSome:
    let colony = colonyOpt.get()
    if colony.owner == houseId:
        return true

  # Check if house has any fleets in this system using iterator
  for fleet in state.fleetsInSystem(systemId):
    if fleet.houseId == houseId:
      return true

  return false
