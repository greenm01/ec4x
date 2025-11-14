# EC4X Architecture

# EC4X – Project Layout & Architecture Overview

---

## 1️⃣ High‑Level Vision

- **Goal:** A turn‑based 4X game written in Nim that can be played over SSH (or any future transport) with a simple ANSI UI now and a modern GUI later.

- **Core Principle:** **Separation of concerns** – the *engine* knows nothing about networking or rendering; the *transport* only moves JSON blobs; the *UI* only displays data and collects orders.

- **Optional Discord front‑end:** A lightweight bot that creates games, registers users, and posts the SSH command / turn‑summary notifications. The bot talks to the daemon via a local HTTP/UNIX‑socket API; it never runs game logic.

---

## 2️⃣ Layered Architecture

```
+-------------------+      +-------------------+     +-------------------+
|   UI Layer        | <──► |   Engine Core     | ◄── |   Transport Layer |
| (ANSI now, later  |      | (pure Nim, no I/O)|     | (SSH, files, TCP, |
|  Nuklear/ImGui…)  |      +-------------------+     |  Discord‑bot)     |
+-------------------+                                +-------------------+
```

| Layer                      | Responsibility                                                                                                                                               | Typical implementation                                      |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------- |
| **Engine Core**            | All game rules, data structures, turn resolution. Pure functions, deterministic, unit‑testable.                                                              | Nim modules under `src/engine/`.                            |
| **Transport Layer**        | Authentication, session handling, file‑watching or socket I/O. Converts player actions ↔ JSON packets.                                                       | `src/transport/` (SSH‑file drop now, TCP/WS later).         |
| **UI Layer**               | Renders a player’s filtered view, collects orders, builds a `PlayerPacket`.                                                                                  | `src/ui/ansi.nim` (current), `src/ui/nuklear.nim` (future). |
| **Discord Bot** (optional) | Game creation, user registration, posting SSH commands, announcing turn results. Communicates with the daemon via a tiny local HTTP API.                     | `src/bot/` (separate process).                              |
| **Daemon**                 | Systemd‑managed long‑running service. Watches all game folders, validates packets, schedules nightly turn resolution, serves the local HTTP API for the bot. | `src/daemon/`.                                              |

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
│   │   ├─ ssh_file.nim             # 🚧 file‑drop over SSH (inotify watcher)
│   │   ├─ http_api.nim             # 🚧 local HTTP server for daemon & bot
│   │   └─ packets.nim              # 🚧 packet serialization/validation
│   │
│   ├─ ui/                          # 🚧 rendering & input (future)
│   │   ├─ ui.nim                   # 🚧 UI interface trait
│   │   ├─ ansi.nim                 # 🚧 ANSI terminal implementation
│   │   └─ map_export.nim           # 🚧 PDF/SVG generation for tabletop
│   │
│   ├─ daemon/                      # 🚧 systemd service (future)
│   │   ├─ daemon.nim               # 🚧 entry point (systemd ExecStart)
│   │   ├─ scheduler.nim            # 🚧 turn‑timer (midnight or manual)
│   │   ├─ game_manager.nim         # 🚧 iterate over games, call engine
│   │   └─ webhook.nim              # 🚧 receive turn‑complete POST from bot
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

- 🚧 **Turn resolution engine** - Income, command, conflict, maintenance phases
- 🚧 **SSH transport layer** - File-drop packet system
- 🚧 **Daemon** - Turn scheduler and game manager
- 🚧 **Fleet orders** - 16 order types from specification
- 🚧 **ANSI UI** - Simple terminal interface for order entry
- 🚧 **Map export** - PDF/SVG generation for hybrid tabletop play
- 🚧 **Discord bot** - Optional social layer (lowest priority)

### Naming Conventions

- **Modules** are singular (`engine/core.nim`, `transport/ssh_file.nim`).

- **Public symbols** that other layers import are prefixed with the module name (e.g., `engine.resolveTurn`).

- **Internal helpers** are `private` or placed in a `*_impl.nim` file that isn’t imported elsewhere.

---

## 4️⃣ Interaction Flow (Typical Turn)

1. **Discord bot** → `/newgame` → creates `games/&lt;game-id&gt;/`, copies `initial_state.json`, stores creator in `users.db`, posts SSH command.

2. **Player** runs the SSH command → forced‑command starts `ec4x --mode=client &lt;game-id&gt;`.

3. **Client (UI layer)** loads the player’s filtered view (`players/&lt;house&gt;_view.json`), shows the ANSI menu, collects orders, writes `games/&lt;game-id&gt;/packets/&lt;house&gt;.json`.

4. **Transport (ssh\_file)** detects the new packet via inotify and notifies the **daemon**.

5. **Daemon** (at scheduled midnight or on manual `/nextturn`) loads all pending packets, calls `engine.resolveTurn`, writes a fresh `state.json`, archives the previous turn, regenerates each `players/&lt;house&gt;_view.json`.

6. **Daemon** POSTs a tiny JSON payload to the **Discord bot** (`/turn_done`).

7. **Bot** posts an embed in the game channel: turn number, prestige table, who submitted, link to the snapshot.

The next day players repeat from step 2.

---

## 5️⃣ Extending the System

| What you want to add                                      | Where it belongs                                                                                                                                         | Minimal changes required                                                                                      |
| --------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| **Web UI**                                                | New `ui/web.nim` (or a separate JS front‑end) that talks to the same transport (HTTP API).                                                               | Implement the UI to consume `players/&lt;house&gt;_view.json` and POST a `PlayerPacket`. No engine changes.   |
| **Persistent TCP server**                                 | `transport/tcp_socket.nim` \+ a small listener in `daemon/daemon.nim`.                                                                                   | Add the listener, register it in the daemon’s HTTP API, and expose the same `loadState/savePacket` interface. |
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
3. **Players**: Print latest map, study offline, SSH in to submit orders
4. **Repeat**: New maps generated with updated positions and intel

This hybrid approach captures the "print and mark up with pencil" aesthetic of classic play-by-mail games while leveraging modern automation.

---

## 6️⃣ Deployment Sketch

1. **VPS (Ubuntu/Debian)**
   
   - Create a system user `ec4x` (no login shell).
   
   - Install Nim, clone the repo, run `nimble build -d:release`.
   
   - Place binaries (`ec4x-daemon`, `ec4x-client`, `ec4x-bot`) in `/opt/ec4x/bin/`.
   
   - Enable the systemd services: `systemctl enable --now ec4x.service ec4x-bot.service`.
   
   - (Optional) Enable `ec4x.timer` for nightly turn execution.

2. **SSH configuration**
   
   - Add a `ForceCommand` line for the `ec4x` user that runs the client binary with the supplied game ID:
     
     ```
     Match User ec4x
         ForceCommand /opt/ec4x/bin/ec4x-client --mode=client %d
         AllowTcpForwarding no
         X11Forwarding no
     ```
   
   - Users add their public keys to `~ec4x/.ssh/authorized_keys` (the bot can insert a line automatically when a user registers).

3. **Discord bot token**
   
   - Store the token in `/opt/ec4x/bot/.env` (or a systemd secret).
   
   - Bot reads the token, connects, registers slash commands, and talks to the daemon via the UNIX socket `/run/ec4x.sock`.

---

## 7️⃣ Quick Reference Glossary

| Term                                                  | Meaning                                                                                                                                              |
| ----------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| **GameState**                                         | Full master representation of a single EC4X game (all houses, colonies, ships, tech, etc.).                                                          |
| **PlayerPacket**                                      | JSON object containing one house’s orders for the current turn (tax, build, move, espionage, etc.).                                                  |
| **Filtered View** (`players/&lt;house&gt;_view.json`) | Subset of `GameState` that a house is allowed to see (fog‑of‑war, known intel).                                                                      |
| **Transport**                                         | The mechanism that moves JSON files between client and daemon (currently SSH‑file‑drop).                                                             |
| **Daemon**                                            | Systemd‑managed process that watches all game folders, validates packets, runs the engine each turn, and serves a tiny HTTP API for the Discord bot. |
| **Discord Bot**                                       | Convenience front‑end for game creation, user registration, and turn announcements; communicates with the daemon via local HTTP.                     |
| **UI Layer**                                          | Code that renders a player’s view and collects orders; currently ANSI, later Nuklear/ImGui.                                                          |

---

## 8️⃣ Checklist for a New Contributor

- **Read `common/types.nim`** to understand the data model.

- **Explore `engine/resolve.nim`** – the single entry point for a turn.

- **Run the daemon locally:** `./scripts/run_daemon.sh` (starts the daemon without systemd).

- **Start a client:** `./src/main/client.nim --mode=client game_demo`.

- **Look at `tests/`** for examples of how to unit‑test engine functions.

- **If you want to add a UI:** implement the two procedures in `ui/ui.nim` (`render`, `collectOrders`) and register the new module in `src/main/client.nim`.

---
