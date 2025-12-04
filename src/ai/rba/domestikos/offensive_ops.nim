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
  ## Generate intelligence gathering orders for scouts
  ## Uses SpyPlanet/SpySystem/HackStarbase for proper intel missions
  result = @[]

  # Find idle scouts
  var availableScouts: seq[FleetAnalysis] = @[]
  for analysis in analyses:
    if analysis.utilization == FleetUtilization.Idle and analysis.hasScouts:
      availableScouts.add(analysis)

  if availableScouts.len == 0:
    return result

  # Find intelligence targets (enemy colonies and starbases)
  type IntelTarget = object
    systemId: SystemId
    orderType: FleetOrderType  # SpyPlanet, SpySystem, or HackStarbase
    priority: int
    description: string

  var intelTargets: seq[IntelTarget] = @[]
  var targetedSystems: seq[SystemId] = @[]  # Track systems to avoid duplicates

  # Priority 1: Hack enemy starbases (high-value intelligence)
  for visibleFleet in filtered.visibleFleets:
    if visibleFleet.owner == controller.houseId:
      continue  # Skip own fleets

    # Check if fleet is a starbase (stationary defensive installation)
    # TODO: Add proper starbase detection when fleet.isStarbase field available
    # For now, check for stationary fleets at colony locations
    var isStarbase = false
    for visibleColony in filtered.visibleColonies:
      if visibleFleet.location == visibleColony.systemId and visibleColony.owner == visibleFleet.owner:
        # Stationary fleet at enemy colony - likely a starbase
        isStarbase = true
        break

    if isStarbase:
      # Skip if already targeted
      if visibleFleet.location in targetedSystems:
        continue

      intelTargets.add(IntelTarget(
        systemId: visibleFleet.location,
        orderType: FleetOrderType.HackStarbase,
        priority: 100,  # Highest priority
        description: "hack starbase"
      ))
      targetedSystems.add(visibleFleet.location)

  # Priority 2: Spy on enemy colonies (gather defense/production intel)
  for visibleColony in filtered.visibleColonies:
    if visibleColony.owner == controller.houseId:
      continue  # Skip own colonies

    # Skip if already targeted
    if visibleColony.systemId in targetedSystems:
      continue

    # Check diplomatic stance - prioritize enemies
    let isEnemy = filtered.ownHouse.diplomaticRelations.isEnemy(visibleColony.owner)
    let priority = if isEnemy: 90 else: 70

    intelTargets.add(IntelTarget(
      systemId: visibleColony.systemId,
      orderType: FleetOrderType.SpyPlanet,
      priority: priority,
      description: "spy planet"
    ))
    targetedSystems.add(visibleColony.systemId)

  # Priority 3: Reconnaissance of enemy systems (general intel)
  # Spy on systems with enemy fleets but no visible colony
  for visibleFleet in filtered.visibleFleets:
    if visibleFleet.owner == controller.houseId:
      continue  # Skip own fleets

    # Skip if already targeted (O(n) instead of O(n²))
    if visibleFleet.location in targetedSystems:
      continue

    intelTargets.add(IntelTarget(
      systemId: visibleFleet.location,
      orderType: FleetOrderType.SpySystem,
      priority: 60,
      description: "spy system"
    ))
    targetedSystems.add(visibleFleet.location)

  if intelTargets.len == 0:
    return result

  # Sort targets by priority (highest first)
  for i in 0..<intelTargets.len:
    for j in (i+1)..<intelTargets.len:
      if intelTargets[j].priority > intelTargets[i].priority:
        swap(intelTargets[i], intelTargets[j])

  # Assign scouts to intel targets (max 1 scout per target)
  let maxMissions = min(availableScouts.len, intelTargets.len)

  for i in 0..<maxMissions:
    let scout = availableScouts[i]
    let target = intelTargets[i]

    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Domestikos: Intelligence mission - fleet {scout.fleetId} → " &
            &"{target.description} at system {target.systemId}")

    result.add(FleetOrder(
      fleetId: scout.fleetId,
      orderType: target.orderType,  # FIXED: Was FleetOrderType.Move
      targetSystem: some(target.systemId),
      priority: 85  # Higher than merge, lower than tactical
    ))

  return result

proc selectCombatOrderType(
  filtered: FilteredGameState,
  fleetId: FleetId,
  shipCount: int,
  targetColony: VisibleColony
): FleetOrderType =
  ## Choose appropriate combat order based on fleet composition and target defenses
  ##
  ## Strategy:
  ## - Weak/no defense + transports → Blitz (simultaneous bombardment + invasion)
  ## - Moderate defense + transports → Bombard first to soften
  ## - Strong defense → Bombard only (invasion too risky)
  ## - No transports → Bombard only

  # Find fleet and check for troop transports (marines)
  var hasTransports = false
  for fleet in filtered.ownFleets:
    if fleet.id == fleetId:
      for squadron in fleet.squadrons:
        if squadron.flagship.shipClass == ShipClass.TroopTransport:
          hasTransports = true
          break
      break

  # Estimate target defense strength (0-10 scale)
  # Higher values = stronger defenses
  var defenseStrength = 0
  if targetColony.estimatedDefenses.isSome:
    let defenses = targetColony.estimatedDefenses.get()
    defenseStrength = defenses  # Ground defenses (armies, marines, batteries)

  # Decision logic based on defenses and fleet composition
  if not hasTransports:
    # No transports - can only bombard
    return FleetOrderType.Bombard

  elif defenseStrength <= 2 and shipCount >= 3:
    # Weak/no defenses, strong fleet with transports → Blitz
    # Simultaneous bombardment + invasion for quick victory
    return FleetOrderType.Blitz

  elif defenseStrength <= 5 and shipCount >= 2:
    # Moderate defenses → Bombard first to soften
    # AI will need to follow up with invasion on next turn
    return FleetOrderType.Bombard

  elif shipCount >= 4:
    # Strong fleet can attempt invasion even with moderate defenses
    return FleetOrderType.Invade

  else:
    # Strong defenses or weak fleet → Just bombard
    # Soften target for future invasion
    return FleetOrderType.Bombard

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
    colony: VisibleColony  # Store colony for defense assessment

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
        priority: priority,
        colony: visibleColony  # Store for combat order selection
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

    # NEW: Select appropriate combat order based on fleet composition and target defenses
    let combatOrder = selectCombatOrderType(
      filtered,
      attacker.fleetId,
      attacker.shipCount,
      target.colony  # Pass target colony for defense assessment
    )

    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Domestikos: {combatOrder} attack - fleet {attacker.fleetId} → " &
            &"enemy colony at system {target.systemId} (priority: {target.priority:.1f})")

    result.add(FleetOrder(
      fleetId: attacker.fleetId,
      orderType: combatOrder,  # FIXED: Was FleetOrderType.Move
      targetSystem: some(target.systemId),
      priority: 90  # High priority - opportunistic strikes
    ))

  return result
