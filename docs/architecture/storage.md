# EC4X Storage Architecture

## Overview

EC4X uses **SQLite** as its single source of truth for all game state. This design provides:

- **Simplicity**: One file per game, no complex setup
- **Portability**: Copy database file = copy entire game
- **Queryability**: SQL for complex game state queries
- **Transactions**: ACID guarantees for turn resolution
- **Performance**: Indexed queries for fast lookups
- **Universality**: Works for both localhost and Nostr modes
- **Event Sourcing**: GameEvents as single source of truth (~5-10MB per 100 turns)

## Database Structure

### One Database Per Game (Recommended)

**EC4X uses separate SQLite files for each game:**

```
data/games/
├── 550e8400-e29b-41d4-a716-446655440000/
│   └── ec4x.db          # Game 1's database
├── 7c9e6679-7425-40de-944b-e07fc1f90ae7/
│   └── ec4x.db          # Game 2's database
└── 123e4567-e89b-12d3-a456-426614174000/
    └── ec4x.db          # Game 3's database
```

**Directory naming:** UUID v4 for technical identity (e.g., `550e8400-e29b-41d4-a716-446655440000`)

**Human names:** Stored in `games.name` field within database (e.g., "Alpha Test Game")

**Benefits:**
- **Isolation**: Corruption in one game doesn't affect others
- **Scalability**: No single large file (each game ~5-10 MB for 100 turns with event sourcing)
- **Portability**: Copy game directory = copy entire game
- **Backup**: Backup individual games independently
- **Concurrency**: No write contention across games
- **Archival**: Easy to archive/delete completed games
- **Scenario Templates**: Reusable game setups separate from instance identity

**Daemon Discovery**: Scan `data/games/*/ec4x.db` to find active games.

**Implementation:** Database initialized by `createGameDatabase()` in `src/daemon/persistence/init.nim`

## Core Schema

**Note on game_id:** Since each game has its own database file, the `game_id` foreign key in tables below is technically redundant (each database contains only one game). However, it's retained for:
- Consistency with queries and code
- Potential future consolidation if needed
- Clarity in data model
- Simplified multi-game queries if databases are attached

In practice, each `ec4x.db` file will have exactly one row in the `games` table.

### games

Master table for game instances (one row per database).

```sql
CREATE TABLE games (
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
    game_setup_json TEXT NOT NULL,    -- Snapshot of GameSetup (scenario config)
    game_config_json TEXT NOT NULL,   -- Snapshot of GameConfig (balance params)
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
);

CREATE INDEX idx_games_phase ON games(phase);
CREATE INDEX idx_games_deadline ON games(turn_deadline) WHERE phase = 'Active';
```

**New fields:**
- `name`: Human-readable identifier (default: scenario name)
- `description`: Optional admin notes for this instance
- `game_setup_json`: Immutable snapshot of scenario configuration at game creation
- `game_config_json`: Immutable snapshot of balance parameters at game creation

**Scenario vs Instance:** Scenarios (`scenarios/*.kdl`) are reusable templates. Each game instance gets a unique UUID and can override the scenario name.

**transport_config JSON examples:**

**Localhost mode:**
```json
{
  "data_dir": "data/games/550e8400-e29b-41d4-a716-446655440000",
  "poll_interval": 30
}
```

**Nostr mode (primary multiplayer transport):**
```json
{
  "relay": "wss://relay.damus.io",
  "moderator_pubkey": "npub1...",
  "fallback_relays": ["wss://relay.nostr.band"],
  "game_event_kind": 30000
}
```

Both modes use the same per-game database structure. Transport mode only affects how orders and state updates are communicated between players.

### houses

Player factions in a game.

```sql
CREATE TABLE houses (
    id TEXT PRIMARY KEY,              -- UUID v4
    game_id TEXT NOT NULL,
    name TEXT NOT NULL,               -- "House Alpha", "Empire Beta"
    nostr_pubkey TEXT,                -- npub/hex (NULL for localhost)
    prestige INTEGER NOT NULL DEFAULT 0,
    eliminated BOOLEAN NOT NULL DEFAULT 0,
    home_system_id TEXT,
    color TEXT,                       -- Hex color code for UI
    created_at INTEGER NOT NULL,
    FOREIGN KEY (game_id) REFERENCES games(id) ON DELETE CASCADE,
    UNIQUE(game_id, name)
);

CREATE INDEX idx_houses_game ON houses(game_id);
CREATE INDEX idx_houses_pubkey ON houses(nostr_pubkey) WHERE nostr_pubkey IS NOT NULL;
```

### systems

Star systems on the map.

```sql
CREATE TABLE systems (
    id TEXT PRIMARY KEY,              -- UUID v4
    game_id TEXT NOT NULL,
    name TEXT NOT NULL,               -- "Alpha Centauri", "Sol"
    hex_q INTEGER NOT NULL,           -- Hex coordinate Q
    hex_r INTEGER NOT NULL,           -- Hex coordinate R
    ring INTEGER NOT NULL,            -- Distance from center (0 = center)
    owner_house_id TEXT,              -- NULL if unowned
    created_at INTEGER NOT NULL,
    FOREIGN KEY (game_id) REFERENCES games(id) ON DELETE CASCADE,
    FOREIGN KEY (owner_house_id) REFERENCES houses(id) ON DELETE SET NULL,
    UNIQUE(game_id, hex_q, hex_r)
);

CREATE INDEX idx_systems_game ON systems(game_id);
CREATE INDEX idx_systems_coords ON systems(game_id, hex_q, hex_r);
CREATE INDEX idx_systems_owner ON systems(owner_house_id) WHERE owner_house_id IS NOT NULL;
```

### lanes

Jump lanes connecting systems.

```sql
CREATE TABLE lanes (
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

CREATE INDEX idx_lanes_game ON lanes(game_id);
CREATE INDEX idx_lanes_from ON lanes(from_system_id);
CREATE INDEX idx_lanes_to ON lanes(to_system_id);
```

### colonies

Player colonies on planets.

```sql
CREATE TABLE colonies (
    id TEXT PRIMARY KEY,              -- UUID v4
    game_id TEXT NOT NULL,
    system_id TEXT NOT NULL,
    owner_house_id TEXT NOT NULL,
    population INTEGER NOT NULL DEFAULT 0,
    industry INTEGER NOT NULL DEFAULT 0,
    defenses INTEGER NOT NULL DEFAULT 0,
    starbase_level INTEGER NOT NULL DEFAULT 0,
    under_siege BOOLEAN NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    FOREIGN KEY (game_id) REFERENCES games(id) ON DELETE CASCADE,
    FOREIGN KEY (system_id) REFERENCES systems(id) ON DELETE CASCADE,
    FOREIGN KEY (owner_house_id) REFERENCES houses(id) ON DELETE CASCADE,
    UNIQUE(game_id, system_id)        -- One colony per system
);

CREATE INDEX idx_colonies_game ON colonies(game_id);
CREATE INDEX idx_colonies_owner ON colonies(owner_house_id);
CREATE INDEX idx_colonies_system ON colonies(system_id);
```

### fleets

Collections of ships.

```sql
CREATE TABLE fleets (
    id TEXT PRIMARY KEY,              -- UUID v4
    game_id TEXT NOT NULL,
    owner_house_id TEXT NOT NULL,
    location_system_id TEXT NOT NULL,
    name TEXT,                        -- Optional fleet name
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    FOREIGN KEY (game_id) REFERENCES games(id) ON DELETE CASCADE,
    FOREIGN KEY (owner_house_id) REFERENCES houses(id) ON DELETE CASCADE,
    FOREIGN KEY (location_system_id) REFERENCES systems(id) ON DELETE CASCADE
);

CREATE INDEX idx_fleets_game ON fleets(game_id);
CREATE INDEX idx_fleets_owner ON fleets(owner_house_id);
CREATE INDEX idx_fleets_location ON fleets(location_system_id);
```

### ships

Individual ships in fleets.

```sql
CREATE TABLE ships (
    id TEXT PRIMARY KEY,              -- UUID v4
    fleet_id TEXT NOT NULL,
    ship_type TEXT NOT NULL,          -- 'Military', 'Spacelift'
    hull_points INTEGER NOT NULL,     -- Current HP
    max_hull_points INTEGER NOT NULL, -- Max HP
    created_at INTEGER NOT NULL,
    FOREIGN KEY (fleet_id) REFERENCES fleets(id) ON DELETE CASCADE,
    CHECK(ship_type IN ('Military', 'Spacelift'))
);

CREATE INDEX idx_ships_fleet ON ships(fleet_id);
```

### orders

Player orders for fleets each turn.

```sql
CREATE TABLE orders (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    game_id TEXT NOT NULL,
    house_id TEXT NOT NULL,
    turn INTEGER NOT NULL,
    fleet_id TEXT NOT NULL,
    order_type TEXT NOT NULL,         -- Fleet order type (see gamestate.nim)
    target_system_id TEXT,            -- For movement/patrol orders
    target_fleet_id TEXT,             -- For join/rendezvous orders
    params TEXT,                      -- JSON blob for order-specific data
    submitted_at INTEGER NOT NULL,    -- Unix timestamp
    processed BOOLEAN NOT NULL DEFAULT 0,
    FOREIGN KEY (game_id) REFERENCES games(id) ON DELETE CASCADE,
    FOREIGN KEY (house_id) REFERENCES houses(id) ON DELETE CASCADE,
    FOREIGN KEY (fleet_id) REFERENCES fleets(id) ON DELETE CASCADE,
    FOREIGN KEY (target_system_id) REFERENCES systems(id) ON DELETE SET NULL,
    FOREIGN KEY (target_fleet_id) REFERENCES fleets(id) ON DELETE SET NULL,
    UNIQUE(game_id, turn, fleet_id)   -- One order per fleet per turn
);

CREATE INDEX idx_orders_turn ON orders(game_id, turn);
CREATE INDEX idx_orders_house_turn ON orders(house_id, turn);
CREATE INDEX idx_orders_unprocessed ON orders(game_id, turn, processed)
    WHERE processed = 0;
```

### diplomacy

Relations between houses.

```sql
CREATE TABLE diplomacy (
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

CREATE INDEX idx_diplomacy_game ON diplomacy(game_id);
CREATE INDEX idx_diplomacy_houses ON diplomacy(house_a_id, house_b_id);
```

### turn_log

Event history for each turn.

```sql
CREATE TABLE turn_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    game_id TEXT NOT NULL,
    turn INTEGER NOT NULL,
    phase TEXT NOT NULL,              -- 'Income', 'Command', 'Conflict', 'Maintenance'
    event_type TEXT NOT NULL,         -- 'Movement', 'Combat', 'Construction', etc.
    data TEXT NOT NULL,               -- JSON event data
    visible_to_house_id TEXT,         -- NULL = public, else private to house
    created_at INTEGER NOT NULL,
    FOREIGN KEY (game_id) REFERENCES games(id) ON DELETE CASCADE,
    FOREIGN KEY (visible_to_house_id) REFERENCES houses(id) ON DELETE CASCADE
);

CREATE INDEX idx_turn_log_game_turn ON turn_log(game_id, turn);
CREATE INDEX idx_turn_log_visibility ON turn_log(visible_to_house_id)
    WHERE visible_to_house_id IS NOT NULL;
```

## Intel Schema

### intel_systems

Tracks which systems each player has knowledge of.

```sql
CREATE TABLE intel_systems (
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

CREATE INDEX idx_intel_systems_house ON intel_systems(game_id, house_id);
CREATE INDEX idx_intel_systems_system ON intel_systems(system_id);
```

**Visibility levels:**
- `owned`: Player has colony here (full visibility)
- `occupied`: Player has fleet here (current visibility)
- `scouted`: Player visited recently (may be stale)
- `adjacent`: System is one jump away (limited intel)

### intel_fleets

Tracks detected enemy fleets.

```sql
CREATE TABLE intel_fleets (
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

CREATE INDEX idx_intel_fleets_house ON intel_fleets(game_id, house_id);
CREATE INDEX idx_intel_fleets_fleet ON intel_fleets(fleet_id);
CREATE INDEX idx_intel_fleets_staleness ON intel_fleets(game_id, detected_turn);
```

**Intel quality:**
- `visual`: Saw fleet in same system (ship count visible)
- `scan`: Active sensor scan (ship types visible)
- `spy`: Espionage operation (full details)

### intel_colonies

Tracks known enemy colony details.

```sql
CREATE TABLE intel_colonies (
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

CREATE INDEX idx_intel_colonies_house ON intel_colonies(game_id, house_id);
CREATE INDEX idx_intel_colonies_colony ON intel_colonies(colony_id);
CREATE INDEX idx_intel_colonies_staleness ON intel_colonies(game_id, intel_turn);
```

## Telemetry & Events Schema

### game_events

Event history using event-sourcing pattern. Single source of truth for all game occurrences.

```sql
CREATE TABLE game_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    game_id TEXT NOT NULL,
    turn INTEGER NOT NULL,
    event_type TEXT NOT NULL,         -- GameEventType enum (e.g., 'Battle', 'OrderCompleted')
    house_id TEXT,                    -- Primary actor (NULL for system events)
    fleet_id TEXT,                    -- Related fleet (NULL if not fleet-related)
    system_id TEXT,                   -- Related system (NULL if not location-specific)
    order_type TEXT,                  -- Order type if order-related
    description TEXT NOT NULL,        -- Human-readable event description
    reason TEXT,                      -- Failure reason for rejected orders
    event_data TEXT,                  -- JSON: event-specific data
    created_at INTEGER NOT NULL,
    FOREIGN KEY (game_id) REFERENCES games(id) ON DELETE CASCADE
);

CREATE INDEX idx_events_game_turn ON game_events(game_id, turn);
CREATE INDEX idx_events_house ON game_events(house_id) WHERE house_id IS NOT NULL;
CREATE INDEX idx_events_type ON game_events(game_id, event_type);
```

**Event Sourcing Benefits:**
- Single source of truth for all game occurrences
- Can reconstruct game state from events
- Enables replay and debugging
- Dramatically smaller than full state snapshots (~5-10MB vs 500MB per 100 turns)

**Visibility:** Events respect fog-of-war. Use `shouldHouseSeeEvent()` from `src/engine/intel/event_processor/visibility.nim` to filter.

### diagnostic_metrics

Comprehensive per-house per-turn metrics for balance testing and AI tuning.

```sql
CREATE TABLE diagnostic_metrics (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    game_id TEXT NOT NULL,
    turn INTEGER NOT NULL,
    act INTEGER NOT NULL,             -- Game chapter/phase
    rank INTEGER NOT NULL,            -- House ranking this turn
    house_id TEXT NOT NULL,

    -- 200+ metric columns covering:
    -- - Economy (treasury, production, population, IU/PU/PTU)
    -- - Technology (all tech levels, research points)
    -- - Military (ship counts by type, combat performance)
    -- - Diplomacy (relation counts, violations)
    -- - Espionage (mission counts, detection)
    -- - Capacity (fighter/squadron limits, violations)
    -- - Production (build queue depth, commissioning)
    -- - Fleet Activity (movement, colonization, stuck fleets)
    -- - Event Counts (order outcomes, combat events)
    -- - Computed Ratios (force projection, fleet readiness)

    created_at INTEGER NOT NULL,
    FOREIGN KEY (game_id) REFERENCES games(id) ON DELETE CASCADE,
    UNIQUE(game_id, turn, house_id)
);

CREATE INDEX idx_diagnostics_game_turn ON diagnostic_metrics(game_id, turn);
CREATE INDEX idx_diagnostics_house ON diagnostic_metrics(game_id, house_id);
CREATE INDEX idx_diagnostics_act ON diagnostic_metrics(game_id, act);
```

**Usage:**
- Balance testing: Run 100+ games, analyze with Python + polars
- AI tuning: Genetic algorithms optimize RBA weights
- Regression detection: Compare metrics across code changes
- Performance analysis: Identify outlier games

**Collection:** Orchestrated by `src/engine/telemetry/orchestrator.nim`, saved via `src/engine/persistence/writer.nim`

**Full schema:** See `src/engine/persistence/schema.nim` for complete 200+ column definition.

## Nostr Transport Schema

The game operates on both localhost and Nostr protocols. These tables enable Nostr-based multiplayer.

### nostr_events

Cache of received Nostr events for asynchronous processing.

```sql
CREATE TABLE nostr_events (
    id TEXT PRIMARY KEY,              -- Nostr event ID (hex)
    game_id TEXT NOT NULL,
    kind INTEGER NOT NULL,
    pubkey TEXT NOT NULL,
    created_at INTEGER NOT NULL,      -- Nostr timestamp
    content TEXT NOT NULL,
    tags TEXT NOT NULL,               -- JSON array
    sig TEXT NOT NULL,
    processed BOOLEAN NOT NULL DEFAULT 0,
    received_at INTEGER NOT NULL,     -- Local timestamp
    FOREIGN KEY (game_id) REFERENCES games(id) ON DELETE CASCADE
);

CREATE INDEX idx_nostr_events_game_kind ON nostr_events(game_id, kind);
CREATE INDEX idx_nostr_events_unprocessed ON nostr_events(processed, game_id)
    WHERE processed = 0;
CREATE INDEX idx_nostr_events_turn ON nostr_events(game_id, json_extract(tags, '$[?(@[0]=="t")][1]'));
```

### nostr_outbox

Queue of Nostr events to publish.

```sql
CREATE TABLE nostr_outbox (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    game_id TEXT NOT NULL,
    event_kind INTEGER NOT NULL,
    recipient_pubkey TEXT,            -- NULL for public events
    content TEXT NOT NULL,            -- Unencrypted or pre-encrypted
    tags TEXT NOT NULL,               -- JSON array
    sent BOOLEAN NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    sent_at INTEGER,                  -- NULL until sent
    FOREIGN KEY (game_id) REFERENCES games(id) ON DELETE CASCADE
);

CREATE INDEX idx_nostr_outbox_unsent ON nostr_outbox(sent, game_id)
    WHERE sent = 0;
```

**Note:** Nostr tables are included in the per-game database schema. Each game tracks its own Nostr events and outbox queue, enabling proper isolation for concurrent multiplayer games.

## State Deltas Schema

### state_deltas

Tracks changes each turn for efficient delta generation.

```sql
CREATE TABLE state_deltas (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    game_id TEXT NOT NULL,
    turn INTEGER NOT NULL,
    house_id TEXT,                    -- NULL = public delta
    delta_type TEXT NOT NULL,         -- 'fleet_moved', 'combat', 'colony_built', etc.
    entity_id TEXT,                   -- Fleet/colony/system ID
    data TEXT NOT NULL,               -- JSON of changed fields only
    created_at INTEGER NOT NULL,
    FOREIGN KEY (game_id) REFERENCES games(id) ON DELETE CASCADE,
    FOREIGN KEY (house_id) REFERENCES houses(id) ON DELETE CASCADE
);

CREATE INDEX idx_deltas_turn ON state_deltas(game_id, turn, house_id);
CREATE INDEX idx_deltas_type ON state_deltas(game_id, delta_type);
```

**Example delta data:**
```json
{
  "type": "fleet_moved",
  "id": "fleet-123",
  "from": "system-A",
  "to": "system-B",
  "ships_damaged": [{"id": "ship-1", "hp": 8}]
}
```

## Query Patterns

### Get Player's Visible Game State

```sql
-- Own colonies
SELECT c.* FROM colonies c
WHERE c.owner_house_id = ?house_id;

-- Known systems
SELECT s.* FROM systems s
JOIN intel_systems i ON s.id = i.system_id
WHERE i.game_id = ?game_id AND i.house_id = ?house_id;

-- Detected enemy fleets (with staleness)
SELECT f.id, i.detected_system_id, i.ship_count,
       (?current_turn - i.detected_turn) as turns_stale
FROM intel_fleets i
JOIN fleets f ON i.fleet_id = f.id
WHERE i.game_id = ?game_id AND i.house_id = ?house_id;
```

### Check Turn Readiness

```sql
-- Count submitted orders vs expected
SELECT
    (SELECT COUNT(*) FROM houses WHERE game_id = ?game_id AND eliminated = 0) as expected,
    (SELECT COUNT(DISTINCT house_id) FROM orders
     WHERE game_id = ?game_id AND turn = ?turn) as submitted;
```

### Get Turn Deltas for Player

```sql
SELECT * FROM state_deltas
WHERE game_id = ?game_id
  AND turn = ?turn
  AND (house_id = ?house_id OR house_id IS NULL)
ORDER BY id;
```

## Migration Strategy

### From Current File-Based System

1. Create SQLite schema
2. Parse existing `systems.txt`, `lanes.txt`, `game_info.txt`
3. Insert into appropriate tables
4. Update game engine to query SQLite
5. Keep file exports for backward compatibility (optional)

### Schema Versioning

```sql
CREATE TABLE schema_version (
    version INTEGER PRIMARY KEY,
    applied_at INTEGER NOT NULL
);

INSERT INTO schema_version VALUES (1, unixepoch());
```

## Backup and Recovery

### Backup
```bash
# Full database backup
sqlite3 ec4x.db ".backup /backup/ec4x_$(date +%Y%m%d).db"

# Per-game backup
sqlite3 ec4x.db "SELECT * FROM games WHERE id='game-123'" | ...
```

### Recovery
```bash
# Restore from backup
cp /backup/ec4x_20250116.db ec4x.db

# Export single game
sqlite3 ec4x.db ".dump" | grep "game-123" > game-123.sql
```

## Persistence Layer Implementation

### Writer Module (`src/engine/persistence/writer.nim`)

Unified persistence layer for per-game databases. All write operations go through this module.

**Core API:**
```nim
proc updateGameMetadata*(state: GameState)
proc saveDiagnosticMetrics*(state: GameState, metrics: DiagnosticMetrics)
proc saveGameEvent*(state: GameState, event: GameEvent)
proc saveGameEvents*(state: GameState, events: seq[GameEvent])
```

**Design principles:**
- Uses `GameState.dbPath` for per-game isolation
- No global database management
- Schema creation handled by `initPerGameDatabase()`
- Batch operations use transactions for atomicity

### Fog-of-War Exports (`src/engine/intel/fog_of_war_export.nim`)

Generate filtered game state views for AI opponents (Claude play-testing).

**API:**
```nim
proc exportFogOfWarView*(state: GameState, houseId: HouseId): FogOfWarView
proc exportFogOfWarViewToJson*(state: GameState, houseId: HouseId): JsonNode
proc saveFogOfWarViewToFile*(state: GameState, houseId: HouseId, filePath: string)
```

**Exported data:**
- Own entities (full visibility): colonies, fleets, house data
- Intelligence reports: known systems, fleets, colonies
- Diplomatic relations
- Visible events (filtered by `shouldHouseSeeEvent()`)

**Use case:** Generate per-house JSON files for Claude to analyze and submit orders.

## Performance Considerations

### Index Strategy
- Primary keys on all ID columns
- Composite indexes on (game_id, turn) for orders/deltas/events
- Partial indexes for active games and unprocessed records
- Event type index for fast event filtering

### Query Optimization
- Use prepared statements for repeated queries
- Batch inserts in transactions (especially for events)
- VACUUM periodically to reclaim space
- Event sourcing reduces storage by 100x vs full snapshots

### Write Patterns
- Turn resolution in single transaction
- Batch event writes (200+ events per turn)
- Diagnostic metrics written once per house per turn
- Intel updates batch-processed after turn resolution

### Storage Growth
- **With event sourcing:** ~50-100KB per turn (typical 4-player game)
- **100-turn game:** ~5-10 MB total
- **1000-turn game:** ~50-100 MB total
- **No full state snapshots** = dramatic space savings

## Related Documentation

- [Architecture Overview](./overview.md)
- [Intel System](./intel.md)
- [Transport Layer](./transport.md)
- Schema implementation: `src/engine/persistence/schema.nim`
- Writer implementation: `src/engine/persistence/writer.nim`
- Fog-of-war exports: `src/engine/intel/fog_of_war_export.nim`
