## Per-Game Database Writer
##
## Unified persistence layer for per-game databases.
## Each game has its own database at data/games/{uuid}/ec4x.db
##
## Architecture:
## - Schema created by createGameDatabase() in daemon/persistence/init.nim
## - This module only handles INSERT operations
## - No table creation (schema.nim owns that)
## - Uses GameState.dbPath for database location
##
## DRY Principle: Single implementation for each entity type
## DoD Principle: Pure functions operating on GameState data

import std/[options, strutils]
import db_connector/db_sqlite
import ../../common/logger
import ../../engine/types/[event, game_state]

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
    SET turn = ?, phase = ?, updated_at = unixepoch()
    WHERE id = ?
  """,
    $state.turn,
    $state.phase,
    state.gameId,
  )

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
        command_type, description, reason, event_data
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
    )
  db.exec(sql"COMMIT")

  logDebug(
    "Persistence", "Saved game events", "count=", $events.len, " turn=", $state.turn
  )
