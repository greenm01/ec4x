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

import std/[options, strutils, tables, json, jsonutils, times]
import db_connector/db_sqlite
import ../../common/logger
import ../../engine/types/[event, game_state, core, house, starmap, colony, fleet, ship, diplomacy, command, tech, espionage]
import ../transport/nostr/types
import ./player_state_snapshot
import ./reader

# ============================================================================
# JSON Helpers for Distinct Types
# ============================================================================

proc `%`*(id: HouseId): JsonNode = %(id.uint32)
proc `%`*(id: SystemId): JsonNode = %(id.uint32)
proc `%`*(id: ColonyId): JsonNode = %(id.uint32)
proc `%`*(id: FleetId): JsonNode = %(id.uint32)
proc `%`*(id: ShipId): JsonNode = %(id.uint32)

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

proc updateHousePubkey*(dbPath: string, gameId: string, houseId: HouseId, pubkey: string) =
  ## Update a house's Nostr pubkey (for slot claims)
  let db = open(dbPath, "", "", "")
  defer: db.close()

  db.exec(
    sql"""
    UPDATE houses
    SET nostr_pubkey = ?
    WHERE game_id = ? AND id = ?
  """,
    pubkey,
    gameId,
    $houseId.uint32,
  )
  logInfo("Persistence", "Updated house ", $houseId, " with pubkey ", pubkey)

proc updateHouseInviteCode*(dbPath: string, gameId: string, houseId: HouseId,
  code: string) =
  ## Update a house invite code
  let db = open(dbPath, "", "", "")
  defer: db.close()

  db.exec(
    sql"""
    UPDATE houses
    SET invite_code = ?
    WHERE game_id = ? AND id = ?
  """,
    code,
    gameId,
    $houseId.uint32,
  )
  logDebug("Persistence", "Updated invite code for house ", $houseId)

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

  let stateJson = snapshotToJson(snapshot)
  db.exec(
    sql"""
    INSERT INTO player_state_snapshots (
      game_id, house_id, turn, state_json, created_at
    ) VALUES (?, ?, ?, ?, unixepoch())
    ON CONFLICT(game_id, house_id, turn) DO UPDATE SET
      state_json=excluded.state_json
    """,
    gameId,
    $houseId.uint32,
    $turn,
    stateJson
  )
  logDebug("Persistence", "Saved player state snapshot for house ", $houseId, " turn ", $turn)

proc insertProcessedEvent*(dbPath: string, gameId: string, turn: int32,
  kind: int, eventId: string, direction: reader.ReplayDirection) =
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
  commandRetentionTurns: int, eventRetentionDays: int) =
  ## Remove old replay protection entries.
  let db = open(dbPath, "", "", "")
  defer: db.close()

  if commandRetentionTurns <= 0 or eventRetentionDays <= 0:
    logWarn("Persistence", "Replay retention not applied for game ", gameId)
    return

  let minTurn = currentTurn - int32(commandRetentionTurns - 1)
  let eventCutoff = getTime().toUnix() -
    int64(eventRetentionDays * 24 * 60 * 60)

  db.exec(
    sql"""
    DELETE FROM nostr_event_log
    WHERE game_id = ? AND kind = ? AND turn < ?
    """,
    gameId,
    $EventKindTurnCommands,
    $minTurn
  )

  db.exec(
    sql"""
    DELETE FROM nostr_event_log
    WHERE game_id = ? AND kind != ? AND created_at < ?
    """,
    gameId,
    $EventKindTurnCommands,
    $eventCutoff
  )

proc saveHouses(db: DbConn, state: GameState) =
  for house in state.houses.entities.data:
    let techJson = $toJson(house.techTree)
    let stateJson = $toJson(house) # Serialize full object for safety/extras
    
    db.exec(sql"""
      INSERT INTO houses (
        id, game_id, name, prestige, treasury, eliminated, 
        tech_json, state_json, created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, unixepoch())
      ON CONFLICT(id) DO UPDATE SET
        prestige=excluded.prestige,
        treasury=excluded.treasury,
        eliminated=excluded.eliminated,
        tech_json=excluded.tech_json,
        state_json=excluded.state_json
    """,
      $house.id,
      state.gameId,
      house.name,
      house.prestige,
      house.treasury,
      if house.isEliminated: 1 else: 0,
      techJson,
      stateJson
    )

proc saveSystems(db: DbConn, state: GameState) =
  for system in state.systems.entities.data:
    # System.owner is removed from engine, use NULL or derived from colony
    
    db.exec(sql"""
      INSERT INTO systems (
        id, game_id, name, hex_q, hex_r, ring, planet_class, resource_rating, owner_house_id, created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL, unixepoch())
      ON CONFLICT(id) DO UPDATE SET
        name=excluded.name,
        planet_class=excluded.planet_class,
        resource_rating=excluded.resource_rating
    """,
      $system.id,
      state.gameId,
      system.name,
      system.coords.q,
      system.coords.r,
      system.ring,
      ord(system.planetClass),
      ord(system.resourceRating)
    )

proc saveLanes(db: DbConn, state: GameState) =
  # Lanes are in state.starMap.lanes.data
  # Table lanes has id (auto), game_id, from, to, type.
  # We should clear and re-insert or upsert?
  # Lanes are static mostly, but can change?
  # Unique constraint on (game_id, from, to).
  for lane in state.starMap.lanes.data:
    db.exec(sql"""
      INSERT INTO lanes (
        game_id, from_system_id, to_system_id, lane_type, created_at
      ) VALUES (?, ?, ?, ?, unixepoch())
      ON CONFLICT(game_id, from_system_id, to_system_id) DO UPDATE SET
        lane_type=excluded.lane_type
    """,
      state.gameId,
      $lane.source,
      $lane.destination,
      $lane.laneType
    )

proc saveColonies(db: DbConn, state: GameState) =
  for colony in state.colonies.entities.data:
    let stateJson = $toJson(colony)
    db.exec(sql"""
      INSERT INTO colonies (
        id, game_id, system_id, owner_house_id, population, industry, defenses,
        starbase_level, tax_rate, auto_repair, under_siege, state_json,
        created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, unixepoch(), unixepoch())
      ON CONFLICT(id) DO UPDATE SET
        population=excluded.population,
        industry=excluded.industry,
        defenses=excluded.defenses,
        starbase_level=excluded.starbase_level,
        tax_rate=excluded.tax_rate,
        auto_repair=excluded.auto_repair,
        under_siege=excluded.under_siege,
        state_json=excluded.state_json,
        updated_at=unixepoch()
    """,
      $colony.id,
      state.gameId,
      $colony.systemId,
      $colony.owner,
      colony.population,
      colony.industrial.units, 
      colony.infrastructure, 
      0, # starbase_level
      colony.taxRate,
      if colony.autoRepair: 1 else: 0,
      if colony.blockaded: 1 else: 0, 
      stateJson
    )
    
proc saveFleets(db: DbConn, state: GameState) =
  for fleet in state.fleets.entities.data:
    let stateJson = $toJson(fleet)
    db.exec(sql"""
      INSERT INTO fleets (
        id, game_id, owner_house_id, location_system_id, name, state_json,
        created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, unixepoch(), unixepoch())
      ON CONFLICT(id) DO UPDATE SET
        owner_house_id=excluded.owner_house_id,
        location_system_id=excluded.location_system_id,
        name=excluded.name,
        state_json=excluded.state_json,
        updated_at=unixepoch()
    """,
      $fleet.id,
      state.gameId,
      $fleet.houseId,
      $fleet.location,
      "", # name not in Fleet object
      stateJson
    )

proc saveShips(db: DbConn, state: GameState) =
  for ship in state.ships.entities.data:
    let stateJson = $toJson(ship)
    db.exec(sql"""
      INSERT INTO ships (
        id, fleet_id, ship_type, hull_points, max_hull_points, state_json,
        created_at
      ) VALUES (?, ?, ?, ?, ?, ?, unixepoch())
      ON CONFLICT(id) DO UPDATE SET
        fleet_id=excluded.fleet_id,
        hull_points=excluded.hull_points,
        state_json=excluded.state_json
    """,
      $ship.id,
      $ship.fleetId,
      $ship.shipClass, 
      0, # hull_points (not tracked)
      0, # max_hull_points (not tracked)
      stateJson
    )

proc saveFullState*(state: GameState) =
  ## Persist all game entities to the database
  let db = open(state.dbPath, "", "", "")
  defer: db.close()

  db.exec(sql"BEGIN TRANSACTION")
  try:
    updateGameMetadata(state)
    saveHouses(db, state)
    saveSystems(db, state)
    saveLanes(db, state)
    saveColonies(db, state)
    saveFleets(db, state)
    saveShips(db, state)
    db.exec(sql"COMMIT")
    logInfo("Persistence", "Saved full game state", "turn=", $state.turn)
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
      let params = %*{
        "roe": cmd.roe,
        "priority": cmd.priority
      }
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
      let params = %*cmd
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

    # TODO: Other command types (Research, Espionage, etc.)
    
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
