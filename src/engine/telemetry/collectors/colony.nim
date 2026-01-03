## @engine/telemetry/collectors/colony.nim
##
## Collect colony metrics from events and GameState.
## Covers: colony counts, colonies gained/lost, colonization events.

import std/options
import ../../types/[telemetry, core, game_state, event, colony, ground_unit]
import ../../state/[iterators, engine]

proc collectColonyMetrics*(
    state: GameState, houseId: HouseId, prevMetrics: DiagnosticMetrics
): DiagnosticMetrics =
  ## Collect colony metrics from events and GameState
  result = prevMetrics # Start with previous metrics

  # Initialize counters for this turn
  var coloniesGained: int32 = 0
  var coloniesGainedViaColonization: int32 = 0
  var coloniesGainedViaConquest: int32 = 0
  var coloniesLost: int32 = 0

  # Process events from state.lastTurnEvents
  for event in state.lastTurnEvents:
    case event.eventType
    of ColonyEstablished:
      if event.houseId == some(houseId):
        coloniesGained += 1
        coloniesGainedViaColonization += 1
    of ColonyCaptured:
      if event.newOwner == some(houseId):
        coloniesGained += 1
        coloniesGainedViaConquest += 1
      if event.oldOwner == some(houseId):
        coloniesLost += 1
    # TODO: Add ColonyAbandoned event
    else:
      discard

  # Query GameState for current totals
  var totalColonies: int32 = 0
  var undefendedColonies: int32 = 0

  for colony in state.coloniesOwned(houseId):
    totalColonies += 1

    # Check if colony has ground defense
    # NOTE: Planetary shields don't count (passive only)
    # NOTE: Starbases and fleets are orbital defense, not ground defense
    var hasGroundDefense = false
    for unitId in colony.groundUnitIds:
      let unitOpt = state.groundUnit(unitId)
      if unitOpt.isSome:
        let unit = unitOpt.get()
        # Count Army, Marine, GroundBattery (but NOT PlanetaryShield)
        if unit.stats.unitType in [
          GroundClass.Army, GroundClass.Marine, GroundClass.GroundBattery
        ]:
          hasGroundDefense = true
          break

    if not hasGroundDefense:
      undefendedColonies += 1

  result.coloniesGained = coloniesGained
  result.coloniesGainedViaColonization = coloniesGainedViaColonization
  result.coloniesGainedViaConquest = coloniesGainedViaConquest
  result.coloniesLost = coloniesLost
  result.totalColonies = totalColonies
  result.coloniesWithoutDefense = undefendedColonies
