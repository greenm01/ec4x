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
import ../../types/[core, game_state, fleet, squadron, ship, starmap]

# =============================================================================
# Lane Traversal Validation
# =============================================================================

proc canFleetTraverseLane*(
    fleet: Fleet,
    laneType: LaneType,
    squadrons: Squadrons,
    ships: Ships,
): bool =
  ## Check if a fleet can traverse a specific lane type
  ##
  ## Restricted lanes cannot be used by:
  ## - Crippled ships
  ## - Transport ships (ETAC, TroopTransport)
  ##
  ## Returns: true if fleet can use this lane type
  # TODO: Implement lane traversal validation
  # - Check for crippled ships in fleet
  # - Check for transport ships on restricted lanes
  # - Major/Minor lanes allow all ships
  return true

# =============================================================================
# Pathfinding Algorithms
# =============================================================================

proc findPath*(
    starMap: StarMap,
    start: SystemId,
    goal: SystemId,
    fleet: Fleet,
    squadrons: Squadrons,
    ships: Ships,
): PathResult =
  ## Find optimal path from start to goal considering fleet restrictions
  ##
  ## Uses A* algorithm with lane costs as weights:
  ## - Major lanes: cost 1
  ## - Minor lanes: cost 2
  ## - Restricted lanes: cost 3 (or impassable if fleet cannot traverse)
  ##
  ## Returns: PathResult with path sequence and total cost
  # TODO: Implement A* pathfinding with fleet restrictions
  # - Use starMap.lanes for adjacency
  # - Use canFleetTraverseLane() to check lane validity
  # - Use hex distance as heuristic
  result = PathResult(found: false, path: @[], totalCost: 0)

proc isReachable*(
    starMap: StarMap,
    start: SystemId,
    goal: SystemId,
    fleet: Fleet,
    squadrons: Squadrons,
    ships: Ships,
): bool =
  ## Check if goal is reachable from start with given fleet
  let path = findPath(starMap, start, goal, fleet, squadrons, ships)
  return path.found

proc findPathsInRange*(
    starMap: StarMap,
    start: SystemId,
    maxCost: uint32,
    fleet: Fleet,
    squadrons: Squadrons,
    ships: Ships,
): seq[SystemId] =
  ## Find all systems reachable within a given movement cost
  ##
  ## Uses breadth-first search with fleet restrictions
  ## Useful for:
  ## - AI movement planning
  ## - UI movement range display
  ## - Tactical positioning analysis
  # TODO: Implement BFS with cost limits and fleet restrictions
  result = @[]

proc getPathCost*(
    starMap: StarMap,
    path: seq[SystemId],
    fleet: Fleet,
    squadrons: Squadrons,
    ships: Ships,
): uint32 =
  ## Calculate the total cost of a path for a given fleet
  ##
  ## Returns uint32.high if path is invalid or fleet cannot traverse
  # TODO: Implement path cost calculation
  # - Sum lane costs along path
  # - Check fleet can traverse each lane
  # - Return high value if any lane is impassable
  return 0

# =============================================================================
# Travel Time & ETA Calculations
# =============================================================================

proc calculateETA*(
    starMap: StarMap,
    fromSystem: SystemId,
    toSystem: SystemId,
    fleet: Fleet,
    squadrons: Squadrons,
    ships: Ships,
): Option[int] =
  ## Calculate estimated turns for fleet to reach target system
  ##
  ## Returns none if target is unreachable
  ##
  ## Uses conservative estimate: assumes 1 jump per turn (enemy/neutral)
  ## Actual travel may be faster with major lanes through friendly space
  ##
  ## Useful for:
  ## - AI strategic planning
  ## - UI feedback to players
  ## - Coordinated fleet operations
  # TODO: Implement ETA calculation
  # - Use findPath() to get path cost
  # - Convert movement points to turns
  # - Consider territory ownership for movement rate
  return none(int)

proc calculateMultiFleetETA*(
    starMap: StarMap,
    assemblyPoint: SystemId,
    fleets: seq[Fleet],
    squadrons: Squadrons,
    ships: Ships,
): Option[int] =
  ## Calculate when all fleets can reach assembly point
  ##
  ## Returns the maximum ETA (when the slowest fleet arrives)
  ## Returns none if any fleet cannot reach the assembly point
  ##
  ## Useful for coordinating multi-fleet operations
  # TODO: Implement multi-fleet ETA calculation
  # - Calculate ETA for each fleet
  # - Return maximum ETA (slowest fleet)
  # - Return none if any fleet can't reach assembly
  return none(int)
