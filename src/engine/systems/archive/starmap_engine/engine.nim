## Starmap Engine for EC4X
##
## This module provides the logic for generating, validating, and pathfinding
## on the starmap. It operates on the StarMap data structures defined in
## `src/engine/types/map/`.

import std/[tables, sequtils, random, math, algorithm, hashes, sets, strutils, heapqueue]
import std/options
import ../../fleet
import ../../config/starmap_config
import ../../types/map/types
import ../../types/map/starmap_definition
import ../../common/types/core # For LaneType

# Constants for robust behavior
const
  minPlayers = 2
  maxPlayers = 12
  maxVertexPlayers = 4  # Hex grids only have 4 true vertices

proc validatePlayerCount(count: int) =
  if count < minPlayers or count > maxPlayers:
    raise newException(StarMapError, "Player count must be between " & $minPlayers & " and " & $maxPlayers)

proc validateMapRings*(rings: int, playerCount: int = 0): seq[string] =
  var errors: seq[string] = @[]
  if rings == 0:
    errors.add("Map rings must be >= 1 (zero rings not supported)")
    return errors
  if rings < 1:
    errors.add("Map rings must be >= 1 (got " & $rings & ")")
  elif rings > 20:
    errors.add("Map rings must be <= 20 (got " & $rings & ")")
  if playerCount > 0 and rings < playerCount:
    discard
  return errors

proc newStarMap*(playerCount: int, seed: int64 = 42): StarMap =
  validatePlayerCount(playerCount)
  StarMap(
    systems: initTable[uint, System](),
    lanes: @[],
    adjacency: initTable[uint, seq[uint]](),
    playerCount: playerCount,
    numRings: playerCount.uint32,
    hubId: 0,
    playerSystemIds: @[],
    seed: seed
  )

proc addSystem(starMap: var StarMap, system: System) =
  starMap.systems[system.id] = system

proc addLane(starMap: var StarMap, lane: JumpLane) =
  if lane.source notin starMap.systems or lane.destination notin starMap.systems:
    raise newException(StarMapError, "Lane endpoints must exist in starmap")
  for existingLane in starMap.lanes:
    if (existingLane.source == lane.source and existingLane.destination == lane.destination) or
       (existingLane.source == lane.destination and existingLane.destination == lane.source):
      return
  starMap.lanes.add(lane)
  starMap.laneMap[(lane.source, lane.destination)] = lane.laneType
  starMap.laneMap[(lane.destination, lane.source)] = lane.laneType
  if lane.source notin starMap.adjacency:
    starMap.adjacency[lane.source] = @[]
  if lane.destination notin starMap.adjacency:
    starMap.adjacency[lane.destination] = @[]
  starMap.adjacency[lane.source].add(lane.destination)
  starMap.adjacency[lane.destination].add(lane.source)

proc weightedSample[T](items: openArray[T], weights: openArray[float], rng: var Rand): T =
  let totalWeight = weights.sum()
  let r = rng.rand(1.0)
  var cumulative = 0.0
  for i, weight in weights:
    cumulative += weight / totalWeight
    if r <= cumulative:
      return items[i]
  return items[^1]

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
  let center = hex(0, 0)
  let hub = newSystem(center, 0, starMap.numRings, none(uint))
  starMap.hubId = hub.id
  starMap.addSystem(hub)
  let allHexes = center.withinRadius(starMap.numRings.int32)
  for hexCoord in allHexes:
    if hexCoord == center:
      continue
    let ring = distance(hexCoord, center)
    let system = newSystem(hexCoord, ring, starMap.numRings, none(uint))
    starMap.addSystem(system)

proc assignPlayerHomeworlds(starMap: var StarMap) =
  var allSystems: seq[System] = @[]
  for system in starMap.systems.values:
    if system.ring > 0:
      allSystems.add(system)
  if allSystems.len < starMap.playerCount:
    raise newException(StarMapError, "Not enough systems for all players")
  allSystems.sort do (a, b: System) -> int:
    let angleA = arctan2(a.coords.r.float64, a.coords.q.float64)
    let angleB = arctan2(b.coords.r.float64, b.coords.q.float64)
    cmp(angleA, angleB)
  var selectedSystems: seq[System] = @[]
  if starMap.playerCount <= maxVertexPlayers:
    let vertices = allSystems.filterIt(starMap.countHexNeighbors(it.coords) == 3)
    let candidateSystems = if vertices.len >= starMap.playerCount: vertices else: allSystems
    var rng = initRand(starMap.seed)
    var shuffledCandidates = candidateSystems
    rng.shuffle(shuffledCandidates)
    selectedSystems = @[shuffledCandidates[0]]
    for i in 1..<starMap.playerCount:
      var bestSystem = shuffledCandidates[1]
      var maxMinDistance = 0.0
      for candidate in shuffledCandidates:
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
    let step = allSystems.len.float64 / starMap.playerCount.float64
    for i in 0..<starMap.playerCount:
      let index = int(i.float64 * step) mod allSystems.len
      selectedSystems.add(allSystems[index])
  for i, system in selectedSystems:
    starMap.systems[system.id].player = some(i.uint)
    starMap.playerSystemIds.add(system.id)

proc connectHub(starMap: var StarMap, rng: var Rand) =
  let hubSystem = starMap.systems[starMap.hubId]
  var ring1Neighbors: seq[uint] = @[]
  for system in starMap.systems.values:
    if system.ring == 1 and distance(system.coords, hubSystem.coords) == 1:
      ring1Neighbors.add(system.id)
  if ring1Neighbors.len != 6:
    raise newException(StarMapError, "Hub must have exactly 6 first-ring neighbors")
  let weights = globalStarmapConfig.lane_weights
  for neighborId in ring1Neighbors:
    let laneType = weightedSample(
      [LaneType.Major, LaneType.Minor, LaneType.Restricted],
      [weights.major_weight, weights.minor_weight, weights.restricted_weight],
      rng
    )
    let lane = JumpLane(source: starMap.hubId, destination: neighborId, laneType: laneType)
    starMap.addLane(lane)

proc connectPlayerSystems(starMap: var StarMap, rng: var Rand) =
  let laneCount = globalStarmapConfig.homeworld_placement.homeworld_lane_count
  for playerId in starMap.playerSystemIds:
    let system = starMap.systems[playerId]
    var neighbors: seq[uint] = @[]
    for dir in 0..5:
      let neighborCoord = system.coords.neighbor(dir)
      let neighborId = neighborCoord.toId(starMap.numRings)
      if neighborId in starMap.systems:
        neighbors.add(neighborId)
    let existing = starMap.getAdjacentSystems(playerId)
    neighbors = neighbors.filterIt(it notin existing)
    if neighbors.len < laneCount:
      raise newException(StarMapError, "Player system must have at least " & $laneCount & " available neighbors")
    shuffle(rng, neighbors)
    for i in 0..<min(laneCount, neighbors.len):
      let laneType = if i < laneCount: LaneType.Major else: LaneType.Minor
      let lane = JumpLane(source: playerId, destination: neighbors[i], laneType: laneType)
      starMap.addLane(lane)

proc connectRemainingSystem(starMap: var StarMap, rng: var Rand) =
  for system in starMap.systems.values:
    if system.ring == 0 or system.player.isSome:
      continue
    var neighbors: seq[uint] = @[]
    for dir in 0..5:
      let neighborCoord = system.coords.neighbor(dir)
      let neighborId = neighborCoord.toId(starMap.numRings)
      if neighborId in starMap.systems:
        neighbors.add(neighborId)
    let existing = starMap.getAdjacentSystems(system.id)
    neighbors = neighbors.filterIt(it notin existing)
    for neighborId in neighbors:
      let neighborSystem = starMap.systems[neighborId]
      if neighborSystem.player.isSome:
        let neighborConnections = starMap.getAdjacentSystems(neighborId)
        if neighborConnections.len >= 3:
          continue
      let weights = globalStarmapConfig.lane_weights
      let laneType = weightedSample(
        [LaneType.Major, LaneType.Minor, LaneType.Restricted],
        [weights.major_weight, weights.minor_weight, weights.restricted_weight],
        rng
      )
      let lane = JumpLane(source: system.id, destination: neighborId, laneType: laneType)
      starMap.addLane(lane)

proc generateLanes(starMap: var StarMap) =
  var rng = initRand(starMap.seed)
  try:
    starMap.connectHub(rng)
    starMap.connectPlayerSystems(rng)
    starMap.connectRemainingSystem(rng)
  except StarMapError:
    raise
  except:
    raise newException(StarMapError, "Failed to generate lanes: " & getCurrentExceptionMsg())

proc validateConnectivity*(starMap: StarMap): bool =
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

proc validateHomeworldLanes*(starMap: StarMap): seq[string] =
  var errors: seq[string] = @[]
  for playerId in starMap.playerSystemIds:
    var majorLanes = 0
    var totalLanes = 0
    for lane in starMap.lanes:
      if lane.source == playerId or lane.destination == playerId:
        totalLanes += 1
        if lane.laneType == LaneType.Major:
          majorLanes += 1
    if totalLanes != 3:
      errors.add("Homeworld " & $playerId & " has " & $totalLanes & " lanes (expected 3)")
    if majorLanes != 3:
      errors.add("Homeworld " & $playerId & " has " & $majorLanes & " Major lanes (expected 3)")
  return errors

proc canFleetTraverseLane*(fleet: Fleet, laneType: LaneType): bool =
  case laneType:
  of LaneType.Major, LaneType.Minor:
    return true
  of LaneType.Restricted:
    for squadron in fleet.squadrons:
      if squadron.flagship.isCrippled:
        return false
    return true

proc weight*(laneType: LaneType): uint32 =
  case laneType:
  of LaneType.Major: 1
  of LaneType.Minor: 2
  of LaneType.Restricted: 3

proc getLaneType*(starMap: StarMap, fromSystem: SystemId, toSystem: SystemId): Option[LaneType] =
  for lane in starMap.lanes:
    if (lane.source == fromSystem and lane.destination == toSystem) or
       (lane.source == toSystem and lane.destination == fromSystem):
      return some(lane.laneType)
  return none(LaneType)

proc findPath*(starMap: StarMap, start: uint, goal: uint, fleet: Fleet): PathResult =
  if start == goal:
    return PathResult(path: @[start], totalCost: 0, found: true)
  if start notin starMap.systems or goal notin starMap.systems:
    return PathResult(path: @[], totalCost: 0, found: false)
  var openSet = initHeapQueue[(uint32, uint)]()
  var openSetNodes = initHashSet[uint]()
  var cameFrom = initTable[uint, uint]()
  var gScore = initTable[uint, uint32]()
  var fScore = initTable[uint, uint32]()
  gScore[start] = 0
  fScore[start] = starMap.distanceMatrix.getOrDefault((start, goal), 0)
  openSet.push((fScore[start], start))
  openSetNodes.incl(start)
  while openSet.len > 0:
    let (currentF, current) = openSet.pop()
    openSetNodes.excl(current)
    if current == goal:
      var path = @[current]
      var node = current
      while node in cameFrom:
        node = cameFrom[node]
        path.add(node)
      path.reverse()
      return PathResult(path: path, totalCost: gScore[current], found: true)
    for neighbor in starMap.getAdjacentSystems(current):
      let laneType = starMap.laneMap.getOrDefault((current, neighbor), LaneType.Major)
      if not canFleetTraverseLane(fleet, laneType):
        continue
      let tentativeGScore = gScore.getOrDefault(current, uint32.high) + laneType.weight
      if tentativeGScore < gScore.getOrDefault(neighbor, uint32.high):
        cameFrom[neighbor] = current
        gScore[neighbor] = tentativeGScore
        fScore[neighbor] = tentativeGScore + starMap.distanceMatrix.getOrDefault((neighbor, goal), 0)
        if neighbor notin openSetNodes:
          openSet.push((fScore[neighbor], neighbor))
          openSetNodes.incl(neighbor)
  return PathResult(path: @[], totalCost: 0, found: false)

proc buildDistanceMatrix(starMap: var StarMap) =
  for id1 in starMap.systems.keys:
    for id2 in starMap.systems.keys:
      if id1 != id2:
        let hex1 = starMap.systems[id1].coords
        let hex2 = starMap.systems[id2].coords
        starMap.distanceMatrix[(id1, id2)] = distance(hex1, hex2)

proc populate*(starMap: var StarMap) =
  try:
    starMap.generateHexGrid()
    starMap.assignPlayerHomeworlds()
    starMap.generateLanes()
    starMap.buildDistanceMatrix()
    if not starMap.validateConnectivity():
      raise newException(StarMapError, "Generated starmap is not fully connected - dead systems detected")
    if starMap.playerSystemIds.len != starMap.playerCount:
      raise newException(StarMapError, "Incorrect number of player systems assigned")
    let homeworldErrors = starMap.validateHomeworldLanes()
    if homeworldErrors.len > 0:
      raise newException(StarMapError, "Homeworld validation failed: " & homeworldErrors.join("; "))
  except StarMapError:
    raise
  except:
    raise newException(StarMapError, "Failed to populate starmap: " & getCurrentExceptionMsg())

proc starMap*(playerCount: int): StarMap =
  result = newStarMap(playerCount)
  result.populate()

proc getStarMapStats*(starMap: StarMap): string =
  var stats = "StarMap Statistics:\n"
  stats &= "  Players: " & $starMap.playerCount & "\n"
  stats &= "  Rings: " & $starMap.numRings & "\n"
  stats &= "  Total Systems: " & $starMap.systems.len & "\n"
  stats &= "  Total Lanes: " & $starMap.lanes.len & "\n"
  var laneCount = [0, 0, 0]
  for lane in starMap.lanes:
    laneCount[ord(lane.laneType)] += 1
  stats &= "  Major Lanes: " & $laneCount[0] & "\n"
  stats &= "  Minor Lanes: " & $laneCount[1] & "\n"
  stats &= "  Restricted Lanes: " & $laneCount[2] & "\n"
  stats &= "  Fully Connected: " & $starMap.validateConnectivity() & "\n"
  return stats

proc verifyGameRules*(starMap: StarMap): bool =
  try:
    let hubConnections = starMap.getAdjacentSystems(starMap.hubId)
    if hubConnections.len != 6:
      return false
    if not starMap.validateConnectivity():
      return false
    let homeworldErrors = starMap.validateHomeworldLanes()
    if homeworldErrors.len > 0:
      return false
    return true
  except:
    return false

proc isReachable*(starMap: StarMap, start: uint, goal: uint, fleet: Fleet): bool =
  let path = findPath(starMap, start, goal, fleet)
  return path.found

proc findPathsInRange*(starMap: StarMap, start: uint, maxCost: uint32, fleet: Fleet): seq[uint] =
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
          let newCost = currentCost + 1
          if newCost <= maxCost:
            distances[neighbor] = newCost
            visited.incl(neighbor)
            nextQueue.add(neighbor)
    queue = nextQueue
    if queue.len == 0:
      break
  return visited.toSeq()

proc getPathCost*(starMap: StarMap, path: seq[uint], fleet: Fleet): uint32 =
  var totalCost: uint32 = 0
  for i in 0..<(path.len - 1):
    let fromId = path[i]
    let toId = path[i + 1]
    for lane in starMap.lanes:
      if (lane.source == fromId and lane.destination == toId) or
         (lane.source == toId and lane.destination == fromId):
        if canFleetTraverseLane(fleet, lane.laneType):
          totalCost += lane.laneType.weight
        else:
          return uint32.high
        break
  return totalCost

proc playerSystems*(starMap: StarMap, playerId: uint): seq[System] =
  var systems: seq[System] = @[]
  for system in starMap.systems.values:
    if system.player.isSome and system.player.get == playerId:
      systems.add(system)
  return systems

proc calculateETA*(starMap: StarMap, fromSystem: SystemId, toSystem: SystemId,
                   fleet: Fleet): Option[int] =
  if fromSystem == toSystem:
    return some(0)
  let path = findPath(starMap, fromSystem, toSystem, fleet)
  if not path.found:
    return none(int)
  let estimatedTurns = max(1, int(path.totalCost))
  return some(estimatedTurns)

proc calculateMultiFleetETA*(starMap: StarMap, assemblyPoint: SystemId,
                              fleets: seq[Fleet]): Option[int] =
  var maxETA = 0
  for fleet in fleets:
    let eta = calculateETA(starMap, fleet.location, assemblyPoint, fleet)
    if eta.isNone:
      return none(int)
    maxETA = max(maxETA, eta.get())
  return some(maxETA)
