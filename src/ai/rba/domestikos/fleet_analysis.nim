## Fleet Analysis Sub-module
## Handles fleet utilization analysis, threat assessment, and opportunity identification

import std/[options, tables]
import ../../../common/types/core
import ../../../engine/[gamestate, fog_of_war, fleet, order_types, standing_orders, starmap]

# Fleet analysis types (also defined in parent domestikos.nim)
type
  FleetUtilization* {.pure.} = enum
    Idle, UnderUtilized, Optimal, OverUtilized, Tactical

  FleetAnalysis* = object
    fleetId*: FleetId
    shipCount*: int
    utilization*: FleetUtilization
    hasScouts*: bool
    hasETACs*: bool
    hasCombatShips*: bool
    location*: SystemId

proc analyzeFleetUtilization*(
  filtered: FilteredGameState,
  houseId: HouseId,
  tacticalOrders: Table[FleetId, FleetOrder],
  standingOrders: Table[FleetId, StandingOrder]
): seq[FleetAnalysis] =
  ## Analyze each fleet's current utilization and composition
  ## Determines if fleets are idle, under-utilized, optimal, or over-utilized
  result = @[]

  for fleet in filtered.ownFleets:
    var analysis = FleetAnalysis(
      fleetId: fleet.id,
      shipCount: 0,
      utilization: FleetUtilization.Idle,
      hasScouts: false,
      hasETACs: false,
      hasCombatShips: false,
      location: fleet.location
    )

    # Count ships and categorize
    for squadron in fleet.squadrons:
      analysis.shipCount += 1
      case squadron.flagship.shipClass
      of ShipClass.Scout:
        analysis.hasScouts = true
      of ShipClass.ETAC:
        analysis.hasETACs = true
      else:
        analysis.hasCombatShips = true

    # Determine utilization based on orders
    # CRITICAL: Check persistent active orders FIRST (from previous turns)
    # ETAC fleets with any active orders should not be reassigned by Domestikos
    if fleet.id in filtered.ownFleetOrders:
      let activeOrder = filtered.ownFleetOrders[fleet.id]
      # ETAC fleets with Move orders (reload) or Colonize orders are tactical
      if analysis.hasETACs and activeOrder.orderType in {FleetOrderType.Move, FleetOrderType.Colonize}:
        analysis.utilization = FleetUtilization.Tactical
      else:
        # Other fleets with active orders also considered tactical
        analysis.utilization = FleetUtilization.Tactical
    elif fleet.id in tacticalOrders:
      # Fleet has NEW tactical order (this turn) - considered tactical (don't touch)
      analysis.utilization = FleetUtilization.Tactical
    elif fleet.id in standingOrders:
      let standingOrder = standingOrders[fleet.id]
      case standingOrder.orderType
      of StandingOrderType.DefendSystem, StandingOrderType.GuardColony:
        # Defending - analyze if appropriately sized
        if analysis.shipCount == 1:
          analysis.utilization = FleetUtilization.UnderUtilized
        elif analysis.shipCount <= 3:
          analysis.utilization = FleetUtilization.Optimal
        else:
          analysis.utilization = FleetUtilization.OverUtilized
      of StandingOrderType.PatrolRoute:
        # Patrolling - typically optimal
        analysis.utilization = FleetUtilization.Optimal
      of StandingOrderType.AutoRepair, StandingOrderType.AutoEvade,
         StandingOrderType.AutoColonize, StandingOrderType.AutoReinforce,
         StandingOrderType.BlockadeTarget:
        # Special orders - don't touch
        analysis.utilization = FleetUtilization.Tactical
      of StandingOrderType.None:
        # No standing order - idle
        analysis.utilization = FleetUtilization.Idle
    else:
      # No orders - idle
      analysis.utilization = FleetUtilization.Idle

    result.add(analysis)

  return result

proc findNearestColonyForDefense*(
  fleet: Fleet,
  undefendedColonies: seq[Colony],
  filtered: FilteredGameState
): Option[SystemId] =
  ## Find the nearest undefended colony to this fleet
  ## Returns None if no undefended colonies exist
  if undefendedColonies.len == 0:
    return none(SystemId)

  # Find nearest colony by jump distance
  var bestColony: Option[Colony] = none(Colony)
  var bestDistance = int.high

  for colony in undefendedColonies:
    let pathResult = filtered.starMap.findPath(fleet.location, colony.systemId, fleet)
    if pathResult.found:
      let distance = pathResult.path.len
      if distance < bestDistance:
        bestDistance = distance
        bestColony = some(colony)

  if bestColony.isSome:
    return some(bestColony.get().systemId)
  else:
    return none(SystemId)
