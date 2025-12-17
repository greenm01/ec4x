## Defensive Operations Sub-module
## Handles smart defensive consolidation and colony protection
##
## Key Strategy:
## - Assign Defender fleets to colonies based on proximity (not first-come-first-served)
## - Prioritize high-value colonies (high production, frontier locations)
## - Ensure homeworld always has at least 1 defender
## - Use existing standing orders when possible (don't churn assignments)

import std/[options, tables, sets, algorithm, strformat]
import ../../../common/types/core
import ../../../engine/[gamestate, fog_of_war, fleet, standing_orders, starmap, logger]
import ../controller_types
import ../config  # For globalRBAConfig
import ../shared/intelligence_types  # Phase F: Intelligence integration
import ./fleet_analysis

# Types imported from fleet_analysis submodule
# FleetUtilization and FleetAnalysis are defined there

type
  ColonyDefenseAssignment = object
    ## Proposed assignment of a fleet to a colony
    colonySystemId: SystemId
    fleetId: FleetId
    distance: int  # Jump distance from fleet to colony
    priority: float  # Priority score (higher = more important)

proc calculateColonyDefensePriority(
  colony: Colony,
  filtered: FilteredGameState,
  homeworld: SystemId,
  controller: AIController,
  intelSnapshot: Option[IntelligenceSnapshot] = none(IntelligenceSnapshot)  # Phase F: Intelligence integration
): float =
  ## Calculate defense priority for a colony (Phase F: Intelligence-aware)
  ## Higher values = more important to defend
  var priority = 0.0

  # Base priority: production value
  priority += colony.production.float * controller.rbaConfig.domestikos_defensive.production_weight

  # Bonus: homeworld is always highest priority
  if colony.systemId == homeworld:
    priority += 1000.0

  # === PHASE F: INTELLIGENCE-DRIVEN PRIORITY BOOST ===
  if intelSnapshot.isSome:
    let snapshot = intelSnapshot.get()

    # Priority boost for colonies under active threat
    if snapshot.military.threatsByColony.hasKey(colony.systemId):
      let threat: ThreatAssessment = snapshot.military.threatsByColony[colony.systemId]
      case threat.level
      of tlCritical:
        priority += controller.rbaConfig.domestikos_defensive.threat_boost_critical
        logInfo(LogCategory.lcAI,
                &"{controller.houseId} Domestikos: CRITICAL THREAT at colony {colony.systemId} - defensive priority boosted")
      of tlHigh:
        priority += controller.rbaConfig.domestikos_defensive.threat_boost_high
      of tlModerate:
        priority += controller.rbaConfig.domestikos_defensive.threat_boost_moderate
      of tlNone, tlLow:
        discard  # No priority boost for low/no threats

    # Priority boost for blockaded colonies (60% GCO reduction = critical)
    for blockade in snapshot.diplomatic.activeBlockades:
      if blockade.systemId == colony.systemId and blockade.targetOwner == controller.houseId:
        priority += 150.0  # Active blockade = high defensive priority
        logInfo(LogCategory.lcAI,
                &"{controller.houseId} Domestikos: Blockade at colony {colony.systemId} - defensive priority boosted")
        break

    # Frontier detection based on enemy fleet proximity (replaces distance proxy)
    for enemyFleet in snapshot.military.knownEnemyFleets:
      let pathResult = filtered.starMap.findPath(enemyFleet.lastKnownLocation, colony.systemId, Fleet())
      if pathResult.found:
        let distance = pathResult.path.len
        if distance <= 2:  # Enemy fleet within 2 jumps = frontier colony
          priority += controller.rbaConfig.domestikos_defensive.owned_system_priority_boost
          break

    # Phase 4.3: Predictive threat from fleet movements
    # Detect approaching enemy fleets and boost defensive priority
    for houseId, movements in snapshot.enemyFleetMovements:
      for movement in movements:
        # Calculate distance from moved fleet to this colony
        let pathResult = filtered.starMap.findPath(movement.lastKnownLocation, colony.systemId, Fleet())
        if pathResult.found:
          let distance = pathResult.path.len
          # Fleet is approaching if within 3 jumps and recently moved
          if distance <= 3:
            # Priority boost scales with proximity and fleet strength
            let proximityMultiplier = case distance
              of 1: controller.rbaConfig.domestikos_defensive.proximity_multiplier_1_jump  # Adjacent = imminent threat
              of 2: controller.rbaConfig.domestikos_defensive.proximity_multiplier_2_jumps  # 2 jumps = near threat
              else: 1.0  # 3 jumps = potential threat

            let strengthFactor = float(movement.estimatedStrength) / 100.0
            let movementBoost = proximityMultiplier * strengthFactor * controller.rbaConfig.domestikos_defensive.movement_boost_base
            priority += movementBoost

            logDebug(LogCategory.lcAI,
                     &"{controller.houseId} Domestikos: Fleet movement detected - " &
                     &"{houseId} fleet {movement.fleetId} at distance {distance} from " &
                     &"{colony.systemId}, boost +{movementBoost:.1f}")

    # Phase 4.3: Staleness penalty for blind spots
    # Colonies with stale intel are potentially at risk
    if colony.systemId in snapshot.staleIntelSystems:
      # Reduce priority slightly for stale intel (unknown = risky to commit forces)
      priority *= controller.rbaConfig.domestikos_defensive.stale_intel_penalty
      logDebug(LogCategory.lcAI,
               &"{controller.houseId} Domestikos: Stale intel at {colony.systemId}, " &
               &"defensive priority reduced (blind spot)")
  else:
    # === FALLBACK: Distance-based frontier detection (legacy behavior) ===
    let pathToHomeworld = filtered.starMap.findPath(colony.systemId, homeworld, Fleet())
    if pathToHomeworld.found:
      let distance = pathToHomeworld.path.len
      priority += distance.float * controller.rbaConfig.domestikos_defensive.frontier_bonus_per_distance  # Frontier bonus (crude proxy)

  return priority

proc generateDefensiveReassignments*(
  filtered: FilteredGameState,
  analyses: seq[FleetAnalysis],
  controller: AIController,
  intelSnapshot: Option[IntelligenceSnapshot] = none(IntelligenceSnapshot)  # Phase F: Intelligence integration
): seq[ColonyDefenseAssignment] =
  ## Generate optimal fleet-to-colony assignments for defense (Phase F: Intelligence-aware)
  ## Uses proximity-based matching with intelligence-driven priority weighting
  result = @[]

  # Identify undefended colonies
  var undefendedColonies: seq[Colony] = @[]
  for colony in filtered.ownColonies:
    var isDefended = false

    # Check if any fleet with a DefendSystem order is assigned to this colony
    for fleetId, standingOrder in controller.standingOrders:
      if standingOrder.orderType == StandingOrderType.DefendSystem:
        if standingOrder.params.defendTargetSystem == colony.systemId:
          isDefended = true
          break

    if not isDefended:
      undefendedColonies.add(colony)

  if undefendedColonies.len == 0:
    # All colonies already defended
    return result

  # Identify available Defender fleets (idle or under-utilized)
  # CRITICAL: Reserve specialized fleets for their advisors
  # ETACs for Eparch colonization ONLY
  # Scouts for Drungarius reconnaissance ONLY
  var availableDefenders: seq[FleetAnalysis] = @[]
  for analysis in analyses:
    if analysis.utilization in {FleetUtilization.Idle, FleetUtilization.UnderUtilized}:
      if analysis.hasCombatShips and not analysis.hasETACs and not analysis.hasScouts:
        availableDefenders.add(analysis)

  if availableDefenders.len == 0:
    # No available defenders
    return result

  # Calculate all possible assignments with priorities
  var possibleAssignments: seq[ColonyDefenseAssignment] = @[]

  for colony in undefendedColonies:
    let colonyPriority = calculateColonyDefensePriority(
      colony, filtered, controller.homeworld, controller, intelSnapshot  # Phase F: Pass intelligence
    )

    for defender in availableDefenders:
      # Find fleet object
      var fleet: Option[Fleet] = none(Fleet)
      for f in filtered.ownFleets:
        if f.id == defender.fleetId:
          fleet = some(f)
          break

      if fleet.isNone:
        continue

      # Calculate distance
      let pathResult = filtered.starMap.findPath(
        defender.location, colony.systemId, fleet.get()
      )

      if pathResult.found:
        let distance = pathResult.path.len

        # Combined priority: colony priority / distance
        # (closer fleets preferred for high-priority colonies)
        let assignmentPriority = colonyPriority / (distance.float + 1.0)

        possibleAssignments.add(ColonyDefenseAssignment(
          colonySystemId: colony.systemId,
          fleetId: defender.fleetId,
          distance: distance,
          priority: assignmentPriority
        ))

  # Sort by priority (highest first)
  possibleAssignments.sort(proc(a, b: ColonyDefenseAssignment): int =
    if a.priority > b.priority: -1
    elif a.priority < b.priority: 1
    else: 0
  )

  # Greedy assignment: assign highest priority matches first
  var assignedFleets = initHashSet[FleetId]()
  var assignedColonies = initHashSet[SystemId]()

  for assignment in possibleAssignments:
    if assignment.fleetId notin assignedFleets and
       assignment.colonySystemId notin assignedColonies:
      result.add(assignment)
      assignedFleets.incl(assignment.fleetId)
      assignedColonies.incl(assignment.colonySystemId)

  return result

proc generateDefensiveOrders*(
  filtered: FilteredGameState,
  analyses: seq[FleetAnalysis],
  controller: var AIController,
  intelSnapshot: Option[IntelligenceSnapshot] = none(IntelligenceSnapshot)  # Phase F
): Table[FleetId, StandingOrder] =
  ## Generate defensive standing orders for fleets (Phase F: Intelligence-aware)
  ## Returns updated standing orders for defensive fleets
  result = initTable[FleetId, StandingOrder]()

  logDebug(LogCategory.lcAI,
           &"{controller.houseId} Domestikos: Analyzing defensive posture")

  # Generate optimal reassignments (Phase F: Pass intelligence)
  let reassignments = generateDefensiveReassignments(filtered, analyses, controller, intelSnapshot)

  if reassignments.len == 0:
    logDebug(LogCategory.lcAI,
             &"{controller.houseId} Domestikos: No defensive reassignments needed")
    return result

  # Create DefendSystem orders for reassignments
  for assignment in reassignments:
    # Find fleet
    var fleet: Option[Fleet] = none(Fleet)
    for f in filtered.ownFleets:
      if f.id == assignment.fleetId:
        fleet = some(f)
        break

    if fleet.isNone:
      continue

    # Create DefendSystem standing order
    let defendOrder = StandingOrder(
      fleetId: assignment.fleetId,
      orderType: StandingOrderType.DefendSystem,
      params: StandingOrderParams(
        orderType: StandingOrderType.DefendSystem,
        defendTargetSystem: assignment.colonySystemId,
        defendMaxRange: controller.rbaConfig.domestikos_defensive.defend_max_range
      ),
      roe: 7,  # Aggressive ROE for defense
      createdTurn: filtered.turn,
      lastActivatedTurn: 0,
      activationCount: 0,
      suspended: false
    )

    result[assignment.fleetId] = defendOrder

    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Domestikos: Assigned fleet {assignment.fleetId} " &
            &"to defend colony at system {assignment.colonySystemId} " &
            &"(distance: {assignment.distance} jumps, priority: {assignment.priority:.1f})")

  return result
