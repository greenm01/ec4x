## Basileus Collector - Emperor (House Coordination & Victory) Domain
##
## Tracks house operational status, prestige (current, change, victory progress),
## maintenance costs, autopilot/defensive collapse states, and elimination countdown.
##
## REFACTORED: 2025-12-06 - Extracted from diagnostics.nim
## (lines 458-474 from collectEconomyMetrics + lines 614-629 from collectHouseStatusMetrics)

import std/tables
import ./types
import ../../../engine/gamestate
import ../../../engine/diagnostics_data
import ../../../common/types/core

proc collectBasileusMetrics*(state: GameState, houseId: HouseId,
                             prevMetrics: DiagnosticMetrics,
                             report: TurnResolutionReport): DiagnosticMetrics =
  ## Collect house coordination, victory, and status metrics
  result = initDiagnosticMetrics(state.turn, houseId)

  let house = state.houses.getOrDefault(houseId)

  # ================================================================
  # PRESTIGE & VICTORY
  # ================================================================

  # Current prestige
  result.prestigeCurrent = house.prestige

  # Prestige change from last turn
  result.prestigeChange = house.prestige - prevMetrics.prestigeCurrent

  # Victory progress: count turns at prestige >= 1500
  # Prestige victory requires 3 consecutive turns at >= 1500
  if house.prestige >= 1500:
    result.prestigeVictoryProgress = prevMetrics.prestigeVictoryProgress + 1
  else:
    result.prestigeVictoryProgress = 0

  # ================================================================
  # MAINTENANCE & ECONOMIC OBLIGATIONS
  # ================================================================

  # Track actual maintenance cost from turn resolution
  result.maintenanceCostTotal = report.maintenanceCostTotal
  result.maintenanceShortfallTurns = house.consecutiveShortfallTurns

  # ================================================================
  # HOUSE STATUS (from gameplay.toml thresholds)
  # ================================================================

  # Operational states
  result.autopilotActive = house.status == HouseStatus.Autopilot
  result.defensiveCollapseActive = house.status == HouseStatus.DefensiveCollapse
  result.missedOrderTurns = house.turnsWithoutOrders

  # Elimination countdown (negative prestige penalty)
  if house.prestige < 0:
    result.turnsUntilElimination = 3 - house.negativePrestigeTurns
  else:
    result.turnsUntilElimination = 0
