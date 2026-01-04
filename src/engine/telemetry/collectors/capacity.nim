## @engine/telemetry/collectors/capacity.nim
##
## Collect capacity violation metrics from GameState.
## Covers: squadron limits, fighter capacity, grace periods.

import std/[math, options]
import ../../types/[telemetry, core, game_state, colony, house, capacity, ship]
import ../../globals
import ../../state/[engine, iterators]

proc collectCapacityMetrics*(
    state: GameState, houseId: HouseId, prevMetrics: DiagnosticMetrics
): DiagnosticMetrics =
  ## Collect capacity metrics from GameState
  result = prevMetrics # Start with previous metrics

  let houseOpt = state.house(houseId)
  if houseOpt.isNone:
    return result # House not found
  let house = houseOpt.get()

  # ================================================================
  # FIGHTER CAPACITY
  # ================================================================

  # Fighter Doctrine multiplier (FD tech level)
  let fdMultiplier: float32 =
    case house.techTree.levels.fd
    of 1: 1.0
    of 2: 1.5
    of 3: 2.0
    else: 1.0

  # Calculate fighter capacity and violations
  let fighterIUDivisor: int32 = gameConfig.limits.fighterCapacity.iuDivisor
  var totalFighterCapacity: int32 = 0
  var totalFighters: int32 = 0
  var capacityViolationCount: int32 = 0

  for colony in state.coloniesOwned(houseId):
    let colonyCapacity = int32(
      floor(float32(colony.industrial.units) / float32(fighterIUDivisor)) * fdMultiplier
    )
    totalFighterCapacity += colonyCapacity
    totalFighters += colony.fighterIds.len.int32
    if colony.capacityViolation.severity != ViolationSeverity.None:
      capacityViolationCount += 1

  result.fighterCapacityMax = totalFighterCapacity
  result.fighterCapacityUsed = totalFighters
  result.fighterCapacityViolation = totalFighters > totalFighterCapacity
  result.capacityViolationsActive = capacityViolationCount

  # ================================================================
  # SQUADRON LIMIT (DEPRECATED - replaced by FC/SC limits)
  # ================================================================
  # NOTE: This section is deprecated and reports placeholder values.
  # The squadron abstraction has been removed in favor of direct fleet-to-ship relationships.
  # Capacity is now enforced via Fleet Command (FC) and Strategic Command (SC) tech limits.

  # Report placeholder values to maintain telemetry compatibility
  result.squadronLimitMax = 0
  result.squadronLimitUsed = 0
  result.squadronLimitViolation = false
