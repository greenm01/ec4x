import ./types/config

# Global game config
let gConfig* {.threadvar.}: GameConfig = loadGameConfig()

var prestigeMultiplier* {.threadvar.}: float64
var popGrowthMultiplier* {.threadvar.}: float64

proc setPrestigeMultiplier*(multiplier: float32) =
  ## Set the prestige multiplier directly for testing
  ## Use 1.0 to disable multiplier effects in tests
  prestigeMultiplier = multiplier

proc getPrestigeMultiplier*(): float32 =
  ## Get the current prestige multiplier
  ## Returns the base multiplier if not initialized
  if prestigeMultiplier == 0.0:
    logError(
      "Prestige",
      "Multiplier uninitialized! Using base value",
      "base=",
      $globalPrestigeConfig.dynamic_scaling.base_multiplier,
    )
    return gameConfig.prestige.dynamicScaling.baseMultiplier
  return prestigeMultiplier

proc applyPrestigeMultiplier*(baseValue: int32): int32 =
  ## Apply the dynamic multiplier to a base prestige value
  result = int32(float32(baseValue) * getPrestigeMultiplier())
