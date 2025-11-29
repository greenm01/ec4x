## Dynamic Prestige Multiplier State
##
## Thread-local storage for current game's prestige multiplier
## This allows prestige calculations throughout the engine to use
## the correct map-size-based scaling without passing it everywhere

import prestige_config
import ../../common/logger

var currentMultiplier* {.threadvar.}: float

proc initializePrestigeMultiplier*(numSystems: int, numPlayers: int) =
  ## Initialize the prestige multiplier for the current game
  ## Call this once during game initialization
  currentMultiplier = calculateDynamicMultiplier(numSystems, numPlayers)
  logInfo("Prestige", "Dynamic multiplier initialized",
          "multiplier=", $currentMultiplier, " systems=", $numSystems, " players=", $numPlayers)

proc setPrestigeMultiplierForTesting*(multiplier: float) =
  ## Set the prestige multiplier directly for testing
  ## Use 1.0 to disable multiplier effects in tests
  currentMultiplier = multiplier

proc getPrestigeMultiplier*(): float =
  ## Get the current prestige multiplier
  ## Returns the base multiplier if not initialized
  if currentMultiplier == 0.0:
    logError("Prestige", "Multiplier uninitialized! Using base value",
             "base=", $globalPrestigeConfig.dynamic_scaling.base_multiplier)
    return globalPrestigeConfig.dynamic_scaling.base_multiplier
  return currentMultiplier

proc applyMultiplier*(baseValue: int): int =
  ## Apply the dynamic multiplier to a base prestige value
  result = int(float(baseValue) * getPrestigeMultiplier())
