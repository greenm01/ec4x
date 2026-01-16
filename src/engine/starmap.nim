## Robust Starmap Implementation for EC4X
##
## This module provides a simplified, robust starmap implementation that:
## - Follows the game specification exactly
## - Handles all edge cases gracefully
## - Prioritizes correctness over complex optimizations
## - Implements actual game rules for lane traversal
## - Provides fast, reliable starmap generation and pathfinding
import ../common/logger
import types/[starmap, core, game_state]
import state/[id_gen, iterators, engine]
import globals
import utils
import
  std/[tables, sequtils, random, math, algorithm, sets, strutils, heapqueue, options]

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

const HexDirections =
  [hex(1, 0), hex(1, -1), hex(0, -1), hex(-1, 0), hex(-1, 1), hex(0, 1)]

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

proc findSystemByCoords(
    starMap: StarMap, state: GameState, coords: Hex
): Option[SystemId] =
  ## Find a system by its hex coordinates
  ## Returns the SystemId if found, none if not found
  for system in state.allSystems():
    if system.coords.q == coords.q and system.coords.r == coords.r:
      return some(system.id)
  return none(SystemId)

# Total systems = 1 + 3 × n × (n + 1)
# where n = number of rings (houseCount)
# This gives you:

# 2 houses: 1 + 3(2)(3) = 19 systems (9.5 per house)
# 3 houses: 1 + 3(3)(4) = 37 systems (12.3 per house)
# 4 houses: 1 + 3(4)(5) = 61 systems (15.25 per house)
# 6 houses: 1 + 3(6)(7) = 127 systems (21.2 per house)
# 12 houses: 1 + 3(12)(13) = 469 systems (39.1 per house)

# The formula is: 3n² + 3n + 1 where n = houseCount.
#
# Systems per house scales non-linearly - larger games give significantly
# more strategic space per house. This matches 4X escalation patterns where
# bigger maps allow more complex empire building.

proc validateHouseCount(count: int32) =
  # Hardcoded
  let minHouses: int32 = 2
  let maxHouses: int32 = 12
  if count < minHouses or count > maxHouses:
    raise newException(
      StarMapError, "House count must be between " & $minHouses & " and " & $maxHouses
    )

proc validateMapRings*(rings: int, houseCount: int = 0): seq[string] =
  ## Domain validation for map rings configuration
  ## This is the DEFINITIVE validation for map ring parameters
  ##
  ## Returns empty seq if valid, otherwise list of error messages
  ##
  ## Rules:
  ## - Zero rings explicitly not allowed (user requirement)
  ## - Reasonable bounds: 1-20 rings
  ## - No requirement that rings >= houses (allow flexible combinations)
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

  # Optional: Warn if very small map for house count (but don't error)
  # User requirement: Allow flexible combinations like 2 houses on 12-ring map
  if houseCount > 0 and rings < houseCount:
    # This is a warning, not an error - game can still work
    # Just might have tight starting positions
    discard

  return errors

proc systemsPerHouse*(houseCount: int32): float32 =
  ## Calculate average number of systems per house
  ## Formula: (3n² + 3n + 1) / n where n = houseCount
  ## Accounts for hub system at center
  let n = houseCount.float32
  let totalSystems = 3.0 * n * n + 3.0 * n + 1.0
  return totalSystems / n

proc totalSystems*(houseCount: int32): int32 =
  ## Calculate total number of systems for given house count
  ## Formula: 3n² + 3n + 1 where n = houseCount (numRings)
  let n = houseCount
  return 3 * n * n + 3 * n + 1

# Forward declarations for helper functions used by generateStarMap
proc generateHexGrid(
  starMap: var StarMap,
  state: GameState,
  playerCount: int32,
  numRings: uint32,
  seed: int64,
)

proc assignSystemNames*(starMap: var StarMap, state: GameState, seed: int64)
proc assignHouseHomeworlds(
  starMap: var StarMap, state: GameState, playerCount: int32, seed: int64
)

proc generateLanes(starMap: var StarMap, state: GameState, seed: int64)
proc buildDistanceMatrix(starMap: var StarMap, state: GameState)
proc validateConnectivity*(starMap: StarMap, state: GameState): bool
proc validateHomeworldLanes*(starMap: StarMap, state: GameState): seq[string]

proc generateStarMap*(state: GameState, playerCount: int32, numRings: uint32): StarMap =
  ## Generates complete starmap, populating state.systems with System entities
  ## Returns StarMap with lanes, distances, and homeworld references
  ## Uses state.seed for deterministic generation
  ## Uses state.generateSystemId() for ID allocation

  validateHouseCount(playerCount)
  let seed = state.seed

  var starMap = StarMap(
    lanes: JumpLanes(
      data: @[],
      neighbors: initTable[SystemId, seq[SystemId]](),
      connectionInfo: initTable[(SystemId, SystemId), LaneClass](),
    ),
    distanceMatrix: initTable[(SystemId, SystemId), uint32](),
    hubId: 0.SystemId,
    homeWorlds: initTable[SystemId, HouseId](),
    houseSystemIds: @[],
  )

  # Generate systems and populate state.systems
  starMap.generateHexGrid(state, playerCount, numRings, seed)
  starMap.assignSystemNames(state, seed)
  starMap.assignHouseHomeworlds(state, playerCount, seed)
  starMap.generateLanes(state, seed)
  starMap.buildDistanceMatrix(state)

  # Validation
  if not starMap.validateConnectivity(state):
    raise newException(StarMapError, "Map not fully connected")

  if starMap.houseSystemIds.len != playerCount:
    raise newException(StarMapError, "Incorrect number of homeworlds assigned")

  let homeworldErrors = starMap.validateHomeworldLanes(state)
  if homeworldErrors.len > 0:
    raise newException(StarMapError, homeworldErrors.join("; "))

  return starMap

proc pickWeighted*[T: enum](rng: var Rand, weights: openArray[float]): T =
  let total = sum(weights)
  var choice = rng.rand(total)

  for item in T:
    let w = weights[item.ord]
    if choice < w:
      return item
    choice -= w

  # If we reach here, there's a precision issue or weights sum to 0
  assert false, "Weighted choice failed: choice=" & $choice & " total=" & $total
  return T.high

proc newSystem(
    state: GameState, coords: Hex, ring: uint32, house: Option[HouseId], seed: int64
): System =
  let id = state.generateSystemId()

  # MIXING THE SEED:
  # We use the map's master seed + the new ID to create a unique seed for this system.
  # This ensures that if you regenerate the map with the same master seed,
  # System #5 will always be the same type of planet.
  var rng = initRand(seed + id.int64)

  # --- GAME SPEC BALANCED WEIGHTS, per 03-economy.md ---

  # PLANET CLASS WEIGHTS
  # Logic: The 'Raw Index Table' shows a linear progression in efficiency.
  # To force the "Population Transfer" mechanics (moving people from full worlds 
  # to empty ones), bad planets must be common.
  # Extreme/Desolate/Hostile (Low Cap) = ~60% of galaxy
  # Benign/Lush (Mid Cap) = ~35% of galaxy
  # Eden (High Cap) = ~5% "Gem" worlds
  const PlanetWeights = [
    0.25, # Extreme  (Level I)   - Most common, requires terraforming
    0.20, # Desolate (Level II)
    0.15, # Hostile  (Level III)
    0.15, # Harsh    (Level IV)
    0.15, # Benign   (Level V)   - The "Standard" habitable world
    0.08, # Lush     (Level VI)  - High value target
    0.02, # Eden     (Level VII) - Strategic objective (Very Rare)
  ]

  # RESOURCE WEIGHTS
  # Logic: Based on 'RAW INDEX Table'.
  # 'Abundant' is the baseline. 
  # 'Very Rich' (140% bonus) must be rare to prevent runaway GCO inflation.
  const ResourceWeights = [
    0.20, # VeryPoor - 60% efficiency floor
    0.25, # Poor
    0.35, # Abundant - Standard (100% eff on Eden)
    0.15, # Rich
    0.05, # VeryRich - 140% efficiency ceiling
  ]

  System(
    id: id,
    name: "",
    coords: coords,
    ring: ring,
    planetClass: pickWeighted[PlanetClass](rng, PlanetWeights),
    resourceRating: pickWeighted[ResourceRating](rng, ResourceWeights),
  )

proc addLane(starMap: var StarMap, state: GameState, lane: JumpLane) =
  # Validate lane endpoints exist
  if state.system(lane.source).isNone or state.system(lane.destination).isNone:
    raise newException(StarMapError, "Lane endpoints must exist in starmap")

  # Prevent duplicate lanes
  for existingLane in starMap.lanes.data:
    if (
      existingLane.source == lane.source and existingLane.destination == lane.destination
    ) or (
      existingLane.source == lane.destination and existingLane.destination == lane.source
    ):
      return # Lane already exists

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

proc adjacentSystems*(starMap: StarMap, systemId: SystemId): seq[SystemId] =
  starMap.lanes.neighbors.getOrDefault(systemId, @[])

proc countHexNeighbors*(starMap: StarMap, state: GameState, coords: Hex): int32 =
  var count: int32 = 0
  for dir in 0 .. 5:
    let neighborCoord = coords.neighbor(dir)
    if starMap.findSystemByCoords(state, neighborCoord).isSome:
      count += 1
  return count

proc generateHexGrid(
    starMap: var StarMap,
    state: GameState,
    playerCount: int32,
    numRings: uint32,
    seed: int64,
) =
  ## Generate hexagonal grid following game specification
  let center = hex(0, 0)

  # Add hub system at center
  let hub = state.newSystem(center, 0, none(HouseId), seed)
  starMap.hubId = hub.id
  state.addSystem(hub.id, hub)

  # Generate all systems in rings
  let allHexes = center.withinRadius(numRings.int32)
  for hexCoord in allHexes:
    if hexCoord == center:
      continue

    let ring = distance(hexCoord, center)
    let system = state.newSystem(hexCoord, ring, none(HouseId), seed)
    state.addSystem(system.id, system)

proc assignHouseHomeworlds(
    starMap: var StarMap, state: GameState, playerCount: int32, seed: int64
) =
  ## Assign house homeworlds following game specification
  ## Homeworlds can be placed on any ring (except hub ring 0) using distance maximization
  let maxVertexHouses: int32 = 4 # Hex grids only have 4 true vertices
  var allSystems: seq[System] = @[]
  for system in state.allSystems():
    # Exclude hub (ring 0), allow all other rings
    if system.ring > 0:
      allSystems.add(system)

  if allSystems.len < playerCount:
    raise newException(StarMapError, "Not enough systems for all houses")

  # Sort by angle for even distribution
  allSystems.sort do(a, b: System) -> int:
    let angleA = arctan2(a.coords.r.float32, a.coords.q.float32)
    let angleB = arctan2(b.coords.r.float32, b.coords.q.float32)
    cmp(angleA, angleB)

  # House placement strategy based on game spec
  var selectedSystems: seq[System] = @[]

  if playerCount <= maxVertexHouses:
    # Use vertices (corners) for optimal strategic placement
    let vertices = allSystems.filterIt(starMap.countHexNeighbors(state, it.coords) == 3)

    # Choose candidate pool: prefer vertices if enough, otherwise use all systems
    let candidateSystems = if vertices.len >= playerCount: vertices else: allSystems

    # Apply distance-maximization to candidate pool for fair spacing
    # Shuffle candidates for randomized but fair initial placement
    var rng = initRand(seed)
    var shuffledCandidates = candidateSystems
    rng.shuffle(shuffledCandidates)

    selectedSystems = @[shuffledCandidates[0]] # Start with random first system

    for i in 1 ..< playerCount:
      var bestSystem = shuffledCandidates[1]
      var maxMinDistance = 0.0'f32

      # Find system that maximizes minimum distance to existing houses
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
    # Even distribution for larger house counts
    let step = allSystems.len.float32 / playerCount.float32
    for i in 0 ..< playerCount:
      let index = int32(i.float32 * step) mod allSystems.len.int32
      selectedSystems.add(allSystems[index])

  # Assign houses to selected systems and apply homeworld characteristics
  for i, system in selectedSystems:
    # Update system using public API
    var updatedSystem = state.system(system.id).get()

    # Override with configured homeworld characteristics
    updatedSystem.planetClass = parsePlanetClass(gameSetup.homeworld.planetClass)
    updatedSystem.resourceRating = parseResourceRating(gameSetup.homeworld.rawQuality)

    state.updateSystem(updatedSystem.id, updatedSystem)

    starMap.houseSystemIds.add(system.id)
    starMap.homeWorlds[system.id] = i.uint32.HouseId

proc connectHub(starMap: var StarMap, state: GameState, rng: var Rand) =
  ## Connect hub with mixed lane types to first ring (prevents rush-to-center)
  let hubSystem = state.system(starMap.hubId).get()

  var ring1Neighbors: seq[SystemId] = @[]
  for system in state.allSystems():
    if system.ring == 1 and distance(system.coords, hubSystem.coords) == 1:
      ring1Neighbors.add(system.id)

  if ring1Neighbors.len != 6:
    raise newException(StarMapError, "Hub must have exactly 6 first-ring neighbors")

  # Connect with weighted lane types to avoid predictable convergence at center
  let weights = gameConfig.starmap.laneWeights
  for neighborId in ring1Neighbors:
    let laneType = weightedSample(
      [LaneClass.Major, LaneClass.Minor, LaneClass.Restricted],
      [weights.majorWeight, weights.minorWeight, weights.restrictedWeight],
      rng,
    )
    let lane =
      JumpLane(source: starMap.hubId, destination: neighborId, laneType: laneType)
    starMap.addLane(state, lane)

proc connectHouseSystems(starMap: var StarMap, state: GameState, rng: var Rand) =
  ## Connect house systems with configurable number of lanes (default: 3)
  let laneCount = gameConfig.starmap.homeworldPlacement.homeworldLaneCount

  # Debug: Check config value
  when not defined(release):
    logDebug(
      "Starmap", "connectHouseSystems laneCount=", laneCount, " houses=",
      starMap.houseSystemIds.len,
    )

  for houseId in starMap.houseSystemIds:
    let system = state.system(houseId).get()

    # Find all potential neighbors
    var neighbors: seq[SystemId] = @[]
    for dir in 0 .. 5:
      let neighborCoord = system.coords.neighbor(dir)
      let neighborIdOpt = starMap.findSystemByCoords(state, neighborCoord)
      if neighborIdOpt.isSome:
        neighbors.add(neighborIdOpt.get)

    # Remove already connected neighbors
    let existing = starMap.adjacentSystems(houseId)
    neighbors = neighbors.filterIt(it notin existing)

    # Connect to exactly N neighbors (configurable)
    if neighbors.len < laneCount:
      raise newException(
        StarMapError,
        "House system must have at least " & $laneCount & " available neighbors",
      )

    shuffle(rng, neighbors)
    for i in 0 ..< min(laneCount, neighbors.len):
      let laneType = if i < laneCount: LaneClass.Major else: LaneClass.Minor
      let lane =
        JumpLane(source: houseId, destination: neighbors[i], laneType: laneType)
      starMap.addLane(state, lane)

proc connectRemainingSystem(starMap: var StarMap, state: GameState, rng: var Rand) =
  ## Connect all remaining systems with random lane types
  for system in state.allSystems():
    if system.ring == 0 or system.id in starMap.homeWorlds:
      continue # Skip hub and house homeworld systems

    # Find unconnected neighbors
    var neighbors: seq[SystemId] = @[]
    for dir in 0 .. 5:
      let neighborCoord = system.coords.neighbor(dir)
      let neighborIdOpt = starMap.findSystemByCoords(state, neighborCoord)
      if neighborIdOpt.isSome:
        neighbors.add(neighborIdOpt.get)

    let existing = starMap.adjacentSystems(system.id)
    neighbors = neighbors.filterIt(it notin existing)

    # Connect to available neighbors with random lane types
    for neighborId in neighbors:
      # Check if neighbor is a house system that already has 3 connections
      if neighborId in starMap.houseSystemIds:
        let neighborConnections = starMap.adjacentSystems(neighborId)
        if neighborConnections.len >= 3:
          continue # Skip connecting to house systems that already have 3 connections

      # Use weighted lane type selection for balanced gameplay
      let weights = gameConfig.starmap.laneWeights
      let laneType = weightedSample(
        [LaneClass.Major, LaneClass.Minor, LaneClass.Restricted],
        [weights.majorWeight, weights.minorWeight, weights.restrictedWeight],
        rng,
      )
      let lane =
        JumpLane(source: system.id, destination: neighborId, laneType: laneType)
      starMap.addLane(state, lane)

proc generateLanes(starMap: var StarMap, state: GameState, seed: int64) =
  ## Generate all jump lanes following game specification
  # Create RNG with seed for deterministic lane generation
  var rng = initRand(seed)

  try:
    starMap.connectHub(state, rng)
    starMap.connectHouseSystems(state, rng)
    starMap.connectRemainingSystem(state, rng)
  except StarMapError:
    raise
  except:
    raise newException(
      StarMapError, "Failed to generate lanes: " & getCurrentExceptionMsg()
    )

proc validateConnectivity*(starMap: StarMap, state: GameState): bool =
  ## Validate that all systems are reachable from hub
  if state.systemsCount() == 0:
    return false

  var visited = initHashSet[SystemId]()
  var queue = @[starMap.hubId]
  visited.incl(starMap.hubId)

  while queue.len > 0:
    let current = queue.pop()
    for neighbor in starMap.adjacentSystems(current):
      if neighbor notin visited:
        visited.incl(neighbor)
        queue.add(neighbor)

  return visited.len == state.systemsCount()

proc validateHomeworldLanes*(starMap: StarMap, state: GameState): seq[string] =
  ## Validate that each homeworld has exactly 3 Major lanes
  ## Returns list of validation errors (empty if valid)
  var errors: seq[string] = @[]

  for houseId in starMap.houseSystemIds:
    # Count lanes connected to this homeworld
    var majorLanes: int32 = 0
    var totalLanes: int32 = 0

    for lane in starMap.lanes.data:
      if lane.source == houseId or lane.destination == houseId:
        totalLanes += 1
        if lane.laneType == LaneClass.Major:
          majorLanes += 1

    # Per assets.md: "Each homeworld is guaranteed to have exactly 3 Major lanes"
    if totalLanes != 3:
      errors.add(
        "Homeworld " & $houseId & " has " & $totalLanes & " lanes (expected 3)"
      )
    if majorLanes != 3:
      errors.add(
        "Homeworld " & $houseId & " has " & $majorLanes & " Major lanes (expected 3)"
      )

  return errors

proc weight*(laneType: LaneClass): uint32 =
  ## Get movement cost for lane type (for pathfinding)
  case laneType
  of LaneClass.Major:
    1 # Standard cost
  of LaneClass.Minor:
    2 # Higher cost (less desirable)
  of LaneClass.Restricted:
    3 # Highest cost (most restrictive)

proc laneType*(
    starMap: StarMap, fromSystem: SystemId, toSystem: SystemId
): Option[LaneClass] =
  ## Efficient lane type lookup between two systems
  ## Returns None if no lane exists between the systems
  ## Used for fleet movement calculations in maintenance phase
  ## Now O(1) via connectionInfo table instead of O(n) linear scan
  if (fromSystem, toSystem) in starMap.lanes.connectionInfo:
    return some(starMap.lanes.connectionInfo[(fromSystem, toSystem)])
  return none(LaneClass)

proc buildDistanceMatrix(starMap: var StarMap, state: GameState) =
  ## Pre-compute all pairwise hex distances for O(1) heuristic lookup
  for sys1 in state.allSystems():
    for sys2 in state.allSystems():
      if sys1.id != sys2.id:
        starMap.distanceMatrix[(sys1.id, sys2.id)] = distance(sys1.coords, sys2.coords)

proc assignSystemNames*(starMap: var StarMap, state: GameState, seed: int64) =
  ## Assign names to systems from the configured name pool
  ## Names are drawn sequentially from the pool
  ## If pool is exhausted, uses fallback pattern: "System-{id}"
  let namePool = gameConfig.starmap.planetNames.names

  if namePool.len == 0:
    # Fallback to numeric names
    for (systemId, system) in state.allSystemsWithId():
      var updated = system
      updated.name = "System-" & $systemId
      state.updateSystem(systemId, updated)
    return

  # Assign names from pool
  var nameIdx = 0
  for (systemId, system) in state.allSystemsWithId():
    var updated = system
    if nameIdx < namePool.len:
      updated.name = namePool[nameIdx]
      nameIdx += 1
    else:
      # Fallback if pool exhausted
      updated.name = "System-" & $systemId
    state.updateSystem(systemId, updated)

# Debugging and analysis functions
proc starMapStats*(starMap: StarMap, state: GameState): string =
  ## Get comprehensive starmap statistics
  var stats = "StarMap Statistics:\n"
  stats &= "  Houses: " & $starMap.houseSystemIds.len & "\n"
  stats &= "  Total Systems: " & $state.systemsCount() & "\n"
  stats &= "  Total Lanes: " & $starMap.lanes.data.len & "\n"

  # Count lane types
  var laneCount = [0, 0, 0] # Major, Minor, Restricted
  for lane in starMap.lanes.data:
    laneCount[ord(lane.laneType)] += 1

  stats &= "  Major Lanes: " & $laneCount[0] & "\n"
  stats &= "  Minor Lanes: " & $laneCount[1] & "\n"
  stats &= "  Restricted Lanes: " & $laneCount[2] & "\n"

  # Connectivity check
  stats &= "  Fully Connected: " & $starMap.validateConnectivity(state) & "\n"

  return stats

proc verifyGameRules*(starMap: StarMap, state: GameState): bool =
  ## Verify starmap follows all game specification rules per assets.md
  try:
    # 1. Hub should have exactly 6 lanes
    let hubConnections = starMap.adjacentSystems(starMap.hubId)
    if hubConnections.len != 6:
      return false

    # 2. All systems must be reachable from hub (no dead systems)
    if not starMap.validateConnectivity(state):
      return false

    # 3. Each homeworld must have exactly 3 Major lanes
    let homeworldErrors = starMap.validateHomeworldLanes(state)
    if homeworldErrors.len > 0:
      return false

    return true
  except:
    return false

proc houseSystems*(starMap: StarMap, state: GameState, houseId: HouseId): seq[System] =
  ## Get all systems owned by a specific house (via colony ownership)
  var systems: seq[System] = @[]
  for system in state.allSystems():
    # System is owned if it has a colony owned by this house
    let colonyOpt = state.colonyBySystem(system.id)
    if colonyOpt.isSome and colonyOpt.get().owner == houseId:
      systems.add(system)
  return systems
