## Unified Per-Game Database Schema
##
## Architecture: One SQLite database per game at: {dataDir}/games/{slug}/ec4x.db
##
## Tables:
##   Core State: games, houses, systems, lanes, colonies, fleets, ships,
##               commands, diplomacy
##   Intel: intel_systems, intel_fleets, intel_colonies
##   Events: game_events
##   Snapshots: player_state_snapshots
##
## Design: Events-only + player state snapshots
## Storage: ~5-10MB per 100-turn game

import std/os
import db_connector/db_sqlite

const SchemaVersion* = 9  # Incremented for msgpack migration

## ============================================================================
## Core Game State Tables
## ============================================================================

const CreateGamesTable* = """
CREATE TABLE IF NOT EXISTS games (
  id TEXT PRIMARY KEY,              -- UUID v4 (auto-generated)
  name TEXT NOT NULL,               -- Human-readable game name
  description TEXT,                 -- Optional admin notes
  slug TEXT NOT NULL UNIQUE,        -- Human-friendly slug
  turn INTEGER NOT NULL DEFAULT 0,
  year INTEGER NOT NULL DEFAULT 2001,
  month INTEGER NOT NULL DEFAULT 1,
  phase TEXT NOT NULL,              -- 'Setup', 'Active', 'Paused', 'Completed', 'Cancelled'
  turn_deadline INTEGER,            -- Unix timestamp (NULL = no deadline)
  transport_mode TEXT NOT NULL,     -- Transport mode (e.g., 'nostr')
  transport_config TEXT,            -- JSON: mode-specific config
  state_msgpack TEXT,               -- Full GameState as base64-encoded msgpack
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  CHECK(phase IN ('Setup', 'Active', 'Paused', 'Completed', 'Cancelled'))
);

CREATE INDEX IF NOT EXISTS idx_games_phase ON games(phase);
CREATE INDEX IF NOT EXISTS idx_games_deadline ON games(turn_deadline)
  WHERE phase = 'Active';
"""

# Entity tables removed - now stored in games.state_msgpack blob
# This includes: houses, systems, lanes, colonies, fleets, ships
# All entity data is serialized as msgpack and stored in games.state_msgpack

const CreateCommandsTable* = """
CREATE TABLE IF NOT EXISTS commands (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  game_id TEXT NOT NULL,
  house_id TEXT NOT NULL,
  turn INTEGER NOT NULL,
  fleet_id TEXT,                     -- NULL for non-fleet commands
  colony_id TEXT,                    -- Set for build/repair/scrap/colony
  command_type TEXT NOT NULL,        -- Command category or fleet cmd type
  target_system_id TEXT,            
  target_fleet_id TEXT,             
  params TEXT,                      -- JSON blob for all command data
  submitted_at INTEGER NOT NULL,    -- Unix timestamp
  processed BOOLEAN NOT NULL DEFAULT 0,
  FOREIGN KEY (game_id) REFERENCES games(id) ON DELETE CASCADE,
  FOREIGN KEY (house_id) REFERENCES houses(id) ON DELETE CASCADE,
  UNIQUE(game_id, turn, house_id, fleet_id, colony_id, command_type)
);

CREATE INDEX IF NOT EXISTS idx_commands_turn ON commands(game_id, turn);
CREATE INDEX IF NOT EXISTS idx_commands_house_turn ON commands(house_id, turn);
CREATE INDEX IF NOT EXISTS idx_commands_unprocessed ON commands(game_id, turn, processed)
  WHERE processed = 0;
"""

# Diplomacy table removed - diplomatic relations stored in GameState.diplomaticRelation

## ============================================================================
## Intel System Tables (Fog of War)
## ============================================================================
# Intel tables removed - intelligence data now stored in GameState.intel
# (per-house IntelDatabase in the msgpack blob)

## ============================================================================
## Event History Table
## ============================================================================

const CreateGameEventsTable* = """
CREATE TABLE IF NOT EXISTS game_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  game_id TEXT NOT NULL,
  turn INTEGER NOT NULL,
  event_type TEXT NOT NULL,
  house_id TEXT,
  fleet_id TEXT,
  system_id TEXT,
  command_type TEXT,
  description TEXT NOT NULL,
  reason TEXT,
  event_data TEXT,                  -- JSON blob for event-specific data
  created_at INTEGER NOT NULL,
  FOREIGN KEY (game_id) REFERENCES games(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_events_game ON game_events(game_id);
CREATE INDEX IF NOT EXISTS idx_events_turn ON game_events(game_id, turn);
CREATE INDEX IF NOT EXISTS idx_events_type ON game_events(event_type);
CREATE INDEX IF NOT EXISTS idx_events_fleet ON game_events(fleet_id)
  WHERE fleet_id IS NOT NULL;
"""

const CreatePlayerStateSnapshotsTable* = """
CREATE TABLE IF NOT EXISTS player_state_snapshots (
  game_id TEXT NOT NULL,
  house_id TEXT NOT NULL,
  turn INTEGER NOT NULL,
  state_msgpack TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (game_id, house_id, turn),
  FOREIGN KEY (game_id) REFERENCES games(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_player_state_house
  ON player_state_snapshots(game_id, house_id);
"""

const CreateNostrEventLogTable* = """
CREATE TABLE IF NOT EXISTS nostr_event_log (
  game_id TEXT NOT NULL,
  turn INTEGER NOT NULL,
  kind INTEGER NOT NULL,
  event_id TEXT NOT NULL,
  direction INTEGER NOT NULL,        -- 0=inbound, 1=outbound
  created_at INTEGER NOT NULL,
  UNIQUE(game_id, kind, event_id, direction)
);

CREATE INDEX IF NOT EXISTS idx_nostr_event_log_game_turn
  ON nostr_event_log(game_id, turn, kind, direction);
CREATE INDEX IF NOT EXISTS idx_nostr_event_log_created
  ON nostr_event_log(created_at);
"""

## ============================================================================
## Schema Initialization
## ============================================================================

proc createAllTables*(db: DbConn) =
  ## Create all tables for a new game database
  ## Call this once when initializing a new game
  ##
  ## Note: Entity tables (houses, systems, colonies, fleets, ships, intel)
  ## are no longer created. All entity data is stored in games.state_msgpack.

  # Core game state (with msgpack blob)
  db.exec(sql CreateGamesTable)
  db.exec(sql CreateCommandsTable)

  # Event history
  db.exec(sql CreateGameEventsTable)

  # Player state snapshots (with msgpack blob)
  db.exec(sql CreatePlayerStateSnapshotsTable)

  # Replay protection
  db.exec(sql CreateNostrEventLogTable)

  # Schema version tracking
  db.exec(sql"""
    CREATE TABLE IF NOT EXISTS schema_version (
      version INTEGER PRIMARY KEY,
      applied_at INTEGER NOT NULL
    )
  """)
  db.exec(sql"INSERT OR IGNORE INTO schema_version VALUES (?, unixepoch())", SchemaVersion)

proc defaultDBConfig*(gameId: string, gameSlug: string,
  dataDir: string = "data"): tuple[
  dbPath: string,
  gameDir: string
] =
  ## Generate per-game database path
  ## Returns: (dbPath, gameDir)
  let gameDirPath = dataDir / "games" / gameSlug
  let dbFilePath = gameDirPath / "ec4x.db"
  return (dbFilePath, gameDirPath)
