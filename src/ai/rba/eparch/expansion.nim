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
import ../../../engine/[gamestate, fleet, orders, fog_of_war, starmap, logger]
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

proc findBestETACConstructionColony(
  colonies: seq[Colony]
): Option[SystemId] =
  ## Find best colony for ETAC ship construction
  ## Priority: Shipyards > Spaceports (ETACs are ships)
  ## Score by production capacity (higher production = faster build)
  var bestColony: Option[SystemId] = none(SystemId)
  var highestScore = -1000.0

  # Phase 1: Prefer colonies with Shipyards (dedicated ship construction)
  for colony in colonies:
    if colony.shipyards.len > 0:
      let score = float(colony.production)
      if score > highestScore:
        bestColony = some(colony.systemId)
        highestScore = score

  # Phase 2: If no Shipyards, accept colonies with Spaceports
  if bestColony.isNone:
    highestScore = -1000.0
    for colony in colonies:
      if colony.spaceports.len > 0:
        let score = float(colony.production)
        if score > highestScore:
          bestColony = some(colony.systemId)
          highestScore = score

  return bestColony

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
    for ship in fleet.spaceLiftShips:
      if ship.shipClass == ShipClass.ETAC:
        etacCount += 1
        # Check if ETAC has colonists loaded (ready to colonize)
        if ship.cargo.cargoType == CargoType.Colonists and ship.cargo.quantity > 0:
          readyETACs += 1
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

      # Find best colony for ETAC construction (prefer Shipyard, accept Spaceport)
      let buildColony = findBestETACConstructionColony(filtered.ownColonies)

      if buildColony.isNone:
        logWarn(LogCategory.lcAI,
                &"Eparch: Cannot create ETAC requirement - no colony with " &
                &"Spaceport/Shipyard available")
      else:
        # ✅ KEY CHANGE: EconomicRequirement (Eparch) instead of BuildRequirement (Domestikos)
        result.requirements.add(EconomicRequirement(
          requirementType: EconomicRequirementType.Facility,
          priority: priority,
          targetColony: buildColony.get(),  # ✅ FIX: Valid colony with Shipyard/Spaceport
          facilityType: some("ETAC"),  # Treat ETAC as infrastructure
          terraformTarget: none(PlanetClass),
          estimatedCost: etacCost * needed,
          reason: &"Expansion (have {etacCount}/{targetETACs} ETACs, " &
                  &"{uncolonizedActual} systems uncolonized, decay={decayFactor:.2f})"
        ))

        logInfo(LogCategory.lcAI,
               &"Eparch: ETAC construction requirement - {needed} ETACs " &
               &"at colony {buildColony.get()} " &
               &"(have {etacCount}, target {targetETACs}, " &
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

    for ship in fleet.spaceLiftShips:
      logInfo(LogCategory.lcAI,
              &"  Fleet {fleet.id} at {fleet.location}: " &
              &"{ship.shipClass} cargo={ship.cargo.cargoType}:{ship.cargo.quantity}")

      if ship.shipClass == ShipClass.ETAC and ship.cargo.quantity == 0:
        logWarn(LogCategory.lcAI,
                &"⚠️  🐛 FOUND EMPTY ETAC! {ship.id} in fleet {fleet.id} " &
                &"at {fleet.location} - ENGINE BUG!")

      if ship.shipClass == ShipClass.ETAC and
         ship.cargo.cargoType == CargoType.Colonists and
         ship.cargo.quantity > 0:
        result.add((fleet.id, ship.id, fleet.location))
        logInfo(LogCategory.lcAI,
                &"  ✅ Found loaded ETAC {ship.id} ({ship.cargo.quantity} PTU)")

  logInfo(LogCategory.lcAI,
          &"{houseId} has {result.len} ETACs ready to colonize (Eparch)")

proc findUncolonizedSystems(
  filtered: FilteredGameState,
  originSystem: SystemId,
  maxRange: int
): seq[ETACTarget] =
  ## Find all uncolonized systems within range and score them
  ##
  ## Uses Act-aware scoring from engine (frontier expansion in Act 1-2,
  ## quality consolidation in Act 3-4)
  ##
  ## Returns: Scored colonization targets sorted by score (highest first)
  result = @[]

  # Scan all visible systems
  for systemId, visSystem in filtered.visibleSystems:
    # Skip if already colonized
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

    if isColonized:
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
      squadrons: @[],
      spaceLiftShips: @[]
    )

    let pathResult = filtered.starMap.findPath(originSystem, systemId,
                                               dummyFleet)
    if not pathResult.found:
      continue

    let distance = pathResult.path.len - 1  # Path includes start system

    if distance > maxRange:
      continue

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

  # Sort by score (highest first)
  result.sort(proc(a, b: ETACTarget): int =
    if a.score > b.score: -1
    elif a.score < b.score: 1
    else: 0
  )

  logDebug(LogCategory.lcAI,
           &"Found {result.len} uncolonized systems within {maxRange} jumps " &
           &"of {originSystem}")

proc assignETACsToTargets(
  etacs: seq[tuple[fleetId: FleetId, etacId: string, location: SystemId]],
  filtered: FilteredGameState,
  maxRange: int = 20
): seq[ETACAssignment] =
  ## Assign ETACs to colonization targets using greedy best-match algorithm
  ##
  ## **Algorithm:**
  ## 1. For each ETAC, find all uncolonized systems within range
  ## 2. Score targets using Act-aware algorithm
  ## 3. Assign ETAC to highest-scoring target
  ## 4. Mark target as assigned (prevent duplicate assignments)
  ##
  ## Returns: Sequence of ETAC assignments with target systems
  result = @[]

  var assignedTargets = initHashSet[SystemId]()

  for (fleetId, etacId, location) in etacs:
    # Find uncolonized systems within range of this ETAC
    let targets = findUncolonizedSystems(filtered, location, maxRange)

    # Filter out already-assigned targets
    let availableTargets = targets.filterIt(it.systemId notin assignedTargets)

    if availableTargets.len == 0:
      logDebug(LogCategory.lcAI,
              &"No colonization targets available for ETAC {etacId} " &
              &"in fleet {fleetId}")
      continue

    # Assign to best available target
    let best = availableTargets[0]

    result.add(ETACAssignment(
      fleetId: fleetId,
      etacId: etacId,
      targetSystem: best.systemId,
      distance: best.distance,
      score: best.score,
      priority: 1  # High priority (colonization is critical in Act 1)
    ))

    # Mark target as assigned
    assignedTargets.incl(best.systemId)

    logInfo(LogCategory.lcAI,
            &"Eparch: Assigned ETAC {etacId} (fleet {fleetId}) to colonize " &
            &"{best.systemId} ({best.planetClass}, {best.distance} jumps, " &
            &"score={best.score:.1f})")

  logInfo(LogCategory.lcAI,
          &"Eparch: Assigned {result.len} ETACs to colonization targets")

proc cleanupCompletedColonizations*(
  controller: var AIController,
  filtered: FilteredGameState
) =
  ## Remove systems from targetedColonizationSystems once colonized
  ## Remove ETAC assignments for ETACs that no longer have cargo

  # Remove colonized systems
  var toRemove: seq[SystemId] = @[]
  for targetSystem in controller.targetedColonizationSystems:
    # Check if now colonized
    for colony in filtered.ownColonies:
      if colony.systemId == targetSystem:
        toRemove.add(targetSystem)
        break

  for systemId in toRemove:
    controller.targetedColonizationSystems.excl(systemId)
    logInfo(LogCategory.lcAI,
            &"Eparch: Removed {systemId} from targets (now colonized)")

  # Remove assignments for ETACs without cargo
  var fleetsToRemove: seq[FleetId] = @[]
  for fleetId, targetSystem in controller.etacAssignments:
    var hasCargoETAC = false
    for fleet in filtered.ownFleets:
      if fleet.id == fleetId:
        for ship in fleet.spaceLiftShips:
          if ship.shipClass == ShipClass.ETAC and
             ship.cargo.cargoType == CargoType.Colonists and
             ship.cargo.quantity > 0:
            hasCargoETAC = true
            break
        break

    if not hasCargoETAC:
      fleetsToRemove.add(fleetId)
      controller.targetedColonizationSystems.excl(targetSystem)

  for fleetId in fleetsToRemove:
    let targetSystem = controller.etacAssignments[fleetId]
    controller.etacAssignments.del(fleetId)
    logDebug(LogCategory.lcAI,
            &"Eparch: Removed ETAC assignment for fleet {fleetId} " &
            &"(target {targetSystem}, cargo depleted)")

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
# Main Entry Point: Unified Expansion Planning
# ============================================================================

proc planExpansionOperations*(
  filtered: FilteredGameState,
  controller: AIController,
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

  # Part 2: ETAC Colonization Orders
  let etacs = getAvailableETACs(filtered, controller.houseId)

  if etacs.len == 0:
    logDebug(LogCategory.lcAI,
            &"Eparch: {controller.houseId} has no ETACs ready to colonize")
    result.colonizationOrders = @[]
    return

  let assignments = assignETACsToTargets(etacs, filtered, maxRange = 20)

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
