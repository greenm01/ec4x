## Shared Fleet Command Execution Logic
##
## This module provides fleet command execution orchestration that can be called
## from different phases with category filters per FINAL_TURN_SEQUENCE.md:
## - Movement commands: Maintenance Phase
## - Combat commands: Conflict Phase (queued Turn N, executed Turn N+1)
## - Administrative commands: Command Phase
## - Special commands: Various phases (colonize, salvage, espionage)

import std/[tables, algorithm, options, random, sequtils, hashes, sets, strformat]
import ../../types/[core, game_state, command, fleet, squadron]
import ../../../common/logger as common_logger
import ../../state/[entity_manager, iterators]
import ../commands/[executor]
import ./standing
import ../resolution/[types as res_types, fleet_orders, simultaneous]
import ../combat/battles # Space/orbital combat (resolveBattle)
import
  ../colony/planetary_combat
    # Planetary combat (resolveBombardment, resolveInvasion, resolveBlitz)
import ../../event_factory/init as event_factory
import ../diplomacy/[types as dip_types]

type
  OrderCategoryFilter* = proc(orderType: FleetCommandType): bool

  ExecutionValidationResult = object
    valid*: bool
    shouldAbort*: bool # True if order should be converted to SeekHome/Hold
    reason*: string

proc validateCommandAtExecution(
    state: GameState, command: FleetCommand, houseId: HouseId
): ExecutionValidationResult =
  ## Fail-safe validation at execution time
  ## Checks if conditions have changed since submission

  # Check fleet still exists (may have been destroyed in combat) - using entity_manager
  let fleetOpt = state.fleets.entities.getEntity(command.fleetId)
  if fleetOpt.isNone:
    return ExecutionValidationResult(
      valid: false, shouldAbort: false, reason: "Fleet no longer exists"
    )

  let fleet = fleetOpt.get()

  # Verify fleet ownership (should never fail, but safety check)
  if fleet.owner != houseId:
    return ExecutionValidationResult(
      valid: false, shouldAbort: false, reason: "Fleet ownership changed"
    )

  # Order-specific validation
  case command.commandType
  of FleetCommandType.Colonize:
    # Check fleet still has ETAC
    # ETACs are in Expansion squadrons
    var hasETAC = false
    for squadron in fleet.squadrons:
      if squadron.squadronType == SquadronClass.Expansion:
        if squadron.flagship.shipClass == ShipClass.ETAC:
          if not squadron.flagship.isCrippled:
            hasETAC = true
            break

    if not hasETAC:
      return ExecutionValidationResult(
        valid: false, shouldAbort: true, reason: "Lost ETAC (ships crippled/destroyed)"
      )

    # Check target not already colonized (using entity_manager)
    if command.targetSystem.isSome:
      let targetId = command.targetSystem.get()
      let colonyOpt = state.colonies.entities.getEntity(targetId)
      if colonyOpt.isSome:
        return ExecutionValidationResult(
          valid: false, shouldAbort: true, reason: "Target system already colonized"
        )
  of FleetCommandType.Bombard, FleetCommandType.Invade, FleetCommandType.Blitz:
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
        reason: "Lost combat capability (ships crippled/destroyed)",
      )

    # Check if target is NOW FRIENDLY (abort - someone else captured it) - using entity_manager
    # Allow attacks on enemies, neutral, or uncolonized systems
    if command.targetSystem.isSome:
      let targetId = command.targetSystem.get()
      let colonyOpt = state.colonies.entities.getEntity(targetId)
      if colonyOpt.isSome:
        let colony = colonyOpt.get()
        if colony.owner == houseId:
          # Target is now OUR colony - abort attack
          return ExecutionValidationResult(
            valid: false,
            shouldAbort: true,
            reason: "Target system is now our colony (captured by us or ally)",
          )
        # NOTE: If target is enemy/neutral, allow attack to proceed
  of FleetCommandType.JoinFleet:
    # Check target fleet still exists (using entity_manager)
    if command.targetFleet.isSome:
      let targetFleetId = command.targetFleet.get()
      let targetFleetOpt = state.fleets.entities.getEntity(targetFleetId)
      if targetFleetOpt.isNone:
        return ExecutionValidationResult(
          valid: false, shouldAbort: false, reason: "Target fleet no longer exists"
        )

      # Check fleets still in same location
      let targetFleet = targetFleetOpt.get()
      if fleet.location != targetFleet.location:
        return ExecutionValidationResult(
          valid: false, shouldAbort: false, reason: "Fleets no longer in same location"
        )

      # Check squadron type compatibility (Intel cannot mix with non-Intel)
      let sourceHasIntel = fleet.squadrons.anyIt(it.squadronType == SquadronClass.Intel)
      let sourceHasNonIntel =
        fleet.squadrons.anyIt(it.squadronType != SquadronClass.Intel)
      let targetHasIntel =
        targetFleet.squadrons.anyIt(it.squadronType == SquadronClass.Intel)
      let targetHasNonIntel =
        targetFleet.squadrons.anyIt(it.squadronType != SquadronClass.Intel)

      # Intel squadrons cannot join non-Intel fleets
      if sourceHasIntel and targetHasNonIntel:
        return ExecutionValidationResult(
          valid: false,
          shouldAbort: false,
          reason: "Cannot join Intel squadron to fleet with non-Intel squadrons",
        )

      # Non-Intel squadrons cannot join Intel fleets
      if sourceHasNonIntel and targetHasIntel:
        return ExecutionValidationResult(
          valid: false,
          shouldAbort: false,
          reason: "Cannot join non-Intel squadron to Intel-only fleet",
        )
  of FleetCommandType.SpyPlanet, FleetCommandType.SpySystem,
      FleetCommandType.HackStarbase:
    # Check fleet is still Intel-only (no combat/other squadrons added)
    let hasIntel = fleet.squadrons.anyIt(it.squadronType == SquadronClass.Intel)
    let hasNonIntel = fleet.squadrons.anyIt(it.squadronType != SquadronClass.Intel)

    if not hasIntel:
      return ExecutionValidationResult(
        valid: false,
        shouldAbort: false,
        reason: "Fleet has no Intel squadrons (spy missions require Intel squadrons)",
      )

    if hasNonIntel:
      return ExecutionValidationResult(
        valid: false,
        shouldAbort: false,
        reason: "Fleet has non-Intel squadrons (spy missions require pure Intel fleets)",
      )

    # Check no Expansion/Auxiliary squadrons (spy missions require Intel-only)
    for squadron in fleet.squadrons:
      if squadron.squadronType in {SquadronClass.Expansion, SquadronClass.Auxiliary}:
        return ExecutionValidationResult(
          valid: false,
          shouldAbort: false,
          reason:
            "Fleet has Expansion/Auxiliary squadrons (spy missions require Intel-only)",
        )
  of FleetCommandType.Patrol:
    # Check if patrol system is now hostile (lost to enemy) - using entity_manager
    if command.targetSystem.isSome:
      let targetId = command.targetSystem.get()
      let colonyOpt = state.colonies.entities.getEntity(targetId)
      if colonyOpt.isSome:
        let colony = colonyOpt.get()
        if colony.owner != houseId:
          let houseOpt = state.houses.entities.getEntity(houseId)
          if houseOpt.isSome:
            let relation =
              houseOpt.get().diplomaticRelations.getDiplomaticState(colony.owner)
            if relation == dip_types.DiplomaticState.Enemy:
              return ExecutionValidationResult(
                valid: false,
                shouldAbort: true,
                reason: "Patrol system captured by enemy",
              )
  else:
    discard

  # Order is valid at execution time
  return ExecutionValidationResult(valid: true, shouldAbort: false, reason: "")

proc performCommandMaintenance*(
    state: var GameState,
    orders: Table[HouseId, OrderPacket],
    events: var seq[res_types.GameEvent],
    combatReports: var seq[res_types.CombatReport],
    rng: var Rand,
    categoryFilter: OrderCategoryFilter,
    phaseDescription: string,
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
      for command in orders[houseId].fleetCommands:
        # Only process orders matching the category filter
        if not categoryFilter(command.commandType):
          continue

        # Check if this fleet has a locked permanent order (Reserve/Mothball) - using entity_manager
        let fleetOpt = state.fleets.entities.getEntity(command.fleetId)
        if fleetOpt.isSome:
          let fleet = fleetOpt.get()
          if fleet.status == FleetStatus.Reserve or
              fleet.status == FleetStatus.Mothballed:
            if command.commandType != FleetCommandType.Reactivate:
              logDebug(
                LogCategory.lcOrders,
                &"  [LOCKED] Fleet {command.fleetId} has locked permanent order",
              )
              continue

        allFleetOrders.add((houseId, command))
        newOrdersThisTurn.incl(command.fleetId)
        state.fleetCommands[command.fleetId] = order

        # Generate OrderIssued event for new order
        events.add(
          event_factory.commandIssued(
            houseId,
            command.fleetId,
            $command.commandType,
            systemId = command.targetSystem,
          )
        )

  # Step 2: Add PERSISTENT orders from previous turns (not overridden) - using entity_manager
  for fleetId, persistentOrder in state.fleetCommands:
    if fleetId in newOrdersThisTurn:
      continue # Overridden by new order

    let fleetOpt = state.fleets.entities.getEntity(fleetId)
    if fleetOpt.isNone:
      continue # Fleet no longer exists

    # Only process orders matching the category filter
    if not categoryFilter(persistentOrder.commandType):
      continue

    let fleet = fleetOpt.get()
    allFleetOrders.add((fleet.owner, persistentOrder))

  # Sort by priority
  allFleetOrders.sort do(a, b: (HouseId, FleetOrder)) -> int:
    cmp(a[1].priority, b[1].priority)

  logDebug(
    LogCategory.lcOrders, &"[{phaseDescription}] Executing {allFleetOrders.len} orders"
  )

  # Track which fleets have already executed orders this turn
  var fleetsProcessed = initHashSet[FleetId]()

  # Execute all fleet orders
  for (houseId, command) in allFleetOrders:
    # Skip if fleet already executed an order this turn
    if command.fleetId in fleetsProcessed:
      logDebug(
        LogCategory.lcOrders, &"  [SKIPPED] Fleet {command.fleetId} already executed"
      )
      continue

    fleetsProcessed.incl(command.fleetId)

    # EXECUTION-TIME VALIDATION: Fail-safe check if conditions changed since submission
    let validation = validateCommandAtExecution(state, order, houseId)

    var actualOrder = order
    if not validation.valid:
      logWarn(
        LogCategory.lcOrders,
        &"  [EXECUTION VALIDATION FAILED] Fleet {command.fleetId}: {validation.reason}",
      )

      if validation.shouldAbort:
        # Order should abort - convert to SeekHome/Hold (using entity_manager)
        let fleetOpt = state.fleets.entities.getEntity(command.fleetId)
        if fleetOpt.isSome:
          let fleet = fleetOpt.get()
          let safeDestination = findClosestOwnedColony(state, fleet.location, houseId)

          # Generate OrderAborted event
          events.add(
            event_factory.commandAborted(
              houseId,
              command.fleetId,
              $command.commandType,
              reason = validation.reason,
              systemId = some(fleet.location),
            )
          )

          if safeDestination.isSome:
            actualOrder = FleetOrder(
              fleetId: command.fleetId,
              orderType: FleetCommandType.SeekHome,
              targetSystem: safeDestination,
              targetFleet: none(FleetId),
              priority: command.priority,
            )
            state.fleetCommands[command.fleetId] = actualOrder
            logInfo(
              LogCategory.lcFleet,
              &"Fleet {command.fleetId} mission aborted - seeking home ({validation.reason})",
            )
          else:
            actualOrder = FleetOrder(
              fleetId: command.fleetId,
              orderType: FleetCommandType.Hold,
              targetSystem: some(fleet.location),
              targetFleet: none(FleetId),
              priority: command.priority,
            )
            state.fleetCommands[command.fleetId] = actualOrder
            logWarn(
              LogCategory.lcFleet,
              &"Fleet {command.fleetId} mission aborted - holding position ({validation.reason})",
            )
        else:
          # Fleet doesn't exist, skip order
          logWarn(
            LogCategory.lcOrders,
            &"  [SKIPPED] Fleet {command.fleetId} no longer exists",
          )
          continue
      else:
        # Order invalid, skip execution
        logWarn(
          LogCategory.lcOrders,
          &"  [SKIPPED] Fleet {command.fleetId} order invalid at execution",
        )
        continue

    # Execute the validated order (events added directly via mutable parameter)
    let outcome = executor.executeFleetCommand(state, houseId, actualOrder, events)

    if outcome == OrderOutcome.Success:
      logDebug(
        LogCategory.lcFleet,
        &"Fleet {actualOrder.fleetId} order {actualOrder.commandType} executed",
      )
      # Events already added via mutable parameter

      # Handle combat orders that trigger battles (using entity_manager and iterators)
      if actualOrder.commandType in
          {FleetCommandType.Bombard, FleetCommandType.Invade, FleetCommandType.Blitz}:
        let fleetOpt = state.fleets.entities.getEntity(actualOrder.fleetId)
        if fleetOpt.isSome and actualOrder.targetSystem.isSome:
          let fleet = fleetOpt.get()
          let targetSystem = actualOrder.targetSystem.get()

          # Check if hostile forces are present
          var hasHostileForces = false

          # Check for enemy/neutral fleets (using fleetsInSystem iterator)
          let houseOpt = state.houses.entities.getEntity(houseId)
          if houseOpt.isSome:
            for otherFleet in state.fleetsInSystem(targetSystem):
              if otherFleet.owner != houseId:
                let relation = houseOpt.get().diplomaticRelations.getDiplomaticState(
                    otherFleet.owner
                  )
                if relation == dip_types.DiplomaticState.Enemy or
                    relation == dip_types.DiplomaticState.Neutral:
                  hasHostileForces = true
                  break

          # Check for starbases (using entity_manager)
          let colonyOpt = state.colonies.entities.getEntity(targetSystem)
          if colonyOpt.isSome:
            let colony = colonyOpt.get()
            if colony.owner != houseId and colony.starbases.len > 0:
              if houseOpt.isSome:
                let relation =
                  houseOpt.get().diplomaticRelations.getDiplomaticState(colony.owner)
                if relation == dip_types.DiplomaticState.Enemy or
                    relation == dip_types.DiplomaticState.Neutral:
                  hasHostileForces = true

          # If hostile forces present, trigger battle first
          if hasHostileForces:
            logInfo(
              LogCategory.lcCombat,
              &"Fleet {actualOrder.fleetId} engaging defenders before {actualOrder.commandType}",
            )
            resolveBattle(state, targetSystem, orders, combatReports, events, rng)

            # Check if fleet survived combat (using entity_manager)
            if state.fleets.entities.getEntity(actualOrder.fleetId).isNone:
              logInfo(
                LogCategory.lcCombat, &"Fleet {actualOrder.fleetId} destroyed in combat"
              )
              continue

          # Execute planetary assault
          case actualOrder.commandType
          of FleetCommandType.Bombard:
            resolveBombardment(state, houseId, actualOrder, events)
          of FleetCommandType.Invade:
            resolveInvasion(state, houseId, actualOrder, events)
          of FleetCommandType.Blitz:
            resolveBlitz(state, houseId, actualOrder, events)
          else:
            discard
    elif outcome == OrderOutcome.Failed:
      # Order failed validation - event generated, cleanup handled by Command Phase
      logDebug(
        LogCategory.lcFleet,
        &"Fleet {actualOrder.fleetId} order {actualOrder.commandType} failed validation",
      )
    elif outcome == OrderOutcome.Aborted:
      # Order aborted - event generated, cleanup handled by Command Phase
      logDebug(
        LogCategory.lcFleet,
        &"Fleet {actualOrder.fleetId} order {actualOrder.commandType} aborted",
      )

  logDebug(
    LogCategory.lcOrders, &"[{phaseDescription}] Completed fleet order execution"
  )
