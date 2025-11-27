## RBA Standing Orders Manager
##
## Intelligent assignment and management of standing orders for AI fleets.
## Integrates QoL standing orders system with RBA strategic decision-making.
##
## Philosophy:
## - Use standing orders to reduce micromanagement and ensure consistent fleet behavior
## - Assign standing orders based on fleet role, personality, and strategic context
## - Let standing orders handle routine tasks while explicit orders handle critical operations

import std/[tables, options, sequtils, strformat, sets]
import ../common/types
import ../../engine/[gamestate, fleet, logger, fog_of_war, starmap]
import ../../engine/order_types
import ../../common/types/[core, planets]
import ./controller_types

export StandingOrderType, StandingOrder, StandingOrderParams

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

    case squadron.flagship.shipClass
    of ShipClass.Scout:
      scoutCount += 1
    of ShipClass.ETAC:
      etacCount += 1
    of ShipClass.TroopTransport:
      discard  # Transports handled separately
    else:
      militaryCount += 1

    # Count wingmen
    for ship in squadron.ships:
      totalShips += 1
      if ship.isCrippled:
        crippledCount += 1

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

proc createAutoRepairOrder*(fleet: Fleet, homeworld: SystemId,
                           damageThreshold: float = 0.3): StandingOrder =
  ## Create AutoRepair standing order for damaged fleet
  ## Returns to homeworld shipyard when damage exceeds threshold

  logDebug(LogCategory.lcAI,
           &"{fleet.id} Assigning AutoRepair standing order " &
           &"(threshold {(damageThreshold * 100).int}%, target {homeworld})")

  result = StandingOrder(
    fleetId: fleet.id,
    orderType: StandingOrderType.AutoRepair,
    params: StandingOrderParams(
      orderType: StandingOrderType.AutoRepair,
      repairDamageThreshold: damageThreshold,
      targetShipyard: some(homeworld)
    ),
    roe: 3,  # Cautious ROE - avoid combat while damaged
    createdTurn: 0,  # Will be set by caller
    lastExecutedTurn: 0,
    executionCount: 0,
    suspended: false
  )

proc createAutoEvadeOrder*(fleet: Fleet, fallbackSystem: SystemId,
                          triggerRatio: float, roe: int): StandingOrder =
  ## Create AutoEvade standing order for risk-averse fleets
  ## Retreats to fallback when outnumbered

  logDebug(LogCategory.lcAI,
           &"{fleet.id} Assigning AutoEvade standing order " &
           &"(trigger ratio {triggerRatio:.2f}, fallback {fallbackSystem}, ROE {roe})")

  result = StandingOrder(
    fleetId: fleet.id,
    orderType: StandingOrderType.AutoEvade,
    params: StandingOrderParams(
      orderType: StandingOrderType.AutoEvade,
      fallbackSystem: fallbackSystem,
      evadeTriggerRatio: triggerRatio
    ),
    roe: roe,
    createdTurn: 0,
    lastExecutedTurn: 0,
    executionCount: 0,
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
    lastExecutedTurn: 0,
    executionCount: 0,
    suspended: false
  )

proc createAutoColonizeOrder*(fleet: Fleet, maxRange: int,
                              preferredClasses: seq[PlanetClass]): StandingOrder =
  ## Create AutoColonize standing order for ETAC fleets
  ## Automatically finds and colonizes suitable systems

  logDebug(LogCategory.lcAI,
           &"{fleet.id} Assigning AutoColonize standing order " &
           &"(range {maxRange} jumps, preferred classes: {preferredClasses.len})")

  result = StandingOrder(
    fleetId: fleet.id,
    orderType: StandingOrderType.AutoColonize,
    params: StandingOrderParams(
      orderType: StandingOrderType.AutoColonize,
      preferredPlanetClasses: preferredClasses,
      colonizeMaxRange: maxRange
    ),
    roe: 5,  # Moderate ROE for colonization
    createdTurn: 0,
    lastExecutedTurn: 0,
    executionCount: 0,
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
    lastExecutedTurn: 0,
    executionCount: 0,
    suspended: false
  )

# =============================================================================
# Intelligent Standing Order Management
# =============================================================================

proc assignStandingOrders*(controller: var AIController,
                          filtered: FilteredGameState,
                          currentTurn: int): Table[FleetId, StandingOrder] =
  ## Assign standing orders to all fleets based on role and personality
  ## Returns table of fleet assignments
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

  for fleet in filtered.ownFleets:
    # Assess fleet role
    let role = assessFleetRole(fleet, filtered, p)

    logDebug(LogCategory.lcAI,
             &"{controller.houseId} Fleet {fleet.id}: Role={role}, " &
             &"Location={fleet.location}")

    # Assign standing order based on role
    case role
    of FleetRole.Damaged:
      # Damaged fleets automatically return to shipyard
      let order = createAutoRepairOrder(fleet, homeworld, 0.3)
      result[fleet.id] = order
      assignedCount += 1

      logInfo(LogCategory.lcAI,
              &"{controller.houseId} Fleet {fleet.id}: Assigned AutoRepair " &
              &"(damaged fleet → homeworld {homeworld})")

    of FleetRole.Colonizer:
      # ETAC fleets automatically colonize
      let order = createAutoColonizeOrder(fleet, 10, preferredPlanetClasses)
      result[fleet.id] = order
      assignedCount += 1

      logInfo(LogCategory.lcAI,
              &"{controller.houseId} Fleet {fleet.id}: Assigned AutoColonize " &
              &"(ETAC fleet, range 10 jumps)")

    of FleetRole.Scout:
      # Scouts patrol and evade when outnumbered
      if p.riskTolerance < 0.5:
        # Risk-averse scouts use AutoEvade
        let evadeRatio = 0.7  # Retreat when at 70% enemy strength or worse
        let order = createAutoEvadeOrder(fleet, fallbackSystem, evadeRatio, baseROE)
        result[fleet.id] = order
        assignedCount += 1

        logInfo(LogCategory.lcAI,
                &"{controller.houseId} Fleet {fleet.id}: Assigned AutoEvade " &
                &"(scout, risk-averse)")
      else:
        # Aggressive scouts - no standing order (tactical will assign missions)
        skippedCount += 1
        logDebug(LogCategory.lcAI,
                 &"{controller.houseId} Fleet {fleet.id}: No standing order " &
                 &"(scout, aggressive personality)")

    of FleetRole.Defender:
      # Defensive fleets guard homeworld/colonies
      let order = createDefendSystemOrder(fleet, homeworld, 3, baseROE)
      result[fleet.id] = order
      assignedCount += 1

      logInfo(LogCategory.lcAI,
              &"{controller.houseId} Fleet {fleet.id}: Assigned DefendSystem " &
              &"(defender, homeworld {homeworld}, range 3)")

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
          &"{assignedCount} assigned, {skippedCount} skipped " &
          &"(tactical/logistics control)")

# =============================================================================
# Standing Order Conversion to Fleet Orders
# =============================================================================

proc findNearestShipyard*(filtered: FilteredGameState, fromSystem: SystemId): Option[SystemId] =
  ## Find nearest colony with shipyard for repairs
  ## Returns closest shipyard colony, or homeworld as fallback

  var nearestSystem: Option[SystemId] = none(SystemId)
  var shortestDistance = int.high

  for colony in filtered.ownColonies:
    # Check if colony has operational shipyard
    if hasOperationalShipyard(colony):
      # Calculate distance (BFS would be more accurate, but this is a simple heuristic)
      # For now, just find any shipyard - pathfinding happens in order execution
      if nearestSystem.isNone:
        nearestSystem = some(colony.systemId)
        break

  return nearestSystem

proc findNearestUnclaimedSystem*(filtered: FilteredGameState,
                                 fromSystem: SystemId,
                                 maxRange: int,
                                 preferredClasses: seq[PlanetClass]): Option[SystemId] =
  ## Find nearest unclaimed system suitable for colonization
  ## Prefers systems matching preferred planet classes

  # Get list of colonized systems
  var colonizedSystems = initHashSet[SystemId]()
  for colony in filtered.ownColonies:
    colonizedSystems.incl(colony.systemId)
  for visCol in filtered.visibleColonies:
    colonizedSystems.incl(visCol.systemId)

  # Search visible systems for unclaimed ones
  var candidates: seq[SystemId] = @[]

  for systemId, visSystem in filtered.visibleSystems:
    if systemId notin colonizedSystems:
      # Check if system has habitable planet (would need planet data to verify)
      # For now, any unclaimed visible system is a candidate
      candidates.add(systemId)

  # Return first candidate (tactical module will prioritize based on value)
  if candidates.len > 0:
    return some(candidates[0])

  return none(SystemId)

proc convertStandingOrderToFleetOrder*(standingOrder: StandingOrder,
                                       fleet: Fleet,
                                       filtered: FilteredGameState): Option[FleetOrder] =
  ## Convert standing order to executable FleetOrder
  ## Returns fleet order if conversion successful, none if order cannot execute

  case standingOrder.orderType

  of StandingOrderType.AutoRepair:
    # Find nearest shipyard for repairs
    let targetShipyard = if standingOrder.params.targetShipyard.isSome:
      standingOrder.params.targetShipyard
    else:
      findNearestShipyard(filtered, fleet.location)

    if targetShipyard.isSome:
      logDebug(LogCategory.lcAI,
               &"{fleet.id} AutoRepair: Moving to shipyard at {targetShipyard.get}")

      return some(FleetOrder(
        fleetId: fleet.id,
        orderType: FleetOrderType.Move,
        targetSystem: targetShipyard,
        targetFleet: none(FleetId),
        priority: 50
      ))
    else:
      logWarn(LogCategory.lcAI,
              &"{fleet.id} AutoRepair: No shipyard found, holding position")
      return none(FleetOrder)

  of StandingOrderType.AutoColonize:
    # Find nearest unclaimed system
    let targetSystem = findNearestUnclaimedSystem(
      filtered,
      fleet.location,
      standingOrder.params.colonizeMaxRange,
      standingOrder.params.preferredPlanetClasses
    )

    if targetSystem.isSome:
      # Check if fleet is already at target
      if fleet.location == targetSystem.get:
        logDebug(LogCategory.lcAI,
                 &"{fleet.id} AutoColonize: Colonizing {targetSystem.get}")

        return some(FleetOrder(
          fleetId: fleet.id,
          orderType: FleetOrderType.Colonize,
          targetSystem: targetSystem,
          targetFleet: none(FleetId),
          priority: 60
        ))
      else:
        logDebug(LogCategory.lcAI,
                 &"{fleet.id} AutoColonize: Moving to {targetSystem.get}")

        return some(FleetOrder(
          fleetId: fleet.id,
          orderType: FleetOrderType.Move,
          targetSystem: targetSystem,
          targetFleet: none(FleetId),
          priority: 60
        ))
    else:
      logDebug(LogCategory.lcAI,
               &"{fleet.id} AutoColonize: No unclaimed systems found, holding")
      return none(FleetOrder)

  of StandingOrderType.DefendSystem:
    # Patrol assigned system or move to it
    let targetSystem = standingOrder.params.defendTargetSystem

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

  of StandingOrderType.AutoEvade:
    # Retreat to fallback system if threatened
    # For now, always generate Move order to fallback (threat detection TBD)
    let fallbackSystem = standingOrder.params.fallbackSystem

    if fleet.location != fallbackSystem:
      logDebug(LogCategory.lcAI,
               &"{fleet.id} AutoEvade: Retreating to {fallbackSystem}")

      return some(FleetOrder(
        fleetId: fleet.id,
        orderType: FleetOrderType.Move,
        targetSystem: some(fallbackSystem),
        targetFleet: none(FleetId),
        priority: 30  # High priority for retreats
      ))
    else:
      # Already at safe location, hold
      return none(FleetOrder)

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
