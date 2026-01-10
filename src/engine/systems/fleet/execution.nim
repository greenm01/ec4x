## Shared Fleet Command Execution Logic
##
## This module provides fleet command execution orchestration that can be called
## from different phases with category filters per FINAL_TURN_SEQUENCE.md:
## - Movement commands: Maintenance Phase
## - Combat commands: Conflict Phase (queued Turn N, executed Turn N+1)
## - Administrative commands: Command Phase
## - Special commands: Various phases (colonize, salvage, espionage)

import std/[tables, algorithm, options, random, hashes, sets, strformat]
import ../../types/[core, game_state, command, fleet, ship, combat, event, diplomacy]
import ../../../common/logger
import ../../state/[engine, iterators, fleet_queries]
import ./dispatcher # For OrderOutcome and executeFleetCommand
import ./mechanics # For findClosestOwnedColony
import ./entity
# import ../combat/battles # REMOVED: Legacy squadron-based system
# import ../colony/planetary_combat # REMOVED: Combat now handled by orchestrator
import ../../event_factory/init

type
  OrderCategoryFilter* = proc(orderType: FleetCommandType): bool

  ExecutionValidationResult = object
    valid*: bool
    shouldAbort*: bool # True if command should be converted to SeekHome/Hold
    reason*: string

proc validateCommandAtExecution(
    state: GameState, command: FleetCommand, houseId: HouseId
): ExecutionValidationResult =
  ## Fail-safe validation at execution time
  ## Checks if conditions have changed since submission

  # Check fleet still exists (may have been destroyed in combat)
  let fleetOpt = state.fleet(command.fleetId)
  if fleetOpt.isNone:
    return ExecutionValidationResult(
      valid: false, shouldAbort: false, reason: "Fleet no longer exists"
    )

  let fleet = fleetOpt.get()

  # Verify fleet ownership (should never fail, but safety check)
  if fleet.houseId != houseId:
    return ExecutionValidationResult(
      valid: false, shouldAbort: false, reason: "Fleet ownership changed"
    )

  # Order-specific validation
  case command.commandType
  of FleetCommandType.Colonize:
    # Check fleet still has operational ETAC
    var hasETAC = false
    for shipId in fleet.ships:
      let shipOpt = state.ship(shipId)
      if shipOpt.isSome:
        let ship = shipOpt.get()
        if ship.shipClass == ShipClass.ETAC and ship.state != CombatState.Crippled:
          hasETAC = true
          break

    if not hasETAC:
      return ExecutionValidationResult(
        valid: false, shouldAbort: true, reason: "Lost ETAC (ships crippled/destroyed)"
      )

    # Check target not already colonized
    if command.targetSystem.isSome:
      let targetId = command.targetSystem.get()
      let colonyOpt = state.colonyBySystem(targetId)
      if colonyOpt.isSome:
        return ExecutionValidationResult(
          valid: false, shouldAbort: true, reason: "Target system already colonized"
        )
  of FleetCommandType.Bombard, FleetCommandType.Invade, FleetCommandType.Blitz:
    # Check fleet still has combat capability
    var hasCombat = false
    for shipId in fleet.ships:
      let shipOpt = state.ship(shipId)
      if shipOpt.isSome:
        let ship = shipOpt.get()
        if ship.stats.attackStrength > 0 and ship.state != CombatState.Crippled:
          hasCombat = true
          break

    if not hasCombat:
      return ExecutionValidationResult(
        valid: false,
        shouldAbort: true,
        reason: "Lost combat capability (ships crippled/destroyed)",
      )

    # Check if target is NOW FRIENDLY (abort - someone else captured it)
    # Allow attacks on enemies, neutral, or uncolonized systems
    if command.targetSystem.isSome:
      let targetId = command.targetSystem.get()
      let colonyOpt = state.colonyBySystem(targetId)
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
    # Check target fleet still exists
    if command.targetFleet.isSome:
      let targetFleetId = command.targetFleet.get()
      let targetFleetOpt = state.fleet(targetFleetId)
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

      # Check ship type compatibility (Intel/Scout ships cannot mix with non-Intel)
      let mergeCheck = state.canMergeWith(fleet, targetFleet)
      if not mergeCheck.canMerge:
        return ExecutionValidationResult(
          valid: false,
          shouldAbort: false,
          reason: mergeCheck.reason,
        )
  of FleetCommandType.ScoutColony, FleetCommandType.ScoutSystem,
      FleetCommandType.HackStarbase:
    # Check fleet is still Intel-only (Scout ships only, no combat/other ships)
    let hasIntel = state.hasScouts(fleet)
    let hasNonIntel = state.hasNonScoutShips(fleet)

    if not hasIntel:
      return ExecutionValidationResult(
        valid: false,
        shouldAbort: false,
        reason: "Fleet has no Scout ships (scout missions require Scout ships)",
      )

    if hasNonIntel:
      return ExecutionValidationResult(
        valid: false,
        shouldAbort: false,
        reason: "Fleet has non-Scout ships (scout missions require pure Scout fleets)",
      )
  of FleetCommandType.Patrol:
    # Check if patrol system is now hostile (lost to enemy)
    if command.targetSystem.isSome:
      let targetId = command.targetSystem.get()
      let colonyOpt = state.colonyBySystem(targetId)
      if colonyOpt.isSome:
        let colony = colonyOpt.get()
        if colony.owner != houseId:
          # Check if patrol system is now enemy-owned
          if (houseId, colony.owner) in state.diplomaticRelation:
            let relation = state.diplomaticRelation[(houseId, colony.owner)]
            if relation.state == DiplomaticState.Enemy:
              return ExecutionValidationResult(
                valid: false,
                shouldAbort: true,
                reason: "Patrol system captured by enemy",
              )
  else:
    discard

  # Order is valid at execution time
  return ExecutionValidationResult(valid: true, shouldAbort: false, reason: "")

# ============================================================================
# Command Category Filters
# ============================================================================

proc isProductionCommand*(cmdType: FleetCommandType): bool =
  ## Returns true if command needs administrative completion in Production Phase
  ## Travel completion, logistics, administrative status changes
  result = cmdType in [
    FleetCommandType.Move,
    FleetCommandType.Hold,
    FleetCommandType.SeekHome,
    FleetCommandType.JoinFleet,
    FleetCommandType.Rendezvous,
    FleetCommandType.Reserve,
    FleetCommandType.Mothball,
    FleetCommandType.View
  ]

proc isConflictCommand*(cmdType: FleetCommandType): bool =
  ## Returns true if command needs administrative completion in Conflict Phase
  ## Combat operations, espionage, colonization
  result = cmdType in [
    FleetCommandType.Patrol,
    FleetCommandType.GuardStarbase,
    FleetCommandType.GuardColony,
    FleetCommandType.Blockade,
    FleetCommandType.Bombard,
    FleetCommandType.Invade,
    FleetCommandType.Blitz,
    FleetCommandType.Colonize,
    FleetCommandType.ScoutColony,
    FleetCommandType.ScoutSystem,
    FleetCommandType.HackStarbase
  ]

proc isIncomeCommand*(cmdType: FleetCommandType): bool =
  ## Returns true if command needs administrative completion in Income Phase
  ## Economic operations
  result = cmdType == FleetCommandType.Salvage

proc performCommandMaintenance*(
    state: GameState,
    orders: Table[HouseId, CommandPacket],
    events: var seq[GameEvent],
    rng: var Rand,
    categoryFilter: OrderCategoryFilter,
    phaseDescription: string,
) =
  ## Manage fleet command lifecycle: validation, completion detection, and execution
  ## This is the core fleet command maintenance logic shared across phases

  logDebug("Commands", &"[{phaseDescription}] Starting fleet command execution")

  # Collect all fleet commands (new + persistent)
  var allFleetCommands: seq[(HouseId, FleetCommand)] = @[]
  var newCommandsThisTurn = initHashSet[FleetId]()

  # Step 1: Collect NEW commands from this turn's OrderPackets
  for (houseId, _) in state.allHousesWithId():
    if houseId in orders:
      for command in orders[houseId].fleetCommands:
        # Only process commands matching the category filter
        if not categoryFilter(command.commandType):
          continue

        # Check if this fleet has a locked permanent command (Reserve/Mothball)
        let fleetOpt = state.fleet(command.fleetId)
        if fleetOpt.isSome:
          let fleet = fleetOpt.get()
          if fleet.status == FleetStatus.Reserve or
              fleet.status == FleetStatus.Mothballed:
            # Reserved/Mothballed fleets are locked and cannot accept new commands
            # They must be reactivated by changing status back to Active
            logDebug(
              "Commands",
              &"  [LOCKED] Fleet {command.fleetId} has command",
            )
            continue

          allFleetCommands.add((houseId, command))
          newCommandsThisTurn.incl(command.fleetId)

          # Assign command to fleet (entity-manager pattern)
          var updatedFleet = fleet
          updatedFleet.command = command
          updatedFleet.missionState = MissionState.Traveling
          updatedFleet.missionTarget = command.targetSystem
          state.updateFleet(command.fleetId, updatedFleet)

          # Generate CommandIssued event for new command
          events.add(
            commandIssued(
              houseId,
              command.fleetId,
              $command.commandType,
              systemId = command.targetSystem,
            )
          )

  # Step 2: Add PERSISTENT commands from previous turns (not overridden)
  for fleet in state.allFleets():
    # Skip if overridden by new command this turn
    if fleet.id in newCommandsThisTurn:
      continue

    # Skip if no active command (idle fleet)
    if fleet.missionState == MissionState.None:
      continue

    let persistentCommand = fleet.command

    # Only process commands matching the category filter
    if not categoryFilter(persistentCommand.commandType):
      continue

    allFleetCommands.add((fleet.houseId, persistentCommand))

  # Sort by priority
  allFleetCommands.sort do(a, b: (HouseId, FleetCommand)) -> int:
    cmp(a[1].priority, b[1].priority)

  logDebug(
    "Commands", &"[{phaseDescription}] Processing {allFleetCommands.len} commands"
  )

  # Track which fleets have already executed commands this turn
  var fleetsProcessed = initHashSet[FleetId]()

  # Execute all fleet commands
  for (houseId, command) in allFleetCommands:
    # Skip if fleet already executed an command this turn
    if command.fleetId in fleetsProcessed:
      logDebug(
        "Commands", &"  [SKIPPED] Fleet {command.fleetId} already executed"
      )
      continue

    fleetsProcessed.incl(command.fleetId)

    # EXECUTION-TIME VALIDATION: Fail-safe check if conditions changed since submission
    let validation = validateCommandAtExecution(state, command, houseId)

    var actualOrder = command
    if not validation.valid:
      logWarn(
        "Commands",
        &"  [EXECUTION VALIDATION FAILED] Fleet {command.fleetId}: {validation.reason}",
      )

      if validation.shouldAbort:
        # Order should abort - convert to SeekHome/Hold
        let fleetOpt = state.fleet(command.fleetId)
        if fleetOpt.isSome:
          let fleet = fleetOpt.get()
          let safeDestination = findClosestOwnedColony(state, fleet.location, houseId)

          # Generate OrderAborted event
          events.add(
            commandAborted(
              houseId,
              command.fleetId,
              $command.commandType,
              reason = validation.reason,
              systemId = some(fleet.location),
            )
          )

          if safeDestination.isSome:
            actualOrder = FleetCommand(
              fleetId: command.fleetId,
              commandType: FleetCommandType.SeekHome,
              targetSystem: safeDestination,
              targetFleet: none(FleetId),
              priority: command.priority,
            )

            # Assign fallback command to fleet (entity-manager pattern)
            var updatedFleet = fleet
            updatedFleet.command = actualOrder
            updatedFleet.missionState = MissionState.Traveling
            updatedFleet.missionTarget = safeDestination
            state.updateFleet(command.fleetId, updatedFleet)

            logInfo(
              "Fleet",
              &"Fleet {command.fleetId} mission aborted - seeking home ({validation.reason})",
            )
          else:
            actualOrder = FleetCommand(
              fleetId: command.fleetId,
              commandType: FleetCommandType.Hold,
              targetSystem: some(fleet.location),
              targetFleet: none(FleetId),
              priority: command.priority,
            )

            # Assign fallback command to fleet (entity-manager pattern)
            var updatedFleet = fleet
            updatedFleet.command = actualOrder
            updatedFleet.missionState = MissionState.None
            updatedFleet.missionTarget = some(fleet.location)
            state.updateFleet(command.fleetId, updatedFleet)

            logWarn(
              "Fleet",
              &"Fleet {command.fleetId} mission aborted - holding position ({validation.reason})",
            )
        else:
          # Fleet doesn't exist, skip order
          logWarn(
            "Commands",
            &"  [SKIPPED] Fleet {command.fleetId} no longer exists",
          )
          continue
      else:
        # Order invalid, skip execution
        logWarn(
          "Commands",
          &"  [SKIPPED] Fleet {command.fleetId} command invalid at execution",
        )
        continue

    # Execute the validated command (events added directly via mutable parameter)
    let outcome = dispatcher.executeFleetCommand(state, houseId, actualOrder, events)

    if outcome == OrderOutcome.Success:
      logDebug(
        "Fleet",
        &"Fleet {actualOrder.fleetId} command {actualOrder.commandType} executed",
      )
      # Events already added via mutable parameter
    elif outcome == OrderOutcome.Failed:
      # Order failed validation - event generated, cleanup handled by Command Phase
      logDebug(
        "Fleet",
        &"Fleet {actualOrder.fleetId} command {actualOrder.commandType} failed validation",
      )
    elif outcome == OrderOutcome.Aborted:
      # Order aborted - event generated, cleanup handled by Command Phase
      logDebug(
        "Fleet",
        &"Fleet {actualOrder.fleetId} command {actualOrder.commandType} aborted",
      )

  logDebug(
    "Commands", &"[{phaseDescription}] Completed fleet command execution"
  )
