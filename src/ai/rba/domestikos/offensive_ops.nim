## Offensive Operations Sub-module
## Handles fleet merging, probing attacks, and counter-attacks
##
## Key Strategies:
## - Fleet merging: Consolidate idle single-ship fleets in Act 2+ for combat effectiveness
## - Probing attacks: Scout enemy defenses with expendable scouts
## - Counter-attacks: Exploit enemy vulnerabilities (weak/absent defenses)

import std/[options, strformat, sets, tables]
import ../../../common/types/core
import ../../../engine/[gamestate, fog_of_war, fleet, order_types, logger, starmap]
import ../../../engine/diplomacy/types as dip_types  # For isEnemy
import ../../../engine/intelligence/types as intel_types  # For IntelQuality enum
import ../controller_types
import ../config
import ../shared/intelligence_types  # Phase F: Intelligence integration
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
  var targetedSystems = initHashSet[SystemId]()  # Track systems to avoid duplicates (O(1) lookup)

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
      targetedSystems.incl(visibleFleet.location)

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
    targetedSystems.incl(visibleColony.systemId)

  # Priority 3: Reconnaissance of enemy systems (general intel)
  # Spy on systems with enemy fleets but no visible colony
  for visibleFleet in filtered.visibleFleets:
    if visibleFleet.owner == controller.houseId:
      continue  # Skip own fleets

    # Skip if already targeted (O(1) HashSet lookup)
    if visibleFleet.location in targetedSystems:
      continue

    intelTargets.add(IntelTarget(
      systemId: visibleFleet.location,
      orderType: FleetOrderType.SpySystem,
      priority: 60,
      description: "spy system"
    ))
    targetedSystems.incl(visibleFleet.location)

  if intelTargets.len == 0:
    return result

  # Sort targets by priority (highest first)
  for i in 0..<intelTargets.len:
    for j in (i+1)..<intelTargets.len:
      if intelTargets[j].priority > intelTargets[i].priority:
        swap(intelTargets[i], intelTargets[j])

  # Sort scouts by size (prefer larger groups for mesh network bonuses)
  # Mesh network: 2-3 scouts = +1 ELI, 4-5 scouts = +2 ELI, 6+ scouts = +3 ELI
  # Optimal: 3-6 scouts per mission (caps at +3 ELI, no benefit beyond 6)
  for i in 0..<availableScouts.len:
    for j in (i+1)..<availableScouts.len:
      if availableScouts[j].shipCount > availableScouts[i].shipCount:
        swap(availableScouts[i], availableScouts[j])

  # Assign scouts to intel targets, prioritizing larger scout groups
  # Prefer 3-6 scout groups for optimal mesh network bonus
  var scoutIndex = 0
  var targetIndex = 0

  while scoutIndex < availableScouts.len and targetIndex < intelTargets.len:
    let scout = availableScouts[scoutIndex]
    let target = intelTargets[targetIndex]

    # Check if scout group size is reasonable for spy missions
    # Ideal: 3-6 scouts (optimal mesh network)
    # Acceptable: 1-2 scouts (suboptimal but usable)
    # Too many: 7+ scouts (no additional benefit, wasteful)
    if scout.shipCount > 6:
      logDebug(LogCategory.lcAI,
               &"{controller.houseId} Domestikos: Skipping oversized scout fleet {scout.fleetId} " &
               &"({scout.shipCount} scouts, optimal is 3-6 for mesh network bonus)")
      scoutIndex += 1
      continue

    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Domestikos: Intelligence mission - fleet {scout.fleetId} " &
            &"({scout.shipCount} scouts) → {target.description} at system {target.systemId}")

    result.add(FleetOrder(
      fleetId: scout.fleetId,
      orderType: target.orderType,
      targetSystem: some(target.systemId),
      priority: 85  # Higher than merge, lower than tactical
    ))

    scoutIndex += 1
    targetIndex += 1

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

proc calculateInvasionPriority(
  opportunity: InvasionOpportunity,
  intelQuality: intel_types.IntelQuality
): float =
  ## Calculate invasion priority using intelligence data (Phase F)
  ## Factors: vulnerability, value, intel quality, distance penalty
  var priority = 100.0

  # Vulnerability boost (0-50 points)
  priority += opportunity.vulnerability * 50.0

  # Economic value (0-200 points)
  priority += float(opportunity.estimatedValue) * 2.0

  # Distance penalty (-10 points per jump beyond 5)
  if opportunity.distance > 5:
    priority -= float(opportunity.distance - 5) * 10.0

  # Intel quality confidence multiplier (0.5x - 1.5x)
  let confidenceMultiplier = case intelQuality
    of intel_types.IntelQuality.Perfect: 1.5
    of intel_types.IntelQuality.Spy: 1.2
    of intel_types.IntelQuality.Scan: 1.0
    of intel_types.IntelQuality.Visual: 0.7

  priority *= confidenceMultiplier
  return priority

proc estimateFleetStrength(composition: FleetComposition): float =
  ## Estimate fleet combat strength based on composition
  ## Simple heuristic: ship count weighted by capability
  return float(composition.capitalShips * 3 + composition.escorts * 2 + composition.scouts)

proc findSuitableInvasionFleet(
  analyses: seq[FleetAnalysis],
  requiredForceScore: int,
  filtered: FilteredGameState,
  targetSystem: SystemId
): Option[FleetId] =
  ## Find available fleet with sufficient strength for invasion (Phase F)
  ## 1.2x safety margin for success probability
  for analysis in analyses:
    # Check availability
    if analysis.utilization notin {FleetUtilization.Idle, FleetUtilization.UnderUtilized}:
      continue

    # Check combat capability
    if not analysis.hasCombatShips or analysis.shipCount < 2:
      continue

    # Estimate fleet strength (simple approximation: ~10 strength per ship)
    let fleetStrength = float(analysis.shipCount) * 10.0

    # Strength requirement (1.2x safety margin)
    if fleetStrength < float(requiredForceScore) * 1.2:
      continue

    # Distance/ETA check (reject if > 8 turns)
    let pathResult = filtered.starMap.findPath(analysis.location, targetSystem, Fleet())
    if pathResult.found:
      let eta = pathResult.path.len
      if eta > 8:
        continue  # Too distant
    else:
      continue  # No path

    return some(analysis.fleetId)

  return none(FleetId)

proc generateCounterAttackOrders*(
  filtered: FilteredGameState,
  analyses: seq[FleetAnalysis],
  controller: AIController,
  intelSnapshot: Option[IntelligenceSnapshot] = none(IntelligenceSnapshot)  # Phase F: Intelligence integration
): seq[FleetOrder] =
  ## Generate counter-attack orders against vulnerable enemy targets
  ## Phase F: Intelligence-driven targeting using military.vulnerableTargets and economic.highValueTargets
  ## Fallback: Visibility-based targeting when intelligence unavailable
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

  # === PHASE F: INTELLIGENCE-DRIVEN TARGETING ===
  type VulnerableTarget = object
    systemId: SystemId
    enemyHouse: HouseId
    priority: float
    colony: VisibleColony  # Store colony for defense assessment (optional for intel targets)

  var vulnerableTargets: seq[VulnerableTarget] = @[]

  # Priority 1: Use military.vulnerableTargets (invasion opportunities)
  if intelSnapshot.isSome:
    let snapshot = intelSnapshot.get()
    var intelTargetsFound = false

    # Primary: Intelligence-identified vulnerable targets
    for opportunity in snapshot.military.vulnerableTargets:
      # Filter: only diplomatic enemies
      let isEnemy = filtered.ownHouse.diplomaticRelations.isEnemy(opportunity.owner)
      if not isEnemy:
        continue

      # Calculate intelligence-driven priority
      let priority = calculateInvasionPriority(opportunity, opportunity.intelQuality)

      # Find suitable fleet with strength safety margin
      let assignedFleet = findSuitableInvasionFleet(analyses, opportunity.requiredForce, filtered, opportunity.systemId)

      if assignedFleet.isSome:
        intelTargetsFound = true
        logInfo(LogCategory.lcAI,
                &"{controller.houseId} Domestikos: Intelligence-driven invasion - system {opportunity.systemId} " &
                &"({opportunity.owner}), vulnerability {opportunity.vulnerability:.2f}, " &
                &"value {opportunity.estimatedValue}, confidence {opportunity.intelQuality}")

        # Create order directly (no need to defer to visibility targeting)
        result.add(FleetOrder(
          fleetId: assignedFleet.get(),
          orderType: FleetOrderType.Invade,  # Intelligence targets warrant invasion
          targetSystem: some(opportunity.systemId),
          priority: int(priority)
        ))

    # Secondary: High-value economic targets (undefended)
    if not intelTargetsFound:
      for hvTarget in snapshot.economic.highValueTargets:
        # Filter: only undefended high-value targets
        if hvTarget.estimatedDefenses > 0:
          continue

        # Filter: only diplomatic enemies
        let isEnemy = filtered.ownHouse.diplomaticRelations.isEnemy(hvTarget.owner)
        if not isEnemy:
          continue

        # Find available fleet
        for attacker in availableAttackers:
          let pathResult = filtered.starMap.findPath(attacker.location, hvTarget.systemId, Fleet())
          if pathResult.found and pathResult.path.len <= 8:
            let priority = float(hvTarget.estimatedValue) * 1.5  # High-value multiplier

            logInfo(LogCategory.lcAI,
                    &"{controller.houseId} Domestikos: Economic target - system {hvTarget.systemId} " &
                    &"({hvTarget.owner}), value {hvTarget.estimatedValue}, " &
                    &"shipyards {hvTarget.shipyardCount}")

            result.add(FleetOrder(
              fleetId: attacker.fleetId,
              orderType: FleetOrderType.Bombard,  # Economic disruption via bombardment
              targetSystem: some(hvTarget.systemId),
              priority: int(priority)
            ))
            break  # One fleet per target

    # If intelligence targeting succeeded, return early
    if result.len > 0:
      return result

  # === FALLBACK: VISIBILITY-BASED OPPORTUNISTIC TARGETING ===
  # Only used when intelligence unavailable or found no suitable targets

  # Find vulnerable enemy colonies from CURRENT visibility (not historical intel)
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
