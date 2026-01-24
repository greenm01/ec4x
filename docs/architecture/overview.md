# EC4X Architecture Overview

## System Design Philosophy

EC4X is an **asynchronous turn-based 4X strategy game** built with these core principles:

1. **Server-Authoritative**: Single source of truth prevents cheating
2. **Transport-Agnostic**: Game logic independent of networking layer
3. **Offline-First**: Full gameplay available without network connectivity
4. **Bandwidth-Efficient**: Delta-based state sync for networked play
5. **Fog of War**: Intel system provides player-specific views

## High-Level Architecture

```
┌─────────────────────────────────────┐
│     Game Engine (src/engine/)       │
│  • PURE game logic (no I/O)         │
│  • Turn-based resolution            │
│  • Command validation               │
│  • Combat & economy systems         │
│  • Telemetry metrics collection     │
└─────────────────────────────────────┘
              ↑ imports
┌─────────────────────────────────────┐
│       Daemon (src/daemon/)          │
│  • SAM event loop                   │
│  • Persistence (SQLite per game)    │
│  • Nostr transport                  │
│  • Turn resolution orchestration    │
└─────────────────────────────────────┘
                    ↑
          ┌─────────────────┐
          │     Nostr       │
          │   Transport     │
          │                 │
          │ • WebSocket     │
          │ • NIP-44        │
          │ • Relays        │
          └─────────────────┘
                    ↑
┌───────────────────────────────────────────────────┐
│              Client (src/client/)                 │
│  • GUI player interface (bin/ec4x-client)         │
│  • SAM architecture with Sokol+Nuklear            │
│  • Starmap rendering, command submission          │
│  • Turn report viewing                            │
└───────────────────────────────────────────────────┘

┌─────────────────────────────────────┐
│     Moderator (src/moderator/)      │
│  • Admin CLI (bin/ec4x)             │
│  • Game creation from scenarios     │
│  • Game management (pause/resume)   │
└─────────────────────────────────────┘

┌─────────────────────────────────────┐
│     Dev Player (src/player/)        │
│  • TUI/CLI tool (bin/ec4x-play)     │
│  • Menu-driven command entry        │
│  • Command validation for LLMs      │
└─────────────────────────────────────┘
```

**Import Rules:**
- `engine/` → imports NOTHING from other modules (pure library)
- `daemon/` → imports from `engine/` (types, resolveTurn)
- `moderator/` → imports from `engine/` and `daemon/persistence/`
- `client/` → imports from `engine/types/` (player_state for data structures)
- `player/` → imports from `engine/` (validation) and `daemon/persistence/` (SQLite)

## Components

### Client (Player Interface)
**Binary**: `bin/ec4x-client`
**Source**: `src/client/`
**Role**: Player's game interface (GUI)
**Capabilities**:
- Join games via Nostr relay
- View game state (filtered by intel)
- Submit commands via KDL format
- View turn history and reports
- Starmap visualization with hex grid

**Architecture**: SAM pattern with Sokol (graphics) + Nuklear (UI)

**Report Generation**: Client-side formatting of TurnResult data
- Engine sends structured TurnResult (events, combatReports)
- Client generates formatted reports with hex coordinates
- Future clients (web, mobile) can format differently
- Minimizes network traffic (no formatted text sent over wire)

### Daemon (Turn Processor)
**Binary**: `bin/ec4x-daemon`
**Role**: Autonomous turn processing service
**Capabilities**:
- Monitors multiple games simultaneously
- Collects commands from both transports
- Resolves turns on deadline or completion
- Publishes results via appropriate transport

**Architecture**:
- SAM (The Elm Architecture) pattern
- Single-threaded async event loop
- Non-blocking concurrent operations
- Manages all active games in one process

### Moderator (Admin Tool)
**Binary**: `bin/ec4x`
**Source**: `src/moderator/`
**Role**: Game administration and management
**Capabilities**:
- Create new games with Nostr transport
- Start/pause/stop games
- Force turn resolution (`ec4x resolve <game-id>`)
- View game statistics
- Manage player roster

### Dev Player (Playtesting Tool)
**Binary**: `bin/ec4x-play`
**Source**: `src/player/`
**Role**: Lightweight dev tool for playtesting without GUI
**Documentation**: `docs/tools/ec4x-play.md`

**Two Modes**:
- **TUI Mode**: Menu-driven terminal interface for human playtesting
- **CLI Mode**: Command validation for Claude/LLM workflows

**Capabilities**:
- View fog-of-war filtered game state
- Enter commands via menu navigation
- Generate KDL command files
- Validate commands before submission
- Submit commands to daemon

**Claude/LLM Integration**:
- LLMs read game state directly from SQLite
- Generate KDL commands per `docs/engine/kdl-commands.md`
- Validate with `ec4x-play validate <game-id> commands.kdl --house=N`
- Drop validated commands to `data/games/{id}/commands/`

## Validation System

**Purpose**: Comprehensive parameter and configuration validation
**File**: `src/engine/setup.nim` (single source of truth)
**Documentation**: `docs/architecture/validation-system.md`

**Architecture**:
- **Layer 3 (Entry Points)**: Parse with error handling, call validation
- **Layer 2 (Orchestrator)**: `validateGameSetup()` coordinates all validation
- **Layer 1 (Domain)**: Each module validates its own invariants

**Validates**:
- Game setup parameters (players, turns, map rings)
- KDL config files (ranges, sums, constraints)
- Cross-parameter rules (e.g., no zero rings)

**Key Features**:
- Single source of truth - all entry points use same validation
- Clear error messages with actual vs expected values
- Collects all errors (not fail-on-first)
- 36 unit tests covering edge cases
- Blocks invalid configs before game creation

## Game Mode

### Nostr Mode
**Use Cases**:
- Online multiplayer
- Distributed async play
- Play-by-relay gaming
- Privacy-focused multiplayer
- Development and testing

**Transport**:
- Commands: Encrypted Nostr events to daemon
- State: Encrypted per-player deltas from relay
- Results: Public turn summaries + private deltas

**Benefits**:
- No central server required
- Censorship-resistant
- Use existing Nostr identity
- End-to-end encrypted fog of war

## Data Flow

### Turn Cycle

```
1. Command Submission Phase
   Players → [Transport] → Daemon → SQLite

2. Turn Deadline
   Daemon checks: all commands received OR deadline passed

3. Turn Resolution
   Daemon → Load State → Game Engine → Resolve Turn

4. State Update
   New State → SQLite (transaction)

5. Intel Update
   Daemon → Update intel tables for each player

6. Result Distribution
   Daemon → Generate per-player deltas → [Transport] → Players
```

### Command Collection

```
Player edits commands.kdl
  ↓
Client serializes to msgpack, encrypts to daemon pubkey
  ↓
Client publishes EventKindTurnCommands (30402)
  ↓
Daemon receives via relay subscription
  ↓
Daemon decrypts and saves to SQLite
```

## Key Technical Decisions

### Single SQLite Database
- **Why**: One storage layer for both modes
- **Benefit**: Single code path, easier maintenance
- **Structure**: All tables use `game_id` foreign key
- **Multi-tenancy**: One database supports many games

### Server-Authoritative Model
- **Why**: Prevent cheating, enforce rules consistently
- **Benefit**: Players receive filtered views only
- **Trade-off**: Server must be trusted (mitigated by open source)

### Transport Abstraction
- **Why**: Game logic shouldn't know about networking
- **Benefit**: Easy to add new transport modes
- **Implementation**: Nostr transport with WebSocket relay connections

### State Deltas (Nostr Only)
- **Why**: Bandwidth efficiency (20-40x reduction)
- **Benefit**: Relay-friendly message sizes
- **Implementation**: Track changes per turn, send diffs

### Intel System
- **Why**: Implement fog of war correctly
- **Benefit**: Each player sees only their known intel
- **Implementation**: Dedicated tables with timestamps

### Single Daemon
- **Why**: Operational simplicity
- **Benefit**: One service manages all games
- **Implementation**: Database-driven game discovery

## Storage Architecture

See [storage.md](./storage.md) for complete schema.

**Core Principles**:
- **One `ec4x.db` per game** (separate database files)
- Each game directory contains its own database
- Full authoritative game state per database
- Intel tracking for fog of war
- Optional Nostr event cache
- Isolation: corruption in one game doesn't affect others

## Transport Architecture

See [transport.md](./transport.md) for implementation details.

**Abstraction Layer**:
```
Transport Interface:
  - submitCommands(commands)
  - collectCommands() → OrderPacket[]
  - publishResults(deltas)
  - getGameState() → GameState
```

**Implementation**:
- NostrTransport: WebSocket relay + NIP-44 encryption

## Intel System

See [intel.md](./intel.md) for fog of war design.

**Visibility Tracking**:
- Systems: owned, occupied, scouted, adjacent
- Fleets: visual, scan, spy intel with timestamps
- Colonies: population, industry, defenses, staleness

**Player View Generation**:
- Query intel tables per player
- Filter full game state by visibility rules
- Include only known information in deltas

## Daemon Design

See [daemon.md](./daemon.md) for operational details.

**Single Process Architecture**:
- Auto-discovers games from SQLite
- Monitors Nostr relay for commands
- Processes turns atomically
- Hot-reload for new games

## Development Workflow

### Local Development
1. Create game: `moderator new test_game --relay=ws://localhost:8080`
2. Start daemon: `daemon start`
3. Start local relay: `docker run -p 8080:8080 nostr-relay`
4. Join as player: `client join test_game --relay=ws://localhost:8080`
5. Test gameplay with local relay

### Production Deployment
1. Configure production relay: `moderator new prod_game --relay=wss://relay.example.com`
2. Players join via Nostr: `client join <game-id> --relay=wss://relay.example.com`
3. Daemon manages games across all configured relays

## Scalability

**Per-Game Resources**:
- SQLite database: ~1-10 MB per game
- Memory: ~10-50 MB per active game
- CPU: Minimal (turn resolution on-demand)

**Daemon Capacity**:
- One daemon can manage 100+ games
- Nostr: One WebSocket per relay (shared across games)

**Bottlenecks**:
- SQLite write throughput (mitigated by transactions)
- Nostr relay limits (mitigated by deltas + chunking)
- Turn resolution CPU (parallelizable across games)

## Security Model

### Nostr Mode
- **Trust**: Players trust daemon operator
- **Encryption**: NIP-44 encryption for all private data
- **Visibility**: Fog of war enforced by server
- **Cheating**: Players cannot see hidden information
- **Mitigation**: Open source daemon allows verification

## Future Extensions

### Additional Transports
- WebSocket (direct client-server)
- Discord bot (commands via DM)
- Email (ultra-slow async)
- Matrix protocol

### Distributed Authority
- Multi-signature turn resolution
- Blockchain-based game state
- Zero-knowledge proofs for fog of war

### Performance Optimizations
- Read replicas for game state
- Caching layer for frequent queries
- Parallel turn resolution
- Event sourcing architecture

## Related Documentation

- [Storage Architecture](./storage.md) - SQLite schema and queries
- [Transport Layer](./transport.md) - Nostr transport implementation
- [Nostr Protocol](./nostr-protocol.md) - Event kinds and protocol details
- [Intel System](./intel.md) - Fog of war and visibility tracking
- [Daemon Design](./daemon.md) - Turn processing and monitoring
- [Data Flow](./dataflow.md) - Complete turn resolution cycle
