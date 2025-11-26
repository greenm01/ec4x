## Tactical Operations Module for EC4X Rule-Based AI
##
## Handles fleet coordination, combat assessment, and tactical planning
## Respects fog-of-war - uses only visible tactical information

import std/[tables, options, algorithm, sequtils, strformat]
import ../common/types
import ../../engine/[gamestate, fog_of_war, fleet, squadron, starmap, logger]
import ../../engine/diplomacy/types as dip_types
import ../../common/types/[core, planets]
import ./controller_types
import ./intelligence  # For isSystemColonized

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
  result = @[]

  for reserve in controller.reserves:
    if reserve.assignedTo.isNone:
      continue

    let protectedSystem = reserve.assignedTo.get()
    let protectedCoords = filtered.starMap.systems[protectedSystem].coords

    for fleet in filtered.ownFleets:
      if fleet.owner == controller.houseId or fleet.combatStrength() == 0:
        continue

      let fleetCoords = filtered.starMap.systems[fleet.location].coords
      let dx = abs(fleetCoords.q - protectedCoords.q)
      let dy = abs(fleetCoords.r - protectedCoords.r)
      let dz = abs((fleetCoords.q + fleetCoords.r) - (protectedCoords.q + protectedCoords.r))
      let dist = (dx + dy + dz) div 2

      if dist <= reserve.responseRadius:
        result.add((reserveFleet: reserve.fleetId, threatSystem: fleet.location))
        break

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
    state.houses[controller.houseId].fallbackRoutes = controller.fallbackRoutes

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
  result = @[]

  for visCol in filtered.visibleColonies:
    if visCol.owner == controller.houseId:
      continue

    let strength = controller.assessRelativeStrength(filtered, visCol.owner)
    result.add((visCol.systemId, visCol.owner, strength))

  result.sort(proc(a, b: auto): int = cmp(a.relativeStrength, b.relativeStrength))

proc identifyInvasionOpportunities*(controller: var AIController, filtered: FilteredGameState): seq[SystemId] =
  ## Identify enemy colonies that warrant coordinated invasion
  ## RESPECTS FOG-OF-WAR: Uses visibleColonies to find targets
  result = @[]

  let vulnerableTargets = controller.identifyVulnerableTargets(filtered)
  logDebug(LogCategory.lcAI, &"{controller.houseId} found {vulnerableTargets.len} vulnerable targets, {filtered.visibleColonies.len} visible colonies")

  # Convert vulnerable targets to a set for O(1) lookup
  var vulnerableSet: seq[SystemId] = @[]
  for target in vulnerableTargets:
    vulnerableSet.add(target.systemId)

  # Check visible enemy colonies for invasion opportunities
  var checkedCount = 0
  var skippedNotVulnerable = 0
  var skippedDefense = 0
  var skippedStrength = 0

  for visCol in filtered.visibleColonies:
    if visCol.owner == controller.houseId:
      continue

    checkedCount += 1

    # Skip if not in vulnerable targets list
    if visCol.systemId notin vulnerableSet:
      skippedNotVulnerable += 1
      continue

    # Estimate defense strength from fog-of-war intel
    var defenseStrength = 0
    if visCol.starbaseLevel.isSome and visCol.starbaseLevel.get() > 0:
      defenseStrength += 100 * visCol.starbaseLevel.get()

    # Check for defending fleets (visible through fog-of-war)
    for fleet in filtered.visibleFleets:
      if fleet.owner == visCol.owner and fleet.location == visCol.systemId:
        if fleet.estimatedShipCount.isSome:
          defenseStrength += fleet.estimatedShipCount.get() * 10

    # Check if colony is valuable (use estimated fields for fog-of-war)
    let production = if visCol.production.isSome: visCol.production.get()
                     elif visCol.estimatedIndustry.isSome: visCol.estimatedIndustry.get()
                     else: 0

    let resources = if visCol.resources.isSome: visCol.resources.get()
                    else: ResourceRating.Poor

    let isValuable = production >= 50 or
                     resources in [ResourceRating.Rich, ResourceRating.VeryRich]

    # Find the target in vulnerable list to get relative strength
    var relativeStrength = 0.5  # Default if not found
    for target in vulnerableTargets:
      if target.systemId == visCol.systemId:
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

    result.add(visCol.systemId)

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

proc planCoordinatedInvasion*(controller: var AIController, filtered: FilteredGameState,
                                target: SystemId, turn: int) =
  ## Plan multi-fleet invasion of a high-value target
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

  var selectedFleets: seq[FleetId] = @[]
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
          selectedFleets.add(fleet.id)
          if selectedFleets.len >= 3:
            break
        elif fleet.squadrons.len == 1 and isSingleScoutSquadron(fleet.squadrons[0]):
          if scoutFleets.len < 4:
            scoutFleets.add(fleet.id)

  if selectedFleets.len >= 2:
    selectedFleets.add(scoutFleets)
    controller.planCoordinatedOperation(
      filtered,
      OperationType.Invasion,
      target,
      selectedFleets,
      assemblyPoint.get(),
      turn
    )
