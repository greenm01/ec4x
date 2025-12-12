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
  controller: AIController,
  intelSnapshot: Option[IntelligenceSnapshot] = none(IntelligenceSnapshot)
): seq[FleetOrder] =
  ## Generate intelligence gathering orders for scouts
  ## Uses reconnaissance recommendations from Drungarius intelligence
  result = @[]

  # Find idle fleets for reconnaissance missions
  var availableScouts: seq[FleetAnalysis] = @[]
  var availableAnyFleet: seq[FleetAnalysis] = @[]

  for analysis in analyses:
    if analysis.utilization == FleetUtilization.Idle:
      if analysis.hasScouts:
        availableScouts.add(analysis)
      else:
        # Non-scout fleets can do ViewWorld missions
        availableAnyFleet.add(analysis)

  if availableScouts.len == 0 and availableAnyFleet.len == 0:
    return result

  # Priority 1: Use Drungarius reconnaissance recommendations
  var intelTargets: seq[tuple[systemId: SystemId, orderType: FleetOrderType, priority: int, description: string]] = @[]

  if intelSnapshot.isSome:
    let snapshot = intelSnapshot.get()
    for target in snapshot.espionage.highPriorityTargets:
      if target.systemId.isNone:
        continue

      # Convert EspionageTarget to internal format
      let orderType = case target.targetType
        of EspionageTargetType.ColonySpy: FleetOrderType.SpyPlanet
        of EspionageTargetType.SystemSpy: FleetOrderType.SpySystem
        of EspionageTargetType.StarbaseHack: FleetOrderType.HackStarbase
        of EspionageTargetType.ScoutRecon: FleetOrderType.ViewWorld

      # Map priority to numeric value
      let priorityValue = case target.priority
        of RequirementPriority.Critical: 100
        of RequirementPriority.High: 90
        of RequirementPriority.Medium: 70
        of RequirementPriority.Low: 50
        of RequirementPriority.Deferred: 30

      intelTargets.add((
        systemId: target.systemId.get(),
        orderType: orderType,
        priority: priorityValue,
        description: target.reason
      ))

    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Domestikos: Received {intelTargets.len} reconnaissance targets from Drungarius")

  # Fallback: Find intelligence targets from visible enemies if Drungarius provided none
  if intelTargets.len == 0:
    logDebug(LogCategory.lcAI,
             &"{controller.houseId} Domestikos: No Drungarius recommendations, using visibility-based targeting")

    var targetedSystems = initHashSet[SystemId]()

    # Priority 1: Hack enemy starbases (high-value intelligence)
    for visibleFleet in filtered.visibleFleets:
      if visibleFleet.owner == controller.houseId:
        continue  # Skip own fleets

      # Check if fleet is a starbase (stationary defensive installation)
      var isStarbase = false
      for visibleColony in filtered.visibleColonies:
        if visibleFleet.location == visibleColony.systemId and visibleColony.owner == visibleFleet.owner:
          isStarbase = true
          break

      if isStarbase:
        if visibleFleet.location in targetedSystems:
          continue

        intelTargets.add((
          systemId: visibleFleet.location,
          orderType: FleetOrderType.HackStarbase,
          priority: 100,
          description: "hack starbase"
        ))
        targetedSystems.incl(visibleFleet.location)

    # Priority 2: Spy on enemy colonies (gather defense/production intel)
    for visibleColony in filtered.visibleColonies:
      if visibleColony.owner == controller.houseId:
        continue  # Skip own colonies

      if visibleColony.systemId in targetedSystems:
        continue

      let isEnemy = filtered.ownHouse.diplomaticRelations.isEnemy(visibleColony.owner)
      let priority = if isEnemy: 90 else: 70

      intelTargets.add((
        systemId: visibleColony.systemId,
        orderType: FleetOrderType.SpyPlanet,
        priority: priority,
        description: "spy planet"
      ))
      targetedSystems.incl(visibleColony.systemId)

    # Priority 3: Reconnaissance of enemy systems (general intel)
    for visibleFleet in filtered.visibleFleets:
      if visibleFleet.owner == controller.houseId:
        continue  # Skip own fleets

      if visibleFleet.location in targetedSystems:
        continue

      intelTargets.add((
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

  # Assign fleets to intel targets based on mission requirements
  var scoutIndex = 0
  var anyFleetIndex = 0

  for target in intelTargets:
    # Scout-only missions: SpyPlanet, SpySystem, HackStarbase
    let requiresScout = target.orderType in [FleetOrderType.SpyPlanet, FleetOrderType.SpySystem, FleetOrderType.HackStarbase]

    var assignedFleet: Option[FleetAnalysis] = none(FleetAnalysis)

    if requiresScout:
      # Must use scouts for spy missions
      if scoutIndex < availableScouts.len:
        let scout = availableScouts[scoutIndex]
        # Skip oversized scout fleets (optimal: 3-6 scouts for mesh network bonus)
        if scout.shipCount <= 6:
          assignedFleet = some(scout)
          scoutIndex += 1
        else:
          logDebug(LogCategory.lcAI,
                   &"{controller.houseId} Domestikos: Skipping oversized scout fleet {scout.fleetId} " &
                   &"({scout.shipCount} scouts, optimal is 3-6)")
          scoutIndex += 1
          continue
    else:
      # ViewWorld: Any fleet can do this - prefer scouts, then any idle fleet
      if scoutIndex < availableScouts.len:
        assignedFleet = some(availableScouts[scoutIndex])
        scoutIndex += 1
      elif anyFleetIndex < availableAnyFleet.len:
        assignedFleet = some(availableAnyFleet[anyFleetIndex])
        anyFleetIndex += 1

    # Create order if we found a suitable fleet
    if assignedFleet.isSome:
      let fleet = assignedFleet.get()
      logInfo(LogCategory.lcAI,
              &"{controller.houseId} Domestikos: Intelligence mission - fleet {fleet.fleetId} " &
              &"→ {target.description} at system {target.systemId}")

      result.add(FleetOrder(
        fleetId: fleet.fleetId,
        orderType: target.orderType,
        targetSystem: some(target.systemId),
        priority: 85,  # Higher than merge, lower than tactical
        roe: some(4)   # Probing mission: Engage with 2:1 advantage, retreat if outgunned
      ))

  return result

proc selectCombatOrderType(
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
      # Check spacelift ships for loaded Marines
      for ship in fleet.spaceLiftShips:
        if ship.shipClass == ShipClass.TroopTransport:
          if ship.cargo.cargoType == CargoType.Marines and ship.cargo.quantity > 0:
            hasLoadedTransports = true
            totalMarines += ship.cargo.quantity
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
        # Rough estimate: 50 strength per ship
        defendingFleetStrength += visibleFleet.estimatedShipCount.get() * 50
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
    # Fallback to basic estimate
    if targetColony.estimatedDefenses.isSome:
      groundDefenses = targetColony.estimatedDefenses.get() div 2

  # === STEP 3: CHOOSE TACTIC ===

  # Check if we have transports - affects available tactics
  if not hasLoadedTransports or totalMarines == 0:
    # No loaded transports - can ONLY bombard (no invasion possible)
    return FleetOrderType.Bombard

  # If we DON'T have space superiority, bombard from range (too risky to close for invasion)
  if not hasSpaceSuperiority:
    return FleetOrderType.Bombard

  # WE HAVE SPACE SUPERIORITY - choose tactic based on ground defenses only
  # Philosophy: With space control, ground defenses just slow us down, they don't stop us

  if groundDefenses == 0:
    # No ground resistance - fast capture
    return FleetOrderType.Blitz

  elif groundDefenses <= 3:
    # Light ground defenses - Blitz (bombardment + simultaneous landing)
    return FleetOrderType.Blitz

  elif groundDefenses <= 8 and totalMarines >= 4:
    # Moderate ground defenses, sufficient Marines - Invade (systematic approach)
    return FleetOrderType.Invade

  elif groundDefenses > 8 or totalMarines < 4:
    # Heavy ground defenses OR insufficient Marines
    # BLOCKADE STRATEGY: Economic warfare instead of costly ground assault
    # Rationale: Blockade cripples production, forces defender to respond, cheaper than bombardment
    # Use blockade for high-value colonies (estimated industry > 5)
    if targetColony.estimatedIndustry.isSome and targetColony.estimatedIndustry.get() >= 5:
      return FleetOrderType.BlockadePlanet  # Economic siege
    else:
      # Low-value colony - bombard to soften, we'll capture later
      return FleetOrderType.Bombard

  else:
    # Fallback: Bombard to soften defenses
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

proc findSuitableInvasionFleet(
  analyses: seq[FleetAnalysis],
  requiredForceScore: int,
  filtered: FilteredGameState,
  targetSystem: SystemId
): Option[FleetId] =
  ## Find available fleet with sufficient strength for invasion (Phase F)
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

    # Use the engine's actual combat strength calculation
    let fleetStrength = fleet.combatStrength().float

    # Strength requirement (1.0x - take risks for opportunity)
    if fleetStrength < float(requiredForceScore) * 1.0: # Even match - aggressive stance
      continue

    # Distance/ETA check (reject if > configured max turns)
    let pathResult = filtered.starMap.findPath(analysis.location, targetSystem, fleet)
    if pathResult.found:
      let eta = pathResult.path.len
      if eta > globalRBAConfig.domestikos.max_invasion_eta_turns:
        logDebug(LogCategory.lcAI, &"Domestikos: Fleet {fleet.id} too distant for invasion ({eta} turns > {globalRBAConfig.domestikos.max_invasion_eta_turns}).")
        continue  # Too distant
    else:
      logDebug(LogCategory.lcAI, &"Domestikos: No path found for fleet {fleet.id} to {targetSystem}.")
      continue  # No path

    return some(analysis.fleetId)

  return none(FleetId)

# =============================================================================
# Phase 2: Multi-Turn Invasion Campaign Functions
# =============================================================================

proc hasRecentIntel(
  filtered: FilteredGameState,
  systemId: SystemId,
  maxAge: int = 5
): bool =
  ## Check if we have fresh intelligence on a system (within maxAge turns)
  let currentTurn = filtered.turn

  if filtered.ownHouse.intelligence.colonyReports.hasKey(systemId):
    let report = filtered.ownHouse.intelligence.colonyReports[systemId]
    return (currentTurn - report.gatheredTurn) <= maxAge

  return false

proc estimateGroundBatteries(
  filtered: FilteredGameState,
  systemId: SystemId
): int =
  ## Estimate remaining ground batteries from intelligence
  ## Returns 0 if no intel available
  if not filtered.ownHouse.intelligence.colonyReports.hasKey(systemId):
    return 5  # Conservative estimate if no intel

  let report = filtered.ownHouse.intelligence.colonyReports[systemId]
  # Batteries based on defense strength (rough estimate)
  # Each ground defense unit might have ~1 battery
  return report.defenses

proc updateCampaignPhase(
  campaign: var InvasionCampaign,
  filtered: FilteredGameState,
  controller: AIController
): bool =
  ## Update campaign phase based on current state
  ## Returns false if campaign should be abandoned

  let currentTurn = filtered.turn
  let turnsStalled = currentTurn - campaign.lastActionTurn
  let config = globalRBAConfig.domestikos

  # Check for stall (no action for N turns)
  if turnsStalled > config.campaign_stall_timeout:
    campaign.abandonReason = some("Stalled for " & $turnsStalled & " turns")
    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Campaign: Abandoning campaign on " &
            &"{campaign.targetSystem} - stalled")
    return false

  # Check if target still exists and is enemy-owned
  var targetExists = false
  var targetOwner: HouseId
  for colony in filtered.visibleColonies:
    if colony.systemId == campaign.targetSystem:
      targetExists = true
      targetOwner = colony.owner
      break

  if not targetExists:
    campaign.abandonReason = some("Target system no longer visible")
    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Campaign: Abandoning campaign on " &
            &"{campaign.targetSystem} - target lost")
    return false

  # Check if we captured the target!
  if targetOwner == controller.houseId:
    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Campaign: SUCCESS! Captured " &
            &"{campaign.targetSystem}")
    campaign.phase = InvasionCampaignPhase.Consolidation
    return true

  # Check if target was captured by someone else
  if targetOwner != campaign.targetOwner:
    campaign.abandonReason = some("Target captured by " & $targetOwner)
    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Campaign: Abandoning campaign on " &
            &"{campaign.targetSystem} - captured by another house")
    return false

  # Phase transition logic
  case campaign.phase
  of InvasionCampaignPhase.Scouting:
    # Transition to Bombardment when we have fresh intel
    if hasRecentIntel(filtered, campaign.targetSystem, maxAge = 3):
      campaign.phase = InvasionCampaignPhase.Bombardment
      campaign.bombardmentRounds = 0
      logInfo(LogCategory.lcAI,
              &"{controller.houseId} Campaign: {campaign.targetSystem} " &
              &"Scouting → Bombardment")

  of InvasionCampaignPhase.Bombardment:
    # Estimate batteries remaining
    let batteries = estimateGroundBatteries(filtered, campaign.targetSystem)
    campaign.estimatedBatteriesRemaining = batteries

    # Transition to Invasion when batteries destroyed or max rounds reached
    if batteries <= 0 or
       campaign.bombardmentRounds >= config.campaign_bombardment_max:
      campaign.phase = InvasionCampaignPhase.Invasion
      logInfo(LogCategory.lcAI,
              &"{controller.houseId} Campaign: {campaign.targetSystem} " &
              &"Bombardment → Invasion (batteries: {batteries}, " &
              &"rounds: {campaign.bombardmentRounds})")

  of InvasionCampaignPhase.Invasion:
    # Stay in Invasion phase until successful (checked above) or stalled
    discard

  of InvasionCampaignPhase.Consolidation:
    # Campaign complete - should be cleaned up soon
    discard

  return true

proc generateCampaignOrder(
  campaign: var InvasionCampaign,
  filtered: FilteredGameState,
  analyses: seq[FleetAnalysis],
  controller: AIController,
  intelSnapshot: Option[IntelligenceSnapshot] = none(IntelligenceSnapshot)
): Option[FleetOrder] =
  ## Generate phase-appropriate order for campaign
  ## Phase 4.2: Enhanced with intelligence for defense assessment
  ## Updates campaign.lastActionTurn if order generated

  # Find best available fleet (prioritize assigned fleets, then nearby idle)
  var bestFleet: Option[FleetAnalysis] = none(FleetAnalysis)
  var bestDistance = 999

  # First pass: check assigned fleets
  for fleetId in campaign.assignedFleets:
    for analysis in analyses:
      if analysis.fleetId == fleetId:
        # Check if fleet is available
        if analysis.utilization in {FleetUtilization.Idle,
                                     FleetUtilization.UnderUtilized}:
          let dist = calculateDistance(filtered.starMap,
                                       analysis.location,
                                       campaign.targetSystem)
          if dist < bestDistance:
            bestFleet = some(analysis)
            bestDistance = dist
        break

  # Second pass: find nearby idle fleets if no assigned fleet available
  if bestFleet.isNone:
    for analysis in analyses:
      if analysis.utilization == FleetUtilization.Idle:
        let dist = calculateDistance(filtered.starMap,
                                     analysis.location,
                                     campaign.targetSystem)
        if dist < bestDistance:
          bestFleet = some(analysis)
          bestDistance = dist

  if bestFleet.isNone:
    logDebug(LogCategory.lcAI,
             &"{controller.houseId} Campaign: No available fleet for " &
             &"{campaign.targetSystem}")
    return none(FleetOrder)

  let fleet = bestFleet.get()

  # Find target colony for defense estimates
  var targetColony: Option[VisibleColony] = none(VisibleColony)
  for colony in filtered.visibleColonies:
    if colony.systemId == campaign.targetSystem:
      targetColony = some(colony)
      break

  if targetColony.isNone:
    logDebug(LogCategory.lcAI,
             &"{controller.houseId} Campaign: Target {campaign.targetSystem} " &
             &"not visible")
    return none(FleetOrder)

  # Generate phase-appropriate order
  var order: FleetOrder

  case campaign.phase
  of InvasionCampaignPhase.Scouting:
    # Spy mission to gather intelligence
    order = FleetOrder(
      fleetId: fleet.fleetId,
      orderType: FleetOrderType.SpyPlanet,
      targetSystem: some(campaign.targetSystem),
      priority: 90,  # High priority - campaign order
      roe: some(4)   # Cautious - gather intel and retreat
    )
    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Campaign: Scouting order - fleet " &
            &"{fleet.fleetId} → {campaign.targetSystem}")

  of InvasionCampaignPhase.Bombardment:
    # Bombard to destroy batteries
    order = FleetOrder(
      fleetId: fleet.fleetId,
      orderType: FleetOrderType.Bombard,
      targetSystem: some(campaign.targetSystem),
      priority: 95,  # Very high priority - active campaign
      roe: some(8)   # Aggressive - destroy ground defenses
    )
    campaign.bombardmentRounds += 1
    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Campaign: Bombardment order (round " &
            &"{campaign.bombardmentRounds}) - fleet {fleet.fleetId} → " &
            &"{campaign.targetSystem}")

  of InvasionCampaignPhase.Invasion:
    # Choose appropriate invasion tactic
    let orderType = selectCombatOrderType(
      filtered,
      fleet.fleetId,
      fleet.shipCount,
      targetColony.get(),
      intelSnapshot  # Phase 4.2: Pass intelligence for defense assessment
    )

    let roe = case orderType
      of FleetOrderType.Blitz: 9   # Aggressive blitz
      of FleetOrderType.Invade: 10 # All-out invasion
      else: 8                       # Fallback to bombardment

    order = FleetOrder(
      fleetId: fleet.fleetId,
      orderType: orderType,
      targetSystem: some(campaign.targetSystem),
      priority: 100,  # Maximum priority - invasion assault
      roe: some(roe)
    )
    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Campaign: {orderType} order - fleet " &
            &"{fleet.fleetId} → {campaign.targetSystem}")

  of InvasionCampaignPhase.Consolidation:
    # Defend newly captured system
    order = FleetOrder(
      fleetId: fleet.fleetId,
      orderType: FleetOrderType.Patrol,  # Defend and intercept in system
      targetSystem: some(campaign.targetSystem),
      priority: 80,  # Important - protect conquest
      roe: some(6)   # Defensive posture
    )
    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Campaign: Consolidation order - fleet " &
            &"{fleet.fleetId} → defend {campaign.targetSystem}")

  # Update campaign action timestamp
  campaign.lastActionTurn = filtered.turn

  # Add fleet to assigned list if not already there
  if fleet.fleetId notin campaign.assignedFleets:
    campaign.assignedFleets.add(fleet.fleetId)

  return some(order)

# =============================================================================
# Counter-Attack Order Generation
# =============================================================================

proc generateCounterAttackOrders*(
  filtered: FilteredGameState,
  analyses: seq[FleetAnalysis],
  controller: var AIController,  # Phase 2: Mutable for campaign tracking
  intelSnapshot: Option[IntelligenceSnapshot] = none(IntelligenceSnapshot)  # Phase F: Intelligence integration
): seq[FleetOrder] =
  ## Generate counter-attack orders against vulnerable enemy targets
  ## Phase 2: Multi-turn campaign tracking with Bombardment → Invasion sequences
  ## Phase F: Intelligence-driven targeting using military.vulnerableTargets and economic.highValueTargets
  ## Fallback: Visibility-based targeting when intelligence unavailable
  result = @[]

  # ==========================================================================
  # PHASE 2: ACTIVE CAMPAIGN EXECUTION (PRIORITY 1)
  # ==========================================================================
  # Process active campaigns FIRST before creating new ones
  # This enables multi-turn Bombardment → Invasion sequences

  var completedCampaigns: seq[int] = @[]  # Track campaigns to remove
  var abandonedCampaigns: seq[int] = @[]

  logDebug(LogCategory.lcAI,
           &"{controller.houseId} Campaign: Processing {controller.activeCampaigns.len} active campaigns")

  for i in 0..<controller.activeCampaigns.len:
    var campaign = controller.activeCampaigns[i]

    # Update campaign state and check if should continue
    if not updateCampaignPhase(campaign, filtered, controller):
      # Campaign should be abandoned
      abandonedCampaigns.add(i)
      continue

    # Check if campaign is complete (Consolidation phase)
    if campaign.phase == InvasionCampaignPhase.Consolidation:
      completedCampaigns.add(i)
      # Still generate consolidation order, then mark for cleanup
      discard

    # Generate order for this campaign
    let campaignOrder = generateCampaignOrder(campaign, filtered, analyses,
                                               controller, intelSnapshot)
    if campaignOrder.isSome:
      result.add(campaignOrder.get())
      # Update campaign in controller (important for state tracking)
      controller.activeCampaigns[i] = campaign

  # Remove completed/abandoned campaigns (reverse order to preserve indices)
  for i in countdown(controller.activeCampaigns.len - 1, 0):
    if i in completedCampaigns:
      logInfo(LogCategory.lcAI,
              &"{controller.houseId} Campaign: Completed campaign on " &
              &"{controller.activeCampaigns[i].targetSystem}")
      controller.activeCampaigns.delete(i)
    elif i in abandonedCampaigns:
      logInfo(LogCategory.lcAI,
              &"{controller.houseId} Campaign: Abandoned campaign on " &
              &"{controller.activeCampaigns[i].targetSystem} - " &
              &"{controller.activeCampaigns[i].abandonReason.get(\"\")}")
      controller.activeCampaigns.delete(i)

  # If we generated campaign orders, return them (campaigns take priority)
  if result.len > 0:
    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Campaign: Generated {result.len} campaign orders")
    return result

  # ==========================================================================
  # PHASE 2: NEW CAMPAIGN CREATION (PRIORITY 2)
  # ==========================================================================
  # Create new campaigns from intelligence vulnerableTargets
  # Can be disabled when GOAP handles strategic invasion planning

  let config = globalRBAConfig.domestikos
  let goapConfig = globalRBAConfig.goap
  let maxConcurrentCampaigns = config.max_concurrent_campaigns

  # Check if RBA campaigns are disabled in favor of GOAP planning
  let skipCampaigns = controller.goapEnabled and goapConfig.disable_rba_campaigns_with_goap

  if not skipCampaigns and controller.activeCampaigns.len < maxConcurrentCampaigns:
    if intelSnapshot.isSome:
      let snapshot = intelSnapshot.get()
      let availableSlots = maxConcurrentCampaigns - controller.activeCampaigns.len

      logDebug(LogCategory.lcAI,
               &"{controller.houseId} Campaign: {availableSlots} campaign " &
               &"slots available, {snapshot.military.vulnerableTargets.len} " &
               &"vulnerable targets")

      # Create new campaigns from top vulnerable targets
      var campaignsCreated = 0
      for opportunity in snapshot.military.vulnerableTargets:
        if campaignsCreated >= availableSlots:
          break

        # Check if we already have a campaign targeting this system
        var alreadyTargeted = false
        for existing in controller.activeCampaigns:
          if existing.targetSystem == opportunity.systemId:
            alreadyTargeted = true
            break

        if alreadyTargeted:
          continue

        # Create new campaign
        let newCampaign = InvasionCampaign(
          targetSystem: opportunity.systemId,
          targetOwner: opportunity.owner,
          phase: InvasionCampaignPhase.Scouting,  # Start with intel gathering
          assignedFleets: @[],
          startTurn: filtered.turn,
          lastActionTurn: filtered.turn - 1,  # -1 so first update triggers action
          bombardmentRounds: 0,
          estimatedBatteriesRemaining: opportunity.estimatedDefenses div 10,
          priority: calculateInvasionPriority(opportunity, opportunity.intelQuality),
          abandonReason: none(string)
        )

        controller.activeCampaigns.add(newCampaign)
        campaignsCreated += 1

        logInfo(LogCategory.lcAI,
                &"{controller.houseId} Campaign: NEW campaign on " &
                &"{opportunity.systemId} ({opportunity.owner}) - " &
                &"vulnerability {opportunity.vulnerability:.2f}, " &
                &"value {opportunity.estimatedValue}")

  # ==========================================================================
  # EXISTING LOGIC: TACTICAL INVASION ORDERS (PRIORITY 3)
  # ==========================================================================
  # Original intelligence-driven and visibility-based targeting
  # Used for immediate tactical opportunities when no campaigns active

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
        let fleetId = assignedFleet.get()
        result.add(FleetOrder(
          fleetId: fleetId,
          orderType: FleetOrderType.Invade,  # Intelligence targets warrant invasion
          targetSystem: some(opportunity.systemId),
          priority: int(priority),
          roe: some(8) # Main assault: fight through resistance. As per dev log.
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
              roe: some(8) # Main assault: fight through resistance. As per dev log.
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
      of 1..2: 300.0  # Immediate neighbors - ATTACK! (highest priority)
      of 3..4: 150.0  # Close neighbors - strong opportunity
      of 5..6: 50.0   # Moderate distance - still viable
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

      # Bonus for weak houses (ratio < 0.7 = significantly weaker)
      if overallRatio < 0.7:
        priority += 150.0  # Large bonus - easy prey
      elif overallRatio < 1.0:
        priority += 75.0   # Moderate bonus - vulnerable house

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
      priority: 90, # High priority - opportunistic strikes
      roe: some(8)  # Main assault: fight through resistance. As per dev log.
    ))

    assignedFleets.incl(attacker.fleetId)  # Mark fleet as assigned
    attackedSystems.add(target.systemId)  # Mark system as attacked

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Invasion: Generated {result.len} invasion orders")

  return result
