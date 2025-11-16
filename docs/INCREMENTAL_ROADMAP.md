# EC4X Incremental Implementation Roadmap

## Philosophy

**Keep the architecture design, build it incrementally.**

Target architecture (from docs/architecture/):
- TEA pattern with async event loop
- Per-game SQLite databases
- Transport abstraction (localhost → Nostr)
- Intel system for fog of war

**Implementation strategy:**
- Build in small, testable increments
- Each milestone produces a playable/testable artifact
- Add complexity only when the simpler version works
- Solo developer = fast iteration, no coordination overhead

---

## Milestone 1: Playable Offline Game

**Goal:** 2-player hotseat game you can actually play

### What to Build

**Game Engine (Pure Logic)**
```nim
# src/engine/game.nim
proc createGame(numPlayers: int): GameState
proc validateOrder(order: Order, state: GameState): bool
proc resolveTurn(state: GameState, orders: Table[HouseId, seq[Order]]): GameState
```

**Minimal Implementation:**
- ✅ Already have: starmap generation, coordinates, types
- ⚠️ Implement: combat resolution (ships fight, take damage, die)
- ⚠️ Implement: basic economy (colonies produce, construction happens)
- ⚠️ Implement: movement (fleets move along lanes)
- ⚠️ Skip for now: diplomacy, espionage, advanced economy

**Simple CLI Interface**
```nim
# src/main/hotseat.nim
proc main() =
  let game = createGame(numPlayers = 2)

  while not game.isOver:
    # Show current state (no fancy UI yet)
    echo "Turn ", game.turn
    echo "Player ", game.currentPlayer, "'s turn"

    # Collect orders via TOML file or stdin
    let orders = collectOrders(game.currentPlayer)

    # When all players submitted, resolve
    if allOrdersIn(game):
      game = resolveTurn(game, orders)
      displayResults(game)
```

**Storage: Simple Files (No SQLite Yet)**
```
game_data/
├── game.json          # Full game state as JSON
├── house_alpha_orders.toml
└── house_beta_orders.toml
```

### Deliverable

**Working game loop:**
```bash
$ nimble build
$ ./bin/hotseat new test_game --players=2

Game created: test_game
Turn 1 - House Alpha's turn

$ ./bin/hotseat orders test_game --house=alpha
# Opens editor with TOML template

$ ./bin/hotseat orders test_game --house=beta
# Opens editor with TOML template

$ ./bin/hotseat resolve test_game
Resolving turn 1...
- Fleet Alpha-1 moved to Delta
- Fleet Beta-1 moved to Gamma
- Combat in system Delta: Alpha wins!

Turn 2 - House Alpha's turn
```

**Success Criteria:**
- [ ] Can create 2-player game
- [ ] Can submit orders for each player
- [ ] Turn resolution produces correct results
- [ ] Combat works (ships take damage, die)
- [ ] Movement works (fleets change locations)
- [ ] Economy works (colonies produce, ships built)
- [ ] Game ends with winner declared

**Skip for M1:**
- ❌ TEA pattern (just functions for now)
- ❌ SQLite (JSON files are fine)
- ❌ Daemon (manual turn resolution)
- ❌ Async (everything synchronous)
- ❌ Fancy UI (CLI is fine)
- ❌ Fog of war (both players see everything)

---

## Milestone 2: Add SQLite Persistence

**Goal:** Replace JSON files with per-game SQLite databases

### What to Build

**Database Layer**
```nim
# src/storage/database.nim
type Database = object
  conn: DbConn
  path: string

proc openDatabase(gamePath: string): Database
proc saveGameState(db: Database, state: GameState)
proc loadGameState(db: Database): GameState
proc saveOrders(db: Database, houseId: HouseId, orders: seq[Order])
proc loadOrders(db: Database, turn: int): Table[HouseId, seq[Order]]
```

**Schema (Simplified)**
```sql
-- Start simple, add tables as needed
CREATE TABLE games (
  id TEXT PRIMARY KEY,
  turn INTEGER,
  phase TEXT,
  created_at INTEGER
);

CREATE TABLE houses (
  id TEXT PRIMARY KEY,
  game_id TEXT,
  name TEXT,
  prestige INTEGER
);

CREATE TABLE fleets (
  id TEXT PRIMARY KEY,
  game_id TEXT,
  owner_house_id TEXT,
  location_system_id TEXT
);

-- Add more tables as you need them
```

**Refactor hotseat CLI**
```nim
# Change from:
let game = loadFromJson("game.json")

# To:
let db = openDatabase("game_data/test_game/ec4x.db")
let game = db.loadGameState()
```

### Deliverable

**Same hotseat game, but with SQLite:**
```
game_data/test_game/
└── ec4x.db          # All game state here now
```

**Success Criteria:**
- [ ] Game state persists in SQLite
- [ ] Can resume game from database
- [ ] Orders saved to database
- [ ] All M1 features still work

**Skip for M2:**
- ❌ TEA pattern
- ❌ Daemon
- ❌ Multiple games (focus on one game working perfectly)

---

## Milestone 3: Localhost Daemon

**Goal:** Automated turn resolution via daemon process

### What to Build

**Simple Daemon (No TEA Yet)**
```nim
# src/main/daemon_simple.nim
proc main() =
  let gameDir = "/var/ec4x/games/test_game"
  let db = openDatabase(gameDir / "ec4x.db")

  while true:
    # Poll for orders every 30 seconds
    sleep(30_000)

    let game = db.loadGameState()
    let orders = db.loadOrders(game.turn)

    # Check if ready to resolve
    if allOrdersSubmitted(game, orders) or deadlineReached(game):
      echo "Resolving turn ", game.turn

      let newState = resolveTurn(game, orders)
      db.saveGameState(newState)

      # Write results to files for players
      exportTurnResults(db, game.turn)
```

**Order Submission**
```nim
# src/main/submit.nim
proc main() =
  let db = openDatabase("game_data/test_game/ec4x.db")
  let orders = parseOrdersFile("my_orders.toml")

  db.saveOrders(houseId = "alpha", orders)
  echo "Orders submitted for turn ", db.getCurrentTurn()
```

**File Watching (Optional)**
```nim
# Watch for new order files instead of polling
# Use inotify on Linux
proc watchForOrders(gameDir: string, callback: proc(orders: Orders))
```

### Deliverable

**Automated game server:**
```bash
# Terminal 1: Start daemon
$ ./bin/daemon start game_data/test_game
Daemon started for game test_game
Monitoring orders for turn 1...

# Terminal 2: Player Alpha submits
$ ./bin/submit game_data/test_game --house=alpha orders.toml
Orders submitted

# Terminal 3: Player Beta submits
$ ./bin/submit game_data/test_game --house=beta orders.toml
Orders submitted

# Terminal 1: Daemon auto-resolves
All orders received!
Resolving turn 1...
Turn 1 complete. Results exported.
Monitoring orders for turn 2...
```

**Success Criteria:**
- [ ] Daemon monitors game directory
- [ ] Auto-resolves when orders ready
- [ ] Players can submit orders independently
- [ ] Results exported after resolution

**Skip for M3:**
- ❌ TEA pattern (simple loop is fine)
- ❌ Async (synchronous polling is fine)
- ❌ Multiple games (one game at a time)

---

## Milestone 4: Refactor to TEA Pattern

**Goal:** Make daemon maintainable with predictable state management

### What to Build

**TEA Architecture**
```nim
# src/daemon/tea.nim
type
  Model = object
    game: GameState
    pendingOrders: Table[HouseId, seq[Order]]
    resolving: bool

  Msg = enum
    Tick
    OrderReceived(house: HouseId, orders: seq[Order])
    ResolveTriggered
    TurnResolved(newState: GameState)

proc update(msg: Msg, model: Model): (Model, Cmd) =
  case msg:
  of OrderReceived:
    var m = model
    m.pendingOrders[msg.house] = msg.orders

    if allOrdersReady(m):
      return (m, Cmd.msg(ResolveTriggered))
    else:
      return (m, Cmd.none)

  of ResolveTriggered:
    let cmd = Cmd.perform(
      resolveTurnAsync(model.game, model.pendingOrders),
      proc(state: GameState): Msg = TurnResolved(state)
    )
    return (model, cmd)

  of TurnResolved:
    var m = model
    m.game = msg.newState
    m.pendingOrders.clear()
    return (m, Cmd.none)

  # ... other cases

proc mainLoop() {.async.} =
  var model = loadInitialModel()
  var msgQueue = newAsyncQueue[Msg]()

  asyncCheck watchOrders(msgQueue)  # Background task
  asyncCheck tickTimer(msgQueue)    # Background task

  while true:
    let msg = await msgQueue.recv()
    let (newModel, cmd) = update(msg, model)
    model = newModel

    if not cmd.isNone:
      asyncCheck executeCmd(cmd, msgQueue)
```

### Deliverable

**Same daemon behavior, cleaner code:**
- Synchronous code refactored to async
- Predictable state management
- Easier to test (pure update function)
- Easier to add features (just add messages)

**Success Criteria:**
- [ ] All M3 features work identically
- [ ] Daemon uses TEA pattern
- [ ] Async I/O (non-blocking)
- [ ] Update function has unit tests

**Skip for M4:**
- ❌ Multiple games (still focusing on one)

---

## Milestone 5: Multi-Game Support

**Goal:** Daemon manages multiple games simultaneously

### What to Build

**Game Discovery**
```nim
type
  Model = object
    games: Table[GameId, GameInfo]   # Multiple games now!
    resolving: HashSet[GameId]
    # ...

proc discoverGames(gamesRoot: string): seq[GameId] =
  for dir in walkDirs(gamesRoot / "*"):
    if fileExists(dir / "ec4x.db"):
      yield extractGameId(dir)

# In main loop:
asyncCheck periodicGameDiscovery(msgQueue)
```

**Per-Game State**
```nim
proc update(msg: Msg, model: Model): (Model, seq[Cmd]) =
  case msg:
  of OrderReceived:
    # msg now includes gameId
    model.games[msg.gameId].addOrder(msg.order)

    if isReady(model.games[msg.gameId]):
      let cmd = Cmd.resolveGame(msg.gameId)
      return (model, @[cmd])

  of TurnResolved:
    # Multiple games can resolve concurrently
    model.games[msg.gameId].updateState(msg.result)
    return (model, @[])
```

### Deliverable

**Daemon manages multiple games:**
```bash
$ ./bin/daemon start /var/ec4x/games
Discovered 3 games:
  - game-123 (turn 5)
  - game-456 (turn 12)
  - game-789 (turn 3)

Monitoring all games...
[game-123] Orders received, resolving turn 5
[game-456] Waiting for orders (2/4)
[game-789] Orders received, resolving turn 3
```

**Success Criteria:**
- [ ] Daemon auto-discovers games
- [ ] Monitors multiple games concurrently
- [ ] Games resolve independently
- [ ] No blocking between games

---

## Milestone 6: Add Fog of War (Intel System)

**Goal:** Players only see what they should see

### What to Build

**Intel Tables**
```sql
CREATE TABLE intel_systems (
  game_id TEXT,
  house_id TEXT,
  system_id TEXT,
  last_scouted_turn INTEGER,
  visibility_level TEXT
);

CREATE TABLE intel_fleets (
  game_id TEXT,
  house_id TEXT,
  fleet_id TEXT,
  detected_turn INTEGER,
  ship_count INTEGER
);
```

**Intel Update Logic**
```nim
proc updateIntel(db: Database, gameId: string, turn: int) =
  for house in db.getHouses(gameId):
    # Update what this house can see
    db.updateSystemVisibility(house.id, turn)
    db.updateFleetDetection(house.id, turn)

proc getPlayerView(db: Database, gameId: string, houseId: string): GameState =
  # Return filtered game state based on intel
  var state = db.loadGameState()

  # Filter to only visible systems
  state.systems = db.getVisibleSystems(houseId)

  # Filter to only detected fleets
  state.fleets = db.getDetectedFleets(houseId)

  return state
```

**Update Turn Resolution**
```nim
proc resolveTurn(state: GameState, orders: Orders): TurnResult =
  let result = engine.resolveTurn(state, orders)

  # After resolution, update intel
  updateIntelTables(db, game.id, game.turn)

  return result
```

### Deliverable

**Players see different views:**
```bash
# Player Alpha
$ ./bin/view game_data/test_game --house=alpha
Turn 5:
  Your fleets: 3 (full detail)
  Visible systems: 8 (5 scouted, 3 adjacent)
  Enemy fleets detected: 1 (in system Delta)

# Player Beta
$ ./bin/view game_data/test_game --house=beta
Turn 5:
  Your fleets: 2 (full detail)
  Visible systems: 6 (4 scouted, 2 adjacent)
  Enemy fleets detected: 2 (in systems Gamma, Epsilon)
```

**Success Criteria:**
- [ ] Intel tables track visibility
- [ ] Players see only their intel
- [ ] Intel updates after each turn
- [ ] Turn results filtered per player

---

## Milestone 7: Nostr Transport

**Goal:** Network multiplayer via Nostr protocol

### What to Build

**Transport Abstraction** (finally!)
```nim
# src/transport/transport.nim
type
  Transport* = ref object of RootObj

method submitOrders*(t: Transport, gameId: string, orders: Orders) {.base.}
method publishResults*(t: Transport, gameId: string, results: TurnResults) {.base.}

# src/transport/local_transport.nim
type LocalTransport = ref object of Transport

method submitOrders*(t: LocalTransport, gameId: string, orders: Orders) =
  writeFile(gameDir / "orders.json", orders.toJson())

# src/transport/nostr_transport.nim
type NostrTransport = ref object of Transport
  relay: WebSocket
  moderatorKeys: KeyPair

method submitOrders*(t: NostrTransport, gameId: string, orders: Orders) =
  let event = createOrderPacket(gameId, orders, t.moderatorKeys)
  await t.relay.send(event.toJson())
```

**Update Daemon**
```nim
type
  Model = object
    games: Table[GameId, GameInfo]
    transports: Table[GameId, Transport]  # Game-specific transport
    # ...

# Transport determined by game config
proc getTransport(gameId: string): Transport =
  let config = loadGameConfig(gameId)
  case config.transportMode:
  of "localhost":
    return LocalTransport(gameDir: config.gameDir)
  of "nostr":
    return NostrTransport(relay: config.relay, keys: config.keys)
```

**Implement Nostr Crypto**
```nim
# Complete the TODOs in src/transport/nostr/crypto.nim
proc nip44Encrypt*(plaintext: string, recipientPubkey: string, senderPrivkey: string): string
proc nip44Decrypt*(ciphertext: string, senderPubkey: string, recipientPrivkey: string): string
```

### Deliverable

**Same game, network multiplayer:**
```bash
# Moderator creates Nostr game
$ ./bin/moderator new net_game --mode=nostr --relay=wss://relay.damus.io

# Players join from anywhere
$ ./bin/client join net_game --relay=wss://relay.damus.io
Connected to net_game
You are House Alpha

$ ./bin/client submit orders.toml
Orders encrypted and published to relay

# Daemon receives and processes
[net_game] Received orders from npub1abc... (House Alpha)
[net_game] Received orders from npub1def... (House Beta)
[net_game] Resolving turn 1...
[net_game] Publishing encrypted results to relay
```

**Success Criteria:**
- [ ] Can create Nostr-mode games
- [ ] Players submit orders via Nostr events
- [ ] Daemon receives orders from relay
- [ ] Results published as encrypted events
- [ ] Same game mechanics as localhost

---

## Milestone 8: State Deltas

**Goal:** Bandwidth optimization for Nostr

### What to Build

**Delta Generation**
```nim
# src/storage/deltas.nim
type
  Delta = object
    turn: int
    changes: seq[Change]

  Change = object
    case kind: ChangeKind
    of ckFleetMoved:
      fleetId: string
      fromSystem: string
      toSystem: string
    of ckShipDamaged:
      shipId: string
      hullPoints: int
    # ... other change types

proc computeDelta(oldState: GameState, newState: GameState, visibleTo: HouseId): Delta
```

**Store Deltas**
```sql
CREATE TABLE state_deltas (
  game_id TEXT,
  turn INTEGER,
  house_id TEXT,
  delta_json TEXT
);
```

**Update Nostr Publishing**
```nim
proc publishResults(transport: NostrTransport, gameId: string, turn: int) =
  for house in game.houses:
    let delta = db.loadDelta(gameId, turn, house.id)

    # Check size
    if delta.toJson().len < 32000:
      # Single event
      let event = createStateDelta(gameId, turn, delta, house.pubkey)
      await transport.publish(event)
    else:
      # Chunk it
      for chunk in delta.chunk(maxSize = 32000):
        let event = createDeltaChunk(gameId, turn, chunk, house.pubkey)
        await transport.publish(event)
```

### Deliverable

**Efficient Nostr bandwidth:**
- Full state: 50 KB per player
- Delta: 2 KB per player (25x reduction!)

**Success Criteria:**
- [ ] Deltas generated after resolution
- [ ] Deltas sent instead of full state
- [ ] Chunking works for large deltas
- [ ] Clients can apply deltas

---

## Development Workflow

### Daily Routine (Solo Developer)

**Morning:**
```bash
# Pull latest, run tests
git pull
nimble test

# Pick next task from milestone
# Focus on ONE thing at a time
```

**During Development:**
```bash
# Make small commits
git commit -m "Implement fleet movement"
git commit -m "Add movement tests"
git commit -m "Fix pathfinding bug"

# Test frequently
nimble test
./bin/hotseat new test --players=2  # Manual test
```

**End of Day:**
```bash
# Push working code
git push

# Update roadmap (mark completed tasks)
```

### When Stuck

**Simplify:**
- Cut scope (defer feature)
- Hardcode values (make dynamic later)
- Skip error handling (add later)

**Ask for help:**
- Post in Nim forum
- Check Nim docs
- Search GitHub issues

**Take breaks:**
- Walk away
- Work on different milestone
- Play a game (research!)

### Milestone Completion Checklist

Before moving to next milestone:
- [ ] All features work
- [ ] Tests pass
- [ ] Manual playtesting successful
- [ ] Commit and tag: `git tag milestone-N`
- [ ] Document what you learned
- [ ] Decide: continue or pivot?

---

## Success Metrics

### Milestone 1
- Can I play a complete game with a friend?
- Is it fun?
- Do the rules make sense?

### Milestone 4
- Is the code easier to understand?
- Can I add features without breaking things?
- Are tests catching bugs?

### Milestone 7
- Can someone in another city play with me?
- Does it work over Nostr?
- Is latency acceptable?

### Milestone 8
- Are message sizes reasonable?
- Does chunking work reliably?
- Is bandwidth under 10 KB per turn per player?

---

## Risk Management

### Risk: Milestone takes 3x longer than estimated

**Mitigation:**
- Cut scope (defer features)
- Ask for help earlier
- Timebox (if > 2 weeks, move on)

### Risk: Architecture doesn't work in practice

**Mitigation:**
- Each milestone proves architecture incrementally
- Refactor early (M4) while codebase small
- Don't be afraid to pivot

### Risk: Game isn't fun

**Mitigation:**
- Playtest at M1 (before investing in architecture)
- Get feedback from friends
- Iterate on rules, not tech

### Risk: Burnout

**Mitigation:**
- Take breaks between milestones
- Celebrate small wins
- Ship early, ship often
- Remember: this is supposed to be fun!

---

## What to Skip (For Now)

**Don't build until you need it:**
- ❌ Comprehensive docs (write as you go)
- ❌ Perfect error handling (good enough is fine)
- ❌ Full test coverage (test critical paths)
- ❌ Performance optimization (premature)
- ❌ All 16 order types (start with 5)
- ❌ Complete economy system (minimal viable)
- ❌ Diplomacy (defer to post-MVP)
- ❌ Spectator mode
- ❌ Game replays
- ❌ Admin tools (build when you need them)

**Add these after you have a working, playable game.**

---

## Key Principle

> **Build the simplest thing that proves the next architectural layer.**

- M1 proves game engine works
- M2 proves SQLite works
- M3 proves daemon works
- M4 proves TEA works
- M7 proves Nostr works

Each milestone de-risks the architecture incrementally.

---

*Last updated: 2025-01-16*
