import ../common/logger
import ./types/config

# Global game configs and setup
var gameConfig* {.threadvar.}: GameConfig
var gameSetup* {.threadvar.}: GameSetup

# Game scaling multipliers (private backing storage)
var prestigeMultiplierImpl {.threadvar.}: float64
var popGrowthMultiplierImpl {.threadvar.}: float64

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

# Population growth multiplier property
proc `popGrowthMultiplier=`*(multiplier: float32) =
  ## Set the population growth multiplier directly for testing
  ## Use 1.0 for standard growth rate in tests
  popGrowthMultiplierImpl = multiplier

proc popGrowthMultiplier*(): float32 =
  ## Get the current population growth multiplier
  ## Returns 1.0 if not initialized (standard growth)
  if popGrowthMultiplierImpl == 0.0:
    logWarn(
      "Economy",
      "Population growth multiplier uninitialized! Using 1.0 (standard growth)",
    )
    return 1.0
  return popGrowthMultiplierImpl

proc applyGrowthMultiplier*(baseGrowthRate: float32): float32 =
  ## Apply the dynamic multiplier to a base growth rate
  result = baseGrowthRate * popGrowthMultiplier()
