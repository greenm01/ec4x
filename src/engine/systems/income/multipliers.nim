## Economic Multipliers - Runtime Scaling for Gameplay Tuning
##
## Provides runtime multipliers for economic systems to accelerate or decelerate
## gameplay during testing and balance iteration.
##
## Pattern: Matches prestige/engine.nim multiplier design
## - Private threadvar backing storage
## - Property accessors for get/set
## - Apply functions for convenience

import ../../../common/logger

# ============================================================================
# POPULATION GROWTH MULTIPLIER
# ============================================================================

# Private backing storage
var popGrowthMultiplierImpl {.threadvar.}: float64

proc `popGrowthMultiplier=`*(multiplier: float32) =
  ## Set the population growth multiplier directly for testing
  ## Use 1.0 for standard growth rate in tests
  ## Use >1.0 to accelerate population growth (e.g., 2.0 = double speed)
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
  ## Example: baseGrowthRate=0.015, multiplier=2.0 -> result=0.030
  result = baseGrowthRate * popGrowthMultiplier()

# ============================================================================
# FUTURE MULTIPLIERS (Placeholder for expansion)
# ============================================================================
#
# Potential additions for gameplay acceleration:
#
# - productionMultiplier: Scale PP generation (test large fleets quickly)
# - researchMultiplier: Scale tech progression (test high-tech gameplay)
# - economicMultiplier: Scale all economic output (general speedup)
# - constructionMultiplier: Scale build times (fast iteration on fleet comp)
#
# Example usage pattern (same as popGrowthMultiplier above):
#
# var productionMultiplierImpl {.threadvar.}: float64
# proc `productionMultiplier=`*(multiplier: float32)
# proc productionMultiplier*(): float32
# proc applyProductionMultiplier*(basePP: int32): int32
