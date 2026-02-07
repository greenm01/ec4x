## Fleet Movement and Pathfinding
##
## This module contains business logic for fleet movement, pathfinding,
## and travel time calculations. It considers fleet composition, lane
## restrictions, and movement capabilities.
##
## **Architecture Note**: This is a @systems module containing algorithms
## and business logic. It does NOT manipulate indexes - use @entities/fleet_ops
## for create/destroy/move operations.

import std/[tables, options, sets, heapqueue]
import ../../types/[core, fleet, ship, starmap, game_state, combat]
import ../../state/engine

# =============================================================================
# Lane Traversal Validation
# =============================================================================

proc canFleetTraverseLane*(
    state: GameState,
    fleet: Fleet,
    laneType: LaneClass,
): bool =
  ## Check if a fleet can traverse a specific lane type
  ##
  ## Restricted lanes can ONLY be used by:
  ## - Solo ETAC fleets (not crippled)
  ##
  ## Design rationale: ETACs need restricted lane access for early game
  ## colonization speed. Combat ships cannot use restricted lanes.
  ##
  ## Returns: true if fleet can use this lane type

  # Major and Minor lanes allow all ships
  if laneType != LaneClass.Restricted:
    return true

  # Restricted lanes: ONLY non-crippled ETACs allowed
  # Any other ship type blocks the entire fleet
  var hasOnlyETACs = true
  var hasAtLeastOneShip = false
  
  for shipId in fleet.ships:
    let shipOpt = state.ship(shipId)
    if shipOpt.isNone:
      continue
    
    hasAtLeastOneShip = true
    let ship = shipOpt.get()
    
    # Crippled ships cannot use restricted lanes (any type)
    if ship.state == CombatState.Crippled:
      return false
    
    # Only ETACs can use restricted lanes
    if ship.shipClass != ShipClass.ETAC:
      hasOnlyETACs = false
  
  # Fleet can traverse if it contains only non-crippled ETACs
  return hasOnlyETACs and hasAtLeastOneShip

# =============================================================================
# Pathfinding Algorithms
# =============================================================================

# A* pathfinding node type
type PathNode = tuple[f: uint32, system: SystemId]

# Custom comparison for HeapQueue (compare by f-score only)
proc `<`(a, b: PathNode): bool =
  a.f < b.f

proc findPath*(
    state: GameState,
    start: SystemId,
    goal: SystemId,
    fleet: Fleet,
): PathResult =
  ## Find optimal path from start to goal considering fleet restrictions
  ##
  ## Uses A* algorithm with lane costs as weights:
  ## - Major lanes: cost 1
  ## - Minor lanes: cost 2
  ## - Restricted lanes: cost 3 (or impassable if fleet cannot traverse)
  ##
  ## Returns: PathResult with path sequence and total cost

  if start == goal:
    return PathResult(found: true, path: @[start], totalCost: 0)

  # A* data structures
  var openSet: HeapQueue[PathNode]
  var cameFrom: Table[SystemId, SystemId]
  var gScore: Table[SystemId, uint32]
  var fScore: Table[SystemId, uint32]

  # Initialize
  gScore[start] = 0'u32
  let h = state.starMap.distanceMatrix.getOrDefault((start, goal), 999'u32)
  fScore[start] = h
  openSet.push((h, start))

  while openSet.len > 0:
    let current = openSet.pop().system

    if current == goal:
      # Reconstruct path
      var path: seq[SystemId] = @[current]
      var node = current
      while node != start:
        node = cameFrom[node]
        path.insert(node, 0)

      return PathResult(
        found: true, path: path, totalCost: gScore[goal]
      )

    # Explore neighbors
    let neighbors = state.starMap.lanes.neighbors.getOrDefault(current, @[])
    for neighbor in neighbors:
      let laneClass = state.starMap.lanes.connectionInfo.getOrDefault(
        (current, neighbor), LaneClass.Minor
      )

      # Check if fleet can traverse this lane
      if not canFleetTraverseLane(state, fleet, laneClass):
        continue # Skip impassable lanes

      # Lane cost
      let edgeCost =
        case laneClass
        of LaneClass.Major: 1'u32
        of LaneClass.Minor: 2'u32
        of LaneClass.Restricted: 3'u32

      let tentativeGScore = gScore[current] + edgeCost

      if neighbor notin gScore or tentativeGScore < gScore[neighbor]:
        cameFrom[neighbor] = current
        gScore[neighbor] = tentativeGScore
        let h = state.starMap.distanceMatrix.getOrDefault((neighbor, goal), 999'u32)
        fScore[neighbor] = tentativeGScore + h
        openSet.push((fScore[neighbor], neighbor))

  # No path found
  return PathResult(found: false, path: @[], totalCost: 0)

proc isReachable*(
    state: GameState,
    start: SystemId,
    goal: SystemId,
    fleet: Fleet,
): bool =
  ## Check if goal is reachable from start with given fleet
  let path = findPath(state, start, goal, fleet)
  return path.found

proc findPathsInRange*(
    state: GameState,
    start: SystemId,
    maxCost: uint32,
    fleet: Fleet,
): seq[SystemId] =
  ## Find all systems reachable within a given movement cost
  ##
  ## Uses breadth-first search with fleet restrictions
  ## Useful for:
  ## - AI movement planning
  ## - UI movement range display
  ## - Tactical positioning analysis

  result = @[]
  var visited: HashSet[SystemId]
  var costMap: Table[SystemId, uint32]
  var queue: seq[SystemId] = @[start]

  costMap[start] = 0'u32
  visited.incl(start)

  while queue.len > 0:
    let current = queue[0]
    queue.delete(0)

    let currentCost = costMap[current]

    # Explore neighbors
    let neighbors = state.starMap.lanes.neighbors.getOrDefault(current, @[])
    for neighbor in neighbors:
      if neighbor in visited:
        continue

      let laneClass = state.starMap.lanes.connectionInfo.getOrDefault(
        (current, neighbor), LaneClass.Minor
      )

      # Check if fleet can traverse this lane
      if not canFleetTraverseLane(state, fleet, laneClass):
        continue

      # Calculate cost to reach neighbor
      let edgeCost =
        case laneClass
        of LaneClass.Major: 1'u32
        of LaneClass.Minor: 2'u32
        of LaneClass.Restricted: 3'u32

      let newCost = currentCost + edgeCost

      if newCost <= maxCost:
        visited.incl(neighbor)
        costMap[neighbor] = newCost
        queue.add(neighbor)
        result.add(neighbor)

  return result

proc pathCost*(
    state: GameState,
    path: seq[SystemId],
    fleet: Fleet,
): uint32 =
  ## Calculate the total cost of a path for a given fleet
  ##
  ## Returns uint32.high if path is invalid or fleet cannot traverse

  if path.len < 2:
    return 0'u32

  var totalCost = 0'u32

  for i in 0 ..< (path.len - 1):
    let current = path[i]
    let next = path[i + 1]

    # Get lane type
    let laneClass = state.starMap.lanes.connectionInfo.getOrDefault(
      (current, next), LaneClass.Minor
    )

    # Check if fleet can traverse
    if not canFleetTraverseLane(state, fleet, laneClass):
      return uint32.high

    # Add lane cost
    let edgeCost =
      case laneClass
      of LaneClass.Major: 1'u32
      of LaneClass.Minor: 2'u32
      of LaneClass.Restricted: 3'u32

    totalCost += edgeCost

  return totalCost

# =============================================================================
# Travel Time & ETA Calculations
# =============================================================================

proc calculateETA*(
    state: GameState,
    fromSystem: SystemId,
    toSystem: SystemId,
    fleet: Fleet,
    houseId: HouseId,
): Option[int] =
  ## Calculate estimated turns for fleet to reach
  ## target system using turn-by-turn simulation.
  ##
  ## Applies the same movement rules as
  ## resolveMovementCommand (mechanics.nim):
  ## - Major lanes through owned systems: 2 jumps/turn
  ## - All other lanes: 1 jump/turn
  ##
  ## Returns none if target is unreachable.

  if fromSystem == toSystem:
    return some(0)

  let pathResult = findPath(
    state, fromSystem, toSystem, fleet
  )

  if not pathResult.found:
    return none(int)

  let path = pathResult.path
  var pos = 0 # Index into path
  var turns = 0

  while pos < path.len - 1:
    turns += 1
    var jumpsThisTurn = 1

    # Check 2-jump major lane rule
    # (matches mechanics.nim resolveMovementCommand)
    if pos + 2 < path.len:
      # Check all systems along remaining path owned
      var allOwned = true
      for i in pos .. min(pos + 2, path.len - 1):
        let colOpt = state.colonyBySystem(path[i])
        if colOpt.isNone or
            colOpt.get().owner != houseId:
          allOwned = false
          break

      if allOwned:
        # Check next two edges are both Major
        var bothMajor = true
        for i in pos ..< pos + 2:
          let lc =
            state.starMap.lanes.connectionInfo
              .getOrDefault(
                (path[i], path[i + 1]),
                LaneClass.Minor,
              )
          if lc != LaneClass.Major:
            bothMajor = false
            break
        if bothMajor:
          jumpsThisTurn = 2

    pos += min(jumpsThisTurn, path.len - 1 - pos)

  return some(turns)

proc calculateMultiFleetETA*(
    state: GameState,
    assemblyPoint: SystemId,
    fleets: seq[Fleet],
    houseId: HouseId,
): Option[int] =
  ## Calculate when all fleets can reach assembly point
  ##
  ## Returns the maximum ETA (when the slowest fleet arrives)
  ## Returns none if any fleet cannot reach the assembly point
  ##
  ## Useful for coordinating multi-fleet operations

  if fleets.len == 0:
    return some(0)

  var maxETA = 0

  for fleet in fleets:
    let etaOpt = calculateETA(
      state, fleet.location, assemblyPoint,
      fleet, houseId,
    )

    if etaOpt.isNone:
      # Fleet cannot reach assembly point
      return none(int)

    let eta = etaOpt.get()
    if eta > maxETA:
      maxETA = eta

  return some(maxETA)
