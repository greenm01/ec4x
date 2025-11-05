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

```
ec4x/
├─ src/
│   ├─ ec4x.nim                     # top‑level package (re‑exports)
│   │
│   ├─ common/                      # shared types & helpers
│   │   ├─ types.nim                # GameState, House, Ship, etc.
│   │   ├─ serde.nim                # JSON/MsgPack (de)serialisation
│   │   └─ utils.nim                # logging, RNG, math helpers
│   │
│   ├─ engine/                      # pure game logic
│   │   ├─ core.nim                 # phase functions (income, combat,…)
│   │   ├─ resolve.nim              # resolveTurn(state, packets) → new state
│   │   └─ validation.nim           # packet sanity checks
│   │
│   ├─ transport/                   # I/O abstractions
│   │   ├─ transport.nim            # generic interface (loadState, savePacket)
│   │   ├─ ssh_file.nim             # file‑drop over SSH (inotify watcher)
│   │   ├─ tcp_socket.nim           # optional TCP/WS transport (future)
│   │   └─ http_api.nim             # local HTTP server used by daemon & bot
│   │
│   ├─ ui/                          # rendering & input
│   │   ├─ ui.nim                   # tiny UI trait (render, collectOrders)
│   │   ├─ ansi.nim                 # current ANSI/curses implementation
│   │   └─ nuklear.nim              # stub for a future immediate‑mode GUI
│   │
│   ├─ daemon/                      # systemd service
│   │   ├─ daemon.nim               # entry point (systemd ExecStart)
│   │   ├─ scheduler.nim            # turn‑timer (midnight or manual)
│   │   ├─ game_manager.nim         # iterate over games, call engine
│   │   └─ webhook.nim              # receive turn‑complete POST from engine
│   │
│   ├─ bot/                         # Discord integration
│   │   ├─ bot.nim                  # main bot process
│   │   ├─ commands.nim             # slash‑command handlers (/newgame, /join,…)
│   │   ├─ discord_api.nim           # thin wrapper around discord.nim / harmony
│   │   └─ bot_http.nim             # local HTTP endpoint for turn‑done webhook
│   │
│   └─ main/                        # user‑facing binaries
│       ├─ client.nim               # `ec4x --mode=client <game-id>` (ANSI UI)
│       └─ server.nim               # forced‑command entry point for SSH
│
├─ tests/                           # unit tests per layer
│   ├─ test_engine.nim
│   ├─ test_transport.nim
│   └─ test_ui.nim
│
├─ scripts/                         # dev helpers
│   ├─ create_game.sh               # quick local game creation
│   └─ run_daemon.sh                # run daemon without systemd (dev)
│
├─ data/
│   ├─ templates/
│   │   └─ initial_state.json       # starter state copied for new games
│   └─ snapshots/                   # optional global archive (git‑ignore)
│
├─ .gitignore
├─ ec4x.nimble                     # Nimble package definition
└─ README.md
```

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
| **Automated testing of whole pipeline**                   | `tests/` – write integration tests that spin up a temporary game folder, run the daemon in a thread, simulate a client packet, and assert the new state. | Use Nim’s `asyncdispatch` or external test harness; no production code changes.                               |

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
