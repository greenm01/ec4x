# EC4X Daemon Design

## Overview

The **daemon** is the autonomous turn processing service that powers EC4X. It monitors active games, collects player commands, resolves turns, and publishes results—all without human intervention.

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
│  │  • Validate commands                     │  │
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
1. Scan game directories for `ec4x.db` files
2. Open each database and query: `SELECT * FROM games WHERE phase = 'Active'`
3. Load transport configuration for each game
4. Initialize transport handlers (filesystem watchers, Nostr subscriptions)

**During Runtime:**
1. Periodically re-scan for new game directories (hot reload)
2. Detect games added by admin tooling
3. Detect games paused/resumed/completed
4. Adjust monitoring dynamically

**Directory Structure:**
```
/var/ec4x/games/
├── game-uuid-1/ec4x.db  → Discovered
├── game-uuid-2/ec4x.db  → Discovered
└── game-uuid-3/ec4x.db  → Discovered
```

**Configuration:**
```kdl
daemon {
  games_root "/var/ec4x/games"
  poll_interval 30
  discovery_interval 300  // re-scan for new games every 5 min
}
```

### 2. Command Collection

**Localhost Mode:**
```
Loop every poll_interval:
  For each active game:
    For each house:
      Check houses/<house>/orders_pending.json
      If exists:
        Parse and validate JSON
        Insert into commands table
        Delete orders_pending.json
        Log command receipt
```

**Nostr Mode:**
```
Maintain WebSocket subscription:
  Filter: kind=30402, d=<game_ids>, p=<daemon_pubkey>

On EVENT received:
  Verify signature
  Validate required tags (d, turn, p)
  Validate turn matches current game turn
  Decrypt with daemon private key
  Parse msgpack CommandPacket
  Upsert commands row by (game_id, turn, house_id)
  Cache event ID for replay protection
  Log command receipt
```

**Nostr Turn Command Lifecycle (30402):**

Normative rules:

- Players MAY resubmit command packets to revise orders for the same turn.
- Daemon MUST retain only the latest valid packet for
  `(game_id, house_id, turn)`.
- Invalid signatures, missing tags, and wrong-turn packets are rejected.
- Turn readiness checks use the authoritative packet per house.

Implementation references:

- `src/daemon/daemon.nim` (`processIncomingCommand`)
- `src/daemon/persistence/writer.nim` (`saveCommandPacket`)
- `src/daemon/transport/nostr/client.nim` (`subscribeDaemon`)

**Multi-Game Efficiency:**
- Localhost: Single filesystem poll covers all games in directory tree
- Nostr: Single WebSocket per relay with multi-game filter

### 3. Turn Readiness Check

**Conditions for Turn Resolution:**

**Condition A: All Commands Received**
```sql
SELECT
  (SELECT COUNT(*) FROM houses WHERE game_id = ?id AND eliminated = 0) as expected,
  (SELECT COUNT(DISTINCT house_id) FROM commands WHERE game_id = ?id AND turn = ?turn) as received;
-- If expected == received, all commands in
```

**Condition B: Deadline Passed**
```sql
SELECT turn_deadline FROM games WHERE id = ?id;
-- If turn_deadline < current_time, resolve with available commands
```

**Policy Options:**
- Strict: Wait for all commands (no deadline)
- Deadline: Auto-resolve on deadline
- Hybrid: Wait up to deadline, then resolve with available commands
- Grace period: X minutes after last command received

### 4. Turn Resolution

**Process (Atomic Transaction):**

```
BEGIN TRANSACTION;

1. Lock game row (prevent concurrent resolution)
   UPDATE games SET phase = 'Resolving' WHERE id = ?id;

2. Load game state from SQLite (msgpack deserialization)
   - Single query: SELECT state_msgpack FROM games
   - Deserialize complete GameState object (<1ms)
   - All entities, diplomacy, intel included

3. Load commands for current turn
   - All submitted commands
   - Default "Hold" commands for missing submissions

4. Run game engine resolution (4 phases)
   a. Income Phase: Calculate production, prestige
   b. Command Phase: Execute commands
      - CMD5: Execute zero-turn commands (DetachShips, MergeFleets,
        TransferShips, Reactivate, cargo/fighter ops) sequentially
        per house, modifying GameState immediately within this phase
      - Process operational fleet orders (movement, colonization)
   c. Conflict Phase: Resolve combat
   d. Maintenance Phase: Construction, research, upkeep

5. Save new game state to SQLite (msgpack serialization)
   - Serialize complete GameState to msgpack (<1ms)
   - Single UPDATE: UPDATE games SET state_msgpack = ?, turn = ?
   - Atomic state update

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

10. Mark commands as processed
    UPDATE commands SET processed = 1 WHERE game_id = ?id AND turn = ?turn;

11. Commit game state
    UPDATE games SET phase = 'Active', turn = turn + 1, updated_at = ?now WHERE id = ?id;

COMMIT;
```

**Error Handling:**
- On any error: ROLLBACK transaction
- Log error details
- Notify operator/admin tooling
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
  3. Generate filtered delta msgpack
  4. Encrypt to house's pubkey (NIP-44)
  5. Create EventKindTurnResults (30403)
  6. Sign with daemon keypair
  7. Publish to relay and record outbound event id

Public results:
  1. Generate public turn summary
  2. Keep as file/log output (no dedicated turn-complete event kind)

Publish loop (separate thread):
  Use Nostr client publisher
  Retry publish according to relay client behavior
```

Implementation references:

- `src/daemon/publisher.nim` (`publishTurnResults`, `publishFullState`)
- `src/daemon/transport/nostr/events.nim` (`createTurnResults`)

## Operational Model

### Daemon Identity (Nostr Keypair)

The daemon requires a Nostr keypair to sign GameDefinition events (30400) and
publish slot claim responses. The keypair is stored at:

```
~/.local/share/ec4x/daemon_identity.kdl
```

**On a fresh machine this file does not exist.** Run the `init` command once
before starting the daemon for the first time:

```bash
ec4x-daemon init
```

Output:
```
Daemon identity created at: /home/user/.local/share/ec4x/daemon_identity.kdl
Public key (npub): npub1...
Keep this file safe - back it up alongside your game databases.
```

Running `init` again is safe — it will never overwrite an existing identity:
```
Daemon identity already exists at: /home/user/.local/share/ec4x/daemon_identity.kdl
Public key (npub): npub1...
No changes made.
```

If the daemon is started without an identity file, it exits with:
```
Daemon identity missing. Run 'ec4x-daemon init' to generate a keypair.
```

**Symptoms in systemd:** `Active: activating (auto-restart) (Result: exit-code)`

**Fix:** Run `ec4x-daemon init` once, then start the service normally.

**Transferring an identity to another machine:**

Copy `~/.local/share/ec4x/daemon_identity.kdl` to the same path on the new
machine. Do **not** run `ec4x-daemon init` — that would overwrite it.

**Environment file location:**

```
~/.config/ec4x/ec4x-daemon.env
```

The systemd unit reads this file via `EnvironmentFile=`. Variables:

```ini
EC4X_DATA_DIR=/home/mag/dev/ec4x/data   # root of game directories
EC4X_RELAY_URLS=ws://localhost:8080      # comma-separated relay WebSocket URLs
EC4X_LOG_LEVEL=info
```

---

### Daemon Lifecycle

**Startup:**
```bash
daemon start --config-kdl=/etc/ec4x/daemon.kdl
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
  2. Collect commands from all transports
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
ExecStart=/usr/local/bin/daemon start --config-kdl=/etc/ec4x/daemon.kdl
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
```kdl
daemon {
  max_concurrent_resolutions 4  // Process 4 turns in parallel
  max_games 100                 // Refuse to monitor more than 100 games
  memory_limit_mb 2048          // Restart if exceeds 2 GB
}
```

### Event Loop Architecture (SAM Pattern)

The daemon uses **State-Action-Model (SAM)** pattern with async/await for non-blocking concurrency.

#### Why SAM?

**Benefits:**
- **Predictable State**: All state changes go through pure `update()` function
- **Testable**: Pure functions easy to unit test
- **Single-Threaded**: No locks, mutexes, or race conditions
- **Non-Blocking**: Async I/O doesn't block the event loop
- **Concurrent**: Multiple games resolve simultaneously without threads

#### SAM Components

**Model (Application State):**
```nim
type
  DaemonModel = object
    games: Table[GameId, GameInfo]        # All managed games
    resolving: HashSet[GameId]            # Currently resolving games
    transports: Table[GameId, Transport]  # Transport handlers
    pendingCommands: Table[GameId, seq[Command]]
    deadlines: Table[GameId, Deadline]
    nostrConnections: Table[RelayUrl, WebSocket]
```

**Messages (Events):**
```nim
type
  DaemonMsg = enum
    # Timer events
    Tick(timestamp: Time)
    DeadlineReached(gameId: GameId)

    # Command events
    OrderReceived(gameId: GameId, houseId: HouseId, command: Command)

    # Turn resolution events
    TurnResolving(gameId: GameId)
    TurnResolved(gameId: GameId, result: TurnResult)

    # Result publishing events
    ResultsPublishing(gameId: GameId)
    ResultsPublished(gameId: GameId)

    # Discovery events
    GameDiscovered(gameDir: string)
    GameRemoved(gameId: GameId)

    # Transport events
    NostrConnected(relay: RelayUrl)
    NostrDisconnected(relay: RelayUrl)
    TransportError(gameId: GameId, error: string)
```

**Update (Pure State Transitions):**
```nim
proc update(msg: DaemonMsg, model: DaemonModel): (DaemonModel, seq[Cmd]) =
  # Pure function - no I/O, no side effects
  case msg.kind:

  of OrderReceived:
    var newModel = model
    newModel.pendingCommands[msg.gameId].add(msg.command)

    # Check if ready to resolve
    if isReadyForResolution(newModel, msg.gameId):
      let cmd = Cmd.msg(TurnResolving(gameId: msg.gameId))
      return (newModel, @[cmd])
    else:
      return (newModel, @[])

  of TurnResolving:
    var newModel = model
    newModel.resolving.incl(msg.gameId)

    # Kick off async resolution (doesn't block!)
    let cmd = Cmd.perform(resolveTurnAsync(msg.gameId), TurnResolved)
    return (newModel, @[cmd])

  of TurnResolved:
    var newModel = model
    newModel.resolving.excl(msg.gameId)
    newModel.games[msg.gameId].updateState(msg.result)

    # Kick off async publishing
    let cmd = Cmd.perform(publishResultsAsync(msg.gameId, msg.result), ResultsPublished)
    return (newModel, @[cmd])

  # ... other message handlers
```

**Commands (Async Effects):**
```nim
type
  Cmd = proc(): Future[DaemonMsg] {.async.}

# Async turn resolution (non-blocking)
proc resolveTurnAsync(gameId: GameId): Future[TurnResult] {.async.} =
  let db = await openDbAsync(gameId)
  let state = await db.loadGameState()
  let commands = await db.loadCommands()

  # Pure game engine (fast)
  let result = engine.resolveTurn(state, commands)

  # Save results
  await db.saveGameState(result.newState)
  await db.close()

  return result

# Async result publishing (non-blocking)
proc publishResultsAsync(gameId: GameId, result: TurnResult): Future[void] {.async.} =
  for house in result.houses:
    let delta = generateDelta(house)
    await transport.publish(gameId, house, delta)
```

#### Main Event Loop

**Non-blocking concurrent execution:**

```nim
proc mainLoop() {.async.} =
  var model = initModel()
  var msgQueue = newAsyncQueue[DaemonMsg]()
  var pendingCmds: seq[Future[DaemonMsg]] = @[]

  # Background tasks (run concurrently)
  asyncCheck tickTimer(msgQueue)              # Periodic poll
  asyncCheck discoverGames(msgQueue)          # Hot reload
  asyncCheck listenNostr(msgQueue)            # WebSocket subscriptions
  asyncCheck watchFilesystem(msgQueue)        # File watchers

  # Main event loop
  while true:
    # Wait for next message (non-blocking)
    let msg = await msgQueue.recv()

    # Update model (pure, instant)
    let (newModel, newCmds) = update(msg, model)
    model = newModel

    # Execute commands concurrently
    for cmd in newCmds:
      let future = cmd()
      pendingCmds.add(future)

    # Check completed commands (non-blocking)
    var completed: seq[int] = @[]
    for i, fut in pendingCmds:
      if fut.finished:
        completed.add(i)
        let resultMsg = fut.read()
        msgQueue.addLast(resultMsg)

    # Remove completed futures
    for i in countdown(completed.high, 0):
      pendingCmds.delete(completed[i])

    # Yield to async scheduler
    await sleepAsync(1)
```

#### Concurrency in Action

**Example: 3 games resolving simultaneously**

```
Time 0ms:
  Msg(TurnResolving, game-a) → update() → Cmd(resolveTurnAsync)
  Msg(TurnResolving, game-b) → update() → Cmd(resolveTurnAsync)
  Msg(TurnResolving, game-c) → update() → Cmd(resolveTurnAsync)

  All 3 resolveTurnAsync() futures running concurrently!
  Event loop continues processing other messages...

Time 100ms:
  Msg(OrderReceived, game-d) → processed immediately
  Games a, b, c still resolving in background

Time 5000ms:
  resolveTurnAsync(game-a) completes
  → Msg(TurnResolved, game-a) → msgQueue

Time 5200ms:
  resolveTurnAsync(game-c) completes
  → Msg(TurnResolved, game-c) → msgQueue

Time 6000ms:
  resolveTurnAsync(game-b) completes
  → Msg(TurnResolved, game-b) → msgQueue
```

**No blocking! All games processed concurrently on single thread.**

#### Transport Integration (Async)

**Nostr Subscriptions:**
```nim
proc listenNostr(msgQueue: AsyncQueue[DaemonMsg]) {.async.} =
  let ws = await newWebSocket(relay)

  while true:
    let packet = await ws.receiveStrPacket()  # Non-blocking
    let event = parseNostrEvent(packet)

    if event.kind == 30402:  # Turn command packet
      let command = decryptCommand(event)
      await msgQueue.send(Msg(
        kind: OrderReceived,
        gameId: extractGameId(event),
        command: command
      ))
```

**Filesystem Watchers:**
```nim
proc watchFilesystem(msgQueue: AsyncQueue[DaemonMsg]) {.async.} =
  let watcher = initInotify()

  for gameDir in gameDirs:
    watcher.addWatch(gameDir / "houses", IN_CREATE)

  while true:
    let events = await watcher.readAsync()  # Non-blocking

    for event in events:
      if event.name.endsWith("orders_pending.json"):
        let command = parseOrderFile(event.path)
        await msgQueue.send(Msg(
          kind: OrderReceived,
          gameId: extractGameId(event.path),
          command: command
        ))
```

#### Performance Characteristics

**Single async thread handles:**
- ✅ 100+ concurrent game resolutions
- ✅ 1000+ WebSocket connections
- ✅ 10,000+ file watches
- ✅ Millisecond-level responsiveness

**When to use thread pool:**
- Turn resolution takes > 10 seconds per game
- Use `spawn` for CPU-heavy computation
- Return via channel → Msg

#### Testability

**Pure update function:**
```nim
# Easy to unit test!
test "command received triggers resolution when ready":
  let model = DaemonModel(
    games: {"game-1": gameWithCommands(4)}.toTable,
    pendingCommands: {"game-1": @[]}.toTable
  )

  let msg = Msg(kind: OrderReceived, gameId: "game-1", command: order5)
  let (newModel, cmds) = update(msg, model)

  check newModel.pendingCommands["game-1"].len == 5
  check cmds.len == 1  # Should trigger resolution
  check cmds[0] is TurnResolving
```

**Thread Safety:**
- ✅ No locks needed (single-threaded)
- ✅ No race conditions
- ✅ All state changes in `update()`
- ✅ SQLite writes per-game (isolated)
- ✅ Game state immutable during resolution

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
- Commands received per minute
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
- DEBUG: Command receipt, state queries, transport details
- INFO: Turn resolution start/complete, game discovery
- WARN: Missing commands on deadline, retry attempts
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
- Game missing commands on deadline
- Nostr relay latency > 5 seconds
- Disk space low

## Configuration

### daemon.kdl

```kdl
daemon {
  db_path "/var/ec4x/games.db"
  poll_interval 30              // Check for commands every 30s
  discovery_interval 300        // Re-scan for games every 5 min
  max_concurrent_resolutions 4  // Process 4 turns in parallel
}

localhost {
  game_root "/var/ec4x/games"   // Root directory for localhost games
  poll_interval 30              // Override main poll_interval
}

nostr {
  timeout_seconds 30
  max_relays 5
  reconnect_delay_seconds 5
  publish_batch_size 10
  publish_rate_limit 10         // Events per second per relay
}

logging {
  level "INFO"
  file "/var/log/ec4x/daemon.log"
  max_size_mb 100
  max_backups 5
}

metrics {
  enabled #true
  port 9090
  path "/metrics"
}

health {
  enabled #true
  port 8080
  path "/health"
}
```

## Error Handling

### Turn Resolution Failures

**Scenario**: Game engine throws error during resolution

**Response:**
1. ROLLBACK transaction
2. Log full error with stack trace
3. Leave game in 'Active' phase
4. Increment failure counter in metadata
5. If failures > 3: Set phase to 'Paused', notify operator
6. Continue processing other games

### Nostr Relay Disconnection

**Scenario**: WebSocket connection drops

**Response:**
1. Log disconnection event
2. Attempt reconnect with exponential backoff
3. Resubscribe to all game filters on reconnect
4. Fetch missed events (if relay supports)
5. If all relays fail: Alert operator, continue with cached state

### Command Validation Failure

**Scenario**: Player submits invalid command

**Response:**
1. Log validation error
2. Reject command (don't insert into commands table)
3. Optionally notify player via transport-specific UX/status messaging
4. On turn deadline: Resolve with valid commands, treat invalid as "Hold"

### Database Corruption

**Scenario**: SQLite reports corruption

**Response:**
1. Log critical error
2. Attempt automatic recovery: `PRAGMA integrity_check`
3. If recoverable: Run recovery, continue
4. If unrecoverable: Pause game, alert operator, restore from backup

## Security Considerations

### Daemon Key Protection

**Critical**: Daemon private key can:
- Decrypt all player commands
- Sign game state updates
- Impersonate the daemon

**Best Practices:**
- Store private key encrypted on disk
- Decrypt in memory only during startup (passphrase)
- Never log private key
- Use secure key derivation (argon2)
- Consider HSM for production

### Command Validation

**Prevent Cheating:**
- Validate all commands against game rules
- Check fleet ownership
- Verify target validity
- Rate limit command submissions (Nostr)
- Detect replayed/forged Nostr events

### Denial of Service

**Mitigations:**
- Rate limit Nostr event processing
- Reject oversized command packets
- Limit max games per daemon
- Timeout slow queries
- Circuit breaker for failing relays

## Testing

### Unit Tests

- Turn resolution logic
- Command validation
- Delta generation
- Intel updates

### Integration Tests

- Localhost command collection and resolution
- Nostr event encryption/decryption
- Multi-game management
- Error handling and recovery

### Load Tests

- 100 concurrent games
- 1000 commands per minute
- Large map sizes (500+ systems)
- Turn resolution under load

### Chaos Tests

- Random relay disconnections
- Simulated database errors
- Corrupted command packets
- Concurrent turn resolution attempts

## Future Enhancements

### Parallel Turn Resolution

**Current**: Resolve turns sequentially
**Future**: Resolve independent games in parallel
**Benefit**: Higher throughput for multi-game daemon

### Replay and Rollback

**Current**: Turn resolution is final
**Future**: Store pre-resolution state, allow rollback on operator approval
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
