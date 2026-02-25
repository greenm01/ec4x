# EC4X Storage Architecture

## Overview

EC4X uses **msgpack + SQLite** for game state persistence. This hybrid design provides:

- **Simplicity**: One file per game, no complex setup
- **Portability**: Copy database file = copy entire game
- **Performance**: ~80% smaller than JSON, instant serialization
- **Type Safety**: msgpack4nim ensures correct deserialization
- **Queryability**: SQL for event log and command history
- **Transactions**: ACID guarantees for turn resolution
- **Universality**: Works for both localhost and Nostr modes

## Architecture Philosophy

**msgpack for GameState, SQL for Events**

- **GameState**: Serialized as single msgpack blob (base64-encoded TEXT)
- **Events**: Stored as queryable SQL rows for reports
- **Commands**: Stored as SQL rows with base64 msgpack packets

This hybrid approach balances:
- Fast state snapshots (msgpack)
- Queryable history (SQL)
- Efficient storage (~10 MB per 100-turn game)

## Database Structure

### One Database Per Game

**EC4X uses separate SQLite files for each game:**

```
data/games/
├── lucky-tiger-jukebox/
│   └── ec4x.db          # Game 1's database
├── jingle-nylon-afoot/
│   └── ec4x.db          # Game 2's database
└── broken-dash-educated/
    └── ec4x.db          # Game 3's database
```

**Directory naming:** Human-readable slug (e.g., `lucky-tiger-jukebox`)

**Benefits:**
- **Isolation**: Corruption in one game doesn't affect others
- **Scalability**: No single large file (each game ~10-15 MB for 100 turns)
- **Portability**: Copy game directory = copy entire game
- **Backup**: Backup individual games independently
- **Concurrency**: No write contention across games
- **Archival**: Easy to archive/delete completed games

**Daemon Discovery**: Scan `data/games/*/ec4x.db` to find active games.

**Moderator lifecycle**:
- `ec4x cancel <game-id>` archives to `data/archive/` and publishes status
  `cancelled`.
- `ec4x delete <game-id>` removes the game directory and publishes status
  `removed`.
- Victory resolution publishes status `completed` and archives the game.

**Implementation:** Database initialized by `createGameDatabase()` in `src/daemon/persistence/init.nim`

## Core Schema

### games

Master table for game instances (one row per database).

```sql
CREATE TABLE games (
    id TEXT PRIMARY KEY,              -- UUID v4 (auto-generated)
    name TEXT NOT NULL,               -- Human-readable game name
    description TEXT,                 -- Optional admin notes
    slug TEXT NOT NULL UNIQUE,        -- Human-friendly slug
    turn INTEGER NOT NULL DEFAULT 0,
    year INTEGER NOT NULL DEFAULT 2001,
    month INTEGER NOT NULL DEFAULT 1,
    phase TEXT NOT NULL,              -- 'Setup', 'Active', 'Paused', 'Completed', 'Cancelled'
    turn_deadline INTEGER,            -- Unix timestamp (NULL = no deadline)
    transport_mode TEXT NOT NULL,     -- 'nostr'
    transport_config TEXT,            -- JSON: mode-specific config
    state_msgpack TEXT,               -- Full GameState as base64-encoded msgpack
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
);

CREATE INDEX idx_games_phase ON games(phase);
CREATE INDEX idx_games_deadline ON games(turn_deadline) WHERE phase = 'Active';
```

**Key Field:**
- `state_msgpack`: Complete GameState serialized as msgpack, base64-encoded for safe SQLite storage

**What's in the msgpack blob:**
- All houses (with tech trees, espionage budgets, nostr pubkeys, invite codes)
- All systems (coordinates, planet class, resource rating)
- All jump lanes
- All colonies (population, industry, infrastructure, build queues, ground units)
- All fleets (location, cargo, ROE, orders)
- All ships (class, hull points, fighters, experience)
- All diplomatic relations
- All intelligence databases (per-house intel)
- All facilities (neorias, kastras)
- All production projects (construction, repairs)
- All ID counters
- All ongoing effects and pending proposals

**Performance:**
- Typical 4-player game: ~100-140 KB (msgpack)
- vs JSON: ~500 KB (79% reduction)
- Serialization: <1ms
- Deserialization: <1ms

### commands

Player command batches for turn resolution.

```sql
CREATE TABLE commands (
    game_id TEXT NOT NULL,
    house_id TEXT NOT NULL,
    turn INTEGER NOT NULL,
    command_msgpack TEXT NOT NULL,     -- Base64 msgpack CommandPacket
    submitted_at INTEGER NOT NULL,     -- Unix timestamp
    processed BOOLEAN NOT NULL DEFAULT 0,
    FOREIGN KEY (game_id) REFERENCES games(id) ON DELETE CASCADE,
    PRIMARY KEY (game_id, turn, house_id)
);

CREATE INDEX idx_commands_turn ON commands(game_id, turn);
CREATE INDEX idx_commands_house_turn ON commands(house_id, turn);
CREATE INDEX idx_commands_unprocessed ON commands(game_id, turn, processed)
    WHERE processed = 0;
```

**Note:** Commands use msgpack (base64) to align with transport and
CommandPacket serialization. Each row stores one house's full packet.

### game_events

Event history for turn reports.

```sql
CREATE TABLE game_events (
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

CREATE INDEX idx_events_game ON game_events(game_id);
CREATE INDEX idx_events_turn ON game_events(game_id, turn);
CREATE INDEX idx_events_type ON game_events(event_type);
CREATE INDEX idx_events_fleet ON game_events(fleet_id)
    WHERE fleet_id IS NOT NULL;
```

**Purpose:** Queryable event log for generating turn reports

**Visibility:** Events respect fog-of-war. Use `shouldHouseSeeEvent()` to filter.

### player_state_snapshots

Per-house PlayerState snapshots for delta generation.

```sql
CREATE TABLE player_state_snapshots (
    game_id TEXT NOT NULL,
    house_id TEXT NOT NULL,
    turn INTEGER NOT NULL,
    state_msgpack TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    PRIMARY KEY (game_id, house_id, turn),
    FOREIGN KEY (game_id) REFERENCES games(id) ON DELETE CASCADE
);

CREATE INDEX idx_player_state_house
    ON player_state_snapshots(game_id, house_id);
```

**Purpose:** Store per-house fog-of-war filtered state for computing deltas between turns

**Format:** msgpack (base64-encoded) for consistency with GameState serialization

### nostr_event_log

Replay protection for Nostr events.

```sql
CREATE TABLE nostr_event_log (
    game_id TEXT NOT NULL,
    turn INTEGER NOT NULL,
    kind INTEGER NOT NULL,
    event_id TEXT NOT NULL,
    direction INTEGER NOT NULL,        -- 0=inbound, 1=outbound
    created_at INTEGER NOT NULL,
    UNIQUE(game_id, kind, event_id, direction)
);

CREATE INDEX idx_nostr_event_log_game_turn
    ON nostr_event_log(game_id, turn, kind, direction);
CREATE INDEX idx_nostr_event_log_created
    ON nostr_event_log(created_at);
```

**Purpose:** Prevent replay attacks and duplicate event processing

## Removed Tables (Now in msgpack blob)

**The following tables were removed in favor of msgpack serialization:**

- ❌ `houses` - House data now in GameState.houses
- ❌ `systems` - System data now in GameState.systems
- ❌ `lanes` - Lane data now in GameState.starMap.lanes
- ❌ `colonies` - Colony data now in GameState.colonies
- ❌ `fleets` - Fleet data now in GameState.fleets
- ❌ `ships` - Ship data now in GameState.ships
- ❌ `diplomacy` - Diplomatic relations now in GameState.diplomaticRelation
- ❌ `intel_systems` - Intel now in GameState.intel (per-house IntelDatabase)
- ❌ `intel_fleets` - Intel now in GameState.intel
- ❌ `intel_colonies` - Intel now in GameState.intel

**Benefits of removal:**
- **79% storage reduction** vs JSON entity tables
- **Simplified schema** (6 tables instead of 15)
- **Atomic state updates** (entire state in one blob)
- **No index maintenance** (no bySystem/byOwner tables)
- **Single source of truth** (GameState object is authoritative)

## Migration from JSON (v8 → v9)

**Schema version 9** introduced msgpack persistence:

**Changes:**
1. Added `state_msgpack TEXT` to `games` table
2. Changed `state_json` → `state_msgpack` in `player_state_snapshots` table
3. Removed 9 entity tables (houses, systems, lanes, colonies, fleets, ships, diplomacy, intel_*)
4. Removed `game_setup_json`, `game_config_json` from games table

**Schema version 10** stores CommandPacket blobs as msgpack:

**Changes:**
1. Replaced per-command rows with one row per house/turn
2. Added `command_msgpack` base64 blob to commands table

**Breaking Change:** No backward compatibility. Games created with schema v9
cannot be loaded with v10.

**Mitigation:** This is pre-release software. Existing games must be recreated.

## Persistence Layer Implementation

### Writer Module (`src/daemon/persistence/writer.nim`)

Unified persistence layer for per-game databases.

**Core API:**
```nim
proc saveFullState*(state: GameState)
  # Serializes entire GameState to msgpack, saves to games.state_msgpack

proc savePlayerStateSnapshot*(dbPath: string, gameId: string,
                              houseId: HouseId, turn: int32,
                              snapshot: PlayerStateSnapshot)
  # Saves per-house fog-of-war state for delta generation

proc saveCommandPacket*(dbPath: string, gameId: string,
                       packet: CommandPacket)
  # Saves player commands to commands table (msgpack base64)

proc saveGameEvents*(state: GameState, events: seq[GameEvent])
  # Batch insert events to game_events table
```

**Design:**
- Single `saveFullState()` call replaces 6+ entity save procs
- Transaction per state save (atomic)
- base64 encoding for safe binary storage

### Reader Module (`src/daemon/persistence/reader.nim`)

Load GameState from msgpack blob.

**Core API:**
```nim
proc loadFullState*(dbPath: string): GameState
  # Loads complete GameState from games.state_msgpack
  # Deserializes msgpack → GameState object
  # Restores runtime fields (dbPath, dataDir)

proc loadPlayerStateSnapshot*(dbPath: string, gameId: string,
                             houseId: HouseId, turn: int32):
                             Option[PlayerStateSnapshot]
  # Loads per-house state snapshot from msgpack

proc loadOrders*(dbPath: string, turn: int): Table[HouseId, CommandPacket]
  # Loads command packets from commands table (msgpack deserialization)
```

**Performance:**
- `loadFullState()`: <1ms for typical game
- No complex queries or joins
- No index rebuilding

### msgpack Serialization Module (`src/daemon/persistence/msgpack_state.nim`)

Custom msgpack serialization for EC4X types.

**Custom Type Handlers:**
```nim
# All distinct ID types (HouseId, SystemId, ColonyId, FleetId, ShipId,
# GroundUnitId, NeoriaId, KastraId, ConstructionProjectId, RepairProjectId,
# PopulationTransferId, ProposalId) have custom pack_type/unpack_type procs

proc pack_type*[S](s: S, x: HouseId) = s.pack(x.uint32)
proc unpack_type*[S](s: S, x: var HouseId) =
  var v: uint32
  s.unpack(v)
  x = HouseId(v)

# ... similar for all ID types
```

**Core API:**
```nim
proc serializeGameState*(state: GameState): string
  # GameState → msgpack binary → base64 string

proc deserializeGameState*(data: string): GameState
  # base64 string → msgpack binary → GameState

proc serializePlayerState*(state: PlayerState): string
proc deserializePlayerState*(data: string): PlayerState
```

**Why base64?**
- SQLite parameter binding safety
- Avoids binary string escaping issues
- ~33% overhead acceptable (still 72% smaller than JSON)

## Query Patterns

### Load Game State

```nim
# Single call loads entire game
let state = loadFullState(dbPath)

# Access any entity directly
let house = state.houses.entities.data[idx]
let colony = state.colonies.entities.data[idx]
let fleet = state.fleets.entities.data[idx]
```

### Query Event History

```sql
-- Get all events for a turn
SELECT * FROM game_events
WHERE game_id = ? AND turn = ?
ORDER BY id;

-- Get events visible to a house (filtered by engine)
SELECT * FROM game_events
WHERE game_id = ? AND turn = ?
  AND (house_id = ? OR house_id IS NULL);
```

### Check Turn Readiness

```sql
-- Count submitted commands vs expected
SELECT
    (SELECT COUNT(*) FROM houses WHERE eliminated = 0) as expected,
    (SELECT COUNT(DISTINCT house_id) FROM commands
     WHERE game_id = ? AND turn = ? AND processed = 0) as submitted;
```

## Backup and Recovery

### Backup

```bash
# Full database backup (includes msgpack state)
sqlite3 data/games/lucky-tiger-jukebox/ec4x.db ".backup /backup/game_$(date +%Y%m%d).db"

# Per-game backup
cp -r data/games/lucky-tiger-jukebox /backup/games/
```

### Recovery

```bash
# Restore from backup
cp /backup/game_20250122.db data/games/lucky-tiger-jukebox/ec4x.db
```

## Performance Considerations

### Storage Growth

**With msgpack serialization:**
- Initial state: ~100-150 KB
- Per-turn growth: ~10-20 KB (commands + events)
- 100-turn game: ~10-15 MB total
- 1000-turn game: ~100-150 MB total

**Comparison to JSON (v8):**
- Initial state: ~500 KB (JSON) vs ~150 KB (msgpack base64) = **70% reduction**
- 100-turn game: ~50 MB (JSON) vs ~15 MB (msgpack) = **70% reduction**

### Write Patterns

- Turn resolution in single transaction
- One `UPDATE games SET state_msgpack = ?` per turn
- Batch event writes (100-200 events per turn)
- Commands written incrementally as submitted

### Read Patterns

- Single query loads entire state: `SELECT state_msgpack FROM games`
- Deserialize msgpack: <1ms
- No complex joins or index rebuilding
- Events queried separately for reports

## TUI Client-Side Cache

The TUI player maintains a separate SQLite cache for client-side data,
independent from the daemon's authoritative database.

### Cache Location

```
~/.local/share/ec4x/cache.db
```

### Identity Wallet Files

The player identity wallet is stored separately from cache:

```
~/.local/share/ec4x/wallet.kdl
```

Wallet format:

```kdl
wallet active="0"
identity nsec="nsec1..." type="local" created="2026-01-17T12:00:00Z"
identity nsec="nsec1..." type="imported" created="2026-01-21T09:35:00Z"
```

Compatibility mirror:

```
~/.local/share/ec4x/identity.kdl
```

The active wallet identity is mirrored to `identity.kdl` for older
single-identity tooling compatibility.

### Schema

```sql
-- Global settings
CREATE TABLE settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

-- Game metadata from Nostr events
CREATE TABLE games (
    game_id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    turn INTEGER NOT NULL DEFAULT 0,
    phase TEXT NOT NULL DEFAULT 'setup',
    relay_url TEXT,
    daemon_pubkey TEXT,
    last_updated INTEGER NOT NULL
);

-- Player's house assignments per game
CREATE TABLE player_slots (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    game_id TEXT NOT NULL,
    player_pubkey TEXT NOT NULL,
    house_index INTEGER NOT NULL,
    joined_at INTEGER NOT NULL,
    UNIQUE(game_id, player_pubkey)
);

-- PlayerState snapshots per game/turn (msgpack)
CREATE TABLE player_states (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    game_id TEXT NOT NULL,
    player_pubkey TEXT NOT NULL,
    turn INTEGER NOT NULL,
    state_msgpack TEXT NOT NULL,
    cached_at INTEGER NOT NULL,
    UNIQUE(game_id, player_pubkey, turn)
);

-- Authoritative TUI rules snapshots per game/hash (msgpack)
CREATE TABLE config_snapshots (
    game_id TEXT NOT NULL,
    config_hash TEXT NOT NULL,
    schema_version INTEGER NOT NULL,
    snapshot_msgpack TEXT NOT NULL,
    updated_at INTEGER NOT NULL,
    PRIMARY KEY(game_id, config_hash)
);

-- Staged CommandPacket draft per game/house (msgpack)
CREATE TABLE order_drafts (
    game_id TEXT NOT NULL,
    house_id INTEGER NOT NULL,
    turn INTEGER NOT NULL,
    config_hash TEXT NOT NULL,
    packet_msgpack TEXT NOT NULL,
    updated_at INTEGER NOT NULL,
    PRIMARY KEY(game_id, house_id)
);

-- Nostr event deduplication
CREATE TABLE received_events (
    event_id TEXT PRIMARY KEY,
    game_id TEXT,
    kind INTEGER NOT NULL,
    received_at INTEGER NOT NULL
);
```

**Note:** Client cache also uses msgpack for PlayerState snapshots (consistency)
and stores authoritative sectioned rules snapshots (`TuiRulesSnapshot`) for
config/schema/hash validation on reconnect and delta application.

### Authoritative Rules in Client Cache

The daemon remains the authoritative source for gameplay config used by
the player TUI. The TUI cache stores the latest valid
`TuiRulesSnapshot` per game in `config_snapshots` and uses it to:

- Materialize runtime rules consumed by TUI screens/validators
- Validate incoming 30403 delta envelopes via `configHash` and
  `configSchemaVersion`
- Block gameplay entry when no valid authoritative snapshot is available

This prevents client-side config drift while still allowing the server
to evolve rule sections/capabilities over time.

### Draft Order Persistence

The player TUI persists staged orders and R&D allocation locally as a
`CommandPacket` draft in `order_drafts` so players can exit/re-enter
without losing work.

Restore policy:
- Restore only when `draft.turn == current PlayerState.turn`
- Restore only when `draft.config_hash == active TuiRulesSnapshot.configHash`
- Discard draft automatically on turn or config mismatch

Lifecycle:
- Save/update draft while staged commands or research allocation change
- Clear draft after successful turn submission

### Implementation

- Cache module: `src/player/state/tui_cache.nim`
- Config module: `src/player/state/tui_config.nim`
- Initialization: `openTuiCache()` creates/opens the cache

## TUI Configuration

Player preferences stored at `~/.config/ec4x/config.kdl`:

```kdl
config {
  default-relay "wss://relay.ec4x.io"

  relay-aliases {
    home "ws://192.168.1.50:8080"
    work "wss://relay.work.example.com"
  }
}
```

## Related Documentation

- [Architecture Overview](./overview.md)
- [Intel System](./intel.md)
- [Transport Layer](./transport.md)
- [Nostr Protocol](./nostr-protocol.md)
- Schema implementation: `src/daemon/persistence/schema.nim`
- Writer implementation: `src/daemon/persistence/writer.nim`
- Reader implementation: `src/daemon/persistence/reader.nim`
- msgpack module: `src/daemon/persistence/msgpack_state.nim`

### Transport Layer Serialization

For Nostr transport, additional msgpack modules handle player-facing state:

- Delta serialization: `src/daemon/transport/nostr/delta_msgpack.nim`
- State serialization: `src/daemon/transport/nostr/state_msgpack.nim`

These modules serialize `PlayerState` and `PlayerStateDelta` for wire transmission,
using the same msgpack + base64 pattern as persistence but with zstd compression
and NIP-44 encryption added. See [Transport Layer](./transport.md) for details.
