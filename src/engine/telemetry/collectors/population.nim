## @engine/telemetry/collectors/population.nim
##
## Collect population metrics from GameState.
## Covers: population units (PU), population transfer units (PTU), transfers.

import std/options
import ../../types/[telemetry, core, game_state, event, colony, population]
import ../../state/interators

proc collectPopulationMetrics*(
  state: GameState,
  houseId: HouseId,
  prevMetrics: DiagnosticMetrics
): DiagnosticMetrics =
  ## Collect population metrics from GameState
  result = prevMetrics  # Start with previous metrics

  # Query GameState for population totals
  var totalPU: int32 = 0
  var totalPTU: int32 = 0
  var blockadedCount: int32 = 0
  var blockadeTurns: int32 = 0

  for colony in state.coloniesOwned(houseId):
    totalPU += colony.populationUnits
    totalPTU += colony.populationTransferUnits

    # Blockade tracking
    if colony.blockaded:
      blockadedCount += 1
      blockadeTurns += colony.blockadeTurns

  result.totalPopulationUnits = totalPU
  result.totalPopulationPTU = totalPTU
  result.coloniesBlockadedCount = blockadedCount
  result.blockadeTurnsCumulative = blockadeTurns

  # Population transfers in transit
  var thisHouseTransfers: int32 = 0
  for transfer in state.populationInTransit:
    if transfer.houseId == houseId:
      thisHouseTransfers += 1
  result.populationTransfersActive = thisHouseTransfers

  # Track from events
  var popTransfersCompleted: int32 = 0
  var popTransfersLost: int32 = 0
  var ptuTransferredTotal: int32 = 0

  for event in state.lastTurnEvents:
    if event.houseId != some(houseId): continue
    # TODO: Add PopulationTransferCompleted, PopulationTransferLost events
    # case event.eventType:
    # of PopulationTransferCompleted:
    #   popTransfersCompleted += 1
    # of PopulationTransferLost:
    #   popTransfersLost += 1
    # else:
    #   discard

  result.populationTransfersCompleted = popTransfersCompleted
  result.populationTransfersLost = popTransfersLost
  result.ptuTransferredTotal = prevMetrics.ptuTransferredTotal +
    ptuTransferredTotal
