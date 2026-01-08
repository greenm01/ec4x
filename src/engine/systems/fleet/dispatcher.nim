## Fleet Command Execution Dispatcher
## Implements all fleet command types from operations.md Section 6.2
## Routes commands to appropriate handlers based on command type

import std/[options, tables, strformat]
import ../../types/[core, fleet, ship, game_state, event, diplomacy]
import ../../state/[engine as state_module, iterators, fleet_queries]
import ../../intel/detection
import ../../event_factory/init as event_factory
import ./[mechanics, movement]
import ../ship/entity as ship_entity
import ../../../common/logger

type OrderOutcome* {.pure.} = enum
  Success # Order executed successfully, continue if persistent
  Failed # Order failed validation/execution, remove from queue
  Aborted # Order cancelled (conditions changed), remove from queue

# =============================================================================
# Forward Declarations
# =============================================================================

proc executeHoldCommand(
  state: var GameState,
  fleet: Fleet,
  command: FleetCommand,
  events: var seq[GameEvent],
): OrderOutcome

proc executeMoveCommand(
  state: var GameState,
  fleet: Fleet,
  command: FleetCommand,
  events: var seq[GameEvent],
): OrderOutcome

proc executeSeekHomeCommand(
  state: var GameState,
  fleet: Fleet,
  command: FleetCommand,
  events: var seq[GameEvent],
): OrderOutcome

proc executePatrolCommand(
  state: var GameState,
  fleet: Fleet,
  command: FleetCommand,
  events: var seq[GameEvent],
): OrderOutcome

proc executeGuardStarbaseCommand(
  state: var GameState,
  fleet: Fleet,
  command: FleetCommand,
  events: var seq[GameEvent],
): OrderOutcome

proc executeGuardColonyCommand(
  state: var GameState,
  fleet: Fleet,
  command: FleetCommand,
  events: var seq[GameEvent],
): OrderOutcome

proc executeBlockadeCommand(
  state: var GameState,
  fleet: Fleet,
  command: FleetCommand,
  events: var seq[GameEvent],
): OrderOutcome

proc executeBombardCommand(
  state: var GameState,
  fleet: Fleet,
  command: FleetCommand,
  events: var seq[GameEvent],
): OrderOutcome

proc executeInvadeCommand(
  state: var GameState,
  fleet: Fleet,
  command: FleetCommand,
  events: var seq[GameEvent],
): OrderOutcome

proc executeBlitzCommand(
  state: var GameState,
  fleet: Fleet,
  command: FleetCommand,
  events: var seq[GameEvent],
): OrderOutcome

proc executeScoutColonyCommand(
  state: var GameState,
  fleet: Fleet,
  command: FleetCommand,
  events: var seq[GameEvent],
): OrderOutcome

proc executeHackStarbaseCommand(
  state: var GameState,
  fleet: Fleet,
  command: FleetCommand,
  events: var seq[GameEvent],
): OrderOutcome

proc executeScoutSystemCommand(
  state: var GameState,
  fleet: Fleet,
  command: FleetCommand,
  events: var seq[GameEvent],
): OrderOutcome

proc executeColonizeCommand(
  state: var GameState,
  fleet: Fleet,
  command: FleetCommand,
  events: var seq[GameEvent],
): OrderOutcome

proc executeJoinFleetCommand(
  state: var GameState,
  fleet: Fleet,
  command: FleetCommand,
  events: var seq[GameEvent],
): OrderOutcome

proc executeRendezvousCommand(
  state: var GameState,
  fleet: Fleet,
  command: FleetCommand,
  events: var seq[GameEvent],
): OrderOutcome

proc executeSalvageCommand(
  state: var GameState,
  fleet: Fleet,
  command: FleetCommand,
  events: var seq[GameEvent],
): OrderOutcome

proc executeReserveCommand(
  state: var GameState,
  fleet: Fleet,
  command: FleetCommand,
  events: var seq[GameEvent],
): OrderOutcome

proc executeMothballCommand(
  state: var GameState,
  fleet: Fleet,
  command: FleetCommand,
  events: var seq[GameEvent],
): OrderOutcome

proc executeReactivateCommand(
  state: var GameState,
  fleet: Fleet,
  command: FleetCommand,
  events: var seq[GameEvent],
): OrderOutcome

proc executeViewCommand(
  state: var GameState,
  fleet: Fleet,
  command: FleetCommand,
  events: var seq[GameEvent],
): OrderOutcome

# =============================================================================
# Order Execution Dispatcher
# =============================================================================

proc executeFleetCommand*(
    state: var GameState,
    houseId: HouseId,
    command: FleetCommand,
    events: var seq[GameEvent],
): OrderOutcome =
  ## Main dispatcher for fleet command execution
  ## Routes to appropriate handler based on command type

  # Validate fleet exists
  let fleetOpt = state.fleet(command.fleetId)
  if fleetOpt.isNone:
    events.add(
      event_factory.commandFailed(
        houseId = houseId,
        fleetId = command.fleetId,
        orderType = $command.commandType,
        reason = "fleet not found",
        systemId = none(SystemId),
      )
    )
    return OrderOutcome.Failed

  let fleet = fleetOpt.get()

  # Validate fleet ownership
  if fleet.houseId != houseId:
    events.add(
      event_factory.commandFailed(
        houseId = houseId,
        fleetId = command.fleetId,
        orderType = $command.commandType,
        reason = "fleet not owned by house",
        systemId = some(fleet.location),
      )
    )
    return OrderOutcome.Failed

  # Route to command type handler
  case command.commandType
  of FleetCommandType.Hold:
    return executeHoldCommand(state, fleet, command, events)
  of FleetCommandType.Move:
    return executeMoveCommand(state, fleet, command, events)
  of FleetCommandType.SeekHome:
    return executeSeekHomeCommand(state, fleet, command, events)
  of FleetCommandType.Patrol:
    return executePatrolCommand(state, fleet, command, events)
  of FleetCommandType.GuardStarbase:
    return executeGuardStarbaseCommand(state, fleet, command, events)
  of FleetCommandType.GuardColony:
    return executeGuardColonyCommand(state, fleet, command, events)
  of FleetCommandType.Blockade:
    return executeBlockadeCommand(state, fleet, command, events)
  of FleetCommandType.Bombard:
    return executeBombardCommand(state, fleet, command, events)
  of FleetCommandType.Invade:
    return executeInvadeCommand(state, fleet, command, events)
  of FleetCommandType.Blitz:
    return executeBlitzCommand(state, fleet, command, events)
  of FleetCommandType.ScoutColony:
    return executeScoutColonyCommand(state, fleet, command, events)
  of FleetCommandType.HackStarbase:
    return executeHackStarbaseCommand(state, fleet, command, events)
  of FleetCommandType.ScoutSystem:
    return executeScoutSystemCommand(state, fleet, command, events)
  of FleetCommandType.Colonize:
    return executeColonizeCommand(state, fleet, command, events)
  of FleetCommandType.JoinFleet:
    return executeJoinFleetCommand(state, fleet, command, events)
  of FleetCommandType.Rendezvous:
    return executeRendezvousCommand(state, fleet, command, events)
  of FleetCommandType.Salvage:
    return executeSalvageCommand(state, fleet, command, events)
  of FleetCommandType.Reserve:
    return executeReserveCommand(state, fleet, command, events)
  of FleetCommandType.Mothball:
    return executeMothballCommand(state, fleet, command, events)
  of FleetCommandType.Reactivate:
    return executeReactivateCommand(state, fleet, command, events)
  of FleetCommandType.View:
    return executeViewCommand(state, fleet, command, events)

# =============================================================================
# Helper Functions
# =============================================================================

proc findNearestColonyFromList(
  state: GameState,
  fleet: Fleet,
  colonies: seq[SystemId]
): tuple[colonyId: SystemId, distance: int32] =
  ## Find nearest colony from a list using pathfinding
  ## Returns the closest colony and its distance
  ## Used to eliminate duplicate pathfinding-in-loop patterns
  result.colonyId = colonies[0]
  result.distance = int32.high

  for colonyId in colonies:
    let pathResult = movement.findPath(state, fleet.location, colonyId, fleet)
    if pathResult.found:
      let distance = int32(pathResult.path.len - 1)
      if distance < result.distance:
        result.distance = distance
        result.colonyId = colonyId

# =============================================================================
# Order 00: Hold Position
# =============================================================================

proc executeHoldCommand(
    state: var GameState,
    fleet: Fleet,
    command: FleetCommand,
    events: var seq[GameEvent],
): OrderOutcome =
  ## Order 00: Hold position and standby
  ## Always succeeds - fleet does nothing this turn

  # Silent - OrderIssued generated upstream
  return OrderOutcome.Success

# =============================================================================
# Order 01: Move Fleet
# =============================================================================

proc executeMoveCommand(
    state: var GameState,
    fleet: Fleet,
    command: FleetCommand,
    events: var seq[GameEvent],
): OrderOutcome =
  ## Order 01: Move to new system and hold position
  ## Calls resolveMovementCommand to execute actual movement with pathfinding

  # Per economy.md:3.9 - Reserve and Mothballed fleets cannot move
  if fleet.status == FleetStatus.Reserve:
    return OrderOutcome.Failed

  if fleet.status == FleetStatus.Mothballed:
    return OrderOutcome.Failed

  if command.targetSystem.isNone:
    return OrderOutcome.Failed

  # Execute actual movement using centralized movement arbiter
  mechanics.resolveMovementCommand(state, fleet.houseId, command, events)

  return OrderOutcome.Success

# =============================================================================
# Order 02: Seek Home
# =============================================================================

proc executeSeekHomeCommand(
    state: var GameState,
    fleet: Fleet,
    command: FleetCommand,
    events: var seq[GameEvent],
): OrderOutcome =
  ## Order 02: Find closest friendly colony and move there
  ## If that colony is conquered, find next closest

  # Find all friendly colonies
  # Use coloniesOwned iterator for O(1) indexed lookup
  var friendlyColonies: seq[SystemId] = @[]
  for colony in state.coloniesOwned(fleet.houseId):
    friendlyColonies.add(colony.systemId)

  if friendlyColonies.len == 0:
    # No friendly colonies - abort mission
    events.add(
      event_factory.commandAborted(
        fleet.houseId,
        fleet.id,
        "SeekHome",
        reason = "no friendly colonies available",
        systemId = some(fleet.location),
      )
    )
    return OrderOutcome.Aborted

  # Find closest colony using pathfinding
  let (closestColony, _) = findNearestColonyFromList(state, fleet, friendlyColonies)

  # Check if already at closest colony - mission complete
  if fleet.location == closestColony:
    events.add(
      event_factory.commandCompleted(
        fleet.houseId,
        fleet.id,
        "SeekHome",
        details = &"reached home at {closestColony}",
        systemId = some(closestColony),
      )
    )
    return OrderOutcome.Success

  # Create movement command to closest colony
  let moveOrder = FleetCommand(
    fleetId: fleet.id,
    commandType: FleetCommandType.Move,
    targetSystem: some(closestColony),
    targetFleet: none(FleetId),
    priority: command.priority,
  )

  # Execute movement (delegated to mechanics.resolveMovementCommand)
  var moveEvents: seq[GameEvent] = @[]
  mechanics.resolveMovementCommand(state, fleet.houseId, moveOrder, moveEvents)
  events.add(moveEvents)

  return OrderOutcome.Success

# =============================================================================
# Order 03: Patrol System
# =============================================================================

proc executePatrolCommand(
    state: var GameState,
    fleet: Fleet,
    command: FleetCommand,
    events: var seq[GameEvent],
): OrderOutcome =
  ## Order 03: Actively patrol system, engaging hostile forces
  ## Engagement rules per operations.md:6.2.4
  ## Persistent command - silent re-execution (only generates event on first execution)

  if command.targetSystem.isNone:
    events.add(
      event_factory.commandFailed(
        fleet.houseId,
        fleet.id,
        "Patrol",
        reason = "no target system specified",
        systemId = some(fleet.location),
      )
    )
    return OrderOutcome.Failed

  let targetSystem = command.targetSystem.get()

  # Check if target system lost (conquered by enemy)
  let colonyOpt = state.colonyBySystem(targetSystem)
  if colonyOpt.isSome:
    let colony = colonyOpt.get()
    if colony.owner != fleet.houseId:
      events.add(
        event_factory.commandAborted(
          fleet.houseId,
          fleet.id,
          "Patrol",
          reason = "target system no longer friendly",
          systemId = some(targetSystem),
        )
      )
      return OrderOutcome.Aborted

  # Persistent command - stays active, combat happens in Conflict Phase
  # Silent - no OrderCompleted spam (would generate every turn)
  return OrderOutcome.Success

# =============================================================================
# Order 04: Guard Starbase
# =============================================================================

proc executeGuardStarbaseCommand(
    state: var GameState,
    fleet: Fleet,
    command: FleetCommand,
    events: var seq[GameEvent],
): OrderOutcome =
  ## Order 04: Protect starbase, join Task Force when confronted
  ## Requires combat ships
  ## Persistent command - silent re-execution

  if command.targetSystem.isNone:
    events.add(
      event_factory.commandFailed(
        fleet.houseId,
        fleet.id,
        "GuardStarbase",
        reason = "no target system specified",
        systemId = some(fleet.location),
      )
    )
    return OrderOutcome.Failed

  # Check for combat capability
  let hasCombatShips = state.hasCombatShips(fleet)

  if not hasCombatShips:
    events.add(
      event_factory.commandFailed(
        fleet.houseId,
        fleet.id,
        "GuardStarbase",
        reason = "no combat-capable ships",
        systemId = some(fleet.location),
      )
    )
    return OrderOutcome.Failed

  let targetSystem = command.targetSystem.get()

  # Validate starbase presence and ownership
  let colonyOpt = state.colonyBySystem(targetSystem)
  if colonyOpt.isNone:
    events.add(
      event_factory.commandAborted(
        fleet.houseId,
        fleet.id,
        "GuardStarbase",
        reason = "target system has no colony",
        systemId = some(targetSystem),
      )
    )
    return OrderOutcome.Aborted

  let colony = colonyOpt.get()
  if colony.owner != fleet.houseId:
    events.add(
      event_factory.commandAborted(
        fleet.houseId,
        fleet.id,
        "GuardStarbase",
        reason = "colony no longer friendly",
        systemId = some(targetSystem),
      )
    )
    return OrderOutcome.Aborted

  if colony.kastraIds.len == 0:
    events.add(
      event_factory.commandAborted(
        fleet.houseId,
        fleet.id,
        "GuardStarbase",
        reason = "starbase destroyed",
        systemId = some(targetSystem),
      )
    )
    return OrderOutcome.Aborted

  # Persistent command - stays active, silent re-execution
  return OrderOutcome.Success

# =============================================================================
# Order 05: Guard/Blockade Planet
# =============================================================================

proc executeGuardColonyCommand(
    state: var GameState,
    fleet: Fleet,
    command: FleetCommand,
    events: var seq[GameEvent],
): OrderOutcome =
  ## Order 05 (Guard): Protect friendly colony, rear guard position
  ## Does not auto-join starbase Task Force (allows Raiders)
  ## Persistent command - silent re-execution

  if command.targetSystem.isNone:
    events.add(
      event_factory.commandFailed(
        fleet.houseId,
        fleet.id,
        "GuardPlanet",
        reason = "no target system specified",
        systemId = some(fleet.location),
      )
    )
    return OrderOutcome.Failed

  let targetSystem = command.targetSystem.get()

  # Check for combat capability
  let hasCombatShips = state.hasCombatShips(fleet)

  if not hasCombatShips:
    events.add(
      event_factory.commandFailed(
        fleet.houseId,
        fleet.id,
        "GuardPlanet",
        reason = "no combat-capable ships",
        systemId = some(fleet.location),
      )
    )
    return OrderOutcome.Failed

  # Check target colony still exists and is friendly
  let colonyOpt = state.colonyBySystem(targetSystem)
  if colonyOpt.isSome:
    let colony = colonyOpt.get()
    if colony.owner != fleet.houseId:
      events.add(
        event_factory.commandAborted(
          fleet.houseId,
          fleet.id,
          "GuardPlanet",
          reason = "colony no longer friendly",
          systemId = some(targetSystem),
        )
      )
      return OrderOutcome.Aborted

  # Persistent command - stays active, silent re-execution
  return OrderOutcome.Success

proc executeBlockadeCommand(
    state: var GameState,
    fleet: Fleet,
    command: FleetCommand,
    events: var seq[GameEvent],
): OrderOutcome =
  ## Order 05 (Blockade): Block enemy planet, reduce GCO by 60%
  ## Per operations.md:6.2.6 - Immediate effect during Income Phase
  ## Prestige penalty: -2 per turn if colony under blockade
  ## Persistent command - silent re-execution

  if command.targetSystem.isNone:
    events.add(
      event_factory.commandFailed(
        fleet.houseId,
        fleet.id,
        "BlockadePlanet",
        reason = "no target system specified",
        systemId = some(fleet.location),
      )
    )
    return OrderOutcome.Failed

  let targetSystem = command.targetSystem.get()

  # Check for combat capability
  let hasCombatShips = state.hasCombatShips(fleet)

  if not hasCombatShips:
    events.add(
      event_factory.commandFailed(
        fleet.houseId,
        fleet.id,
        "BlockadePlanet",
        reason = "no combat-capable ships",
        systemId = some(fleet.location),
      )
    )
    return OrderOutcome.Failed

  # Check target colony exists and is hostile
  let colonyOpt = state.colonyBySystem(targetSystem)
  if colonyOpt.isNone:
    events.add(
      event_factory.commandAborted(
        fleet.houseId,
        fleet.id,
        "BlockadePlanet",
        reason = "target system has no colony",
        systemId = some(targetSystem),
      )
    )
    return OrderOutcome.Aborted

  let colony = colonyOpt.get()
  if colony.owner == fleet.houseId:
    events.add(
      event_factory.commandAborted(
        fleet.houseId,
        fleet.id,
        "BlockadePlanet",
        reason = "cannot blockade own colony",
        systemId = some(targetSystem),
      )
    )
    return OrderOutcome.Aborted

  # Validate target house is not eliminated (leaderboard is public info)
  let targetHouseOpt = state.house(colony.owner)
  if targetHouseOpt.isSome:
    let targetHouse = targetHouseOpt.get()
    if targetHouse.isEliminated:
      events.add(
        event_factory.commandAborted(
          fleet.houseId,
          fleet.id,
          "BlockadePlanet",
          reason = "target house eliminated",
          systemId = some(targetSystem),
        )
      )
      return OrderOutcome.Aborted

  # NOTE: Blockade tracking not yet implemented in Colony type
  # Blockade effects are calculated dynamically during Income Phase by checking
  # for BlockadePlanet fleet commands at colony systems (see income.nim)
  # Future enhancement: Add blockaded: bool field to Colony type for faster lookups

  # Persistent command - stays active, silent re-execution
  return OrderOutcome.Success

# =============================================================================
# Order 06: Bombard Planet
# =============================================================================

proc executeBombardCommand(
    state: var GameState,
    fleet: Fleet,
    command: FleetCommand,
    events: var seq[GameEvent],
): OrderOutcome =
  ## Order 06: Orbital bombardment of planet
  ## Resolved in Conflict Phase - this marks intent

  if command.targetSystem.isNone:
    return OrderOutcome.Failed

  let targetSystem = command.targetSystem.get()

  # Check target colony exists
  let colonyOpt = state.colonyBySystem(targetSystem)
  if colonyOpt.isNone:
    return OrderOutcome.Failed

  let colony = colonyOpt.get()
  if colony.owner == fleet.houseId:
    return OrderOutcome.Failed

  # Validate target house is not eliminated (leaderboard is public info)
  let targetHouseOpt = state.house(colony.owner)
  if targetHouseOpt.isSome:
    let targetHouse = targetHouseOpt.get()
    if targetHouse.isEliminated:
      return OrderOutcome.Failed

  # Check for combat capability
  let hasCombatShips = state.hasCombatShips(fleet)

  if not hasCombatShips:
    return OrderOutcome.Failed

  return OrderOutcome.Success

# =============================================================================
# Order 07: Invade Planet
# =============================================================================

proc executeInvadeCommand(
    state: var GameState,
    fleet: Fleet,
    command: FleetCommand,
    events: var seq[GameEvent],
): OrderOutcome =
  ## Order 07: Three-round planetary invasion
  ## 1) Destroy ground batteries
  ## 2) Pound population/ground troops
  ## 3) Land Marines (if batteries destroyed)

  if command.targetSystem.isNone:
    return OrderOutcome.Failed

  let targetSystem = command.targetSystem.get()

  # Check target colony exists
  let colonyOpt = state.colonyBySystem(targetSystem)
  if colonyOpt.isNone:
    return OrderOutcome.Failed

  let colony = colonyOpt.get()
  if colony.owner == fleet.houseId:
    return OrderOutcome.Failed

  # Validate target house is not eliminated (leaderboard is public info)
  let targetHouseOpt = state.house(colony.owner)
  if targetHouseOpt.isSome:
    let targetHouse = targetHouseOpt.get()
    if targetHouse.isEliminated:
      return OrderOutcome.Failed

  # Check for combat ships and loaded troop transports
  let hasCombatShips = state.hasCombatShips(fleet)
  let hasLoadedTransports = state.hasLoadedMarines(fleet)

  if not hasCombatShips:
    return OrderOutcome.Failed

  if not hasLoadedTransports:
    return OrderOutcome.Failed

  return OrderOutcome.Success

# =============================================================================
# Order 08: Blitz Planet
# =============================================================================

proc executeBlitzCommand(
    state: var GameState,
    fleet: Fleet,
    command: FleetCommand,
    events: var seq[GameEvent],
): OrderOutcome =
  ## Order 08: Fast assault - dodge batteries, drop Marines
  ## Less planet damage, but requires 2:1 Marine superiority
  ## Per operations.md:6.2.9

  if command.targetSystem.isNone:
    return OrderOutcome.Failed

  let targetSystem = command.targetSystem.get()

  # Check target colony exists
  let colonyOpt = state.colonyBySystem(targetSystem)
  if colonyOpt.isNone:
    return OrderOutcome.Failed

  let colony = colonyOpt.get()
  if colony.owner == fleet.houseId:
    return OrderOutcome.Failed

  # Validate target house is not eliminated (leaderboard is public info)
  let targetHouseOpt = state.house(colony.owner)
  if targetHouseOpt.isSome:
    let targetHouse = targetHouseOpt.get()
    if targetHouse.isEliminated:
      return OrderOutcome.Failed

  # Check for loaded troop transports
  let hasLoadedTransports = state.hasLoadedMarines(fleet)

  if not hasLoadedTransports:
    return OrderOutcome.Failed

  return OrderOutcome.Success

# =============================================================================
# Order 09: Spy on Planet
# =============================================================================

proc executeScoutColonyCommand(
    state: var GameState,
    fleet: Fleet,
    command: FleetCommand,
    events: var seq[GameEvent],
): OrderOutcome =
  ## Order 09: Deploy scout to gather planet intelligence
  ## Reserved for solo Scout operations per operations.md:6.2.10

  if command.targetSystem.isNone:
    events.add(
      event_factory.commandFailed(
        fleet.houseId,
        fleet.id,
        "SpyPlanet",
        reason = "no target system specified",
        systemId = some(fleet.location),
      )
    )
    return OrderOutcome.Failed

  let targetSystem = command.targetSystem.get()

  # Validate target house is not eliminated (leaderboard is public info)
  let colonyOpt = state.colonyBySystem(targetSystem)
  if colonyOpt.isSome:
    let colony = colonyOpt.get()
    let targetHouseOpt = state.house(colony.owner)
    if targetHouseOpt.isSome:
      let targetHouse = targetHouseOpt.get()
      if targetHouse.isEliminated:
        events.add(
          event_factory.commandFailed(
            fleet.houseId,
            fleet.id,
            "SpyPlanet",
            reason = "target house eliminated",
            systemId = some(fleet.location),
          )
        )
        return OrderOutcome.Failed

  # Count scouts for mesh network bonus (validation already confirmed scout-only fleet)
  let scoutCount = int32(fleet.ships.len)

  # Set fleet mission state
  var updatedFleet = fleet
  updatedFleet.missionState = MissionState.Traveling
  updatedFleet.missionTarget = some(targetSystem)

  # Create movement command to target (if not already there)
  if fleet.location != targetSystem:
    # Calculate jump lane path from current location to target
    let pathResult = movement.findPath(state, fleet.location, targetSystem, fleet)

    if not pathResult.found:
      events.add(
        event_factory.commandFailed(
          fleet.houseId,
          fleet.id,
          "SpyPlanet",
          reason = "no path to target system",
          systemId = some(fleet.location),
        )
      )
      return OrderOutcome.Failed

    # Create movement command
    let travelCommand = FleetCommand(
      fleetId: fleet.id,
      commandType: FleetCommandType.Move,
      targetSystem: some(targetSystem),
      targetFleet: none(FleetId),
      priority: 0,
    )

    # Assign command to fleet (entity-manager pattern)
    updatedFleet.command = some(travelCommand)

    # Update fleet in state
    state.updateFleet(fleet.id, updatedFleet)

    # Generate command accepted event
    events.add(
      event_factory.commandCompleted(
        fleet.houseId,
        fleet.id,
        "SpyPlanet",
        details =
          &"scout fleet traveling to {targetSystem} for scout mission ({scoutCount} scouts)",
        systemId = some(fleet.location),
      )
    )
  else:
    # Already at target - start mission immediately
    updatedFleet.missionState = MissionState.ScoutLocked
    updatedFleet.missionStartTurn = state.turn
    # Mission data now stored on fleet entity (entity-manager pattern):
    # - command.commandType = ScoutColony
    # - missionTarget = targetSystem
    # - ships.len = scout count (scout-only fleets)

    # Update fleet in state
    state.updateFleet(fleet.id, updatedFleet)

    # Generate mission start event
    events.add(
      event_factory.commandCompleted(
        fleet.houseId,
        fleet.id,
        "SpyPlanet",
        details = &"scout mission started at {targetSystem} ({scoutCount} scouts)",
        systemId = some(targetSystem),
      )
    )

  return OrderOutcome.Success

# =============================================================================
# Order 10: Hack Starbase
# =============================================================================

proc executeHackStarbaseCommand(
    state: var GameState,
    fleet: Fleet,
    command: FleetCommand,
    events: var seq[GameEvent],
): OrderOutcome =
  ## Order 10: Electronic warfare against starbase
  ## Reserved for Scout operations per operations.md:6.2.11

  if command.targetSystem.isNone:
    events.add(
      event_factory.commandFailed(
        fleet.houseId,
        fleet.id,
        "HackStarbase",
        reason = "no target system specified",
        systemId = some(fleet.location),
      )
    )
    return OrderOutcome.Failed

  let targetSystem = command.targetSystem.get()

  # Validate starbase presence at target
  let colonyOpt = state.colonyBySystem(targetSystem)
  if colonyOpt.isNone:
    events.add(
      event_factory.commandFailed(
        fleet.houseId,
        fleet.id,
        "HackStarbase",
        reason = "target system has no colony",
        systemId = some(fleet.location),
      )
    )
    return OrderOutcome.Failed

  let colony = colonyOpt.get()
  if colony.kastraIds.len == 0:
    events.add(
      event_factory.commandFailed(
        fleet.houseId,
        fleet.id,
        "HackStarbase",
        reason = "target colony has no starbase",
        systemId = some(fleet.location),
      )
    )
    return OrderOutcome.Failed

  # Validate target house is not eliminated (leaderboard is public info)
  let targetHouseOpt = state.house(colony.owner)
  if targetHouseOpt.isSome:
    let targetHouse = targetHouseOpt.get()
    if targetHouse.isEliminated:
      events.add(
        event_factory.commandFailed(
          fleet.houseId,
          fleet.id,
          "HackStarbase",
          reason = "target house eliminated",
          systemId = some(fleet.location),
        )
      )
      return OrderOutcome.Failed

  # Count scouts for mission (validation already confirmed scout-only fleet)
  let scoutCount = int32(fleet.ships.len)

  # Set fleet mission state
  var updatedFleet = fleet
  updatedFleet.missionState = MissionState.Traveling
  updatedFleet.missionTarget = some(targetSystem)

  # Create movement command to target (if not already there)
  if fleet.location != targetSystem:
    # Calculate jump lane path from current location to target
    let pathResult = movement.findPath(state, fleet.location, targetSystem, fleet)

    if not pathResult.found:
      events.add(
        event_factory.commandFailed(
          fleet.houseId,
          fleet.id,
          "HackStarbase",
          reason = "no path to target system",
          systemId = some(fleet.location),
        )
      )
      return OrderOutcome.Failed

    # Create movement command
    let travelCommand = FleetCommand(
      fleetId: fleet.id,
      commandType: FleetCommandType.Move,
      targetSystem: some(targetSystem),
      targetFleet: none(FleetId),
      priority: 0,
    )

    # Assign command to fleet (entity-manager pattern)
    updatedFleet.command = some(travelCommand)

    # Update fleet in state
    state.updateFleet(fleet.id, updatedFleet)

    # Generate command accepted event
    events.add(
      event_factory.commandCompleted(
        fleet.houseId,
        fleet.id,
        "HackStarbase",
        details =
          &"scout fleet traveling to {targetSystem} to hack starbase ({scoutCount} scouts)",
        systemId = some(fleet.location),
      )
    )
  else:
    # Already at target - start mission immediately
    updatedFleet.missionState = MissionState.ScoutLocked
    updatedFleet.missionStartTurn = state.turn

    # Register active mission

    # Update fleet in state
    state.updateFleet(fleet.id, updatedFleet)

    # Generate mission start event
    events.add(
      event_factory.commandCompleted(
        fleet.houseId,
        fleet.id,
        "HackStarbase",
        details =
          &"starbase hack mission started at {targetSystem} ({scoutCount} scouts)",
        systemId = some(targetSystem),
      )
    )

  return OrderOutcome.Success

# =============================================================================
# Order 11: Spy on System
# =============================================================================

proc executeScoutSystemCommand(
    state: var GameState,
    fleet: Fleet,
    command: FleetCommand,
    events: var seq[GameEvent],
): OrderOutcome =
  ## Order 11: Deploy scout for system reconnaissance
  ## Reserved for solo Scout operations per operations.md:6.2.12

  if command.targetSystem.isNone:
    events.add(
      event_factory.commandFailed(
        fleet.houseId,
        fleet.id,
        "ScoutSystem",
        reason = "no target system specified",
        systemId = some(fleet.location),
      )
    )
    return OrderOutcome.Failed

  let targetSystem = command.targetSystem.get()

  # Validate target house is not eliminated (leaderboard is public info)
  let colonyOpt = state.colonyBySystem(targetSystem)
  if colonyOpt.isSome:
    let colony = colonyOpt.get()
    let targetHouseOpt = state.house(colony.owner)
    if targetHouseOpt.isSome:
      let targetHouse = targetHouseOpt.get()
      if targetHouse.isEliminated:
        events.add(
          event_factory.commandFailed(
            fleet.houseId,
            fleet.id,
            "ScoutSystem",
            reason = "target house eliminated",
            systemId = some(fleet.location),
          )
        )
        return OrderOutcome.Failed

  # Count scouts for mission (validation already confirmed scout-only fleet)
  let scoutCount = int32(fleet.ships.len)

  # Set fleet mission state
  var updatedFleet = fleet
  updatedFleet.missionState = MissionState.Traveling
  updatedFleet.missionTarget = some(targetSystem)

  # Create movement command to target (if not already there)
  if fleet.location != targetSystem:
    # Calculate jump lane path from current location to target
    let pathResult = movement.findPath(state, fleet.location, targetSystem, fleet)

    if not pathResult.found:
      events.add(
        event_factory.commandFailed(
          fleet.houseId,
          fleet.id,
          "ScoutSystem",
          reason = "no path to target system",
          systemId = some(fleet.location),
        )
      )
      return OrderOutcome.Failed

    # Create movement command
    let travelCommand = FleetCommand(
      fleetId: fleet.id,
      commandType: FleetCommandType.Move,
      targetSystem: some(targetSystem),
      targetFleet: none(FleetId),
      priority: 0,
    )

    # Assign command to fleet (entity-manager pattern)
    updatedFleet.command = some(travelCommand)

    # Update fleet in state
    state.updateFleet(fleet.id, updatedFleet)

    # Generate command accepted event
    events.add(
      event_factory.commandCompleted(
        fleet.houseId,
        fleet.id,
        "ScoutSystem",
        details =
          &"scout fleet traveling to {targetSystem} for system reconnaissance ({scoutCount} scouts)",
        systemId = some(fleet.location),
      )
    )
  else:
    # Already at target - start mission immediately
    updatedFleet.missionState = MissionState.ScoutLocked
    updatedFleet.missionStartTurn = state.turn

    # Register active mission

    # Update fleet in state
    state.updateFleet(fleet.id, updatedFleet)

    # Generate mission start event
    events.add(
      event_factory.commandCompleted(
        fleet.houseId,
        fleet.id,
        "ScoutSystem",
        details =
          &"system reconnaissance mission started at {targetSystem} ({scoutCount} scouts)",
        systemId = some(targetSystem),
      )
    )

  return OrderOutcome.Success

# =============================================================================
# Order 12: Colonize Planet
# =============================================================================

proc executeColonizeCommand(
    state: var GameState,
    fleet: Fleet,
    command: FleetCommand,
    events: var seq[GameEvent],
): OrderOutcome =
  ## Order 12: Establish colony with ETAC
  ## Reserved for ETAC under fleet escort per operations.md:6.2.13
  ## Calls resolveColonizationCommand to execute actual colonization

  if command.targetSystem.isNone:
    return OrderOutcome.Failed

  # Check fleet has ETAC with loaded colonists
  var hasLoadedETAC = false

  for shipId in fleet.ships:
    let shipOpt = state.ship(shipId)
    if shipOpt.isSome:
      let ship = shipOpt.get()
      if ship.shipClass == ShipClass.ETAC and ship.cargo.isSome:
        let cargo = ship.cargo.get()
        if cargo.cargoType == CargoClass.Colonists and cargo.quantity > 0:
          hasLoadedETAC = true
          break

  if not hasLoadedETAC:
    return OrderOutcome.Failed

  # Execute actual colonization using centralized colonization logic
  var colonizationEvents: seq[GameEvent] = @[]
  mechanics.resolveColonizationCommand(state, fleet.houseId, command, colonizationEvents)
  events.add(colonizationEvents)

  return OrderOutcome.Success

# =============================================================================
# Order 13: Join Fleet
# =============================================================================

proc executeJoinFleetCommand(
    state: var GameState,
    fleet: Fleet,
    command: FleetCommand,
    events: var seq[GameEvent],
): OrderOutcome =
  ## Order 13: Seek and merge with another fleet
  ## Old fleet disbands, ships join target
  ## Per operations.md:6.2.14
  ##
  ## SCOUT MESH NETWORK BENEFITS:
  ## When merging scout ships, they automatically gain mesh network ELI bonuses:
  ## - 2-3 scouts: +1 ELI bonus
  ## - 4-5 scouts: +2 ELI bonus
  ## - 6+ scouts: +3 ELI bonus (maximum)
  ## These bonuses apply to detection, counter-intelligence, and scout missions.
  ## See assets.md:2.4.2 for mesh network modifier table.

  if command.targetFleet.isNone:
    events.add(
      event_factory.commandFailed(
        fleet.houseId,
        fleet.id,
        "JoinFleet",
        reason = "no target fleet specified",
        systemId = some(fleet.location),
      )
    )
    return OrderOutcome.Failed

  let targetFleetId = command.targetFleet.get()

  # Target is a normal fleet
  let targetFleetOpt = state.fleet(targetFleetId)

  if targetFleetOpt.isNone:
    # Target fleet destroyed or deleted - clear the command
    let fleetOpt = state.fleet(fleet.id)
    if fleetOpt.isSome:
      var updatedFleet = fleetOpt.get()
      updatedFleet.command = none(FleetCommand)
      updatedFleet.missionState = MissionState.None
      state.updateFleet(fleet.id, updatedFleet)

    events.add(
      event_factory.commandAborted(
        houseId = fleet.houseId,
        fleetId = fleet.id,
        orderType = "JoinFleet",
        reason = "target fleet no longer exists",
        systemId = some(fleet.location),
      )
    )

    return OrderOutcome.Failed

  let targetFleet = targetFleetOpt.get()

  # Check same owner
  if targetFleet.houseId != fleet.houseId:
    events.add(
      event_factory.commandFailed(
        fleet.houseId,
        fleet.id,
        "JoinFleet",
        reason = "target fleet is not owned by same house",
        systemId = some(fleet.location),
      )
    )
    return OrderOutcome.Failed

  # Check if at same location - if not, move toward target
  if targetFleet.location != fleet.location:
    # Fleet will follow target - use centralized movement system
    # Create a movement command to target's current location
    let movementOrder = FleetCommand(
      fleetId: fleet.id,
      commandType: FleetCommandType.Move,
      targetSystem: some(targetFleet.location),
      targetFleet: none(FleetId),
      priority: command.priority,
    )

    # Use the centralized movement arbiter (handles all lane logic, pathfinding, etc.)
    # This respects DoD principles - movement logic in ONE place
    var events: seq[GameEvent] = @[]
    resolveMovementCommand(state, fleet.houseId, movementOrder, events)

    # Check if movement succeeded by comparing fleet location
    let updatedFleetOpt = state.fleet(fleet.id)
    if updatedFleetOpt.isNone:
      return OrderOutcome.Failed

    let movedFleet = updatedFleetOpt.get()

    # Check if fleet actually moved (pathfinding succeeded)
    if movedFleet.location == fleet.location:
      # Fleet didn't move - no path found to target
      # Cancel command
      var updatedFleet = movedFleet
      updatedFleet.command = none(FleetCommand)
      updatedFleet.missionState = MissionState.None
      state.updateFleet(fleet.id, updatedFleet)

      events.add(
        event_factory.commandAborted(
          houseId = fleet.houseId,
          fleetId = fleet.id,
          orderType = "JoinFleet",
          reason = "cannot reach target",
          systemId = some(fleet.location),
        )
      )

      return OrderOutcome.Failed

    # If still not at target location, keep command persistent
    if movedFleet.location != targetFleet.location:
      # Keep the Join Fleet command active so it continues pursuit next turn
      # Order remains in fleetCommands table
      # Silent - ongoing pursuit
      return OrderOutcome.Success

    # If we got here, fleet reached target - fall through to merge logic below

  # At same location - merge ships into target fleet
  var updatedTargetFleet = targetFleet
  for shipId in fleet.ships:
    updatedTargetFleet.ships.add(shipId)

  state.updateFleet(targetFleetId, updatedTargetFleet)

  # Remove source fleet using state accessor (UFCS)
  state.delFleet(fleet.id)

  logInfo(
    "Fleet",
    "Fleet " & $fleet.id & " merged into fleet " & $targetFleetId &
      " (source fleet removed)",
  )

  # Generate OrderCompleted event for successful fleet merge
  events.add(
    event_factory.commandCompleted(
      fleet.houseId,
      fleet.id,
      "JoinFleet",
      details = &"merged into fleet {targetFleetId}",
      systemId = some(fleet.location),
    )
  )

  return OrderOutcome.Success

# =============================================================================
# Order 14: Rendezvous
# =============================================================================

proc executeRendezvousCommand(
    state: var GameState,
    fleet: Fleet,
    command: FleetCommand,
    events: var seq[GameEvent],
): OrderOutcome =
  ## Order 14: Move to system and merge with other rendezvous fleets
  ## Lowest fleet ID becomes host
  ## Per operations.md:6.2.15
  ##
  ## SCOUT MESH NETWORK BENEFITS:
  ## When multiple scout ships rendezvous, they automatically gain mesh network ELI bonuses:
  ## - 2-3 scouts: +1 ELI bonus
  ## - 4-5 scouts: +2 ELI bonus
  ## - 6+ scouts: +3 ELI bonus (maximum)
  ## All ships (including scouts) from all rendezvous fleets are merged into the host fleet.
  ## See assets.md:2.4.2 for mesh network modifier table.

  if command.targetSystem.isNone:
    events.add(
      event_factory.commandFailed(
        fleet.houseId,
        fleet.id,
        "Rendezvous",
        reason = "no target system specified",
        systemId = some(fleet.location),
      )
    )
    return OrderOutcome.Failed

  let targetSystem = command.targetSystem.get()

  # Check if rendezvous point has hostile forces (enemy/neutral fleets)
  # Check for hostile forces at rendezvous point
  let houseOpt = state.house(fleet.houseId)
  if houseOpt.isSome:
    for otherFleet in state.fleetsInSystem(targetSystem):
      if otherFleet.houseId != fleet.houseId:
        # Check diplomatic relation
        var relation = DiplomaticState.Neutral # Default
        if (fleet.houseId, otherFleet.houseId) in state.diplomaticRelation:
          relation = state.diplomaticRelation[(fleet.houseId, otherFleet.houseId)].state

        if relation == DiplomaticState.Enemy:
          # Hostile forces at rendezvous - abort
          events.add(
            event_factory.commandAborted(
              fleet.houseId,
              fleet.id,
              "Rendezvous",
              reason = "hostile forces present at rendezvous point",
              systemId = some(fleet.location),
            )
          )
          return OrderOutcome.Aborted

  # Check if rendezvous point colony is enemy-controlled (additional check)
  let colonyOpt = state.colonyBySystem(targetSystem)
  if colonyOpt.isSome:
    let colony = colonyOpt.get()
    if colony.owner != fleet.houseId:
      # Check diplomatic relation
      var relation = DiplomaticState.Neutral # Default
      if (fleet.houseId, colony.owner) in state.diplomaticRelation:
        relation = state.diplomaticRelation[(fleet.houseId, colony.owner)].state

      if relation == DiplomaticState.Enemy:
        # Rendezvous point is enemy territory - abort
        events.add(
          event_factory.commandAborted(
            fleet.houseId,
            fleet.id,
            "Rendezvous",
            reason = "rendezvous point is enemy-controlled",
            systemId = some(fleet.location),
          )
        )
        return OrderOutcome.Aborted

  # Check if fleet is at rendezvous point
  if fleet.location != targetSystem:
    # Still moving to rendezvous
    return OrderOutcome.Success

  # Find other fleets at rendezvous with same command at same location
  # Use fleetsInSystem iterator for O(1) indexed lookup
  var rendezvousFleets: seq[Fleet] = @[]
  rendezvousFleets.add(fleet)

  # Collect all fleets with Rendezvous commands at this system
  for otherFleet in state.fleetsInSystem(targetSystem):
    if otherFleet.id == fleet.id:
      continue # Skip self

    # Check if owned by same house
    if otherFleet.houseId == fleet.houseId:
      # Check if has Rendezvous command to same system
      if otherFleet.command.isSome:
        let otherCommand = otherFleet.command.get()
        if otherCommand.commandType == FleetCommandType.Rendezvous and
            otherCommand.targetSystem.isSome and
            otherCommand.targetSystem.get() == targetSystem:
          rendezvousFleets.add(otherFleet)

  # If only this fleet, wait for others
  if rendezvousFleets.len == 1:
    # Silent - waiting
    return OrderOutcome.Success

  # Multiple fleets at rendezvous - merge into lowest ID fleet
  var lowestId = fleet.id
  for f in rendezvousFleets:
    if uint32(f.id) < uint32(lowestId):
      lowestId = f.id

  # Get host fleet using state accessor (UFCS)
  var hostFleet = state.fleet(lowestId).get()

  # Merge all other fleets into host
  var mergedCount = 0
  for f in rendezvousFleets:
    if f.id == lowestId:
      continue # Skip host

    # Merge ships from all fleets
    for shipId in f.ships:
      hostFleet.ships.add(shipId)

    # Remove merged fleet using state accessor (UFCS)
    state.delFleet(f.id)

    mergedCount += 1
    logInfo(
      "Fleet",
      "Fleet " & $f.id & " merged into rendezvous host " & $lowestId &
        " (source fleet removed)",
    )

  # Update host fleet using state accessor (UFCS)
  state.updateFleet(lowestId, hostFleet)

  # Generate OrderCompleted event for successful rendezvous
  var details = &"{mergedCount} fleet(s) merged"

  events.add(
    event_factory.commandCompleted(
      fleet.houseId,
      lowestId,
      "Rendezvous",
      details = details,
      systemId = some(targetSystem),
    )
  )

  return OrderOutcome.Success

# =============================================================================
# Order 15: Salvage
# =============================================================================

proc executeSalvageCommand(
    state: var GameState,
    fleet: Fleet,
    command: FleetCommand,
    events: var seq[GameEvent],
): OrderOutcome =
  ## Order 15: Salvage fleet at closest friendly colony with spaceport or shipyard
  ## Fleet disbands, ships salvaged for 50% PC
  ## Per operations.md:6.2.16
  ##
  ## AUTOMATIC EXECUTION: This command executes immediately when given
  ## FACILITIES: Works at colonies with either spaceport OR shipyard

  # Find closest friendly colony with salvage facilities (spaceport or shipyard)
  var closestColony: Option[SystemId] = none(SystemId)

  # Check if fleet is currently at a friendly colony with facilities
  let currentColonyOpt = state.colonyBySystem(fleet.location)
  if currentColonyOpt.isSome:
    let colony = currentColonyOpt.get()
    let hasFacilities = state.countSpaceportsAtColony(colony.id) > 0 or
                        state.countShipyardsAtColony(colony.id) > 0

    if colony.owner == fleet.houseId and hasFacilities:
      # Already at a suitable colony - use it immediately
      closestColony = some(fleet.location)

  # If not at suitable colony, search all owned colonies for one with facilities
  # Note: For simplicity, we take the first colony with facilities found
  # A more sophisticated implementation would use pathfinding to find truly closest
  # Use coloniesOwned iterator for O(1) indexed lookup
  if closestColony.isNone:
    for colony in state.coloniesOwned(fleet.houseId):
      # Check if colony has salvage facilities (neorias)
      let hasFacilities = state.countSpaceportsAtColony(colony.id) > 0 or
                          state.countShipyardsAtColony(colony.id) > 0

      if hasFacilities:
        closestColony = some(colony.systemId)
        break

  if closestColony.isNone:
    events.add(
      event_factory.commandFailed(
        fleet.houseId,
        fleet.id,
        "Salvage",
        reason = "no friendly colonies with salvage facilities (spaceport or shipyard)",
        systemId = some(fleet.location),
      )
    )
    return OrderOutcome.Failed

  # Calculate salvage value (50% of ship PC per operations.md:6.2.16)
  var salvageValue: int32 = 0
  for shipId in fleet.ships:
    let shipOpt = state.ship(shipId)
    if shipOpt.isSome:
      let ship = shipOpt.get()
      salvageValue += (ship_entity.buildCost(ship) div 2)

  # Add salvage PP to house treasury
  let houseOpt = state.house(fleet.houseId)
  if houseOpt.isSome:
    var house = houseOpt.get()
    house.treasury += salvageValue
    state.updateHouse(fleet.houseId, house)

  # Generate event
  let targetSystem = closestColony.get()

  # Remove fleet from game state using state accessor (UFCS)
  state.delFleet(fleet.id)

  # Generate OrderCompleted event for salvage operation
  events.add(
    event_factory.commandCompleted(
      fleet.houseId,
      fleet.id,
      "Salvage",
      details = &"recovered {salvageValue} PP from {fleet.ships.len} ship(s)",
      systemId = some(targetSystem),
    )
  )

  return OrderOutcome.Success

# =============================================================================
# Reserve / Mothball / Reactivate Orders
# =============================================================================

proc executeReserveCommand(
    state: var GameState,
    fleet: Fleet,
    command: FleetCommand,
    events: var seq[GameEvent],
): OrderOutcome =
  ## Place fleet on Reserve status (50% maintenance, half AS/DS, can't move)
  ## Per economy.md:3.9
  ## If not at friendly colony, auto-seeks nearest friendly colony first

  # Check if already at a friendly colony
  var atFriendlyColony = false
  let currentColonyOpt = state.colonyBySystem(fleet.location)
  if currentColonyOpt.isSome:
    let colony = currentColonyOpt.get()
    if colony.owner == fleet.houseId:
      atFriendlyColony = true

  # If not at friendly colony, find closest one and move there
  if not atFriendlyColony:
    # Find all friendly colonies
    var friendlyColonies: seq[SystemId] = @[]
    for colony in state.coloniesOwned(fleet.houseId):
      friendlyColonies.add(colony.systemId)

    if friendlyColonies.len == 0:
      return OrderOutcome.Failed

    # Find closest colony using pathfinding
    let (closestColony, _) = findNearestColonyFromList(state, fleet, friendlyColonies)

    # Not at colony yet - move toward it
    if fleet.location != closestColony:
      # Create movement command to target colony
      let moveOrder = FleetCommand(
        fleetId: fleet.id,
        commandType: FleetCommandType.Move,
        targetSystem: some(closestColony),
        targetFleet: none(FleetId),
        priority: command.priority,
      )

      # Use centralized movement arbiter
      var events: seq[GameEvent] = @[]
      resolveMovementCommand(state, fleet.houseId, moveOrder, events)

      # Check if fleet moved
      let updatedFleetOpt = state.fleet(fleet.id)
      if updatedFleetOpt.isNone:
        return OrderOutcome.Failed

      let movedFleet = updatedFleetOpt.get()

      # Check if actually moved (pathfinding succeeded)
      if movedFleet.location == fleet.location:
        # Fleet didn't move - no path found
        events.add(
          event_factory.commandFailed(
            houseId = fleet.houseId,
            fleetId = fleet.id,
            orderType = "Reserve",
            reason = "cannot reach colony",
            systemId = some(fleet.location),
          )
        )
        return OrderOutcome.Failed

      # Keep command persistent - will execute when fleet arrives
      # Silent - movement in progress
      return OrderOutcome.Success

  # At friendly colony - apply reserve status
  var updatedFleet = fleet
  updatedFleet.status = FleetStatus.Reserve
  state.updateFleet(fleet.id, updatedFleet)

  # Generate OrderCompleted event for state change
  events.add(
    event_factory.commandCompleted(
      fleet.houseId,
      fleet.id,
      "Reserve",
      details = "placed on reserve status",
      systemId = some(fleet.location),
    )
  )

  return OrderOutcome.Success

proc executeMothballCommand(
    state: var GameState,
    fleet: Fleet,
    command: FleetCommand,
    events: var seq[GameEvent],
): OrderOutcome =
  ## Mothball fleet (0% maintenance, offline, screened in combat)
  ## Per economy.md:3.9
  ## If not at friendly colony with spaceport, auto-seeks nearest one first

  # Check if already at a friendly colony with spaceport
  var atFriendlyColonyWithSpaceport = false
  let colonyOpt = state.colonyBySystem(fleet.location)
  if colonyOpt.isSome:
    let colony = colonyOpt.get()
    if colony.owner == fleet.houseId and colony.neoriaIds.len > 0:
      atFriendlyColonyWithSpaceport = true

  # If not at friendly colony with spaceport, find closest one and move there
  if not atFriendlyColonyWithSpaceport:
    # Find all friendly colonies with spaceports (neoria facilities)
    var friendlyColoniesWithSpaceports: seq[SystemId] = @[]
    for colony in state.coloniesOwned(fleet.houseId):
      if colony.neoriaIds.len > 0:
        friendlyColoniesWithSpaceports.add(colony.systemId)

    if friendlyColoniesWithSpaceports.len == 0:
      return OrderOutcome.Failed

    # Find closest colony using pathfinding
    let (closestColony, _) = findNearestColonyFromList(state, fleet, friendlyColoniesWithSpaceports)

    # Not at colony yet - move toward it
    if fleet.location != closestColony:
      # Create movement command to target colony
      let moveOrder = FleetCommand(
        fleetId: fleet.id,
        commandType: FleetCommandType.Move,
        targetSystem: some(closestColony),
        targetFleet: none(FleetId),
        priority: command.priority,
      )

      # Use centralized movement arbiter
      var events: seq[GameEvent] = @[]
      resolveMovementCommand(state, fleet.houseId, moveOrder, events)

      # Check if fleet moved
      let updatedFleetOpt = state.fleet(fleet.id)
      if updatedFleetOpt.isNone:
        return OrderOutcome.Failed

      let movedFleet = updatedFleetOpt.get()

      # Check if actually moved (pathfinding succeeded)
      if movedFleet.location == fleet.location:
        # Fleet didn't move - no path found
        events.add(
          event_factory.commandFailed(
            houseId = fleet.houseId,
            fleetId = fleet.id,
            orderType = "Mothball",
            reason = "cannot reach colony",
            systemId = some(fleet.location),
          )
        )
        return OrderOutcome.Failed

      # Keep command persistent - will execute when fleet arrives
      # Silent - movement in progress
      return OrderOutcome.Success

  # At friendly colony with spaceport - apply mothball status
  var updatedFleet = fleet
  updatedFleet.status = FleetStatus.Mothballed
  state.updateFleet(fleet.id, updatedFleet)

  # Generate OrderCompleted event for state change
  events.add(
    event_factory.commandCompleted(
      fleet.houseId,
      fleet.id,
      "Mothball",
      details = "mothballed",
      systemId = some(fleet.location),
    )
  )

  return OrderOutcome.Success

proc executeReactivateCommand(
    state: var GameState,
    fleet: Fleet,
    command: FleetCommand,
    events: var seq[GameEvent],
): OrderOutcome =
  ## Return reserve or mothballed fleet to active duty

  if fleet.status == FleetStatus.Active:
    events.add(
      event_factory.commandFailed(
        houseId = fleet.houseId,
        fleetId = fleet.id,
        orderType = "Reactivate",
        reason = "fleet already active",
        systemId = some(fleet.location),
      )
    )
    return OrderOutcome.Failed

  # Change status to Active
  var updatedFleet = fleet
  updatedFleet.status = FleetStatus.Active
  state.updateFleet(fleet.id, updatedFleet)

  # Generate OrderCompleted event for state change
  events.add(
    event_factory.commandCompleted(
      fleet.houseId,
      fleet.id,
      "Reactivate",
      details = "reactivated",
      systemId = some(fleet.location),
    )
  )

  return OrderOutcome.Success

# =============================================================================
# Order 19: View World (Long-Range Planetary Reconnaissance)
# =============================================================================

proc executeViewCommand(
    state: var GameState,
    fleet: Fleet,
    command: FleetCommand,
    events: var seq[GameEvent],
): OrderOutcome =
  ## Order 19: Perform long-range scan of planet from system edge
  ## Gathers: planet owner (if colonized) + planet class (production potential)
  ## Resolution logic handled by resolveViewWorldCommand in fleet_orders.nim

  if command.targetSystem.isNone:
    events.add(
      event_factory.commandFailed(
        fleet.houseId,
        fleet.id,
        "ViewWorld",
        reason = "no target system specified",
        systemId = some(fleet.location),
      )
    )
    return OrderOutcome.Failed

  return OrderOutcome.Success
