## @engine/telemetry/orchestrator.nim
##
## Public API for telemetry system. Orchestrates collection from all domain
## collectors using event-driven architecture.

import ../types/[telemetry, core, game_state]
import ./collectors/[
  combat, military, fleet, facilities, colony, production, capacity,
  population, income, tech, espionage, diplomacy, house
]

proc initDiagnosticMetrics*(
  turn: int,
  houseId: HouseId,
  strategy: string = "",
  gameId: string = ""
): DiagnosticMetrics =
  ## Initialize empty DiagnosticMetrics for a house at a given turn
  result.gameId = gameId
  result.turn = turn
  result.houseId = houseId
  result.strategy = strategy
  # All fields default to 0/false/empty as defined in types/telemetry.nim

proc collectDiagnostics*(
  state: GameState,
  houseId: HouseId,
  strategy: string = "",
  gameId: string = "",
  act: int32 = 0,
  rank: int32 = 0
): DiagnosticMetrics =
  ## Collect comprehensive diagnostics for a house using all domain collectors.
  ##
  ## This is the main entry point for telemetry collection. It orchestrates
  ## all 13 domain-specific collectors in sequence.
  ##
  ## Pure event-driven architecture:
  ## - Processes events from state.lastTurnEvents
  ## - Queries GameState for snapshot metrics (counts, totals)
  ## - No TurnResolutionReport dependency
  ##
  ## Args:
  ##   state: Current game state with lastTurnEvents populated
  ##   houseId: House to collect metrics for
  ##   strategy: AI strategy name (optional)
  ##   gameId: Game identifier (optional)
  ##   act: Current act/chapter (optional)
  ##   rank: House rank/position (optional)
  ##
  ## Returns:
  ##   Complete DiagnosticMetrics for the house

  # Initialize metrics with metadata
  var metrics = initDiagnosticMetrics(state.turn, houseId, strategy, gameId)
  metrics.act = act
  metrics.rank = rank

  # Collect from each domain collector in sequence
  # Each collector processes events and queries GameState
  metrics = collectCombatMetrics(state, houseId, metrics)
  metrics = collectMilitaryMetrics(state, houseId, metrics)
  metrics = collectFleetMetrics(state, houseId, metrics)
  metrics = collectFacilitiesMetrics(state, houseId, metrics)
  metrics = collectColonyMetrics(state, houseId, metrics)
  metrics = collectProductionMetrics(state, houseId, metrics)
  metrics = collectCapacityMetrics(state, houseId, metrics)
  metrics = collectPopulationMetrics(state, houseId, metrics)
  metrics = collectIncomeMetrics(state, houseId, metrics)
  metrics = collectTechMetrics(state, houseId, metrics)
  metrics = collectEspionageMetrics(state, houseId, metrics)
  metrics = collectDiplomacyMetrics(state, houseId, metrics)
  metrics = collectHouseMetrics(state, houseId, metrics)

  return metrics
