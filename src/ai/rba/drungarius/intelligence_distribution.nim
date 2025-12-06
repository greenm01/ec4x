## Drungarius Intelligence Distribution Module
##
## Byzantine Drungarius - Intelligence Hub
##
## Consolidates fog-of-war visibility, reconnaissance reports, and espionage data
## into a unified IntelligenceSnapshot for all imperial advisors

import std/[tables, strformat, options]
import ../../../common/types/[core, diplomacy]
import ../../../engine/[gamestate, fog_of_war, logger]
import ../../../engine/diplomacy/types as dip_types
import ../../../engine/economy/capacity/[total_squadrons, capital_squadrons, fighter]
import ../controller_types
import ../config
import ../shared/intelligence_types
import ./analyzers/[colony_analyzer, system_analyzer, starbase_analyzer, combat_analyzer, surveillance_analyzer, diplomatic_events_analyzer, counterintel_analyzer, construction_trends_analyzer]
from ./threat_assessment import assessAllThreats

proc assessThreat*(
  filtered: FilteredGameState,
  ownSystemId: SystemId,
  controller: AIController
): intelligence_types.ThreatLevel =
  ## Assess threat level to one of our systems based on enemy presence

  # Check for enemy fleets in system (from fog-of-war)
  var enemyFleetCount = 0
  var totalEnemyStrength = 0

  for fleetId, visFleet in filtered.visibleFleets:
    if visFleet.location == ownSystemId and visFleet.owner != controller.houseId:
      enemyFleetCount += 1
      # Use estimated ship count for enemy fleets, or full details if available
      if visFleet.fullDetails.isSome:
        totalEnemyStrength += visFleet.fullDetails.get().squadrons.len
      elif visFleet.estimatedShipCount.isSome:
        totalEnemyStrength += visFleet.estimatedShipCount.get()
      else:
        totalEnemyStrength += 1  # Unknown strength, assume 1

  if enemyFleetCount > 0:
    # Assess based on fleet strength
    if totalEnemyStrength >= 10:
      return intelligence_types.ThreatLevel.tlCritical  # Large enemy force
    elif totalEnemyStrength >= 5:
      return intelligence_types.ThreatLevel.tlHigh  # Moderate enemy force
    else:
      return intelligence_types.ThreatLevel.tlModerate  # Small enemy presence

  # Check intelligence for recent enemy activity
  for fleetId, history in filtered.ownHouse.intelligence.fleetMovementHistory:
    if history.lastKnownLocation == ownSystemId:
      # Enemy was here recently - elevated threat
      let turnsSince = filtered.turn - history.lastSeen
      if turnsSince <= 2:
        return intelligence_types.ThreatLevel.tlModerate  # Recent enemy activity
      elif turnsSince <= 5:
        return intelligence_types.ThreatLevel.tlLow  # Enemy was here recently

  return intelligence_types.ThreatLevel.tlNone  # No known threats

proc needsReconnaissance*(
  filtered: FilteredGameState,
  systemId: SystemId,
  controller: AIController
): bool =
  ## Determine if a system needs reconnaissance (stale intel)

  # Check if we have recent intel on this system
  if filtered.ownHouse.intelligence.colonyReports.hasKey(systemId):
    let report = filtered.ownHouse.intelligence.colonyReports[systemId]
    let turnsSince = filtered.turn - report.gatheredTurn

    # Intel is stale if > 10 turns old
    if turnsSince > 10:
      return true

  # Check if we have any fleet movement intel for this system
  var hasRecentMovementIntel = false
  for fleetId, history in filtered.ownHouse.intelligence.fleetMovementHistory:
    if history.lastKnownLocation == systemId:
      let turnsSince = filtered.turn - history.lastSeen
      if turnsSince <= 10:
        hasRecentMovementIntel = true
        break

  if not hasRecentMovementIntel:
    # No recent movement intel - needs reconnaissance
    return true

  return false

proc calculateSquadronCapacity(
  filtered: FilteredGameState
): SquadronCapacityInfo =
  ## Calculate current squadron capacity status from game state
  ## Uses existing capacity module functions for DRY compliance

  # Calculate total IU for capacity limits
  var totalIU = 0
  for colony in filtered.ownColonies:
    totalIU += colony.industrial.units

  # Get map parameters for capacity multipliers
  let mapRings = int(filtered.starMap.numRings)
  let numPlayers = filtered.starMap.playerCount

  # Calculate maximum capacities using existing capacity modules
  let maxTotal = total_squadrons.calculateMaxTotalSquadrons(totalIU, mapRings, numPlayers)
  let maxCapital = capital_squadrons.calculateMaxCapitalSquadrons(totalIU, mapRings, numPlayers)

  # Count current squadrons from fleets
  var currentTotal = 0
  var currentCapital = 0
  var currentPBs = 0

  for fleet in filtered.ownFleets:
    for squadron in fleet.squadrons:
      let shipClass = squadron.flagship.shipClass
      if total_squadrons.isMilitarySquadron(shipClass):
        currentTotal += 1
      if capital_squadrons.isCapitalShip(shipClass):
        currentCapital += 1
      if shipClass == ShipClass.PlanetBreaker:
        currentPBs += 1

  # Calculate fighter capacity per colony
  var fighterCapacity = initTable[SystemId, tuple[current: int, maximum: int]]()
  let fdLevel = filtered.ownHouse.techTree.levels.fighterDoctrine

  for colony in filtered.ownColonies:
    let maxFighters = fighter.calculateMaxFighterCapacity(colony.industrial.units, fdLevel)
    let currentFighters = colony.fighterSquadrons.len
    fighterCapacity[colony.systemId] = (current: currentFighters, maximum: maxFighters)

  result = SquadronCapacityInfo(
    totalSquadrons: currentTotal,
    maxTotalSquadrons: maxTotal,
    capitalSquadrons: currentCapital,
    maxCapitalSquadrons: maxCapital,
    fightersPerColony: fighterCapacity,
    planetBreakers: currentPBs,
    maxPlanetBreakers: filtered.ownColonies.len,
    utilizationPercent: if maxTotal > 0: float(currentTotal) / float(maxTotal) else: 0.0,
    atCapitalLimit: currentCapital >= maxCapital,
    atTotalLimit: currentTotal >= maxTotal
  )

proc generateIntelligenceReport*(
  filtered: FilteredGameState,
  controller: AIController
): IntelligenceSnapshot =
  ## Enhanced intelligence report generation (Phase B+)
  ## Analyzes ColonyIntelReport, SystemIntelReport, and generates domain-specific summaries

  result.turn = filtered.turn

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Drungarius: Generating enhanced intelligence report for turn {result.turn}")

  let config = globalRBAConfig.intelligence

  # === PHASE B: COLONY & SYSTEM INTELLIGENCE ===

  # Analyze colony intelligence (vulnerabilities, high-value targets)
  let (vulnerableTargets, highValueTargets) = analyzeColonyIntelligence(filtered, controller)

  # Analyze system intelligence (enemy fleet tracking)
  let enemyFleets = analyzeSystemIntelligence(filtered, controller)

  # Unified threat assessment for all colonies
  let threats: Table[SystemId, ThreatAssessment] = assessAllThreats(filtered, enemyFleets, config, filtered.turn)

  # === PHASE C: STARBASE & COMBAT INTELLIGENCE ===

  # Analyze starbase intelligence (tech gaps, economy)
  let (enemyEcon, enemyTech) = analyzeStarbaseIntelligence(filtered, controller)

  # Analyze combat reports (tactical lessons)
  let combatLessons = analyzeCombatReports(filtered, controller)

  # Calculate squadron capacity for Domestikos awareness
  let squadronCapacity = calculateSquadronCapacity(filtered)

  # Populate military intelligence domain (will be enhanced with patrol routes in Phase E below)
  result.military = MilitaryIntelligence(
    knownEnemyFleets: enemyFleets,
    enemyMilitaryCapability: initTable[HouseId, MilitaryCapabilityAssessment](),  # Phase D
    threatsByColony: threats,
    vulnerableTargets: vulnerableTargets,
    combatLessonsLearned: combatLessons,
    detectedPatrolRoutes: @[],  # Populated in Phase E below
    squadronCapacity: squadronCapacity,
    lastUpdated: filtered.turn
  )

  # Populate economic intelligence domain (will be enhanced with construction trends in Phase E below)
  result.economic = EconomicIntelligence(
    enemyEconomicStrength: enemyEcon,
    highValueTargets: highValueTargets,
    enemyTechGaps: initTable[HouseId, TechGapAnalysis](),  # Phase D
    constructionActivity: initTable[SystemId, ConstructionTrend](),  # Populated in Phase E below
    lastUpdated: filtered.turn
  )

  # Generate tech gap priorities from enemy tech intelligence
  let techGapPriorities = generateTechGapPriorities(filtered, enemyTech, controller)

  result.research = ResearchIntelligence(
    enemyTechLevels: enemyTech,
    techAdvantages: @[],  # TODO: Compute which fields we lead in
    techGaps: @[],  # TODO: Compute which fields we're behind in
    urgentResearchNeeds: techGapPriorities,
    lastUpdated: filtered.turn
  )

  # Phase D: Surveillance analysis
  let (surveillanceGaps, surveillanceCoverage) = analyzeSurveillanceReports(filtered, controller)

  # Log surveillance gaps (Phase D)
  if surveillanceGaps.len > 0:
    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Drungarius: {surveillanceGaps.len} surveillance gaps identified")
    for gap in surveillanceGaps:
      logDebug(LogCategory.lcAI,
               &"{controller.houseId} Drungarius:   Gap at {gap.systemId} ({gap.reason}, priority {gap.priority:.2f})")

  # === PHASE E: DIPLOMATIC, COUNTER-INTEL, CONSTRUCTION, PATROL ANALYSIS ===

  # Analyze diplomatic events and blockades (Phase E - CRITICAL)
  let (blockades, diplomaticEvents, hostility, potentialAllies, potentialThreats) =
    analyzeDiplomaticEvents(filtered, controller)

  # Analyze counter-intelligence (Phase E - HIGH)
  let (espionagePatterns, detectionRisks) = analyzeCounterIntelligence(filtered, controller)

  # Analyze construction trends (Phase E - MEDIUM)
  let constructionTrends = analyzeConstructionTrends(filtered, controller)

  # Detect patrol routes (Phase E - MEDIUM)
  let patrolRoutes = detectPatrolRoutes(filtered, controller)

  # Update military intelligence with patrol routes
  result.military.detectedPatrolRoutes = patrolRoutes

  # Update economic intelligence with construction trends
  result.economic.constructionActivity = constructionTrends

  # Populate diplomatic intelligence domain with Phase E data
  result.diplomatic = DiplomaticIntelligence(
    houseRelativeStrength: initTable[HouseId, HouseRelativeStrength](),  # Populated by calculateHouseRelativeStrength
    potentialAllies: potentialAllies,
    potentialThreats: potentialThreats,
    observedHostility: hostility,
    activeBlockades: blockades,
    recentDiplomaticEvents: diplomaticEvents,
    lastUpdated: filtered.turn
  )

  # Generate reconnaissance recommendations for Domestikos
  var reconTargets: seq[EspionageTarget] = @[]

  # Priority 1: SpyPlanet missions for visible enemy colonies (scout-only, detailed intel)
  for visibleColony in filtered.visibleColonies:
    if visibleColony.owner == controller.houseId:
      continue  # Skip own colonies

    # Check if we have fresh intelligence on this colony
    var needsIntel = true
    if filtered.ownHouse.intelligence.colonyReports.hasKey(visibleColony.systemId):
      let report = filtered.ownHouse.intelligence.colonyReports[visibleColony.systemId]
      let turnsSince = filtered.turn - report.gatheredTurn
      if turnsSince <= 10:
        needsIntel = false  # Fresh intel, no need to spy again yet

    if needsIntel:
      # Determine priority based on diplomatic stance
      let isEnemy = filtered.ownHouse.diplomaticRelations.isEnemy(visibleColony.owner)
      let scoutPriority = if isEnemy: RequirementPriority.High else: RequirementPriority.Medium

      # Recommend detailed spy mission (scout-only)
      reconTargets.add(EspionageTarget(
        targetType: EspionageTargetType.ColonySpy,
        systemId: some(visibleColony.systemId),
        houseId: visibleColony.owner,
        priority: scoutPriority,
        reason: if isEnemy: "Enemy colony reconnaissance" else: "Foreign colony surveillance",
        lastAttemptTurn: none(int)
      ))

  # Priority 2: ViewWorld missions for unexplored systems (any ship type, basic intel)
  # Recommend basic reconnaissance of visible but unintelligenced systems
  for systemId in filtered.visibleSystems.keys:
    # Skip if we already have colony intel for this system
    if filtered.ownHouse.intelligence.colonyReports.hasKey(systemId):
      continue

    # Skip if it's one of our own colonies
    var isOwnColony = false
    for colony in filtered.ownColonies:
      if colony.systemId == systemId:
        isOwnColony = true
        break
    if isOwnColony:
      continue

    # Recommend basic ViewWorld reconnaissance (any fleet can do this)
    reconTargets.add(EspionageTarget(
      targetType: EspionageTargetType.ScoutRecon,
      systemId: some(systemId),
      houseId: controller.houseId,  # Not specific to any house
      priority: RequirementPriority.Low,
      reason: "Basic system reconnaissance",
      lastAttemptTurn: none(int)
    ))

  # Log reconnaissance recommendations
  if reconTargets.len > 0:
    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Drungarius: Recommending {reconTargets.len} reconnaissance missions")

  result.espionage = EspionageIntelligence(
    intelCoverage: initTable[HouseId, IntelCoverageScore](),
    staleIntelSystems: @[],
    highPriorityTargets: reconTargets,
    detectionRisks: detectionRisks,
    espionagePatterns: espionagePatterns,
    surveillanceGaps: surveillanceGaps,
    surveillanceCoverage: surveillanceCoverage,
    lastUpdated: filtered.turn
  )

  # Log Phase E intelligence summary
  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Drungarius: Phase E intelligence - " &
          &"{blockades.len} blockades, " &
          &"{diplomaticEvents.len} diplomatic events, " &
          &"{espionagePatterns.len} espionage patterns, " &
          &"{constructionTrends.len} construction trends, " &
          &"{patrolRoutes.len} patrol routes detected")

  # === BACKWARD COMPATIBILITY: Populate legacy fields ===

  # Extract known enemy colonies from military intel
  for target in vulnerableTargets:
    result.knownEnemyColonies.add((target.systemId, target.owner))
  for target in highValueTargets:
    var alreadyAdded = false
    for known in result.knownEnemyColonies:
      if known.systemId == target.systemId:
        alreadyAdded = true
        break
    if not alreadyAdded:
      result.knownEnemyColonies.add((target.systemId, target.owner))

  # Extract high-value targets
  for target in highValueTargets:
    result.highValueTargets.add(target.systemId)

  # Convert ThreatAssessment to legacy ThreatLevel format
  for systemId, threat in threats:
    result.threatAssessment[systemId] = threat.level

  # Fleet movements (from existing implementation below)
  result.enemyFleetMovements = initTable[HouseId, seq[FleetMovement]]()

  # Report counts for debugging
  result.reportCounts = (
    colonies: filtered.ownHouse.intelligence.colonyReports.len,
    systems: filtered.ownHouse.intelligence.systemReports.len,
    starbases: filtered.ownHouse.intelligence.starbaseReports.len,
    combat: filtered.ownHouse.intelligence.combatReports.len,
    surveillance: filtered.ownHouse.intelligence.starbaseSurveillance.len
  )

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Drungarius: Enhanced intelligence - " &
          &"{enemyFleets.len} enemy fleets, " &
          &"{threats.len} threats, " &
          &"{vulnerableTargets.len} vulnerable targets, " &
          &"{highValueTargets.len} high-value targets")

  # === LEGACY PROCESSING (keep for now) ===
  # Aggregate all known enemy colonies from intelligence database
  for systemId, colonyReport in filtered.ownHouse.intelligence.colonyReports:
    if colonyReport.targetOwner != controller.houseId:
      # Non-self colony = potential target
      result.knownEnemyColonies.add((systemId, colonyReport.targetOwner))

      # Check if this is a high-value target (weak defenses)
      let hasDefenders = block:
        var found = false
        for fleetId, history in filtered.ownHouse.intelligence.fleetMovementHistory:
          if history.owner == colonyReport.targetOwner and
             history.lastKnownLocation == systemId:
            found = true
            break
        found

      if not hasDefenders and colonyReport.industry > 0:
        # Undefended colony with production = high value target
        result.highValueTargets.add(systemId)
        logInfo(LogCategory.lcAI,
                &"{controller.houseId} Drungarius: High-value target identified - " &
                &"system {systemId} (owner: {colonyReport.targetOwner}, industry: {colonyReport.industry})")

  # === ENEMY FLEET MOVEMENTS ===
  # Track enemy fleet positions per house
  for fleetId, history in filtered.ownHouse.intelligence.fleetMovementHistory:
    if history.owner != controller.houseId:
      let movement = FleetMovement(
        fleetId: fleetId,
        owner: history.owner,
        lastKnownLocation: history.lastKnownLocation,
        lastSeenTurn: history.lastSeen,
        estimatedStrength: 0  # TODO: Add strength tracking in future
      )

      if not result.enemyFleetMovements.hasKey(history.owner):
        result.enemyFleetMovements[history.owner] = @[]
      result.enemyFleetMovements[history.owner].add(movement)

  # === THREAT ASSESSMENT ===
  # Assess threats to our own colonies
  for colony in filtered.ownColonies:
    let threat = assessThreat(filtered, colony.systemId, controller)
    if threat != intelligence_types.ThreatLevel.tlNone:
      result.threatAssessment[colony.systemId] = threat
      logInfo(LogCategory.lcAI,
              &"{controller.houseId} Drungarius: Threat {threat} detected at colony {colony.systemId}")

  # === STALE INTEL SYSTEMS ===
  # Identify systems that need reconnaissance
  # Check all visible systems first
  for systemId in filtered.visibleSystems.keys:
    if needsReconnaissance(filtered, systemId, controller):
      result.staleIntelSystems.add(systemId)

  # Also check systems in intelligence database but not currently visible
  for systemId in filtered.ownHouse.intelligence.colonyReports.keys:
    if not filtered.visibleSystems.hasKey(systemId):
      if needsReconnaissance(filtered, systemId, controller):
        result.staleIntelSystems.add(systemId)

  if result.staleIntelSystems.len > 0:
    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Drungarius: {result.staleIntelSystems.len} systems need reconnaissance")

  # === ESPIONAGE OPPORTUNITIES ===
  # Identify houses that are good targets for espionage
  let house = filtered.ownHouse
  let myPrestige = house.prestige

  for houseId, prestige in filtered.housePrestige:
    if houseId == controller.houseId:
      continue

    let prestigeGap = prestige - myPrestige
    let relation = dip_types.getDiplomaticState(house.diplomaticRelations, houseId)

    # Prioritize: enemies, prestige leaders, economic powerhouses
    if relation == dip_types.DiplomaticState.Enemy or prestigeGap > 100:
      result.espionageOpportunities.add(houseId)

  # Summary logging
  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Drungarius: Intelligence summary - " &
          &"{result.knownEnemyColonies.len} enemy colonies, " &
          &"{result.highValueTargets.len} high-value targets, " &
          &"{result.threatAssessment.len} threats, " &
          &"{result.staleIntelSystems.len} stale intel, " &
          &"{result.espionageOpportunities.len} espionage opportunities")

  return result
