## Dynamic Prestige Multiplier State
##
## Thread-local storage for current game's prestige multiplier
## This allows prestige calculations throughout the engine to use
## the correct map-size-based scaling without passing it everywhere

import prestige_config

var currentMultiplier* {.threadvar.}: float

proc initializePrestigeMultiplier*(numSystems: int, numPlayers: int) =
  ## Initialize the prestige multiplier for the current game
  ## Call this once during game initialization
  currentMultiplier = calculateDynamicMultiplier(numSystems, numPlayers)
  echo "[Prestige] Dynamic multiplier: ", currentMultiplier,
       " (", numSystems, " systems, ", numPlayers, " players)"

proc getPrestigeMultiplier*(): float =
  ## Get the current prestige multiplier
  ## Returns the base multiplier if not initialized
  if currentMultiplier == 0.0:
    return globalPrestigeConfig.dynamic_scaling.base_multiplier
  return currentMultiplier

proc applyMultiplier*(baseValue: int): int =
  ## Apply the dynamic multiplier to a base prestige value
  result = int(float(baseValue) * getPrestigeMultiplier())
