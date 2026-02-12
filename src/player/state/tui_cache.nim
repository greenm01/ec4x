## TUI Client-Side Cache
##
## Provides local SQLite cache for the TUI client, separate from the daemon's
## authoritative database. This enables the TUI to run on a different machine
## from the daemon.
##
## Cache location: ~/.local/share/ec4x/cache.db
##
## Tables:
##   - settings: Global settings (default relay, schema version)
##   - games: Game metadata from Nostr events
##   - player_slots: Player's house assignments per game
##   - player_states: PlayerState snapshots per game/turn (msgpack encoded)
##   - intel_notes: Per-system player notes (local-only annotations)
##   - received_events: Nostr event deduplication

import std/[os, options, times, strutils, base64, tables]
import db_connector/db_sqlite
import kdl
import msgpack4nim

import ../../common/logger
import ../../engine/types/player_state

const
  SchemaVersion* = 2  # Bumped for msgpack migration
  DefaultCacheDir* = ".local/share/ec4x"
  CacheFileName* = "cache.db"

type
  TuiCache* = ref object
    db: DbConn
    path: string

  CachedGame* = object
    id*: string
    name*: string
    turn*: int
    status*: string
    relayUrl*: string
    daemonPubkey*: string
    lastUpdated*: int64

  PlayerSlot* = object
    gameId*: string
    playerPubkey*: string
    houseId*: int
    joinedAt*: int64

# =============================================================================
# Cache Path
# =============================================================================

proc getCacheDir*(): string =
  ## Get the cache directory path (XDG compliant)
  let home = getHomeDir()
  home / DefaultCacheDir

proc getCachePath*(): string =
  ## Get the full cache database path
  getCacheDir() / CacheFileName

# =============================================================================
# Schema Management
# =============================================================================

proc checkAndMigrateSchema(db: DbConn): bool =
  ## Check schema version and migrate if needed.
  ## Returns true if a fresh schema was created (old data cleared).
  var needsReset = false
  
  try:
    let row = db.getRow(
      sql"SELECT value FROM settings WHERE key = 'schema_version'"
    )
    if row[0] != "":
      let version = parseInt(row[0])
      if version < SchemaVersion:
        logInfo("TuiCache", "Schema version ", $version, " -> ", $SchemaVersion,
          ", clearing old data")
        needsReset = true
  except CatchableError:
    # Table doesn't exist yet, will be created fresh
    needsReset = false
  
  if needsReset:
    # Drop old tables before recreating
    db.exec(sql"DROP TABLE IF EXISTS player_states")
    db.exec(sql"DROP TABLE IF EXISTS intel_notes")
    db.exec(sql"DROP TABLE IF EXISTS received_events")
    db.exec(sql"DROP TABLE IF EXISTS player_slots")
    db.exec(sql"DROP TABLE IF EXISTS games")
    db.exec(sql"DROP TABLE IF EXISTS settings")
  
  needsReset

proc initSchema(db: DbConn, forceInit: bool = false) =
  ## Initialize the cache database schema
  
  # Settings table
  db.exec(sql"""
    CREATE TABLE IF NOT EXISTS settings (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )
  """)
  
  # Games table (from Nostr kind 30400)
  db.exec(sql"""
    CREATE TABLE IF NOT EXISTS games (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      turn INTEGER NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'unknown',
      relay_url TEXT,
      daemon_pubkey TEXT,
      last_updated INTEGER NOT NULL
    )
  """)
  
  # Player slots table
  db.exec(sql"""
    CREATE TABLE IF NOT EXISTS player_slots (
      game_id TEXT NOT NULL,
      player_pubkey TEXT NOT NULL,
      house_id INTEGER NOT NULL,
      joined_at INTEGER NOT NULL,
      PRIMARY KEY (game_id, player_pubkey),
      FOREIGN KEY (game_id) REFERENCES games(id) ON DELETE CASCADE
    )
  """)
  
  # Player states table (msgpack blob stored as base64)
  db.exec(sql"""
    CREATE TABLE IF NOT EXISTS player_states (
      game_id TEXT NOT NULL,
      house_id INTEGER NOT NULL,
      turn INTEGER NOT NULL,
      state_msgpack TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      PRIMARY KEY (game_id, house_id, turn)
    )
  """)

  # Intel notes table (local player annotations)
  db.exec(sql"""
    CREATE TABLE IF NOT EXISTS intel_notes (
      game_id TEXT NOT NULL,
      house_id INTEGER NOT NULL,
      system_id INTEGER NOT NULL,
      note_text TEXT NOT NULL,
      updated_at INTEGER NOT NULL,
      PRIMARY KEY (game_id, house_id, system_id)
    )
  """)
  
  # Received events table (deduplication)
  db.exec(sql"""
    CREATE TABLE IF NOT EXISTS received_events (
      event_id TEXT PRIMARY KEY,
      kind INTEGER NOT NULL,
      game_id TEXT,
      created_at INTEGER NOT NULL
    )
  """)
  
  # Indexes
  db.exec(sql"""
    CREATE INDEX IF NOT EXISTS idx_player_slots_pubkey
    ON player_slots(player_pubkey)
  """)
  
  db.exec(sql"""
    CREATE INDEX IF NOT EXISTS idx_player_states_game_house
    ON player_states(game_id, house_id)
  """)

  db.exec(sql"""
    CREATE INDEX IF NOT EXISTS idx_intel_notes_game_house
    ON intel_notes(game_id, house_id)
  """)
  
  db.exec(sql"""
    CREATE INDEX IF NOT EXISTS idx_received_events_game
    ON received_events(game_id)
  """)
  
  # Insert default settings if not exists
  db.exec(sql"""
    INSERT OR IGNORE INTO settings (key, value)
    VALUES ('schema_version', ?)
  """, $SchemaVersion)
  
  db.exec(sql"""
    INSERT OR IGNORE INTO settings (key, value)
    VALUES ('default_relay', '')
  """)

# =============================================================================
# Cache Open/Close
# =============================================================================

proc openTuiCache*(): TuiCache =
  ## Open the TUI cache database, creating it if necessary.
  ## Automatically handles schema migrations (clears old data if needed).
  let cacheDir = getCacheDir()
  createDir(cacheDir)
  
  let cachePath = getCachePath()
  let db = open(cachePath, "", "", "")
  
  let wasReset = checkAndMigrateSchema(db)
  initSchema(db, wasReset)
  
  TuiCache(db: db, path: cachePath)

proc close*(cache: TuiCache) =
  ## Close the cache database
  if cache != nil and cache.db != nil:
    cache.db.close()

proc deleteCacheFile*(): bool =
  ## Delete cache database file if it exists
  let path = getCachePath()
  if fileExists(path):
    removeFile(path)
    return true
  false

proc clearCacheGames*(): bool =
  ## Clear game-related tables while keeping settings
  if not fileExists(getCachePath()):
    return false
  let cache = openTuiCache()
  defer: cache.close()
  cache.db.exec(sql"DELETE FROM player_states")
  cache.db.exec(sql"DELETE FROM intel_notes")
  cache.db.exec(sql"DELETE FROM player_slots")
  cache.db.exec(sql"DELETE FROM games")
  cache.db.exec(sql"DELETE FROM received_events")
  true

proc clearCacheGame*(gameId: string): bool =
  ## Clear a specific game from the cache
  if gameId.len == 0 or not fileExists(getCachePath()):
    return false
  let cache = openTuiCache()
  defer: cache.close()
  cache.db.exec(sql"DELETE FROM player_states WHERE game_id = ?", gameId)
  cache.db.exec(sql"DELETE FROM intel_notes WHERE game_id = ?", gameId)
  cache.db.exec(sql"DELETE FROM player_slots WHERE game_id = ?", gameId)
  cache.db.exec(sql"DELETE FROM games WHERE id = ?", gameId)
  cache.db.exec(sql"DELETE FROM received_events WHERE game_id = ?", gameId)
  true

# =============================================================================
# Settings Operations
# =============================================================================

proc getSetting*(cache: TuiCache, key: string): string =
  ## Get a setting value, empty string if not found
  let row = cache.db.getRow(
    sql"SELECT value FROM settings WHERE key = ?",
    key
  )
  if row[0] == "":
    ""
  else:
    row[0]

proc setSetting*(cache: TuiCache, key, value: string) =
  ## Set a setting value
  cache.db.exec(sql"""
    INSERT INTO settings (key, value) VALUES (?, ?)
    ON CONFLICT(key) DO UPDATE SET value = excluded.value
  """, key, value)

proc getDefaultRelay*(cache: TuiCache): string =
  ## Get the default relay URL
  cache.getSetting("default_relay")

proc setDefaultRelay*(cache: TuiCache, relayUrl: string) =
  ## Set the default relay URL
  cache.setSetting("default_relay", relayUrl)

# =============================================================================
# Game Operations
# =============================================================================

proc upsertGame*(cache: TuiCache, id, name: string, turn: int,
                 status: string, relayUrl: string = "",
                 daemonPubkey: string = "") =
  ## Insert or update a game in the cache
  let now = epochTime().int64
  cache.db.exec(sql"""
    INSERT INTO games (id, name, turn, status, relay_url, daemon_pubkey,
                       last_updated)
    VALUES (?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET
      name = excluded.name,
      turn = excluded.turn,
      status = excluded.status,
      relay_url = COALESCE(NULLIF(excluded.relay_url, ''), relay_url),
      daemon_pubkey = COALESCE(NULLIF(excluded.daemon_pubkey, ''),
                               daemon_pubkey),
      last_updated = excluded.last_updated
  """, id, name, $turn, status, relayUrl, daemonPubkey, $now)

proc getGame*(cache: TuiCache, id: string): Option[CachedGame] =
  ## Get a game by ID
  let row = cache.db.getRow(
    sql"""SELECT id, name, turn, status, relay_url, daemon_pubkey,
                 last_updated
          FROM games WHERE id = ?""",
    id
  )
  if row[0] == "":
    return none(CachedGame)
  
  some(CachedGame(
    id: row[0],
    name: row[1],
    turn: parseInt(row[2]),
    status: row[3],
    relayUrl: row[4],
    daemonPubkey: row[5],
    lastUpdated: parseBiggestInt(row[6])
  ))

proc listGames*(cache: TuiCache): seq[CachedGame] =
  ## List all games in cache
  result = @[]
  for row in cache.db.fastRows(
    sql"""SELECT id, name, turn, status, relay_url, daemon_pubkey,
                 last_updated
          FROM games ORDER BY last_updated DESC"""
  ):
    result.add(CachedGame(
      id: row[0],
      name: row[1],
      turn: parseInt(row[2]),
      status: row[3],
      relayUrl: row[4],
      daemonPubkey: row[5],
      lastUpdated: parseBiggestInt(row[6])
    ))

proc deleteGame*(cache: TuiCache, id: string) =
  ## Delete a game from cache
  cache.db.exec(sql"DELETE FROM intel_notes WHERE game_id = ?", id)
  cache.db.exec(sql"DELETE FROM games WHERE id = ?", id)

# =============================================================================
# Player Slot Operations
# =============================================================================

proc insertPlayerSlot*(cache: TuiCache, gameId, playerPubkey: string,
                       houseId: int) =
  ## Insert or update a player's slot assignment
  let now = epochTime().int64
  cache.db.exec(sql"""
    INSERT INTO player_slots (game_id, player_pubkey, house_id, joined_at)
    VALUES (?, ?, ?, ?)
    ON CONFLICT(game_id, player_pubkey) DO UPDATE SET
      house_id = excluded.house_id
  """, gameId, playerPubkey, $houseId, $now)

proc getPlayerSlot*(cache: TuiCache, gameId, playerPubkey: string):
    Option[PlayerSlot] =
  ## Get a player's slot for a game
  let row = cache.db.getRow(
    sql"""SELECT game_id, player_pubkey, house_id, joined_at
          FROM player_slots
          WHERE game_id = ? AND player_pubkey = ?""",
    gameId, playerPubkey
  )
  if row[0] == "":
    return none(PlayerSlot)
  
  some(PlayerSlot(
    gameId: row[0],
    playerPubkey: row[1],
    houseId: parseInt(row[2]),
    joinedAt: parseBiggestInt(row[3])
  ))

proc listPlayerGames*(cache: TuiCache, playerPubkey: string):
    seq[tuple[game: CachedGame, houseId: int]] =
  ## List all games a player has joined with their house assignments
  result = @[]
  for row in cache.db.fastRows(
    sql"""SELECT g.id, g.name, g.turn, g.status, g.relay_url,
                 g.daemon_pubkey, g.last_updated, ps.house_id
          FROM games g
          JOIN player_slots ps ON g.id = ps.game_id
          WHERE ps.player_pubkey = ?
          ORDER BY g.last_updated DESC""",
    playerPubkey
  ):
    result.add((
      game: CachedGame(
        id: row[0],
        name: row[1],
        turn: parseInt(row[2]),
        status: row[3],
        relayUrl: row[4],
        daemonPubkey: row[5],
        lastUpdated: parseBiggestInt(row[6])
      ),
      houseId: parseInt(row[7])
    ))

proc deletePlayerSlot*(cache: TuiCache, gameId, playerPubkey: string) =
  ## Delete a player's slot
  cache.db.exec(sql"""
    DELETE FROM player_slots
    WHERE game_id = ? AND player_pubkey = ?
  """, gameId, playerPubkey)

# =============================================================================
# Player State Operations
# =============================================================================

proc savePlayerState*(cache: TuiCache, gameId: string, houseId: int,
                      turn: int, state: PlayerState) =
  ## Save a PlayerState snapshot using msgpack serialization
  let now = epochTime().int64
  let binary = pack(state)
  let payload = encode(binary)  # base64 for SQLite text storage
  cache.db.exec(sql"""
    INSERT INTO player_states (game_id, house_id, turn, state_msgpack, created_at)
    VALUES (?, ?, ?, ?, ?)
    ON CONFLICT(game_id, house_id, turn) DO UPDATE SET
      state_msgpack = excluded.state_msgpack
  """, gameId, $houseId, $turn, payload, $now)

proc loadPlayerState*(cache: TuiCache, gameId: string, houseId: int,
                      turn: int): Option[PlayerState] =
  ## Load a specific PlayerState snapshot
  let row = cache.db.getRow(
    sql"""SELECT state_msgpack FROM player_states
          WHERE game_id = ? AND house_id = ? AND turn = ?""",
    gameId, $houseId, $turn
  )
  if row[0] == "":
    return none(PlayerState)
  
  try:
    let binary = decode(row[0])
    some(unpack(binary, PlayerState))
  except CatchableError as e:
    logError("TuiCache", "Failed to parse player state: ", e.msg)
    none(PlayerState)

proc loadLatestPlayerState*(cache: TuiCache, gameId: string,
                            houseId: int): Option[PlayerState] =
  ## Load the latest PlayerState snapshot for a game/house
  let row = cache.db.getRow(
    sql"""SELECT state_msgpack FROM player_states
          WHERE game_id = ? AND house_id = ?
          ORDER BY turn DESC LIMIT 1""",
    gameId, $houseId
  )
  if row[0] == "":
    return none(PlayerState)
  
  try:
    let binary = decode(row[0])
    some(unpack(binary, PlayerState))
  except CatchableError as e:
    logError("TuiCache", "Failed to parse player state: ", e.msg)
    none(PlayerState)

proc pruneOldPlayerStates*(cache: TuiCache, gameId: string, houseId: int,
                           keepTurns: int = 10) =
  ## Prune old PlayerState snapshots, keeping only the last N turns
  cache.db.exec(sql"""
    DELETE FROM player_states
    WHERE game_id = ? AND house_id = ? AND turn NOT IN (
      SELECT turn FROM player_states
      WHERE game_id = ? AND house_id = ?
      ORDER BY turn DESC LIMIT ?
    )
  """, gameId, $houseId, gameId, $houseId, $keepTurns)

# =============================================================================
# Intel Note Operations
# =============================================================================

proc saveIntelNote*(cache: TuiCache, gameId: string, houseId: int,
                    systemId: int, noteText: string) =
  ## Save or update a local intel note for a specific system.
  let now = epochTime().int64
  cache.db.exec(sql"""
    INSERT INTO intel_notes (game_id, house_id, system_id, note_text,
                             updated_at)
    VALUES (?, ?, ?, ?, ?)
    ON CONFLICT(game_id, house_id, system_id) DO UPDATE SET
      note_text = excluded.note_text,
      updated_at = excluded.updated_at
  """, gameId, $houseId, $systemId, noteText, $now)

proc loadIntelNote*(cache: TuiCache, gameId: string, houseId: int,
                    systemId: int): Option[string] =
  ## Load a specific intel note.
  let row = cache.db.getRow(
    sql"""SELECT note_text FROM intel_notes
          WHERE game_id = ? AND house_id = ? AND system_id = ?""",
    gameId, $houseId, $systemId
  )
  if row[0] == "":
    return none(string)
  some(row[0])

proc loadIntelNotes*(cache: TuiCache, gameId: string,
                     houseId: int): Table[int, string] =
  ## Load all intel notes for a game/house keyed by system ID.
  result = initTable[int, string]()
  for row in cache.db.fastRows(
      sql"""SELECT system_id, note_text FROM intel_notes
            WHERE game_id = ? AND house_id = ?""",
      gameId, $houseId
  ):
    result[parseInt(row[0])] = row[1]

# =============================================================================
# Event Deduplication
# =============================================================================

proc hasReceivedEvent*(cache: TuiCache, eventId: string): bool =
  ## Check if we've already received an event
  let row = cache.db.getRow(
    sql"SELECT 1 FROM received_events WHERE event_id = ?",
    eventId
  )
  row[0] != ""

proc markEventReceived*(cache: TuiCache, eventId: string, kind: int,
                        gameId: string = "") =
  ## Mark an event as received
  let now = epochTime().int64
  cache.db.exec(sql"""
    INSERT OR IGNORE INTO received_events (event_id, kind, game_id, created_at)
    VALUES (?, ?, ?, ?)
  """, eventId, $kind, gameId, $now)

proc pruneOldEvents*(cache: TuiCache, keepCount: int = 1000) =
  ## Prune old received events, keeping only the last N
  cache.db.exec(sql"""
    DELETE FROM received_events
    WHERE event_id NOT IN (
      SELECT event_id FROM received_events
      ORDER BY created_at DESC LIMIT ?
    )
  """, $keepCount)

proc pruneStaleGames*(
    cache: TuiCache,
    maxAgeDays: int,
    stateGraceDays: int = 30) =
  ## Remove cached games with no recent updates or player state.
  if maxAgeDays <= 0:
    return

  let now = epochTime().int64
  let maxAgeSeconds = int64(maxAgeDays) * 24 * 60 * 60
  let stateGraceSeconds = int64(stateGraceDays) * 24 * 60 * 60
  let cutoff = now - maxAgeSeconds
  let stateCutoff = now - stateGraceSeconds

  var staleGameIds: seq[string] = @[]
  for row in cache.db.fastRows(
      sql"""SELECT id FROM games
             WHERE last_updated < ?
             AND id NOT IN (
               SELECT DISTINCT game_id FROM player_states
               WHERE created_at >= ?
             )""",
      $cutoff,
      $stateCutoff
  ):
    staleGameIds.add(row[0])

  if staleGameIds.len == 0:
    return

  for gameId in staleGameIds:
    cache.db.exec(sql"DELETE FROM intel_notes WHERE game_id = ?", gameId)
    cache.db.exec(sql"DELETE FROM player_slots WHERE game_id = ?", gameId)
    cache.db.exec(sql"DELETE FROM games WHERE id = ?", gameId)

  logInfo("TuiCache", "Pruned stale games: ", $staleGameIds.len)

# =============================================================================
# Migration from Old Format
# =============================================================================

proc migrateOldJoinCache*(cache: TuiCache, dataDir: string,
                          playerPubkey: string) =
  ## Migrate old KDL join cache files to the new cache.db
  ##
  ## Old format: data/players/{pubkey}/games/{gameId}.kdl
  ## New format: cache.db tables
  let gamesDir = dataDir / "players" / playerPubkey / "games"
  if not dirExists(gamesDir):
    return
  
  var migratedCount = 0
  
  for kind, path in walkDir(gamesDir):
    if kind != pcFile or not path.endsWith(".kdl"):
      continue
    
    try:
      let content = readFile(path)
      let doc = parseKdl(content)
      if doc.len == 0:
        continue
      
      let node = doc[0]
      if node.name != "join-cache":
        continue
      
      if not node.props.hasKey("game") or not node.props.hasKey("house"):
        continue
      
      let gameId = node.props["game"].kString()
      let houseId = node.props["house"].kInt()
      
      # Read optional metadata from children
      var name = gameId
      var turn = 0
      var status = "unknown"
      for child in node.children:
        case child.name
        of "name":
          if child.args.len > 0:
            name = child.args[0].kString()
        of "turn":
          if child.args.len > 0:
            turn = child.args[0].kInt()
        of "status":
          if child.args.len > 0:
            status = child.args[0].kString()
        else:
          discard
      
      # Insert into cache
      cache.upsertGame(gameId, name, turn, status)
      cache.insertPlayerSlot(gameId, playerPubkey, houseId)
      
      migratedCount += 1
      logInfo("TuiCache", "Migrated join cache: ", gameId)
      
      # Delete old file after successful migration
      removeFile(path)
    except CatchableError as e:
      logWarn("TuiCache", "Failed to migrate: ", path, " ", e.msg)
  
  if migratedCount > 0:
    logInfo("TuiCache", "Migrated ", $migratedCount, " join cache files")

proc migrateOldPlayerStateDb*(cache: TuiCache, dataDir: string,
                              playerPubkey: string) =
  ## Migrate old per-game player_state.db files to the new cache.db
  ## NOTE: Old JSON format is no longer compatible - we just delete old files.
  ##
  ## Old format: data/players/{pubkey}/games/{gameId}/player_state.db
  ## New format: cache.db player_states table (msgpack)
  let gamesDir = dataDir / "players" / playerPubkey / "games"
  if not dirExists(gamesDir):
    return
  
  var deletedCount = 0
  
  for kind, gameDirPath in walkDir(gamesDir):
    if kind != pcDir:
      continue
    
    let oldDbPath = gameDirPath / "player_state.db"
    if not fileExists(oldDbPath):
      continue
    
    # Just delete old incompatible databases
    try:
      removeFile(oldDbPath)
      deletedCount += 1
      logInfo("TuiCache", "Deleted old player state DB: ", oldDbPath)
      
      # Try to remove empty game directory
      try:
        removeDir(gameDirPath)
      except CatchableError:
        discard  # Directory not empty, that's fine
    except CatchableError as e:
      logWarn("TuiCache", "Failed to delete old player state: ", 
              oldDbPath, " ", e.msg)
  
  if deletedCount > 0:
    logInfo("TuiCache", "Deleted ", $deletedCount, " old player state DBs")

proc runMigrations*(cache: TuiCache, dataDir: string, playerPubkey: string) =
  ## Run all migrations from old formats
  logInfo("TuiCache", "Checking for migrations...")
  cache.migrateOldJoinCache(dataDir, playerPubkey)
  cache.migrateOldPlayerStateDb(dataDir, playerPubkey)
