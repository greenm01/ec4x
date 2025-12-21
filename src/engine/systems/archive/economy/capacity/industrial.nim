import std/[tables, options]
import ../../common/types/core # HouseId
import ../../types/core # GameState, Colony
import ../state_helpers # For getHouseColonies

# Industrial capacity functions

proc getTotalHouseIndustrialUnits*(state: GameState, houseId: HouseId): int =
  ## Get total industrial units for a house across all colonies
  ## Used for capital squadron capacity calculation per reference.md Table 10.5
  result = 0
  for colony in state.getHouseColonies(houseId):
    result += colony.industrial.units