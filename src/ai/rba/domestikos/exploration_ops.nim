## Exploration Operations Sub-module
## Handles exploration for Act 1 intelligence gathering
##
## Key Strategy:
## - Send idle/under-utilized fleets to unexplored systems
## - Ensures continuous exploration throughout Act 1
## - Builds intelligence reports by visiting colonies
## - Populates FilteredGameState.visibleColonies for offensive ops in Act 2+

import std/[options, strformat, tables, algorithm]
import ../../../common/types/core
import ../../../engine/[gamestate, fog_of_war, order_types, logger]
import ../../common/types as ai_types  # For GameAct
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

proc generateReconnaissanceOrders*(
  filtered: FilteredGameState,
  analyses: seq[FleetAnalysis],
  controller: AIController,
  currentAct: ai_types.GameAct
): seq[FleetOrder] =
  ## Generate reconnaissance orders for Act 2+ to maintain fresh intelligence
  ## Scouts enemy colonies with stale intel to enable invasion planning
  result = @[]

  # Only scout in Act 2+ (Act 1 uses exploration)
  if currentAct == ai_types.GameAct.Act1_LandGrab:
    return result

  # Find scout-capable fleets (idle/underutilized with scouts or small ships)
  var availableScouts: seq[FleetAnalysis] = @[]
  for analysis in analyses:
    if analysis.utilization in {FleetUtilization.Idle, FleetUtilization.UnderUtilized}:
      # Prefer actual scouts, but any small fleet can scout
      if analysis.hasScouts or analysis.shipCount <= 2:
        availableScouts.add(analysis)

  if availableScouts.len == 0:
    return result

  # Identify enemy colonies needing fresh intel
  type StaleIntelTarget = object
    systemId: SystemId
    owner: HouseId
    turnsSinceUpdate: int
    priority: float

  var staleTargets: seq[StaleIntelTarget] = @[]
  let currentTurn = filtered.turn

  # Check all visible enemy colonies
  for colony in filtered.visibleColonies:
    if colony.owner == controller.houseId:
      continue  # Skip own colonies

    # Check if we have intel on this colony
    let hasIntel = filtered.ownHouse.intelligence.colonyReports.hasKey(colony.systemId)

    if hasIntel:
      let report = filtered.ownHouse.intelligence.colonyReports[colony.systemId]
      let turnsSinceUpdate = currentTurn - report.gatheredTurn

      # Only scout if intel is stale (>5 turns old)
      if turnsSinceUpdate > 5:
        # Priority: more valuable colonies scouted more frequently
        let valuePriority = report.grossOutput.get(0).float + (report.industry * 100).float
        let staleness = turnsSinceUpdate.float / 10.0  # More stale = higher priority

        staleTargets.add(StaleIntelTarget(
          systemId: colony.systemId,
          owner: report.targetOwner,
          turnsSinceUpdate: turnsSinceUpdate,
          priority: valuePriority * staleness
        ))
    else:
      # No intel at all - high priority to scout
      staleTargets.add(StaleIntelTarget(
        systemId: colony.systemId,
        owner: colony.owner,
        turnsSinceUpdate: 999,
        priority: 1000.0  # Very high priority for unknown colonies
      ))

  if staleTargets.len == 0:
    return result

  # Sort by priority (highest first)
  staleTargets.sort(proc(a, b: StaleIntelTarget): int =
    if a.priority > b.priority: -1
    elif a.priority < b.priority: 1
    else: 0
  )

  # Personality-based scout allocation
  let personality = controller.personality
  let scoutingAggression = personality.aggression + personality.expansionDrive
  let maxScouts = case currentAct
    of ai_types.GameAct.Act2_RisingTensions:
      # Act 2: Moderate scouting
      if scoutingAggression > 0.8: min(4, availableScouts.len)
      elif scoutingAggression > 0.5: min(2, availableScouts.len)
      else: min(1, availableScouts.len)
    of ai_types.GameAct.Act3_TotalWar, ai_types.GameAct.Act4_Endgame:
      # Act 3+: Aggressive scouting for invasion targets
      if scoutingAggression > 0.8: min(6, availableScouts.len)
      elif scoutingAggression > 0.5: min(3, availableScouts.len)
      else: min(2, availableScouts.len)
    else:
      1

  # Assign scouts to targets
  let assignmentCount = min(maxScouts, min(availableScouts.len, staleTargets.len))

  for i in 0..<assignmentCount:
    let scout = availableScouts[i]
    let target = staleTargets[i]

    result.add(FleetOrder(
      fleetId: scout.fleetId,
      orderType: FleetOrderType.SpyPlanet,  
      targetSystem: some(target.systemId),
      priority: 75  # Higher than exploration, lower than defense
    ))

    let intelStatus = if target.turnsSinceUpdate == 999: "no intel"
                      else: &"{target.turnsSinceUpdate} turns stale"
    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Domestikos: Reconnaissance - fleet {scout.fleetId} → {target.systemId} " &
            &"({target.owner}, {intelStatus})")

  if result.len > 0:
    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Domestikos: Assigned {result.len} scouts for reconnaissance " &
            &"({staleTargets.len} stale intel targets)")

  return result
