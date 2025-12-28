## Prestige Engine - Multiplier and Utilities
##
## Provides prestige multiplier management and application functions.
## The multiplier is initialized once at game start based on map size.

import ../globals  # For gameConfig access
import ../../common/logger

# Private backing storage
var prestigeMultiplierImpl {.threadvar.}: float64

# Prestige multiplier property
proc `prestigeMultiplier=`*(multiplier: float32) =
  ## Set the prestige multiplier directly for testing
  ## Use 1.0 to disable multiplier effects in tests
  prestigeMultiplierImpl = multiplier

proc prestigeMultiplier*(): float32 =
  ## Get the current prestige multiplier
  ## Returns the base multiplier if not initialized
  if prestigeMultiplierImpl == 0.0:
    logWarn(
      "Prestige",
      "Multiplier uninitialized! Using base value",
      "base=",
      $gameConfig.prestige.dynamicScaling.baseMultiplier
    )
    return gameConfig.prestige.dynamicScaling.baseMultiplier
  return prestigeMultiplierImpl

proc applyPrestigeMultiplier*(baseValue: int32): int32 =
  ## Apply the dynamic multiplier to a base prestige value
  result = int32(float32(baseValue) * prestigeMultiplier())
