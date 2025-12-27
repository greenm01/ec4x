import ../common/logger
import ./types/config

# Global game config
var gameConfig* {.threadvar.}: GameConfig
# Game scaling multipliers
var prestigeMultiplier* {.threadvar.}: float64
var popGrowthMultiplier* {.threadvar.}: float64

# Prestige growth multipliers
proc setPrestigeMultiplier*(multiplier: float32) =
  ## Set the prestige multiplier directly for testing
  ## Use 1.0 to disable multiplier effects in tests
  prestigeMultiplier = multiplier

proc getPrestigeMultiplier*(): float32 =
  ## Get the current prestige multiplier
  ## Returns the base multiplier if not initialized
  if prestigeMultiplier == 0.0:
    logWarn(
      "Prestige",
      "Multiplier uninitialized! Using base value",
      "base=",
      $gameConfig.prestige.dynamicScaling.baseMultiplier
    )
    return gameConfig.prestige.dynamicScaling.baseMultiplier
  return prestigeMultiplier

proc applyPrestigeMultiplier*(baseValue: int32): int32 =
  ## Apply the dynamic multiplier to a base prestige value
  result = int32(float32(baseValue) * getPrestigeMultiplier())

# Population growth multipliers
proc setPopulationGrowthMultiplier*(multiplier: float32) =
  ## Set the population growth multiplier directly for testing
  ## Use 1.0 for standard growth rate in tests
  popGrowthMultiplier = multiplier

proc getPopulationGrowthMultiplier*(): float32 =
  ## Get the current population growth multiplier
  ## Returns 1.0 if not initialized (standard growth)
  if popGrowthMultiplier == 0.0:
    logWarn(
      "Economy",
      "Population growth multiplier uninitialized! Using 1.0 (standard growth)",
    )
    return 1.0
  return popGrowthMultiplier

proc applyGrowthMultiplier*(baseGrowthRate: float32): float32 =
  ## Apply the dynamic multiplier to a base growth rate
  result = baseGrowthRate * getPopulationGrowthMultiplier()
