## Offensive Operations Sub-module
## Handles fleet merging, probing attacks, and counter-attacks
##
## Key Strategies:
## - Fleet merging: Consolidate idle single-ship fleets in Act 2+ for combat effectiveness
## - Probing attacks: Scout enemy defenses with expendable scouts
## - Counter-attacks: Exploit enemy vulnerabilities (weak/absent defenses)

import std/[options, strformat]
import ../../../common/types/core
import ../../../engine/[gamestate, fog_of_war, fleet, order_types, logger]
import ../../../engine/diplomacy/types as dip_types  # For isEnemy
import ../controller_types
import ../config
import ./fleet_analysis  # For FleetAnalysis, FleetUtilization types

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
  let mergeThreshold = globalRBAConfig.domestikos.merge_threshold_act2

  # Merge idle scouts
  if idleScouts.len >= mergeThreshold:
    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Domestikos: Merging {idleScouts.len} idle scout fleets to {stagingArea}")

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
            &"{controller.houseId} Domestikos: Merging {idleCombatFleets.len} idle combat fleets to {stagingArea}")

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

  # Find enemy colonies to probe (from current visibility)
  var probingTargets: seq[SystemId] = @[]

  # Check currently visible enemy colonies
  for visibleColony in filtered.visibleColonies:
    if visibleColony.owner == controller.houseId:
      continue  # Skip own colonies

    # Probe all enemy colonies (scouting mission, not attack)
    probingTargets.add(visibleColony.systemId)

  if probingTargets.len == 0:
    return result

  # Assign scouts to probe targets (max 1 scout per target)
  let maxProbes = min(availableScouts.len, probingTargets.len)

  for i in 0..<maxProbes:
    let scout = availableScouts[i]
    let target = probingTargets[i]

    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Domestikos: Probing attack - fleet {scout.fleetId} → system {target}")

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

  # Find vulnerable enemy colonies from CURRENT visibility (not historical intel)
  type VulnerableTarget = object
    systemId: SystemId
    enemyHouse: HouseId
    priority: float

  var vulnerableTargets: seq[VulnerableTarget] = @[]

  # Check currently visible enemy colonies
  for visibleColony in filtered.visibleColonies:
    if visibleColony.owner == controller.houseId:
      continue  # Skip own colonies

    # Check diplomatic stance - only counter-attack enemies
    let isEnemy = filtered.ownHouse.diplomaticRelations.isEnemy(visibleColony.owner)
    if not isEnemy:
      continue  # Skip allies/neutrals

    # Check for visible defending fleets at this location
    var hasDefenders = false
    for visibleFleet in filtered.visibleFleets:
      if visibleFleet.owner == visibleColony.owner and visibleFleet.location == visibleColony.systemId:
        hasDefenders = true
        break

    # Only target undefended or lightly defended enemy colonies
    if not hasDefenders:
      # Undefended colony - high priority target
      var priority = 100.0
      if visibleColony.estimatedIndustry.isSome:
        priority += visibleColony.estimatedIndustry.get().float * 2.0

      vulnerableTargets.add(VulnerableTarget(
        systemId: visibleColony.systemId,
        enemyHouse: visibleColony.owner,
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
            &"{controller.houseId} Domestikos: Counter-attack - fleet {attacker.fleetId} → " &
            &"enemy colony at system {target.systemId} (priority: {target.priority:.1f})")

    result.add(FleetOrder(
      fleetId: attacker.fleetId,
      orderType: FleetOrderType.Move,
      targetSystem: some(target.systemId),
      priority: 90  # High priority - opportunistic strikes
    ))

  return result
