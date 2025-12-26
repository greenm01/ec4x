## Dynamic Population Growth Multiplier State
##
## Thread-local storage for current game's population growth multiplier
## This allows population growth calculations to scale based on map size
## without passing the multiplier everywhere

import std/math
import ../../common/logger

var growthMultiplier* {.threadvar.}: float32

proc calculatePopulationGrowthMultiplier*(numSystems: int32, numPlayers: int32): float32 =
  ## Calculate dynamic population growth multiplier based on map size
  ##
  ## Formula:
  ##   systems_per_player = numSystems / numPlayers
  ##   multiplier = sqrt(systems_per_player / baseline_systems_per_player)
  ##
  ## This ensures:
  ## - Small maps (few systems): Normal growth (1.0x)
  ## - Large maps (many systems): Faster growth to support expansion
  ## - Growth scales sublinearly with map size (sqrt prevents excessive scaling)
  ##
  ## Example:
  ##   4 players, 37 systems (9.25 sys/player), baseline 7 sys/player
  ##   multiplier = sqrt(9.25 / 7) = sqrt(1.32) ≈ 1.15 (15% faster growth)

  const baselineSystemsPerPlayer = 7.0 # Standard map density

  # Calculate systems per player
  let systemsPerPlayer = float32(numSystems) / float32(numPlayers)

  # Square root scaling prevents excessive growth on very large maps
  let multiplier = sqrt(systemsPerPlayer / baselineSystemsPerPlayer)

  # Clamp to reasonable bounds (50% to 200% of base growth)
  result = clamp(multiplier, 0.5, 2.0)

proc initializePopulationGrowthMultiplier*(numSystems: int32, numPlayers: int32) =
  ## Initialize the population growth multiplier for the current game
  ## Call this once during game initialization alongside prestige multiplier
  growthMultiplier = calculatePopulationGrowthMultiplier(numSystems, numPlayers)
  logInfo(
    "Economy",
    "Population growth multiplier initialized",
    "multiplier=",
    $growthMultiplier,
    " systems=",
    $numSystems,
    " players=",
    $numPlayers,
  )

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
