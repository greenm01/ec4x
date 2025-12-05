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

import std/[options, tables, sequtils, algorithm, strformat]
import ../../../common/types/[core, units]
import ../../../engine/[gamestate, fog_of_war, logger, order_types, fleet, starmap, squadron, spacelift]
import ../../../engine/economy/config_accessors  # For centralized cost accessors
import ../../../engine/intelligence/types as intel_types  # For CombatOutcome
import ../../common/types as ai_common_types  # For BuildObjective
import ../controller_types  # For BuildRequirements types
import ../shared/intelligence_types  # For IntelligenceSnapshot
import ../config
import ./fleet_analysis
import ./intelligence_ops  # Extracted: estimateLocalThreat

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
  currentAct: GameAct
): seq[DefenseGap] =
  ## Identify reconnaissance gaps (stale intel, unknown systems)
  ## Returns DefenseGap type for simplicity (reuses structure)
  result = @[]

  # For MVP: Simple scout count check
  # TODO: Enhance with stale intel detection, unknown system tracking

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
    # Target: 2-8 fighters per game act for flexible defense/offense
    let targetFighters = case currentAct
      of GameAct.Act1_LandGrab: 2        # Basic defensive coverage
      of GameAct.Act2_RisingTensions: 4  # Increased threat level
      of GameAct.Act3_TotalWar: 6        # Full defensive commitment
      of GameAct.Act4_Endgame: 8         # Maximum fighter production

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
          reason: &"Fighter defense squadron #{i+1} (have {fighterCount+i}/{targetFighters})"
        )
        result.add(req)

      logInfo(LogCategory.lcAI, &"Domestikos requests: {neededFighters}x Fighter (colony defense, 1 at a time, {fighterCost}PP each)")

    # PHASE 2: Request carriers for offensive projection (SpecialUnits budget)
    # Carriers are strategic mobility platforms - only build if we have fighters
    let targetCarriers = case currentAct
      of GameAct.Act1_LandGrab: 1  # One carrier for expansion
      of GameAct.Act2_RisingTensions: 2  # Two carriers for rising tensions
      of GameAct.Act3_TotalWar: 3  # Three carriers for total war
      of GameAct.Act4_Endgame: 4  # Four carriers for endgame

    if carrierCount < targetCarriers and fighterCount >= 2:  # Only request carriers if we have fighters
      let carrierClass = if cstLevel >= 5: ShipClass.SuperCarrier else: ShipClass.Carrier
      let carrierCost = getShipConstructionCost(carrierClass)

      let req = BuildRequirement(
        requirementType: RequirementType.StrategicAsset,
        priority: RequirementPriority.Low,  # Lower priority: expensive, strategic (not urgent)
        shipClass: some(carrierClass),
        quantity: targetCarriers - carrierCount,
        buildObjective: BuildObjective.SpecialUnits,  # Carriers use SpecialUnits budget
        targetSystem: none(SystemId),
        estimatedCost: carrierCost * (targetCarriers - carrierCount),
        reason: &"Carrier mobility platform (have {carrierCount}/{targetCarriers}, {fighterCount} fighters available)"
      )
      logInfo(LogCategory.lcAI, &"Domestikos requests: {req.quantity}x {carrierClass} ({req.estimatedCost}PP) - {req.reason}")
      result.add(req)

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
    let starbaseCost = getShipConstructionCost(ShipClass.Starbase)
    let req = BuildRequirement(
      requirementType: RequirementType.Infrastructure,
      priority: RequirementPriority.High,  # Urgent - prevents fighter disbanding
      shipClass: some(ShipClass.Starbase),
      quantity: requiredStarbases - totalStarbases,
      buildObjective: BuildObjective.Defense,
      targetSystem: none(SystemId),
      estimatedCost: starbaseCost * (requiredStarbases - totalStarbases),
      reason: &"Starbase infrastructure for fighters (have {totalStarbases}, need {requiredStarbases})"
    )
    logInfo(LogCategory.lcAI, &"Domestikos requests: {req.quantity}x Starbase ({req.estimatedCost}PP) - {req.reason}")
    result.add(req)

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

    let req = BuildRequirement(
      requirementType: RequirementType.OffensivePrep,
      priority: RequirementPriority.High,
      shipClass: some(capitalClass),
      quantity: targetCapitalShips - totalCapitalShips,
      buildObjective: BuildObjective.Military,
      targetSystem: none(SystemId),
      estimatedCost: capitalCost * (targetCapitalShips - totalCapitalShips),
      reason: &"Capital ship battle line (have {totalCapitalShips}/{targetCapitalShips})"
    )
    logInfo(LogCategory.lcAI, &"Domestikos requests: {req.quantity}x {capitalClass} ({req.estimatedCost}PP) - {req.reason}")
    result.add(req)

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
    let req = BuildRequirement(
      requirementType: RequirementType.Infrastructure,
      priority: RequirementPriority.Medium,
      shipClass: none(ShipClass),
      quantity: targetShields - shieldedColonies,
      buildObjective: BuildObjective.Defense,
      targetSystem: none(SystemId),
      estimatedCost: planetaryShieldCost * (targetShields - shieldedColonies),
      reason: &"Planetary shields for high-value colonies (have {shieldedColonies}/{targetShields})"
    )
    logInfo(LogCategory.lcAI, &"Domestikos requests: {req.quantity}x PlanetaryShield ({req.estimatedCost}PP) - {req.reason}")
    result.add(req)

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
  intelSnapshot: IntelligenceSnapshot
): BuildRequirements =
  ## Main entry point: Generate all build requirements from Domestikos analysis
  ## Now accepts IntelligenceSnapshot from Drungarius for threat-aware prioritization

  logDebug(LogCategory.lcAI,
           &"{controller.houseId} Domestikos: Generating build requirements (Act={currentAct})")

  # Assess gaps (personality-driven, intelligence-informed)
  let defenseGaps = assessDefenseGaps(filtered, analyses, defensiveAssignments, controller, currentAct, intelSnapshot)
  let strategicAssets = assessStrategicAssets(filtered, controller, currentAct)

  # Extract combat lessons from intelligence snapshot
  let combatLessons = intelSnapshot.military.combatLessonsLearned

  if combatLessons.len > 0:
    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Domestikos: Using {combatLessons.len} combat lessons for ship selection")

  # Convert gaps to build requirements
  var requirements: seq[BuildRequirement] = @[]

  # Defense requirements (now combat-lesson-aware)
  for gap in defenseGaps:
    let req = createDefenseRequirement(gap, filtered, combatLessons)
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
    act: currentAct,
    iteration: 0  # Initial requirements (not reprioritized)
  )

  logInfo(LogCategory.lcAI,
          &"Domestikos generated {requirements.len} build requirements " &
          &"(Critical={result.criticalCount}, High={result.highCount}, Total={result.totalEstimatedCost}PP)")

proc reprioritizeRequirements*(
  originalRequirements: BuildRequirements,
  treasurerFeedback: TreasurerFeedback
): BuildRequirements =
  ## Domestikos reprioritizes requirements based on Treasurer feedback
  ##
  ## Strategy:
  ## 1. Start with unfulfilled requirements
  ## 2. Downgrade priorities of less critical items to fit within budget
  ## 3. Focus on absolute essentials (Critical → High)
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
          &"(iteration {originalRequirements.iteration + 1}, shortfall: {treasurerFeedback.totalUnfulfilledCost}PP)")

  # Strategy: Keep only Critical requirements, downgrade High→Medium, Medium→Low
  var reprioritized: seq[BuildRequirement] = @[]

  # Add all fulfilled requirements (these were already affordable)
  reprioritized.add(treasurerFeedback.fulfilledRequirements)

  # Reprioritize unfulfilled requirements
  for req in treasurerFeedback.unfulfilledRequirements:
    var adjustedReq = req

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
  reprioritized.sort(proc(a, b: BuildRequirement): int =
    if a.priority < b.priority: 1  # Reverse: Higher priority first
    elif a.priority > b.priority: -1
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
