## Reconnaissance Order Execution
##
## This module contains the logic for executing 'View World' fleet orders.

import std/[options, tables, strformat]
import ../../../../common/types/[core, units]
import ../../gamestate, ../../fleet, ../../logger, ../../starmap
import ../../index_maintenance
import ../../types/resolution as resolution_types
import ../../events/init as event_factory
import ../../intelligence/generator # For generateColonyIntelReport, generateSystemIntelReport
import ../../intelligence/types as intel_types # For IntelQuality, ColonyIntelReport
import ../main as orders # For FleetOrder and FleetOrderType
import ../utils/order_utils # For completeFleetOrder

proc executeViewWorldOrder*(
  state: var GameState, fleet: Fleet, order: orders.FleetOrder,
  events: var seq[resolution_types.GameEvent]
): OrderOutcome =
  ## Order 20: Perform long-range planetary reconnaissance
  ## Ship approaches system edge, scans planet, retreats to deep space
  ## Gathers: planet owner (if colonized) and planet class (production potential)
  if order.targetSystem.isNone:
    order_utils.completeFleetOrder(
      state, order.fleetId, "ViewWorld",
      details = "failed: no target system specified",
      systemId = some(fleet.location),
      events
    )
    return OrderOutcome.Failed

  let targetId = order.targetSystem.get()
  let houseId = fleet.owner

  # The dispatcher (fleet_order_executor) should ensure the fleet is at the target
  # before calling the execution module. So, if we are here, we assume fleet.location == targetId
  if fleet.location != targetId:
    logError(LogCategory.lcFleet, &"Fleet {order.fleetId} not at target {targetId} during ViewWorld execution. This should be handled by dispatcher.")
    return OrderOutcome.Failed # Should not happen if dispatcher works correctly

  # Fleet is at system - perform long-range scan
  var house = state.houses[houseId]

  # Gather intel on planet
  if targetId in state.colonies:
    let colony = state.colonies[targetId]

    # Create minimal colony intel report from long-range scan
    # ViewWorld only gathers: owner + planet class (no detailed statistics)
    let intelReport = intel_types.ColonyIntelReport(
      colonyId: targetId,
      targetOwner: colony.owner,
      gatheredTurn: state.turn,
      quality: intel_types.IntelQuality.Scan,  # Long-range scan quality
      # Colony stats: minimal info from long-range scan
      population: 0,               # Unknown from long range
      industry: 0,                 # Unknown from long range
      defenses: 0,                 # Unknown from long range
      starbaseLevel: 0,            # Unknown from long range
      constructionQueue: @[],      # Unknown from long range
      # Economic intel: not available from long-range scan
      grossOutput: none(int),
      taxRevenue: none(int),
      # Orbital defenses: not visible from deep space approach
      unassignedSquadronCount: 0,
      reserveFleetCount: 0,
      mothballedFleetCount: 0,
      shipyardCount: 0
    )

    house.intelligence.colonyReports[targetId] = intelReport
    logInfo(LogCategory.lcFleet,
            &"{house.name} viewed world at {targetId}: Owner={colony.owner}, Class={colony.planetClass}")
  else:
    # Uncolonized system - no intel report needed
    # Just log that we found an uncolonized system
    if targetId in state.starMap.systems:
      logInfo(LogCategory.lcFleet,
              &"{house.name} viewed uncolonized system at {targetId}")

  state.houses[houseId] = house

  # Generate event
  events.add(event_factory.intelGathered(
    houseId,
    HouseId("neutral"),  # ViewWorld doesn\'t target a specific house
    targetId,
    "long-range planetary scan"
  ))

  # Generate OrderCompleted event for successful scan
  var scanDetails = if targetId in state.colonies:
    let colony = state.colonies[targetId]
    &"scanned {targetId} (owner: {colony.owner})"
  else:
    &"scanned uncolonized system {targetId}"

  order_utils.completeFleetOrder(
    state, order.fleetId, "ViewWorld",
    details = scanDetails,
    systemId = some(targetId),
    events
  )

  # Order completes - fleet remains at system (player must issue new orders)
  # NOTE: Fleet is in deep space, not orbit, so no orbital combat triggered
  # Cleanup handled by Command Phase

  return OrderOutcome.Success
