## @engine/telemetry/collectors/facilities.nim
##
## Collect facilities metrics from GameState.
## Covers: starbases, spaceports, shipyards, drydocks.
import ../../types/[telemetry, core, game_state]
import ../../state/iterators

proc collectFacilitiesMetrics*(
  state: GameState,
  houseId: HouseId,
  prevMetrics: DiagnosticMetrics
): DiagnosticMetrics =
  ## Collect facility counts from GameState
  result = prevMetrics  # Start with previous metrics

  var totalSpaceports: int32 = 0
  var totalShipyards: int32 = 0
  var totalDrydocks: int32 = 0
  var totalStarbases: int32 = 0

  # Count facilities using efficient iterators
  for starbase in state.starbasesOwned(houseId):
    totalStarbases += 1

  for spaceport in state.spaceportsOwned(houseId):
    totalSpaceports += 1

  for shipyard in state.shipyardsOwned(houseId):
    totalShipyards += 1

  for drydock in state.drydocksOwned(houseId):
    totalDrydocks += 1

  result.totalSpaceports = totalSpaceports
  result.totalShipyards = totalShipyards
  result.totalDrydocks = totalDrydocks
  result.starbasesActual = totalStarbases
