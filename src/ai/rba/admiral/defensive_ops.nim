## Defensive Operations Sub-module
## Handles smart defensive consolidation and colony protection
##
## Key Strategy:
## - Assign Defender fleets to colonies based on proximity (not first-come-first-served)
## - Prioritize high-value colonies (high production, frontier locations)
## - Ensure homeworld always has at least 1 defender
## - Use existing standing orders when possible (don't churn assignments)

import std/[sequtils, options, tables, sets, algorithm, strformat]
import ../../../common/system
import ../../../common/types/core
import ../../../engine/[gamestate, fog_of_war, fleet, standing_orders, starmap, logger]
import ../controller_types
import ./fleet_analysis

# Import types from parent module
{.push used.}
from ../admiral import FleetUtilization, FleetAnalysis
{.pop.}

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
  homeworld: SystemId
): float =
  ## Calculate defense priority for a colony
  ## Higher values = more important to defend
  var priority = 0.0

  # Base priority: production value
  priority += colony.production.float * 0.5

  # Bonus: homeworld is always highest priority
  if colony.systemId == homeworld:
    priority += 1000.0

  # Bonus: frontier colonies (adjacent to unowned/enemy systems)
  # TODO: Check for adjacent enemy/unowned systems when intel available
  # For now, use distance from homeworld as proxy (farther = more frontier)
  let pathToHomeworld = filtered.starMap.findPath(colony.systemId, homeworld, Fleet())
  if pathToHomeworld.found:
    let distance = pathToHomeworld.path.len
    priority += distance.float * 2.0  # Frontier bonus

  return priority

proc generateDefensiveReassignments*(
  filtered: FilteredGameState,
  analyses: seq[FleetAnalysis],
  controller: AIController
): seq[ColonyDefenseAssignment] =
  ## Generate optimal fleet-to-colony assignments for defense
  ## Uses proximity-based matching with priority weighting
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
  var availableDefenders: seq[FleetAnalysis] = @[]
  for analysis in analyses:
    if analysis.utilization in {FleetUtilization.Idle, FleetUtilization.UnderUtilized}:
      if analysis.hasCombatShips:
        availableDefenders.add(analysis)

  if availableDefenders.len == 0:
    # No available defenders
    return result

  # Calculate all possible assignments with priorities
  var possibleAssignments: seq[ColonyDefenseAssignment] = @[]

  for colony in undefendedColonies:
    let colonyPriority = calculateColonyDefensePriority(
      colony, filtered, controller.homeworld
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
  controller: var AIController
): Table[FleetId, StandingOrder] =
  ## Generate defensive standing orders for fleets
  ## Returns updated standing orders for defensive fleets
  result = initTable[FleetId, StandingOrder]()

  logDebug(LogCategory.lcAI,
           &"{controller.houseId} Admiral: Analyzing defensive posture")

  # Generate optimal reassignments
  let reassignments = generateDefensiveReassignments(filtered, analyses, controller)

  if reassignments.len == 0:
    logDebug(LogCategory.lcAI,
             &"{controller.houseId} Admiral: No defensive reassignments needed")
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
        defendMaxRange: 3
      ),
      roe: 7,  # Aggressive ROE for defense
      createdTurn: filtered.turn,
      lastExecutedTurn: 0,
      executionCount: 0,
      suspended: false
    )

    result[assignment.fleetId] = defendOrder

    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Admiral: Assigned fleet {assignment.fleetId} " &
            &"to defend colony at system {assignment.colonySystemId} " &
            &"(distance: {assignment.distance} jumps, priority: {assignment.priority:.1f})")

  return result
