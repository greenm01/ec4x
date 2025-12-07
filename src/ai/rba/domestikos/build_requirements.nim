## Build Requirements Module - Domestikos Strategic Analysis
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
## Integration: Called by Domestikos module, consumed by build system

import std/[options, tables, sequtils, algorithm, strformat, strutils]
import ../../../common/types/[core, units]
import ../../../engine/[gamestate, fog_of_war, logger, order_types, fleet, starmap, squadron, spacelift]
import ../../../engine/economy/config_accessors  # For centralized cost accessors
import ../../../engine/economy/types as econ_types  # For ConstructionType
import ../../../engine/intelligence/types as intel_types  # For CombatOutcome
import ../../common/types as ai_common_types  # For BuildObjective
import ../controller_types  # For BuildRequirements types
import ../shared/intelligence_types  # For IntelligenceSnapshot
import ../config
import ./fleet_analysis
import ./intelligence_ops  # Extracted: estimateLocalThreat
import ./unit_priority  # Priority scoring for unit selection

# ============================================================================
# UNIVERSAL AFFORDABILITY HELPERS
# ============================================================================
# Budget-aware unit construction helpers for all expensive units (>100PP)
# Prevents requesting unaffordable units and scales quantity based on treasury
# ============================================================================

proc calculateAffordabilityFactor*(
  unitCost: int,
  quantity: int,
  treasury: int,
  currentAct: ai_common_types.GameAct
): float =
  ## Universal affordability scaling for expensive units
  ## Returns 0.0-1.0 multiplier based on cost-to-treasury ratio
  ##
  ## Prevents requesting expensive units when economy can't support them.
  ## Act-specific thresholds ensure early-game focus on expansion.
  ##
  ## Example:
  ##   Turn 1 (Act1, 208PP treasury):
  ##     2x Battlecruiser (200PP total) → 15% max = 31PP → 0% affordable
  ##   Turn 15 (Act2, 1500PP treasury):
  ##     2x Battleship (300PP total) → 25% max = 375PP → 100% affordable

  let totalCost = unitCost * quantity

  # Avoid division by zero
  if treasury <= 0 or quantity <= 0:
    return 0.0

  let costRatio = float(totalCost) / float(treasury)

  # Act-specific thresholds (how much of treasury we're willing to spend per request)
  # DOUBLED from original values - original thresholds too conservative
  # These are per-request, not total spending caps (multiple requests can compound)
  let maxCostRatio = case currentAct
    of ai_common_types.GameAct.Act1_LandGrab: 0.30        # Act 1: 30% per request (was 15%)
    of ai_common_types.GameAct.Act2_RisingTensions: 0.50  # Act 2: 50% per request (was 25%)
    of ai_common_types.GameAct.Act3_TotalWar: 0.70        # Act 3: 70% per request (was 40%)
    of ai_common_types.GameAct.Act4_Endgame: 0.90         # Act 4: 90% per request (was 50%)

  if costRatio > maxCostRatio:
    # Too expensive - scale down quantity
    return max(0.0, maxCostRatio / costRatio)
  else:
    # Affordable - request full quantity
    return 1.0

proc adjustPriorityForAffordability*(
  basePriority: RequirementPriority,
  unitCost: int,
  quantity: int,
  treasury: int,
  currentAct: ai_common_types.GameAct,
  unitType: string  # For logging
): RequirementPriority =
  ## Adjust priority downward if unit is unaffordable
  ## Applied to expensive units (>100PP total cost)
  ##
  ## Economic health check: Can we afford 2x the cost?
  ## - If yes: Keep original priority
  ## - If no: Downgrade by one level (preserves Critical priority)
  ##
  ## Rationale: 2x cost threshold ensures we can afford unit + still do other things

  let totalCost = unitCost * quantity

  # Cheap units (<100PP) - no adjustment
  if totalCost < 100:
    return basePriority

  # Economic health check: can we afford 1.5x the cost?
  # RELAXED from 2x to 1.5x - original threshold too strict
  # Ensures we can afford unit + have 50% buffer for other needs
  let economicHealthy = treasury >= (totalCost * 3 div 2)  # 1.5x using integer math

  if not economicHealthy and basePriority != RequirementPriority.Critical:
    # Poor economy - downgrade by one level
    let adjusted = case basePriority
      of RequirementPriority.High: RequirementPriority.Medium
      of RequirementPriority.Medium: RequirementPriority.Low
      of RequirementPriority.Low: RequirementPriority.Deferred
      else: basePriority

    logDebug(LogCategory.lcAI,
             &"Priority adjustment: {unitType} ({totalCost}PP) unaffordable " &
             &"(treasury={treasury}PP, need 1.5x={totalCost * 3 div 2}PP), {basePriority} → {adjusted}")
    return adjusted
  else:
    return basePriority

# FleetAnalysis and FleetUtilization types now imported from ./fleet_analysis directly

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

  let config = globalRBAConfig.domestikos
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

# estimateLocalThreat extracted to intelligence_ops.nim for file size management

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
  let config = globalRBAConfig.domestikos

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
  currentAct: GameAct,
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

proc assessReconnaissanceGaps*(
  filtered: FilteredGameState,
  controller: AIController,
  currentAct: GameAct,
  intelSnapshot: IntelligenceSnapshot
): seq[BuildRequirement] =
  ## Intelligence-driven scout requirements based on intel coverage
  ## Calculates need from stale intel systems and enemy house coverage
  result = @[]

  # Count current scouts
  var scoutCount = 0
  for fleet in filtered.ownFleets:
    scoutCount += fleet.squadrons.countIt(it.flagship.shipClass == ShipClass.Scout)

  # Intelligence-driven targeting
  let staleIntelSystems = intelSnapshot.espionage.staleIntelSystems
  let enemyHouses = intelSnapshot.military.enemyMilitaryCapability.len

  # Calculate need: 1 scout per 2 stale systems + 1 per enemy house (min 3)
  var targetScouts = max(3, staleIntelSystems.len div 2) + min(3, enemyHouses)

  # Act 1: Minimal scouts (any ship can explore)
  if currentAct == ai_common_types.GameAct.Act1_LandGrab:
    targetScouts = min(targetScouts, 3)

  if scoutCount < targetScouts:
    let scoutCost = getShipConstructionCost(ShipClass.Scout)
    let needed = targetScouts - scoutCount
    let priority = if staleIntelSystems.len > 5:
      RequirementPriority.High
    elif staleIntelSystems.len > 2:
      RequirementPriority.Medium
    else:
      RequirementPriority.Low

    result.add(BuildRequirement(
      requirementType: RequirementType.ReconnaissanceGap,
      priority: priority,
      shipClass: some(ShipClass.Scout),
      quantity: needed,
      buildObjective: ai_common_types.BuildObjective.Reconnaissance,
      estimatedCost: scoutCost * needed,
      reason: &"Intel coverage (have {scoutCount}/{targetScouts}, " &
              &"{staleIntelSystems.len} stale systems)"
    ))

proc assessExpansionNeeds*(
  filtered: FilteredGameState,
  controller: AIController,
  currentAct: GameAct
): seq[BuildRequirement] =
  ## Intelligence-driven ETAC requirements for colonization
  ## Only active in Acts 1-2 (expansion phases)
  result = @[]

  # Only Acts 1-2 (expansion phase)
  if currentAct notin {ai_common_types.GameAct.Act1_LandGrab, ai_common_types.GameAct.Act2_RisingTensions}:
    return

  # Count uncolonized visible systems
  var uncolonizedVisible = 0
  for systemId, visSystem in filtered.visibleSystems:
    # Check if this system has any colony (ours or enemy)
    var hasColony = false

    # Check our colonies
    for colony in filtered.ownColonies:
      if colony.systemId == systemId:
        hasColony = true
        break

    # Check visible enemy colonies
    if not hasColony:
      for visColony in filtered.visibleColonies:
        if visColony.systemId == systemId:
          hasColony = true
          break

    if not hasColony:
      uncolonizedVisible += 1

  if uncolonizedVisible == 0:
    return  # No targets

  # Count ETACs (in fleets + under construction + queued)
  var etacCount = 0
  for fleet in filtered.ownFleets:
    etacCount += fleet.spaceLiftShips.countIt(it.shipClass == ShipClass.ETAC)

  # Also count ETACs under construction (prevents duplicate orders)
  for colony in filtered.ownColonies:
    if colony.underConstruction.isSome:
      let project = colony.underConstruction.get()
      if project.projectType == econ_types.ConstructionType.Ship and
         project.itemId == "ETAC":
        etacCount += 1
    # Also check construction queue
    for queuedProject in colony.constructionQueue:
      if queuedProject.projectType == econ_types.ConstructionType.Ship and
         queuedProject.itemId == "ETAC":
        etacCount += 1

  # Target: Based on map rings (one ETAC per ring for parallel colonization)
  # Standard game: 4 players = 4 rings → 4 ETACs max
  # Large game: 8 players = 8 rings → 8 ETACs max
  let mapRings = int(filtered.starMap.numRings)
  let targetETACs = min(mapRings, (uncolonizedVisible + 1) div 2)

  logDebug(LogCategory.lcAI,
           &"ETAC assessment: have {etacCount}, target {targetETACs}, " &
           &"mapRings {mapRings}, uncolonizedVisible {uncolonizedVisible}")

  if etacCount < targetETACs:
    let etacCost = getShipConstructionCost(ShipClass.ETAC)
    let needed = targetETACs - etacCount
    let priority = if currentAct == ai_common_types.GameAct.Act1_LandGrab:
      RequirementPriority.High  # Land grab urgency
    else:
      RequirementPriority.Medium

    result.add(BuildRequirement(
      requirementType: RequirementType.ExpansionSupport,
      priority: priority,
      shipClass: some(ShipClass.ETAC),
      quantity: needed,
      buildObjective: ai_common_types.BuildObjective.Expansion,
      estimatedCost: etacCost * needed,
      reason: &"Expansion (have {etacCount}/{targetETACs} ETACs, " &
              &"{uncolonizedVisible} systems visible)"
    ))

proc assessOffensiveReadiness*(
  filtered: FilteredGameState,
  controller: AIController,
  currentAct: GameAct,
  intelSnapshot: IntelligenceSnapshot
): seq[BuildRequirement] =
  ## Personality-modulated offensive building
  ## Aggressive: Build proactively; Defensive/Economic: Only build for opportunities
  result = @[]

  let personality = controller.personality
  let isAggressive = personality.aggression > 0.2  # Lowered from 0.7 to enable more personalities (Aggressive, Balanced, Economic)
  let opportunities = intelSnapshot.military.vulnerableTargets
  let cstLevel = filtered.ownHouse.techTree.levels.constructionTech

  # Check if transports available (CST 3+)
  if cstLevel < 3:
    return

  # Count current offensive assets
  var transportCount = 0
  var loadedMarines = 0

  for fleet in filtered.ownFleets:
    transportCount += fleet.spaceLiftShips.countIt(it.shipClass == ShipClass.TroopTransport)
    for spaceLiftShip in fleet.spaceLiftShips:
      if spaceLiftShip.cargo.cargoType == CargoType.Marines:
        loadedMarines += spaceLiftShip.cargo.quantity

  # Aggressive: Build proactively (Act 2+ only - no transports in Act 1)
  if isAggressive and currentAct >= GameAct.Act2_RisingTensions:
    let targetTransports = max(2, filtered.ownColonies.len div 3)
    let targetMarines = targetTransports * 1  # 1 marine per transport capacity

    if transportCount < targetTransports:
      let needed = targetTransports - transportCount
      result.add(BuildRequirement(
        requirementType: RequirementType.OffensivePrep,
        priority: RequirementPriority.Medium,
        shipClass: some(ShipClass.TroopTransport),
        quantity: needed,
        buildObjective: ai_common_types.BuildObjective.SpecialUnits,
        estimatedCost: getShipConstructionCost(ShipClass.TroopTransport) * needed,
        reason: &"Offensive capability (aggressive, have {transportCount}/{targetTransports})"
      ))

    if loadedMarines < targetMarines and transportCount > 0:
      let needed = targetMarines - loadedMarines
      result.add(BuildRequirement(
        requirementType: RequirementType.OffensivePrep,
        priority: RequirementPriority.Medium,  # Match transports in importance
        shipClass: none(ShipClass),
        itemId: some("Marine"),
        quantity: needed,
        buildObjective: ai_common_types.BuildObjective.Military,
        estimatedCost: getMarineBuildCost() * needed,
        reason: &"Marines (aggressive, have {loadedMarines}/{targetMarines})"
      ))

  # Defensive/Economic: Only build for opportunities
  elif opportunities.len > 0:
    let opp = opportunities[0]  # Highest priority target
    let requiredMarines = max(2, int(float(opp.estimatedDefenses) * 1.5))
    let requiredTransports = (requiredMarines + 0) div 1  # 1 marine per transport

    if transportCount < requiredTransports:
      result.add(BuildRequirement(
        requirementType: RequirementType.OffensivePrep,
        priority: RequirementPriority.High,
        shipClass: some(ShipClass.TroopTransport),
        quantity: requiredTransports - transportCount,
        targetSystem: some(opp.systemId),
        buildObjective: ai_common_types.BuildObjective.SpecialUnits,
        estimatedCost: getShipConstructionCost(ShipClass.TroopTransport) * (requiredTransports - transportCount),
        reason: &"Invasion of {opp.systemId} (need {requiredTransports})"
      ))

    if loadedMarines < requiredMarines:
      result.add(BuildRequirement(
        requirementType: RequirementType.OffensivePrep,
        priority: RequirementPriority.High,
        shipClass: none(ShipClass),
        itemId: some("Marine"),
        quantity: requiredMarines - loadedMarines,
        targetSystem: some(opp.systemId),
        buildObjective: ai_common_types.BuildObjective.Military,
        estimatedCost: getMarineBuildCost() * (requiredMarines - loadedMarines),
        reason: &"Marines for {opp.systemId} (need {requiredMarines})"
      ))

proc assessStrategicAssets*(
  filtered: FilteredGameState,
  controller: AIController,
  currentAct: GameAct,
  intelSnapshot: IntelligenceSnapshot
): seq[BuildRequirement] =
  ## Comprehensive strategic asset assessment - Domestikos requests ALL needed assets
  ## Covers:
  ##   - Capital Ships: Dreadnoughts, Battleships, Battlecruisers (main battle line)
  ##   - Carriers & Fighters: Power projection and strike warfare
  ##   - Starbases: Infrastructure for fighter support & colony defense
  ##   - Ground Units: Armies, Marines, Planetary Shields, Ground Batteries
  ##   - Transports: Invasion capability and logistics
  ##   - Raiders: Harassment and asymmetric warfare
  ## Treasurer decides what's affordable based on budget reality
  result = @[]

  let house = filtered.ownHouse
  let cstLevel = house.techTree.levels.constructionTech
  let personality = controller.personality

  logDebug(LogCategory.lcAI,
           &"{controller.houseId} Domestikos: Generating strategic assets (Act={currentAct}, CST={cstLevel})")

  # =============================================================================
  # CARRIERS & FIGHTERS (CST 3+)
  # =============================================================================
  # BUDGETING STRATEGY:
  #   - Colony-defense fighters = Military budget (treat like escorts: DD, CA)
  #   - Carriers = SpecialUnits budget (strategic mobility platforms)
  #   - Embarked fighters = SpecialUnits budget (offensive strike capability)
  #
  # BUILD STRATEGY:
  #   - Build fighters FIRST for colony defense (cheap, immediate value)
  #   - Build carriers LATER for offensive projection (expensive, strategic)
  if cstLevel >= 3:
    # Count existing carriers and fighters
    var carrierCount = 0
    var fighterCount = 0
    var colonyFighterCount = 0
    var embarkedFighterCount = 0

    for fleet in filtered.ownFleets:
      for squadron in fleet.squadrons:
        if squadron.flagship.shipClass == ShipClass.Carrier:
          carrierCount += 1
          embarkedFighterCount += squadron.embarkedFighters.len
        elif squadron.flagship.shipClass == ShipClass.SuperCarrier:
          carrierCount += 1
          embarkedFighterCount += squadron.embarkedFighters.len

    # Count colony-based fighters (available for defense or later embarkation)
    for colony in filtered.ownColonies:
      colonyFighterCount += colony.fighterSquadrons.len

    fighterCount = colonyFighterCount + embarkedFighterCount

    # PHASE 1: Request fighters for colony defense (Military budget)
    # These are defensive assets, like escorts (DD/CA)
    # Intelligence-driven fighter requirements based on threat assessment
    var threatenedColonies = 0
    var highThreatColonies = 0

    for colony in filtered.ownColonies:
      let threat = estimateLocalThreat(colony.systemId, filtered, controller)
      if threat > 0.2:
        threatenedColonies += 1
      if threat > 0.5:
        highThreatColonies += 1

    # Calculate defensive fighter needs: 1 per threatened colony + 2 per high-threat colony
    let defensiveFighters = threatenedColonies + (highThreatColonies * 2)

    # Calculate offensive fighter needs: Based on aggression + vulnerable targets + Act
    # Aggressive houses want fighters for carrier strike operations
    var offensiveFighters = 0
    if personality.aggression > 0.5 and currentAct >= GameAct.Act2_RisingTensions:
      # Base offensive fighter complement: 4 fighters (1 carrier load)
      offensiveFighters = 4

      # Scale up with vulnerable targets (intelligence-driven offensive planning)
      let opportunities = intelSnapshot.military.vulnerableTargets
      if opportunities.len > 0:
        # +2 fighters per vulnerable target (cap at +8)
        offensiveFighters += min(8, opportunities.len * 2)

      # Act scaling: More fighters in later Acts (total war requires strike capability)
      if currentAct >= GameAct.Act3_TotalWar:
        offensiveFighters += 4  # +4 fighters in Act 3 (8-12 total)

    # CRITICAL FIX: Calculate carrier/starbase-based fighter needs
    # Problem: Carriers/Starbases built with 0 fighters (can't operate empty!)
    # Solution: Ensure existing carriers/starbases have fighters to load

    # Count carriers and starbases to calculate capacity
    var currentCarriers = 0
    var currentSuperCarriers = 0
    for fleet in filtered.ownFleets:
      for squadron in fleet.squadrons:
        case squadron.flagship.shipClass
        of ShipClass.Carrier: currentCarriers += 1
        of ShipClass.SuperCarrier: currentSuperCarriers += 1
        else: discard

    # Count operational starbases from colonies (now facilities, not ships)
    var currentStarbases = 0
    for colony in filtered.ownColonies:
      for starbase in colony.starbases:
        if not starbase.isCrippled:
          currentStarbases += 1

    let carrierCapacity = currentCarriers * 4 + currentSuperCarriers * 8  # 4 fighters per carrier, 8 per super
    let starbaseCapacity = currentStarbases * 5  # 5 fighters per starbase (colony-based facilities)
    let totalCapacity = carrierCapacity + starbaseCapacity
    let capacityFighters = if totalCapacity > 0:
      min(20, totalCapacity)  # Build up to capacity (cap at 20 total)
    else:
      0

    # Target fighters: MAXIMUM of defensive, offensive, OR capacity needs
    # Must fill existing carriers/starbases even if no threats detected
    let targetFighters = min(20, max(defensiveFighters, max(offensiveFighters, capacityFighters)))

    if fighterCount < targetFighters:
      let fighterCost = getShipConstructionCost(ShipClass.Fighter)
      let neededFighters = targetFighters - fighterCount

      # Request fighters individually to enable incremental fulfillment
      # Individual requests allow Treasurer to build what budget permits
      for i in 0..<neededFighters:
        let req = BuildRequirement(
          requirementType: RequirementType.DefenseGap,  # Defense fighters fill defensive gap
          priority: RequirementPriority.Medium,
          shipClass: some(ShipClass.Fighter),
          quantity: 1,  # Request one at a time for incremental fulfillment
          buildObjective: BuildObjective.Military,  # Use Military budget, not SpecialUnits
          targetSystem: none(SystemId),
          estimatedCost: fighterCost,
          reason: &"Fighter #{i+1} (have {fighterCount+i}/{targetFighters}, " &
                  &"defense={defensiveFighters}, offense={offensiveFighters})"
        )
        result.add(req)

      let fighterPurpose = if offensiveFighters > defensiveFighters:
        &"offensive strike ops ({offensiveFighters} needed)"
      else:
        &"colony defense ({defensiveFighters} needed, {threatenedColonies} threatened)"

      logInfo(LogCategory.lcAI, &"Domestikos requests: {neededFighters}x Fighter ({fighterPurpose}, {fighterCost}PP each)")

    # PHASE 2: Request carriers for offensive projection (SpecialUnits budget)
    # Carriers are strategic mobility platforms - only build if we have fighters
    # Intelligence-driven: Fighter-based + opportunity-based for aggressive AI
    let fightersPerCarrier = 4  # Typical carrier capacity
    let baseCarriers = if fighterCount >= 2: (fighterCount + 3) div 4 else: 0  # 1 carrier per 4 fighters

    # Add carriers for offensive opportunities (aggressive personalities)
    let opportunities = intelSnapshot.military.vulnerableTargets
    let offensiveCarriers = if personality.aggression > 0.7 and opportunities.len > 0:
      min(2, opportunities.len div 2)  # 1 carrier per 2 opportunities
    else:
      0

    let targetCarriers = min(6, baseCarriers + offensiveCarriers)

    if carrierCount < targetCarriers and fighterCount >= 2:  # Only request carriers if we have fighters
      let carrierClass = if cstLevel >= 5: ShipClass.SuperCarrier else: ShipClass.Carrier
      let carrierCost = getShipConstructionCost(carrierClass)

      # BUDGET-AWARE: Scale quantity based on treasury affordability
      let idealCarriers = targetCarriers - carrierCount
      let carrierAffordability = calculateAffordabilityFactor(
        carrierCost, idealCarriers, filtered.ownHouse.treasury, currentAct
      )
      let requestedCarriers = max(0, int(float(idealCarriers) * carrierAffordability))

      # Only request if we can afford at least one carrier
      if requestedCarriers > 0:
        # BUDGET-AWARE: Adjust priority downward if unaffordable
        let carrierPriority = adjustPriorityForAffordability(
          RequirementPriority.Low,  # Base priority: expensive, strategic (not urgent)
          carrierCost, requestedCarriers,
          filtered.ownHouse.treasury, currentAct,
          &"{requestedCarriers}x {carrierClass}"
        )

        let req = BuildRequirement(
          requirementType: RequirementType.StrategicAsset,
          priority: carrierPriority,
          shipClass: some(carrierClass),
          quantity: requestedCarriers,
          buildObjective: BuildObjective.SpecialUnits,  # Carriers use SpecialUnits budget
          targetSystem: none(SystemId),
          estimatedCost: carrierCost * requestedCarriers,
          reason: &"Carrier mobility (have {carrierCount}/{targetCarriers}, requesting {requestedCarriers}/{idealCarriers}, " &
                  &"{fighterCount} fighters, {opportunities.len} opportunities)"
        )
        logInfo(LogCategory.lcAI,
                &"Domestikos requests: {req.quantity}x {carrierClass} ({req.estimatedCost}PP, priority={carrierPriority}, " &
                &"affordability={int(carrierAffordability*100)}%, treasury={filtered.ownHouse.treasury}PP) - intelligence-driven")
        result.add(req)
      else:
        logInfo(LogCategory.lcAI,
                &"Domestikos: {idealCarriers}x {carrierClass} unaffordable (cost={carrierCost * idealCarriers}PP, " &
                &"treasury={filtered.ownHouse.treasury}PP, have {fighterCount} fighters without carrier support)")

  # =============================================================================
  # STARBASES (Moved to Eparch - facilities, not ships)
  # =============================================================================
  # Starbases are now immobile facilities managed by Eparch (economic advisor)
  # Eparch handles facility construction: Spaceport → Shipyard → Starbase
  # Domestikos no longer builds Starbases (they're not ships anymore)

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
        let transportCost = getShipConstructionCost(ShipClass.TroopTransport)
        let req = BuildRequirement(
          requirementType: RequirementType.StrategicAsset,
          priority: RequirementPriority.Low,
          shipClass: some(ShipClass.TroopTransport),
          quantity: targetTransports - transportCount,
          buildObjective: BuildObjective.SpecialUnits,
          targetSystem: none(SystemId),
          estimatedCost: transportCost * (targetTransports - transportCount),
          reason: &"Invasion transports (have {transportCount}/{targetTransports})"
        )
        logInfo(LogCategory.lcAI, &"Domestikos requests: {req.quantity}x TroopTransport ({req.estimatedCost}PP) - {req.reason}")
        result.add(req)

  # =============================================================================
  # CAPITAL SHIPS (DNs, BBs, BCs - main battle line)
  # =============================================================================
  # Count existing capital ships
  var dreadnoughtCount = 0
  var battleshipCount = 0
  var battlecruiserCount = 0

  for fleet in filtered.ownFleets:
    for squadron in fleet.squadrons:
      case squadron.flagship.shipClass
      of ShipClass.Dreadnought: dreadnoughtCount += 1
      of ShipClass.Battleship: battleshipCount += 1
      of ShipClass.Battlecruiser: battlecruiserCount += 1
      else: discard

  # Capital ship requirements based on game phase and personality
  let totalCapitalShips = dreadnoughtCount + battleshipCount + battlecruiserCount

  # Target capital ship count scales with game phase
  let targetCapitalShips = case currentAct
    of GameAct.Act1_LandGrab: 2  # Small core fleet
    of GameAct.Act2_RisingTensions: 4  # Expanding fleet
    of GameAct.Act3_TotalWar: 8  # Major battle fleet
    of GameAct.Act4_Endgame: 12  # Massive endgame fleet

  if totalCapitalShips < targetCapitalShips:
    # Choose capital ship type based on CST level and personality
    let capitalClass =
      if cstLevel >= 5 and personality.aggression > 0.7:
        ShipClass.Dreadnought  # Aggressive: DNs for firepower
      elif cstLevel >= 4:
        ShipClass.Battleship  # Standard: BBs for balance
      else:
        ShipClass.Battlecruiser  # Early: BCs for mobility
    let capitalCost = getShipConstructionCost(capitalClass)

    # BUDGET-AWARE: Scale quantity based on treasury affordability
    let idealQuantity = targetCapitalShips - totalCapitalShips
    let affordabilityFactor = calculateAffordabilityFactor(
      capitalCost, idealQuantity, filtered.ownHouse.treasury, currentAct
    )
    let requestedQuantity = max(0, int(float(idealQuantity) * affordabilityFactor))

    # Only request if we can afford at least one capital ship
    if requestedQuantity > 0:
      # Priority scales with Act: capitals are strategic investments, not urgent in land grab
      # Act 1: Low (focus on expansion/defense)
      # Act 2: Medium (building military strength)
      # Act 3+: High/Critical (war footing)
      let basePriority = case currentAct
        of GameAct.Act1_LandGrab:
          RequirementPriority.Low  # Land grab: capitals are long-term goals
        of GameAct.Act2_RisingTensions:
          RequirementPriority.Medium  # Rising tensions: build up fleet
        of GameAct.Act3_TotalWar:
          RequirementPriority.High  # Total war: capitals critical for combat
        of GameAct.Act4_Endgame:
          RequirementPriority.Critical  # Endgame: max military power

      # BUDGET-AWARE: Adjust priority downward if unaffordable
      let capitalPriority = adjustPriorityForAffordability(
        basePriority, capitalCost, requestedQuantity,
        filtered.ownHouse.treasury, currentAct,
        &"{requestedQuantity}x {capitalClass}"
      )

      let req = BuildRequirement(
        requirementType: RequirementType.OffensivePrep,
        priority: capitalPriority,
        shipClass: some(capitalClass),
        quantity: requestedQuantity,
        buildObjective: BuildObjective.Military,
        targetSystem: none(SystemId),
        estimatedCost: capitalCost * requestedQuantity,
        reason: &"Capital ship battle line (have {totalCapitalShips}/{targetCapitalShips}, requesting {requestedQuantity}/{idealQuantity})"
      )
      logInfo(LogCategory.lcAI,
              &"Domestikos requests: {req.quantity}x {capitalClass} ({req.estimatedCost}PP, priority={capitalPriority}, " &
              &"affordability={int(affordabilityFactor*100)}%, treasury={filtered.ownHouse.treasury}PP) - {req.reason}")
      result.add(req)
    else:
      logInfo(LogCategory.lcAI,
              &"Domestikos: {idealQuantity}x {capitalClass} unaffordable (cost={capitalCost * idealQuantity}PP, " &
              &"treasury={filtered.ownHouse.treasury}PP, max_spend={int(0.15 * float(filtered.ownHouse.treasury))}PP in {currentAct})")

  # =============================================================================
  # GROUND UNITS (armies, marines, shields, batteries)
  # =============================================================================
  # Count existing ground forces
  var totalArmies = 0
  var totalMarines = 0  # Marines at colonies (not loaded on transports)
  var totalGroundBatteries = 0
  var shieldedColonies = 0

  for colony in filtered.ownColonies:
    totalArmies += colony.armies
    totalMarines += colony.marines  # Colony-based marines
    totalGroundBatteries += colony.groundBatteries
    if colony.planetaryShieldLevel > 0:
      shieldedColonies += 1

  # Count loaded marines on transports
  var loadedMarines = 0
  for fleet in filtered.ownFleets:
    for spaceLiftShip in fleet.spaceLiftShips:
      if spaceLiftShip.cargo.cargoType == CargoType.Marines:
        loadedMarines += spaceLiftShip.cargo.quantity

  let totalMarinesAll = totalMarines + loadedMarines  # Total marines (colony + loaded)

  # Planetary shields for high-value colonies (homeworld + major systems)
  let highValueColonies = filtered.ownColonies.filterIt(
    it.systemId == controller.homeworld or it.populationUnits >= 10
  )

  let targetShields = highValueColonies.len
  if shieldedColonies < targetShields:
    let planetaryShieldCost = getPlanetaryShieldCost(1)  # SLD1 shields

    # BUDGET-AWARE: Only request shields if treasury can support them (2x cost minimum)
    # RELAXED from 3x to 2x - more forgiving for shield requests
    let idealShields = targetShields - shieldedColonies
    let totalShieldCost = planetaryShieldCost * idealShields

    # 2x cost check: need 2x total cost in treasury to consider affordable
    if filtered.ownHouse.treasury >= (totalShieldCost * 2):
      # BUDGET-AWARE: Adjust priority downward if unaffordable (2x cost check)
      let adjustedPriority = adjustPriorityForAffordability(
        RequirementPriority.Medium, planetaryShieldCost, idealShields,
        filtered.ownHouse.treasury, currentAct,
        &"{idealShields}x PlanetaryShield (high-value colonies)"
      )

      let req = BuildRequirement(
        requirementType: RequirementType.Infrastructure,
        priority: adjustedPriority,
        shipClass: none(ShipClass),
        itemId: some("PlanetaryShield"),
        quantity: idealShields,
        buildObjective: BuildObjective.Defense,
        targetSystem: none(SystemId),
        estimatedCost: totalShieldCost,
        reason: &"Planetary shields for high-value colonies (have {shieldedColonies}/{targetShields})"
      )
      logInfo(LogCategory.lcAI,
              &"Domestikos requests: {req.quantity}x PlanetaryShield ({req.estimatedCost}PP, priority={adjustedPriority}, " &
              &"treasury={filtered.ownHouse.treasury}PP) - {req.reason}")
      result.add(req)
    else:
      logDebug(LogCategory.lcAI,
               &"Domestikos: {idealShields}x PlanetaryShield for high-value colonies deferred " &
               &"(cost={totalShieldCost}PP, treasury={filtered.ownHouse.treasury}PP < 3x threshold={totalShieldCost * 3}PP)")

  # Ground batteries for colony defense - ACT-AWARE + INTELLIGENCE-DRIVEN + UNDEFENDED PENALTY AWARE
  # Phased buildup matching economic capacity: 1 (Act1) → 2 (Act2) → 3 (Act3+)
  let groundBatteryCost = getBuildingCost("GroundBattery")
  for colony in filtered.ownColonies:
    let currentBatteries = colony.groundBatteries  # int, not seq

    # PHASE F: Check if colony is completely undefended (no armies, marines, or batteries)
    # Undefended colonies incur +50% prestige penalty when lost (-15 vs -10)
    let isUndefended = (colony.armies == 0 and colony.marines == 0 and currentBatteries == 0)

    # ACT-AWARE: Baseline target matches economic capacity
    # Act 1: 1 battery (13PP after cost reduction, affordable for expanding colonies)
    # Act 2: 2 batteries (26PP, mature economy)
    # Act 3+: 3 batteries (39PP, full fortification with economic surplus)
    let baselineTarget = case currentAct
      of GameAct.Act1_LandGrab: 1  # Minimal baseline: expansion priority
      of GameAct.Act2_RisingTensions: 2  # Moderate: consolidation
      of GameAct.Act3_TotalWar, GameAct.Act4_Endgame: 3  # Full: war economy

    # INTELLIGENCE-DRIVEN: Calculate threat at this colony
    let threat = estimateLocalThreat(colony.systemId, filtered, controller)

    # Threat-based escalation: threatened colonies get full defenses regardless of Act
    let targetBatteries = if threat > 0.5:
      3  # Emergency: full fortification
    elif threat > 0.2:
      max(baselineTarget, 2)  # Elevated threat: at least 2 batteries
    elif isUndefended:
      1  # PHASE F: Undefended colonies need at least 1 battery to avoid prestige penalty
    else:
      baselineTarget  # Normal: match Act baseline

    if currentBatteries < targetBatteries:
      let needed = targetBatteries - currentBatteries

      # Priority combines threat + Act awareness + undefended penalty awareness
      let priority = if isUndefended:
        RequirementPriority.High      # PHASE F: Avoid -15 prestige penalty (HIGH priority)
      elif threat > 0.5:
        RequirementPriority.Critical  # Emergency fortification
      elif threat > 0.2 or currentAct >= GameAct.Act3_TotalWar:
        RequirementPriority.High      # Elevated threat OR war economy
      elif currentBatteries == 0:
        RequirementPriority.Medium    # No batteries but has armies/marines
      else:
        RequirementPriority.Low       # Has baseline, maintenance

      let req = BuildRequirement(
        requirementType: RequirementType.Infrastructure,
        priority: priority,  # DYNAMIC: Based on threat intelligence + undefended penalty awareness
        shipClass: none(ShipClass),
        itemId: some("GroundBattery"),
        quantity: needed,
        buildObjective: BuildObjective.Defense,
        targetSystem: some(colony.systemId),  # Target specific colony
        estimatedCost: groundBatteryCost * needed,
        reason: if isUndefended:
          &"Ground batteries for {colony.systemId} (UNDEFENDED - avoid -15 prestige penalty, threat={threat:.2f})"
        else:
          &"Ground batteries for {colony.systemId} (threat={threat:.2f}, have {currentBatteries}/{targetBatteries})"
      )
      let undefendedTag = if isUndefended: " [UNDEFENDED]" else: ""
      logInfo(LogCategory.lcAI, &"Domestikos requests: {needed}x GroundBattery at {colony.systemId}{undefendedTag} (priority={priority}, threat={threat:.2f})")
      result.add(req)

  # Armies for colony defense - ACT-AWARE + INTELLIGENCE-DRIVEN + UNDEFENDED PENALTY AWARE
  # Phased buildup: armies are last-line defense, build after batteries
  let armyCost = getArmyBuildCost()
  for colony in filtered.ownColonies:
    let currentArmies = colony.armies  # int, not seq
    let currentBatteries = colony.groundBatteries
    let currentMarines = colony.marines

    # PHASE F: Check if colony is completely undefended (no armies, marines, or batteries)
    # Undefended colonies incur +50% prestige penalty when lost (-15 vs -10)
    let isUndefended = (currentArmies == 0 and currentMarines == 0 and currentBatteries == 0)

    # ACT-AWARE: Baseline target matches economic capacity
    # Act 1: 0 armies (10PP after cost reduction, batteries prioritized first)
    # Act 2: 1 army (10PP, basic garrison)
    # Act 3+: 2 armies (20PP, full ground defense)
    let baselineTarget = case currentAct
      of GameAct.Act1_LandGrab: 0  # Minimal: batteries first, armies later
      of GameAct.Act2_RisingTensions: 1  # Basic garrison
      of GameAct.Act3_TotalWar, GameAct.Act4_Endgame: 2  # Full ground defense

    # INTELLIGENCE-DRIVEN: Calculate threat at this colony
    let threat = estimateLocalThreat(colony.systemId, filtered, controller)

    # Threat-based escalation: armies are last-line defense
    let targetArmies = if threat > 0.6:
      2  # Emergency: full ground defense
    elif threat > 0.3:
      max(baselineTarget, 1)  # Elevated: at least basic garrison
    elif isUndefended and currentBatteries == 0:
      1  # PHASE F: If no batteries, need at least 1 army to avoid prestige penalty
    else:
      baselineTarget  # Normal: match Act baseline

    if currentArmies < targetArmies:
      let needed = targetArmies - currentArmies

      # Priority: armies slightly lower than batteries, BUT boosted if colony is undefended
      let priority = if isUndefended and currentBatteries == 0:
        RequirementPriority.High      # PHASE F: Avoid -15 prestige penalty (HIGH priority)
      elif threat > 0.6:
        RequirementPriority.Critical  # Emergency
      elif threat > 0.3 or currentAct >= GameAct.Act3_TotalWar:
        RequirementPriority.High      # Elevated threat OR war economy
      elif currentArmies == 0 and currentAct >= GameAct.Act2_RisingTensions:
        RequirementPriority.Medium    # Act 2+: establish garrison
      else:
        RequirementPriority.Low       # Gradual buildup

      let req = BuildRequirement(
        requirementType: RequirementType.DefenseGap,
        priority: priority,  # DYNAMIC: Based on threat intelligence + undefended penalty awareness
        shipClass: none(ShipClass),
        itemId: some("Army"),
        quantity: needed,
        buildObjective: BuildObjective.Defense,
        targetSystem: some(colony.systemId),  # Target specific colony
        estimatedCost: armyCost * needed,
        reason: if isUndefended and currentBatteries == 0:
          &"Ground armies for {colony.systemId} (UNDEFENDED - avoid -15 prestige penalty, threat={threat:.2f})"
        else:
          &"Ground armies for {colony.systemId} (threat={threat:.2f}, have {currentArmies}/{targetArmies})"
      )
      let undefendedTag = if isUndefended and currentBatteries == 0: " [UNDEFENDED]" else: ""
      logInfo(LogCategory.lcAI, &"Domestikos requests: {needed}x Army at {colony.systemId}{undefendedTag} (priority={priority}, threat={threat:.2f})")
      result.add(req)

  # =============================================================================
  # PLANETARY SHIELDS (high-value colony protection)
  # =============================================================================
  # Phase F: Prioritize shields for high-value colonies (homeworld + high IU colonies)
  # Cost: 50 PP (Phase F reduction), DS=100, slows invasions
  # Requires CST 5
  if cstLevel >= 5:
    let shieldCost = getPlanetaryShieldCost(1)  # SLD1 shields

    for colony in filtered.ownColonies:
      # Check if colony already has max shield (planetaryShieldLevel > 0)
      let hasShield = colony.planetaryShieldLevel > 0

      if not hasShield:
        # Prioritize shields for:
        # 1. Homeworld (always high priority)
        # 2. High IU colonies (IU >= 100)
        # 3. Act 3+ colonies under threat

        let isHomeworld = (colony.systemId == controller.homeworld)
        let isHighValue = colony.industrial.units >= 100
        let threat = estimateLocalThreat(colony.systemId, filtered, controller)
        let underThreat = threat > 0.3

        var shouldBuildShield = false
        var priority = RequirementPriority.Low
        var reason = ""

        if isHomeworld:
          shouldBuildShield = true
          priority = RequirementPriority.High
          reason = &"Planetary shield for HOMEWORLD {colony.systemId} (DS=100, slows invasions)"
        elif isHighValue and underThreat:
          shouldBuildShield = true
          priority = RequirementPriority.Medium
          reason = &"Planetary shield for high-value {colony.systemId} (IU={colony.industrial.units}, threat={threat:.2f})"
        elif isHighValue and currentAct >= GameAct.Act3_TotalWar:
          shouldBuildShield = true
          priority = RequirementPriority.Medium
          reason = &"Planetary shield for high-value {colony.systemId} (IU={colony.industrial.units}, Act 3+)"
        elif underThreat and currentAct >= GameAct.Act3_TotalWar:
          shouldBuildShield = true
          priority = RequirementPriority.Low
          reason = &"Planetary shield for {colony.systemId} (threat={threat:.2f}, Act 3+)"

        if shouldBuildShield:
          # BUDGET-AWARE: Only request shield if treasury can support it (2x cost minimum)
          # RELAXED from 3x to 2x - more forgiving for shield requests
          # Rationale: 50PP shield with 100PP treasury still leaves 50PP for other needs
          if filtered.ownHouse.treasury >= (shieldCost * 2):
            # BUDGET-AWARE: Adjust priority downward if unaffordable (2x cost check)
            let adjustedPriority = adjustPriorityForAffordability(
              priority, shieldCost, 1,
              filtered.ownHouse.treasury, currentAct,
              &"PlanetaryShield at {colony.systemId}"
            )

            let req = BuildRequirement(
              requirementType: RequirementType.DefenseGap,
              priority: adjustedPriority,
              shipClass: none(ShipClass),
              quantity: 1,
              buildObjective: BuildObjective.Defense,
              targetSystem: some(colony.systemId),
              estimatedCost: shieldCost,
              reason: reason
            )
            logInfo(LogCategory.lcAI,
                    &"Domestikos requests: Planetary Shield at {colony.systemId} " &
                    &"(priority={adjustedPriority}, cost={shieldCost}PP, treasury={filtered.ownHouse.treasury}PP)")
            result.add(req)
          else:
            logDebug(LogCategory.lcAI,
                     &"Domestikos: Planetary Shield at {colony.systemId} deferred " &
                     &"(cost={shieldCost}PP, treasury={filtered.ownHouse.treasury}PP < 3x threshold={shieldCost * 3}PP)")

  # Marines for offensive operations (if aggressive and have transports)
  if personality.aggression > 0.6 and currentAct >= GameAct.Act2_RisingTensions:
    # Count transports
    var transportCount = 0
    for fleet in filtered.ownFleets:
      transportCount += fleet.spaceLiftShips.countIt(it.shipClass == ShipClass.TroopTransport)

    if transportCount > 0:
      let targetMarines = transportCount * 1  # 1 MD per transport (full capacity)
      if totalMarinesAll < targetMarines:
        let marineCost = getMarineBuildCost()
        let req = BuildRequirement(
          requirementType: RequirementType.OffensivePrep,
          priority: RequirementPriority.Low,
          shipClass: none(ShipClass),
          quantity: targetMarines - totalMarinesAll,
          buildObjective: BuildObjective.Military,
          targetSystem: none(SystemId),
          estimatedCost: marineCost * (targetMarines - totalMarinesAll),
          reason: &"Marines for invasion operations (have {totalMarinesAll}/{targetMarines})"
        )
        logInfo(LogCategory.lcAI, &"Domestikos requests: {req.quantity}x Marines ({req.estimatedCost}PP) - {req.reason}")
        result.add(req)

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
        let raiderCost = getShipConstructionCost(ShipClass.Raider)
        let req = BuildRequirement(
          requirementType: RequirementType.StrategicAsset,
          priority: RequirementPriority.Low,
          shipClass: some(ShipClass.Raider),
          quantity: targetRaiders - raiderCount,
          buildObjective: BuildObjective.Military,
          targetSystem: none(SystemId),
          estimatedCost: raiderCost * (targetRaiders - raiderCount),
          reason: &"Raider harassment force (have {raiderCount}/{targetRaiders})"
        )
        logInfo(LogCategory.lcAI, &"Domestikos requests: {req.quantity}x Raider ({req.estimatedCost}PP) - {req.reason}")
        result.add(req)

# =============================================================================
# Combat Lessons Integration (Phase C)
# =============================================================================

proc selectShipClassFromCombatLessons(
  combatLessons: seq[intelligence_types.TacticalLesson],
  threatHouse: Option[HouseId],
  fallbackClass: ShipClass
): ShipClass =
  ## Select ship class based on combat lessons learned against specific enemy
  ## Returns ship types that have proven effective in actual combat

  if combatLessons.len == 0 or threatHouse.isNone:
    return fallbackClass

  # Find lessons against this specific enemy house
  var relevantLessons: seq[intelligence_types.TacticalLesson] = @[]
  for lesson in combatLessons:
    if lesson.enemyHouse == threatHouse.get():
      relevantLessons.add(lesson)

  if relevantLessons.len == 0:
    return fallbackClass

  # Count effectiveness of each ship class against this enemy
  var effectivenessScores = initTable[ShipClass, int]()

  for lesson in relevantLessons:
    # Weight recent lessons more heavily (lessons from last 20 turns)
    let recencyWeight = if lesson.turn > 0: 1 else: 1  # Placeholder for turn weighting

    # Successful outcomes: boost effective ship types
    case lesson.outcome:
    of intel_types.CombatOutcome.Victory, intel_types.CombatOutcome.MutualRetreat:
      for shipClass in lesson.effectiveShipTypes:
        effectivenessScores[shipClass] = effectivenessScores.getOrDefault(shipClass, 0) + (2 * recencyWeight)
    of intel_types.CombatOutcome.Defeat, intel_types.CombatOutcome.Retreat:
      # Failed outcomes: penalize ineffective ship types
      for shipClass in lesson.ineffectiveShipTypes:
        effectivenessScores[shipClass] = effectivenessScores.getOrDefault(shipClass, 0) - (1 * recencyWeight)
    of intel_types.CombatOutcome.Ongoing:
      # Ongoing combat - no clear lesson yet, skip
      discard

  # Find ship class with highest effectiveness score
  var bestClass = fallbackClass
  var bestScore = -999

  for shipClass, score in effectivenessScores:
    if score > bestScore and shipClass in {ShipClass.Destroyer, ShipClass.Cruiser, ShipClass.Battlecruiser, ShipClass.Battleship}:
      bestScore = score
      bestClass = shipClass

  # Only use learned ship class if score is positive (proven effective)
  if bestScore > 0:
    return bestClass
  else:
    return fallbackClass

# =============================================================================
# Requirement Generation
# =============================================================================

proc createDefenseRequirement(
  gap: DefenseGap,
  filtered: FilteredGameState,
  combatLessons: seq[intelligence_types.TacticalLesson] = @[]
): BuildRequirement =
  ## Convert a defense gap into a build requirement
  ## Now uses combat lessons to select effective ship types

  # Identify threatening enemy house from fleet movement history
  var threatHouse: Option[HouseId] = none(HouseId)
  for fleetId, history in filtered.ownHouse.intelligence.fleetMovementHistory:
    if history.lastKnownLocation == gap.colonySystemId and history.owner != filtered.ownHouse.id:
      threatHouse = some(history.owner)
      break

  # Select ship class based on combat lessons (if available)
  let defaultClass = ShipClass.Destroyer
  let shipClass = selectShipClassFromCombatLessons(combatLessons, threatHouse, defaultClass)

  let shipStats = getShipStats(shipClass)  # Get stats from config/ships.toml
  let shipCost = shipStats.buildCost

  let reasonSuffix = if shipClass != defaultClass and threatHouse.isSome:
    &" [Combat lesson: {shipClass} effective vs {threatHouse.get()}]"
  else:
    ""

  result = BuildRequirement(
    requirementType: RequirementType.DefenseGap,
    priority: gap.severity,
    shipClass: some(shipClass),
    quantity: gap.recommendedDefenders - gap.currentDefenders,
    buildObjective: BuildObjective.Defense,
    targetSystem: some(gap.colonySystemId),
    estimatedCost: shipCost * (gap.recommendedDefenders - gap.currentDefenders),
    reason: &"Defense gap at system {gap.colonySystemId} (priority={gap.colonyPriority:.1f}, threat={gap.estimatedThreat:.2f})" & reasonSuffix
  )

proc generateBuildRequirements*(
  filtered: FilteredGameState,
  analyses: seq[FleetAnalysis],
  defensiveAssignments: Table[FleetId, StandingOrder],
  controller: var AIController,
  currentAct: GameAct,
  intelSnapshot: IntelligenceSnapshot,
  capacityInfo: SquadronCapacityInfo
): BuildRequirements =
  ## Main entry point: Generate all build requirements from Domestikos analysis
  ## Now accepts IntelligenceSnapshot from Drungarius for threat-aware prioritization
  ## Capacity-aware: Uses squadronCapacity to generate realistic requirements

  logDebug(LogCategory.lcAI,
           &"{controller.houseId} Domestikos: Generating build requirements (Act={currentAct}, " &
           &"capacity={capacityInfo.totalSquadrons}/{capacityInfo.maxTotalSquadrons})")

  # Assess gaps (personality-driven, intelligence-informed)
  let defenseGaps = assessDefenseGaps(filtered, analyses, defensiveAssignments, controller, currentAct, intelSnapshot)
  let strategicAssets = assessStrategicAssets(filtered, controller, currentAct, intelSnapshot)

  # Extract combat lessons from intelligence snapshot
  let combatLessons = intelSnapshot.military.combatLessonsLearned

  if combatLessons.len > 0:
    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Domestikos: Using {combatLessons.len} combat lessons for ship selection")

  # Check capacity headroom for realistic requirements
  let hasCapacityHeadroom = capacityInfo.utilizationPercent < 0.9
  let canBuildCapitals = not capacityInfo.atCapitalLimit
  let canBuildEscorts = not capacityInfo.atTotalLimit

  if capacityInfo.atTotalLimit:
    logWarn(LogCategory.lcAI,
            &"{controller.houseId} Domestikos: At squadron capacity " &
            &"({capacityInfo.totalSquadrons}/{capacityInfo.maxTotalSquadrons}), " &
            &"deferring non-critical requirements")

  # Convert gaps to build requirements
  var requirements: seq[BuildRequirement] = @[]

  # Defense requirements (now combat-lesson-aware)
  for gap in defenseGaps:
    let req = createDefenseRequirement(gap, filtered, combatLessons)
    if req.quantity > 0:  # Only add if we actually need ships
      requirements.add(req)

  # Strategic asset requirements (fighters, carriers, starbases, transports, etc.)
  requirements.add(strategicAssets)

  # Intelligence-driven reconnaissance requirements (scouts)
  let reconGaps = assessReconnaissanceGaps(filtered, controller, currentAct, intelSnapshot)
  requirements.add(reconGaps)

  # Intelligence-driven expansion requirements (ETACs)
  let expansionNeeds = assessExpansionNeeds(filtered, controller, currentAct)
  requirements.add(expansionNeeds)

  # Personality-modulated offensive requirements (transports, marines)
  let offensiveNeeds = assessOffensiveReadiness(filtered, controller, currentAct, intelSnapshot)
  requirements.add(offensiveNeeds)

  # Sort by priority (Critical > High > Medium > Low)
  # CRITICAL FIX: Enum ord values: Critical=0, High=1, Medium=2, Low=3, Deferred=4
  # Lower ord() = higher priority, so sort ASCENDING by ord() to get descending priority
  requirements.sort(proc(a, b: BuildRequirement): int =
    if a.priority > b.priority: 1  # Higher ord (Low=3) comes AFTER
    elif a.priority < b.priority: -1  # Lower ord (Critical=0) comes FIRST
    else: 0
  )

  # =============================================================================
  # CAPACITY FILLER: Budget-Matched Adaptive Requirements
  # =============================================================================
  # Problem: OLD system generated 50 fillers (1,775PP) with 208PP budget → 8.5x oversubscription
  #   - 0% SpecialUnits requirements → 31PP budget wasted
  #   - 83% Military fillers → mismatched with 30% Military budget
  # Solution: Budget-matched 20-slot rotation + smart dock/budget balancing
  #   - Matches budget percentages (45% Expansion, 25% Military, 10% Recon, 10% SpecialUnits, 10% Defense)
  #   - Act-aware ship mix (Fighters in Act 1-2, Transports in Act 3-4)
  #   - Accounts for actual high-priority costs and dock usage

  # STEP 1: Calculate available docks and budget
  # Count ACTUAL docks across all colonies (spaceports + shipyards)
  # Docks are CST-scaled: Base (Spaceport=5, Shipyard=10) × (1.0 + (CST-1) × 0.10)
  # Example: CST VI → Spaceport=7, Shipyard=15 docks
  let cstLevel = filtered.ownHouse.techTree.levels.constructionTech
  var totalDocks = 0
  for colony in filtered.ownColonies:
    for spaceport in colony.spaceports:
      totalDocks += spaceport.effectiveDocks  # Pre-calculated with CST scaling
    for shipyard in colony.shipyards:
      totalDocks += shipyard.effectiveDocks  # Pre-calculated with CST scaling

  # Count docks and budget committed to high-priority requirements
  var highPriorityCost = 0
  var docksCommitted = 0
  for req in requirements:
    highPriorityCost += req.estimatedCost
    # Ship requirements need docks
    if req.shipClass.isSome:
      docksCommitted += req.quantity

  # Calculate remaining resources for fillers
  let availableDocks = max(0, totalDocks - docksCommitted)

  # CRITICAL FIX: Generate fillers for ALL available docks
  # Don't pre-filter by budget - let priority scoring and perSlotBudget handle affordability
  # The selectBestUnit() function already filters unaffordable ships
  # Pre-filtering causes Act 3-4 to generate 0 fillers when treasury < avgFillerCost
  let affordableFillerCount = availableDocks

  # Calculate total filler budget (informational only, not used for filtering)
  let fillerBudgetEstimate = filtered.ownHouse.treasury

  logDebug(LogCategory.lcAI,
           &"Capacity fillers: treasury={filtered.ownHouse.treasury}PP, " &
           &"total_docks={totalDocks} (CST-adjusted), " &
           &"high-priority={highPriorityCost}PP ({docksCommitted} docks), " &
           &"available={availableDocks} docks, filler_budget={fillerBudgetEstimate}PP, " &
           &"affordable={affordableFillerCount} fillers ({currentAct})")

  # STEP 2: Generate capacity fillers using 20-slot budget-matched rotation
  # Track ETAC requirements generated in THIS turn (prevents generating 9 ETACs in one loop)
  # CRITICAL: Count ETACs already requested by assessExpansionNeeds() (prevents double-building)
  var etacsGeneratedThisTurn = 0
  for req in expansionNeeds:
    if req.shipClass.isSome and req.shipClass.get() == ShipClass.ETAC:
      etacsGeneratedThisTurn += req.quantity

  # Starbases moved to Eparch (facilities, not ships)
  # No longer tracked in capacity filler - Eparch handles facility construction

  # Calculate per-slot budget for unit selection (Act-aware, not just fair share)
  # Acts 1-2 build light units (30-40PP), Acts 2-3 build capitals (120-180PP),
  # Acts 3-4 build heavy capitals (200-400PP)
  let basePerSlotBudget = case currentAct
    of GameAct.Act1_LandGrab:
      40  # ETAC (25PP), Destroyer (40PP), Frigate (30PP)
    of GameAct.Act2_RisingTensions:
      180  # Cruiser (120PP), Battlecruiser (180PP), Carrier (150PP)
    of GameAct.Act3_TotalWar:
      300  # Battleship (250PP), Dreadnought (400PP), SuperCarrier (200PP)
    of GameAct.Act4_Endgame:
      400  # SuperDreadnought (500PP), Dreadnought (400PP), PlanetBreaker (800PP)

  let perSlotBudget = if affordableFillerCount > 0:
                        # Use Act-aware budget OR fair share, whichever is higher
                        max(basePerSlotBudget, fillerBudgetEstimate div affordableFillerCount)
                      else:
                        basePerSlotBudget

  for i in 0..<affordableFillerCount:
    var shipClass: Option[ShipClass] = none(ShipClass)
    var itemId: Option[string] = none(string)
    var objective: BuildObjective
    var reason: string
    var estimatedCost: int
    var requirementType: RequirementType

    # 20-slot rotation matching budget allocation percentages
    let slot = i mod 20
    case slot
    of 0..8:  # 45% Expansion/Military (9 slots)
      # Count ETACs in fleets + under construction + queued
      var currentETACs = 0
      for fleet in filtered.ownFleets:
        currentETACs += fleet.spaceLiftShips.countIt(it.shipClass == ShipClass.ETAC)

      # CRITICAL: Also count ETACs under construction (prevents treadmill)
      for colony in filtered.ownColonies:
        if colony.underConstruction.isSome:
          let project = colony.underConstruction.get()
          if project.projectType == econ_types.ConstructionType.Ship and
             project.itemId == "ETAC":
            currentETACs += 1
        # Also check construction queue
        for queuedProject in colony.constructionQueue:
          if queuedProject.projectType == econ_types.ConstructionType.Ship and
             queuedProject.itemId == "ETAC":
            currentETACs += 1

      # CRITICAL: Add ETACs already generated THIS turn (prevents slot 0-8 each making an ETAC)
      currentETACs += etacsGeneratedThisTurn

      let etacCap = int(filtered.starMap.numRings)

      logDebug(LogCategory.lcAI, &"ETAC cap: {currentETACs}/{etacCap} (slot {slot}, turn reqs: {etacsGeneratedThisTurn})")

      # If under cap AND in Act 1: build ETAC (per user table: Act 1 only)
      if currentAct == GameAct.Act1_LandGrab and currentETACs < etacCap:
        logDebug(LogCategory.lcAI, &"Building ETAC {currentETACs + 1}/{etacCap}")
        shipClass = some(ShipClass.ETAC)
        objective = BuildObjective.Expansion
        reason = &"Expansion (ETAC {currentETACs + 1}/{etacCap})"
        estimatedCost = 25
        requirementType = RequirementType.ExpansionSupport
        etacsGeneratedThisTurn += 1
      else:
        # At cap: build best available military ship based on CST tech
        # Check from most powerful to least, use first available
        let candidates = case currentAct
          of GameAct.Act1_LandGrab:
            # Act 1: Light escorts only (no Cruiser/Battlecruiser until Act 2)
            @[ShipClass.LightCruiser, ShipClass.Destroyer,
              ShipClass.Frigate, ShipClass.Corvette]
          of GameAct.Act2_RisingTensions:
            @[ShipClass.Battlecruiser, ShipClass.Cruiser, ShipClass.LightCruiser,
              ShipClass.Carrier, ShipClass.Destroyer, ShipClass.Frigate]
          of GameAct.Act3_TotalWar:
            # Act 3: Heavy capitals, SuperCarrier (CST V), carriers, raiders
            @[ShipClass.Battleship, ShipClass.Dreadnought, ShipClass.SuperCarrier,
              ShipClass.Battlecruiser, ShipClass.Carrier, ShipClass.Raider, ShipClass.Cruiser]
          of GameAct.Act4_Endgame:
            # Act 4: Ultimate capitals, SuperCarrier, Raider for economy disruption
            @[ShipClass.SuperDreadnought, ShipClass.Dreadnought, ShipClass.Battleship,
              ShipClass.SuperCarrier, ShipClass.Raider, ShipClass.Battlecruiser, ShipClass.Carrier]

        # Select best ship using priority scoring (Act-aware, budget-aware)
        let selectedUnit = selectBestUnit(candidates, currentAct, cstLevel,
                                          perSlotBudget)
        shipClass = if selectedUnit.isSome:
                      selectedUnit
                    else:
                      some(ShipClass.Corvette)  # Fallback if no affordable option
        objective = BuildObjective.Military
        reason = &"Military (ETACs at cap {etacCap})"
        estimatedCost = getShipConstructionCost(shipClass.get())
        requirementType = RequirementType.OffensivePrep


    of 9, 10:  # 10% Military (2 slots) - Affordable combat, Act-aware progression
      # Select best available ship based on CST tech (from config, not hardcoded)
      let candidates = case currentAct
        of GameAct.Act1_LandGrab:
          # Act 1: Light escorts only (no Cruiser/Battlecruiser until Act 2)
          @[ShipClass.LightCruiser, ShipClass.Destroyer, ShipClass.Frigate,
            ShipClass.Corvette]
        of GameAct.Act2_RisingTensions:
          # Act 2: Capitals and cruisers unlock
          @[ShipClass.Battlecruiser, ShipClass.Cruiser, ShipClass.LightCruiser,
            ShipClass.Destroyer]
        of GameAct.Act3_TotalWar:
          # Act 3: Heavy capitals, SuperCarrier, raiders
          @[ShipClass.Battleship, ShipClass.SuperCarrier, ShipClass.Battlecruiser,
            ShipClass.Raider, ShipClass.Cruiser]
        of GameAct.Act4_Endgame:
          # Act 4: Ultimate capitals, raiders for economic warfare
          @[ShipClass.SuperDreadnought, ShipClass.Dreadnought, ShipClass.Battleship,
            ShipClass.Raider, ShipClass.Battlecruiser]

      # Select best ship using priority scoring (Act-aware, budget-aware)
      let selectedUnit = selectBestUnit(candidates, currentAct, cstLevel,
                                        perSlotBudget)
      shipClass = if selectedUnit.isSome:
                    selectedUnit
                  else:
                    some(ShipClass.Corvette)  # Fallback if no affordable option
      objective = BuildObjective.Military
      reason = "Fleet capacity (filler)"
      estimatedCost = getShipConstructionCost(shipClass.get())
      requirementType = RequirementType.OffensivePrep

    of 11, 12:  # 10% Reconnaissance (2 slots)
      shipClass = some(ShipClass.Scout)
      objective = BuildObjective.Reconnaissance
      reason = "Intel capacity (filler)"
      estimatedCost = getShipConstructionCost(ShipClass.Scout)
      requirementType = RequirementType.ReconnaissanceGap

    of 13, 14:  # 10% SpecialUnits (2 slots) - ACT-AWARE: Fighters (all acts), Transports (Act 2+), PlanetBreakers (Act 4)
      # Rotate between Fighter and TroopTransport based on act and slot
      case currentAct
      of GameAct.Act1_LandGrab:
        # Act 1: Fighters for colony defense and space combat
        shipClass = some(ShipClass.Fighter)
        reason = "Fighter capacity (filler, colony defense)"
        estimatedCost = getShipConstructionCost(ShipClass.Fighter)
      of GameAct.Act2_RisingTensions, GameAct.Act3_TotalWar:
        # Act 2-3: Mix of Fighters and TroopTransports (rotate by slot)
        if i mod 2 == 0:
          shipClass = some(ShipClass.Fighter)
          reason = "Fighter capacity (filler, space combat)"
          estimatedCost = getShipConstructionCost(ShipClass.Fighter)
        else:
          shipClass = some(ShipClass.TroopTransport)
          reason = "Transport capacity (filler, invasion/blitz prep)"
          estimatedCost = getShipConstructionCost(ShipClass.TroopTransport)
      of GameAct.Act4_Endgame:
        # Act 4: PlanetBreaker (CST 10) if available, else rotate Fighter/Transport
        if cstLevel >= getShipCSTRequirement(ShipClass.PlanetBreaker) and i mod 3 == 0:
          shipClass = some(ShipClass.PlanetBreaker)
          reason = "Planet-Breaker (filler, strategic weapon)"
          estimatedCost = getShipConstructionCost(ShipClass.PlanetBreaker)
        elif i mod 2 == 0:
          shipClass = some(ShipClass.Fighter)
          reason = "Fighter capacity (filler, space superiority)"
          estimatedCost = getShipConstructionCost(ShipClass.Fighter)
        else:
          shipClass = some(ShipClass.TroopTransport)
          reason = "Transport capacity (filler, invasion prep)"
          estimatedCost = getShipConstructionCost(ShipClass.TroopTransport)
      objective = BuildObjective.SpecialUnits
      requirementType = RequirementType.StrategicAsset

    of 15:  # 5% Defense (1 slot) - Ground Batteries
      # NOTE: Starbases moved to Eparch (facilities, not ships)
      # This slot now only builds Ground Batteries for colony defense
      shipClass = none(ShipClass)
      itemId = some("GroundBattery")
      reason = "Colony defense battery (filler)"
      estimatedCost = getBuildingCost("GroundBattery")
      objective = BuildObjective.Defense
      requirementType = RequirementType.Infrastructure

    of 16:  # 5% Defense (1 slot) - Army (all acts), Marine/Shield (Act 2+)
      case currentAct
      of GameAct.Act1_LandGrab:
        # Act 1: Armies only (ground defense)
        shipClass = none(ShipClass)
        itemId = some("Army")
        reason = "Ground defense army (filler)"
        estimatedCost = getBuildingCost("Army")
      of GameAct.Act2_RisingTensions, GameAct.Act3_TotalWar:
        # Act 2-3: Rotate between Army, Marine, and PlanetaryShield (if CST allows)
        if cstLevel >= 5 and i mod 3 == 0:
          # Planetary Shield available at CST V
          shipClass = none(ShipClass)
          itemId = some("PlanetaryShield")
          reason = "Planetary shield (filler, ultimate defense)"
          estimatedCost = getBuildingCost("PlanetaryShield")
        elif i mod 2 == 0:
          shipClass = none(ShipClass)
          itemId = some("Marine")
          reason = "Marine division (filler, invasion prep)"
          estimatedCost = getBuildingCost("Marine")
        else:
          shipClass = none(ShipClass)
          itemId = some("Army")
          reason = "Ground defense army (filler)"
          estimatedCost = getBuildingCost("Army")
      of GameAct.Act4_Endgame:
        # Act 4: Prioritize Planetary Shields, fallback to Marines/Armies
        if cstLevel >= 5 and i mod 2 == 0:
          shipClass = none(ShipClass)
          itemId = some("PlanetaryShield")
          reason = "Planetary shield (filler, ultimate defense)"
          estimatedCost = getBuildingCost("PlanetaryShield")
        elif i mod 3 == 0:
          shipClass = none(ShipClass)
          itemId = some("Marine")
          reason = "Marine division (filler)"
          estimatedCost = getBuildingCost("Marine")
        else:
          shipClass = none(ShipClass)
          itemId = some("Army")
          reason = "Ground defense army (filler)"
          estimatedCost = getBuildingCost("Army")
      objective = BuildObjective.Defense
      requirementType = RequirementType.Infrastructure

    of 17:  # 5% Military (1 slot) - Mid-tier, Act-aware
      let candidates = case currentAct
        of GameAct.Act1_LandGrab:
          @[ShipClass.LightCruiser, ShipClass.Destroyer, ShipClass.Frigate]
        of GameAct.Act2_RisingTensions:
          @[ShipClass.Cruiser, ShipClass.LightCruiser, ShipClass.Destroyer]
        of GameAct.Act3_TotalWar:
          @[ShipClass.Battlecruiser, ShipClass.HeavyCruiser, ShipClass.Cruiser]
        of GameAct.Act4_Endgame:
          @[ShipClass.Battleship, ShipClass.Battlecruiser, ShipClass.HeavyCruiser]

      # Select best ship using priority scoring (Act-aware, budget-aware)
      let selectedUnit = selectBestUnit(candidates, currentAct, cstLevel,
                                        perSlotBudget)
      shipClass = if selectedUnit.isSome:
                    selectedUnit
                  else:
                    some(ShipClass.Corvette)  # Fallback if no affordable option
      objective = BuildObjective.Military
      reason = "Mid-tier capacity (filler)"
      estimatedCost = getShipConstructionCost(shipClass.get())
      requirementType = RequirementType.OffensivePrep

    of 18, 19:  # 10% Military (2 slots) - Affordable combat (escorts)
      let candidates = case currentAct
        of GameAct.Act1_LandGrab:
          @[ShipClass.Destroyer, ShipClass.Frigate, ShipClass.Corvette]
        of GameAct.Act2_RisingTensions:
          @[ShipClass.LightCruiser, ShipClass.Destroyer, ShipClass.Frigate]
        of GameAct.Act3_TotalWar:
          @[ShipClass.Cruiser, ShipClass.LightCruiser, ShipClass.Destroyer]
        of GameAct.Act4_Endgame:
          @[ShipClass.HeavyCruiser, ShipClass.Cruiser, ShipClass.LightCruiser]

      # Select best ship using priority scoring (Act-aware, budget-aware)
      let selectedUnit = selectBestUnit(candidates, currentAct, cstLevel,
                                        perSlotBudget)
      shipClass = if selectedUnit.isSome:
                    selectedUnit
                  else:
                    some(ShipClass.Corvette)  # Fallback if no affordable option
      objective = BuildObjective.Military
      reason = "Combat capacity (filler)"
      estimatedCost = getShipConstructionCost(shipClass.get())
      requirementType = RequirementType.OffensivePrep

    else:
      # Fallback (should never hit with mod 20)
      shipClass = some(ShipClass.Destroyer)
      objective = BuildObjective.Military
      reason = "Fallback filler"
      estimatedCost = 40
      requirementType = RequirementType.OffensivePrep

    # STEP 3: Act-aware priority assignment (not just cost-based)
    # Capital ships should have higher priority in later Acts to match strategic value
    # This ensures they win the weighted priority queue in Basileus mediation
    let priority = case currentAct
      of GameAct.Act1_LandGrab:
        # Act 1: Expansion focus - cheap units get Medium priority
        if estimatedCost <= 40:
          RequirementPriority.Medium  # ETAC, Fighter, Scout, Destroyer
        else:
          RequirementPriority.Low  # Capitals not priority in Act 1

      of GameAct.Act2_RisingTensions:
        # Act 2: Medium capitals (Cruiser, Battlecruiser) get High priority
        if estimatedCost <= 25:
          RequirementPriority.Medium  # Cheap units still useful
        elif estimatedCost <= 200:
          RequirementPriority.High  # Cruiser=120, Battlecruiser=180
        else:
          RequirementPriority.Medium  # Heavy capitals deferred

      of GameAct.Act3_TotalWar:
        # Act 3: Heavy capitals (Battleship, Dreadnought) get High priority
        if estimatedCost <= 25:
          RequirementPriority.Low  # Cheap units less relevant
        elif estimatedCost <= 400:
          RequirementPriority.High  # Battleship=250, Dreadnought=350
        else:
          RequirementPriority.Medium  # SuperDreadnoughts

      of GameAct.Act4_Endgame:
        # Act 4: Ultimate capitals get Critical priority
        if estimatedCost <= 40:
          RequirementPriority.Low  # Light units irrelevant
        elif estimatedCost >= 300:
          RequirementPriority.Critical  # Dreadnought=350, SuperDreadnought=500+
        else:
          RequirementPriority.High  # Medium capitals still strong

    # Add capacity filler requirement (ships have shipClass, ground units/facilities have itemId)
    requirements.add(BuildRequirement(
      requirementType: requirementType,  # Use the type set by slot rotation
      priority: priority,
      shipClass: shipClass,  # Some for ships, none for ground units
      itemId: itemId,  # Some for ground units/facilities, none for ships
      quantity: 1,
      buildObjective: objective,
      targetSystem: none(SystemId),
      estimatedCost: estimatedCost,
      reason: reason
    ))

  # STEP 4: Enhanced logging with budget breakdown
  let mediumCount = requirements.countIt(it.priority == RequirementPriority.Medium and it.reason.contains("filler"))
  let lowCount = requirements.countIt(it.priority == RequirementPriority.Low and it.reason.contains("filler"))
  let totalFillerCost = requirements.filterIt(it.reason.contains("filler")).mapIt(it.estimatedCost).foldl(a + b, 0)
  logInfo(LogCategory.lcAI,
          &"Domestikos: Generated {affordableFillerCount} capacity fillers (Medium={mediumCount}, Low={lowCount}, " &
          &"total={totalFillerCost}PP, 20-slot budget-matched rotation)")

  result = BuildRequirements(
    requirements: requirements,
    totalEstimatedCost: requirements.mapIt(it.estimatedCost).foldl(a + b, 0),
    criticalCount: requirements.countIt(it.priority == RequirementPriority.Critical),
    highCount: requirements.countIt(it.priority == RequirementPriority.High),
    generatedTurn: filtered.turn,
    act: currentAct,
    iteration: 0  # Initial requirements (not reprioritized)
  )

  logInfo(LogCategory.lcAI,
          &"Domestikos generated {requirements.len} TOTAL build requirements " &
          &"(Critical={result.criticalCount}, High={result.highCount}, Deferred={requirements.countIt(it.priority == RequirementPriority.Deferred)}, " &
          &"Total={result.totalEstimatedCost}PP)")

proc reprioritizeRequirements*(
  originalRequirements: BuildRequirements,
  treasurerFeedback: TreasurerFeedback,
  treasury: int  # NEW: Treasury for budget-aware reprioritization
): BuildRequirements =
  ## Domestikos reprioritizes requirements based on Treasurer feedback
  ##
  ## Strategy:
  ## 1. Start with unfulfilled requirements
  ## 2. Downgrade priorities based on cost-effectiveness
  ## 3. Aggressive downgrade for very expensive requests (>50% treasury)
  ## 4. Moderate downgrade for expensive requests (25-50% treasury)
  ## 5. Normal downgrade for affordable requests (<25% treasury)
  ##
  ## This creates a tighter, more affordable requirements list

  const MAX_ITERATIONS = 3  # Prevent infinite loops

  if originalRequirements.iteration >= MAX_ITERATIONS:
    logWarn(LogCategory.lcAI,
            &"Domestikos reprioritization limit reached ({MAX_ITERATIONS} iterations). " &
            &"Accepting unfulfilled requirements.")
    return originalRequirements

  # If everything was fulfilled OR nothing was unfulfilled, no need to reprioritize
  if treasurerFeedback.unfulfilledRequirements.len == 0:
    return originalRequirements

  logInfo(LogCategory.lcAI,
          &"Domestikos reprioritizing {treasurerFeedback.unfulfilledRequirements.len} unfulfilled requirements " &
          &"(iteration {originalRequirements.iteration + 1}, shortfall: {treasurerFeedback.totalUnfulfilledCost}PP, treasury={treasury}PP)")

  # Strategy: Downgrade priorities based on cost-effectiveness
  var reprioritized: seq[BuildRequirement] = @[]

  # Add all fulfilled requirements (these were already affordable)
  reprioritized.add(treasurerFeedback.fulfilledRequirements)

  # Reprioritize unfulfilled requirements with cost-awareness
  for req in treasurerFeedback.unfulfilledRequirements:
    var adjustedReq = req

    # Calculate cost-effectiveness ratio
    let costRatio = if treasury > 0: float(req.estimatedCost) / float(treasury) else: 1.0

    # BUDGET-AWARE: Aggressive downgrade for VERY expensive unfulfilled requests (>50% treasury)
    if costRatio > 0.5:
      case req.priority
      of RequirementPriority.Critical:
        adjustedReq.priority = RequirementPriority.High  # Critical → High
      of RequirementPriority.High:
        adjustedReq.priority = RequirementPriority.Low  # High → Low (skip Medium)
      of RequirementPriority.Medium:
        adjustedReq.priority = RequirementPriority.Deferred  # Medium → Deferred
      else:
        adjustedReq.priority = RequirementPriority.Deferred

      logDebug(LogCategory.lcAI,
               &"Domestikos: '{req.reason}' too expensive ({req.estimatedCost}PP = " &
               &"{int(costRatio*100)}% of treasury), aggressive downgrade {req.priority} → {adjustedReq.priority}")

    # BUDGET-AWARE: Moderate downgrade for expensive requests (25-50% treasury)
    elif costRatio > 0.25:
      case req.priority
      of RequirementPriority.Critical:
        adjustedReq.priority = RequirementPriority.High  # Critical → High
      of RequirementPriority.High:
        adjustedReq.priority = RequirementPriority.Medium  # High → Medium
      of RequirementPriority.Medium:
        adjustedReq.priority = RequirementPriority.Low  # Medium → Low
      of RequirementPriority.Low:
        adjustedReq.priority = RequirementPriority.Deferred  # Low → Deferred
      else:
        adjustedReq.priority = RequirementPriority.Deferred

      logDebug(LogCategory.lcAI,
               &"Domestikos: '{req.reason}' expensive ({req.estimatedCost}PP = " &
               &"{int(costRatio*100)}% of treasury), moderate downgrade {req.priority} → {adjustedReq.priority}")

    # Normal downgrade for affordable units (<25% treasury)
    else:
      case req.priority
      of RequirementPriority.Critical:
        # Keep Critical as-is (absolute essentials)
        adjustedReq.priority = RequirementPriority.Critical
      of RequirementPriority.High:
        # Downgrade High → Medium (important but not critical)
        adjustedReq.priority = RequirementPriority.Medium
        logDebug(LogCategory.lcAI,
                 &"Domestikos: Downgrading '{req.reason}' (High → Medium)")
      of RequirementPriority.Medium:
        # Downgrade Medium → Low (nice-to-have)
        adjustedReq.priority = RequirementPriority.Low
        logDebug(LogCategory.lcAI,
                 &"Domestikos: Downgrading '{req.reason}' (Medium → Low)")
      of RequirementPriority.Low:
        # Downgrade Low → Deferred (skip this round)
        adjustedReq.priority = RequirementPriority.Deferred
        logDebug(LogCategory.lcAI,
                 &"Domestikos: Deferring '{req.reason}' (Low → Deferred)")
      of RequirementPriority.Deferred:
        # Already deferred, keep as deferred
        adjustedReq.priority = RequirementPriority.Deferred

    reprioritized.add(adjustedReq)

  # Re-sort by new priorities
  # CRITICAL FIX: Same logic as generateBuildRequirements - lower ord() = higher priority
  reprioritized.sort(proc(a, b: BuildRequirement): int =
    if a.priority > b.priority: 1  # Higher ord (Low=3) comes AFTER
    elif a.priority < b.priority: -1  # Lower ord (Critical=0) comes FIRST
    else: 0
  )

  result = BuildRequirements(
    requirements: reprioritized,
    totalEstimatedCost: reprioritized.mapIt(it.estimatedCost).foldl(a + b, 0),
    criticalCount: reprioritized.countIt(it.priority == RequirementPriority.Critical),
    highCount: reprioritized.countIt(it.priority == RequirementPriority.High),
    generatedTurn: originalRequirements.generatedTurn,
    act: originalRequirements.act,
    iteration: originalRequirements.iteration + 1
  )

  logInfo(LogCategory.lcAI,
          &"Domestikos reprioritized requirements: {result.requirements.len} total " &
          &"(Critical={result.criticalCount}, High={result.highCount}, iteration={result.iteration})")
