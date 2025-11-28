## Build Requirements Module - Admiral Strategic Analysis
##
## Generates build requirements based on tactical gap analysis.
## Enables requirements-driven ship production instead of hardcoded thresholds.
##
## Key Features:
## - Defense gap detection with severity scoring
## - Reconnaissance gap analysis
## - Offensive readiness assessment
## - Priority-based requirement generation
## - Escalation for persistent gaps (adaptive AI)
##
## Integration: Called by Admiral module, consumed by build system

import std/[options, tables, sequtils, algorithm, strformat]
import ../../../common/system
import ../../../common/types/[core, units]
import ../../../engine/[gamestate, fog_of_war, logger, order_types, fleet, starmap, squadron]
import ../../common/types as ai_common_types  # For BuildObjective
import ../controller_types  # For BuildRequirements types
import ../config
import ./fleet_analysis

# Import types from parent Admiral module
{.push used.}
from ../admiral import FleetAnalysis, FleetUtilization
{.pop.}

# Re-export types from controller_types for convenience
export controller_types.RequirementPriority
export controller_types.RequirementType
export controller_types.BuildRequirement
export controller_types.BuildRequirements

type
  DefenseGap* = object
    ## Detailed defense gap analysis for a single colony
    colonySystemId*: SystemId
    severity*: RequirementPriority
    currentDefenders*: int
    recommendedDefenders*: int
    nearestDefenderDistance*: int
    colonyPriority*: float               # Production-based priority
    estimatedThreat*: float              # 0.0-1.0
    deploymentUrgency*: int              # Turns until critical
    turnsUndefended*: int                # Escalation tracker (for adaptive AI)

  ColonyDefenseHistory* = object
    ## Tracks defense history for escalation logic
    systemId*: SystemId
    turnsUndefended*: int
    lastDefenderAssigned*: int           # Turn number

# =============================================================================
# Gap Severity and Escalation
# =============================================================================

proc escalateSeverity*(
  baseSeverity: RequirementPriority,
  turnsUndefended: int
): RequirementPriority =
  ## Escalate gap severity based on persistence
  ## Creates adaptive AI: Fresh analysis each turn, but urgency increases
  ## if problem persists (engaging gameplay - not predictable patterns)
  ##
  ## Escalation thresholds (configurable in rba.toml):
  ## - 3+ turns: Low → Medium
  ## - 5+ turns: Medium → High
  ## - 7+ turns: High → Critical

  result = baseSeverity

  let config = globalRBAConfig.admiral
  case baseSeverity
  of RequirementPriority.Low:
    if turnsUndefended >= config.escalation_low_to_medium_turns:
      result = RequirementPriority.Medium
      logDebug(LogCategory.lcAI,
               &"Escalated gap severity: Low → Medium (undefended {turnsUndefended} turns)")
  of RequirementPriority.Medium:
    if turnsUndefended >= config.escalation_medium_to_high_turns:
      result = RequirementPriority.High
      logDebug(LogCategory.lcAI,
               &"Escalated gap severity: Medium → High (undefended {turnsUndefended} turns)")
  of RequirementPriority.High:
    if turnsUndefended >= config.escalation_high_to_critical_turns:
      result = RequirementPriority.Critical
      logWarn(LogCategory.lcAI,
              &"Escalated gap severity: High → CRITICAL (undefended {turnsUndefended} turns)")
  else:
    discard  # Critical and Deferred don't escalate

# =============================================================================
# Helper Functions
# =============================================================================

proc countDefendersAtColony(
  colony: Colony,
  defensiveAssignments: Table[FleetId, StandingOrder]
): int =
  ## Count how many fleets are assigned to defend this colony
  result = 0
  for fleetId, order in defensiveAssignments:
    if order.orderType == StandingOrderType.DefendSystem:
      if order.params.defendTargetSystem == colony.systemId:
        result += 1

proc getColonyDefenseHistory(
  systemId: SystemId,
  controller: AIController
): ColonyDefenseHistory =
  ## Get defense history for escalation tracking
  ## TODO: Implement persistent tracking in controller
  ## For now, return zero (no escalation) - will be enhanced later
  result = ColonyDefenseHistory(
    systemId: systemId,
    turnsUndefended: 0,
    lastDefenderAssigned: 0
  )

proc calculateColonyDefensePriority(
  colony: Colony,
  controller: AIController,
  starMap: StarMap
): float =
  ## Calculate defense priority for a colony (reused from defensive_ops)
  var priority = 0.0

  # Base priority: production value
  priority += colony.production.float * 0.5

  # Bonus: homeworld is always highest priority
  if colony.systemId == controller.homeworld:
    priority += 1000.0

  # Bonus: frontier colonies (farther from homeworld)
  let pathToHomeworld = starMap.findPath(colony.systemId, controller.homeworld, Fleet())
  if pathToHomeworld.found:
    let distance = pathToHomeworld.path.len
    priority += distance.float * 2.0

  return priority

proc estimateLocalThreat(
  systemId: SystemId,
  filtered: FilteredGameState,
  controller: AIController
): float =
  ## Estimate threat level at a system (0.0-1.0)
  ## Checks for enemy fleets within threat_assessment_radius
  result = 0.0

  let config = globalRBAConfig.admiral
  let radius = config.threat_assessment_radius

  # Check intelligence database for enemy fleets nearby
  for fleetId, history in filtered.ownHouse.intelligence.fleetMovementHistory:
    if history.owner == controller.houseId:
      continue  # Skip own fleets

    # Calculate distance to threat
    let pathResult = filtered.starMap.findPath(systemId, history.lastKnownLocation, Fleet())
    if pathResult.found:
      let distance = pathResult.path.len
      if distance <= radius:
        # Threat decreases with distance
        let threatContribution = 1.0 - (distance.float / radius.float)
        result += threatContribution * 0.3  # Each nearby enemy fleet adds threat

  # Cap at 1.0
  result = min(result, 1.0)

proc findNearestAvailableDefender(
  targetSystem: SystemId,
  analyses: seq[FleetAnalysis],
  filtered: FilteredGameState
): tuple[fleetId: FleetId, distance: int] =
  ## Find nearest idle/under-utilized fleet that can defend
  result = (fleetId: FleetId(""), distance: 999)

  for analysis in analyses:
    if analysis.utilization notin {FleetUtilization.Idle, FleetUtilization.UnderUtilized}:
      continue
    if not analysis.hasCombatShips:
      continue

    let pathResult = filtered.starMap.findPath(analysis.location, targetSystem, Fleet())
    if pathResult.found:
      let distance = pathResult.path.len
      if distance < result.distance:
        result = (analysis.fleetId, distance)

proc calculateGapSeverity(
  colonyPriority: float,
  threat: float,
  currentDefenders: int,
  nearestDefenderDistance: int,
  currentAct: GameAct,
  riskTolerance: float
): RequirementPriority =
  ## Calculate gap severity based on Act objectives + personality modulation
  ##
  ## Design Philosophy:
  ## - Acts define WHAT strategic objectives matter (expansion, war, etc.)
  ## - Personality defines HOW willing you are to take risks within that objective
  ##
  ## Act 1 (Land Grab): Everyone prioritizes expansion, but...
  ##   - High risk (0.7+): Pure expansion, no colony defense at all
  ##   - Medium risk (0.4-0.6): Homeworld-only, accept exposed colonies
  ##   - Low risk (<0.4): Defend as you expand, slower but safer
  ##
  ## Act 2+ (Rising Tensions/War): Defense becomes critical, but...
  ##   - High risk: Still aggressive, only defend high-value/threatened
  ##   - Medium risk: Balanced defense, standard thresholds
  ##   - Low risk: Cautious, defend everything proactively
  let config = globalRBAConfig.admiral

  # Homeworld always protected (all acts, all personalities)
  if colonyPriority > 500.0 and currentDefenders == 0:
    return RequirementPriority.Critical

  # Act 1: Expansion is primary objective - personality modulates defense willingness
  if currentAct == GameAct.Act1_LandGrab:
    # High risk: Pure expansion focus, skip all colony defense
    if riskTolerance >= 0.7:
      return RequirementPriority.Deferred

    # Medium risk: Homeworld-only, colonies fend for themselves
    if riskTolerance >= 0.4:
      return RequirementPriority.Deferred

    # Low risk: Cautious expansion - defend colonies as you claim them
    # (Falls through to Act 2+ logic below with lower thresholds)

  # Act 2+: Defense becomes critical strategic objective
  # Acts 2-4 all prioritize defense, but personality modulates HOW defensive

  # High-value colony (50+ industry) undefended - Act objective: Protect production
  if colonyPriority > config.high_priority_production_threshold.float and currentDefenders == 0:
    # Act says: High-value colonies MUST be defended
    # Personality says: HOW urgent is this?
    if riskTolerance >= 0.7:
      return RequirementPriority.Medium  # Aggressive: "Eventually, sure"
    else:
      return RequirementPriority.High    # Cautious/Balanced: "Right now!"

  # Active threat nearby - Act objective: Respond to enemy movements
  if threat > 0.5 and currentDefenders == 0:
    # Act says: Enemies nearby = defend
    # Personality says: How much risk do I accept?
    if riskTolerance >= 0.7:
      return RequirementPriority.Medium  # Aggressive: "I'll counter-attack instead"
    else:
      return RequirementPriority.High    # Cautious/Balanced: "Defend immediately!"
  elif threat > 0.3 and currentDefenders == 0:
    if riskTolerance < 0.4:
      return RequirementPriority.Medium  # Cautious: "Even minor threats matter"
    else:
      return RequirementPriority.Low     # Balanced/Aggressive: "Not urgent yet"

  # Distant defender - Act objective: Coverage efficiency
  if nearestDefenderDistance > config.defense_gap_max_distance:
    if currentDefenders == 0:
      if riskTolerance < 0.4:
        return RequirementPriority.Medium  # Cautious: "Too far, build local"
      else:
        return RequirementPriority.Low     # Balanced/Aggressive: "Acceptable gap"
    else:
      return RequirementPriority.Low

  # Standard undefended colony - Act objective varies by phase
  # Act 2: Preparation - defense matters but not urgent
  # Act 3/4: War - all colonies should be defended
  if currentDefenders == 0:
    if currentAct == GameAct.Act2_RisingTensions:
      # Act 2: Prepare defenses, not urgent yet
      if riskTolerance < 0.4:
        return RequirementPriority.Medium  # Cautious: "Prepare now"
      elif riskTolerance < 0.7:
        return RequirementPriority.Low     # Balanced: "Eventually"
      else:
        return RequirementPriority.Deferred  # Aggressive: "Focus on offense"
    else:
      # Act 3/4: War - defend everything (personality modulates priority)
      if riskTolerance < 0.4:
        return RequirementPriority.High    # Cautious: "Critical in war!"
      elif riskTolerance < 0.7:
        return RequirementPriority.Medium  # Balanced: "Important"
      else:
        return RequirementPriority.Low     # Aggressive: "Meh, offense > defense"

  # Under-defended (threat > defenders) - personality-scaled
  if threat > currentDefenders.float * 0.3:
    if riskTolerance < 0.4:
      return RequirementPriority.Low     # Cautious: "Reinforce proactively"
    else:
      return RequirementPriority.Deferred  # Balanced/Aggressive: "Acceptable risk"

  return RequirementPriority.Deferred

# =============================================================================
# Gap Analysis Functions
# =============================================================================

proc assessDefenseGaps*(
  filtered: FilteredGameState,
  analyses: seq[FleetAnalysis],
  defensiveAssignments: Table[FleetId, StandingOrder],
  controller: AIController,
  currentAct: GameAct
): seq[DefenseGap] =
  ## Identify defense gaps with severity scoring
  result = @[]

  for colony in filtered.ownColonies:
    # Count current defenders
    let currentDefenders = countDefendersAtColony(colony, defensiveAssignments)

    # Calculate colony priority
    let colonyPriority = calculateColonyDefensePriority(
      colony, controller, filtered.starMap
    )

    # Estimate local threat
    let threat = estimateLocalThreat(
      colony.systemId, filtered, controller
    )

    # Find nearest available defender
    let nearestDefender = findNearestAvailableDefender(
      colony.systemId, analyses, filtered
    )

    # Track persistence (for escalation)
    let turnsUndefended = getColonyDefenseHistory(
      colony.systemId, controller
    ).turnsUndefended

    # Calculate gap severity with escalation (personality-driven)
    let baseSeverity = calculateGapSeverity(
      colonyPriority, threat, currentDefenders, nearestDefender.distance,
      currentAct, controller.personality.risk_tolerance
    )
    let severity = escalateSeverity(baseSeverity, turnsUndefended)

    if severity != RequirementPriority.Deferred:
      result.add(DefenseGap(
        colonySystemId: colony.systemId,
        severity: severity,
        currentDefenders: currentDefenders,
        recommendedDefenders: max(1, int(threat * 3.0)),  # Scale with threat
        nearestDefenderDistance: nearestDefender.distance,
        colonyPriority: colonyPriority,
        estimatedThreat: threat,
        deploymentUrgency: nearestDefender.distance,  # Turns to arrive
        turnsUndefended: turnsUndefended
      ))

proc assessReconnaissanceGaps*(
  filtered: FilteredGameState,
  controller: AIController,
  currentAct: GameAct
): seq[DefenseGap] =
  ## Identify reconnaissance gaps (stale intel, unknown systems)
  ## Returns DefenseGap type for simplicity (reuses structure)
  result = @[]

  # For MVP: Simple scout count check
  # TODO: Enhance with stale intel detection, unknown system tracking

  var scoutCount = 0
  # Would get from analyses parameter - for now, defer to existing logic
  # for analysis in analyses:
  #   if analysis.hasScouts:
  #     scoutCount += 1

  # Act-based scout targets (from config)
  let targetScouts = case currentAct
    of GameAct.Act1_LandGrab:
      globalRBAConfig.orders.scout_count_act1
    of GameAct.Act2_RisingTensions:
      globalRBAConfig.orders.scout_count_act2
    else:
      globalRBAConfig.orders.scout_count_act3_plus

  # If we need more scouts, create a gap
  # (Simplified for MVP - full implementation would check intel coverage)
  # For now, defer to existing hardcoded logic
  result = @[]

proc assessOffensiveReadiness*(
  filtered: FilteredGameState,
  analyses: seq[FleetAnalysis],
  controller: AIController,
  currentAct: GameAct
): seq[DefenseGap] =
  ## Assess offensive capability and opportunities
  ## For MVP: Defer to existing offensive_ops logic
  ## TODO: Full implementation for Act 2+ offensive requirements
  result = @[]

proc assessStrategicAssets*(
  filtered: FilteredGameState,
  controller: AIController,
  currentAct: GameAct
): seq[BuildRequirement] =
  ## Comprehensive strategic asset assessment - Admiral requests ALL needed assets
  ## Covers: Fighters, Carriers, Starbases, Ground Units, Transports, Raiders, Scouts
  ## CFO decides what's affordable based on budget reality
  result = @[]

  let house = filtered.ownHouse
  let cstLevel = house.techTree.levels.constructionTech
  let personality = controller.personality

  # =============================================================================
  # CARRIERS & FIGHTERS (CST 3+)
  # =============================================================================
  if cstLevel >= 3:
    # Count existing carriers and fighters
    var carrierCount = 0
    var fighterCount = 0
    var totalCarrierCapacity = 0

    for fleet in filtered.ownFleets:
      for squadron in fleet.squadrons:
        if squadron.flagship.shipClass == ShipClass.Carrier:
          carrierCount += 1
          totalCarrierCapacity += 3  # Simplified: CV holds 3
          fighterCount += squadron.embarkedFighters.len
        elif squadron.flagship.shipClass == ShipClass.SuperCarrier:
          carrierCount += 1
          totalCarrierCapacity += 5  # Simplified: CX holds 5
          fighterCount += squadron.embarkedFighters.len

    # Count colony-based fighters
    for colony in filtered.ownColonies:
      fighterCount += colony.fighterSquadrons.len

    # Aggressive houses want carriers for power projection
    let wantsCarriers = personality.aggression > 0.5 or currentAct >= GameAct.Act2_RisingTensions

    if wantsCarriers:
      # Request carriers based on fleet size and game phase
      let targetCarriers = case currentAct
        of GameAct.Act1_LandGrab: 1  # One carrier for expansion
        of GameAct.Act2_RisingTensions: 2  # Two carriers for rising tensions
        of GameAct.Act3_TotalWar: 3  # Three carriers for total war
        of GameAct.Act4_Endgame: 4  # Four carriers for endgame

      if carrierCount < targetCarriers:
        let carrierCost = if cstLevel >= 5: 200 else: 120
        let carrierClass = if cstLevel >= 5: ShipClass.SuperCarrier else: ShipClass.Carrier

        result.add(BuildRequirement(
          requirementType: RequirementType.StrategicAsset,
          priority: RequirementPriority.Medium,
          shipClass: some(carrierClass),
          quantity: targetCarriers - carrierCount,
          buildObjective: BuildObjective.SpecialUnits,
          targetSystem: none(SystemId),
          estimatedCost: carrierCost * (targetCarriers - carrierCount),
          reason: &"Carrier strike force (have {carrierCount}/{targetCarriers})"
        ))

      # Request fighters to fill carrier capacity
      let targetFighters = totalCarrierCapacity
      if fighterCount < targetFighters:
        result.add(BuildRequirement(
          requirementType: RequirementType.StrategicAsset,
          priority: RequirementPriority.Low,
          shipClass: some(ShipClass.Fighter),
          quantity: targetFighters - fighterCount,
          buildObjective: BuildObjective.SpecialUnits,
          targetSystem: none(SystemId),
          estimatedCost: 20 * (targetFighters - fighterCount),
          reason: &"Fighter wings for carriers (have {fighterCount}/{targetFighters})"
        ))

  # =============================================================================
  # STARBASES (for fighter support & colony defense)
  # =============================================================================
  # Count existing starbases and fighter requirements
  var totalStarbases = 0
  var requiredStarbases = 0

  for colony in filtered.ownColonies:
    let operationalStarbases = colony.starbases.countIt(not it.isCrippled)
    totalStarbases += operationalStarbases

    let currentFighters = colony.fighterSquadrons.len
    # Rule: 1 starbase per 5 fighters (ceil(FS / 5))
    if currentFighters > 0:
      requiredStarbases += (currentFighters + 4) div 5  # Ceiling division

  if requiredStarbases > totalStarbases:
    result.add(BuildRequirement(
      requirementType: RequirementType.Infrastructure,
      priority: RequirementPriority.High,  # Urgent - prevents fighter disbanding
      shipClass: some(ShipClass.Starbase),
      quantity: requiredStarbases - totalStarbases,
      buildObjective: BuildObjective.Defense,
      targetSystem: none(SystemId),
      estimatedCost: 30 * (requiredStarbases - totalStarbases),  # Starbase cost
      reason: &"Starbase infrastructure for fighters (have {totalStarbases}, need {requiredStarbases})"
    ))

  # =============================================================================
  # TRANSPORTS (for invasion & logistics)
  # =============================================================================
  if cstLevel >= 3:  # Transports available at CST 3
    var transportCount = 0
    for fleet in filtered.ownFleets:
      transportCount += fleet.spaceLiftShips.countIt(it.shipClass == ShipClass.TroopTransport)

    # Aggressive houses want transports for invasion
    let wantsTransports = personality.aggression > 0.6 and currentAct >= GameAct.Act2_RisingTensions
    if wantsTransports:
      let targetTransports = filtered.ownColonies.len div 3  # ~1 transport per 3 colonies

      if transportCount < targetTransports:
        result.add(BuildRequirement(
          requirementType: RequirementType.StrategicAsset,
          priority: RequirementPriority.Low,
          shipClass: some(ShipClass.TroopTransport),
          quantity: targetTransports - transportCount,
          buildObjective: BuildObjective.SpecialUnits,
          targetSystem: none(SystemId),
          estimatedCost: 100 * (targetTransports - transportCount),
          reason: &"Invasion transports (have {transportCount}/{targetTransports})"
        ))

  # =============================================================================
  # GROUND UNITS (armies, marines, shields)
  # =============================================================================
  # TODO: Assess ground unit needs based on:
  # - Planetary shields for high-value colonies
  # - Armies for invasion-ready colonies
  # - Marines for offensive operations

  # =============================================================================
  # RAIDERS (for harassment)
  # =============================================================================
  if cstLevel >= 3:  # Raiders available at CST 3
    var raiderCount = 0
    for fleet in filtered.ownFleets:
      raiderCount += fleet.squadrons.countIt(it.flagship.shipClass == ShipClass.Raider)

    # Raider personalities want raiders
    let wantsRaiders = personality.aggression > 0.7 and currentAct >= GameAct.Act2_RisingTensions
    if wantsRaiders:
      let targetRaiders = 2  # Small raider force

      if raiderCount < targetRaiders:
        result.add(BuildRequirement(
          requirementType: RequirementType.StrategicAsset,
          priority: RequirementPriority.Low,
          shipClass: some(ShipClass.Raider),
          quantity: targetRaiders - raiderCount,
          buildObjective: BuildObjective.Military,
          targetSystem: none(SystemId),
          estimatedCost: 60 * (targetRaiders - raiderCount),
          reason: &"Raider harassment force (have {raiderCount}/{targetRaiders})"
        ))

# =============================================================================
# Requirement Generation
# =============================================================================

proc createDefenseRequirement(
  gap: DefenseGap,
  filtered: FilteredGameState
): BuildRequirement =
  ## Convert a defense gap into a build requirement
  let shipClass = ShipClass.Destroyer  # Default defender
  let shipStats = getShipStats(shipClass)  # Get stats from config/ships.toml
  let shipCost = shipStats.buildCost

  result = BuildRequirement(
    requirementType: RequirementType.DefenseGap,
    priority: gap.severity,
    shipClass: some(shipClass),
    quantity: gap.recommendedDefenders - gap.currentDefenders,
    buildObjective: BuildObjective.Defense,
    targetSystem: some(gap.colonySystemId),
    estimatedCost: shipCost * (gap.recommendedDefenders - gap.currentDefenders),
    reason: &"Defense gap at system {gap.colonySystemId} (priority={gap.colonyPriority:.1f}, threat={gap.estimatedThreat:.2f})"
  )

proc generateBuildRequirements*(
  filtered: FilteredGameState,
  analyses: seq[FleetAnalysis],
  defensiveAssignments: Table[FleetId, StandingOrder],
  controller: AIController,
  currentAct: GameAct
): BuildRequirements =
  ## Main entry point: Generate all build requirements from Admiral analysis

  # Assess gaps (personality-driven)
  let defenseGaps = assessDefenseGaps(filtered, analyses, defensiveAssignments, controller, currentAct)
  let reconGaps = assessReconnaissanceGaps(filtered, controller, currentAct)
  let offensiveNeeds = assessOffensiveReadiness(filtered, analyses, controller, currentAct)
  let strategicAssets = assessStrategicAssets(filtered, controller, currentAct)

  # Convert gaps to build requirements
  var requirements: seq[BuildRequirement] = @[]

  # Defense requirements
  for gap in defenseGaps:
    let req = createDefenseRequirement(gap, filtered)
    if req.quantity > 0:  # Only add if we actually need ships
      requirements.add(req)

  # Strategic asset requirements (fighters, carriers, starbases, transports, etc.)
  requirements.add(strategicAssets)

  # Reconnaissance requirements (deferred to existing logic for MVP)
  # Offensive requirements (deferred to existing logic for MVP)

  # Sort by priority (Critical > High > Medium > Low)
  requirements.sort(proc(a, b: BuildRequirement): int =
    if a.priority < b.priority: 1  # Reverse: Higher priority first
    elif a.priority > b.priority: -1
    else: 0
  )

  result = BuildRequirements(
    requirements: requirements,
    totalEstimatedCost: requirements.mapIt(it.estimatedCost).foldl(a + b, 0),
    criticalCount: requirements.countIt(it.priority == RequirementPriority.Critical),
    highCount: requirements.countIt(it.priority == RequirementPriority.High),
    generatedTurn: filtered.turn,
    act: currentAct
  )

  logInfo(LogCategory.lcAI,
          &"Admiral generated {requirements.len} build requirements " &
          &"(Critical={result.criticalCount}, High={result.highCount}, Total={result.totalEstimatedCost}PP)")
