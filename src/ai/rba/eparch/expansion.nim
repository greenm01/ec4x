## Expansion Operations Module
##
## Single source of truth for ETAC construction and colonization management.
## Part of Eparch (economic advisor) - handles all expansion operations.
##
## **Architecture:**
## - Consolidates ETAC construction requirements (formerly in Domestikos)
## - Consolidates ETAC colonization orders (formerly in etac_manager)
## - Returns ExpansionPlan with both requirements AND orders
## - Executes in Phase 1 (Eparch requirements generation)
##
## **ETAC One-Time Consumable Model:**
## - Each ETAC carries 3 PTU (free colonists via cryostasis technology)
## - Deposits ALL 3 PTU on ONE colony (3 PU "foundation colony")
## - Ship is cannibalized after colonization (becomes colony infrastructure)
## - One ETAC needed per system on map (~57 for 61-system map)
## - No reload cycles needed (one-time consumable)
##
## **Design Principles:**
## - DoD (Data-Oriented Design): Operates on FilteredGameState, returns data
## - DRY (Don't Repeat Yourself): Reuses engine's Act-aware scoring logic
## - Single Responsibility: Eparch owns expansion (economic), not Domestikos (military)

import std/[tables, options, sets, strformat, sequtils, algorithm, math]
import ../../../common/types/core
import ../../../engine/[gamestate, fleet, orders, fog_of_war, starmap, logger, order_types]
import ../../../engine/standing_orders  # For scoreColonizationCandidate
import ../../../engine/economy/types as econ_types
import ../../../engine/economy/config_accessors  # For getShipConstructionCost
import ../../../ai/common/types as ai_common_types
import ../controller_types
import ../config

type
  ETACTarget = object
    ## Colonization target candidate with scoring
    systemId: SystemId
    planetClass: PlanetClass
    distance: int
    score: float

  ETACAssignment = object
    ## ETAC-to-target assignment with priority and scoring
    fleetId: FleetId
    etacId: string
    targetSystem: SystemId
    distance: int
    score: float
    priority: int

  ExpansionPlan* = object
    ## Complete expansion plan: construction + colonization
    buildRequirements*: seq[EconomicRequirement]  # ETAC construction
    colonizationOrders*: seq[FleetOrder]          # Colonize orders
    etacsReady*: int                              # ETACs ready to colonize
    etacsInConstruction*: int                     # ETACs being built
    uncolonizedSystems*: int                      # Remaining targets

# ============================================================================
# Part 1: ETAC Construction (from Domestikos assessExpansionNeeds)
# ============================================================================

# =============================================================================
# Frontier ETAC Production (Phase 6)
# =============================================================================

proc getHomeworld(filtered: FilteredGameState): SystemId =
  ## Get this house's homeworld from filtered state
  ## Homeworld is the colony with highest population + infrastructure
  var best = filtered.ownColonies[0].systemId
  var bestScore = 0

  for colony in filtered.ownColonies:
    let score = colony.population + colony.infrastructure * 10
    if score > bestScore:
      bestScore = score
      best = colony.systemId

  return best

proc findFrontierColonies(
  filtered: FilteredGameState,
  uncolonizedSystems: HashSet[SystemId]
): seq[tuple[colony: Colony, frontierScore: int]] =
  ## Find colonies adjacent to uncolonized systems (expansion frontier)
  ## Returns colonies sorted by frontier score (# of uncolonized neighbors)
  result = @[]

  for colony in filtered.ownColonies:
    # Must have Shipyard or Spaceport to build ETACs
    if colony.shipyards.len == 0 and colony.spaceports.len == 0:
      continue

    # Count uncolonized neighbors
    let adjacentSystemIds = filtered.starMap.getAdjacentSystems(colony.systemId)
    var uncolonizedNeighbors = 0
    for neighborId in adjacentSystemIds:
      if neighborId in uncolonizedSystems:
        inc uncolonizedNeighbors

    if uncolonizedNeighbors > 0:
      result.add((colony, uncolonizedNeighbors))

  # Sort by frontier score (most uncolonized neighbors first)
  result.sort(proc(a, b: tuple[colony: Colony, frontierScore: int]): int =
    cmp(b.frontierScore, a.frontierScore))

proc selectETACConstructionColonies(
  filtered: FilteredGameState,
  uncolonizedSystems: HashSet[SystemId],
  needed: int
): seq[Colony] =
  ## Select up to 'needed' colonies for ETAC construction
  ## Priority: Frontier colonies (adjacent to uncolonized), then homeworld
  result = @[]

  # Get frontier colonies
  let frontierColonies = findFrontierColonies(filtered, uncolonizedSystems)

  # Add frontier colonies (max 3)
  for (colony, score) in frontierColonies:
    if result.len >= min(needed, 3):  # Cap at 3 frontier colonies
      break
    result.add(colony)

  # Always include homeworld if it has shipyard/spaceport and isn't already included
  let homeworld = getHomeworld(filtered)
  var homeworldColony: Option[Colony] = none(Colony)

  for colony in filtered.ownColonies:
    if colony.systemId == homeworld:
      homeworldColony = some(colony)
      break

  if homeworldColony.isSome:
    let hw = homeworldColony.get()
    if (hw.shipyards.len > 0 or hw.spaceports.len > 0):
      # Check if not already in result
      var alreadyIncluded = false
      for col in result:
        if col.systemId == hw.systemId:
          alreadyIncluded = true
          break
      if not alreadyIncluded:
        result.add(hw)

  logInfo(LogCategory.lcAI,
          &"Eparch: Selected {result.len} colonies for ETAC construction " &
          &"({frontierColonies.len} frontier colonies available)")

proc assessETACConstructionNeeds(
  filtered: FilteredGameState,
  controller: AIController,
  currentAct: ai_common_types.GameAct
): tuple[requirements: seq[EconomicRequirement], stats: tuple[
  etacCount, readyETACs, emptyETACs, uncolonizedActual: int
]] =
  ## Intelligence-driven ETAC construction requirements
  ## Active in Act 1 ONLY to prevent late-game ETAC spam.
  ##
  ## Returns: (requirements, stats) tuple with construction requirements
  ## and ETAC status for use in colonization planning
  result.requirements = @[]

  # Act 1 (Land Grab): Expansion is primary objective
  # Acts 2-4: Stop proactive ETAC production, focus on military/economy
  if currentAct != ai_common_types.GameAct.Act1_LandGrab:
    return

  # Calculate ACTUAL uncolonized systems using public leaderboard data
  # Leaderboard shows each house's total colonies (not affected by fog of war)
  # This prevents overbuilding ETACs for systems already colonized by other houses
  let totalSystems = filtered.starMap.systems.len
  var totalColonized = 0
  for houseId, colonyCount in filtered.houseColonies:
    totalColonized += colonyCount

  let uncolonizedActual = max(0, totalSystems - totalColonized)

  logDebug(LogCategory.lcAI,
           &"Map status: {totalColonized}/{totalSystems} systems colonized, " &
           &"{uncolonizedActual} remain (leaderboard)")

  if uncolonizedActual == 0:
    return  # Map fully colonized

  # Count ETACs by status: total, under construction, ready to colonize
  var etacCount = 0
  var readyETACs = 0  # ETACs with loaded PTU ready to colonize
  var emptyETACs = 0  # ETACs returning home for PTU refill

  for fleet in filtered.ownFleets:
    for squadron in fleet.squadrons:
      if squadron.squadronType == SquadronType.Expansion:
        if squadron.flagship.shipClass == ShipClass.ETAC:
          etacCount += 1
          # Check if ETAC has colonists loaded (ready to colonize)
          if squadron.flagship.cargo.isSome:
            let cargo = squadron.flagship.cargo.get()
            if cargo.cargoType == CargoType.Colonists and cargo.quantity > 0:
              readyETACs += 1
            else:
              emptyETACs += 1
          else:
            emptyETACs += 1

  # Also count ETACs under construction (prevents duplicate orders)
  for colony in filtered.ownColonies:
    if colony.underConstruction.isSome:
      let project = colony.underConstruction.get()
      if project.projectType == econ_types.ConstructionType.Ship and
         project.itemId == "ETAC":
        etacCount += 1
    # Also check construction queue
    for queuedProject in colony.constructionQueue:
      if queuedProject.projectType == econ_types.ConstructionType.Ship and
         queuedProject.itemId == "ETAC":
        etacCount += 1

  # ONE-TIME CONSUMABLE MODEL: 1 ETAC = 1 system (3 PU foundation colony)
  # ETACs deposit all 3 PTU on single colony, then are cannibalized
  # No reload cycles - build exactly as many ETACs as uncolonized systems
  #
  # Math for 61-system map, 4 players:
  # - Wave 1 (turns 1-3): 12 starting ETACs → 12 colonies
  # - Wave 2 (turns 4-7): ~15 ETACs built → 15 colonies
  # - Wave 3 (turns 7-10): ~20 ETACs built → 20 colonies
  # - Wave 4 (turns 10-12): ~10 ETACs built → 10 colonies
  # - Total: 57 ETACs (one per system) → 100% colonization by turn 10-12

  let cfg = controller.rbaConfig.domestikos

  # Act 1 AGGRESSIVE EXPANSION: Build as many ETACs as needed for 100% colonization by turn 15
  # No decay, no artificial caps - just build ETACs for every uncolonized system
  # Acts 2+: Apply exponential decay to prevent late-game ETAC spam

  let decayFactor = if currentAct == ai_common_types.GameAct.Act1_LandGrab:
    1.0  # Act 1: NO DECAY - full aggressive expansion
  else:
    # Acts 2+: Exponential decay based on colonization progress
    let uncolonizedRatio = uncolonizedActual.float / totalSystems.float
    if uncolonizedRatio > 0.3:
      1.0  # No decay while >30% uncolonized
    else:
      let scaledRatio = uncolonizedRatio / 0.3
      scaledRatio * scaledRatio  # Quadratic decay

  # Base capacity per player: aggressive in Act 1, conservative later
  let baseCapPerPlayer = if currentAct == ai_common_types.GameAct.Act1_LandGrab:
    # Act 1: Cap = uncolonized systems (build enough for 100% colonization)
    max(10, uncolonizedActual)  # At least 10, scale up with remaining systems
  else:
    # Acts 2+: Conservative cap (scales with map size)
    let ringsCount = filtered.starMap.numRings.int
    max(4, ringsCount + 1)

  # Apply decay factor to cap
  let dynamicCap = max(1, (baseCapPerPlayer.float * decayFactor).int)

  # Calculate deficit and target
  # Use readyETACs (loaded with cargo) since ETACs commission with full cargo
  # If ETACs are sitting idle without orders, the issue is target visibility, not cargo
  let deficit = uncolonizedActual - readyETACs
  let targetETACs = if deficit > 0:
    # Act 1: Build many ETACs simultaneously for fast expansion
    # Acts 2+: Conservative +2 at a time
    if currentAct == ai_common_types.GameAct.Act1_LandGrab:
      min(dynamicCap, etacCount + deficit)  # Build as many as needed
    else:
      min(dynamicCap, etacCount + 2)  # Conservative expansion
  else:
    etacCount  # No more needed

  logDebug(LogCategory.lcAI,
           &"ETAC assessment (one-time consumable): have {etacCount} " &
           &"(ready: {readyETACs}, empty: {emptyETACs}), " &
           &"uncolonized {uncolonizedActual}/{totalSystems}, " &
           &"deficit {deficit}, target {targetETACs}, " &
           &"turn {filtered.turn}")

  # Store stats for colonization planning
  result.stats = (etacCount, readyETACs, emptyETACs, uncolonizedActual)

  if etacCount < targetETACs:
    let etacCost = getShipConstructionCost(ShipClass.ETAC)
    let needed = min(targetETACs - etacCount, cfg.max_etacs_queued)

    if needed > 0:
      let priority = case currentAct
        of ai_common_types.GameAct.Act1_LandGrab:
          RequirementPriority.Critical  # CRITICAL: Exponential expansion is #1 priority in Land Grab
        of ai_common_types.GameAct.Act2_RisingTensions:
          RequirementPriority.Medium  # Balanced expansion
        of ai_common_types.GameAct.Act3_TotalWar:
          RequirementPriority.Low  # Military priority, but finish expansion
        else:
          RequirementPriority.Low

      # Phase 6: Multi-colony frontier ETAC production
      # Build set of uncolonized systems for frontier detection
      var uncolonizedSystemsSet = initHashSet[SystemId]()
      for systemId in filtered.starMap.systems.keys:
        var isColonized = false
        # Check own colonies
        for colony in filtered.ownColonies:
          if colony.systemId == systemId:
            isColonized = true
            break
        # Check visible enemy colonies
        if not isColonized:
          for visColony in filtered.visibleColonies:
            if visColony.systemId == systemId:
              isColonized = true
              break
        if not isColonized:
          uncolonizedSystemsSet.incl(systemId)

      # Select colonies for ETAC construction (frontier + homeworld)
      let buildColonies = selectETACConstructionColonies(
        filtered,
        uncolonizedSystemsSet,
        needed
      )

      if buildColonies.len == 0:
        logWarn(LogCategory.lcAI,
                &"Eparch: Cannot create ETAC requirement - no colonies with " &
                &"Spaceport/Shipyard available")
      else:
        # Create one requirement per colony (distributed production)
        for colony in buildColonies:
          result.requirements.add(EconomicRequirement(
            requirementType: EconomicRequirementType.Facility,
            priority: priority,
            targetColony: colony.systemId,
            facilityType: some("ETAC"),
            terraformTarget: none(PlanetClass),
            estimatedCost: etacCost,  # Cost per ETAC
            reason: &"Frontier expansion (have {etacCount}/{targetETACs} ETACs, " &
                    &"{uncolonizedActual} systems uncolonized, " &
                    &"colony at {colony.systemId})"
          ))

        logInfo(LogCategory.lcAI,
               &"Eparch: ETAC construction requirements - {buildColonies.len} colonies " &
               &"building ETACs (have {etacCount}, target {targetETACs}, " &
               &"decay factor {decayFactor:.2f})")

# ============================================================================
# Part 2: ETAC Colonization (from etac_manager.nim)
# ============================================================================

proc getAvailableETACs(
  filtered: FilteredGameState,
  houseId: HouseId
): seq[tuple[fleetId: FleetId, etacId: string, location: SystemId]] =
  ## Find all ETACs with cargo (ready to colonize)
  ##
  ## Returns: Sequence of (fleetId, etacId, location) tuples for ETACs
  ## with colonists loaded and ready to establish colonies
  result = @[]

  logInfo(LogCategory.lcAI,
          &"{houseId} getAvailableETACs: Scanning {filtered.ownFleets.len} fleets")

  for fleet in filtered.ownFleets:
    if fleet.owner != houseId:
      continue

    for squadron in fleet.squadrons:
      if squadron.squadronType != SquadronType.Expansion:
        continue

      if squadron.flagship.shipClass != ShipClass.ETAC:
        continue

      let ship = squadron.flagship
      if ship.cargo.isSome:
        let cargo = ship.cargo.get()
        logInfo(LogCategory.lcAI,
                &"  Fleet {fleet.id} at {fleet.location}: " &
                &"{ship.shipClass} cargo={cargo.cargoType}:{cargo.quantity}")

        if cargo.quantity == 0:
          logWarn(LogCategory.lcAI,
                  &"⚠️  🐛 FOUND EMPTY ETAC! {squadron.id} in fleet {fleet.id} " &
                  &"at {fleet.location} - ENGINE BUG!")

        if cargo.cargoType == CargoType.Colonists and cargo.quantity > 0:
          result.add((fleet.id, squadron.id, fleet.location))
          logInfo(LogCategory.lcAI,
                  &"  ✅ Found loaded ETAC {squadron.id} ({cargo.quantity} PTU)")
      else:
        logInfo(LogCategory.lcAI,
                &"  Fleet {fleet.id} at {fleet.location}: " &
                &"{ship.shipClass} cargo=None (empty)")

  logInfo(LogCategory.lcAI,
          &"{houseId} has {result.len} ETACs ready to colonize (Eparch)")

# =============================================================================
# Wave-Based Colonization Strategy (Phase 5)
# =============================================================================

proc calculateColonizationWaves(
  filtered: FilteredGameState,
  homeworld: SystemId,
  uncolonizedSystems: seq[SystemId]
): Table[SystemId, int] =
  ## Calculate which "wave" each uncolonized system belongs to
  ## Wave 0 = homeworld (already colonized)
  ## Wave 1 = adjacent to homeworld
  ## Wave 2 = adjacent to Wave 1 colonies
  ## etc.
  ##
  ## This promotes frontier expansion (colonize adjacent to existing colonies first)
  result = initTable[SystemId, int]()

  # Track colonized systems by wave
  var colonizedByWave: Table[int, HashSet[SystemId]] = initTable[int, HashSet[SystemId]]()
  colonizedByWave[0] = initHashSet[SystemId]()
  colonizedByWave[0].incl(homeworld)

  # Add all existing colonies to wave 0 (treat as "already conquered frontier")
  for colony in filtered.ownColonies:
    if colony.systemId != homeworld:
      colonizedByWave[0].incl(colony.systemId)

  var currentWave = 1
  var unassigned = uncolonizedSystems.toHashSet()

  while unassigned.len > 0 and currentWave < 20:  # Max 20 waves
    colonizedByWave[currentWave] = initHashSet[SystemId]()

    # Find systems adjacent to previous wave
    for systemId in unassigned:
      if systemId notin filtered.starMap.systems:
        continue

      # Check if adjacent to any Wave N-1 colony
      let adjacentSystemIds = filtered.starMap.getAdjacentSystems(systemId)
      for neighborId in adjacentSystemIds:
        if neighborId in colonizedByWave[currentWave - 1]:
          result[systemId] = currentWave
          colonizedByWave[currentWave].incl(systemId)
          break

    # Remove assigned systems
    for systemId in colonizedByWave[currentWave]:
      unassigned.excl(systemId)

    # If no systems assigned this wave, remaining are unreachable
    if colonizedByWave[currentWave].len == 0:
      break

    inc currentWave

  # Unreachable systems get wave 999
  for systemId in unassigned:
    result[systemId] = 999

proc findUncolonizedSystems(
  filtered: FilteredGameState,
  originSystem: SystemId
): seq[ETACTarget] =
  ## Find all uncolonized systems on the map and score them
  ##
  ## Uses Act-aware scoring from engine (frontier expansion in Act 1-2,
  ## quality consolidation in Act 3-4)
  ##
  ## ETACs have FTL engines and can reach any system - no range limit
  ##
  ## Returns: Scored colonization targets sorted by score (highest first)
  result = @[]

  # Scan all visible systems (includes universal map awareness)
  # ETACs act as exploration vessels - they can target any visible system
  # even if we haven't scouted them yet (fog-of-war expansion)
  var candidateSystems = initHashSet[SystemId]()

  # Add all visible systems (fog_of_war.nim ensures ALL systems are visible)
  for systemId in filtered.visibleSystems.keys:
    candidateSystems.incl(systemId)

  for systemId in candidateSystems:
    # Skip if CONFIRMED colonized (check visible intel)
    # IMPORTANT: Systems with UNKNOWN status are valid targets!
    # ETACs act as exploration vessels - they probe unknown systems
    # If empty → colonize, if occupied → order fails but intel gained
    var isKnownColonized = false

    # Check own colonies (always known)
    for colony in filtered.ownColonies:
      if colony.systemId == systemId:
        isKnownColonized = true
        break

    # Check visible enemy colonies (only if we've scouted them)
    if not isKnownColonized:
      for visColony in filtered.visibleColonies:
        if visColony.systemId == systemId:
          isKnownColonized = true
          break

    if isKnownColonized:
      continue

    # Get planet details from star map
    if systemId notin filtered.starMap.systems:
      continue
    let system = filtered.starMap.systems[systemId]

    # Check pathfinding (can we reach this system?)
    # Create minimal fleet for pathfinding (just need to check reachability)
    let dummyFleet = Fleet(
      id: FleetId("dummy"),
      owner: filtered.viewingHouse,
      location: originSystem,
      squadrons: @[]
    )

    let pathResult = filtered.starMap.findPath(originSystem, systemId,
                                               dummyFleet)
    if not pathResult.found:
      continue

    let distance = pathResult.path.len - 1  # Path includes start system

    # Score using engine's Act-aware algorithm
    let score = scoreColonizationCandidate(
      filtered.turn,
      distance,
      system.planetClass
    )

    result.add(ETACTarget(
      systemId: systemId,
      planetClass: system.planetClass,
      distance: distance,
      score: score
    ))

  # Wave-based sorting: Prioritize frontier expansion (Phase 5)
  # Sort by wave (closest to frontier first), then by score
  let homeworld = getHomeworld(filtered)
  let uncolonizedSystemIds = result.mapIt(it.systemId)
  let waves = calculateColonizationWaves(filtered, homeworld, uncolonizedSystemIds)

  result.sort(proc(a, b: ETACTarget): int =
    let waveA = waves.getOrDefault(a.systemId, 999)
    let waveB = waves.getOrDefault(b.systemId, 999)

    # First priority: earlier wave (closer to frontier)
    if waveA != waveB:
      return cmp(waveA, waveB)

    # Second priority: higher score (better planet)
    return cmp(b.score, a.score)  # Descending
  )

  # Log wave information
  if waves.len > 0:
    let waveValues = toSeq(waves.values)
    let minWave = waveValues.min
    let maxWave = waveValues.max
    logInfo(LogCategory.lcAI,
            &"Eparch: Found {result.len} colonization targets " &
            &"(waves {minWave}-{maxWave}, prioritizing frontier expansion)")

  # Conservative approach: Use leaderboard data to detect stale intel
  # (Phase 4: Fix Rival Colony Filtering)
  var totalColonizedByAll = 0
  for houseId, colonyCount in filtered.houseColonies:
    totalColonizedByAll += colonyCount

  let totalSystemsOnMap = filtered.starMap.systems.len
  let estimatedUncolonized = totalSystemsOnMap - totalColonizedByAll

  logDebug(LogCategory.lcAI,
          &"Colonization estimate: {totalColonizedByAll}/{totalSystemsOnMap} colonized, " &
          &"~{estimatedUncolonized} uncolonized remaining")

  # If we have few confirmed uncolonized targets but leaderboard shows many exist,
  # we likely have stale intel - warn but still proceed (can't do much about fog-of-war)
  if result.len < estimatedUncolonized div 2:
    logWarn(LogCategory.lcAI,
            &"⚠️  Intel gap detected: Found {result.len} confirmed uncolonized systems, " &
            &"but leaderboard suggests ~{estimatedUncolonized} exist. " &
            &"May target rival colonies due to stale intel (fog-of-war limitation).")

  logDebug(LogCategory.lcAI,
           &"Found {result.len} uncolonized systems reachable from {originSystem}")

proc assignETACsToTargets(
  etacs: seq[tuple[fleetId: FleetId, etacId: string, location: SystemId]],
  filtered: FilteredGameState
): seq[ETACAssignment] =
  ## Assign ETACs to colonization targets using greedy best-match algorithm
  ## with PERSISTENT target tracking via existing fleet orders to prevent convergence
  ##
  ## **Algorithm:**
  ## 1. Check existing colonization orders in filtered.ownFleetOrders (persistent!)
  ## 2. For each ETAC WITHOUT an existing order, find all uncolonized systems on the map
  ## 3. Score targets using Act-aware algorithm
  ## 4. Assign ETAC to highest-scoring target (excluding already-targeted systems)
  ##
  ## **Convergence Fix:**
  ## Uses existing fleetOrders in GameState (persistent across turns, thread-safe)
  ## instead of controller-based tracking
  ##
  ## Returns: Sequence of ETAC assignments with target systems
  result = @[]

  # CRITICAL FIX: Check existing colonization orders from GameState (persistent!)
  var assignedTargets = initHashSet[SystemId]()
  var etacsWithOrders = initHashSet[FleetId]()

  for fleetId, order in filtered.ownFleetOrders:
    if order.orderType == FleetOrderType.Colonize and order.targetSystem.isSome:
      assignedTargets.incl(order.targetSystem.get())
      etacsWithOrders.incl(fleetId)

  logDebug(LogCategory.lcAI,
          &"Eparch: Starting ETAC assignment with {assignedTargets.len} " &
          &"already-targeted systems from existing fleet orders (persistent)")

  for (fleetId, etacId, location) in etacs:
    # Skip if this ETAC already has a colonization order
    if fleetId in etacsWithOrders:
      let existingTarget = filtered.ownFleetOrders[fleetId].targetSystem.get()
      logDebug(LogCategory.lcAI,
              &"ETAC {etacId} (fleet {fleetId}) already has order to {existingTarget}, skipping")
      continue

    # Find ALL uncolonized systems from this ETAC's location
    # ETACs can travel anywhere on the map (no range limit)
    let allTargets = findUncolonizedSystems(filtered, location)

    logInfo(LogCategory.lcAI,
            &"ETAC {etacId} (fleet {fleetId}) at {location}: " &
            &"findUncolonizedSystems returned {allTargets.len} targets, " &
            &"{assignedTargets.len} already assigned")

    # Filter out already-assigned targets
    var availableTargets = allTargets.filterIt(it.systemId notin assignedTargets)

    if availableTargets.len == 0:
      logInfo(LogCategory.lcAI,
              &"❌ No colonization targets available for ETAC {etacId} " &
              &"in fleet {fleetId} at {location} " &
              &"(all systems colonized or assigned)")
      continue

    # Sort by distance (closest first) - override wave/score sorting
    availableTargets.sort(proc(a, b: ETACTarget): int =
      cmp(a.distance, b.distance)
    )

    # Assign to closest available target
    let best = availableTargets[0]

    result.add(ETACAssignment(
      fleetId: fleetId,
      etacId: etacId,
      targetSystem: best.systemId,
      distance: best.distance,
      score: best.score,
      priority: 1  # High priority (colonization is critical in Act 1)
    ))

    # Mark target as assigned locally (prevent duplicate assignments THIS turn)
    assignedTargets.incl(best.systemId)

    logInfo(LogCategory.lcAI,
            &"Eparch: Assigned ETAC {etacId} (fleet {fleetId}) to colonize " &
            &"{best.systemId} ({best.planetClass}, {best.distance} jumps, " &
            &"score={best.score:.1f})")

  logInfo(LogCategory.lcAI,
          &"Eparch: Assigned {result.len} ETACs to colonization targets, " &
          &"{assignedTargets.len} total systems targeted (including existing orders)")

proc generateColonizationOrders(
  assignments: seq[ETACAssignment],
  filtered: FilteredGameState
): seq[FleetOrder] =
  ## Generate Colonize orders for ETAC assignments
  ##
  ## Returns: Sequence of FleetOrder objects ready for controller execution
  result = @[]

  for assignment in assignments:
    let order = FleetOrder(
      fleetId: assignment.fleetId,
      orderType: FleetOrderType.Colonize,
      targetSystem: some(assignment.targetSystem),
      priority: assignment.priority
    )

    result.add(order)

    logDebug(LogCategory.lcAI,
            &"Generated Colonize order for fleet {assignment.fleetId} → " &
            &"{assignment.targetSystem}")

  if result.len > 0:
    logInfo(LogCategory.lcAI,
            &"Eparch: Generated {result.len} ETAC colonization orders")

# ============================================================================
# ETAC Salvage (Post-Colonization Cleanup)
# ============================================================================

proc findNearestColony(
  fromLocation: SystemId,
  filtered: FilteredGameState
): Option[SystemId] =
  ## Find nearest friendly colony from a given location
  ## Returns: Some(SystemId) of nearest colony, or none() if no colonies exist
  if filtered.ownColonies.len == 0:
    return none(SystemId)

  var nearestColony = filtered.ownColonies[0].systemId
  var shortestDistance = int.high

  # Create dummy fleet for pathfinding
  let dummyFleet = Fleet(
    id: FleetId("salvage_dummy"),
    owner: filtered.viewingHouse,
    location: fromLocation,
    squadrons: @[]
  )

  # Calculate path distance to each colony
  for colony in filtered.ownColonies:
    let pathResult = filtered.starMap.findPath(fromLocation, colony.systemId,
                                               dummyFleet)
    if pathResult.found:
      let distance = pathResult.path.len - 1  # Path includes start system
      if distance < shortestDistance:
        shortestDistance = distance
        nearestColony = colony.systemId

  return some(nearestColony)

proc planETACSalvage(
  etacs: seq[tuple[fleetId: FleetId, etacId: string, location: SystemId]],
  filtered: FilteredGameState,
  houseId: HouseId
): seq[FleetOrder] =
  ## Generate salvage/movement orders for ALL ETACs (map is 100% colonized)
  ##
  ## **Precondition:** Map must be 100% colonized (checked by caller)
  ##
  ## **Purpose:**
  ## - Recover PP value from unused/idle ETACs
  ## - Clear out obsolete ETAC fleets after colonization complete
  ##
  ## **Algorithm:**
  ## 1. For each ETAC fleet, check if at friendly colony:
  ##    - If at colony: Issue Salvage order (executes same turn via arrivedFleets)
  ##    - If NOT at colony: Issue Move order to nearest colony (salvage next turn)
  ## 2. Engine will detach ETACs from mixed fleets (fleet_organization.nim)
  ## 3. Engine will recover salvage value when fleet arrives at colony
  ##
  ## Returns: Sequence of Salvage/Move orders for all ETAC fleets
  result = @[]

  logInfo(LogCategory.lcAI,
          &"Eparch: Processing {etacs.len} ETAC fleets for salvage " &
          &"(map 100% colonized)")

  for (fleetId, etacId, location) in etacs:
    # Check if ETAC fleet is already at a friendly colony
    var atOwnColony = false
    for colony in filtered.ownColonies:
      if colony.systemId == location:
        atOwnColony = true
        break

    if atOwnColony:
      # Fleet is at colony: Issue Salvage order with current location as target
      # Engine will mark fleet as "arrived" (location == target) and salvage in Income Phase
      let order = FleetOrder(
        fleetId: fleetId,
        orderType: FleetOrderType.Salvage,
        targetSystem: some(location),  # Current colony
        priority: 50
      )
      result.add(order)
      logInfo(LogCategory.lcAI,
              &"Eparch: Salvaging ETAC fleet {fleetId} at colony {location}")

    else:
      # Fleet is NOT at colony: Move to nearest colony first, salvage next turn
      let nearestColony = findNearestColony(location, filtered)

      if nearestColony.isNone:
        logWarn(LogCategory.lcAI,
                &"Eparch: Cannot salvage ETAC fleet {fleetId} - " &
                &"no friendly colonies available")
        continue

      let targetColony = nearestColony.get()

      # Issue Move order to nearest colony
      let order = FleetOrder(
        fleetId: fleetId,
        orderType: FleetOrderType.Move,
        targetSystem: some(targetColony),
        priority: 50
      )
      result.add(order)
      logInfo(LogCategory.lcAI,
              &"Eparch: Moving ETAC fleet {fleetId} to colony {targetColony} " &
              &"for salvage (currently at {location})")

  if result.len > 0:
    logInfo(LogCategory.lcAI,
            &"Eparch: Generated {result.len} ETAC salvage/movement orders " &
            &"(map fully colonized, recovering idle ETACs)")

# ============================================================================
# Main Entry Point: Unified Expansion Planning
# ============================================================================

proc planExpansionOperations*(
  filtered: FilteredGameState,
  controller: var AIController,
  currentAct: ai_common_types.GameAct
): ExpansionPlan =
  ## Main entry point: Plan ALL expansion operations (construction + colonization)
  ##
  ## **Workflow:**
  ## 1. Assess ETAC construction needs (requirements generation)
  ## 2. Find available ETACs with cargo
  ## 3. Assign ETACs to colonization targets
  ## 4. Generate Colonize orders for assignments
  ##
  ## Returns: ExpansionPlan with both construction requirements AND colonization orders
  ##
  ## **Usage:**
  ## ```nim
  ## let expansionPlan = planExpansionOperations(filtered, controller, currentAct)
  ## result.add(expansionPlan.buildRequirements)  # Add to economic requirements
  ## controller.eparchColonizationOrders = expansionPlan.colonizationOrders  # Store for Phase 6.9
  ## ```

  logInfo(LogCategory.lcAI,
          &"Eparch: Planning expansion operations for {controller.houseId}")

  # Part 1: ETAC Construction Requirements
  let (buildReqs, stats) = assessETACConstructionNeeds(filtered, controller, currentAct)
  result.buildRequirements = buildReqs
  result.etacsReady = stats.readyETACs
  result.etacsInConstruction = stats.etacCount - stats.readyETACs
  result.uncolonizedSystems = stats.uncolonizedActual

  # Part 2: ETAC Colonization Orders OR Salvage
  # Check if map is 100% colonized (use leaderboard data)
  var totalColonizedByAll = 0
  for houseId, colonyCount in filtered.houseColonies:
    totalColonizedByAll += colonyCount
  let totalSystemsOnMap = filtered.starMap.systems.len
  let mapFullyColonized = (totalColonizedByAll >= totalSystemsOnMap)

  if mapFullyColonized:
    # Map 100% colonized - ETAC salvage now handled by fleet_organization.nim
    # (detachAndSalvageETACs function detaches from mixed fleets and issues salvage orders)
    logInfo(LogCategory.lcAI,
            &"Eparch: Map 100% colonized ({totalColonizedByAll}/{totalSystemsOnMap}), " &
            &"ETAC salvage handled by fleet organization")
    result.colonizationOrders = @[]
    return

  # Map not fully colonized - normal colonization logic
  let etacs = getAvailableETACs(filtered, controller.houseId)

  if etacs.len == 0:
    logDebug(LogCategory.lcAI,
            &"Eparch: {controller.houseId} has no ETACs ready to colonize")
    result.colonizationOrders = @[]
    return

  let assignments = assignETACsToTargets(etacs, filtered)

  if assignments.len == 0:
    logDebug(LogCategory.lcAI,
            &"Eparch: {controller.houseId} has {etacs.len} ETACs " &
            &"but no colonization targets")
    result.colonizationOrders = @[]
    return

  result.colonizationOrders = generateColonizationOrders(assignments, filtered)

  logInfo(LogCategory.lcAI,
          &"Eparch: Expansion planning complete - " &
          &"{result.buildRequirements.len} construction requirements, " &
          &"{result.colonizationOrders.len} colonization orders, " &
          &"{result.etacsReady} ETACs ready, " &
          &"{result.uncolonizedSystems} systems uncolonized")
