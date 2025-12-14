## Tactical Operations Module for EC4X Rule-Based AI
##
## Handles fleet coordination, combat assessment, and tactical planning
## Respects fog-of-war - uses only visible tactical information

import std/[tables, options, algorithm, sequtils, strformat, random, sets]
import ../common/types
import ../../engine/[gamestate, fog_of_war, fleet, squadron, starmap, logger, orders, standing_orders]
import ../../engine/order_types  # For StandingOrder
import ../../engine/diplomacy/types as dip_types
import ../../engine/intelligence/types as intel_types
import ../../common/types/[core, planets]
import ./controller_types
import ./config  # RBA configuration system
import ./intelligence  # For isSystemColonized, getColony
import ./protostrator/assessment  # For getOwnedFleets
import ./shared/colony_assessment  # Shared defense assessment
import ./tactical_assessment  # Extracted: assessRelativeStrength, identifyVulnerableTargets

# =============================================================================
# Helper Functions
# =============================================================================

proc getOwnedColonies*(filtered: FilteredGameState, houseId: HouseId): seq[Colony] =
  ## Get all colonies owned by a house
  ## RESPECTS FOG-OF-WAR: Only returns own colonies
  if houseId != filtered.viewingHouse:
    return @[]
  return filtered.ownColonies

# getColony - moved to intelligence.nim to avoid duplication

proc isSingleScoutSquadron*(squadron: Squadron): bool =
  ## Check if squadron is a single scout (ideal for espionage)
  result = squadron.flagship.shipClass == ShipClass.Scout and squadron.ships.len == 0

# =============================================================================
# Fleet Coordination
# =============================================================================

proc planCoordinatedOperation*(controller: var AIController, filtered: FilteredGameState,
                                opType: OperationType, target: SystemId,
                                fleets: seq[FleetId], assembly: SystemId, turn: int) =
  ## Plan a multi-fleet coordinated operation
  let operation = CoordinatedOperation(
    operationType: opType,
    targetSystem: target,
    assemblyPoint: assembly,
    requiredFleets: fleets,
    readyFleets: @[],
    turnScheduled: turn,
    executionTurn: none(int)
  )
  controller.operations.add(operation)
  logInfo(LogCategory.lcAI, &"{controller.houseId} CREATED {opType} OPERATION: target={target}, assembly={assembly}, fleets={fleets.len}")

proc updateOperationStatus*(controller: var AIController, filtered: FilteredGameState) =
  ## Update status of ongoing coordinated operations
  for op in controller.operations.mitems:
    op.readyFleets.setLen(0)
    for fleetId in op.requiredFleets:
      for fleet in filtered.ownFleets:
        if fleet.id == fleetId:
          if fleet.location == op.assemblyPoint:
            op.readyFleets.add(fleetId)
          break

    if op.readyFleets.len == op.requiredFleets.len and op.executionTurn.isNone:
      op.executionTurn = some(filtered.turn + 1)

proc shouldExecuteOperation*(controller: AIController, op: CoordinatedOperation, turn: int): bool =
  ## Check if operation should execute this turn
  if op.executionTurn.isSome and op.executionTurn.get() <= turn:
    return op.readyFleets.len == op.requiredFleets.len
  return false

proc removeCompletedOperations*(controller: var AIController, turn: int) =
  ## Remove operations that are too old or completed
  controller.operations = controller.operations.filterIt(
    it.executionTurn.isNone or it.executionTurn.get() >= turn - 2
  )

# =============================================================================
# Strategic Defense
# =============================================================================

proc identifyImportantColonies*(controller: AIController, filtered: FilteredGameState): seq[SystemId] =
  ## Identify colonies that need defense-in-depth
  ## Uses shared colony_assessment module for consistent high-value determination
  result = @[]
  for colony in filtered.ownColonies:
    if colony.owner == controller.houseId:
      if colony_assessment.isHighValueColony(colony):
        result.add(colony.systemId)

proc assignStrategicReserve*(controller: var AIController, fleetId: FleetId,
                              assignedSystem: Option[SystemId], radius: int = -1) =
  ## Designate a fleet as strategic reserve
  let effectiveRadius = if radius == -1: globalRBAConfig.tactical.response_radius_jumps else: radius
  let reserve = StrategicReserve(
    fleetId: fleetId,
    assignedTo: assignedSystem,
    responseRadius: effectiveRadius
  )
  controller.reserves.add(reserve)

proc getReserveForSystem*(controller: AIController, systemId: SystemId): Option[FleetId] =
  ## Get strategic reserve assigned to defend a system
  for reserve in controller.reserves:
    if reserve.assignedTo.isSome and reserve.assignedTo.get() == systemId:
      return some(reserve.fleetId)
  return none(FleetId)

proc manageStrategicReserves*(controller: var AIController, filtered: FilteredGameState) =
  ## Assign fleets as strategic reserves for important colonies
  let importantSystems = controller.identifyImportantColonies(filtered)

  for systemId in importantSystems:
    if controller.getReserveForSystem(systemId).isSome:
      continue

    let systemCoords = filtered.starMap.systems[systemId].coords
    var bestFleet: Option[FleetId] = none(FleetId)
    var minDist = 999

    for fleet in filtered.ownFleets:
      if fleet.owner != controller.houseId or fleet.combatStrength() == 0:
        continue

      var isReserve = false
      for reserve in controller.reserves:
        if reserve.fleetId == fleet.id:
          isReserve = true
          break

      if isReserve:
        continue

      let fleetCoords = filtered.starMap.systems[fleet.location].coords
      let dx = abs(fleetCoords.q - systemCoords.q)
      let dy = abs(fleetCoords.r - systemCoords.r)
      let dz = abs((fleetCoords.q + fleetCoords.r) - (systemCoords.q + systemCoords.r))
      let dist = (dx + dy + dz) div 2

      if dist < minDist and dist <= globalRBAConfig.tactical.response_radius_jumps:
        minDist = dist
        bestFleet = some(fleet.id)

    if bestFleet.isSome:
      controller.assignStrategicReserve(bestFleet.get(), some(systemId), globalRBAConfig.tactical.response_radius_jumps)

proc respondToThreats*(controller: var AIController, filtered: FilteredGameState): seq[tuple[reserveFleet: FleetId, threatSystem: SystemId]] =
  ## Check for enemy fleets near protected systems
  ## NOW WITH TRAVEL TIME AWARENESS: Only dispatches reserves that can respond in time
  result = @[]

  for reserve in controller.reserves:
    if reserve.assignedTo.isNone:
      continue

    let protectedSystem = reserve.assignedTo.get()
    let protectedCoords = filtered.starMap.systems[protectedSystem].coords

    # Find nearest threat within response radius
    var nearestThreat: Option[tuple[location: SystemId, distance: int, eta: int]] = none(tuple[location: SystemId, distance: int, eta: int])
    var minDist = 999

    for visFleet in filtered.visibleFleets:
      if visFleet.owner == controller.houseId:
        continue

      # Skip if no combat strength (check estimatedShipCount for enemy fleets)
      if visFleet.estimatedShipCount.isSome and visFleet.estimatedShipCount.get() == 0:
        continue

      let fleetCoords = filtered.starMap.systems[visFleet.location].coords
      let dx = abs(fleetCoords.q - protectedCoords.q)
      let dy = abs(fleetCoords.r - protectedCoords.r)
      let dz = abs((fleetCoords.q + fleetCoords.r) - (protectedCoords.q + protectedCoords.r))
      let dist = (dx + dy + dz) div 2

      if dist <= reserve.responseRadius and dist < minDist:
        minDist = dist
        # Calculate reserve's ETA to threat location
        let reserveFleetOpt = filtered.ownFleets.filterIt(it.id == reserve.fleetId)
        if reserveFleetOpt.len > 0:
          let reserveFleet = reserveFleetOpt[0]
          let etaOpt = calculateETA(filtered.starMap, reserveFleet.location, visFleet.location, reserveFleet)
          if etaOpt.isSome:
            let threat: tuple[location: SystemId, distance: int, eta: int] = (visFleet.location, dist, etaOpt.get())
            nearestThreat = some(threat)

    # Only dispatch if reserve can respond in reasonable time
    # Compare threat distance to protected system vs reserve ETA
    # If threat is 2 jumps away and reserve needs 5 turns, too late
    if nearestThreat.isSome:
      let threat = nearestThreat.get()
      if threat.eta <= globalRBAConfig.tactical.max_response_eta_turns:
        logInfo(LogCategory.lcAI, &"{controller.houseId} dispatching reserve {reserve.fleetId} " &
                &"to threat at {threat.location} (ETA: {threat.eta} turns)")
        result.add((reserveFleet: reserve.fleetId, threatSystem: threat.location))

# =============================================================================
# Fallback Routes (Safe Retreat Planning)
# =============================================================================

# isSystemColonized - moved to intelligence.nim to avoid duplication

proc updateFallbackRoutes*(controller: var AIController, filtered: FilteredGameState) =
  ## Update fallback/retreat routes for all colonies
  let myColonies = getOwnedColonies(filtered, controller.houseId)
  if myColonies.len == 0:
    return

  # Clear stale routes
  controller.fallbackRoutes = controller.fallbackRoutes.filterIt(
    filtered.turn - it.lastUpdated < 20
  )

  for colony in myColonies:
    var hasRecentRoute = false
    for route in controller.fallbackRoutes:
      if route.region == colony.systemId and filtered.turn - route.lastUpdated < 10:
        hasRecentRoute = true
        break

    if hasRecentRoute:
      continue

    var bestFallback: Option[SystemId] = none(SystemId)
    var minDist = 999

    for otherColony in myColonies:
      if otherColony.systemId == colony.systemId:
        continue

      var isSafe = otherColony.starbases.len > 0
      if not isSafe:
        var fleetStrength = 0
        for fleet in filtered.ownFleets:
          if fleet.owner == controller.houseId and fleet.location == otherColony.systemId:
            fleetStrength += fleet.squadrons.len
        isSafe = fleetStrength >= 2

      if not isSafe:
        continue

      let dummyFleet = Fleet(
        id: "temp",
        owner: controller.houseId,
        location: colony.systemId,
        squadrons: @[],
        spaceLiftShips: @[],
        status: FleetStatus.Active
      )

      let pathResult = filtered.starMap.findPath(colony.systemId, otherColony.systemId, dummyFleet)
      if pathResult.path.len == 0:
        continue

      var pathIsSafe = true
      for pathSystemId in pathResult.path:
        if pathSystemId != colony.systemId and isSystemColonized(filtered, pathSystemId):
          let pathColonyOpt = getColony(filtered, pathSystemId)
          if pathColonyOpt.isSome:
            let pathColony = pathColonyOpt.get()
            if pathColony.owner != controller.houseId:
              let house = filtered.ownHouse
              if house.diplomaticRelations.isEnemy(pathColony.owner):
                pathIsSafe = false
                break

      if not pathIsSafe:
        continue

      let dist = pathResult.path.len - 1

      if dist < minDist:
        minDist = dist
        bestFallback = some(otherColony.systemId)

    if bestFallback.isSome:
      controller.fallbackRoutes = controller.fallbackRoutes.filterIt(
        it.region != colony.systemId
      )
      controller.fallbackRoutes.add(FallbackRoute(
        region: colony.systemId,
        fallbackSystem: bestFallback.get(),
        lastUpdated: filtered.turn
      ))

proc syncFallbackRoutesToEngine*(controller: AIController, state: var GameState) =
  ## Sync AI controller's fallback routes to engine's House state
  if controller.houseId in state.houses:
    # CRITICAL: Get, modify, write back to persist
    var house = state.houses[controller.houseId]
    house.fallbackRoutes = controller.fallbackRoutes
    state.houses[controller.houseId] = house

proc findFallbackSystem*(controller: AIController, currentSystem: SystemId): Option[SystemId] =
  ## Find designated fallback system for a region
  for route in controller.fallbackRoutes:
    if route.region == currentSystem:
      return some(route.fallbackSystem)
  return none(SystemId)

# =============================================================================
# Relative Strength Assessment
# =============================================================================
# Extracted to tactical_assessment.nim to maintain file size limits
# Import: assessRelativeStrength, identifyVulnerableTargets

proc identifyInvasionOpportunities*(controller: var AIController, filtered: FilteredGameState, currentAct: GameAct): seq[SystemId] =
  ## Identify enemy colonies that warrant coordinated invasion
  ## USES INTELLIGENCE REPORTS: Combines current visibility with intelligence database
  ## This allows invasion planning even when scouts aren't actively watching targets
  ##
  ## Act 1 behavior (user preference): Only undefended colonies allowed ("border incidents")
  ## Act 2+: All vulnerable colonies based on aggression and strength ratios
  result = @[]

  let vulnerableTargets = controller.identifyVulnerableTargets(filtered)

  # Build list of known enemy colonies from:
  # 1. Currently visible colonies (fog-of-war)
  # 2. Intelligence reports from scouts, spies, combat encounters, starbase surveillance
  var knownEnemyColonies: seq[tuple[systemId: SystemId, owner: HouseId]] = @[]

  # Add currently visible colonies
  for visCol in filtered.visibleColonies:
    if visCol.owner != controller.houseId:
      knownEnemyColonies.add((visCol.systemId, visCol.owner))

  # Add colonies from intelligence database (even if not currently visible)
  for systemId, report in filtered.ownHouse.intelligence.colonyReports:
    if report.targetOwner != controller.houseId:
      # Check if not already in list
      var alreadyKnown = false
      for known in knownEnemyColonies:
        if known.systemId == systemId:
          alreadyKnown = true
          break
      if not alreadyKnown:
        knownEnemyColonies.add((systemId, report.targetOwner))

  logDebug(LogCategory.lcAI, &"{controller.houseId} found {vulnerableTargets.len} vulnerable targets, {filtered.visibleColonies.len} visible colonies, {knownEnemyColonies.len} known enemy colonies from intel")

  # Convert vulnerable targets to a set for O(1) lookup
  var vulnerableSet: seq[SystemId] = @[]
  for target in vulnerableTargets:
    vulnerableSet.add(target.systemId)

  # Check known enemy colonies for invasion opportunities
  var checkedCount = 0
  var skippedNotVulnerable = 0
  var skippedDefense = 0
  var skippedStrength = 0

  for enemyCol in knownEnemyColonies:
    checkedCount += 1

    # Skip if not in vulnerable targets list
    if enemyCol.systemId notin vulnerableSet:
      skippedNotVulnerable += 1
      continue

    # Get intel from intelligence database if available
    let intelReport = filtered.ownHouse.intelligence.getColonyIntel(enemyCol.systemId)

    # Estimate defense strength from intelligence reports or visible data
    var defenseStrength = 0
    if intelReport.isSome:
      # Use intelligence data
      defenseStrength += intelReport.get().starbaseLevel * 100
      defenseStrength += intelReport.get().defenses * 10  # Ground units

    # Check currently visible colonies for up-to-date info
    for visCol in filtered.visibleColonies:
      if visCol.systemId == enemyCol.systemId:
        if visCol.starbaseLevel.isSome and visCol.starbaseLevel.get() > 0:
          defenseStrength = visCol.starbaseLevel.get() * 100  # Override with current data

    # Check for defending fleets (visible through fog-of-war)
    for fleet in filtered.visibleFleets:
      if fleet.owner == enemyCol.owner and fleet.location == enemyCol.systemId:
        if fleet.estimatedShipCount.isSome:
          defenseStrength += fleet.estimatedShipCount.get() * 10

    # Check if colony is valuable (use intelligence or visible data)
    var production = 0
    var resources = ResourceRating.Poor

    if intelReport.isSome:
      production = intelReport.get().industry
      resources = ResourceRating.Poor  # Not in ColonyIntelReport, use conservative estimate

    # Override with current visible data if available
    for visCol in filtered.visibleColonies:
      if visCol.systemId == enemyCol.systemId:
        if visCol.production.isSome:
          production = visCol.production.get()
        elif visCol.estimatedIndustry.isSome:
          production = visCol.estimatedIndustry.get()
        if visCol.resources.isSome:
          resources = visCol.resources.get()

    let isValuable = production >= 50 or
                     resources in [ResourceRating.Rich, ResourceRating.VeryRich]

    # Find the target in vulnerable list to get relative strength
    var relativeStrength = 0.5  # Default if not found
    for target in vulnerableTargets:
      if target.systemId == enemyCol.systemId:
        relativeStrength = target.relativeStrength
        break

    # BALANCE: Be more aggressive with invasion targeting
    # Accept any target weaker than us (< 0.5) or valuable targets even if equal strength (< 0.7)
    let preferTarget = (relativeStrength < 0.5) or
                       (isValuable and relativeStrength < 0.7)

    if not preferTarget:
      skippedStrength += 1
      continue

    if defenseStrength >= 200:
      skippedDefense += 1
      continue

    # Act 1 filter: Only allow undefended colonies (border incidents)
    if currentAct == GameAct.Act1_LandGrab:
      if defenseStrength > 0:
        continue  # Skip defended colonies in Act 1

    result.add(enemyCol.systemId)

  logDebug(LogCategory.lcAI, &"{controller.houseId} invasion filtering: checked={checkedCount}, skippedNotVulnerable={skippedNotVulnerable}, skippedDefense={skippedDefense}, skippedStrength={skippedStrength}, opportunities={result.len}")

proc countAvailableFleets*(controller: AIController, filtered: FilteredGameState): int =
  ## Count fleets not currently in operations
  result = 0
  for fleet in filtered.ownFleets:
    if fleet.owner != controller.houseId:
      continue

    var inOperation = false
    for op in controller.operations:
      if fleet.id in op.requiredFleets:
        inOperation = true
        break

    if not inOperation and fleet.combatStrength() > 0:
      result += 1

proc isETACFleet(fleet: Fleet): bool =
  ## Check if fleet has ETACs (colonization-only fleet)
  for ship in fleet.spaceLiftShips:
    if ship.shipClass == ShipClass.ETAC:
      return true
  return false

proc isColonizationOrder(orderType: FleetOrderType): bool =
  ## Check if order is valid for ETAC fleets
  orderType in {
    FleetOrderType.Hold,
    FleetOrderType.Move,
    FleetOrderType.SeekHome,
    FleetOrderType.Colonize
  }

proc generateFleetOrders*(controller: var AIController, filtered: FilteredGameState, rng: var Rand,
                          standingOrders: Table[FleetId, StandingOrder] = initTable[FleetId, StandingOrder](),
                          alreadyTargeted: HashSet[SystemId] = initHashSet[SystemId]()): seq[FleetOrder] =
  ## Generate fleet orders for all owned fleets
  ## NOW WITH PHASE-AWARE PRIORITIES (4-act structure)
  ## standingOrders: Skip tactical orders for fleets with AutoColonize (let standing orders handle it)
  ## alreadyTargeted: Systems already targeted by standing orders (passed from orders.nim for coordination)
  result = @[]

  let myFleets = getOwnedFleets(filtered, controller.houseId)
  let currentAct = getCurrentGameAct(filtered.turn)

  # Update operation status
  updateOperationStatus(controller, filtered)
  removeCompletedOperations(controller, filtered.turn)

  logInfo(LogCategory.lcAI, &"{controller.houseId} Turn {filtered.turn} ({currentAct}): Generating orders for {myFleets.len} fleets")

  # Build set of systems already targeted by other fleets to prevent duplicates
  # Bug fix: Multiple fleets were targeting same system, causing 78% colonization failure rate
  # Start with targets from standing orders (passed as parameter)
  var alreadyTargeted = alreadyTargeted  # Make mutable copy
  for fleetId, existingOrder in filtered.ownFleetOrders:
    if existingOrder.orderType == FleetOrderType.Colonize and existingOrder.targetSystem.isSome:
      alreadyTargeted.incl(existingOrder.targetSystem.get())
      logDebug(LogCategory.lcAI, &"  System {existingOrder.targetSystem.get()} already targeted by {fleetId}")

  for fleet in myFleets:
    var order: FleetOrder
    order.fleetId = fleet.id
    order.priority = 1

    # Determine fleet type for logging
    var hasETAC = false
    var hasCombatShips = false
    for ship in fleet.spaceLiftShips:
      if ship.shipClass == ShipClass.ETAC:
        hasETAC = true
    if fleet.squadrons.len > 0:
      hasCombatShips = true

    let fleetType = if hasETAC: "ETAC" elif hasCombatShips: "Combat" else: "Empty"
    logDebug(LogCategory.lcAI, &"  Fleet {fleet.id} ({fleetType}) at {fleet.location}: Determining orders...")

    # Special handling for ETAC fleets
    if isETACFleet(fleet):
      # Check if ETAC has colonists
      var hasColonists = false
      var totalPTU = 0
      for ship in fleet.spaceLiftShips:
        if ship.cargo.cargoType == CargoType.Colonists:
          hasColonists = true
          totalPTU += ship.cargo.quantity

      if hasColonists:
        # CRITICAL FIX: Only defer if fleet ACTUALLY has AutoColonize standing order
        # Bug: Was skipping all loaded ETACs, causing 0 colonize orders generated
        # Check: Standing order exists, is AutoColonize, is enabled, and not suspended
        if fleet.id in standingOrders and
           standingOrders[fleet.id].orderType == StandingOrderType.AutoColonize and
           standingOrders[fleet.id].enabled and
           not standingOrders[fleet.id].suspended:
          logDebug(LogCategory.lcAI,
            &"Fleet {fleet.id} has {totalPTU} PTU and active AutoColonize standing order - deferring")
          continue
        # No standing order - fall through to tactical colonization logic
        logDebug(LogCategory.lcAI,
          &"Fleet {fleet.id} has {totalPTU} PTU but no AutoColonize - tactical will assign orders")
      else:
        # ETAC empty - check for AutoColonize standing order first
        # If present and active, let standing order handle reload (standing_orders.nim:490-523)
        # Check: Standing order exists, is AutoColonize, is enabled, and not suspended
        if fleet.id in standingOrders and
           standingOrders[fleet.id].orderType == StandingOrderType.AutoColonize and
           standingOrders[fleet.id].enabled and
           not standingOrders[fleet.id].suspended:
          logDebug(LogCategory.lcAI,
            &"Fleet {fleet.id} empty ETAC with active AutoColonize standing order - deferring to standing order for reload")
          continue

        # No standing order - tactical sends ETAC home for reload
        # Find nearest colony with sufficient population for PTU transfer
        const MIN_POPULATION_FOR_RELOAD = 3
        var bestColony: Option[SystemId] = none(SystemId)
        var bestDistance = 999

        for colony in filtered.ownColonies:
          if colony.population < MIN_POPULATION_FOR_RELOAD:
            continue  # Colony too small to spare PTUs

          # Calculate distance via jump lanes
          let pathResult = filtered.starMap.findPath(fleet.location, colony.systemId, fleet)
          if not pathResult.found:
            continue

          let distance = pathResult.path.len - 1
          if distance < bestDistance:
            bestDistance = distance
            bestColony = some(colony.systemId)

        if bestColony.isSome:
          let targetColony = bestColony.get()
          order.orderType = FleetOrderType.Move
          order.targetSystem = some(targetColony)
          order.priority = 90  # High priority - need reload

          result.add(order)

          # Get colony population for logging
          let targetColonyData = filtered.ownColonies.filterIt(it.systemId == targetColony)[0]
          logInfo(LogCategory.lcAI,
            &"Fleet {fleet.id} empty ETAC seeking reload at {targetColony} " &
            &"({bestDistance} jumps, pop {targetColonyData.population})")
          continue
        else:
          logWarn(LogCategory.lcAI,
            &"Fleet {fleet.id} empty ETAC has no viable reload colonies (need pop >= {MIN_POPULATION_FOR_RELOAD})")
          continue

    # ==========================================================================
    # PHASE-AWARE PRIORITY SYSTEM
    # ==========================================================================
    # Act 1: Exploration >> Colonization >> Defense
    # Act 2: Consolidation >> Military >> Opportunistic Colonization
    # Act 3+: Invasions >> Defense >> Combat
    # ==========================================================================

    case currentAct:
    of GameAct.Act1_LandGrab:
      # ========================================================================
      # ACT 1: LAND GRAB (Turns 1-7)
      # Priority: Exploration (70-80%) >> Colonization >> Minimal Defense
      # ========================================================================

      # Priority 1a: ETACs colonize best available system using Act-aware scoring
      # SKIP if fleet has active AutoColonize standing order (let standing order handle it)
      let hasActiveAutoColonize = fleet.id in standingOrders and
                                   standingOrders[fleet.id].orderType == StandingOrderType.AutoColonize and
                                   standingOrders[fleet.id].enabled and
                                   not standingOrders[fleet.id].suspended
      if hasETAC and not hasActiveAutoColonize:
        # Use engine function for Act-aware colonization target selection
        # Act 1: Prioritizes distance over quality (frontier expansion)
        let bestTarget = findColonizationTargetFiltered(
          filtered, fleet, fleet.location,
          maxRange = 20,  # Reasonable max range for colonization
          alreadyTargeted,
          preferredClasses = @[]  # No class preference in Act 1
        )

        if bestTarget.isSome:
          order.orderType = FleetOrderType.Colonize
          order.targetSystem = bestTarget
          order.targetFleet = none(FleetId)
          # Mark as targeted to prevent other fleets from picking same system
          alreadyTargeted.incl(bestTarget.get())
          logInfo(LogCategory.lcAI, &"    → COLONIZE {bestTarget.get()} (Act 1: Act-aware selection)")
          result.add(order)
          continue
        else:
          logDebug(LogCategory.lcAI, &"    → No colonization targets found (map fully colonized?)")

      # Priority 1b: View World missions for unexamined systems (Act 1 intelligence gathering)
      # FIX: Exclude ETAC fleets (colonization-only, even with escorts)
      if hasCombatShips and not isETACFleet(fleet):
        # Check for unexamined systems (no intel report on file)
        var viewTarget: Option[SystemId] = none(SystemId)
        var minDist = 999
        let fromCoords = filtered.starMap.systems[fleet.location].coords

        for systemId, visSystem in filtered.visibleSystems:
          # Skip if we already have intelligence on this system
          if systemId in filtered.ownHouse.intelligence.colonyReports:
            continue

          # Only view systems we haven't visited yet
          let coords = filtered.starMap.systems[systemId].coords
          let dx = abs(coords.q - fromCoords.q)
          let dy = abs(coords.r - fromCoords.r)
          let dz = abs((coords.q + coords.r) - (fromCoords.q + fromCoords.r))
          let dist = (dx + dy + dz) div 2

          if dist < minDist and dist > 0:  # dist > 0 excludes current location
            minDist = dist
            viewTarget = some(systemId)

        if viewTarget.isSome:
          order.orderType = FleetOrderType.ViewWorld
          order.targetSystem = viewTarget
          order.targetFleet = none(FleetId)
          logInfo(LogCategory.lcAI, &"    → VIEW WORLD {viewTarget.get()} (Act 1: Intelligence gathering)")
          result.add(order)
          continue

      # Priority 1c: Combat ships explore aggressively
      # FIX: Exclude ETAC fleets (colonization-only, even with escorts)
      if hasCombatShips and not isETACFleet(fleet):
        # Build set of systems already targeted by our other fleets this turn
        # NOTE: Uses the alreadyTargeted set defined at line 490 (don't redeclare!)
        for existingOrder in result:
          if existingOrder.targetSystem.isSome:
            alreadyTargeted.incl(existingOrder.targetSystem.get())

        # Find closest unexplored system NOT already targeted (fan-out)
        var reconTarget: Option[SystemId] = none(SystemId)
        var minDist = 999
        let fromCoords = filtered.starMap.systems[fleet.location].coords

        for systemId, visSystem in filtered.visibleSystems:
          if systemId == fleet.location or systemId in alreadyTargeted:
            continue

          # Target systems that need reconnaissance (adjacent/unscouted/stale)
          if needsReconnaissance(filtered, systemId):
            let coords = filtered.starMap.systems[systemId].coords
            let dx = abs(coords.q - fromCoords.q)
            let dy = abs(coords.r - fromCoords.r)
            let dz = abs((coords.q + coords.r) - (fromCoords.q + fromCoords.r))
            let dist = (dx + dy + dz) div 2
            if dist < minDist:
              minDist = dist
              reconTarget = some(systemId)

        if reconTarget.isSome:
          order.orderType = FleetOrderType.Move
          order.targetSystem = reconTarget
          order.targetFleet = none(FleetId)
          logInfo(LogCategory.lcAI, &"    → EXPLORE {reconTarget.get()} (Act 1: Systematic reconnaissance)")
          result.add(order)

          # Track reconnaissance mission for intelligence update
          controller.pendingIntelUpdates.add(ReconUpdate(
            systemId: reconTarget.get(),
            fleetId: fleet.id,
            scheduledTurn: filtered.turn + 1
          ))
          logDebug(LogCategory.lcAI,
                   &"{controller.houseId} Fleet {fleet.id}: Scheduled intel update for system " &
                   &"{reconTarget.get()} after reconnaissance")

          continue

        # Fallback: Random adjacent exploration
        if fleet.location in filtered.starMap.adjacency:
          let adjacentSystems = filtered.starMap.adjacency[fleet.location]
          if adjacentSystems.len > 0:
            let targetSystem = adjacentSystems[rng.rand(adjacentSystems.len - 1)]
            order.orderType = FleetOrderType.Move
            order.targetSystem = some(targetSystem)
            order.targetFleet = none(FleetId)
            logInfo(LogCategory.lcAI, &"    → EXPLORE {targetSystem} (Act 1: Random adjacent)")
            result.add(order)

            # Track reconnaissance mission for intelligence update
            controller.pendingIntelUpdates.add(ReconUpdate(
              systemId: targetSystem,
              fleetId: fleet.id,
              scheduledTurn: filtered.turn + 1
            ))

            continue

      # Default: Hold position
      order.orderType = FleetOrderType.Hold
      order.targetSystem = some(fleet.location)
      order.targetFleet = none(FleetId)
      logDebug(LogCategory.lcAI, &"    → HOLD at {fleet.location} (Act 1: No valid targets)")
      result.add(order)

    of GameAct.Act2_RisingTensions:
      # ========================================================================
      # ACT 2: RISING TENSIONS (Turns 8-15)
      # Priority: Military Buildup >> Defense >> Opportunistic Colonization
      # ========================================================================

      # Priority 1: Coordinated operations (invasions)
      var inOperation = false
      for op in controller.operations:
        if fleet.id in op.requiredFleets:
          inOperation = true
          if fleet.location != op.assemblyPoint:
            order.orderType = FleetOrderType.Rendezvous
            order.targetSystem = some(op.assemblyPoint)
            logInfo(LogCategory.lcAI, &"    → RENDEZVOUS at {op.assemblyPoint} (Act 2: Operation assembly)")
          elif shouldExecuteOperation(controller, op, filtered.turn):
            case op.operationType
            of OperationType.Invasion:
              order.orderType = FleetOrderType.Invade
            of OperationType.Raid:
              order.orderType = FleetOrderType.Blitz
            of OperationType.Blockade:
              order.orderType = FleetOrderType.BlockadePlanet
            of OperationType.Defense:
              order.orderType = FleetOrderType.Patrol
            order.targetSystem = some(op.targetSystem)
            logInfo(LogCategory.lcAI, &"    → EXECUTE {op.operationType} on {op.targetSystem} (Act 2: Operation)")
          else:
            order.orderType = FleetOrderType.Hold
            order.targetSystem = some(fleet.location)
            logDebug(LogCategory.lcAI, &"    → HOLD at assembly point (Act 2: Waiting for operation)")
          order.targetFleet = none(FleetId)
          result.add(order)
          break

      if inOperation:
        continue

      # Priority 2: Strategic reserve threat response
      let threats = respondToThreats(controller, filtered)
      var respondingToThreat = false
      for threat in threats:
        if threat.reserveFleet == fleet.id:
          order.orderType = FleetOrderType.Move
          order.targetSystem = some(threat.threatSystem)
          order.targetFleet = none(FleetId)
          logInfo(LogCategory.lcAI, &"    → RESPOND to threat at {threat.threatSystem} (Act 2: Reserve activation)")
          result.add(order)
          respondingToThreat = true
          break

      if respondingToThreat:
        continue

      # Priority 3: Pick up unassigned squadrons (ONE fleet only)
      if isSystemColonized(filtered, fleet.location):
        let colonyOpt = getColony(filtered, fleet.location)
        if colonyOpt.isSome:
          let colony = colonyOpt.get()
          if colony.owner == controller.houseId and colony.unassignedSquadrons.len > 0:
            # Check if another fleet is already assigned to pickup duty
            var hasPickupFleet = false
            for existingOrder in result:
              if existingOrder.orderType == FleetOrderType.Hold and
                 existingOrder.targetSystem == some(fleet.location):
                hasPickupFleet = true
                break

            if not hasPickupFleet:
              order.orderType = FleetOrderType.Hold
              order.targetSystem = some(fleet.location)
              order.targetFleet = none(FleetId)
              logInfo(LogCategory.lcAI, &"    → HOLD to pickup {colony.unassignedSquadrons.len} squadrons (Act 2: Reinforcement)")
              result.add(order)
              continue

      # Priority 4: Opportunistic colonization with Act-aware scoring (ETACs only)
      # SKIP if fleet has active AutoColonize standing order (let standing order handle it)
      let hasActiveAutoColonize = fleet.id in standingOrders and
                                   standingOrders[fleet.id].orderType == StandingOrderType.AutoColonize and
                                   standingOrders[fleet.id].enabled and
                                   not standingOrders[fleet.id].suspended
      if hasETAC and not hasActiveAutoColonize:
        # Use engine function for Act-aware colonization target selection
        # Act 2: Still prioritizes distance but considers quality more than Act 1
        let bestTarget = findColonizationTargetFiltered(
          filtered, fleet, fleet.location,
          maxRange = 20,  # Reasonable max range for colonization
          alreadyTargeted,
          preferredClasses = @[]  # No specific class preference
        )

        if bestTarget.isSome:
          order.orderType = FleetOrderType.Colonize
          order.targetSystem = bestTarget
          order.targetFleet = none(FleetId)
          # Mark as targeted to prevent other fleets from picking same system
          alreadyTargeted.incl(bestTarget.get())
          logInfo(LogCategory.lcAI, &"    → COLONIZE {bestTarget.get()} (Act 2: Act-aware selection)")
          result.add(order)
          continue

      # Priority 5: Exploration/patrol
      # FIX: Exclude ETAC fleets (colonization-only, even with escorts)
      if hasCombatShips and not isETACFleet(fleet):
        var reconTarget: Option[SystemId] = none(SystemId)
        var minDist = 999
        let fromCoords = filtered.starMap.systems[fleet.location].coords

        for systemId, visSystem in filtered.visibleSystems:
          if systemId == fleet.location:
            continue

          if needsReconnaissance(filtered, systemId):
            let coords = filtered.starMap.systems[systemId].coords
            let dx = abs(coords.q - fromCoords.q)
            let dy = abs(coords.r - fromCoords.r)
            let dz = abs((coords.q + coords.r) - (fromCoords.q + fromCoords.r))
            let dist = (dx + dy + dz) div 2
            if dist < minDist:
              minDist = dist
              reconTarget = some(systemId)

        if reconTarget.isSome:
          order.orderType = FleetOrderType.Move
          order.targetSystem = reconTarget
          order.targetFleet = none(FleetId)
          logInfo(LogCategory.lcAI, &"    → PATROL/EXPLORE {reconTarget.get()} (Act 2: Intel gathering)")
          result.add(order)

          # Track reconnaissance mission for intelligence update
          controller.pendingIntelUpdates.add(ReconUpdate(
            systemId: reconTarget.get(),
            fleetId: fleet.id,
            scheduledTurn: filtered.turn + 1
          ))

          continue

      # Default: Hold position
      order.orderType = FleetOrderType.Hold
      order.targetSystem = some(fleet.location)
      order.targetFleet = none(FleetId)
      logDebug(LogCategory.lcAI, &"    → HOLD at {fleet.location} (Act 2: No priority targets)")
      result.add(order)

    of GameAct.Act3_TotalWar, GameAct.Act4_Endgame:
      # ========================================================================
      # ACT 3-4: TOTAL WAR / ENDGAME (Turns 16-30)
      # Priority: Invasions >> Defense >> Combat (NO colonization)
      # ========================================================================

      # Priority 1: Coordinated operations
      var inOperation = false
      for op in controller.operations:
        if fleet.id in op.requiredFleets:
          inOperation = true
          if fleet.location != op.assemblyPoint:
            order.orderType = FleetOrderType.Rendezvous
            order.targetSystem = some(op.assemblyPoint)
            logInfo(LogCategory.lcAI, &"    → RENDEZVOUS at {op.assemblyPoint} (Act 3+: War operation)")
          elif shouldExecuteOperation(controller, op, filtered.turn):
            case op.operationType
            of OperationType.Invasion:
              order.orderType = FleetOrderType.Invade
            of OperationType.Raid:
              order.orderType = FleetOrderType.Blitz
            of OperationType.Blockade:
              order.orderType = FleetOrderType.BlockadePlanet
            of OperationType.Defense:
              order.orderType = FleetOrderType.Patrol
            order.targetSystem = some(op.targetSystem)
            logInfo(LogCategory.lcAI, &"    → EXECUTE {op.operationType} on {op.targetSystem} (Act 3+: Total war)")
          else:
            order.orderType = FleetOrderType.Hold
            order.targetSystem = some(fleet.location)
            logDebug(LogCategory.lcAI, &"    → HOLD at assembly (Act 3+: Waiting)")
          order.targetFleet = none(FleetId)
          result.add(order)
          break

      if inOperation:
        continue

      # Priority 2: Strategic reserve threat response
      let threats = respondToThreats(controller, filtered)
      var respondingToThreat = false
      for threat in threats:
        if threat.reserveFleet == fleet.id:
          order.orderType = FleetOrderType.Move
          order.targetSystem = some(threat.threatSystem)
          order.targetFleet = none(FleetId)
          logInfo(LogCategory.lcAI, &"    → RESPOND to threat at {threat.threatSystem} (Act 3+: Defense)")
          result.add(order)
          respondingToThreat = true
          break

      if respondingToThreat:
        continue

      # Priority 3: Pick up reinforcements
      if isSystemColonized(filtered, fleet.location):
        let colonyOpt = getColony(filtered, fleet.location)
        if colonyOpt.isSome:
          let colony = colonyOpt.get()
          if colony.owner == controller.houseId and colony.unassignedSquadrons.len > 0:
            var hasPickupFleet = false
            for existingOrder in result:
              if existingOrder.orderType == FleetOrderType.Hold and
                 existingOrder.targetSystem == some(fleet.location):
                hasPickupFleet = true
                break

            if not hasPickupFleet:
              order.orderType = FleetOrderType.Hold
              order.targetSystem = some(fleet.location)
              order.targetFleet = none(FleetId)
              logInfo(LogCategory.lcAI, &"    → HOLD for reinforcements (Act 3+: {colony.unassignedSquadrons.len} squadrons)")
              result.add(order)
              continue

      # Priority 4: Aggressive patrol/reconnaissance
      # FIX: Exclude ETAC fleets (colonization-only, even with escorts)
      if hasCombatShips and not isETACFleet(fleet):
        var reconTarget: Option[SystemId] = none(SystemId)
        var minDist = 999
        let fromCoords = filtered.starMap.systems[fleet.location].coords

        for systemId, visSystem in filtered.visibleSystems:
          if systemId == fleet.location:
            continue

          if needsReconnaissance(filtered, systemId):
            let coords = filtered.starMap.systems[systemId].coords
            let dx = abs(coords.q - fromCoords.q)
            let dy = abs(coords.r - fromCoords.r)
            let dz = abs((coords.q + coords.r) - (fromCoords.q + fromCoords.r))
            let dist = (dx + dy + dz) div 2
            if dist < minDist:
              minDist = dist
              reconTarget = some(systemId)

        if reconTarget.isSome:
          order.orderType = FleetOrderType.Patrol
          order.targetSystem = reconTarget
          order.targetFleet = none(FleetId)
          logInfo(LogCategory.lcAI, &"    → PATROL {reconTarget.get()} (Act 3+: Aggressive recon)")
          result.add(order)

          # Track reconnaissance mission for intelligence update
          controller.pendingIntelUpdates.add(ReconUpdate(
            systemId: reconTarget.get(),
            fleetId: fleet.id,
            scheduledTurn: filtered.turn + 1
          ))

          continue

      # Default: Hold position
      order.orderType = FleetOrderType.Hold
      order.targetSystem = some(fleet.location)
      order.targetFleet = none(FleetId)
      logDebug(LogCategory.lcAI, &"    → HOLD at {fleet.location} (Act 3+: Defensive posture)")
      result.add(order)

proc planCoordinatedInvasion*(controller: var AIController, filtered: FilteredGameState,
                                target: SystemId, turn: int) =
  ## Plan multi-fleet invasion of a high-value target
  ## NOW WITH TRAVEL TIME AWARENESS: Selects fleets by ETA and schedules execution
  var assemblyPoint: Option[SystemId] = none(SystemId)
  var minDist = 999

  let targetCoords = filtered.starMap.systems[target].coords

  for colony in filtered.ownColonies:
    if colony.owner != controller.houseId:
      continue

    let coords = filtered.starMap.systems[colony.systemId].coords
    let dx = abs(coords.q - targetCoords.q)
    let dy = abs(coords.r - targetCoords.r)
    let dz = abs((coords.q + coords.r) - (targetCoords.q + targetCoords.r))
    let dist = (dx + dy + dz) div 2

    if dist < minDist and dist > 0:
      minDist = dist
      assemblyPoint = some(colony.systemId)

  if assemblyPoint.isNone:
    return

  # Collect combat fleets with their ETAs to assembly point
  type FleetWithETA = tuple[fleetId: FleetId, fleet: Fleet, eta: int]
  var fleetsWithETA: seq[FleetWithETA] = @[]
  var scoutFleets: seq[FleetId] = @[]

  for fleet in filtered.ownFleets:
    if fleet.owner == controller.houseId:
      # CRITICAL FIX: Never add ETACs to military operations (even mixed fleets)
      if isETACFleet(fleet):
        continue

      var inOperation = false
      for op in controller.operations:
        if fleet.id in op.requiredFleets:
          inOperation = true
          break

      if not inOperation:
        if fleet.combatStrength() > 0:
          # Calculate ETA to assembly point
          let etaOpt = calculateETA(filtered.starMap, fleet.location, assemblyPoint.get(), fleet)
          if etaOpt.isSome:
            fleetsWithETA.add((fleet.id, fleet, etaOpt.get()))
        elif fleet.squadrons.len == 1 and isSingleScoutSquadron(fleet.squadrons[0]):
          if scoutFleets.len < 4:
            scoutFleets.add(fleet.id)

  # Sort fleets by ETA (fastest first)
  fleetsWithETA.sort(proc(a, b: FleetWithETA): int = cmp(a.eta, b.eta))

  # Select up to 3 combat fleets, but only if max ETA is reasonable
  var selectedFleets: seq[FleetId] = @[]
  var maxETA = 0

  for i in 0..<min(3, fleetsWithETA.len):
    let fleetData = fleetsWithETA[i]
    if fleetData.eta <= globalRBAConfig.tactical.max_invasion_eta_turns:
      selectedFleets.add(fleetData.fleetId)
      maxETA = max(maxETA, fleetData.eta)

  if selectedFleets.len >= 2:
    selectedFleets.add(scoutFleets)

    # Calculate execution turn: when slowest fleet arrives + 1 turn buffer
    let executionTurn = turn + maxETA + 1

    logInfo(LogCategory.lcAI, &"{controller.houseId} planning invasion of {target}: " &
            &"{selectedFleets.len} fleets, assembly at {assemblyPoint.get()}, " &
            &"max ETA {maxETA} turns, executing turn {executionTurn}")

    controller.planCoordinatedOperation(
      filtered,
      OperationType.Invasion,
      target,
      selectedFleets,
      assemblyPoint.get(),
      turn
    )
