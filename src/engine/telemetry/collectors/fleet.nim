## @engine/telemetry/collectors/fleet.nim
##
## Collect fleet operations metrics from events and GameState.
## Covers: fleet movement, orders, ETAC colonization activity.

import std/options
import ../../types/[telemetry, core, game_state, event, squadron]
import ../../state/interators

proc collectFleetMetrics*(
  state: GameState,
  houseId: HouseId,
  prevMetrics: DiagnosticMetrics
): DiagnosticMetrics =
  ## Collect fleet activity metrics from events and GameState
  result = prevMetrics  # Start with previous metrics

  # Initialize counters for this turn
  var fleetsMoved: int32 = 0
  var systemsColonized: int32 = 0
  var failedColonizationAttempts: int32 = 0
  var fleetsWithOrders: int32 = 0
  var stuckFleets: int32 = 0

  # Process events from state.lastTurnEvents
  for event in state.lastTurnEvents:
    if event.houseId != some(houseId): continue

    case event.eventType:
    of FleetArrived:
      fleetsMoved += 1
    of ColonyEstablished:
      systemsColonized += 1
    # TODO: Add events for failed colonization and stuck fleets
    # These may need to be added to the event system
    else:
      discard

  # Assign to result
  result.fleetsMoved = fleetsMoved
  result.systemsColonized = systemsColonized
  result.failedColonizationAttempts = failedColonizationAttempts
  result.fleetsWithOrders = fleetsWithOrders
  result.stuckFleets = stuckFleets

  # ETAC specific tracking
  var totalETACs: int32 = 0
  var etacsWithoutOrders: int32 = 0
  var etacsInTransit: int32 = 0

  # Count ETACs from squadrons
  for squadron in state.squadronsOwned(houseId):
    if not squadron.destroyed:
      if squadron.flagship.shipClass == ShipClass.ETAC:
        totalETACs += 1
        # TODO: Check if ETAC has orders or is in transit
        # This requires checking fleet orders and fleet status

  result.totalETACs = totalETACs
  result.etacsWithoutOrders = etacsWithoutOrders
  result.etacsInTransit = etacsInTransit
