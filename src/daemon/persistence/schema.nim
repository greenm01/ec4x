## Unified Per-Game Database Schema
##
## Architecture: One SQLite database per game at: {dataDir}/games/{gameId}/ec4x.db
##
## Tables:
##   Core State: games, houses, systems, lanes, colonies, fleets, ships,
##               commands, diplomacy
##   Intel: intel_systems, intel_fleets, intel_colonies
##   Events: game_events
##
## Design: Events-only (no snapshots, no fleet_tracking)
## Storage: ~5-10MB per 100-turn game

import std/os
import db_connector/db_sqlite

const SchemaVersion* = 4  # Incremented for new unified schema

## ============================================================================
## Core Game State Tables
## ============================================================================

const CreateGamesTable* = """
CREATE TABLE IF NOT EXISTS games (
  id TEXT PRIMARY KEY,              -- UUID v4 (auto-generated)
  name TEXT NOT NULL,               -- Human-readable game name
  description TEXT,                 -- Optional admin notes
  turn INTEGER NOT NULL DEFAULT 0,
  year INTEGER NOT NULL DEFAULT 2001,
  month INTEGER NOT NULL DEFAULT 1,
  phase TEXT NOT NULL,              -- 'Setup', 'Active', 'Paused', 'Completed'
  turn_deadline INTEGER,            -- Unix timestamp (NULL = no deadline)
  transport_mode TEXT NOT NULL,     -- 'localhost' or 'nostr'
  transport_config TEXT,            -- JSON: mode-specific config
  game_setup_json TEXT NOT NULL,    -- GameSetup snapshot (fixed at creation)
  game_config_json TEXT NOT NULL,   -- GameConfig snapshot (fixed at creation)
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  CHECK(phase IN ('Setup', 'Active', 'Paused', 'Completed')),
  CHECK(transport_mode IN ('localhost', 'nostr'))
);

CREATE INDEX IF NOT EXISTS idx_games_phase ON games(phase);
CREATE INDEX IF NOT EXISTS idx_games_deadline ON games(turn_deadline)
  WHERE phase = 'Active';
"""

const CreateHousesTable* = """
CREATE TABLE IF NOT EXISTS houses (
  id TEXT PRIMARY KEY,              -- UUID v4
  game_id TEXT NOT NULL,
  name TEXT NOT NULL,               -- "House Alpha", "Empire Beta"
  nostr_pubkey TEXT,                -- npub/hex (NULL for localhost)
  prestige INTEGER NOT NULL DEFAULT 0,
  treasury INTEGER NOT NULL DEFAULT 0,
  eliminated BOOLEAN NOT NULL DEFAULT 0,
  home_system_id TEXT,
  color TEXT,                       -- Hex color code for UI
  tech_json TEXT,                   -- JSON: TechTree
  state_json TEXT,                  -- JSON: Extra state (espionage, policies, etc.)
  created_at INTEGER NOT NULL,
  FOREIGN KEY (game_id) REFERENCES games(id) ON DELETE CASCADE,
  UNIQUE(game_id, name)
);

CREATE INDEX IF NOT EXISTS idx_houses_game ON houses(game_id);
CREATE INDEX IF NOT EXISTS idx_houses_pubkey ON houses(nostr_pubkey)
  WHERE nostr_pubkey IS NOT NULL;
"""

const CreateSystemsTable* = """
CREATE TABLE IF NOT EXISTS systems (
  id TEXT PRIMARY KEY,              -- UUID v4
  game_id TEXT NOT NULL,
  name TEXT NOT NULL,               -- "Alpha Centauri", "Sol"
  hex_q INTEGER NOT NULL,           -- Hex coordinate Q
  hex_r INTEGER NOT NULL,           -- Hex coordinate R
  ring INTEGER NOT NULL,            -- Distance from center (0 = center)
  planet_class INTEGER,             -- Enum value
  resource_rating INTEGER,          -- Enum value
  owner_house_id TEXT,              -- NULL if unowned
  created_at INTEGER NOT NULL,
  FOREIGN KEY (game_id) REFERENCES games(id) ON DELETE CASCADE,
  FOREIGN KEY (owner_house_id) REFERENCES houses(id) ON DELETE SET NULL,
  UNIQUE(game_id, hex_q, hex_r)
);

CREATE INDEX IF NOT EXISTS idx_systems_game ON systems(game_id);
CREATE INDEX IF NOT EXISTS idx_systems_coords ON systems(game_id, hex_q, hex_r);
CREATE INDEX IF NOT EXISTS idx_systems_owner ON systems(owner_house_id)
  WHERE owner_house_id IS NOT NULL;
"""

const CreateLanesTable* = """
CREATE TABLE IF NOT EXISTS lanes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  game_id TEXT NOT NULL,
  from_system_id TEXT NOT NULL,
  to_system_id TEXT NOT NULL,
  lane_type TEXT NOT NULL,          -- 'Major', 'Minor', 'Restricted'
  created_at INTEGER NOT NULL,
  FOREIGN KEY (game_id) REFERENCES games(id) ON DELETE CASCADE,
  FOREIGN KEY (from_system_id) REFERENCES systems(id) ON DELETE CASCADE,
  FOREIGN KEY (to_system_id) REFERENCES systems(id) ON DELETE CASCADE,
  UNIQUE(game_id, from_system_id, to_system_id),
  CHECK(lane_type IN ('Major', 'Minor', 'Restricted'))
);

CREATE INDEX IF NOT EXISTS idx_lanes_game ON lanes(game_id);
CREATE INDEX IF NOT EXISTS idx_lanes_from ON lanes(from_system_id);
CREATE INDEX IF NOT EXISTS idx_lanes_to ON lanes(to_system_id);
"""

const CreateColoniesTable* = """
CREATE TABLE IF NOT EXISTS colonies (
  id TEXT PRIMARY KEY,              -- UUID v4
  game_id TEXT NOT NULL,
  system_id TEXT NOT NULL,
  owner_house_id TEXT NOT NULL,
  population INTEGER NOT NULL DEFAULT 0,
  industry INTEGER NOT NULL DEFAULT 0,
  defenses INTEGER NOT NULL DEFAULT 0,
  starbase_level INTEGER NOT NULL DEFAULT 0,
  tax_rate INTEGER NOT NULL DEFAULT 50,
  auto_repair BOOLEAN NOT NULL DEFAULT 0,
  under_siege BOOLEAN NOT NULL DEFAULT 0,
  state_json TEXT,                  -- JSON: Queues, ground units, settings
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (game_id) REFERENCES games(id) ON DELETE CASCADE,
  FOREIGN KEY (system_id) REFERENCES systems(id) ON DELETE CASCADE,
  FOREIGN KEY (owner_house_id) REFERENCES houses(id) ON DELETE CASCADE,
  UNIQUE(game_id, system_id)        -- One colony per system
);

CREATE INDEX IF NOT EXISTS idx_colonies_game ON colonies(game_id);
CREATE INDEX IF NOT EXISTS idx_colonies_owner ON colonies(owner_house_id);
CREATE INDEX IF NOT EXISTS idx_colonies_system ON colonies(system_id);
"""

const CreateFleetsTable* = """
CREATE TABLE IF NOT EXISTS fleets (
  id TEXT PRIMARY KEY,              -- UUID v4
  game_id TEXT NOT NULL,
  owner_house_id TEXT NOT NULL,
  location_system_id TEXT NOT NULL,
  name TEXT,                        -- Optional fleet name
  state_json TEXT,                  -- JSON: Cargo, orders, etc.
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (game_id) REFERENCES games(id) ON DELETE CASCADE,
  FOREIGN KEY (owner_house_id) REFERENCES houses(id) ON DELETE CASCADE,
  FOREIGN KEY (location_system_id) REFERENCES systems(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_fleets_game ON fleets(game_id);
CREATE INDEX IF NOT EXISTS idx_fleets_owner ON fleets(owner_house_id);
CREATE INDEX IF NOT EXISTS idx_fleets_location ON fleets(location_system_id);
"""

const CreateShipsTable* = """
CREATE TABLE IF NOT EXISTS ships (
  id TEXT PRIMARY KEY,              -- UUID v4
  fleet_id TEXT NOT NULL,
  ship_type TEXT NOT NULL,          -- 'Military', 'Spacelift', etc.
  hull_points INTEGER NOT NULL,     -- Current HP
  max_hull_points INTEGER NOT NULL, -- Max HP
  state_json TEXT,                  -- JSON: Fighters, exp, etc.
  created_at INTEGER NOT NULL,
  FOREIGN KEY (fleet_id) REFERENCES fleets(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_ships_fleet ON ships(fleet_id);
"""

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

const CreateDiplomacyTable* = """
CREATE TABLE IF NOT EXISTS diplomacy (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  game_id TEXT NOT NULL,
  house_a_id TEXT NOT NULL,
  house_b_id TEXT NOT NULL,
  relation TEXT NOT NULL,           -- 'War', 'Peace', 'Alliance', 'NAP'
  turn_established INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (game_id) REFERENCES games(id) ON DELETE CASCADE,
  FOREIGN KEY (house_a_id) REFERENCES houses(id) ON DELETE CASCADE,
  FOREIGN KEY (house_b_id) REFERENCES houses(id) ON DELETE CASCADE,
  UNIQUE(game_id, house_a_id, house_b_id),
  CHECK(relation IN ('War', 'Peace', 'Alliance', 'NAP')),
  CHECK(house_a_id < house_b_id)    -- Enforce ordering to prevent duplicates
);

CREATE INDEX IF NOT EXISTS idx_diplomacy_game ON diplomacy(game_id);
CREATE INDEX IF NOT EXISTS idx_diplomacy_houses ON diplomacy(house_a_id, house_b_id);
"""

## ============================================================================
## Intel System Tables (Fog of War)
## ============================================================================

const CreateIntelSystemsTable* = """
CREATE TABLE IF NOT EXISTS intel_systems (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  game_id TEXT NOT NULL,
  house_id TEXT NOT NULL,           -- Who has this intel
  system_id TEXT NOT NULL,          -- What system
  last_scouted_turn INTEGER NOT NULL,
  visibility_level TEXT NOT NULL,   -- 'owned', 'occupied', 'scouted', 'adjacent'
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (game_id) REFERENCES games(id) ON DELETE CASCADE,
  FOREIGN KEY (house_id) REFERENCES houses(id) ON DELETE CASCADE,
  FOREIGN KEY (system_id) REFERENCES systems(id) ON DELETE CASCADE,
  UNIQUE(game_id, house_id, system_id),
  CHECK(visibility_level IN ('owned', 'occupied', 'scouted', 'adjacent'))
);

CREATE INDEX IF NOT EXISTS idx_intel_systems_house ON intel_systems(game_id, house_id);
CREATE INDEX IF NOT EXISTS idx_intel_systems_system ON intel_systems(system_id);
"""

const CreateIntelFleetsTable* = """
CREATE TABLE IF NOT EXISTS intel_fleets (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  game_id TEXT NOT NULL,
  house_id TEXT NOT NULL,           -- Who detected this
  fleet_id TEXT NOT NULL,           -- Enemy fleet
  detected_turn INTEGER NOT NULL,   -- Last seen
  detected_system_id TEXT NOT NULL, -- Where it was seen
  ship_count INTEGER,               -- Approximate count
  ship_types TEXT,                  -- JSON: {"Military": 5, "Spacelift": 2}
  intel_quality TEXT NOT NULL,      -- 'visual', 'scan', 'spy'
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (game_id) REFERENCES games(id) ON DELETE CASCADE,
  FOREIGN KEY (house_id) REFERENCES houses(id) ON DELETE CASCADE,
  FOREIGN KEY (fleet_id) REFERENCES fleets(id) ON DELETE CASCADE,
  FOREIGN KEY (detected_system_id) REFERENCES systems(id) ON DELETE CASCADE,
  UNIQUE(game_id, house_id, fleet_id),
  CHECK(intel_quality IN ('visual', 'scan', 'spy'))
);

CREATE INDEX IF NOT EXISTS idx_intel_fleets_house ON intel_fleets(game_id, house_id);
CREATE INDEX IF NOT EXISTS idx_intel_fleets_fleet ON intel_fleets(fleet_id);
CREATE INDEX IF NOT EXISTS idx_intel_fleets_staleness ON intel_fleets(game_id, detected_turn);
"""

const CreateIntelColoniesTable* = """
CREATE TABLE IF NOT EXISTS intel_colonies (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  game_id TEXT NOT NULL,
  house_id TEXT NOT NULL,           -- Who has this intel
  colony_id TEXT NOT NULL,          -- Target colony
  intel_turn INTEGER NOT NULL,      -- When intel was gathered
  population INTEGER,               -- NULL if unknown
  industry INTEGER,
  defenses INTEGER,
  starbase_level INTEGER,
  intel_source TEXT NOT NULL,       -- 'spy', 'capture', 'scan'
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (game_id) REFERENCES games(id) ON DELETE CASCADE,
  FOREIGN KEY (house_id) REFERENCES houses(id) ON DELETE CASCADE,
  FOREIGN KEY (colony_id) REFERENCES colonies(id) ON DELETE CASCADE,
  UNIQUE(game_id, house_id, colony_id),
  CHECK(intel_source IN ('spy', 'capture', 'scan'))
);

CREATE INDEX IF NOT EXISTS idx_intel_colonies_house ON intel_colonies(game_id, house_id);
CREATE INDEX IF NOT EXISTS idx_intel_colonies_colony ON intel_colonies(colony_id);
CREATE INDEX IF NOT EXISTS idx_intel_colonies_staleness ON intel_colonies(game_id, intel_turn);
"""

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

## ============================================================================
## Schema Initialization
## ============================================================================

proc createAllTables*(db: DbConn) =
  ## Create all tables for a new game database
  ## Call this once when initializing a new game

  # Core game state
  db.exec(sql CreateGamesTable)
  db.exec(sql CreateHousesTable)
  db.exec(sql CreateSystemsTable)
  db.exec(sql CreateLanesTable)
  db.exec(sql CreateColoniesTable)
  db.exec(sql CreateFleetsTable)
  db.exec(sql CreateShipsTable)
  db.exec(sql CreateCommandsTable)
  db.exec(sql CreateDiplomacyTable)

  # Intel system
  db.exec(sql CreateIntelSystemsTable)
  db.exec(sql CreateIntelFleetsTable)
  db.exec(sql CreateIntelColoniesTable)

  # Event history
  db.exec(sql CreateGameEventsTable)

  # Schema version tracking
  db.exec(sql"""
    CREATE TABLE IF NOT EXISTS schema_version (
      version INTEGER PRIMARY KEY,
      applied_at INTEGER NOT NULL
    )
  """)
  db.exec(sql"INSERT OR IGNORE INTO schema_version VALUES (?, unixepoch())", SchemaVersion)

proc defaultDBConfig*(gameId: string, dataDir: string = "data"): tuple[
  dbPath: string,
  gameDir: string
] =
  ## Generate per-game database path
  ## Returns: (dbPath, gameDir)
  let gameDirPath = dataDir / "games" / gameId
  let dbFilePath = gameDirPath / "ec4x.db"
  return (dbFilePath, gameDirPath)
