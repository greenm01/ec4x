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
│  • Pure game logic                  │
│  • Turn-based resolution            │
│  • Order validation                 │
│  • Combat & economy systems         │
└─────────────────────────────────────┘
              ↓
┌─────────────────────────────────────┐
│ Storage Layer (src/persistence/)    │
│  • SQLite (one db per game)         │
│  • Event sourcing (~5-10MB/100 turns)│
│  • Intel/fog of war tracking        │
│  • Diagnostic telemetry (200+ metrics)│
└─────────────────────────────────────┘
         ↙                    ↘
┌─────────────┐          ┌─────────────┐
│ Localhost   │          │   Nostr     │
│ Transport   │          │  Transport  │
│             │          │             │
│ • File I/O  │          │ • Encrypted │
│ • Direct DB │          │ • Relays    │
│ • Testing   │          │ • P2P       │
└─────────────┘          └─────────────┘
```

## Components

### Client (Player Interface)
**Binary**: `bin/client`
**Role**: Player's game interface
**Capabilities**:
- Join games (localhost or Nostr)
- View game state (filtered by intel)
- Submit orders
- View turn history
- Generate human-readable turn reports from structured data

**Transport Support**: Auto-detects from game config

**Report Generation**: Client-side formatting of TurnResult data
- Engine sends structured TurnResult (events, combatReports)
- Client generates formatted reports with hex coordinates
- Different clients can format differently (CLI, web, mobile)
- Minimizes network traffic (no formatted text sent over wire)

### Daemon (Turn Processor)
**Binary**: `bin/daemon`
**Role**: Autonomous turn processing service
**Capabilities**:
- Monitors multiple games simultaneously
- Collects orders from both transports
- Resolves turns on deadline or completion
- Publishes results via appropriate transport

**Architecture**:
- TEA (The Elm Architecture) pattern
- Single-threaded async event loop
- Non-blocking concurrent operations
- Manages all active games in one process

### Moderator (Admin Tool)
**Binary**: `bin/moderator`
**Role**: Game administration and management
**Capabilities**:
- Create new games (localhost or Nostr mode)
- Start/pause/stop games
- View game statistics
- Manage player roster
- Convert between transport modes

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
- RBA AI configuration (budgets, ratios, thresholds)
- TOML config files (ranges, sums, constraints)
- Cross-parameter rules (e.g., no zero rings)

**Key Features**:
- Single source of truth - all entry points use same validation
- Clear error messages with actual vs expected values
- Collects all errors (not fail-on-first)
- 36 unit tests covering edge cases
- Blocks invalid configs before game creation

## Game Modes

### Localhost Mode
**Use Cases**:
- Single-player testing
- Hotseat multiplayer
- Development and debugging
- Offline play

**Transport**:
- Orders: JSON files in game directory
- State: Direct SQLite access
- Results: JSON exports per player

**Benefits**:
- No network required
- Instant feedback
- Easy inspection with sqlite3 CLI
- Simple file-based order submission

### Nostr Mode
**Use Cases**:
- Online multiplayer
- Distributed async play
- Play-by-relay gaming
- Privacy-focused multiplayer

**Transport**:
- Orders: Encrypted Nostr events to moderator
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
1. Order Submission Phase
   Players → [Transport] → Daemon → SQLite

2. Turn Deadline
   Daemon checks: all orders received OR deadline passed

3. Turn Resolution
   Daemon → Load State → Game Engine → Resolve Turn

4. State Update
   New State → SQLite (transaction)

5. Intel Update
   Daemon → Update intel tables for each player

6. Result Distribution
   Daemon → Generate per-player deltas → [Transport] → Players
```

### Order Collection (Both Modes)

**Localhost:**
```
Player edits orders.toml
  ↓
Client writes orders_pending.json
  ↓
Daemon polls game directory
  ↓
Orders saved to SQLite
```

**Nostr:**
```
Player edits orders.toml
  ↓
Client encrypts to moderator pubkey
  ↓
Client publishes EventKindOrderPacket
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
- **Implementation**: Interface with LocalTransport and NostrTransport

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
  - submitOrders(orders)
  - collectOrders() → OrderPacket[]
  - publishResults(deltas)
  - getGameState() → GameState
```

**Implementations**:
- LocalTransport: filesystem + direct SQLite
- NostrTransport: WebSocket relay + encryption

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
- Monitors both transports simultaneously
- Processes turns atomically
- Hot-reload for new games

## Development Workflow

### Local Development
1. Create localhost game: `moderator new test_game --mode=localhost`
2. Start daemon: `daemon start`
3. Join as player: `client join test_game --house=Alpha`
4. Test gameplay offline

### Production Deployment
1. Convert to Nostr: `moderator convert test_game --mode=nostr --relay=wss://...`
2. Players join via Nostr: `client join <game-id> --relay=wss://...`
3. Same daemon manages both types

## Scalability

**Per-Game Resources**:
- SQLite database: ~1-10 MB per game
- Memory: ~10-50 MB per active game
- CPU: Minimal (turn resolution on-demand)

**Daemon Capacity**:
- One daemon can manage 100+ games
- Nostr: One WebSocket per relay (shared across games)
- Localhost: Filesystem polling (configurable interval)

**Bottlenecks**:
- SQLite write throughput (mitigated by transactions)
- Nostr relay limits (mitigated by deltas + chunking)
- Turn resolution CPU (parallelizable across games)

## Security Model

### Localhost Mode
- **Trust**: Players trust game moderator
- **Access**: Direct filesystem and database access
- **Cheating**: Possible if players access SQLite directly
- **Mitigation**: Use for testing or trusted groups only

### Nostr Mode
- **Trust**: Players trust moderator's daemon
- **Encryption**: NIP-44 encryption for all private data
- **Visibility**: Fog of war enforced by server
- **Cheating**: Players cannot see hidden information
- **Mitigation**: Open source daemon allows verification

## Future Extensions

### Additional Transports
- WebSocket (direct client-server)
- Discord bot (orders via DM)
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

## AI & QoL Systems (2025-11-26)

**Status:** Phase 1 Complete - Core QoL integrated with RBA

### Rule-Based AI (RBA)

**Location:** `src/ai/rba/`
**Architecture:** Multi-module personality-driven decision system

**Modules:**
- **Budget** - Multi-objective budget allocation with running tracking
- **Standing Orders** - Intelligent fleet automation based on role + personality
- **Tactical** - Phase-aware 4-act priority system for fleet operations
- **Strategic** - Invasion planning and coordinated operations
- **Logistics** - Asset lifecycle management (cargo, PTU, reserves)
- **Economic** - Terraforming and colony development
- **Espionage** - Mission generation (BROKEN - under investigation)
- **Intelligence** - Intel gathering and analysis
- **Diplomacy** - Placeholder (not yet integrated)

**Decision Flow:**
```
generateAIOrders()
   ├─> Logistics (cargo, PTU, squadrons)
   ├─> Build Orders (via budget module)
   ├─> Strategic Planning (invasions)
   ├─> Tactical Orders (fleet movements)
   ├─> Standing Orders (routine automation)
   ├─> Espionage (spy/hack missions)
   └─> Economic Orders (terraform)
```

### Quality-of-Life (QoL) Features

**Status:** Integrated with RBA for intelligent automation

**Core Features:**
1. **Budget Tracking** ✅ OPERATIONAL
   - Engine-level validation (`OrderValidationContext`)
   - AI-level tracking (`BudgetTracker`)
   - Prevents overspending (0% violations achieved)

2. **Standing Orders** ✅ OPERATIONAL
   - 8 order types (Patrol, Defend, Colonize, Repair, Reinforce, Evade, Guard, Blockade)
   - Role-based assignment (Colonizer, Scout, Defender, Raider, etc.)
   - Personality-driven parameters (ROE, thresholds, ranges)
   - 67% fleet assignment rate

3. **Fleet Validation** ✅ OPERATIONAL
   - Ownership security checks (100% compliance)
   - Target validation (system existence, reachability)
   - Capability validation (required ship types)

4. **Planned Features** ⏳
   - Movement range calculator
   - Construction queue preview
   - Batch order system

**Integration Benefits:**
- AI uses QoL features for consistent behavior
- Reduced tactical micromanagement burden
- Security enforcement at engine level
- Full visibility via comprehensive logging

### Known Issues

**Critical (Discovered 2025-11-26):**
- Espionage system not executing (0% usage)
- Scout production not triggering (0 scouts built)
- Mothballing logic not activating (0% usage)
- Resource hoarding (55% games affected)

**See:**
- [QoL Integration Status](../ai/QOL_INTEGRATION_STATUS.md)
- [Balance Testing Report](../testing/BALANCE_TESTING_2025-11-26.md)
- [Known Issues](../KNOWN_ISSUES.md) - Issue #0

## Related Documentation

- [Storage Architecture](./storage.md) - SQLite schema and queries
- [Transport Layer](./transport.md) - Localhost and Nostr implementation
- [Intel System](./intel.md) - Fog of war and visibility tracking
- [Daemon Design](./daemon.md) - Turn processing and monitoring
- [Data Flow](./dataflow.md) - Complete turn resolution cycle
- [Nostr Events](../EC4X-Nostr-Events.md) - Event kind specifications
- [Nostr Implementation](../EC4X-Nostr-Implementation.md) - Protocol details
