## Tactical Operations Module for EC4X Rule-Based AI
##
## Handles fleet coordination, combat assessment, and tactical planning
## Respects fog-of-war - uses only visible tactical information

import std/[tables, options, algorithm, sequtils, strformat, random]
import ../common/types
import ../../engine/[gamestate, fog_of_war, fleet, squadron, starmap, logger, orders]
import ../../engine/diplomacy/types as dip_types
import ../../engine/intelligence/types as intel_types
import ../../common/types/[core, planets]
import ./controller_types
import ./intelligence  # For isSystemColonized, getColony
import ./diplomacy  # For getOwnedFleets

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

import ./controller_types

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
  result = @[]
  for colony in filtered.ownColonies:
    if colony.owner == controller.houseId:
      if colony.production >= 30:
        result.add(colony.systemId)
      elif colony.resources in [ResourceRating.Rich, ResourceRating.VeryRich, ResourceRating.Abundant]:
        result.add(colony.systemId)

proc assignStrategicReserve*(controller: var AIController, fleetId: FleetId,
                              assignedSystem: Option[SystemId], radius: int = 3) =
  ## Designate a fleet as strategic reserve
  let reserve = StrategicReserve(
    fleetId: fleetId,
    assignedTo: assignedSystem,
    responseRadius: radius
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

      if dist < minDist and dist <= 3:
        minDist = dist
        bestFleet = some(fleet.id)

    if bestFleet.isSome:
      controller.assignStrategicReserve(bestFleet.get(), some(systemId), 3)

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

    for fleet in filtered.ownFleets:
      if fleet.owner == controller.houseId or fleet.combatStrength() == 0:
        continue

      let fleetCoords = filtered.starMap.systems[fleet.location].coords
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
          let etaOpt = calculateETA(filtered.starMap, reserveFleet.location, fleet.location, reserveFleet)
          if etaOpt.isSome:
            let threat: tuple[location: SystemId, distance: int, eta: int] = (fleet.location, dist, etaOpt.get())
            nearestThreat = some(threat)

    # Only dispatch if reserve can respond in reasonable time
    # Compare threat distance to protected system vs reserve ETA
    # If threat is 2 jumps away and reserve needs 5 turns, too late
    if nearestThreat.isSome:
      let threat = nearestThreat.get()
      const MAX_RESPONSE_ETA = 5  # Only respond if we can get there in 5 turns
      if threat.eta <= MAX_RESPONSE_ETA:
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

proc assessRelativeStrength*(controller: AIController, filtered: FilteredGameState, targetHouse: HouseId): float =
  ## Assess relative strength of a house (0.0 = weakest, 1.0 = strongest)
  if targetHouse notin filtered.housePrestige:
    return 0.5

  let targetPrestige = filtered.housePrestige[targetHouse]
  let myHouse = filtered.ownHouse

  var targetStrength = 0.0
  var myStrength = 0.0

  # Prestige weight: 50%
  targetStrength += targetPrestige.float * 0.5
  myStrength += myHouse.prestige.float * 0.5

  # Colony count weight: 30%
  var targetKnownColonies = 0
  let myColonies = filtered.ownColonies.len

  for systemId, colonyReport in myHouse.intelligence.colonyReports:
    if colonyReport.targetOwner == targetHouse:
      targetKnownColonies += 1

  targetStrength += targetKnownColonies.float * 20.0 * 0.3
  myStrength += myColonies.float * 20.0 * 0.3

  # Fleet strength weight: 20%
  var myFleets = 0
  for fleet in filtered.ownFleets:
    myFleets += fleet.combatStrength()

  var targetEstimatedFleetCount = 0
  for systemId, systemReport in myHouse.intelligence.systemReports:
    for detectedFleet in systemReport.detectedFleets:
      if detectedFleet.owner == targetHouse:
        targetEstimatedFleetCount += 1

  let estimatedFleetStrength = targetEstimatedFleetCount * 100
  targetStrength += estimatedFleetStrength.float * 0.2
  myStrength += myFleets.float * 0.2

  if myStrength == 0:
    return 1.0
  return targetStrength / (targetStrength + myStrength)

proc identifyVulnerableTargets*(controller: var AIController, filtered: FilteredGameState): seq[tuple[systemId: SystemId, owner: HouseId, relativeStrength: float]] =
  ## Identify colonies owned by weaker players
  ## USES INTELLIGENCE REPORTS: Includes colonies from intelligence database, not just visible
  result = @[]

  # Track which systems we've already added to avoid duplicates
  var addedSystems: seq[SystemId] = @[]

  # Add currently visible colonies
  for visCol in filtered.visibleColonies:
    if visCol.owner == controller.houseId:
      continue

    let strength = controller.assessRelativeStrength(filtered, visCol.owner)
    result.add((visCol.systemId, visCol.owner, strength))
    addedSystems.add(visCol.systemId)

  # Add colonies from intelligence database (even if not currently visible)
  for systemId, report in filtered.ownHouse.intelligence.colonyReports:
    if report.targetOwner == controller.houseId:
      continue

    # Skip if already added from visible colonies
    if systemId in addedSystems:
      continue

    let strength = controller.assessRelativeStrength(filtered, report.targetOwner)
    result.add((systemId, report.targetOwner, strength))
    addedSystems.add(systemId)

  result.sort(proc(a, b: auto): int = cmp(a.relativeStrength, b.relativeStrength))

proc identifyInvasionOpportunities*(controller: var AIController, filtered: FilteredGameState): seq[SystemId] =
  ## Identify enemy colonies that warrant coordinated invasion
  ## USES INTELLIGENCE REPORTS: Combines current visibility with intelligence database
  ## This allows invasion planning even when scouts aren't actively watching targets
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

proc generateFleetOrders*(controller: var AIController, filtered: FilteredGameState, rng: var Rand): seq[FleetOrder] =
  ## Generate fleet orders for all owned fleets
  result = @[]

  let myFleets = getOwnedFleets(filtered, controller.houseId)

  # Update operation status
  updateOperationStatus(controller, filtered)
  removeCompletedOperations(controller, filtered.turn)

  for fleet in myFleets:
    var order: FleetOrder
    order.fleetId = fleet.id
    order.priority = 1

    # Priority 1: Hold at colony to pick up unassigned squadrons
    if isSystemColonized(filtered, fleet.location):
      let colonyOpt = getColony(filtered, fleet.location)
      if colonyOpt.isSome:
        let colony = colonyOpt.get()
        if colony.owner == controller.houseId and colony.unassignedSquadrons.len > 0:
          order.orderType = FleetOrderType.Hold
          order.targetSystem = some(fleet.location)
          order.targetFleet = none(FleetId)
          result.add(order)
          continue

    # Priority 2: Coordinated operations
    var inOperation = false
    for op in controller.operations:
      if fleet.id in op.requiredFleets:
        inOperation = true
        if fleet.location != op.assemblyPoint:
          # Move to assembly point
          order.orderType = FleetOrderType.Rendezvous
          order.targetSystem = some(op.assemblyPoint)
          order.targetFleet = none(FleetId)
        elif shouldExecuteOperation(controller, op, filtered.turn):
          # Execute operation
          case op.operationType
          of OperationType.Invasion:
            order.orderType = FleetOrderType.Invade
            order.targetSystem = some(op.targetSystem)
          of OperationType.Raid:
            order.orderType = FleetOrderType.Blitz
            order.targetSystem = some(op.targetSystem)
          of OperationType.Blockade:
            order.orderType = FleetOrderType.BlockadePlanet
            order.targetSystem = some(op.targetSystem)
          of OperationType.Defense:
            order.orderType = FleetOrderType.Patrol
            order.targetSystem = some(op.targetSystem)
          order.targetFleet = none(FleetId)
        else:
          # Wait at assembly point
          order.orderType = FleetOrderType.Hold
          order.targetSystem = some(fleet.location)
          order.targetFleet = none(FleetId)
        result.add(order)
        break

    if inOperation:
      continue

    # Priority 3: Strategic reserve threat response
    let threats = respondToThreats(controller, filtered)
    var respondingToThreat = false
    for threat in threats:
      if threat.reserveFleet == fleet.id:
        order.orderType = FleetOrderType.Move
        order.targetSystem = some(threat.threatSystem)
        order.targetFleet = none(FleetId)
        result.add(order)
        respondingToThreat = true
        break

    if respondingToThreat:
      continue

    # Default: Hold position
    order.orderType = FleetOrderType.Hold
    order.targetSystem = some(fleet.location)
    order.targetFleet = none(FleetId)
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
  const MAX_INVASION_ETA = 8  # Don't plan invasions > 8 turns away

  for i in 0..<min(3, fleetsWithETA.len):
    let fleetData = fleetsWithETA[i]
    if fleetData.eta <= MAX_INVASION_ETA:
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
