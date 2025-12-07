## Domestikos Defense Gap Analysis Module
##
## Functions for analyzing defense gaps and calculating gap severity.
## Following DoD (Data-Oriented Design): Pure functions operating on data.
##
## Extracted from build_requirements.nim (lines 148-428)

import std/[options, tables, strformat]
import ../../../../common/types/[core, units]
import ../../../../engine/[gamestate, fog_of_war, logger, starmap, fleet]
import ../../../../engine/order_types  # For StandingOrder
import ../../common/types as ai_common_types  # For GameAct
import ../../controller_types  # For RequirementPriority, AIController
import ../../shared/intelligence_types  # For IntelligenceSnapshot
import ../../config
import ../fleet_analysis  # For FleetAnalysis
import ../intelligence_ops  # For estimateLocalThreatFromIntel
import ./types  # For DefenseGap, ColonyDefenseHistory

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

  let config = globalRBAConfig.domestikos
  case baseSeverity
  of RequirementPriority.Low:
    if turnsUndefended >= config.escalation_low_to_medium_turns:
      result = RequirementPriority.Medium
      logDebug(LogCategory.lcAI,
               &"Escalated gap severity: Low → Medium (undefended " &
               &"{turnsUndefended} turns)")
  of RequirementPriority.Medium:
    if turnsUndefended >= config.escalation_medium_to_high_turns:
      result = RequirementPriority.High
      logDebug(LogCategory.lcAI,
               &"Escalated gap severity: Medium → High (undefended " &
               &"{turnsUndefended} turns)")
  of RequirementPriority.High:
    if turnsUndefended >= config.escalation_high_to_critical_turns:
      result = RequirementPriority.Critical
      logWarn(LogCategory.lcAI,
              &"Escalated gap severity: High → CRITICAL (undefended " &
              &"{turnsUndefended} turns)")
  else:
    discard  # Critical and Deferred don't escalate

# =============================================================================
# Helper Functions
# =============================================================================

proc countDefendersAtColony*(
  colony: Colony,
  defensiveAssignments: Table[FleetId, StandingOrder]
): int =
  ## Count how many fleets are assigned to defend this colony
  result = 0
  for fleetId, order in defensiveAssignments:
    if order.orderType == StandingOrderType.DefendSystem:
      if order.params.defendTargetSystem == colony.systemId:
        result += 1

proc getColonyDefenseHistory*(
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
  let pathToHomeworld = starMap.findPath(
    colony.systemId, controller.homeworld, Fleet())
  if pathToHomeworld.found:
    let distance = pathToHomeworld.path.len
    priority += distance.float * 2.0

  return priority

# estimateLocalThreat extracted to intelligence_ops.nim for file size management

proc findNearestAvailableDefender(
  targetSystem: SystemId,
  analyses: seq[FleetAnalysis],
  filtered: FilteredGameState
): tuple[fleetId: FleetId, distance: int] =
  ## Find nearest idle/under-utilized fleet that can defend
  result = (fleetId: FleetId(""), distance: 999)

  for analysis in analyses:
    if analysis.utilization notin {
      FleetUtilization.Idle, FleetUtilization.UnderUtilized}:
      continue
    if not analysis.hasCombatShips:
      continue

    let pathResult = filtered.starMap.findPath(
      analysis.location, targetSystem, Fleet())
    if pathResult.found:
      let distance = pathResult.path.len
      if distance < result.distance:
        result = (analysis.fleetId, distance)

proc calculateGapSeverity(
  colonyPriority: float,
  threat: float,
  currentDefenders: int,
  nearestDefenderDistance: int,
  currentAct: ai_common_types.GameAct,
  riskTolerance: float
): RequirementPriority =
  ## Calculate gap severity based on Act objectives + personality modulation
  ##
  ## Design Philosophy:
  ## - Acts define WHAT strategic objectives matter (expansion, war, etc.)
  ## - Personality defines HOW willing you are to take risks within that
  ##   objective
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
  let config = globalRBAConfig.domestikos

  # Homeworld always protected (all acts, all personalities)
  if colonyPriority > 500.0 and currentDefenders == 0:
    return RequirementPriority.Critical

  # Act 1: Expansion is primary objective - personality modulates defense
  if currentAct == ai_common_types.GameAct.Act1_LandGrab:
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

  # High-value colony (50+ industry) undefended
  if colonyPriority > config.high_priority_production_threshold.float and
     currentDefenders == 0:
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
      return RequirementPriority.Medium  # Aggressive: counter-attack instead
    else:
      return RequirementPriority.High    # Cautious/Balanced: Defend!
  elif threat > 0.3 and currentDefenders == 0:
    if riskTolerance < 0.4:
      return RequirementPriority.Medium  # Cautious: minor threats matter
    else:
      return RequirementPriority.Low     # Balanced/Aggressive: Not urgent

  # Distant defender - Act objective: Coverage efficiency
  if nearestDefenderDistance > config.defense_gap_max_distance:
    if currentDefenders == 0:
      if riskTolerance < 0.4:
        return RequirementPriority.Medium  # Cautious: Too far, build local
      else:
        return RequirementPriority.Low     # Balanced: Acceptable gap
    else:
      return RequirementPriority.Low

  # Standard undefended colony - Act objective varies by phase
  # Act 2: Preparation - defense matters but not urgent
  # Act 3/4: War - all colonies should be defended
  if currentDefenders == 0:
    if currentAct == ai_common_types.GameAct.Act2_RisingTensions:
      # Act 2: Prepare defenses, not urgent yet
      if riskTolerance < 0.4:
        return RequirementPriority.Medium  # Cautious: Prepare now
      elif riskTolerance < 0.7:
        return RequirementPriority.Low     # Balanced: Eventually
      else:
        return RequirementPriority.Deferred  # Aggressive: Focus on offense
    else:
      # Act 3/4: War - defend everything (personality modulates priority)
      if riskTolerance < 0.4:
        return RequirementPriority.High    # Cautious: Critical in war!
      elif riskTolerance < 0.7:
        return RequirementPriority.Medium  # Balanced: Important
      else:
        return RequirementPriority.Low     # Aggressive: offense > defense

  # Under-defended (threat > defenders) - personality-scaled
  if threat > currentDefenders.float * 0.3:
    if riskTolerance < 0.4:
      return RequirementPriority.Low     # Cautious: Reinforce proactively
    else:
      return RequirementPriority.Deferred  # Balanced/Aggressive: Acceptable

  return RequirementPriority.Deferred

# =============================================================================
# Gap Analysis Functions
# =============================================================================

proc assessDefenseGaps*(
  filtered: FilteredGameState,
  analyses: seq[FleetAnalysis],
  defensiveAssignments: Table[FleetId, StandingOrder],
  controller: AIController,
  currentAct: ai_common_types.GameAct,
  intelSnapshot: IntelligenceSnapshot
): seq[DefenseGap] =
  ## Identify defense gaps with severity scoring
  ## Phase B+: Uses IntelligenceSnapshot for enhanced threat assessment
  result = @[]

  for colony in filtered.ownColonies:
    # Count current defenders
    let currentDefenders = countDefendersAtColony(colony, defensiveAssignments)

    # Calculate colony priority
    let colonyPriority = calculateColonyDefensePriority(
      colony, controller, filtered.starMap
    )

    # Estimate local threat using enhanced intelligence (Phase B+)
    let threat = estimateLocalThreatFromIntel(
      colony.systemId, intelSnapshot
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
