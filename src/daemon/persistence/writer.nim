## Per-Game Database Writer
##
## Unified persistence layer for per-game databases.
## Each game has its own database at data/games/{slug}/ec4x.db
##
## Architecture:
## - Schema created by createGameDatabase() in daemon/persistence/init.nim
## - This module handles state persistence using msgpack serialization
## - No table creation (schema.nim owns that)
## - Uses GameState.dbPath for database location
##
## Migration: Switched from JSON to msgpack for GameState persistence
## - Faster serialization (2-5x)
## - Smaller storage (30-50%)
## - Type-safe binary format

import std/[options, strutils, tables, times]
import kdl
import db_connector/db_sqlite
import ../../common/logger
import ../../engine/types/[event, game_state, core, command, tech, espionage]
import ./replay
import ../transport/nostr/types
import ./msgpack_state
import ./player_state_snapshot

proc paramsKdl(
    props: Table[string, KdlVal],
    children: seq[KdlNode] = @[]): string =
  if props.len == 0 and children.len == 0:
    return ""
  let node = initKNode("params", props = props, children = children)
  let doc: KdlDoc = @[node]
  $doc

proc addProp(props: var Table[string, KdlVal], key: string, value: KdlVal) =
  props[key] = value

# ============================================================================
# Core State Writers
# ============================================================================

proc updateGameMetadata*(state: GameState) =
  ## Update games table with current turn/phase info
  ## Called after each turn resolution
  let db = open(state.dbPath, "", "", "")
  defer: db.close()

  db.exec(
    sql"""
    UPDATE games
    SET turn = ?, updated_at = unixepoch()
    WHERE id = ?
  """,
    $state.turn,
    state.gameId,
  )

proc updateTurnDeadline*(dbPath: string, gameId: string,
  deadline: Option[int64]) =
  ## Update the per-turn deadline timestamp (unix seconds)
  let db = open(dbPath, "", "", "")
  defer: db.close()

  let deadlineValue = if deadline.isSome: $deadline.get() else: "NULL"
  if deadline.isSome:
    db.exec(
      sql"""
      UPDATE games
      SET turn_deadline = ?, updated_at = unixepoch()
      WHERE id = ?
    """,
      deadlineValue,
      gameId
    )
  else:
    db.exec(
      sql"""
      UPDATE games
      SET turn_deadline = NULL, updated_at = unixepoch()
      WHERE id = ?
    """,
      gameId
    )

# Note: House pubkey and invite codes are now stored in GameState
# and persisted via saveFullState(). No separate UPDATE needed.

proc savePlayerStateSnapshot*(
  dbPath: string,
  gameId: string,
  houseId: HouseId,
  turn: int32,
  snapshot: PlayerStateSnapshot
) =
  ## Persist per-house PlayerState snapshot for delta generation
  let db = open(dbPath, "", "", "")
  defer: db.close()

  let stateMsgpack = snapshotToMsgpack(snapshot)
  db.exec(
    sql"""
    INSERT INTO player_state_snapshots (
      game_id, house_id, turn, state_msgpack, created_at
    ) VALUES (?, ?, ?, ?, unixepoch())
    ON CONFLICT(game_id, house_id, turn) DO UPDATE SET
      state_msgpack=excluded.state_msgpack
    """,
    gameId,
    $houseId.uint32,
    $turn,
    stateMsgpack
  )
  logDebug("Persistence", "Saved player state snapshot for house ", $houseId, " turn ", $turn)

proc insertProcessedEvent*(dbPath: string, gameId: string, turn: int32,
  kind: int, eventId: string, direction: ReplayDirection) =
  ## Record a processed event id
  let db = open(dbPath, "", "", "")
  defer: db.close()

  db.exec(
    sql"""
    INSERT OR IGNORE INTO nostr_event_log (
      game_id, turn, kind, event_id, direction, created_at
    ) VALUES (?, ?, ?, ?, ?, unixepoch())
    """,
    gameId,
    $turn,
    $kind,
    eventId,
    $(direction.ord)
  )

proc cleanupProcessedEvents*(dbPath: string, gameId: string, currentTurn: int32,
  commandRetentionTurns: int, eventRetentionDays: int,
  definitionRetentionDays: int, stateRetentionDays: int) =
  ## Remove old replay protection entries.
  let db = open(dbPath, "", "", "")
  defer: db.close()

  if commandRetentionTurns <= 0:
    logWarn("Persistence", "Replay retention not applied for game ", gameId)
    return

  let effectiveEventDays = if eventRetentionDays > 0: eventRetentionDays else: 0
  let effectiveDefinitionDays = if definitionRetentionDays > 0:
    definitionRetentionDays
  else:
    0
  let effectiveStateDays = if stateRetentionDays > 0: stateRetentionDays else: 0

  let minTurn = currentTurn - int32(commandRetentionTurns - 1)
  let nowUnix = getTime().toUnix()
  let eventCutoff = nowUnix - int64(effectiveEventDays * 24 * 60 * 60)
  let definitionCutoff = nowUnix -
    int64(effectiveDefinitionDays * 24 * 60 * 60)
  let stateCutoff = nowUnix - int64(effectiveStateDays * 24 * 60 * 60)

  db.exec(
    sql"""
    DELETE FROM nostr_event_log
    WHERE game_id = ? AND kind = ? AND turn < ?
    """,
    gameId,
    $EventKindTurnCommands,
    $minTurn
  )

  if effectiveEventDays > 0:
    db.exec(
      sql"""
      DELETE FROM nostr_event_log
      WHERE game_id = ? AND kind NOT IN (?, ?) AND created_at < ?
      """,
      gameId,
      $EventKindGameDefinition,
      $EventKindGameState,
      $eventCutoff
    )

  if effectiveDefinitionDays > 0:
    db.exec(
      sql"""
      DELETE FROM nostr_event_log
      WHERE game_id = ? AND kind = ? AND created_at < ?
      """,
      gameId,
      $EventKindGameDefinition,
      $definitionCutoff
    )

  if effectiveStateDays > 0:
    db.exec(
      sql"""
      DELETE FROM nostr_event_log
      WHERE game_id = ? AND kind = ? AND created_at < ?
      """,
      gameId,
      $EventKindGameState,
      $stateCutoff
    )

proc saveFullState*(state: GameState) =
  ## Persist complete GameState to database as msgpack blob
  ## This replaces the old JSON-based entity table persistence
  let db = open(state.dbPath, "", "", "")
  defer: db.close()

  db.exec(sql"BEGIN TRANSACTION")
  try:
    # Serialize entire GameState to msgpack
    let blob = serializeGameState(state)

    # Update games table with msgpack blob and current turn
    db.exec(
      sql"""
      UPDATE games
      SET state_msgpack = ?, turn = ?, updated_at = unixepoch()
      WHERE id = ?
      """,
      blob,
      $state.turn,
      state.gameId
    )

    db.exec(sql"COMMIT")
    logInfo("Persistence", "Saved full game state (msgpack)", "turn=", $state.turn, " size=", $blob.len, " bytes")
  except:
    db.exec(sql"ROLLBACK")
    logError("Persistence", "Failed to save game state: ", getCurrentExceptionMsg())
    raise



# ============================================================================
# Event Writers
# ============================================================================

proc saveGameEvent*(state: GameState, event: GameEvent) =
  ## Insert game event into per-game database
  ## Called during event processing
  let db = open(state.dbPath, "", "", "")
  defer: db.close()

  # Extract optional fields
  let houseIdStr = if event.houseId.isSome: $event.houseId.get().uint32 else: ""
  let fleetIdStr = if event.fleetId.isSome: $event.fleetId.get().uint32 else: ""
  let systemIdStr = if event.systemId.isSome: $event.systemId.get().uint32 else: ""

  # Serialize event-specific data as JSON (placeholder for now)
  let eventDataJson = "{}"

  db.exec(
    sql"""
    INSERT INTO game_events (
      game_id, turn, event_type, house_id, fleet_id, system_id,
      command_type, description, reason, event_data
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  """,
    state.gameId,
    $event.turn,
    $event.eventType,
    houseIdStr,
    fleetIdStr,
    systemIdStr,
    "", # commandType (extract from event if needed)
    event.description,
    "", # reason (extract from event if needed)
    eventDataJson,
  )

proc saveCommandPacket*(dbPath: string, gameId: string, packet: CommandPacket) =
  ## Persist a command packet to the database
  let db = open(dbPath, "", "", "")
  defer: db.close()
  
  db.exec(sql"BEGIN TRANSACTION")
  try:
    # 1. Fleet Commands
    for cmd in packet.fleetCommands:
      var props = initTable[string, KdlVal]()
      if cmd.roe.isSome:
        addProp(props, "roe", initKVal(cmd.roe.get()))
      if cmd.priority != 0:
        addProp(props, "priority", initKVal(cmd.priority))
      let params = paramsKdl(props)
      db.exec(sql"""
        INSERT INTO commands (
          game_id, house_id, turn, fleet_id, command_type, 
          target_system_id, target_fleet_id, params, submitted_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, unixepoch())
        ON CONFLICT(game_id, turn, house_id, fleet_id, colony_id, command_type) 
        DO UPDATE SET
          command_type=excluded.command_type,
          target_system_id=excluded.target_system_id,
          target_fleet_id=excluded.target_fleet_id,
          params=excluded.params,
          submitted_at=excluded.submitted_at
      """,
        gameId, $packet.houseId, packet.turn, $cmd.fleetId, $cmd.commandType,
        if cmd.targetSystem.isSome: $cmd.targetSystem.get else: "",
        if cmd.targetFleet.isSome: $cmd.targetFleet.get else: "",
        $params
      )
    
    # 2. Build Commands
    for cmd in packet.buildCommands:
      var props = initTable[string, KdlVal]()
      addProp(props, "buildType", initKVal($cmd.buildType))
      addProp(props, "quantity", initKVal(cmd.quantity))
      if cmd.industrialUnits != 0:
        addProp(props, "industrialUnits", initKVal(cmd.industrialUnits))
      if cmd.shipClass.isSome:
        addProp(props, "shipClass", initKVal($cmd.shipClass.get()))
      if cmd.facilityClass.isSome:
        addProp(props, "facilityClass", initKVal($cmd.facilityClass.get()))
      if cmd.groundClass.isSome:
        addProp(props, "groundClass", initKVal($cmd.groundClass.get()))
      let params = paramsKdl(props)
      db.exec(sql"""
        INSERT INTO commands (
          game_id, house_id, turn, colony_id, command_type, params, submitted_at
        ) VALUES (?, ?, ?, ?, 'Build', ?, unixepoch())
        ON CONFLICT(game_id, turn, house_id, fleet_id, colony_id, command_type)
        DO UPDATE SET
          params=excluded.params,
          submitted_at=excluded.submitted_at
      """,
        gameId, $packet.houseId, packet.turn, $cmd.colonyId, $params
      )

    # 3. Research Allocation
    if packet.researchAllocation.economic > 0 or
        packet.researchAllocation.science > 0 or
        packet.researchAllocation.technology.len > 0:
      var props = initTable[string, KdlVal]()
      addProp(props, "economic", initKVal(packet.researchAllocation.economic))
      addProp(props, "science", initKVal(packet.researchAllocation.science))
      var children: seq[KdlNode] = @[]
      if packet.researchAllocation.technology.len > 0:
        var techNode = initKNode("technology")
        for field, points in packet.researchAllocation.technology:
          techNode.children.add(
            initKNode($field, args = @[initKVal(points)])
          )
        children.add(techNode)
      let params = paramsKdl(props, children)
      db.exec(sql"""
        INSERT INTO commands (
          game_id, house_id, turn, command_type, params, submitted_at
        ) VALUES (?, ?, ?, 'Research', ?, unixepoch())
        ON CONFLICT(game_id, turn, house_id, fleet_id, colony_id, command_type)
        DO UPDATE SET
          params=excluded.params,
          submitted_at=excluded.submitted_at
      """,
        gameId, $packet.houseId, packet.turn, $params
      )

    # 4. Espionage Budget
    if packet.ebpInvestment > 0 or packet.cipInvestment > 0:
      var props = initTable[string, KdlVal]()
      if packet.ebpInvestment > 0:
        addProp(props, "ebpInvestment", initKVal(packet.ebpInvestment))
      if packet.cipInvestment > 0:
        addProp(props, "cipInvestment", initKVal(packet.cipInvestment))
      let params = paramsKdl(props)
      db.exec(sql"""
        INSERT INTO commands (
          game_id, house_id, turn, command_type, params, submitted_at
        ) VALUES (?, ?, ?, 'EspionageBudget', ?, unixepoch())
        ON CONFLICT(game_id, turn, house_id, fleet_id, colony_id, command_type)
        DO UPDATE SET
          params=excluded.params,
          submitted_at=excluded.submitted_at
      """,
        gameId, $packet.houseId, packet.turn, $params
      )

    # 5. Espionage Actions
    for action in packet.espionageActions:
      var props = initTable[string, KdlVal]()
      addProp(props, "attacker", initKVal(action.attacker.uint32))
      addProp(props, "target", initKVal(action.target.uint32))
      addProp(props, "action", initKVal($action.action))
      if action.targetSystem.isSome:
        addProp(
          props,
          "targetSystem",
          initKVal(action.targetSystem.get().uint32)
        )
      let params = paramsKdl(props)
      db.exec(sql"""
        INSERT INTO commands (
          game_id, house_id, turn, command_type, params, submitted_at
        ) VALUES (?, ?, ?, 'EspionageAction', ?, unixepoch())
        ON CONFLICT(game_id, turn, house_id, fleet_id, colony_id, command_type)
        DO UPDATE SET
          params=excluded.params,
          submitted_at=excluded.submitted_at
      """,
        gameId, $packet.houseId, packet.turn, $params
      )

    # 6. Diplomatic Commands
    for cmd in packet.diplomaticCommand:
      var props = initTable[string, KdlVal]()
      addProp(props, "targetHouse", initKVal(cmd.targetHouse.uint32))
      addProp(props, "actionType", initKVal($cmd.actionType))
      if cmd.proposalId.isSome:
        addProp(props, "proposalId", initKVal(cmd.proposalId.get().uint32))
      if cmd.proposalType.isSome:
        addProp(props, "proposalType", initKVal($cmd.proposalType.get()))
      if cmd.message.isSome:
        addProp(props, "message", initKVal(cmd.message.get()))
      let params = paramsKdl(props)
      db.exec(sql"""
        INSERT INTO commands (
          game_id, house_id, turn, command_type, params, submitted_at
        ) VALUES (?, ?, ?, 'Diplomatic', ?, unixepoch())
        ON CONFLICT(game_id, turn, house_id, fleet_id, colony_id, command_type)
        DO UPDATE SET
          params=excluded.params,
          submitted_at=excluded.submitted_at
      """,
        gameId, $packet.houseId, packet.turn, $params
      )

    db.exec(sql"COMMIT")
    logInfo("Persistence", "Saved command packet for house ", $packet.houseId, " turn ", $packet.turn)
  except:
    db.exec(sql"ROLLBACK")
    logError("Persistence", "Failed to save command packet: ", getCurrentExceptionMsg())
    raise

proc markCommandsProcessed*(dbPath: string, gameId: string, turn: int32) =
  ## Mark all commands for a turn as processed
  let db = open(dbPath, "", "", "")
  defer: db.close()
  db.exec(sql"UPDATE commands SET processed = 1 WHERE game_id = ? AND turn = ?", gameId, $turn)
  logInfo("Persistence", "Marked commands as processed for turn ", $turn)

proc saveGameEvents*(state: GameState, events: seq[GameEvent]) =
  ## Batch insert game events (more efficient than individual inserts)
  ## Called after turn resolution
  if events.len == 0:
    return

  let db = open(state.dbPath, "", "", "")
  defer: db.close()

  db.exec(sql"BEGIN TRANSACTION")
  for event in events:
    let houseIdStr = if event.houseId.isSome: $event.houseId.get().uint32 else: ""
    let fleetIdStr = if event.fleetId.isSome: $event.fleetId.get().uint32 else: ""
    let systemIdStr = if event.systemId.isSome: $event.systemId.get().uint32 else: ""
    let eventDataJson = "{}"

    db.exec(
      sql"""
      INSERT INTO game_events (
        game_id, turn, event_type, house_id, fleet_id, system_id,
        command_type, description, reason, event_data, created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """,
      state.gameId,
      $event.turn,
      $event.eventType,
      houseIdStr,
      fleetIdStr,
      systemIdStr,
      "",
      event.description,
      "",
      eventDataJson,
      $epochTime(),
    )
  db.exec(sql"COMMIT")

  logDebug(
    "Persistence", "Saved game events", "count=", $events.len, " turn=", $state.turn
  )
