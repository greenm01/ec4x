## Robust Starmap Implementation for EC4X
##
## This module provides a simplified, robust starmap implementation that:
## - Follows the game specification exactly
## - Handles all edge cases gracefully
## - Prioritizes correctness over complex optimizations
## - Implements actual game rules for lane traversal
## - Provides fast, reliable starmap generation and pathfinding
import std/[
  tables, sequtils, random, math, algorithm, hashes, sets,
  strutils, heapqueue, options
]

import types/[starmap, squadron, core]
import config/starmap_config

# Hex coordinate utilities
proc hex*(q, r: int32): Hex =
  ## Create a hex coordinate
  Hex(q: q, r: r)

proc distance*(a, b: Hex): uint32 =
  ## Calculate hex grid distance between two coordinates
  let dq = abs(a.q - b.q)
  let dr = abs(a.r - b.r)
  let ds = abs(a.q + a.r - b.q - b.r)
  return max(dq, max(dr, ds)).uint32

const HexDirections = [
  hex(1, 0), hex(1, -1), hex(0, -1),
  hex(-1, 0), hex(-1, 1), hex(0, 1)
]

proc neighbor*(h: Hex, direction: int): Hex =
  ## Get neighbor in given direction (0-5)
  let dir = HexDirections[direction mod 6]
  hex(h.q + dir.q, h.r + dir.r)

proc withinRadius*(center: Hex, radius: int32): seq[Hex] =
  ## Get all hex coordinates within radius of center (inclusive)
  result = @[]
  for q in -radius .. radius:
    let r1 = max(-radius, -q - radius)
    let r2 = min(radius, -q + radius)
    for r in r1 .. r2:
      result.add(hex(center.q + q, center.r + r))

proc findSystemByCoords(starMap: StarMap, coords: Hex): Option[SystemId] =
  ## Find a system by its hex coordinates
  ## Returns the SystemId if found, none if not found
  for system in starMap.systems.entities.data:
    if system.coords.q == coords.q and system.coords.r == coords.r:
      return some(system.id)
  return none(SystemId)

# Total systems = 1 + 3 × n × (n + 1)
# where n = number of rings (playerCount)
# This gives you:

# 2 players: 1 + 3(2)(3) = 19 systems (9.5 per player)
# 3 players: 1 + 3(3)(4) = 37 systems (12.3 per player)
# 4 players: 1 + 3(4)(5) = 61 systems (15.25 per player)
# 6 players: 1 + 3(6)(7) = 127 systems (21.2 per player)
# 12 players: 1 + 3(12)(13) = 469 systems (39.1 per player)

# The formula is: 3n² + 3n + 1 where n = playerCount.
#
# Systems per player scales non-linearly - larger games give significantly
# more strategic space per player. This matches 4X escalation patterns where
# bigger maps allow more complex empire building.

proc validatePlayerCount(count: int32) =
  # Hardcoded
  let minPlayers: int32 = 2
  let maxPlayers: int32 = 12
  if count < minPlayers or count > maxPlayers:
    raise newException(
      StarMapError,
      "Player count must be between " & $minPlayers & " and " & $maxPlayers,
    )

proc validateMapRings*(rings: int, playerCount: int = 0): seq[string] =
  ## Domain validation for map rings configuration
  ## This is the DEFINITIVE validation for map ring parameters
  ##
  ## Returns empty seq if valid, otherwise list of error messages
  ##
  ## Rules:
  ## - Zero rings explicitly not allowed (user requirement)
  ## - Reasonable bounds: 1-20 rings
  ## - No requirement that rings >= players (allow flexible combinations)
  var errors: seq[string] = @[]

  # Zero rings not allowed - must be explicit
  if rings == 0:
    errors.add("Map rings must be >= 1 (zero rings not supported)")
    return errors # Don't continue validation if zero

  # Bounds checking
  if rings < 1:
    errors.add("Map rings must be >= 1 (got " & $rings & ")")
  elif rings > 20:
    errors.add("Map rings must be <= 20 (got " & $rings & ")")

  # Optional: Warn if very small map for player count (but don't error)
  # User requirement: Allow flexible combinations like 2 players on 12-ring map
  if playerCount > 0 and rings < playerCount:
    # This is a warning, not an error - game can still work
    # Just might have tight starting positions
    discard

  return errors

proc systemsPerPlayer*(playerCount: int32): float32 =
  ## Calculate average number of systems per player
  ## Formula: (3n² + 3n + 1) / n where n = playerCount
  ## Accounts for hub system at center
  let n = playerCount.float32
  let totalSystems = 3.0 * n * n + 3.0 * n + 1.0
  return totalSystems / n

proc totalSystems*(playerCount: int32): int32 =
  ## Calculate total number of systems for given player count
  ## Formula: 3n² + 3n + 1 where n = playerCount (numRings)
  let n = playerCount
  return 3 * n * n + 3 * n + 1

proc newStarMap*(playerCount: int32, seed: int64 = 2001): StarMap =
  validatePlayerCount(playerCount)

  StarMap(
    systems: Systems(
      entities: EntityManager[SystemId, System](
        data: @[],
        index: initTable[SystemId, int]()
      )
    ),
    lanes: JumpLanes(
      data: @[],
      neighbors: initTable[SystemId, seq[SystemId]](),
      connectionInfo: initTable[(SystemId, SystemId), LaneType]()
    ),
    distanceMatrix: initTable[(SystemId, SystemId), uint32](),
    playerCount: playerCount,
    numRings: playerCount.uint32,
    hubId: 0.SystemId,
    playerSystemIds: @[],
    seed: seed,
    nextSystemId: 0
  )

proc newSystem(starMap: var StarMap, coords: Hex, ring: uint32, player: Option[PlayerId]): System =
  ## Create a new system with auto-generated ID
  ## Uses StarMap's internal counter for ID generation
  let id = SystemId(starMap.nextSystemId)
  starMap.nextSystemId += 1

  # TODO: Assign planetClass and resourceRating based on game rules
  System(
    id: id,
    coords: coords,
    ring: ring,
    player: player,
    planetClass: PlanetClass.Benign,  # Placeholder
    resourceRating: ResourceRating.Abundant  # Placeholder
  )

proc addSystem(starMap: var StarMap, system: System) =
  starMap.systems.entities.data.add(system)
  starMap.systems.entities.index[system.id] = starMap.systems.entities.data.len - 1

proc addLane(starMap: var StarMap, lane: JumpLane) =
  # Validate lane endpoints exist
  if lane.source notin starMap.systems.entities.index or
     lane.destination notin starMap.systems.entities.index:
    raise newException(StarMapError, "Lane endpoints must exist in starmap")

  # Prevent duplicate lanes
  for existingLane in starMap.lanes.data:
    if (
      existingLane.source == lane.source and
      existingLane.destination == lane.destination
    ) or (
      existingLane.source == lane.destination and
      existingLane.destination == lane.source
    ):
      return  # Lane already exists

  starMap.lanes.data.add(lane)

  # Cache lane type for O(1) lookup (bidirectional)
  starMap.lanes.connectionInfo[(lane.source, lane.destination)] = lane.laneType
  starMap.lanes.connectionInfo[(lane.destination, lane.source)] = lane.laneType

  # Update adjacency (bidirectional)
  if lane.source notin starMap.lanes.neighbors:
    starMap.lanes.neighbors[lane.source] = @[]
  if lane.destination notin starMap.lanes.neighbors:
    starMap.lanes.neighbors[lane.destination] = @[]

  starMap.lanes.neighbors[lane.source].add(lane.destination)
  starMap.lanes.neighbors[lane.destination].add(lane.source)

proc weightedSample[T](
    items: openArray[T], weights: openArray[float32], rng: var Rand
): T =
  ## Select a random item using weighted probabilities
  ## Weights should sum to 1.0, but will be normalized if not
  let totalWeight = weights.sum()
  let r = rng.rand(1.0'f32)
  var cumulative = 0.0'f32

  for i, weight in weights:
    cumulative += weight / totalWeight
    if r <= cumulative:
      return items[i]

  # Fallback (should never reach here with valid weights)
  return items[^1]

proc getAdjacentSystems*(starMap: StarMap, systemId: SystemId): seq[SystemId] =
  starMap.lanes.neighbors.getOrDefault(systemId, @[])

proc countHexNeighbors*(starMap: StarMap, coords: Hex): int32 =
  var count: int32 = 0
  for dir in 0 .. 5:
    let neighborCoord = coords.neighbor(dir)
    if starMap.findSystemByCoords(neighborCoord).isSome:
      count += 1
  return count

proc generateHexGrid(starMap: var StarMap) =
  ## Generate hexagonal grid following game specification
  let center = hex(0, 0)

  # Add hub system at center
  let hub = starMap.newSystem(center, 0, none(PlayerId))
  starMap.hubId = hub.id
  starMap.addSystem(hub)

  # Generate all systems in rings
  let allHexes = center.withinRadius(starMap.numRings.int32)
  for hexCoord in allHexes:
    if hexCoord == center:
      continue

    let ring = distance(hexCoord, center)
    let system = starMap.newSystem(hexCoord, ring, none(PlayerId))
    starMap.addSystem(system)

proc assignPlayerHomeworlds(starMap: var StarMap) =
  ## Assign player homeworlds following game specification
  ## Homeworlds can be placed on any ring (except hub ring 0) using distance maximization
  let maxVertexPlayers: int32 = 4  # Hex grids only have 4 true vertices
  var allSystems: seq[System] = @[]
  for system in starMap.systems.entities.data:
    # Exclude hub (ring 0), allow all other rings
    if system.ring > 0:
      allSystems.add(system)

  if allSystems.len < starMap.playerCount:
    raise newException(StarMapError, "Not enough systems for all players")

  # Sort by angle for even distribution
  allSystems.sort do(a, b: System) -> int:
    let angleA = arctan2(a.coords.r.float32, a.coords.q.float32)
    let angleB = arctan2(b.coords.r.float32, b.coords.q.float32)
    cmp(angleA, angleB)

  # Player placement strategy based on game spec
  var selectedSystems: seq[System] = @[]

  if starMap.playerCount <= maxVertexPlayers:
    # Use vertices (corners) for optimal strategic placement
    let vertices = allSystems.filterIt(starMap.countHexNeighbors(it.coords) == 3)

    # Choose candidate pool: prefer vertices if enough, otherwise use all systems
    let candidateSystems =
      if vertices.len >= starMap.playerCount: vertices else: allSystems

    # Apply distance-maximization to candidate pool for fair spacing
    # Shuffle candidates for randomized but fair initial placement
    var rng = initRand(starMap.seed)
    var shuffledCandidates = candidateSystems
    rng.shuffle(shuffledCandidates)

    selectedSystems = @[shuffledCandidates[0]]  # Start with random first system

    for i in 1 ..< starMap.playerCount:
      var bestSystem = shuffledCandidates[1]
      var maxMinDistance = 0.0'f32

      # Find system that maximizes minimum distance to existing players
      for candidate in shuffledCandidates:
        if candidate in selectedSystems:
          continue

        var minDistance = float32.high
        for existing in selectedSystems:
          let dist = distance(candidate.coords, existing.coords).float32
          minDistance = min(minDistance, dist)

        if minDistance > maxMinDistance:
          maxMinDistance = minDistance
          bestSystem = candidate

      selectedSystems.add(bestSystem)
  else:
    # Even distribution for larger player counts
    let step = allSystems.len.float32 / starMap.playerCount.float32
    for i in 0 ..< starMap.playerCount:
      let index = int32(i.float32 * step) mod allSystems.len.int32
      selectedSystems.add(allSystems[index])

  # Assign players to selected systems
  for i, system in selectedSystems:
    # Update system using EntityManager
    let idx = starMap.systems.entities.index[system.id]
    starMap.systems.entities.data[idx].player = some(i.uint32.PlayerId)
    starMap.playerSystemIds.add(system.id)

proc connectHub(starMap: var StarMap, rng: var Rand) =
  ## Connect hub with mixed lane types to first ring (prevents rush-to-center)
  let hubIdx = starMap.systems.entities.index[starMap.hubId]
  let hubSystem = starMap.systems.entities.data[hubIdx]

  var ring1Neighbors: seq[SystemId] = @[]
  for system in starMap.systems.entities.data:
    if system.ring == 1 and distance(system.coords, hubSystem.coords) == 1:
      ring1Neighbors.add(system.id)

  if ring1Neighbors.len != 6:
    raise newException(StarMapError, "Hub must have exactly 6 first-ring neighbors")

  # Connect with weighted lane types to avoid predictable convergence at center
  let weights = globalStarmapConfig.lane_weights
  for neighborId in ring1Neighbors:
    let laneType = weightedSample(
      [LaneType.Major, LaneType.Minor, LaneType.Restricted],
      [weights.major_weight, weights.minor_weight, weights.restricted_weight],
      rng,
    )
    let lane =
      JumpLane(source: starMap.hubId, destination: neighborId, laneType: laneType)
    starMap.addLane(lane)

proc connectPlayerSystems(starMap: var StarMap, rng: var Rand) =
  ## Connect player systems with configurable number of lanes (default: 3)
  let laneCount = globalStarmapConfig.homeworld_placement.homeworld_lane_count

  # Debug: Check config value
  when not defined(release):
    echo "DEBUG: connectPlayerSystems laneCount=",
      laneCount, " players=", starMap.playerSystemIds.len

  for playerId in starMap.playerSystemIds:
    let sysIdx = starMap.systems.entities.index[playerId]
    let system = starMap.systems.entities.data[sysIdx]

    # Find all potential neighbors
    var neighbors: seq[SystemId] = @[]
    for dir in 0 .. 5:
      let neighborCoord = system.coords.neighbor(dir)
      let neighborIdOpt = starMap.findSystemByCoords(neighborCoord)
      if neighborIdOpt.isSome:
        neighbors.add(neighborIdOpt.get)

    # Remove already connected neighbors
    let existing = starMap.getAdjacentSystems(playerId)
    neighbors = neighbors.filterIt(it notin existing)

    # Connect to exactly N neighbors (configurable)
    if neighbors.len < laneCount:
      raise newException(
        StarMapError,
        "Player system must have at least " & $laneCount & " available neighbors",
      )

    shuffle(rng, neighbors)
    for i in 0 ..< min(laneCount, neighbors.len):
      let laneType = if i < laneCount: LaneType.Major else: LaneType.Minor
      let lane =
        JumpLane(source: playerId, destination: neighbors[i], laneType: laneType)
      starMap.addLane(lane)

proc connectRemainingSystem(starMap: var StarMap, rng: var Rand) =
  ## Connect all remaining systems with random lane types
  for system in starMap.systems.entities.data:
    if system.ring == 0 or system.player.isSome:
      continue  # Skip hub and player systems

    # Find unconnected neighbors
    var neighbors: seq[SystemId] = @[]
    for dir in 0 .. 5:
      let neighborCoord = system.coords.neighbor(dir)
      let neighborIdOpt = starMap.findSystemByCoords(neighborCoord)
      if neighborIdOpt.isSome:
        neighbors.add(neighborIdOpt.get)

    let existing = starMap.getAdjacentSystems(system.id)
    neighbors = neighbors.filterIt(it notin existing)

    # Connect to available neighbors with random lane types
    for neighborId in neighbors:
      # Check if neighbor is a player system that already has 3 connections
      let neighborIdx = starMap.systems.entities.index[neighborId]
      let neighborSystem = starMap.systems.entities.data[neighborIdx]
      if neighborSystem.player.isSome:
        let neighborConnections = starMap.getAdjacentSystems(neighborId)
        if neighborConnections.len >= 3:
          continue  # Skip connecting to player systems that already have 3 connections

      # Use weighted lane type selection for balanced gameplay
      let weights = globalStarmapConfig.lane_weights
      let laneType = weightedSample(
        [LaneType.Major, LaneType.Minor, LaneType.Restricted],
        [weights.major_weight, weights.minor_weight, weights.restricted_weight],
        rng,
      )
      let lane =
        JumpLane(source: system.id, destination: neighborId, laneType: laneType)
      starMap.addLane(lane)

proc generateLanes(starMap: var StarMap) =
  ## Generate all jump lanes following game specification
  # Create RNG with stored seed for deterministic lane generation
  var rng = initRand(starMap.seed)

  try:
    starMap.connectHub(rng)
    starMap.connectPlayerSystems(rng)
    starMap.connectRemainingSystem(rng)
  except StarMapError:
    raise
  except:
    raise newException(
      StarMapError, "Failed to generate lanes: " & getCurrentExceptionMsg()
    )

proc validateConnectivity*(starMap: StarMap): bool =
  ## Validate that all systems are reachable from hub
  if starMap.systems.entities.data.len == 0:
    return false

  var visited = initHashSet[SystemId]()
  var queue = @[starMap.hubId]
  visited.incl(starMap.hubId)

  while queue.len > 0:
    let current = queue.pop()
    for neighbor in starMap.getAdjacentSystems(current):
      if neighbor notin visited:
        visited.incl(neighbor)
        queue.add(neighbor)

  return visited.len == starMap.systems.entities.data.len

proc validateHomeworldLanes*(starMap: StarMap): seq[string] =
  ## Validate that each homeworld has exactly 3 Major lanes
  ## Returns list of validation errors (empty if valid)
  var errors: seq[string] = @[]

  for playerId in starMap.playerSystemIds:
    # Count lanes connected to this homeworld
    var majorLanes: int32 = 0
    var totalLanes: int32 = 0

    for lane in starMap.lanes.data:
      if lane.source == playerId or lane.destination == playerId:
        totalLanes += 1
        if lane.laneType == LaneType.Major:
          majorLanes += 1

    # Per assets.md: "Each homeworld is guaranteed to have exactly 3 Major lanes"
    if totalLanes != 3:
      errors.add(
        "Homeworld " & $playerId & " has " & $totalLanes & " lanes (expected 3)"
      )
    if majorLanes != 3:
      errors.add(
        "Homeworld " & $playerId & " has " & $majorLanes & " Major lanes (expected 3)"
      )

  return errors

# TODO: Fleet traversal functions removed - require Squadrons/Ships types
# Will be re-added once type import issues are resolved

proc weight*(laneType: LaneType): uint32 =
  ## Get movement cost for lane type (for pathfinding)
  case laneType
  of LaneType.Major:
    1 # Standard cost
  of LaneType.Minor:
    2 # Higher cost (less desirable)
  of LaneType.Restricted:
    3 # Highest cost (most restrictive)

proc getLaneType*(
    starMap: StarMap, fromSystem: SystemId, toSystem: SystemId
): Option[LaneType] =
  ## Efficient lane type lookup between two systems
  ## Returns None if no lane exists between the systems
  ## Used for fleet movement calculations in maintenance phase
  ## Now O(1) via connectionInfo table instead of O(n) linear scan
  if (fromSystem, toSystem) in starMap.lanes.connectionInfo:
    return some(starMap.lanes.connectionInfo[(fromSystem, toSystem)])
  return none(LaneType)

# TODO: findPath and related fleet pathfinding functions removed
# Will be re-added once Squadrons/Ships type import issues are resolved

proc buildDistanceMatrix(starMap: var StarMap) =
  ## Pre-compute all pairwise hex distances for O(1) heuristic lookup
  for sys1 in starMap.systems.entities.data:
    for sys2 in starMap.systems.entities.data:
      if sys1.id != sys2.id:
        starMap.distanceMatrix[(sys1.id, sys2.id)] = distance(sys1.coords, sys2.coords)

proc populate*(starMap: var StarMap) =
  ## Main population function - generates complete starmap
  try:
    starMap.generateHexGrid()
    starMap.assignPlayerHomeworlds()
    starMap.generateLanes()
    starMap.buildDistanceMatrix() # Pre-compute hex distances for pathfinding

    # Validate result
    if not starMap.validateConnectivity():
      raise newException(
        StarMapError, "Generated starmap is not fully connected - dead systems detected"
      )

    # Validate player count
    if starMap.playerSystemIds.len != starMap.playerCount:
      raise newException(StarMapError, "Incorrect number of player systems assigned")

    # Validate homeworld lanes (must have exactly 3 Major lanes each)
    let homeworldErrors = starMap.validateHomeworldLanes()
    if homeworldErrors.len > 0:
      raise newException(
        StarMapError, "Homeworld validation failed: " & homeworldErrors.join("; ")
      )
  except StarMapError:
    raise
  except:
    raise newException(
      StarMapError, "Failed to populate starmap: " & getCurrentExceptionMsg()
    )

proc starMap*(playerCount: int): StarMap =
  ## Create a complete, validated starmap
  result = newStarMap(playerCount.int32)
  result.populate()

# Debugging and analysis functions
proc getStarMapStats*(starMap: StarMap): string =
  ## Get comprehensive starmap statistics
  var stats = "StarMap Statistics:\n"
  stats &= "  Players: " & $starMap.playerCount & "\n"
  stats &= "  Rings: " & $starMap.numRings & "\n"
  stats &= "  Total Systems: " & $starMap.systems.entities.data.len & "\n"
  stats &= "  Total Lanes: " & $starMap.lanes.data.len & "\n"

  # Count lane types
  var laneCount = [0, 0, 0] # Major, Minor, Restricted
  for lane in starMap.lanes.data:
    laneCount[ord(lane.laneType)] += 1

  stats &= "  Major Lanes: " & $laneCount[0] & "\n"
  stats &= "  Minor Lanes: " & $laneCount[1] & "\n"
  stats &= "  Restricted Lanes: " & $laneCount[2] & "\n"

  # Connectivity check
  stats &= "  Fully Connected: " & $starMap.validateConnectivity() & "\n"

  return stats

proc verifyGameRules*(starMap: StarMap): bool =
  ## Verify starmap follows all game specification rules per assets.md
  try:
    # 1. Hub should have exactly 6 lanes
    let hubConnections = starMap.getAdjacentSystems(starMap.hubId)
    if hubConnections.len != 6:
      return false

    # 2. All systems must be reachable from hub (no dead systems)
    if not starMap.validateConnectivity():
      return false

    # 3. Each homeworld must have exactly 3 Major lanes
    let homeworldErrors = starMap.validateHomeworldLanes()
    if homeworldErrors.len > 0:
      return false

    return true
  except:
    return false

proc playerSystems*(starMap: StarMap, playerId: PlayerId): seq[System] =
  ## Get all systems owned by a specific player
  var systems: seq[System] = @[]
  for system in starMap.systems.entities.data:
    if system.player.isSome and system.player.get == playerId:
      systems.add(system)
  return systems
