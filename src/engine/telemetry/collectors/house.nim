## @engine/telemetry/collectors/house.nim
##
## Collect house status metrics from GameState.
## Covers: prestige, victory progress, autopilot status, house metadata.

import std/options
import ../../types/[telemetry, core, game_state, event, house, prestige, progression]

proc collectHouseMetrics*(
  state: GameState,
  houseId: HouseId,
  prevMetrics: DiagnosticMetrics
): DiagnosticMetrics =
  ## Collect house status metrics from GameState
  result = prevMetrics  # Start with previous metrics

  let house = state.houses.entities.getOrDefault(houseId)

  # ================================================================
  # PRESTIGE & VICTORY
  # ================================================================

  result.prestigeCurrent = house.prestige

  # Prestige change from last turn
  result.prestigeChange = result.prestigeCurrent - prevMetrics.prestigeCurrent

  # Victory progress: count turns at prestige >= 1500
  # Prestige victory requires 3 consecutive turns at >= 1500
  if result.prestigeCurrent >= 1500:
    result.prestigeVictoryProgress = prevMetrics.prestigeVictoryProgress + 1
  else:
    result.prestigeVictoryProgress = 0

  # Track prestige changes from events
  var prestigeGained: int32 = 0
  var prestigeLost: int32 = 0

  for event in state.lastTurnEvents:
    if event.houseId != some(houseId): continue

    case event.eventType:
    of PrestigeGained:
      # TODO: Extract amount from event details
      prestigeGained += 1
    of PrestigeLost:
      # TODO: Extract amount from event details
      prestigeLost += 1
    else:
      discard

  # ================================================================
  # MAINTENANCE & ECONOMIC OBLIGATIONS
  # ================================================================

  # TODO: Track maintenance from events when maintenance system emits them
  result.maintenanceCostTotal = prevMetrics.maintenanceCostTotal
  result.maintenanceShortfallTurns = house.consecutiveShortfallTurns

  # ================================================================
  # HOUSE STATUS (from gameplay.toml thresholds)
  # ================================================================

  result.autopilotActive = house.status == HouseStatus.Autopilot
  result.defensiveCollapseActive = house.status == HouseStatus.DefensiveCollapse
  result.missedOrderTurns = house.turnsWithoutOrders

  # Elimination countdown (negative prestige penalty)
  if result.prestigeCurrent < 0:
    result.turnsUntilElimination = max(0, 3 - house.negativePrestigeTurns)
  else:
    result.turnsUntilElimination = 0
