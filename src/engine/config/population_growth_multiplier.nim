## Dynamic Population Growth Multiplier State
##
## Thread-local storage for current game's population growth multiplier
## This allows population growth calculations to scale based on map size
## without passing the multiplier everywhere

import std/math
import ../../common/logger

var growthMultiplier* {.threadvar.}: float32

proc setPopulationGrowthMultiplier*(multiplier: float32) =
  ## Set the population growth multiplier directly for testing
  ## Use 1.0 for standard growth rate in tests
  growthMultiplier = multiplier

proc getPopulationGrowthMultiplier*(): float32 =
  ## Get the current population growth multiplier
  ## Returns 1.0 if not initialized (standard growth)
  if growthMultiplier == 0.0:
    logWarn(
      "Economy",
      "Population growth multiplier uninitialized! Using 1.0 (standard growth)",
    )
    return 1.0
  return growthMultiplier

proc applyGrowthMultiplier*(baseGrowthRate: float32): float32 =
  ## Apply the dynamic multiplier to a base growth rate
  result = baseGrowthRate * getPopulationGrowthMultiplier()
