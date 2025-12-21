## Victory Condition Evaluation System
##
## This module provides functions for evaluating game victory conditions.
## It encapsulates logic for various victory types, such as elimination and prestige, 
## as defined in game_setup configurations.

import std/[tables, options, algorithm]
import ../../common/types/core
import ../gamestate # For GameState type and its queries
import ../config/prestige_config # For prestige definitions

proc calculatePrestige*(state: GameState, houseId: HouseId): int =
  ## Return current prestige for a house
  ## Prestige is tracked via events and stored in House.prestige
  return state.houses[houseId].prestige

proc isFinalConfrontation*(state: GameState): bool =
  ## Check if only 2 houses remain (final confrontation)
  ## No dishonor penalties for inevitable war between final two houses
  let activeHouses = state.getActiveHouses()
  return activeHouses.len == 2

proc checkVictoryCondition*(state: GameState): Option[HouseId] =
  ## Check if any house has won the game
  ## Victory: last house standing (elimination)
  ## NOTE: Prestige victory removed - now handled by victory engine
  ## (src/engine/victory/) with configurable modes per game_setup/*.toml

  let activeHouses = state.getActiveHouses()

  # Last house standing (elimination victory)
  if activeHouses.len == 1:
    return some(activeHouses[0].id)

  # No victory yet
  return none(HouseId)
