# EC4X Daemon Design

## Overview

The **daemon** is the autonomous turn processing service that powers EC4X. It monitors active games, collects player orders, resolves turns, and publishes results—all without human intervention.

**Key Design**: Single process manages all games across both transport modes.

## Architecture

```
┌──────────────────────────────────────────────┐
│              EC4X Daemon Process             │
├──────────────────────────────────────────────┤
│  ┌────────────────────────────────────────┐  │
│  │      Game Discovery & Management       │  │
│  │  • Scan SQLite for active games        │  │
│  │  • Load transport configs              │  │
│  │  • Track turn deadlines                │  │
│  │  • Hot reload new games                │  │
│  └────────────────────────────────────────┘  │
│  ┌────────────────────────────────────────┐  │
│  │       Transport Handler Layer          │  │
│  │  ┌──────────────┐  ┌───────────────┐  │  │
│  │  │  Localhost   │  │    Nostr      │  │  │
│  │  │  Watcher     │  │  Subscriber   │  │  │
│  │  │              │  │               │  │  │
│  │  │ • Poll files │  │ • WebSocket   │  │  │
│  │  │ • Parse JSON │  │ • Decrypt     │  │  │
│  │  └──────────────┘  └───────────────┘  │  │
│  └────────────────────────────────────────┘  │
│  ┌────────────────────────────────────────┐  │
│  │       Turn Resolution Engine           │  │
│  │  • Validate orders                     │  │
│  │  • Resolve 4-phase turn cycle          │  │
│  │  • Update game state                   │  │
│  │  • Generate deltas                     │  │
│  │  • Update intel tables                 │  │
│  └────────────────────────────────────────┘  │
│  ┌────────────────────────────────────────┐  │
│  │       Result Publisher Layer           │  │
│  │  ┌──────────────┐  ┌───────────────┐  │  │
│  │  │  Localhost   │  │    Nostr      │  │  │
│  │  │  Exporter    │  │  Publisher    │  │  │
│  │  │              │  │               │  │  │
│  │  │ • Write JSON │  │ • Encrypt     │  │  │
│  │  │ • Export TXT │  │ • Publish     │  │  │
│  │  └──────────────┘  └───────────────┘  │  │
│  └────────────────────────────────────────┘  │
│  ┌────────────────────────────────────────┐  │
│  │          Scheduler & Monitoring        │  │
│  │  • Check deadlines                     │  │
│  │  • Trigger turn resolution             │  │
│  │  • Health checks                       │  │
│  │  • Metrics & logging                   │  │
│  └────────────────────────────────────────┘  │
└──────────────────────────────────────────────┘
```

## Core Responsibilities

### 1. Game Discovery

**On Startup:**
1. Connect to SQLite database(s)
2. Query for active games: `SELECT * FROM games WHERE phase = 'Active'`
3. Load transport configuration for each game
4. Initialize transport handlers (filesystem watchers, Nostr subscriptions)

**During Runtime:**
1. Periodically re-query for new games (hot reload)
2. Detect games added by `moderator new`
3. Detect games paused/resumed/completed
4. Adjust monitoring dynamically

**Configuration:**
```toml
[daemon]
db_path = "/var/ec4x/games.db"
poll_interval = 30  # seconds
discovery_interval = 300  # re-scan for new games every 5 min
```

### 2. Order Collection

**Localhost Mode:**
```
Loop every poll_interval:
  For each active game:
    For each house:
      Check houses/<house>/orders_pending.json
      If exists:
        Parse and validate JSON
        Insert into orders table
        Delete orders_pending.json
        Log order receipt
```

**Nostr Mode:**
```
Maintain WebSocket subscription:
  Filter: kind=30001, g=<game_ids>, p=<moderator_pubkey>

On EVENT received:
  Verify signature
  Decrypt with moderator's private key
  Parse order packet
  Validate against game rules
  Insert into orders table
  Cache in nostr_events table
  Log order receipt
```

**Multi-Game Efficiency:**
- Localhost: Single filesystem poll covers all games in directory tree
- Nostr: Single WebSocket per relay with multi-game filter

### 3. Turn Readiness Check

**Conditions for Turn Resolution:**

**Condition A: All Orders Received**
```sql
SELECT
  (SELECT COUNT(*) FROM houses WHERE game_id = ?id AND eliminated = 0) as expected,
  (SELECT COUNT(DISTINCT house_id) FROM orders WHERE game_id = ?id AND turn = ?turn) as received;
-- If expected == received, all orders in
```

**Condition B: Deadline Passed**
```sql
SELECT turn_deadline FROM games WHERE id = ?id;
-- If turn_deadline < current_time, resolve with available orders
```

**Policy Options:**
- Strict: Wait for all orders (no deadline)
- Deadline: Auto-resolve on deadline
- Hybrid: Wait up to deadline, then resolve with available orders
- Grace period: X minutes after last order received

### 4. Turn Resolution

**Process (Atomic Transaction):**

```
BEGIN TRANSACTION;

1. Lock game row (prevent concurrent resolution)
   UPDATE games SET phase = 'Resolving' WHERE id = ?id;

2. Load game state from SQLite
   - All systems, lanes, colonies, fleets, ships
   - Current diplomatic relations
   - Active construction/research

3. Load orders for current turn
   - All submitted orders
   - Default "Hold" orders for missing submissions

4. Run game engine resolution (4 phases)
   a. Income Phase: Calculate production, prestige
   b. Command Phase: Execute orders (movement, colonization)
   c. Conflict Phase: Resolve combat
   d. Maintenance Phase: Construction, research, upkeep

5. Save new game state to SQLite
   - Update all changed entities
   - Increment turn counter
   - Update year/month calendar

6. Generate turn log events
   - Movement events
   - Combat reports
   - Construction completions
   - Diplomatic changes

7. Update intel tables for all players
   - System visibility
   - Fleet detection
   - Colony intel from spy ops

8. Generate state deltas per player
   - Query intel tables for each house
   - Compute changes since last turn
   - Store in state_deltas table

9. Update turn deadline
   - Calculate next deadline (e.g., +48 hours)
   - Update games table

10. Mark orders as processed
    UPDATE orders SET processed = 1 WHERE game_id = ?id AND turn = ?turn;

11. Commit game state
    UPDATE games SET phase = 'Active', turn = turn + 1, updated_at = ?now WHERE id = ?id;

COMMIT;
```

**Error Handling:**
- On any error: ROLLBACK transaction
- Log error details
- Notify moderator (future: via Nostr event)
- Leave game in 'Active' state for retry
- Mark turn as failed in metadata

### 5. Result Distribution

**Localhost Mode:**

```
For each house in game:
  1. Query state_deltas for house_id
  2. Query intel tables for visibility
  3. Generate filtered GameState
  4. Serialize to JSON
  5. Write to houses/<house>/turn_results/turn_N.json
  6. Generate human-readable summary
  7. Write to houses/<house>/turn_results/turn_N.txt

Public results:
  1. Generate public turn summary (no secrets)
  2. Write to public/turn_summaries/turn_N.txt
  3. Append to public/game_log.txt
```

**Nostr Mode:**

```
For each house in game:
  1. Query state_deltas for house_id
  2. Query intel tables for visibility
  3. Generate filtered delta JSON
  4. Check size:
     - If < 32 KB: single event
     - If >= 32 KB: chunk into multiple events
  5. Encrypt to house's pubkey (NIP-44)
  6. Create EventKindStateDelta (or EventKindDeltaChunk)
  7. Sign with moderator's keypair
  8. Insert into nostr_outbox queue

Public results:
  1. Generate public turn summary
  2. Create EventKindTurnComplete
  3. Sign with moderator's keypair
  4. Insert into nostr_outbox queue

Publish loop (separate thread):
  Poll nostr_outbox for unsent events
  Batch publish to relay (up to 10/second)
  Mark sent = 1 on success
  Retry on failure (exponential backoff)
```

## Operational Model

### Daemon Lifecycle

**Startup:**
```bash
daemon start --config=/etc/ec4x/daemon.toml
```

1. Load configuration
2. Connect to SQLite database
3. Discover active games
4. Initialize transport handlers
5. Start monitoring loops
6. Enter main loop

**Main Loop:**
```
Loop forever (every poll_interval seconds):
  1. Check for new/changed games (hot reload)
  2. Collect orders from all transports
  3. Check turn readiness for each game
  4. Resolve turns for ready games
  5. Distribute results via transports
  6. Update metrics and logs
  7. Sleep until next interval
```

**Shutdown:**
```bash
daemon stop
```

1. Receive SIGTERM/SIGINT
2. Finish current turn resolutions (graceful)
3. Close WebSocket connections
4. Close SQLite connections
5. Exit

**Reload:**
```bash
daemon reload
```

1. Receive SIGHUP
2. Re-read configuration
3. Re-discover games (hot reload)
4. Restart transport handlers if config changed

### Process Management

**Systemd Service:**

```ini
[Unit]
Description=EC4X Game Daemon
After=network.target

[Service]
Type=simple
User=ec4x
Group=ec4x
WorkingDirectory=/var/ec4x
ExecStart=/usr/local/bin/daemon start --config=/etc/ec4x/daemon.toml
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
```

**Commands:**
```bash
systemctl start ec4x-daemon
systemctl stop ec4x-daemon
systemctl restart ec4x-daemon
systemctl reload ec4x-daemon  # Hot reload games
systemctl status ec4x-daemon
journalctl -u ec4x-daemon -f  # View logs
```

### Multi-Game Management

**Capacity Planning:**

Per-game resource usage:
- Memory: ~10-50 MB (depending on map size)
- CPU: ~0.1% idle, ~10% during turn resolution
- I/O: Minimal (SQLite writes on turn resolution)

**Expected capacity**:
- Single daemon: 100+ games
- Bottleneck: Turn resolution CPU (serialized per game)
- Mitigation: Parallelize turn resolution across games

**Resource Limits:**
```toml
[daemon]
max_concurrent_resolutions = 4  # Process 4 turns in parallel
max_games = 100                 # Refuse to monitor more than 100 games
memory_limit_mb = 2048          # Restart if exceeds 2 GB
```

### Concurrency Model

**Single-Threaded Event Loop:**
```
Main thread:
  - Game discovery
  - Order collection
  - Turn readiness checks
  - Result distribution

Worker pool:
  - Turn resolution (CPU-intensive)
  - Nostr encryption/decryption
  - Delta generation
```

**Thread Safety:**
- SQLite writes: Serialized per database file
- Nostr publishing: Async queue with worker threads
- Game state: Immutable during resolution (transaction isolation)

## Monitoring and Observability

### Health Checks

**HTTP Endpoint** (optional):
```bash
curl http://localhost:8080/health
{
  "status": "healthy",
  "games_active": 5,
  "turns_resolved_last_hour": 12,
  "nostr_connected": true,
  "uptime_seconds": 86400
}
```

### Metrics

**Key Metrics to Track:**
- Games monitored (total, by transport mode)
- Orders received per minute
- Turns resolved per hour
- Turn resolution latency (p50, p95, p99)
- Nostr events sent/received per minute
- WebSocket connection status
- SQLite query latency
- Error rate

**Prometheus Integration:**
```
# HELP ec4x_games_active Number of active games
# TYPE ec4x_games_active gauge
ec4x_games_active{transport="localhost"} 3
ec4x_games_active{transport="nostr"} 2

# HELP ec4x_turn_resolution_seconds Time to resolve a turn
# TYPE ec4x_turn_resolution_seconds histogram
ec4x_turn_resolution_seconds_bucket{le="1"} 45
ec4x_turn_resolution_seconds_bucket{le="5"} 50
ec4x_turn_resolution_seconds_bucket{le="+Inf"} 50
```

### Logging

**Log Levels:**
- DEBUG: Order receipt, state queries, transport details
- INFO: Turn resolution start/complete, game discovery
- WARN: Missing orders on deadline, retry attempts
- ERROR: Turn resolution failures, database errors, Nostr connection loss

**Structured Logging:**
```json
{
  "timestamp": "2025-01-16T12:34:56Z",
  "level": "INFO",
  "message": "Turn resolved",
  "game_id": "game-123",
  "turn": 42,
  "duration_ms": 1234,
  "orders_received": 5,
  "combats": 2
}
```

**Log Rotation:**
```
/var/log/ec4x/daemon.log
/var/log/ec4x/daemon.log.1
/var/log/ec4x/daemon.log.2.gz
```

### Alerting

**Critical Alerts:**
- Daemon crashed (systemd restart)
- Database corruption detected
- All Nostr relays disconnected
- Turn resolution failed 3+ times

**Warning Alerts:**
- Turn resolution taking > 10 seconds
- Game missing orders on deadline
- Nostr relay latency > 5 seconds
- Disk space low

## Configuration

### daemon.toml

```toml
[daemon]
db_path = "/var/ec4x/games.db"
poll_interval = 30              # Check for orders every 30s
discovery_interval = 300        # Re-scan for games every 5 min
max_concurrent_resolutions = 4  # Process 4 turns in parallel

[localhost]
game_root = "/var/ec4x/games"   # Root directory for localhost games
poll_interval = 30              # Override main poll_interval

[nostr]
timeout_seconds = 30
max_relays = 5
reconnect_delay_seconds = 5
publish_batch_size = 10
publish_rate_limit = 10         # Events per second per relay

[logging]
level = "INFO"
file = "/var/log/ec4x/daemon.log"
max_size_mb = 100
max_backups = 5

[metrics]
enabled = true
port = 9090
path = "/metrics"

[health]
enabled = true
port = 8080
path = "/health"
```

## Error Handling

### Turn Resolution Failures

**Scenario**: Game engine throws error during resolution

**Response:**
1. ROLLBACK transaction
2. Log full error with stack trace
3. Leave game in 'Active' phase
4. Increment failure counter in metadata
5. If failures > 3: Set phase to 'Paused', notify moderator
6. Continue processing other games

### Nostr Relay Disconnection

**Scenario**: WebSocket connection drops

**Response:**
1. Log disconnection event
2. Attempt reconnect with exponential backoff
3. Resubscribe to all game filters on reconnect
4. Fetch missed events (if relay supports)
5. If all relays fail: Alert moderator, continue with cached state

### Order Validation Failure

**Scenario**: Player submits invalid order

**Response:**
1. Log validation error
2. Reject order (don't insert into orders table)
3. Send error notification to player (Nostr: EventKindError)
4. On turn deadline: Resolve with valid orders, treat invalid as "Hold"

### Database Corruption

**Scenario**: SQLite reports corruption

**Response:**
1. Log critical error
2. Attempt automatic recovery: `PRAGMA integrity_check`
3. If recoverable: Run recovery, continue
4. If unrecoverable: Pause affected game, alert moderator, restore from backup

## Security Considerations

### Moderator Key Protection

**Critical**: Moderator's private key can:
- Decrypt all player orders
- Sign game state updates
- Impersonate the game server

**Best Practices:**
- Store private key encrypted on disk
- Decrypt in memory only during startup (passphrase)
- Never log private key
- Use secure key derivation (argon2)
- Consider HSM for production

### Order Validation

**Prevent Cheating:**
- Validate all orders against game rules
- Check fleet ownership
- Verify target validity
- Rate limit order submissions (Nostr)
- Detect replayed/forged Nostr events

### Denial of Service

**Mitigations:**
- Rate limit Nostr event processing
- Reject oversized order packets
- Limit max games per daemon
- Timeout slow queries
- Circuit breaker for failing relays

## Testing

### Unit Tests

- Turn resolution logic
- Order validation
- Delta generation
- Intel updates

### Integration Tests

- Localhost order collection and resolution
- Nostr event encryption/decryption
- Multi-game management
- Error handling and recovery

### Load Tests

- 100 concurrent games
- 1000 orders per minute
- Large map sizes (500+ systems)
- Turn resolution under load

### Chaos Tests

- Random relay disconnections
- Simulated database errors
- Corrupted order packets
- Concurrent turn resolution attempts

## Future Enhancements

### Parallel Turn Resolution

**Current**: Resolve turns sequentially
**Future**: Resolve independent games in parallel
**Benefit**: Higher throughput for multi-game daemon

### Replay and Rollback

**Current**: Turn resolution is final
**Future**: Store pre-resolution state, allow rollback on moderator approval
**Use Case**: Correct bugs, adjudicate disputes

### Distributed Daemon

**Current**: Single daemon per server
**Future**: Multiple daemons share game load (distributed lock)
**Benefit**: Horizontal scalability, high availability

### AI Players

**Current**: Only human players
**Future**: Daemon can control AI houses with configurable strategies
**Use Case**: Fill empty slots, practice mode

## Related Documentation

- [Architecture Overview](./overview.md)
- [Storage Layer](./storage.md)
- [Transport Layer](./transport.md)
- [Data Flow](./dataflow.md)
- [Deployment Guide](../EC4X-Deployment.md)
