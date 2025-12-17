## Scout Deployment Orders Module
##
## Part of Drungarius (Intelligence Advisor) - manages scout deployment to
## reconnaissance missions based on intelligence priorities.
##
## Follows Eparch/ETAC pattern: Intelligence advisor owns scout pipeline
## (identify needs → build scouts → deploy scouts)

import std/[strformat, options, sequtils, algorithm, tables]
import ../../../../common/types/[core, units]
import ../../../../engine/[gamestate, fog_of_war, order_types, fleet, logger]
import ../../../common/types as ai_common_types
import ../../[controller_types, config]
import ../../shared/intelligence_types
import ../../domestikos/fleet_analysis

proc generateScoutOrders*(
  filtered: FilteredGameState,
  controller: AIController,
  intelSnapshot: IntelligenceSnapshot
): seq[FleetOrder] =
  ## Generate reconnaissance orders for available scout fleets
  ##
  ## Assigns idle scout fleets to high-priority intelligence targets identified
  ## by Drungarius intelligence analysis. Uses intelligence snapshot directly
  ## for targeting (SpyPlanet, ViewWorld, HackStarbase missions).
  ##
  ## Scout fleet optimization:
  ## - Mesh network bonuses: 2-3 scouts = +1 ELI, 4-5 = +2, 6+ = +3 ELI
  ## - Optimal fleet size: 3-6 scouts per mission (caps at +3 bonus)
  ##
  ## Returns fleet orders for reconnaissance missions
  result = @[]

  # Analyze all fleets to find idle scouts
  let allAnalyses = analyzeFleetUtilization(
    filtered,
    controller.houseId,
    initTable[FleetId, FleetOrder](),  # No tactical orders for Drungarius context
    controller.standingOrders
  )

  # Find idle scout fleets (pure scout composition only)
  var availableScouts: seq[FleetAnalysis] = @[]
  for analysis in allAnalyses:
    # Only idle fleets with scouts
    if analysis.utilization == FleetUtilization.Idle and analysis.hasScouts and
       not analysis.hasCombatShips:
      availableScouts.add(analysis)

  if availableScouts.len == 0:
    logDebug(LogCategory.lcAI,
             &"{controller.houseId} Drungarius: No idle scout fleets available " &
             &"(analyzed {allAnalyses.len} fleets)")
    return result

  # Use Drungarius reconnaissance recommendations
  var intelTargets: seq[
    tuple[systemId: SystemId, orderType: FleetOrderType, priority: int]
  ] = @[]

  for espTarget in intelSnapshot.espionage.highPriorityTargets:
    # Map EspionageTarget to FleetOrder type
    let orderType = case espTarget.targetType
      of EspionageTargetType.ColonySpy: FleetOrderType.SpyPlanet
      of EspionageTargetType.ScoutRecon: FleetOrderType.ViewWorld
      of EspionageTargetType.StarbaseHack: FleetOrderType.HackStarbase
      else: continue  # Skip non-reconnaissance target types

    # Map priority to numeric value from config
    let numericPriority = case espTarget.priority
      of RequirementPriority.Critical:
        100  # Above all other priorities
      of RequirementPriority.High:
        controller.rbaConfig.drungarius_reconnaissance.priority_spy_planet
      of RequirementPriority.Medium:
        controller.rbaConfig.drungarius_reconnaissance.priority_spy_system
      of RequirementPriority.Low:
        controller.rbaConfig.drungarius_reconnaissance.priority_view_world
      else:
        50  # Deferred

    if espTarget.systemId.isSome:
      intelTargets.add((
        systemId: espTarget.systemId.get(),
        orderType: orderType,
        priority: numericPriority
      ))

  if intelTargets.len == 0:
    logDebug(LogCategory.lcAI,
             &"{controller.houseId} Drungarius: No reconnaissance targets " &
             &"identified (highPriorityTargets={intelSnapshot.espionage.highPriorityTargets.len})")
    return result

  # Sort scouts by size (largest first) for optimal mesh network bonuses
  # Optimal: 3-6 scouts per mission (caps at +3 ELI bonus)
  availableScouts.sort(proc(a, b: FleetAnalysis): int =
    return b.shipCount - a.shipCount
  )

  # Assign scouts to intel targets
  for target in intelTargets:
    if availableScouts.len == 0:
      break

    let scout = availableScouts[0]
    availableScouts.delete(0)

    result.add(FleetOrder(
      fleetId: scout.fleetId,
      orderType: target.orderType,
      targetSystem: some(target.systemId),
      priority: target.priority,
      roe: some(4)  # Cautious: Gather intel and retreat if threatened
    ))

    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Drungarius: Scout mission - " &
            &"fleet {scout.fleetId} ({scout.shipCount} scouts) → " &
            &"system {target.systemId} ({target.orderType})")

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Drungarius: Reconnaissance deployment - " &
          &"{result.len} scout orders generated from " &
          &"{intelTargets.len} intelligence targets")
