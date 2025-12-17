## RBA Standing Orders Manager
##
## Intelligent assignment and management of standing orders for AI fleets.
## Integrates QoL standing orders system with RBA strategic decision-making.
##
## Philosophy:
## - Use standing orders to reduce micromanagement and ensure consistent fleet behavior
## - Assign standing orders based on fleet role, personality, and strategic context
## - Let standing orders handle routine tasks while explicit orders handle critical operations

import std/[tables, options, strformat, sets, algorithm]
import ../common/types
import ../../engine/[gamestate, fleet, logger, fog_of_war, standing_orders, starmap]
import ../../engine/order_types
import ../../common/types/[core, planets]
import ./controller_types
import ./config  # RBA configuration for colonization parameters

export StandingOrderType, StandingOrder, StandingOrderParams

# Forward declarations
proc findBestDrydockForRepair*(filtered: FilteredGameState,
                                fleetLocation: SystemId): Option[SystemId]

# =============================================================================
# Fleet Role Assessment
# =============================================================================

type
  FleetRole* {.pure.} = enum
    ## Strategic role assessment for fleet
    Colonizer       # ETAC fleet for expansion
    Scout           # Intel gathering and exploration
    Defender        # Homeworld/colony defense
    Raider          # Hit-and-run offensive
    Invasion        # Coordinated invasion force
    Reserve         # Mothballed or in reserve
    Damaged         # Needs repair
    Unknown         # Cannot determine role

proc assessFleetRole*(fleet: Fleet, filtered: FilteredGameState,
                     personality: AIPersonality): FleetRole =
  ## Assess fleet's current strategic role based on composition and context

  # Count ship types
  var scoutCount = 0
  var etacCount = 0
  var militaryCount = 0
  var crippledCount = 0
  var totalShips = 0

  for squadron in fleet.squadrons:
    totalShips += 1
    if squadron.flagship.isCrippled:
      crippledCount += 1

    case squadron.squadronType
    of SquadronType.Intel:
      scoutCount += 1
    of SquadronType.Expansion:
      etacCount += 1
    of SquadronType.Auxiliary:
      discard  # Transports handled separately
    of SquadronType.Combat:
      militaryCount += 1
    of SquadronType.Fighter:
      discard  # Fighters stay at colonies

    # Count wingmen
    for ship in squadron.ships:
      totalShips += 1
      if ship.isCrippled:
        crippledCount += 1

  # Count spacelift ships (ETACs are usually in spaceLiftShips, not squadrons)
  for spaceLift in fleet.spaceLiftShips:
    totalShips += 1
    case spaceLift.shipClass
    of ShipClass.ETAC:
      etacCount += 1
    of ShipClass.TroopTransport:
      discard  # Transports handled separately
    else:
      discard

  # Calculate damage percentage
  let damagePercent = if totalShips > 0:
                        crippledCount.float / totalShips.float
                      else: 0.0

  # Role assessment
  if damagePercent > 0.3:
    # Fleet is significantly damaged
    return FleetRole.Damaged

  if etacCount > 0:
    # Has colonization capability
    return FleetRole.Colonizer

  if scoutCount > 0 and militaryCount == 0:
    # Pure scout fleet
    return FleetRole.Scout

  if militaryCount > 0:
    # Has military ships - assess offensive vs defensive
    if personality.aggression > 0.6:
      return FleetRole.Raider
    else:
      return FleetRole.Defender

  return FleetRole.Unknown

# =============================================================================
# Standing Order Assignment
# =============================================================================

proc createAutoRepairOrder*(fleet: Fleet, filtered: FilteredGameState,
                           damageThreshold: float = 0.3): StandingOrder =
  ## Create AutoRepair standing order for damaged fleet.
  ## Finds the best available Drydock for repair.

  let bestDrydockSystem = findBestDrydockForRepair(filtered, fleet.location)
  let targetSystem = if bestDrydockSystem.isSome:
                       bestDrydockSystem.get
                     else:
                       0.SystemId

  logDebug(LogCategory.lcAI,
           &"{fleet.id} Assigning AutoRepair standing order " &
           &"(threshold {(damageThreshold * 100).int}%, target {targetSystem})")

  result = StandingOrder(
    fleetId: fleet.id,
    orderType: StandingOrderType.AutoRepair,
    params: StandingOrderParams(
      orderType: StandingOrderType.AutoRepair,
      repairDamageThreshold: damageThreshold,
      targetShipyard: bestDrydockSystem # Now dynamic
    ),
    roe: 3,  # Cautious ROE - avoid combat while damaged
    createdTurn: 0,  # Will be set by caller
    lastActivatedTurn: 0,
    activationCount: 0,
    suspended: false
  )

proc createDefendSystemOrder*(fleet: Fleet, targetSystem: SystemId,
                              maxRange: int, roe: int): StandingOrder =
  ## Create DefendSystem standing order for defensive fleets
  ## Guards system and engages hostiles per ROE

  logDebug(LogCategory.lcAI,
           &"{fleet.id} Assigning DefendSystem standing order " &
           &"(system {targetSystem}, range {maxRange} jumps, ROE {roe})")

  result = StandingOrder(
    fleetId: fleet.id,
    orderType: StandingOrderType.DefendSystem,
    params: StandingOrderParams(
      orderType: StandingOrderType.DefendSystem,
      defendTargetSystem: targetSystem,
      defendMaxRange: maxRange
    ),
    roe: roe,
    createdTurn: 0,
    lastActivatedTurn: 0,
    activationCount: 0,
    suspended: false
  )

proc createPatrolRouteOrder*(fleet: Fleet, patrolSystems: seq[SystemId],
                             roe: int): StandingOrder =
  ## Create PatrolRoute standing order for border patrols
  ## Loops continuously through patrol path

  logDebug(LogCategory.lcAI,
           &"{fleet.id} Assigning PatrolRoute standing order " &
           &"({patrolSystems.len} systems, ROE {roe})")

  result = StandingOrder(
    fleetId: fleet.id,
    orderType: StandingOrderType.PatrolRoute,
    params: StandingOrderParams(
      orderType: StandingOrderType.PatrolRoute,
      patrolSystems: patrolSystems,
      patrolIndex: 0
    ),
    roe: roe,
    createdTurn: 0,
    lastActivatedTurn: 0,
    activationCount: 0,
    suspended: false
  )

# =============================================================================
# Colony Defense Assessment
# =============================================================================

type
  UndefendedColony = object
    systemId: SystemId
    priority: float  # Higher = more important to defend

proc identifyUndefendedColonies(filtered: FilteredGameState): seq[UndefendedColony] =
  ## Identify colonies without fleet defense and prioritize them
  ## Priority based on: distance from homeworld (farther = higher priority)
  result = @[]

  # Build set of systems with our fleets for quick lookup
  var systemsWithFleets = initHashSet[SystemId]()
  for fleet in filtered.ownFleets:
    systemsWithFleets.incl(fleet.location)

  # Identify undefended colonies
  for colony in filtered.ownColonies:
    let systemId = colony.systemId

    # Check if colony has defense (starbases or fleets)
    let hasStarbase = colony.starbases.len > 0
    let hasFleet = systemId in systemsWithFleets

    if not hasStarbase and not hasFleet:
      # Colony is undefended - calculate priority
      # For now, simple priority: all colonies equally important
      # Could enhance with: distance from homeworld, strategic value, threat level
      result.add(UndefendedColony(
        systemId: systemId,
        priority: 1.0  # All colonies equal priority for now
      ))

# =============================================================================
# Standing Order Query API (Gap 5 Integration)
# =============================================================================

type
  DefenseAssignment* = object
    ## Active defense standing order assignment
    fleetId*: FleetId
    targetSystem*: SystemId
    createdTurn*: int

proc getActiveDefenseOrders*(
  controller: AIController
): seq[DefenseAssignment] =
  ## Get all active DefendSystem standing orders with target systems
  ## Used by build requirements to track defense assignments
  result = @[]

  for fleetId, order in controller.standingOrders:
    if order.orderType == StandingOrderType.DefendSystem and
       not order.suspended:
      result.add(DefenseAssignment(
        fleetId: fleetId,
        targetSystem: order.params.defendTargetSystem,
        createdTurn: order.createdTurn
      ))

proc getUndefendedSystemsWithOrders*(
  controller: AIController,
  filtered: FilteredGameState
): seq[SystemId] =
  ## Get systems with DefendSystem orders but no actual defenders present
  ## Returns list of colony systems that have defense orders assigned
  ## but the fleet hasn't arrived yet (used for defense gap detection)
  result = @[]

  # Get all systems with active defense orders
  var systemsWithOrders = initHashSet[SystemId]()
  for assignment in getActiveDefenseOrders(controller):
    systemsWithOrders.incl(assignment.targetSystem)

  # Get systems with actual fleet presence
  var systemsWithFleets = initHashSet[SystemId]()
  for fleet in filtered.ownFleets:
    systemsWithFleets.incl(fleet.location)

  # Find systems that have orders but no fleets
  for systemId in systemsWithOrders:
    if systemId notin systemsWithFleets:
      result.add(systemId)

# =============================================================================
# Intelligent Standing Order Management
# =============================================================================

proc assignStandingOrders*(controller: var AIController,
                          filtered: FilteredGameState,
                          currentTurn: int): Table[FleetId, StandingOrder] =
  ## Assign standing orders to all fleets based on role and personality
  ## Returns table of fleet assignments
  ##
  ## Standing orders are PERSISTENT - only reassign when necessary to avoid
  ## fleets constantly changing targets before reaching destinations
  ##
  ## Comprehensive logging of all assignments for diagnostics

  result = initTable[FleetId, StandingOrder]()

  let p = controller.personality
  let homeworld = controller.homeworld

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Assigning standing orders for {filtered.ownFleets.len} fleets")

  # Get fallback system for AutoEvade (homeworld or nearest defended colony)
  let fallbackSystem = homeworld

  # Calculate ROE based on personality
  let baseROE = int(p.aggression * 10.0)  # 0-10 scale

  # Preferred planet classes for colonization (best to worst)
  # Per docs: Eden > Lush > Benign > Harsh > Hostile > Desolate > Extreme
  let preferredPlanetClasses = @[
    PlanetClass.Eden,
    PlanetClass.Lush,
    PlanetClass.Benign,
    PlanetClass.Harsh,
    PlanetClass.Hostile
  ]

  var assignedCount = 0
  var skippedCount = 0
  var preservedCount = 0

  # Check if colonization is complete (100%)
  let totalSystems = filtered.starMap.systems.len
  var totalColonized = 0
  for houseId, colonyCount in filtered.houseColonies:
    totalColonized += colonyCount
  let colonizationComplete = totalColonized >= totalSystems

  if colonizationComplete:
    logInfo(LogCategory.lcAI,
            &"{controller.houseId} Colonization complete ({totalColonized}/{totalSystems}) - " &
            &"ETACs will be salvaged by tactical module")

  # Identify undefended colonies for Defender fleet assignment
  var undefendedColonies = identifyUndefendedColonies(filtered)
  var coloniesNeedingDefense = undefendedColonies.len

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Colony defense status: {coloniesNeedingDefense} undefended of {filtered.ownColonies.len} total")

  # Build set of systems that still need defense for existing assignments
  var systemsNeedingDefense = initHashSet[SystemId]()
  for colony in undefendedColonies:
    systemsNeedingDefense.incl(colony.systemId)

  for fleet in filtered.ownFleets:
    # Check if this fleet has an existing standing order that's still valid
    if fleet.id in controller.standingOrders:
      let existingOrder = controller.standingOrders[fleet.id]

      # For DefendSystem orders, check if the target still needs defense
      if existingOrder.orderType == StandingOrderType.DefendSystem:
        let target = existingOrder.params.defendTargetSystem

        # If defending homeworld or a system that still needs defense, preserve the order
        if target == homeworld or target in systemsNeedingDefense:
          result[fleet.id] = existingOrder
          preservedCount += 1

          # If defending a colony that still needs defense, remove it from the undefended list
          if target != homeworld and target in systemsNeedingDefense:
            for i in 0..<undefendedColonies.len:
              if undefendedColonies[i].systemId == target:
                undefendedColonies.delete(i)
                break

          logDebug(LogCategory.lcAI,
                   &"{controller.houseId} Fleet {fleet.id}: Preserving DefendSystem order for {target}")
          continue

      # For other order types, preserve them (AutoRepair)
      elif existingOrder.orderType in {StandingOrderType.AutoRepair}:
        result[fleet.id] = existingOrder
        preservedCount += 1
        logDebug(LogCategory.lcAI,
                 &"{controller.houseId} Fleet {fleet.id}: Preserving {existingOrder.orderType} order")
        continue

    # No valid existing order - assess role and assign new order
    let role = assessFleetRole(fleet, filtered, p)

    logDebug(LogCategory.lcAI,
             &"{controller.houseId} Fleet {fleet.id}: Role={role}, " &
             &"Location={fleet.location}")

    # Assign standing order based on role
    case role
    of FleetRole.Damaged:
      # Damaged fleets automatically return to best available Drydock
      let order = createAutoRepairOrder(fleet, filtered, 0.3) # Pass filtered to find best drydock
      if order.params.targetShipyard.isSome: # Only assign if a repair target was found
        result[fleet.id] = order
        assignedCount += 1

        logInfo(LogCategory.lcAI,
                &"{controller.houseId} Fleet {fleet.id}: Assigned AutoRepair " &
                &"(damaged fleet → best drydock {order.params.targetShipyard.get()})")
      else:
        skippedCount += 1
        logDebug(LogCategory.lcAI,
                 &"{controller.houseId} Fleet {fleet.id}: Skipped AutoRepair " &
                 &"(no suitable drydock found)")

    of FleetRole.Colonizer:
      # ETAC fleets managed by ETAC manager - explicit colonization orders
      skippedCount += 1
      logDebug(LogCategory.lcAI,
              &"{controller.houseId} Fleet {fleet.id}: No standing order " &
              &"(colonizer role, ETAC manager control)")

    of FleetRole.Scout:
      # Scouts managed by tactical module - no standing orders
      # They need explicit orders for coordinated reconnaissance operations
      skippedCount += 1
      logDebug(LogCategory.lcAI,
               &"{controller.houseId} Fleet {fleet.id}: No standing order " &
               &"(scout role, tactical control)")

    of FleetRole.Defender:
      # Defensive fleets guard homeworld/colonies
      # Prioritize undefended colonies, then homeworld
      var targetSystem = homeworld
      var assignmentType = "homeworld"

      if undefendedColonies.len > 0:
        # Assign to highest-priority undefended colony
        let colony = undefendedColonies[0]
        targetSystem = colony.systemId
        assignmentType = "colony"
        undefendedColonies.delete(0)  # Remove assigned colony from list

      let order = createDefendSystemOrder(fleet, targetSystem, 3, baseROE)
      result[fleet.id] = order
      assignedCount += 1

      logInfo(LogCategory.lcAI,
              &"{controller.houseId} Fleet {fleet.id}: Assigned DefendSystem " &
              &"(defender, {assignmentType} {targetSystem}, range 3)")

    of FleetRole.Raider, FleetRole.Invasion:
      # Offensive fleets managed by tactical module - no standing orders
      # They need explicit orders for coordinated operations
      skippedCount += 1
      logDebug(LogCategory.lcAI,
               &"{controller.houseId} Fleet {fleet.id}: No standing order " &
               &"(offensive role {role}, tactical control)")

    of FleetRole.Reserve:
      # Reserve fleets - no standing orders (lifecycle managed by logistics)
      skippedCount += 1
      logDebug(LogCategory.lcAI,
               &"{controller.houseId} Fleet {fleet.id}: No standing order " &
               &"(reserve, logistics control)")

    of FleetRole.Unknown:
      # Unknown role - no standing order, wait for tactical assessment
      skippedCount += 1
      logDebug(LogCategory.lcAI,
               &"{controller.houseId} Fleet {fleet.id}: No standing order " &
               &"(unknown role)")

  logInfo(LogCategory.lcAI,
          &"{controller.houseId} Standing order assignment complete: " &
          &"{assignedCount} new, {preservedCount} preserved, {skippedCount} skipped " &
          &"(tactical/logistics control)")

# =============================================================================
# Standing Order Conversion to Fleet Orders
# =============================================================================

proc findBestDrydockForRepair*(filtered: FilteredGameState, fleetLocation: SystemId): Option[SystemId] =
  ## Find the best colony with an operational Drydock for a fleet needing repair.
  ## Considers available capacity and proximity.
  result = none(SystemId)
  var bestScore = -1.0 # Higher score is better

  for colony in filtered.ownColonies:
    let totalRepairDocks = colony.getTotalRepairDocks() # Includes all operational Drydocks
    if totalRepairDocks == 0:
      continue # No drydocks or all crippled

    var availableDocks = 0
    for drydock in colony.drydocks:
      if not drydock.isCrippled:
        availableDocks += (drydock.effectiveDocks - drydock.activeRepairs.len)
    
    if availableDocks <= 0:
      continue # No available slots

    # TODO: Calculate distance score (closer is better)
    # Systems don't have .position field (hex-based map, not coordinates)
    # Need to implement hex pathfinding distance calculation
    let distance = 1.0  # Placeholder

    # Simple scoring: prefer more available docks, penalize distance
    # Example: score = (availableDocks * 10.0) - distance
    # Higher available docks is better, lower distance is better
    
    # For now, a simpler scoring: prefer more available docks strongly, then closer
    var currentScore = float(availableDocks) * 100.0 # High weight for available docks
    if distance > 0:
      currentScore -= distance # Penalize distance

    if currentScore > bestScore:
      bestScore = currentScore
      result = some(colony.systemId)
      
  return result

proc convertStandingOrderToFleetOrder*(standingOrder: StandingOrder,
                                       fleet: Fleet,
                                       filtered: FilteredGameState,
                                       alreadyTargeted: HashSet[SystemId]): Option[FleetOrder] =
  ## Convert standing order to executable FleetOrder
  ## Returns fleet order if conversion successful, none if order cannot execute
  ## alreadyTargeted: Systems already targeted by other fleets (for duplicate prevention)

  case standingOrder.orderType
  of StandingOrderType.AutoRepair:
    let targetShipyard = standingOrder.params.targetShipyard # This is now set by createAutoRepairOrder

    if targetShipyard.isSome:
      logDebug(LogCategory.lcAI,
               &"{fleet.id} AutoRepair: Moving to drydock at {targetShipyard.get}")

      return some(FleetOrder(
        fleetId: fleet.id,
        orderType: FleetOrderType.Move,
        targetSystem: targetShipyard,
        targetFleet: none(FleetId),
        priority: 50
      ))
    else:
      logWarn(LogCategory.lcAI,
              &"{fleet.id} AutoRepair: No specific repair target, holding position")
      return none(FleetOrder)

  of StandingOrderType.DefendSystem:
    # Patrol assigned system or move to it
    let targetSystem = standingOrder.params.defendTargetSystem

    # CRITICAL: Validate target system exists
    if targetSystem == SystemId(0):
      logError(LogCategory.lcAI,
               &"[RBA CONVERSION] {fleet.id} DefendSystem: BUG - defendTargetSystem is SystemId(0)!")
      return none(FleetOrder)

    # Check if system still exists in visible systems
    if targetSystem notin filtered.visibleSystems:
      logWarn(LogCategory.lcAI,
              &"[RBA CONVERSION] {fleet.id} DefendSystem: Target system {targetSystem} not visible, holding")
      return none(FleetOrder)

    if fleet.location == targetSystem:
      logDebug(LogCategory.lcAI,
               &"{fleet.id} DefendSystem: Patrolling {targetSystem}")

      return some(FleetOrder(
        fleetId: fleet.id,
        orderType: FleetOrderType.Patrol,
        targetSystem: some(targetSystem),
        targetFleet: none(FleetId),
        priority: 40
      ))
    else:
      logDebug(LogCategory.lcAI,
               &"{fleet.id} DefendSystem: Moving to {targetSystem}")

      return some(FleetOrder(
        fleetId: fleet.id,
        orderType: FleetOrderType.Move,
        targetSystem: some(targetSystem),
        targetFleet: none(FleetId),
        priority: 40
      ))

  of StandingOrderType.PatrolRoute:
    # Follow patrol path
    if standingOrder.params.patrolSystems.len > 0:
      let currentIndex = standingOrder.params.patrolIndex
      let nextSystem = standingOrder.params.patrolSystems[currentIndex]

      logDebug(LogCategory.lcAI,
               &"{fleet.id} PatrolRoute: Moving to waypoint {currentIndex + 1}/{standingOrder.params.patrolSystems.len}")

      return some(FleetOrder(
        fleetId: fleet.id,
        orderType: FleetOrderType.Move,
        targetSystem: some(nextSystem),
        targetFleet: none(FleetId),
        priority: 50
      ))
    else:
      return none(FleetOrder)

  else:
    # Other standing order types not yet implemented
    logDebug(LogCategory.lcAI,
             &"{fleet.id} Standing order {standingOrder.orderType} not yet implemented")
    return none(FleetOrder)
