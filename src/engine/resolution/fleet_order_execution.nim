## Shared Fleet Order Execution Logic
##
## This module provides fleet order execution that can be called from different
## phases with category filters per FINAL_TURN_SEQUENCE.md:
## - Movement orders: Maintenance Phase
## - Combat orders: Conflict Phase (queued Turn N, executed Turn N+1)
## - Administrative orders: Command Phase
## - Special orders: Various phases (colonize, salvage, espionage)

import std/[tables, algorithm, options, random, sequtils, hashes, sets, strformat]
import ../../common/types/core
import ../../common/logger as common_logger
import ../gamestate, ../orders, ../fleet, ../squadron, ../logger, ../order_types
import ../diplomacy/[types as dip_types]
import ../commands/[executor]
import ../standing_orders
import ./[types as res_types, fleet_orders, combat_resolution, simultaneous]
import ./event_factory/init as event_factory

type
  OrderCategoryFilter* = proc(orderType: FleetOrderType): bool

  ExecutionValidationResult = object
    valid*: bool
    shouldAbort*: bool  # True if order should be converted to SeekHome/Hold
    reason*: string

proc validateOrderAtExecution(
  state: GameState,
  order: FleetOrder,
  houseId: HouseId
): ExecutionValidationResult =
  ## Fail-safe validation at execution time
  ## Checks if conditions have changed since submission

  # Check fleet still exists (may have been destroyed in combat)
  if order.fleetId notin state.fleets:
    return ExecutionValidationResult(
      valid: false,
      shouldAbort: false,
      reason: "Fleet no longer exists"
    )

  let fleet = state.fleets[order.fleetId]

  # Verify fleet ownership (should never fail, but safety check)
  if fleet.owner != houseId:
    return ExecutionValidationResult(
      valid: false,
      shouldAbort: false,
      reason: "Fleet ownership changed"
    )

  # Order-specific validation
  case order.orderType
  of FleetOrderType.Colonize:
    # Check fleet still has ETAC
    # ETACs are in Expansion squadrons
    var hasETAC = false
    for squadron in fleet.squadrons:
      if squadron.squadronType == SquadronType.Expansion:
        if squadron.flagship.shipClass == ShipClass.ETAC:
          if not squadron.flagship.isCrippled:
            hasETAC = true
            break

    if not hasETAC:
      return ExecutionValidationResult(
        valid: false,
        shouldAbort: true,
        reason: "Lost ETAC (ships crippled/destroyed)"
      )

    # Check target not already colonized
    if order.targetSystem.isSome:
      let targetId = order.targetSystem.get()
      if targetId in state.colonies:
        return ExecutionValidationResult(
          valid: false,
          shouldAbort: true,
          reason: "Target system already colonized"
        )

  of FleetOrderType.Bombard, FleetOrderType.Invade, FleetOrderType.Blitz:
    # Check fleet still has combat capability
    var hasCombat = false
    for squadron in fleet.squadrons:
      if squadron.flagship.stats.attackStrength > 0 and not squadron.flagship.isCrippled:
        hasCombat = true
        break

    if not hasCombat:
      return ExecutionValidationResult(
        valid: false,
        shouldAbort: true,
        reason: "Lost combat capability (ships crippled/destroyed)"
      )

    # Check if target is NOW FRIENDLY (abort - someone else captured it)
    # Allow attacks on enemies, neutral, or uncolonized systems
    if order.targetSystem.isSome:
      let targetId = order.targetSystem.get()
      if targetId in state.colonies:
        let colony = state.colonies[targetId]
        if colony.owner == houseId:
          # Target is now OUR colony - abort attack
          return ExecutionValidationResult(
            valid: false,
            shouldAbort: true,
            reason: "Target system is now our colony (captured by us or ally)"
          )
        # NOTE: If target is enemy/neutral, allow attack to proceed

  of FleetOrderType.JoinFleet:
    # Check target fleet still exists
    if order.targetFleet.isSome:
      let targetFleetId = order.targetFleet.get()
      if targetFleetId notin state.fleets:
        return ExecutionValidationResult(
          valid: false,
          shouldAbort: false,
          reason: "Target fleet no longer exists"
        )

      # Check fleets still in same location
      let targetFleet = state.fleets[targetFleetId]
      if fleet.location != targetFleet.location:
        return ExecutionValidationResult(
          valid: false,
          shouldAbort: false,
          reason: "Fleets no longer in same location"
        )

  of FleetOrderType.SpyPlanet, FleetOrderType.SpySystem, FleetOrderType.HackStarbase:
    # Check fleet is still Intel-only (no combat/other squadrons added)
    let hasIntel = fleet.squadrons.anyIt(it.squadronType == SquadronType.Intel)
    let hasNonIntel = fleet.squadrons.anyIt(it.squadronType != SquadronType.Intel)

    if not hasIntel:
      return ExecutionValidationResult(
        valid: false,
        shouldAbort: false,
        reason: "Fleet has no Intel squadrons (spy missions require Intel squadrons)"
      )

    if hasNonIntel:
      return ExecutionValidationResult(
        valid: false,
        shouldAbort: false,
        reason: "Fleet has non-Intel squadrons (spy missions require pure Intel fleets)"
      )

    # Check no Expansion/Auxiliary squadrons (spy missions require Intel-only)
    for squadron in fleet.squadrons:
      if squadron.squadronType in {SquadronType.Expansion, SquadronType.Auxiliary}:
        return ExecutionValidationResult(
          valid: false,
          shouldAbort: false,
          reason: "Fleet has Expansion/Auxiliary squadrons (spy missions require Intel-only)"
        )

  of FleetOrderType.Patrol:
    # Check if patrol system is now hostile (lost to enemy)
    if order.targetSystem.isSome:
      let targetId = order.targetSystem.get()
      if targetId in state.colonies:
        let colony = state.colonies[targetId]
        if colony.owner != houseId:
          let relation = state.houses[houseId].diplomaticRelations.getDiplomaticState(colony.owner)
          if relation == dip_types.DiplomaticState.Enemy:
            return ExecutionValidationResult(
              valid: false, shouldAbort: true,
              reason: "Patrol system captured by enemy"
            )

  else:
    discard

  # Order is valid at execution time
  return ExecutionValidationResult(valid: true, shouldAbort: false, reason: "")

proc performOrderMaintenance*(
  state: var GameState,
  orders: Table[HouseId, OrderPacket],
  events: var seq[res_types.GameEvent],
  combatReports: var seq[res_types.CombatReport],
  rng: var Rand,
  categoryFilter: OrderCategoryFilter,
  phaseDescription: string
) =
  ## Manage fleet order lifecycle: validation, completion detection, and execution
  ## This is the core fleet order maintenance logic shared across phases

  logDebug(LogCategory.lcOrders, &"[{phaseDescription}] Starting fleet order execution")

  # Collect all fleet orders (new + persistent)
  var allFleetOrders: seq[(HouseId, FleetOrder)] = @[]
  var newOrdersThisTurn = initHashSet[FleetId]()

  # Step 1: Collect NEW orders from this turn's OrderPackets
  for houseId in state.houses.keys:
    if houseId in orders:
      for order in orders[houseId].fleetOrders:
        # Only process orders matching the category filter
        if not categoryFilter(order.orderType):
          continue

        # Check if this fleet has a locked permanent order (Reserve/Mothball)
        if order.fleetId in state.fleets:
          let fleet = state.fleets[order.fleetId]
          if fleet.status == FleetStatus.Reserve or fleet.status == FleetStatus.Mothballed:
            if order.orderType != FleetOrderType.Reactivate:
              logDebug(LogCategory.lcOrders, &"  [LOCKED] Fleet {order.fleetId} has locked permanent order")
              continue

        allFleetOrders.add((houseId, order))
        newOrdersThisTurn.incl(order.fleetId)
        state.fleetOrders[order.fleetId] = order

        # Generate OrderIssued event for new order
        events.add(event_factory.orderIssued(
          houseId,
          order.fleetId,
          $order.orderType,
          systemId = order.targetSystem
        ))

  # Step 2: Add PERSISTENT orders from previous turns (not overridden)
  for fleetId, persistentOrder in state.fleetOrders:
    if fleetId in newOrdersThisTurn:
      continue  # Overridden by new order

    if fleetId notin state.fleets:
      continue  # Fleet no longer exists

    # Only process orders matching the category filter
    if not categoryFilter(persistentOrder.orderType):
      continue

    let fleet = state.fleets[fleetId]
    allFleetOrders.add((fleet.owner, persistentOrder))

  # Sort by priority
  allFleetOrders.sort do (a, b: (HouseId, FleetOrder)) -> int:
    cmp(a[1].priority, b[1].priority)

  logDebug(LogCategory.lcOrders, &"[{phaseDescription}] Executing {allFleetOrders.len} orders")

  # Track which fleets have already executed orders this turn
  var fleetsProcessed = initHashSet[FleetId]()

  # Execute all fleet orders
  for (houseId, order) in allFleetOrders:
    # Skip if fleet already executed an order this turn
    if order.fleetId in fleetsProcessed:
      logDebug(LogCategory.lcOrders, &"  [SKIPPED] Fleet {order.fleetId} already executed")
      continue

    fleetsProcessed.incl(order.fleetId)

    # EXECUTION-TIME VALIDATION: Fail-safe check if conditions changed since submission
    let validation = validateOrderAtExecution(state, order, houseId)

    var actualOrder = order
    if not validation.valid:
      logWarn(LogCategory.lcOrders,
        &"  [EXECUTION VALIDATION FAILED] Fleet {order.fleetId}: {validation.reason}")

      if validation.shouldAbort:
        # Order should abort - convert to SeekHome/Hold
        if order.fleetId in state.fleets:
          let fleet = state.fleets[order.fleetId]
          let safeDestination = findClosestOwnedColony(state, fleet.location, houseId)

          # Generate OrderAborted event
          events.add(event_factory.orderAborted(
            houseId,
            order.fleetId,
            $order.orderType,
            reason = validation.reason,
            systemId = some(fleet.location)
          ))

          if safeDestination.isSome:
            actualOrder = FleetOrder(
              fleetId: order.fleetId,
              orderType: FleetOrderType.SeekHome,
              targetSystem: safeDestination,
              targetFleet: none(FleetId),
              priority: order.priority
            )
            state.fleetOrders[order.fleetId] = actualOrder
            logInfo(LogCategory.lcFleet,
              &"Fleet {order.fleetId} mission aborted - seeking home ({validation.reason})")
          else:
            actualOrder = FleetOrder(
              fleetId: order.fleetId,
              orderType: FleetOrderType.Hold,
              targetSystem: some(fleet.location),
              targetFleet: none(FleetId),
              priority: order.priority
            )
            state.fleetOrders[order.fleetId] = actualOrder
            logWarn(LogCategory.lcFleet,
              &"Fleet {order.fleetId} mission aborted - holding position ({validation.reason})")
        else:
          # Fleet doesn't exist, skip order
          logWarn(LogCategory.lcOrders, &"  [SKIPPED] Fleet {order.fleetId} no longer exists")
          continue
      else:
        # Order invalid, skip execution
        logWarn(LogCategory.lcOrders, &"  [SKIPPED] Fleet {order.fleetId} order invalid at execution")
        continue

    # Execute the validated order (events added directly via mutable parameter)
    let outcome = executor.executeFleetOrder(state, houseId, actualOrder, events)

    if outcome == OrderOutcome.Success:
      logDebug(LogCategory.lcFleet, &"Fleet {actualOrder.fleetId} order {actualOrder.orderType} executed")
      # Events already added via mutable parameter

      # Handle combat orders that trigger battles
      if actualOrder.orderType in {FleetOrderType.Bombard, FleetOrderType.Invade, FleetOrderType.Blitz}:
        if actualOrder.fleetId in state.fleets and actualOrder.targetSystem.isSome:
          let fleet = state.fleets[actualOrder.fleetId]
          let targetSystem = actualOrder.targetSystem.get()

          # Check if hostile forces are present
          var hasHostileForces = false

          # Check for enemy/neutral fleets
          for otherFleet in state.fleets.values:
            if otherFleet.location == targetSystem and otherFleet.owner != houseId:
              let relation = state.houses[houseId].diplomaticRelations.getDiplomaticState(otherFleet.owner)
              if relation == dip_types.DiplomaticState.Enemy or
                 relation == dip_types.DiplomaticState.Neutral:
                hasHostileForces = true
                break

          # Check for starbases
          if targetSystem in state.colonies:
            let colony = state.colonies[targetSystem]
            if colony.owner != houseId and colony.starbases.len > 0:
              let relation = state.houses[houseId].diplomaticRelations.getDiplomaticState(colony.owner)
              if relation == dip_types.DiplomaticState.Enemy or
                 relation == dip_types.DiplomaticState.Neutral:
                hasHostileForces = true

          # If hostile forces present, trigger battle first
          if hasHostileForces:
            logInfo(LogCategory.lcCombat, &"Fleet {actualOrder.fleetId} engaging defenders before {actualOrder.orderType}")
            resolveBattle(state, targetSystem, orders, combatReports, events, rng)

            # Check if fleet survived combat
            if actualOrder.fleetId notin state.fleets:
              logInfo(LogCategory.lcCombat, &"Fleet {actualOrder.fleetId} destroyed in combat")
              continue

          # Execute planetary assault
          case actualOrder.orderType
          of FleetOrderType.Bombard:
            resolveBombardment(state, houseId, actualOrder, events)
          of FleetOrderType.Invade:
            resolveInvasion(state, houseId, actualOrder, events)
          of FleetOrderType.Blitz:
            resolveBlitz(state, houseId, actualOrder, events)
          else:
            discard
    elif outcome == OrderOutcome.Failed:
      # Order failed validation - event generated, cleanup handled by Command Phase
      logDebug(LogCategory.lcFleet, &"Fleet {actualOrder.fleetId} order {actualOrder.orderType} failed validation")
    elif outcome == OrderOutcome.Aborted:
      # Order aborted - event generated, cleanup handled by Command Phase
      logDebug(LogCategory.lcFleet, &"Fleet {actualOrder.fleetId} order {actualOrder.orderType} aborted")

  logDebug(LogCategory.lcOrders, &"[{phaseDescription}] Completed fleet order execution")
