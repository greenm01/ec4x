import std/[tables, options]
import ../../common/types/core # HouseId
import ../../types/core # GameState, Colony
import ../state_helpers # For getHouseColonies
import ../../population/types as pop_types # For colony.population

# Population management functions

proc getHousePopulationUnits*(state: GameState, houseId: HouseId): int =
  ## Get total population units for a house across all colonies
  result = 0
  for colony in state.getHouseColonies(houseId):
    result += colony.population