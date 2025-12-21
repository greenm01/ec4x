## Dynamic Prestige Multiplier State
##
## Thread-local storage for current game's prestige multiplier
## This allows prestige calculations throughout the engine to use
## the correct map-size-based scaling without passing it everywhere

import prestige_config
import ../../common/logger

var currentMultiplier* {.threadvar.}: float32

proc initializePrestigeMultiplier*(numSystems: int32, numPlayers: int32) =
  ## Initialize the prestige multiplier for the current game
  ## Call this once during game initialization
  currentMultiplier = calculateDynamicMultiplier(numSystems, numPlayers)
  logInfo("Prestige", "Dynamic multiplier initialized",
          "multiplier=", $currentMultiplier, " systems=", $numSystems, " players=", $numPlayers)

proc setPrestigeMultiplierForTesting*(multiplier: float32) =
  ## Set the prestige multiplier directly for testing
  ## Use 1.0 to disable multiplier effects in tests
  currentMultiplier = multiplier

proc getPrestigeMultiplier*(): float32 =
  ## Get the current prestige multiplier
  ## Returns the base multiplier if not initialized
  if currentMultiplier == 0.0:
    logError("Prestige", "Multiplier uninitialized! Using base value",
             "base=", $globalPrestigeConfig.dynamic_scaling.base_multiplier)
    return globalPrestigeConfig.dynamic_scaling.base_multiplier
  return currentMultiplier

proc applyMultiplier*(baseValue: int32): int32 =
  ## Apply the dynamic multiplier to a base prestige value
  result = int32(float32(baseValue) * getPrestigeMultiplier())
