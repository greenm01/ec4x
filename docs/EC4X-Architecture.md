# EC4X Architecture

# EC4X – Project Layout & Architecture Overview

---

## 1️⃣ High‑Level Vision

- **Goal:** A turn‑based 4X game written in Nim that runs on the Nostr protocol, combining the async rhythm of BBS door games with modern cryptographic identity and decentralized infrastructure.

- **Core Principle:** **Separation of concerns** – the *engine* knows nothing about networking or rendering; the *transport* only moves Nostr events (encrypted JSON); the *UI* only displays data and collects orders.

- **Development Strategy:** **Offline first** – Complete game engine supports local/hotseat multiplayer independently of Nostr. Network transport is added as a layer around the working game logic, not intertwined with it.

- **Nostr-Native Architecture:** Players submit orders as encrypted Nostr events to relays, daemon watches for order events, resolves turns on schedule, publishes encrypted game states back to players. Like a BBS door game, but with cryptographic signatures and decentralized message passing.

- **Optional Discord integration:** A lightweight bot for game announcements, turn notifications, and social coordination. The bot monitors Nostr events and posts summaries to Discord channels.

---

## 2️⃣ Layered Architecture

```
+-------------------+      +-------------------+     +------------------------+
|   UI Layer        | <──► |   Engine Core     | ◄── |   Transport Layer      |
| (Desktop client:  |      | (pure Nim, no I/O)|     | (Nostr events via      |
|  ANSI/TUI now,    |      +-------------------+     |  WebSocket to relays)  |
|  GUI later)       |                                +------------------------+
+-------------------+                                          ▲
                                                               │
                                                    +----------▼----------+
                                                    |   Nostr Relay(s)    |
                                                    | (nostr-rs-relay or  |
                                                    |  public relays)     |
                                                    +---------------------+
```

| Layer                      | Responsibility                                                                                                                                               | Typical implementation                                      |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------- |
| **Engine Core**            | All game rules, data structures, turn resolution. Pure functions, deterministic, unit‑testable.                                                              | Nim modules under `src/engine/`.                            |
| **Transport Layer**        | Nostr protocol implementation: WebSocket relay connections, event signing/encryption (NIP-44), subscription management. Converts player actions ↔ encrypted Nostr events. | `src/transport/nostr/` (client, events, crypto, filters).   |
| **UI Layer**               | Renders a player's filtered view, collects orders, publishes encrypted order events.                                                                        | `src/ui/ansi.nim` (current TUI), `src/ui/gui.nim` (future). |
| **Discord Bot** (optional) | Monitors Nostr events for game updates, posts turn summaries to Discord. Creates games, coordinates players.                                                 | `src/bot/` (separate process, bridges Nostr ↔ Discord).     |
| **Daemon**                 | Systemd‑managed service. Subscribes to order events on Nostr relays, decrypts orders, runs turn resolution, publishes encrypted game states to each player. | `src/daemon/` (subscriber, processor, publisher).           |
| **Nostr Relay**            | Message broker and event storage. Receives encrypted orders from players, delivers them to daemon. Stores game history permanently.                         | `nostr-rs-relay` (Rust) or public relays.                   |

---

## 3️⃣ Repository Layout

### Current Implementation Status

The codebase is organized into the following layers. Items marked ✅ are implemented; items marked 🚧 are prepared but not yet implemented.

```
ec4x/
├─ src/
│   ├─ core.nim                     # ✅ top‑level package (re‑exports common + engine)
│   │
│   ├─ common/                      # ✅ shared types & data structures
│   │   ├─ types.nim                # ✅ LaneType enum and base types
│   │   ├─ hex.nim                  # ✅ hexagonal coordinate system
│   │   └─ system.nim               # ✅ solar system representation
│   │
│   ├─ engine/                      # ✅ pure game logic (partially implemented)
│   │   ├─ starmap.nim              # ✅ map generation & pathfinding
│   │   ├─ fleet.nim                # ✅ fleet data structures
│   │   ├─ ship.nim                 # ✅ ship types and traversal rules
│   │   ├─ resolve.nim              # 🚧 resolveTurn(state, packets) → new state
│   │   └─ validation.nim           # 🚧 packet sanity checks
│   │
│   ├─ transport/                   # 🚧 I/O abstractions (future)
│   │   └─ nostr/                   # 🚧 Nostr protocol implementation
│   │       ├─ types.nim            # 🚧 Nostr event types, filters, constants
│   │       ├─ crypto.nim           # 🚧 secp256k1, NIP-44 encryption
│   │       ├─ events.nim           # 🚧 event creation, parsing, signing
│   │       ├─ filter.nim           # 🚧 subscription filters
│   │       └─ client.nim           # 🚧 WebSocket relay connection
│   │
│   ├─ ui/                          # 🚧 rendering & input (future)
│   │   ├─ ui.nim                   # 🚧 UI interface trait
│   │   ├─ ansi.nim                 # 🚧 ANSI terminal implementation
│   │   └─ map_export.nim           # 🚧 PDF/SVG generation for tabletop
│   │
│   ├─ daemon/                      # 🚧 systemd service (future)
│   │   ├─ daemon.nim               # 🚧 entry point (systemd ExecStart)
│   │   ├─ scheduler.nim            # 🚧 turn‑timer (midnight or manual)
│   │   ├─ subscriber.nim           # 🚧 listen for order events on relays
│   │   ├─ processor.nim            # 🚧 decrypt orders, validate, resolve turn
│   │   └─ publisher.nim            # 🚧 publish game states to players
│   │
│   ├─ bot/                         # 🚧 Discord integration (optional future)
│   │   ├─ bot.nim                  # 🚧 main bot process
│   │   ├─ commands.nim             # 🚧 slash‑command handlers (/newgame, /join,…)
│   │   └─ discord_api.nim          # 🚧 thin wrapper around discord library
│   │
│   └─ main/                        # ✅ user‑facing binaries (stubs)
│       ├─ client.nim               # ✅ client entry point (network stubs)
│       ├─ moderator.nim            # ✅ moderator CLI for game creation
│       └─ moderator/               # ✅ moderator support modules
│           ├─ config.nim           # ✅ TOML configuration
│           └─ create.nim           # ✅ game initialization
│
├─ tests/                           # ✅ comprehensive test suite
│   ├─ test_core.nim                # ✅ core functionality tests
│   ├─ test_starmap_robust.nim      # ✅ starmap generation tests
│   └─ test_starmap_validation.nim  # ✅ game spec compliance tests
│
├─ docs/                            # ✅ documentation
│   ├─ ec4x_specs.md                # ✅ complete game specification
│   ├─ EC4X-Architecture.md         # ✅ this document
│   ├─ IMPLEMENTATION_SUMMARY.md    # ✅ technical achievements
│   └─ ...                          # ✅ various technical docs
│
├─ .gitignore
├─ ec4x.nimble                      # ✅ Nimble package definition
├─ flake.nix                        # ✅ Nix development environment
└─ README.md                        # ✅ project overview
```

### What's Currently Working

- ✅ **Robust starmap generation** - Procedural hex maps with lane generation (2-12 players)
- ✅ **Pathfinding** - A* with fleet lane traversal rules
- ✅ **Game rule compliance** - Hub connectivity, player placement validated
- ✅ **Build system** - Nimble tasks for build, test, clean
- ✅ **Test suite** - 58 tests, 100% passing
- ✅ **Moderator CLI** - Game creation with TOML config

### What's Next

- 🚧 **Nostr protocol implementation** - Core transport layer (crypto, events, WebSocket client)
- 🚧 **Turn resolution engine** - Income, command, conflict, maintenance phases
- 🚧 **Daemon** - Subscriber/processor/publisher for Nostr events
- 🚧 **Desktop client** - TUI with Nostr integration for order submission
- 🚧 **Fleet orders** - 16 order types from specification
- 🚧 **Map export** - PDF/SVG generation for hybrid tabletop play
- 🚧 **Discord bot** - Optional bridge (Nostr events → Discord announcements)
- 🚧 **Nostr relay** - Deploy nostr-rs-relay for game event storage

### Naming Conventions

- **Modules** are singular (`engine/core.nim`, `transport/ssh_file.nim`).

- **Public symbols** that other layers import are prefixed with the module name (e.g., `engine.resolveTurn`).

- **Internal helpers** are `private` or placed in a `*_impl.nim` file that isn’t imported elsewhere.

---

## 4️⃣ Interaction Flow (Typical Turn)

### Game Creation

1. **Moderator** runs `./bin/moderator new-game --config game.toml`
2. **Moderator daemon** publishes game metadata as Nostr event (kind 30004)
3. **Players** discover game via relay, register their pubkeys
4. **Game starts** when all players ready

### Order Submission (Player Perspective)

1. **Player** opens desktop client: `./bin/client`
2. **Client** subscribes to relay for their game state events (kind 30002)
3. **Client** receives encrypted game state, decrypts with player private key
4. **Client** displays ANSI/TUI interface with fog-of-war filtered view
5. **Player** studies map, plans strategy, enters orders
6. **Client** encrypts orders to moderator pubkey (NIP-44)
7. **Client** publishes order packet as Nostr event (kind 30001) to relay(s)
8. **Relay** stores event, delivers to daemon's subscription

### Turn Resolution (Daemon Perspective)

1. **Scheduler** triggers at midnight UTC (or manual `/nextturn`)
2. **Daemon** queries relay for all order events (kind 30001) for current game/turn
3. **Daemon** decrypts each player's orders using moderator private key
4. **Daemon** validates orders (schema, legality, resources)
5. **Daemon** calls `engine.resolveTurn(gameState, allOrders)` -> new state
6. **Daemon** archives previous turn state
7. **For each player:**
   - Generate filtered view (fog of war, intel level)
   - Encrypt game state to player's pubkey
   - Publish as Nostr event (kind 30002) tagged for that player
8. **Daemon** publishes public turn summary (kind 30003) - leaderboard, major events
9. **Daemon** optionally publishes spectator feed (kind 30006) - sanitized public view

### Notification (Discord Bot, Optional)

1. **Bot** subscribes to turn complete events (kind 30003)
2. **Bot** receives turn summary from relay
3. **Bot** posts embed to Discord channel: turn #, prestige rankings, battles
4. **Bot** reminds players to check their clients for new turn

### Next Turn

Players repeat order submission flow. The game continues until victory condition or max turns reached.

### BBS Door Game Analogy

Like classic BBS door games:
- Players "dial in" (connect via Nostr client)
- Submit their moves (encrypted orders)
- Log out (client disconnects)
- Game processes all moves overnight (turn resolution)
- Players "dial in" next day to see results

But modernized with:
- Cryptographic identity (Nostr keypairs)
- Decentralized infrastructure (multiple relays)
- Provable game history (signed events on relay)

---

## 5️⃣ Extending the System

| What you want to add                                      | Where it belongs                                                                                                                                         | Minimal changes required                                                                                      |
| --------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| **Web UI**                                                | New `ui/web.nim` (or browser-based client in JS/WASM) that uses Nostr protocol.                                                                          | Implement Nostr client in browser (nostr-tools), subscribe to game state events, publish order events. No engine changes. |
| **Additional relays**                                     | Configure daemon and clients with additional relay URLs in config.                                                                                        | Add relay URLs to config files. System automatically uses all configured relays for redundancy. |
| **Additional game mechanics** (new ship class, tech tree) | `common/types.nim` (data structs) + `engine/core.nim` (rules).                                                                                           | Extend the structs, add the rule logic, update `serde` if needed.                                             |
| **Graphical UI (Nuklear/ImGui)**                          | `ui/nuklear.nim` (or `ui/imgui.nim`).                                                                                                                    | Implement the same `render` / `collectOrders` signatures; the daemon and engine stay untouched.               |
| **Multiple Discord servers**                              | `bot/commands.nim` (store guild‑ID → game‑folder mapping).                                                                                               | Adjust the bot to prefix game IDs with the guild, but the daemon still sees plain folder names.               |
| **Automated testing of whole pipeline**                   | `tests/` – write integration tests that spin up a temporary game folder, run the daemon in a thread, simulate a client packet, and assert the new state. | Use Nim's `asyncdispatch` or external test harness; no production code changes.                               |

---

## 5️⃣.1 Fleet Order System

The fleet order system is a core gameplay mechanic that allows players to command their fleets each turn. The game specification defines 16 order types (see `docs/ec4x_specs.md` Section 6.2).

### Order Types Overview

| Order # | Name | Purpose | Implementation Priority |
|---------|------|---------|------------------------|
| 01 | Move Fleet | Navigate to target system | High (core mechanic) |
| 02 | Seek Home | Find closest friendly system | Medium |
| 03 | Patrol System | Defend and intercept | Medium |
| 04 | Guard Starbase | Protect orbital installation | Medium |
| 05 | Guard/Blockade Planet | Planetary defense/siege | Medium |
| 06 | Bombard Planet | Orbital bombardment | High (combat) |
| 07 | Invade Planet | Ground assault | High (combat) |
| 08 | Blitz Planet | Combined strike | High (combat) |
| 09 | Spy on Planet | Intelligence gathering | Medium |
| 10 | Hack Starbase | Electronic warfare | Low |
| 11 | Spy on System | Reconnaissance | Medium |
| 12 | Colonize Planet | Establish colony | High (expansion) |
| 13 | Join Fleet | Merge squadrons | Medium |
| 14 | Rendezvous | Coordinate movements | Medium |
| 15 | Salvage | Recover wreckage | Low |

### Implementation Approach

Fleet orders will be implemented in `src/engine/` as pure functions:

```nim
# src/engine/orders.nim
type
  FleetOrderType* = enum
    HoldPosition, MoveFleet, SeekHome, PatrolSystem,
    GuardStarbase, GuardPlanet, BombardPlanet, InvadePlanet,
    BlitzPlanet, SpyPlanet, HackStarbase, SpySystem,
    ColonizePlanet, JoinFleet, RendezvousSystem, Salvage

  FleetOrder* = object
    orderType*: FleetOrderType
    targetSystem*: Option[SystemId]
    targetFleet*: Option[FleetId]
    parameters*: Table[string, JsonNode]

# Validation
proc validateOrder*(order: FleetOrder, gameState: GameState): ValidationResult

# Execution (called by engine.resolveTurn)
proc executeOrders*(orders: seq[FleetOrder], gameState: GameState): GameState
```

### Turn-Based Movement Rules

Movement follows specific rules from the game specification:
- **2 major lanes per turn** if you own all systems along path
- **1 lane per turn** otherwise
- **1 lane maximum** when entering enemy/unexplored systems
- **Fleet encounters** trigger when fleets meet

Multi-turn routes are calculated by the engine and displayed to players in their filtered view.

### Player Intel and Fog of War

Players only see what they've discovered:
- **Own fleets**: Full details (location, composition, orders)
- **Friendly fleets**: Last known location and estimated strength
- **Enemy fleets**: Sighting reports with confidence levels
- **Unexplored systems**: Basic star class, no planet details

The daemon generates filtered views (`players/<house>_view.json`) after each turn that respect fog of war.

---

## 5️⃣.2 Map Generation for Hybrid Tabletop Play

One of EC4X's unique features is support for hybrid tabletop/computer gameplay. Players study physical hex maps and enter orders via the client.

### Map Export Formats

The system will generate printable maps in two formats:

**PDF Generation** (`src/ui/map_export.nim`):
- Full-page hex maps with coordinate labels
- System details (planet class, resources, ownership)
- Lane connections (major/minor/restricted with visual distinction)
- Fleet positions (player's own fleets and known enemy fleets)
- Print-optimized: high-DPI vector graphics, B&W friendly

**SVG Generation**:
- Web-viewable format for digital reference
- Interactive elements (hover for system details)
- Layer support (toggle fleets, fog of war, etc.)
- Exportable to other vector editors for customization

### Map Types

Different map views for different purposes:

1. **Master Map** (moderator only)
   - Shows all systems, fleets, and fog of war boundaries
   - Used for debugging and game management
   - Never shared with players

2. **Player View Map**
   - Filtered to player's intel level
   - Shows explored systems and last known fleet positions
   - Generated from `players/<house>_view.json`
   - Updated after each turn resolution

3. **Strategic Planning Map**
   - Simplified view with just systems and lanes
   - No fleet positions (for offline planning)
   - Exported once at game start

### Implementation

```nim
# src/ui/map_export.nim
proc exportMapToPDF*(gameState: GameState, playerIntel: PlayerIntel,
                     outputPath: string): bool

proc exportMapToSVG*(gameState: GameState, playerIntel: PlayerIntel,
                     outputPath: string): bool

# Generate maps for all players after turn resolution
proc generatePlayerMaps*(gameId: GameId, turn: int) =
  for house in gameState.houses:
    let intel = loadPlayerIntel(gameId, house)
    let pdfPath = fmt"games/{gameId}/maps/turn_{turn}_{house}.pdf"
    exportMapToPDF(gameState, intel, pdfPath)
```

### Workflow

1. **Game Start**: Moderator generates initial strategic maps for all players
2. **Each Turn**: Daemon auto-generates updated player maps after resolution
3. **Players**: Print latest map, study offline, open client to submit orders
4. **Repeat**: New maps generated with updated positions and intel

This hybrid approach captures the "print and mark up with pencil" aesthetic of classic play-by-mail games while leveraging modern automation.

---

## 6️⃣ Deployment Sketch


1. **VPS Setup (Ubuntu/Debian)**
   - Create system user `ec4x` (no login shell)
   - Install Nim and build EC4X: `nimble build -d:release`
   - Place binaries in `/opt/ec4x/bin/`

2. **Nostr Relay Deployment**
   - Install nostr-rs-relay (Rust): `cargo build --release`
   - Configure relay in `/opt/nostr-relay/config.toml`:
     - Set permanent retention for EC4X events (kinds 30001-30006)
     - Bind to localhost:8080 (Caddy will proxy)
     - Enable event archival (never prune game data)
   - Create systemd service: `nostr-relay.service`
   - Enable: `systemctl enable --now nostr-relay`

3. **Reverse Proxy (Caddy)**
   - Install Caddy for automatic HTTPS
   - Configure `/etc/caddy/Caddyfile`:
     ```
     relay.ec4x.game {
         reverse_proxy localhost:8080
     }
     ```
   - Caddy auto-obtains Let's Encrypt certificates
   - Point DNS A record to your VPS IP

4. **EC4X Daemon Configuration**
   - Generate moderator Nostr keypair: `./bin/moderator keygen`
   - Configure `/opt/ec4x/daemon_config.toml`:
     - Relay URLs (local + public fallbacks)
     - Moderator private key path
     - Turn schedule (midnight UTC)
     - Game data directories
   - Create systemd service: `ec4x-daemon.service`
   - Enable: `systemctl enable --now ec4x-daemon`

5. **Discord Bot (Optional)**
   - Store bot token in `/opt/ec4x/bot/.env`
   - Configure bot to monitor Nostr relay for game events
   - Bot subscribes to turn complete events (kind 30003)
   - Posts summaries to Discord channels
   - Create systemd service: `ec4x-bot.service`

6. **Player Clients**
   - Players download client binary or build from source
   - Generate Nostr keypair: `./bin/client keygen`
   - Configure client with relay URLs
   - Connect and register for games

See **[docs/EC4X-VPS-Deployment.md](EC4X-VPS-Deployment.md)** for detailed step-by-step deployment guide.
---

## 7️⃣ Quick Reference Glossary

| Term                                                  | Meaning                                                                                                                                              |
| ----------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| **GameState**                                         | Full master representation of a single EC4X game (all houses, colonies, ships, tech, etc.).                                                          |
| **PlayerPacket**                                      | JSON object containing one house’s orders for the current turn (tax, build, move, espionage, etc.).                                                  |
| **Filtered View** | Subset of `GameState` that a house is allowed to see (fog of war, known intel). Sent as encrypted Nostr events. |
| **Nostr Event** | Signed JSON message transmitted via relays. EC4X uses custom event kinds (30001-30006) for game operations. |
| **Transport** | Nostr protocol: WebSocket connections to relays, encrypted event publishing/subscribing. |
| **Daemon** | Systemd-managed process that subscribes to order events, decrypts them, runs turn resolution, publishes game states. |
| **Nostr Relay** | Message broker that stores and delivers EC4X events. Archives complete game history. |
| **Moderator** | Game operator with private key to decrypt orders and sign official game states. |
| **Discord Bot** | Optional bridge that monitors Nostr events and posts turn summaries to Discord channels. |
| **UI Layer** | Desktop client (TUI/GUI) that displays game state and publishes encrypted orders as Nostr events. |

---

## 8️⃣ Checklist for a New Contributor

- **Read `common/types.nim`** to understand the data model.

- **Explore `engine/resolve.nim`** – the single entry point for a turn.

- **Run the daemon locally:** `./scripts/run_daemon.sh` (starts the daemon without systemd).

- **Start a client:** `./src/main/client.nim --mode=client game_demo`.

- **Look at `tests/`** for examples of how to unit‑test engine functions.

- **If you want to add a UI:** implement the two procedures in `ui/ui.nim` (`render`, `collectOrders`) and register the new module in `src/main/client.nim`.

- **For Nostr implementation details:** see `EC4X-Nostr-Implementation.md` for module structure, `EC4X-Nostr-Events.md` for event schema, and `EC4X-VPS-Deployment.md` for deployment guide.

---

## 9️⃣ Additional Documentation

- **[EC4X-Nostr-Implementation.md](EC4X-Nostr-Implementation.md)** - Nostr protocol module structure and implementation guide
- **[EC4X-Nostr-Events.md](EC4X-Nostr-Events.md)** - Complete event schema and data flow examples
- **[EC4X-VPS-Deployment.md](EC4X-VPS-Deployment.md)** - Production VPS deployment with Nostr relay
- **[Game Specification](specs/)** - Complete game rules and mechanics
- **[EC4X-Deployment.md](EC4X-Deployment.md)** - General deployment guide

---
