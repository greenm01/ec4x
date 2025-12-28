import ../common/logger
import ./types/config

# Global game configs and setup
var gameConfig* {.threadvar.}: GameConfig
var gameSetup* {.threadvar.}: GameSetup

# Population growth multiplier (private backing storage)
var popGrowthMultiplierImpl {.threadvar.}: float64

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
