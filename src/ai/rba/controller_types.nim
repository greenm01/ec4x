## AI Controller Type Definition
##
## Separated to avoid circular imports between controller and subsystems

import std/tables
import ../common/types
import ../../engine/gamestate  # For FallbackRoute
import ../../common/types/core

type AIController* = ref object
  houseId*: HouseId
  strategy*: AIStrategy
  personality*: AIPersonality
  intelligence*: Table[SystemId, IntelligenceReport]
  operations*: seq[CoordinatedOperation]
  reserves*: seq[StrategicReserve]
  fallbackRoutes*: seq[FallbackRoute]
