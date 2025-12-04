## Exploration Operations Sub-module
## Handles exploration for Act 1 intelligence gathering
##
## Key Strategy:
## - Send idle/under-utilized fleets to unexplored systems
## - Ensures continuous exploration throughout Act 1
## - Builds intelligence reports by visiting colonies
## - Populates FilteredGameState.visibleColonies for offensive ops in Act 2+

import std/[options, strformat, tables]
import ../../../common/types/core
import ../../../engine/[gamestate, fog_of_war, order_types, logger]
import ../controller_types
import ./fleet_analysis  # For FleetAnalysis, FleetUtilization types

proc generateExplorationOrders*(
  filtered: FilteredGameState,
  analyses: seq[FleetAnalysis],
  controller: AIController
): seq[FleetOrder] =
  ## Generate exploration orders for Act 1
  ## Sends idle fleets to adjacent unscouted systems
  result = @[]

  # Find unexplored systems (Adjacent visibility = known but not scouted)
  var unexploredSystems: seq[SystemId] = @[]
  for systemId, visibleSys in filtered.visibleSystems:
    if visibleSys.visibility == VisibilityLevel.Adjacent:
      unexploredSystems.add(systemId)

  if unexploredSystems.len == 0:
    # No unexplored systems visible - nothing to do
    return result

  # Find idle or under-utilized fleets suitable for exploration
  var availableExplorers: seq[FleetAnalysis] = @[]
  for analysis in analyses:
    if analysis.utilization in {FleetUtilization.Idle, FleetUtilization.UnderUtilized}:
      availableExplorers.add(analysis)

  if availableExplorers.len == 0:
    # No available fleets - nothing to do
    return result

  # Assign explorers to unexplored systems (round-robin)
  let assignmentCount = min(availableExplorers.len, unexploredSystems.len)

  for i in 0..<assignmentCount:
    let explorer = availableExplorers[i]
    let target = unexploredSystems[i]

    result.add(FleetOrder(
      fleetId: explorer.fleetId,
      orderType: FleetOrderType.Move,
      targetSystem: some(target),
      priority: 70  # Higher than logistics, lower than defense
    ))

    logDebug(LogCategory.lcAI,
             &"{controller.houseId} Domestikos: Exploration - fleet {explorer.fleetId} → system {target}")

  if result.len > 0:
    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Domestikos: Assigned {result.len} fleets to exploration " &
            &"({unexploredSystems.len} unexplored systems)")

  return result
