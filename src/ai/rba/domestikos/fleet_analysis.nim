## Fleet Analysis Sub-module
## Handles fleet utilization analysis, threat assessment, and opportunity identification

import std/[options, tables, logging, strformat]
import ../../../common/types/core
import ../../../engine/[gamestate, fog_of_war, fleet, order_types, standing_orders, starmap, squadron]

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

proc isIntelFleet*(fleet: Fleet): bool =
  ## Check if fleet is exclusively Intel squadrons (reserved for Drungarius)
  ##
  ## Returns true if fleet contains ONLY Intel-type squadrons.
  ## Mixed fleets (intel + combat) return false - Domestikos can use them.
  ##
  ## This filter ensures Intel squadrons are managed by Drungarius (Intelligence
  ## Advisor) for reconnaissance missions, not assigned to combat/patrol/merge
  ## operations by Domestikos (Military Advisor).
  if fleet.squadrons.len == 0:
    return false

  for squadron in fleet.squadrons:
    if squadron.squadronType != SquadronType.Intel:
      return false

  return true

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
    # NOTE: Scout fleets are included in analysis but filtered by Domestikos operations
    # via `not analysis.hasScouts` checks. This allows Drungarius to analyze scouts
    # for reconnaissance missions.

    var analysis = FleetAnalysis(
      fleetId: fleet.id,
      shipCount: 0,
      utilization: FleetUtilization.Idle,
      hasScouts: false,
      hasETACs: false,
      hasCombatShips: false,
      location: fleet.location
    )

    # Count ships and categorize by squadron type
    for squadron in fleet.squadrons:
      analysis.shipCount += 1
      case squadron.squadronType
      of SquadronType.Intel:
        analysis.hasScouts = true  # Intel squadrons (scouts)
      of SquadronType.Expansion:
        analysis.hasETACs = true  # Expansion squadrons (ETACs)
      of SquadronType.Combat, SquadronType.Auxiliary:
        analysis.hasCombatShips = true
      of SquadronType.Fighter:
        # Fighters stay at colonies, shouldn't be in fleets
        discard

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
      of StandingOrderType.AutoRepair, StandingOrderType.AutoReinforce,
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
# =============================================================================
# GOAP Fleet Requisitioning
# =============================================================================

proc requestFleetForOperation*(
  analyses: seq[FleetAnalysis],
  targetSystem: SystemId,
  requireCombatShips: bool = true,
  requireMarines: bool = false,
  filtered: FilteredGameState = FilteredGameState()  # Needed for marine check
): Option[FleetAnalysis] =
  ## Request a fleet for GOAP strategic operation
  ##
  ## Respects priority:
  ## 1. Idle fleets (no assignment)
  ## 2. UnderUtilized fleets (low-priority standing orders like Patrol)
  ## 3. None (don't interrupt critical operations)
  ##
  ## Filters:
  ## - Skips ETAC fleets (Eparch domain, CRITICAL priority)
  ## - Skips Intel-only fleets (Drungarius domain)
  ## - Respects requireCombatShips flag
  ## - Respects requireMarines flag (checks for loaded marines on transports)

  var bestFleet: Option[FleetAnalysis] = none(FleetAnalysis)
  var bestScore = 0

  for analysis in analyses:
    # Skip ETAC fleets - Eparch domain, CRITICAL priority in Act 1
    if analysis.hasETACs:
      continue

    # Skip if combat ships required but fleet doesn't have them
    if requireCombatShips and not analysis.hasCombatShips:
      continue

    # CRITICAL: If marines are required, the fleet MUST have loaded marines.
    if requireMarines:
      var hasLoadedMarines = false
      # Look up the actual fleet to check its cargo
      for actualFleet in filtered.ownFleets:
        if actualFleet.id == analysis.fleetId:
          for squadron in actualFleet.squadrons:
            if squadron.squadronType == SquadronType.Auxiliary and
               squadron.flagship.shipClass == ShipClass.TroopTransport and
               squadron.flagship.cargo.isSome:
              let cargo = squadron.flagship.cargo.get()
              if cargo.cargoType == CargoType.Marines and cargo.quantity > 0:
                hasLoadedMarines = true
                break
          if hasLoadedMarines:
            break
      
      if not hasLoadedMarines:
        continue # Skip this fleet, it does not have marines for the invasion.

    # Score fleet based on utilization (higher = more available)
    var score = case analysis.utilization
      of FleetUtilization.Idle: 100  # Best - no assignment
      of FleetUtilization.UnderUtilized: 50  # Good - low-priority standing order
      of FleetUtilization.Optimal: 0  # Don't interrupt
      of FleetUtilization.OverUtilized: 0  # Don't interrupt
      of FleetUtilization.Tactical: 0  # Don't interrupt active operations

    if score > bestScore:
      bestScore = score
      bestFleet = some(analysis)

  return bestFleet
