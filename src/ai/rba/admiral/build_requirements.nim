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
  nearestDefenderDistance: int
): RequirementPriority =
  ## Calculate gap severity based on multiple factors
  let config = globalRBAConfig.admiral

  # Homeworld undefended = Critical
  if colonyPriority > 500.0 and currentDefenders == 0:
    return RequirementPriority.Critical

  # High-value colony (50+ industry) undefended = High
  if colonyPriority > config.high_priority_production_threshold.float and currentDefenders == 0:
    return RequirementPriority.High

  # Active threat nearby = elevate priority
  if threat > 0.5 and currentDefenders == 0:
    return RequirementPriority.High
  elif threat > 0.3 and currentDefenders == 0:
    return RequirementPriority.Medium

  # Distant defender = lower priority
  if nearestDefenderDistance > config.defense_gap_max_distance:
    if currentDefenders == 0:
      return RequirementPriority.Medium
    else:
      return RequirementPriority.Low

  # Standard undefended colony
  if currentDefenders == 0:
    return RequirementPriority.Medium

  # Under-defended (threat > defenders)
  if threat > currentDefenders.float * 0.3:
    return RequirementPriority.Low

  return RequirementPriority.Deferred

# =============================================================================
# Gap Analysis Functions
# =============================================================================

proc assessDefenseGaps*(
  filtered: FilteredGameState,
  analyses: seq[FleetAnalysis],
  defensiveAssignments: Table[FleetId, StandingOrder],
  controller: AIController
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

    # Calculate gap severity with escalation
    let baseSeverity = calculateGapSeverity(
      colonyPriority, threat, currentDefenders, nearestDefender.distance
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

  # Assess gaps
  let defenseGaps = assessDefenseGaps(filtered, analyses, defensiveAssignments, controller)
  let reconGaps = assessReconnaissanceGaps(filtered, controller, currentAct)
  let offensiveNeeds = assessOffensiveReadiness(filtered, analyses, controller, currentAct)

  # Convert gaps to build requirements
  var requirements: seq[BuildRequirement] = @[]

  # Defense requirements
  for gap in defenseGaps:
    let req = createDefenseRequirement(gap, filtered)
    if req.quantity > 0:  # Only add if we actually need ships
      requirements.add(req)

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
