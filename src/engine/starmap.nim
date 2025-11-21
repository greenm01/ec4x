## Robust Starmap Implementation for EC4X
##
## This module provides a simplified, robust starmap implementation that:
## - Follows the game specification exactly
## - Handles all edge cases gracefully
## - Prioritizes correctness over complex optimizations
## - Implements actual game rules for lane traversal
## - Provides fast, reliable starmap generation and pathfinding

import fleet, ship
import ../common/[hex, system, types/combat]
import std/[tables, sequtils, random, math, algorithm, hashes, sets]
import std/options

type
  StarMapError* = object of CatchableError

  StarMap* = object
    systems*: Table[uint, System]
    lanes*: seq[JumpLane]
    adjacency*: Table[uint, seq[uint]]
    playerCount*: int
    numRings*: uint32
    hubId*: uint
    playerSystemIds*: seq[uint]

  JumpLane* = object
    source*: uint
    destination*: uint
    laneType*: LaneType

  PathResult* = object
    path*: seq[uint]
    totalCost*: uint32
    found*: bool

# Constants for robust behavior
const
  minPlayers = 2
  maxPlayers = 12
  maxVertexPlayers = 4  # Hex grids only have 4 true vertices

proc validatePlayerCount(count: int) =
  if count < minPlayers or count > maxPlayers:
    raise newException(StarMapError, "Player count must be between " & $minPlayers & " and " & $maxPlayers)

proc newStarMap*(playerCount: int): StarMap =
  validatePlayerCount(playerCount)

  StarMap(
    systems: initTable[uint, System](),
    lanes: @[],
    adjacency: initTable[uint, seq[uint]](),
    playerCount: playerCount,
    numRings: playerCount.uint32,
    hubId: 0,
    playerSystemIds: @[]
  )

proc addSystem(starMap: var StarMap, system: System) =
  starMap.systems[system.id] = system

proc addLane(starMap: var StarMap, lane: JumpLane) =
  # Validate lane endpoints exist
  if lane.source notin starMap.systems or lane.destination notin starMap.systems:
    raise newException(StarMapError, "Lane endpoints must exist in starmap")

  # Prevent duplicate lanes
  for existingLane in starMap.lanes:
    if (existingLane.source == lane.source and existingLane.destination == lane.destination) or
       (existingLane.source == lane.destination and existingLane.destination == lane.source):
      return  # Lane already exists

  starMap.lanes.add(lane)

  # Update adjacency (bidirectional)
  if lane.source notin starMap.adjacency:
    starMap.adjacency[lane.source] = @[]
  if lane.destination notin starMap.adjacency:
    starMap.adjacency[lane.destination] = @[]

  starMap.adjacency[lane.source].add(lane.destination)
  starMap.adjacency[lane.destination].add(lane.source)

proc getAdjacentSystems*(starMap: StarMap, systemId: uint): seq[uint] =
  starMap.adjacency.getOrDefault(systemId, @[])

proc countHexNeighbors*(starMap: StarMap, coords: Hex): int =
  var count = 0
  for dir in 0..5:
    let neighborCoord = coords.neighbor(dir)
    let neighborId = neighborCoord.toId(starMap.numRings)
    if neighborId in starMap.systems:
      count += 1
  return count

proc generateHexGrid(starMap: var StarMap) =
  ## Generate hexagonal grid following game specification
  let center = hex(0, 0)

  # Add hub system at center
  let hub = newSystem(center, 0, starMap.numRings, none(uint))
  starMap.hubId = hub.id
  starMap.addSystem(hub)

  # Generate all systems in rings
  let allHexes = center.withinRadius(starMap.numRings.int32)
  for hexCoord in allHexes:
    if hexCoord == center:
      continue

    let ring = distance(hexCoord, center)
    let system = newSystem(hexCoord, ring, starMap.numRings, none(uint))
    starMap.addSystem(system)

proc assignPlayerHomeworlds(starMap: var StarMap) =
  ## Assign player homeworlds following game specification
  var outerRingSystems: seq[System] = @[]
  for system in starMap.systems.values:
    if system.ring == starMap.numRings:
      outerRingSystems.add(system)

  if outerRingSystems.len < starMap.playerCount:
    raise newException(StarMapError, "Not enough outer ring systems for all players")

  # Sort by angle for even distribution
  outerRingSystems.sort do (a, b: System) -> int:
    let angleA = arctan2(a.coords.r.float64, a.coords.q.float64)
    let angleB = arctan2(b.coords.r.float64, b.coords.q.float64)
    cmp(angleA, angleB)

  # Player placement strategy based on game spec
  var selectedSystems: seq[System] = @[]

  if starMap.playerCount <= maxVertexPlayers:
    # Use vertices (corners) for optimal strategic placement
    let vertices = outerRingSystems.filterIt(starMap.countHexNeighbors(it.coords) == 3)

    if vertices.len >= starMap.playerCount:
      # Use vertices directly
      for i in 0..<starMap.playerCount:
        selectedSystems.add(vertices[i])
    else:
      # Fall back to maximizing distance
      selectedSystems = @[outerRingSystems[0]]  # Start with first system

      for i in 1..<starMap.playerCount:
        var bestSystem = outerRingSystems[1]
        var maxMinDistance = 0.0

        # Find system that maximizes minimum distance to existing players
        for candidate in outerRingSystems:
          if candidate in selectedSystems:
            continue

          var minDistance = float.high
          for existing in selectedSystems:
            let dist = distance(candidate.coords, existing.coords).float64
            minDistance = min(minDistance, dist)

          if minDistance > maxMinDistance:
            maxMinDistance = minDistance
            bestSystem = candidate

        selectedSystems.add(bestSystem)
  else:
    # Even distribution for larger player counts
    let step = outerRingSystems.len.float64 / starMap.playerCount.float64
    for i in 0..<starMap.playerCount:
      let index = int(i.float64 * step) mod outerRingSystems.len
      selectedSystems.add(outerRingSystems[index])

  # Assign players to selected systems
  for i, system in selectedSystems:
    starMap.systems[system.id].player = some(i.uint)
    starMap.playerSystemIds.add(system.id)

proc connectHub(starMap: var StarMap) =
  ## Connect hub with exactly 6 major lanes to first ring (game spec)
  let hubSystem = starMap.systems[starMap.hubId]

  var ring1Neighbors: seq[uint] = @[]
  for system in starMap.systems.values:
    if system.ring == 1 and distance(system.coords, hubSystem.coords) == 1:
      ring1Neighbors.add(system.id)

  if ring1Neighbors.len != 6:
    raise newException(StarMapError, "Hub must have exactly 6 first-ring neighbors")

  # Connect with Major lanes as per spec
  for neighborId in ring1Neighbors:
    let lane = JumpLane(source: starMap.hubId, destination: neighborId, laneType: LaneType.Major)
    starMap.addLane(lane)

proc connectPlayerSystems(starMap: var StarMap) =
  ## Connect player systems with exactly 3 lanes each (game spec)
  for playerId in starMap.playerSystemIds:
    let system = starMap.systems[playerId]

    # Find all potential neighbors
    var neighbors: seq[uint] = @[]
    for dir in 0..5:
      let neighborCoord = system.coords.neighbor(dir)
      let neighborId = neighborCoord.toId(starMap.numRings)
      if neighborId in starMap.systems:
        neighbors.add(neighborId)

    # Remove already connected neighbors
    let existing = starMap.getAdjacentSystems(playerId)
    neighbors = neighbors.filterIt(it notin existing)

    # Connect to exactly 3 neighbors (game spec requirement)
    if neighbors.len < 3:
      raise newException(StarMapError, "Player system must have at least 3 available neighbors")

    neighbors.shuffle()
    for i in 0..<min(3, neighbors.len):
      let laneType = if i < 3: LaneType.Major else: LaneType.Minor
      let lane = JumpLane(source: playerId, destination: neighbors[i], laneType: laneType)
      starMap.addLane(lane)

proc connectRemainingSystem(starMap: var StarMap) =
  ## Connect all remaining systems with random lane types
  for system in starMap.systems.values:
    if system.ring == 0 or system.player.isSome:
      continue  # Skip hub and player systems

    # Find unconnected neighbors
    var neighbors: seq[uint] = @[]
    for dir in 0..5:
      let neighborCoord = system.coords.neighbor(dir)
      let neighborId = neighborCoord.toId(starMap.numRings)
      if neighborId in starMap.systems:
        neighbors.add(neighborId)

    let existing = starMap.getAdjacentSystems(system.id)
    neighbors = neighbors.filterIt(it notin existing)

    # Connect to available neighbors with random lane types
    for neighborId in neighbors:
      # Check if neighbor is a player system that already has 3 connections
      let neighborSystem = starMap.systems[neighborId]
      if neighborSystem.player.isSome:
        let neighborConnections = starMap.getAdjacentSystems(neighborId)
        if neighborConnections.len >= 3:
          continue  # Skip connecting to player systems that already have 3 connections

      let laneType = sample([LaneType.Major, LaneType.Minor, LaneType.Restricted])
      let lane = JumpLane(source: system.id, destination: neighborId, laneType: laneType)
      starMap.addLane(lane)

proc generateLanes(starMap: var StarMap) =
  ## Generate all jump lanes following game specification
  randomize()

  try:
    starMap.connectHub()
    starMap.connectPlayerSystems()
    starMap.connectRemainingSystem()
  except StarMapError:
    raise
  except:
    raise newException(StarMapError, "Failed to generate lanes: " & getCurrentExceptionMsg())

proc validateConnectivity*(starMap: StarMap): bool =
  ## Validate that all systems are reachable from hub
  if starMap.systems.len == 0:
    return false

  var visited = initHashSet[uint]()
  var queue = @[starMap.hubId]
  visited.incl(starMap.hubId)

  while queue.len > 0:
    let current = queue.pop()
    for neighbor in starMap.getAdjacentSystems(current):
      if neighbor notin visited:
        visited.incl(neighbor)
        queue.add(neighbor)

  return visited.len == starMap.systems.len

proc canFleetTraverseLane*(fleet: Fleet, laneType: LaneType): bool =
  ## Check if fleet can traverse lane type per game rules
  case laneType:
  of LaneType.Major, LaneType.Minor:
    return true
  of LaneType.Restricted:
    # Restricted lanes: no crippled ships or spacelift command
    for ship in fleet.ships:
      if ship.isCrippled or ship.shipType == ShipType.Spacelift:
        return false
    return true

proc weight*(laneType: LaneType): uint32 =
  ## Get movement cost for lane type (for pathfinding)
  case laneType:
  of LaneType.Major:
    1  # Standard cost
  of LaneType.Minor:
    2  # Higher cost (less desirable)
  of LaneType.Restricted:
    3  # Highest cost (most restrictive)

proc findPath*(starMap: StarMap, start: uint, goal: uint, fleet: Fleet): PathResult =
  ## Robust A* pathfinding with game rule compliance
  if start == goal:
    return PathResult(path: @[start], totalCost: 0, found: true)

  if start notin starMap.systems or goal notin starMap.systems:
    return PathResult(path: @[], totalCost: 0, found: false)

  var openSet = @[(0'u32, start)]
  var cameFrom = initTable[uint, uint]()
  var gScore = initTable[uint, uint32]()
  var fScore = initTable[uint, uint32]()

  gScore[start] = 0
  fScore[start] = distance(starMap.systems[start].coords, starMap.systems[goal].coords)

  while openSet.len > 0:
    # Find node with lowest fScore
    var currentIdx = 0
    for i in 1..<openSet.len:
      if openSet[i][0] < openSet[currentIdx][0]:
        currentIdx = i

    let current = openSet[currentIdx][1]
    openSet.del(currentIdx)

    if current == goal:
      # Reconstruct path
      var path = @[current]
      var node = current
      while node in cameFrom:
        node = cameFrom[node]
        path.add(node)
      path.reverse()
      return PathResult(path: path, totalCost: gScore[current], found: true)

    # Explore neighbors
    for neighbor in starMap.getAdjacentSystems(current):
      # Find lane type between current and neighbor
      var laneType = LaneType.Major  # Default
      for lane in starMap.lanes:
        if (lane.source == current and lane.destination == neighbor) or
           (lane.source == neighbor and lane.destination == current):
          laneType = lane.laneType
          break

      # Check if fleet can traverse this lane
      if not canFleetTraverseLane(fleet, laneType):
        continue

      let tentativeGScore = gScore.getOrDefault(current, uint32.high) + laneType.weight

      if tentativeGScore < gScore.getOrDefault(neighbor, uint32.high):
        cameFrom[neighbor] = current
        gScore[neighbor] = tentativeGScore
        fScore[neighbor] = tentativeGScore + distance(starMap.systems[neighbor].coords, starMap.systems[goal].coords)

        # Add to open set if not present
        var inOpenSet = false
        for item in openSet:
          if item[1] == neighbor:
            inOpenSet = true
            break

        if not inOpenSet:
          openSet.add((fScore[neighbor], neighbor))

  return PathResult(path: @[], totalCost: 0, found: false)

proc populate*(starMap: var StarMap) =
  ## Main population function - generates complete starmap
  try:
    starMap.generateHexGrid()
    starMap.assignPlayerHomeworlds()
    starMap.generateLanes()

    # Validate result
    if not starMap.validateConnectivity():
      raise newException(StarMapError, "Generated starmap is not fully connected")

    # Validate player count
    if starMap.playerSystemIds.len != starMap.playerCount:
      raise newException(StarMapError, "Incorrect number of player systems assigned")

  except StarMapError:
    raise
  except:
    raise newException(StarMapError, "Failed to populate starmap: " & getCurrentExceptionMsg())

proc starMap*(playerCount: int): StarMap =
  ## Create a complete, validated starmap
  result = newStarMap(playerCount)
  result.populate()

# Debugging and analysis functions
proc getStarMapStats*(starMap: StarMap): string =
  ## Get comprehensive starmap statistics
  var stats = "StarMap Statistics:\n"
  stats &= "  Players: " & $starMap.playerCount & "\n"
  stats &= "  Rings: " & $starMap.numRings & "\n"
  stats &= "  Total Systems: " & $starMap.systems.len & "\n"
  stats &= "  Total Lanes: " & $starMap.lanes.len & "\n"

  # Count lane types
  var laneCount = [0, 0, 0]  # Major, Minor, Restricted
  for lane in starMap.lanes:
    laneCount[ord(lane.laneType)] += 1

  stats &= "  Major Lanes: " & $laneCount[0] & "\n"
  stats &= "  Minor Lanes: " & $laneCount[1] & "\n"
  stats &= "  Restricted Lanes: " & $laneCount[2] & "\n"

  # Connectivity check
  stats &= "  Fully Connected: " & $starMap.validateConnectivity() & "\n"

  return stats

proc verifyGameRules*(starMap: StarMap): bool =
  ## Verify starmap follows all game specification rules
  try:
    # Hub should have exactly 6 lanes
    let hubConnections = starMap.getAdjacentSystems(starMap.hubId)
    if hubConnections.len != 6:
      return false

    # Player systems should have exactly 3 lanes each
    for playerId in starMap.playerSystemIds:
      let connections = starMap.getAdjacentSystems(playerId)
      if connections.len != 3:
        return false

    # All systems should be reachable
    if not starMap.validateConnectivity():
      return false

    return true
  except:
    return false

# Additional convenience functions for compatibility
proc isReachable*(starMap: StarMap, start: uint, goal: uint, fleet: Fleet): bool =
  ## Check if goal is reachable from start with given fleet
  let path = findPath(starMap, start, goal, fleet)
  return path.found

proc findPathsInRange*(starMap: StarMap, start: uint, maxCost: uint32, fleet: Fleet): seq[uint] =
  ## Find all systems reachable within a given movement cost
  var visited = initHashSet[uint]()
  var queue = @[start]
  var distances = initTable[uint, uint32]()
  distances[start] = 0
  visited.incl(start)

  while queue.len > 0:
    var nextQueue: seq[uint] = @[]
    for current in queue:
      let currentCost = distances[current]
      if currentCost >= maxCost:
        continue

      for neighbor in starMap.getAdjacentSystems(current):
        if neighbor notin visited:
          let newCost = currentCost + 1  # Simplified cost calculation
          if newCost <= maxCost:
            distances[neighbor] = newCost
            visited.incl(neighbor)
            nextQueue.add(neighbor)

    queue = nextQueue
    if queue.len == 0:
      break

  return visited.toSeq()

proc getPathCost*(starMap: StarMap, path: seq[uint], fleet: Fleet): uint32 =
  ## Calculate the total cost of a path for a given fleet
  var totalCost: uint32 = 0
  for i in 0..<(path.len - 1):
    let fromId = path[i]
    let toId = path[i + 1]

    # Find the lane between these systems
    for lane in starMap.lanes:
      if (lane.source == fromId and lane.destination == toId) or
         (lane.source == toId and lane.destination == fromId):
        if canFleetTraverseLane(fleet, lane.laneType):
          totalCost += lane.laneType.weight
        else:
          return uint32.high  # Cannot traverse this lane
        break

  return totalCost

proc playerSystems*(starMap: StarMap, playerId: uint): seq[System] =
  ## Get all systems owned by a specific player
  var systems: seq[System] = @[]
  for system in starMap.systems.values:
    if system.player.isSome and system.player.get == playerId:
      systems.add(system)
  return systems
