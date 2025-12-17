## Offensive Operations Sub-module
## Handles fleet merging, probing attacks, and counter-attacks
##
## Key Strategies:
## - Fleet merging: Consolidate idle single-ship fleets in Act 2+ for combat effectiveness
## - Probing attacks: Scout enemy defenses with expendable scouts
## - Counter-attacks: Exploit enemy vulnerabilities (weak/absent defenses)

import std/[options, strformat, sets, tables, algorithm] # Added algorithm for min/max if not already present
import ../../../common/types/core
import ../../../engine/[gamestate, fog_of_war, fleet, order_types, logger, starmap]
import ../../../engine/diplomacy/types as dip_types  # For isEnemy
import ../../../engine/intelligence/types as intel_types  # For IntelQuality enum
import ../controller_types
import ../config # For globalRBAConfig
import ../shared/intelligence_types  # Phase F: Intelligence integration
import ../intelligence # For calculateDistance
import ./fleet_analysis # For FleetAnalysis, FleetUtilization types

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
  let mergeThreshold = controller.rbaConfig.domestikos.merge_threshold_act2

  # Merge idle scouts
  if idleScouts.len >= mergeThreshold:
    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Domestikos: Merging {idleScouts.len} idle scout fleets to {stagingArea}")

    for analysis in idleScouts:
      result.add(FleetOrder(
        fleetId: analysis.fleetId,
        orderType: FleetOrderType.Move,
        targetSystem: some(stagingArea),
        priority: controller.rbaConfig.domestikos_offensive.priority_base
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
        priority: controller.rbaConfig.domestikos_offensive.priority_base
      ))

  return result

# generateProbingOrders removed - scouts now managed by Drungarius (intelligence advisor)
# See src/ai/rba/drungarius/reconnaissance/deployment.nim for scout deployment

proc selectCombatOrderType(
  controller: AIController,
  filtered: FilteredGameState,
  fleetId: FleetId,
  shipCount: int,
  targetColony: VisibleColony,
  intelSnapshot: Option[IntelligenceSnapshot] = none(IntelligenceSnapshot)
): FleetOrderType =
  ## Space-First Combat Order Selection
  ##
  ## Philosophy: Space superiority is PRIMARY. Ground defenses are SECONDARY.
  ## Strategy:
  ## 1. Check space superiority (our fleet vs their defending fleet)
  ## 2. If we have space superiority → choose tactic based on ground defenses
  ## 3. If we DON'T have space superiority → Bombard from range (risky to close)
  ##
  ## Ground defenses only affect TACTIC (Invade/Blitz/Bombard), not WHETHER to attack

  # Find fleet and check for troop transports with LOADED Marines
  var hasLoadedTransports = false
  var totalMarines = 0
  for fleet in filtered.ownFleets:
    if fleet.id == fleetId:
      # Check Auxiliary squadrons for loaded Marines
      for squadron in fleet.squadrons:
        if squadron.squadronType == SquadronType.Auxiliary:
          if squadron.flagship.shipClass == ShipClass.TroopTransport:
            if squadron.flagship.cargo.isSome:
              let cargo = squadron.flagship.cargo.get()
              if cargo.cargoType == CargoType.Marines and cargo.quantity > 0:
                hasLoadedTransports = true
                totalMarines += cargo.quantity
      break

  # === STEP 1: ASSESS SPACE SUPERIORITY (PRIMARY) ===
  # Find attacking fleet strength
  var attackingFleetStrength = 0
  for fleet in filtered.ownFleets:
    if fleet.id == fleetId:
      attackingFleetStrength = fleet.combatStrength()
      break

  # Find defending fleet strength at target
  var defendingFleetStrength = 0
  var defendingFleetCount = 0

  # Check visible fleets at target location
  for visibleFleet in filtered.visibleFleets:
    if visibleFleet.owner == targetColony.owner and visibleFleet.location == targetColony.systemId:
      defendingFleetCount += 1
      # Estimate fleet strength from ship count (rough approximation)
      if visibleFleet.estimatedShipCount.isSome:
        # Strength multiplier from config
        defendingFleetStrength += visibleFleet.estimatedShipCount.get() *
          int(controller.rbaConfig.domestikos_offensive.fleet_strength_multiplier)
      else:
        # Unknown composition - assume 1 medium ship (100 strength)
        defendingFleetStrength += 100

  # Space superiority check
  let hasSpaceSuperiority = defendingFleetCount == 0 or
                           attackingFleetStrength >= defendingFleetStrength

  # === STEP 2: ASSESS GROUND DEFENSES (SECONDARY - only affects tactic) ===
  var groundDefenses = 0  # Armies, marines, ground batteries
  var hasStarbase = false

  if intelSnapshot.isSome:
    let snap = intelSnapshot.get()
    # Check for detailed target intelligence
    for target in snap.military.vulnerableTargets:
      if target.systemId == targetColony.systemId:
        groundDefenses = target.estimatedDefenses div 10  # Ground units
        hasStarbase = (target.estimatedDefenses mod 10) > 0
        break
  else:
    # Fallback to basic estimate (from config)
    if targetColony.estimatedDefenses.isSome:
      groundDefenses = targetColony.estimatedDefenses.get() div
        controller.rbaConfig.domestikos_offensive.ground_defense_divisor

  # === STEP 3: CHOOSE TACTIC ===

  # Check if we have transports - affects available tactics
  if not hasLoadedTransports or totalMarines == 0:
    # No loaded transports - can ONLY bombard (no invasion possible)
    return FleetOrderType.Bombard

  # If we DON'T have space superiority, bombard from range (too risky to close for invasion)
  if not hasSpaceSuperiority:
    return FleetOrderType.Bombard

  # WE HAVE SPACE SUPERIORITY - choose tactic based on RELATIVE STRENGTH
  # Philosophy: Compare invasion force vs planetary defenses (scales with game progression)

  # Calculate marine-to-defense ratio (relative strength)
  let marineRatio = if groundDefenses > 0:
                      float(totalMarines) / float(groundDefenses)
                    else:
                      float(totalMarines)  # Undefended = infinite advantage

  # Minimum marines check (need at least 2 for any ground assault)
  if totalMarines < 2:
    # Insufficient marines for ground assault - use bombardment to soften
    if targetColony.estimatedIndustry.isSome and targetColony.estimatedIndustry.get() >= 5:
      return FleetOrderType.BlockadePlanet  # High-value target = blockade
    else:
      return FleetOrderType.Bombard  # Low-value target = bombard to weaken

  # Select tactic based on marine advantage
  if marineRatio >= 2.0 or groundDefenses == 0:
    # Overwhelming marine superiority (2:1 or better) OR undefended
    # Blitz = skip bombardment, immediate assault
    return FleetOrderType.Blitz

  elif marineRatio >= 0.5:
    # Adequate marines for systematic approach (1:2 ratio or better)
    # Invade = bombardment round + ground assault
    # This should be the MOST COMMON order type for conquest
    return FleetOrderType.Invade

  else:
    # Insufficient marines (less than 1:2 ratio) - high casualties expected
    # Use bombardment or blockade to weaken defenses first
    if targetColony.estimatedIndustry.isSome and targetColony.estimatedIndustry.get() >= 5:
      return FleetOrderType.BlockadePlanet  # Economic siege for high-value targets
    else:
      return FleetOrderType.Bombard  # Bombard to soften defenses

proc calculateInvasionPriority(
  controller: AIController,
  opportunity: InvasionOpportunity,
  intelQuality: intel_types.IntelQuality
): float =
  ## Calculate invasion priority using intelligence data (Phase F)
  ## Factors: vulnerability, value, intel quality, distance penalty
  var priority = 100.0

  # Vulnerability boost (from config)
  priority += opportunity.vulnerability * controller.rbaConfig.domestikos_offensive.vulnerability_multiplier

  # Economic value (from config)
  priority += float(opportunity.estimatedValue) * controller.rbaConfig.domestikos_offensive.estimated_value_multiplier

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

proc estimateEnemyFleetStrength*(
  systemId: SystemId,
  enemyHouse: HouseId,
  intelSnapshot: Option[IntelligenceSnapshot]
): tuple[minStrength: int, maxStrength: int, confidence: float] =
  ## Phase 4.1: Enhanced enemy fleet strength estimation using intelligence
  ## Returns (minStrength, maxStrength, confidence) based on intel quality
  ## Uses detailed composition and tech levels when available

  result = (minStrength: 0, maxStrength: 0, confidence: 0.0)

  if intelSnapshot.isNone:
    # No intelligence - return unknown
    return (minStrength: 0, maxStrength: 500, confidence: 0.1)

  let snap = intelSnapshot.get()

  # Find enemy fleets at this system
  var fleetsAtSystem: seq[EnemyFleetSummary] = @[]
  for fleet in snap.military.knownEnemyFleets:
    if fleet.lastKnownLocation == systemId and fleet.owner == enemyHouse:
      fleetsAtSystem.add(fleet)

  if fleetsAtSystem.len == 0:
    # No known enemy fleets - return minimal threat
    return (minStrength: 0, maxStrength: 100, confidence: 0.5)

  # Calculate total strength from composition data
  var totalMinStrength = 0
  var totalMaxStrength = 0
  var totalConfidence = 0.0

  for fleet in fleetsAtSystem:
    var fleetMin = fleet.estimatedStrength
    var fleetMax = fleet.estimatedStrength

    # If we have detailed composition, calculate more accurately
    if fleet.composition.isSome:
      let comp = fleet.composition.get()
      # Base strength from composition
      let baseStrength =
        comp.capitalShips * 200 +
        comp.cruisers * 100 +
        comp.destroyers * 50 +
        comp.escorts * 25 +
        comp.scouts * 10

      fleetMin = baseStrength
      fleetMax = baseStrength

      # Apply tech level multiplier if available
      if snap.research.enemyTechLevels.hasKey(enemyHouse):
        let enemyTech = snap.research.enemyTechLevels[enemyHouse]
        # Use CST (ConstructionTech) as proxy for ship quality
        if enemyTech.techLevels.hasKey(TechField.ConstructionTech):
          let techLevel = enemyTech.techLevels[TechField.ConstructionTech]
          # Higher tech = stronger ships (10% per level above 1)
          let techMultiplier = 1.0 + (float(techLevel - 1) * 0.1)
          fleetMin = int(float(fleetMin) * techMultiplier)
          fleetMax = int(float(fleetMax) * techMultiplier * 1.2)  # 20% uncertainty
    else:
      # No composition data - use rough estimate with wider range
      fleetMax = int(float(fleetMin) * 1.5)  # 50% uncertainty

    totalMinStrength += fleetMin
    totalMaxStrength += fleetMax

    # Confidence based on intel age
    let intelAge = snap.turn - fleet.lastSeen
    let ageConfidence = max(0.3, 1.0 - (float(intelAge) * 0.1))  # Decay 10% per turn
    totalConfidence += ageConfidence

  # Average confidence across all fleets
  if fleetsAtSystem.len > 0:
    totalConfidence /= float(fleetsAtSystem.len)

  result = (
    minStrength: totalMinStrength,
    maxStrength: totalMaxStrength,
    confidence: totalConfidence
  )

proc hasLoadedMarines(fleet: Fleet): tuple[hasTransports: bool, marineCount: int] =
  ## Check if fleet has Auxiliary squadrons (TroopTransports) with loaded marines
  ## Returns (hasTransports, marineCount)
  result = (hasTransports: false, marineCount: 0)

  for squadron in fleet.squadrons:
    if squadron.squadronType == SquadronType.Auxiliary:
      if squadron.flagship.shipClass == ShipClass.TroopTransport:
        if squadron.flagship.cargo.isSome:
          let cargo = squadron.flagship.cargo.get()
          if cargo.cargoType == CargoType.Marines and cargo.quantity > 0:
            result.hasTransports = true
            result.marineCount += cargo.quantity

proc findSuitableInvasionFleet(
  controller: AIController,
  analyses: seq[FleetAnalysis],
  requiredForceScore: int,
  filtered: FilteredGameState,
  targetSystem: SystemId
): Option[FleetId] =
  ## Find available fleet with sufficient strength for invasion (Phase F)
  ## CRITICAL: Fleet MUST have loaded TroopTransports (marines) for ground assault
  ## 1.0x safety margin - take risks for opportunity strikes
  for analysis in analyses:
    # Check availability
    if analysis.utilization notin {FleetUtilization.Idle, FleetUtilization.Idle, FleetUtilization.UnderUtilized}: # Corrected to not have duplicate 'Idle'
      continue

    # Retrieve the actual Fleet object to use its combatStrength
    var maybeFleet: Option[Fleet] = none(Fleet)
    for f in filtered.ownFleets:
      if f.id == analysis.fleetId:
        maybeFleet = some(f)
        break
    if maybeFleet.isNone:
      continue # Fleet no longer exists or not accessible in filtered state

    let fleet = maybeFleet.get()

    # Check combat capability
    if not fleet.hasCombatShips or fleet.squadrons.len < 1: # At least one squadron
      continue

    # CRITICAL: Check for loaded marines (required for invasion)
    let (hasTransports, marineCount) = hasLoadedMarines(fleet)
    if not hasTransports or marineCount < 2:
      # Need at least 2 marines for invasion
      logDebug(LogCategory.lcAI,
               &"Domestikos: Fleet {fleet.id} unsuitable for invasion - " &
               &"no loaded transports (marines: {marineCount})")
      continue

    # Use the engine's actual combat strength calculation
    let fleetStrength = fleet.combatStrength().float

    # Strength requirement (1.0x - take risks for opportunity)
    if fleetStrength < float(requiredForceScore) * 1.0: # Even match - aggressive stance
      continue

    # Distance/ETA check (reject if > configured max turns)
    let pathResult = filtered.starMap.findPath(analysis.location, targetSystem, fleet)
    if pathResult.found:
      let eta = pathResult.path.len
      if eta > controller.rbaConfig.domestikos.max_invasion_eta_turns:
        logDebug(LogCategory.lcAI, &"Domestikos: Fleet {fleet.id} too distant for invasion ({eta} turns > {controller.rbaConfig.domestikos.max_invasion_eta_turns}).")
        continue  # Too distant
    else:
      logDebug(LogCategory.lcAI, &"Domestikos: No path found for fleet {fleet.id} to {targetSystem}.")
      continue  # No path

    logInfo(LogCategory.lcAI,
            &"Domestikos: Selected fleet {fleet.id} for invasion - " &
            &"strength {fleetStrength:.0f}, marines {marineCount}")
    return some(analysis.fleetId)

  return none(FleetId)

# =============================================================================
# Phase 2: Multi-Turn Invasion Campaign Functions
# =============================================================================

proc hasRecentIntel(
  controller: AIController,
  filtered: FilteredGameState,
  systemId: SystemId,
  maxAge: int = 0  # Will use config default if 0
): bool =
  ## Check if we have fresh intelligence on a system (within maxAge turns)
  let currentTurn = filtered.turn
  let actualMaxAge = if maxAge > 0: maxAge else: controller.rbaConfig.domestikos_offensive.max_intel_age_turns

  if filtered.ownHouse.intelligence.colonyReports.hasKey(systemId):
    let report = filtered.ownHouse.intelligence.colonyReports[systemId]
    return (currentTurn - report.gatheredTurn) <= actualMaxAge

  return false

proc estimateGroundBatteries(
  controller: AIController,
  filtered: FilteredGameState,
  systemId: SystemId
): int =
  ## Estimate remaining ground batteries from intelligence
  ## Returns 0 if no intel available
  if not filtered.ownHouse.intelligence.colonyReports.hasKey(systemId):
    return controller.rbaConfig.domestikos_offensive.conservative_ship_estimate

  let report = filtered.ownHouse.intelligence.colonyReports[systemId]
  # Batteries based on defense strength (rough estimate)
  # Each ground defense unit might have ~1 battery
  return report.defenses

# Campaign functions removed - GOAP now handles multi-turn strategic planning
# See: goap/domains/fleet/goals.nim for InvadeColony, SecureSystem, DefendColony goals
# RBA Domestikos focuses on tactical order selection via selectCombatOrderType()

# =============================================================================
# Counter-Attack Order Generation
# =============================================================================

proc generateCounterAttackOrders*(
  filtered: FilteredGameState,
  analyses: seq[FleetAnalysis],
  controller: var AIController,
  intelSnapshot: Option[IntelligenceSnapshot] = none(IntelligenceSnapshot)
): seq[FleetOrder] =
  ## Generate opportunistic counter-attack orders against vulnerable enemy targets
  ##
  ## Tactical (single-turn) invasion order generation:
  ## - Intelligence-driven targeting using military.vulnerableTargets
  ## - Visibility-based fallback when intelligence unavailable
  ## - Order type selection via selectCombatOrderType (Invade/Blitz/Bombard)
  ##
  ## NOTE: Multi-turn strategic campaigns now handled by GOAP
  ## See: goap/domains/fleet/goals.nim for InvadeColony, SecureSystem goals
  result = @[]

  # ==========================================================================
  # TACTICAL INVASION ORDERS (OPPORTUNISTIC)
  # ==========================================================================
  # Immediate single-turn tactical responses to intelligence opportunities

  logDebug(LogCategory.lcAI,
           &"{controller.houseId} Invasion: Evaluating invasion opportunities " &
           &"(total fleets: {analyses.len})")

  # Find available combat fleets (idle, under-utilized, or optimally-defended)
  # IMPORTANT: Include Optimal fleets with DefendSystem standing orders
  # Rationale: Defensive fleets can be reassigned for offensive ops (standing orders are strategic defaults)
  var availableAttackers: seq[FleetAnalysis] = @[]
  for analysis in analyses:
    if analysis.utilization in {FleetUtilization.Idle, FleetUtilization.UnderUtilized, FleetUtilization.Optimal}:
      if analysis.hasCombatShips and analysis.shipCount >= 2:
        # Need at least 2 ships for counter-attack
        availableAttackers.add(analysis)

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Invasion: Found {availableAttackers.len} available combat fleets " &
          &"(idle/underutilized with 2+ ships)")

  if availableAttackers.len == 0:
    logWarn(LogCategory.lcAI,
            &"{controller.houseId} Invasion: NO AVAILABLE ATTACKERS - all fleets busy or too small")
    return result

  # === PHASE F: INTELLIGENCE-DRIVEN TARGETING ===
  type VulnerableTarget = object
    systemId: SystemId
    enemyHouse: HouseId
    priority: float
    colony: VisibleColony  # Store colony for defense assessment (optional for intel targets)

  var vulnerableTargets: seq[VulnerableTarget] = @[]
  var assignedFleets: HashSet[FleetId] = initHashSet[FleetId]()  # Track fleets already assigned

  # Priority 1: Use military.vulnerableTargets (invasion opportunities)
  if intelSnapshot.isSome:
    let snapshot = intelSnapshot.get()
    var intelTargetsFound = false

    # Primary: Intelligence-identified vulnerable targets
    for opportunity in snapshot.military.vulnerableTargets:
      # No diplomatic filtering - attack ANY house (neutrals, hostiles, enemies)
      # Surprise attacks and opportunistic land grabs are valid strategies

      # Calculate intelligence-driven priority
      let priority = calculateInvasionPriority(controller, opportunity, opportunity.intelQuality)

      # Find suitable fleet with strength safety margin
      let assignedFleet = findSuitableInvasionFleet(controller, analyses, opportunity.requiredForce, filtered, opportunity.systemId)

      if assignedFleet.isSome:
        intelTargetsFound = true
        let fleetId = assignedFleet.get()

        # Find target colony for combat order selection
        var targetColony: Option[VisibleColony] = none(VisibleColony)
        for colony in filtered.visibleColonies:
          if colony.systemId == opportunity.systemId:
            targetColony = some(colony)
            break

        # Select appropriate combat order based on conditions
        var orderType = FleetOrderType.Bombard  # Fallback if no colony visible
        var shipCount = 1

        # Get fleet ship count for order selection
        for analysis in analyses:
          if analysis.fleetId == fleetId:
            shipCount = analysis.shipCount
            break

        if targetColony.isSome:
          orderType = selectCombatOrderType(
            controller,
            filtered,
            fleetId,
            shipCount,
            targetColony.get(),
            intelSnapshot
          )

        logInfo(LogCategory.lcAI,
                &"{controller.houseId} Domestikos: Intelligence-driven {orderType} - system {opportunity.systemId} " &
                &"({opportunity.owner}), vulnerability {opportunity.vulnerability:.2f}, " &
                &"value {opportunity.estimatedValue}, confidence {opportunity.intelQuality}")

        # Create order with selected tactic
        let roe = case orderType
          of FleetOrderType.Blitz: controller.rbaConfig.domestikos_offensive.roe_blitz_priority
          of FleetOrderType.Invade: 10  # All-out invasion
          of FleetOrderType.BlockadePlanet: controller.rbaConfig.domestikos_offensive.roe_bombardment_priority
          else: controller.rbaConfig.domestikos_offensive.roe_bombardment_priority  # Bombard fallback

        result.add(FleetOrder(
          fleetId: fleetId,
          orderType: orderType,
          targetSystem: some(opportunity.systemId),
          priority: int(priority),
          roe: some(roe)
        ))
        assignedFleets.incl(fleetId)  # Mark fleet as assigned

    # Secondary: High-value economic targets (undefended)
    if not intelTargetsFound:
      for hvTarget in snapshot.economic.highValueTargets:
        # Filter: only undefended high-value targets
        if hvTarget.estimatedDefenses > 0:
          continue

        # No diplomatic filtering - attack ANY house for economic disruption

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
              priority: int(priority),
              roe: some(controller.rbaConfig.domestikos_offensive.roe_bombardment_priority) # Main assault
            ))
            assignedFleets.incl(attacker.fleetId)  # Mark fleet as assigned
            break  # One fleet per target

  # === PROXIMITY-BASED OPPORTUNISTIC TARGETING ===
  # ALWAYS evaluate nearby visible colonies for surprise attacks
  # Rationale: Proximity = opportunity. Attack neighbors regardless of intel quality

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Invasion: Using visibility-based targeting " &
          &"(visible colonies: {filtered.visibleColonies.len})")

  # === ASSESS OVERALL ENEMY HOUSE STRENGTH ===
  # Count total ships and colonies per house (strategic assessment)
  var enemyHouseStrength: Table[HouseId, tuple[ships: int, colonies: int]] = initTable[HouseId, tuple[ships: int, colonies: int]]()

  # Count enemy ships from visible fleets
  for visibleFleet in filtered.visibleFleets:
    if visibleFleet.owner != controller.houseId:
      if not enemyHouseStrength.hasKey(visibleFleet.owner):
        enemyHouseStrength[visibleFleet.owner] = (ships: 0, colonies: 0)
      # Add estimated ship count (or assume 1 if unknown)
      let shipCount = if visibleFleet.estimatedShipCount.isSome:
                        visibleFleet.estimatedShipCount.get()
                      else:
                        1  # Assume at least 1 ship if detected
      enemyHouseStrength[visibleFleet.owner].ships += shipCount

  # Count enemy colonies from visible colonies
  for visibleColony in filtered.visibleColonies:
    if visibleColony.owner != controller.houseId:
      if not enemyHouseStrength.hasKey(visibleColony.owner):
        enemyHouseStrength[visibleColony.owner] = (ships: 0, colonies: 0)
      enemyHouseStrength[visibleColony.owner].colonies += 1

  # Calculate our own strength for comparison
  let ourShips = filtered.ownFleets.len  # Total fleets (roughly proportional to ships)
  let ourColonies = filtered.ownColonies.len

  # Find vulnerable enemy colonies from CURRENT visibility (not historical intel)
  var enemyColoniesFound = 0
  for visibleColony in filtered.visibleColonies:
    if visibleColony.owner == controller.houseId:
      continue  # Skip own colonies

    # No diplomatic filtering - attack ANY house (neutrals, hostiles, enemies)
    # Design: Zero-sum conquest game with no allies, only 3 states (Neutral/Hostile/Enemy)
    # Surprise attacks on neutrals are valid strategy for land grab and positioning

    enemyColoniesFound += 1

    # Check for visible defending fleets at this location
    var hasDefenders = false
    for visibleFleet in filtered.visibleFleets:
      if visibleFleet.owner == visibleColony.owner and visibleFleet.location == visibleColony.systemId:
        hasDefenders = true
        break

    # TARGET ALL ENEMY COLONIES (defended and undefended)
    # AI will bombard defended colonies to soften defenses, then invade when weak
    var priority = 100.0
    if visibleColony.estimatedIndustry.isSome:
      priority += visibleColony.estimatedIndustry.get().float * 1.0

    # Prioritize undefended colonies (easier targets)
    if not hasDefenders:
      priority += 100.0  # +100 priority bonus for undefended colonies

    # PROXIMITY BONUS: Heavily prioritize nearby targets (surprise attacks on neighbors)
    # Rationale: Close neighbors are easy targets, low logistical cost, quick conquest
    # Find nearest own colony for distance calculation
    var minDistance = 999
    for ownColony in filtered.ownColonies:
      let dist = calculateDistance(filtered.starMap, visibleColony.systemId,
                                    ownColony.systemId)
      if dist < minDistance:
        minDistance = dist

    # Distance-based priority (proximity = opportunity)
    let proximityBonus = case minDistance
      of 1..2: controller.rbaConfig.domestikos_offensive.distance_bonus_1_2_jumps  # Immediate neighbors - ATTACK!
      of 3..4: controller.rbaConfig.domestikos_offensive.distance_bonus_3_4_jumps  # Close neighbors - strong opportunity
      of 5..6: controller.rbaConfig.domestikos_offensive.distance_bonus_5_6_jumps  # Moderate distance - still viable
      else: 0.0       # Distant targets - no bonus

    priority += proximityBonus

    # HOUSE WEAKNESS BONUS: Prioritize attacking weak houses
    # Rationale: Weak houses can't defend effectively, easier to conquer
    if enemyHouseStrength.hasKey(visibleColony.owner):
      let enemyStrength = enemyHouseStrength[visibleColony.owner]

      # Compare their strength to ours (ratio < 1.0 means they're weaker)
      let shipRatio = if ourShips > 0: float(enemyStrength.ships) / float(ourShips) else: 1.0
      let colonyRatio = if ourColonies > 0: float(enemyStrength.colonies) / float(ourColonies) else: 1.0
      let overallRatio = (shipRatio + colonyRatio) / 2.0

      # Bonus for weak houses (ratio < vulnerability threshold = significantly weaker)
      if overallRatio < controller.rbaConfig.domestikos_offensive.weakness_threshold_vulnerable:
        priority += controller.rbaConfig.domestikos_offensive.weakness_priority_boost * 2.0  # Large bonus - easy prey
      elif overallRatio < 1.0:
        priority += controller.rbaConfig.domestikos_offensive.weakness_priority_boost   # Moderate bonus - vulnerable house

    vulnerableTargets.add(VulnerableTarget(
      systemId: visibleColony.systemId,
      enemyHouse: visibleColony.owner,
      priority: priority,
      colony: visibleColony  # Store for combat order selection
    ))

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Invasion: Found {enemyColoniesFound} enemy colonies, " &
          &"{vulnerableTargets.len} vulnerable targets")

  if vulnerableTargets.len == 0:
    logWarn(LogCategory.lcAI,
            &"{controller.houseId} Invasion: NO VULNERABLE TARGETS - all enemy colonies defended")
    return result

  # Sort targets by priority (highest first) - simple bubble approach
  for i in 0..<vulnerableTargets.len:
    for j in (i+1)..<vulnerableTargets.len:
      if vulnerableTargets[j].priority > vulnerableTargets[i].priority:
        swap(vulnerableTargets[i], vulnerableTargets[j])

  # Assign attackers to targets
  let maxAttacks = min(availableAttackers.len, vulnerableTargets.len)
  var attackedSystems: seq[SystemId] = @[]  # Track assigned targets

  for i in 0..<maxAttacks:
    let attacker = availableAttackers[i]
    let target = vulnerableTargets[i]

    # Skip if this fleet already assigned by intelligence targeting
    if attacker.fleetId in assignedFleets:
      continue

    # Skip if this target already has an attack order
    if target.systemId in attackedSystems:
      continue

    # NEW: Select appropriate combat order based on fleet composition and target defenses
    let combatOrder = selectCombatOrderType(
      controller,
      filtered,
      attacker.fleetId,
      attacker.shipCount,
      target.colony,  # Pass target colony for defense assessment
      intelSnapshot   # Phase 4.2: Pass intelligence for enhanced defense assessment
    )

    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Domestikos: {combatOrder} attack - fleet {attacker.fleetId} → " &
            &"enemy colony at system {target.systemId} (priority: {target.priority:.1f})")

    result.add(FleetOrder(
      fleetId: attacker.fleetId,
      orderType: combatOrder,
      targetSystem: some(target.systemId),
      priority: controller.rbaConfig.domestikos_offensive.priority_high, # High priority - opportunistic strikes
      roe: some(controller.rbaConfig.domestikos_offensive.roe_bombardment_priority)  # Main assault
    ))

    assignedFleets.incl(attacker.fleetId)  # Mark fleet as assigned
    attackedSystems.add(target.systemId)  # Mark system as attacked

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Invasion: Generated {result.len} invasion orders")

  return result
