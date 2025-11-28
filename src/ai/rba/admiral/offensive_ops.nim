## Offensive Operations Sub-module
## Handles fleet merging, probing attacks, and counter-attacks
##
## Key Strategies:
## - Fleet merging: Consolidate idle single-ship fleets in Act 2+ for combat effectiveness
## - Probing attacks: Scout enemy defenses with expendable scouts
## - Counter-attacks: Exploit enemy vulnerabilities (weak/absent defenses)

import std/[options, sequtils, tables, strformat, sets]
import ../../../common/system
import ../../../common/types/[core, diplomacy]
import ../../../engine/[gamestate, fog_of_war, fleet, order_types, logger]
import ../controller_types
import ../config
import ./staging

# Import types from parent module
{.push used.}
from ../admiral import FleetUtilization, FleetAnalysis
{.pop.}

proc generateMergeOrders*(
  filtered: FilteredGameState,
  analyses: seq[FleetAnalysis],
  controller: var AIController,
  stagingArea: SystemId
): seq[FleetOrder] =
  ## Generate fleet merge orders for Act 2+
  ## Consolidates idle single-ship fleets at staging area for combined operations
  result = @[]

  # Find idle fleets suitable for merging
  var idleScouts: seq[FleetAnalysis] = @[]
  var idleCombatFleets: seq[FleetAnalysis] = @[]

  for analysis in analyses:
    if analysis.utilization == FleetUtilization.Idle:
      # Small idle fleets are candidates for merging
      if analysis.shipCount <= 2:
        if analysis.hasScouts and not analysis.hasCombatShips:
          idleScouts.add(analysis)
        elif analysis.hasCombatShips:
          idleCombatFleets.add(analysis)

  # Need at least 3 fleets to make merging worthwhile
  let mergeThreshold = globalRBAConfig.admiral.merge_threshold_act2

  # Merge idle scouts
  if idleScouts.len >= mergeThreshold:
    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Admiral: Merging {idleScouts.len} idle scout fleets to {stagingArea}")

    for analysis in idleScouts:
      result.add(FleetOrder(
        fleetId: analysis.fleetId,
        orderType: FleetOrderType.Move,
        targetSystem: some(stagingArea),
        priority: 80  # Lower than tactical, higher than standing orders
      ))

  # Merge idle combat fleets
  if idleCombatFleets.len >= mergeThreshold:
    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Admiral: Merging {idleCombatFleets.len} idle combat fleets to {stagingArea}")

    for analysis in idleCombatFleets:
      result.add(FleetOrder(
        fleetId: analysis.fleetId,
        orderType: FleetOrderType.Move,
        targetSystem: some(stagingArea),
        priority: 80
      ))

  return result

proc generateProbingOrders*(
  filtered: FilteredGameState,
  analyses: seq[FleetAnalysis],
  controller: AIController
): seq[FleetOrder] =
  ## Generate probing attack orders
  ## Sends scouts to enemy systems to gather intelligence on defenses
  result = @[]

  # Find idle scouts
  var availableScouts: seq[FleetAnalysis] = @[]
  for analysis in analyses:
    if analysis.utilization == FleetUtilization.Idle and analysis.hasScouts:
      availableScouts.add(analysis)

  if availableScouts.len == 0:
    return result

  # Find enemy colonies to probe (from intelligence reports)
  var probingTargets: seq[SystemId] = @[]

  # Check for known enemy colonies from own house intelligence
  for systemId, colonyReport in filtered.ownHouse.intelligence.colonyReports:
    if colonyReport.targetOwner == controller.houseId:
      continue  # Skip own colonies

    # Add all non-self colonies as potential probing targets
    # TODO: Filter by diplomatic stance when diplomacy fully implemented
    probingTargets.add(systemId)

  if probingTargets.len == 0:
    return result

  # Assign scouts to probe targets (max 1 scout per target)
  let maxProbes = min(availableScouts.len, probingTargets.len)

  for i in 0..<maxProbes:
    let scout = availableScouts[i]
    let target = probingTargets[i]

    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Admiral: Probing attack - fleet {scout.fleetId} → system {target}")

    result.add(FleetOrder(
      fleetId: scout.fleetId,
      orderType: FleetOrderType.Move,
      targetSystem: some(target),
      priority: 85  # Higher than merge, lower than tactical
    ))

  return result

proc generateCounterAttackOrders*(
  filtered: FilteredGameState,
  analyses: seq[FleetAnalysis],
  controller: AIController
): seq[FleetOrder] =
  ## Generate counter-attack orders against vulnerable enemy targets
  ## Targets: enemy colonies with weak/no visible defenses
  result = @[]

  # Find available combat fleets (idle or under-utilized)
  var availableAttackers: seq[FleetAnalysis] = @[]
  for analysis in analyses:
    if analysis.utilization in {FleetUtilization.Idle, FleetUtilization.UnderUtilized}:
      if analysis.hasCombatShips and analysis.shipCount >= 2:
        # Need at least 2 ships for counter-attack
        availableAttackers.add(analysis)

  if availableAttackers.len == 0:
    return result

  # Find vulnerable enemy colonies
  type VulnerableTarget = object
    systemId: SystemId
    enemyHouse: HouseId
    priority: float

  var vulnerableTargets: seq[VulnerableTarget] = @[]

  # Check enemy colonies from intelligence database
  for systemId, colonyReport in filtered.ownHouse.intelligence.colonyReports:
    if colonyReport.targetOwner == controller.houseId:
      continue  # Skip own colonies

    # Check diplomatic stance - only counter-attack enemies
    # TODO: Use isEnemy when diplomacy module fully imported
    # For now, assume all non-self colonies are potential targets in Act 1
    # let isEnemy = filtered.ownHouse.diplomaticRelations.isEnemy(colonyReport.targetOwner)
    # if not isEnemy:
    #   continue  # Skip allies/neutrals

    # TODO: Check for fleet presence when we have better fleet intel tracking
    # For MVP, consider all enemy colonies as potential targets
    # Fleet defender detection would require scout encounters or full fog-of-war visibility

    # Priority based on industry value
    var priority = 100.0
    priority += colonyReport.industry.float * 2.0

    vulnerableTargets.add(VulnerableTarget(
      systemId: systemId,
      enemyHouse: colonyReport.targetOwner,
      priority: priority
    ))

  if vulnerableTargets.len == 0:
    return result

  # Sort targets by priority (highest first) - simple bubble approach
  for i in 0..<vulnerableTargets.len:
    for j in (i+1)..<vulnerableTargets.len:
      if vulnerableTargets[j].priority > vulnerableTargets[i].priority:
        swap(vulnerableTargets[i], vulnerableTargets[j])

  # Assign attackers to targets
  let maxAttacks = min(availableAttackers.len, vulnerableTargets.len)

  for i in 0..<maxAttacks:
    let attacker = availableAttackers[i]
    let target = vulnerableTargets[i]

    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Admiral: Counter-attack - fleet {attacker.fleetId} → " &
            &"enemy colony at system {target.systemId} (priority: {target.priority:.1f})")

    result.add(FleetOrder(
      fleetId: attacker.fleetId,
      orderType: FleetOrderType.Move,
      targetSystem: some(target.systemId),
      priority: 90  # High priority - opportunistic strikes
    ))

  return result
