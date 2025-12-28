## Dynamic Multiplier Initialization
##
## Calculates dynamic prestige and population growth multipliers based on
## map size and player count for balanced game pacing.

import std/math
import ../../common/logger
import ../globals
import ../prestige/engine  # For prestigeMultiplier property

proc initPrestigeMultiplier*(numSystems: int32, numPlayers: int32) =
  ## Calculate dynamic prestige multiplier based on map size and player count
  ##
  ## Formula:
  ##   systems_per_player = numSystems / numPlayers
  ##   target_turns = baseline_turns + (systems_per_player - baseline_ratio) * turn_scaling_factor
  ##   multiplier = base_multiplier * (baseline_turns / target_turns)
  ##   multiplier = clamp(multiplier, min_multiplier, max_multiplier)
  ##
  ## This ensures:
  ## - Small maps (few systems per player): Higher multiplier = faster games
  ## - Large maps (many systems per player): Lower multiplier = longer games
  ## - Victory threshold (5000 prestige) stays constant regardless of map size

  let config = gameConfig.prestige.dynamicScaling

  # If dynamic scaling is disabled, use base multiplier
  if not config.enabled:
    `prestigeMultiplier=`(config.baseMultiplier)
    return

  # Calculate systems per player
  let systemsPerPlayer = float32(numSystems) / float32(numPlayers)

  # Calculate target turns based on map density
  let systemDiff = systemsPerPlayer - float32(config.baselineSystemsPerPlayer)
  let targetTurns =
    float32(config.baselineTurns) + (systemDiff * config.turnScalingFactor)

  # Calculate multiplier (inverse relationship: more turns = lower multiplier)
  let multiplier =
    config.baseMultiplier * (float32(config.baselineTurns) / targetTurns)

  # Clamp to reasonable bounds
  `prestigeMultiplier=`(max(config.minMultiplier, min(config.maxMultiplier, multiplier)))

  logInfo(
    "Prestige",
    "Dynamic multiplier initialized",
    "multiplier=",
    $prestigeMultiplier(),
    " systems=",
    $numSystems,
    " players=",
    $numPlayers,
  )

proc initPopulationGrowthMultiplier*(numSystems: int32, numPlayers: int32) =
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
  `popGrowthMultiplier=`(clamp(multiplier, 0.5, 2.0))

  logInfo(
    "Economy",
    "Population growth multiplier initialized",
    "multiplier=",
    $popGrowthMultiplier(),
    " systems=",
    $numSystems,
    " players=",
    $numPlayers,
  )
