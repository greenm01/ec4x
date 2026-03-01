# EC4X Documentation

**Project:** EC4X - Turn-based 4X Space Strategy Game
**Language:** Nim
**Status:** Engine Refactoring
**Branch:** refactor-engine

---

## 📚 Documentation Structure

### Game Specifications

Located in `specs/`:
- **[index.md](specs/index.md)** - Specification index
- **[01-gameplay.md](specs/01-gameplay.md)** - How you play, prestige system, setup, and turn structure
- **[02-assets.md](specs/02-assets.md)** - Ships, fleets, squadrons, and special units
- **[03-economy.md](specs/03-economy.md)** - Economics system
- **[04-research_development.md](specs/04-research_development.md)** - R&D systems
- **[05-construction.md](specs/05-construction.md)** - Construction systems
- **[06-operations.md](specs/06-operations.md)** - Movement mechanics
- **[07-combat.md](specs/07-combat.md)** - Combat mechanics
- **[08-diplomacy.md](specs/08-diplomacy.md)** - Diplomatic states and espionage
- **[09-intelligence.md](specs/09-intelligence.md)** - Intelligence gathering, reports, and fog of war
- **[10-reference.md](specs/10-reference.md)** - Ship stats, tech trees, and data tables
- **[11-glossary.md](specs/11-glossary.md)** - Comprehensive definitions of game terms and abbreviations

### Engine Architecture

Located in `architecture/`:
- **[overview.md](architecture/overview.md)** - System architecture overview
- **[combat-engine.md](architecture/combat-engine.md)** - Combat system design
- **[dataflow.md](architecture/dataflow.md)** - Data flow and turn resolution
- **[fleet_system.md](architecture/fleet_system.md)** - Fleet management architecture
- **[storage.md](architecture/storage.md)** - Data persistence
- **[validation-system.md](architecture/validation-system.md)** - Parameter validation system
- **[intel.md](architecture/intel.md)** - Intelligence and fog-of-war system
- **[tea-implementation.md](architecture/tea-implementation.md)** - TEA pattern implementation
- **[transport.md](architecture/transport.md)** - Nostr network protocol
- **[daemon.md](architecture/daemon.md)** - Game server architecture
- **[player-tui-command-audit.md](architecture/player-tui-command-audit.md)** - TUI command surface audit and gameplay-readiness backlog

### Engine Implementation Details

Located in `engine/`:
- **architecture/** - Core engine architecture
  - `turn-cycle.md` - Canonical turn execution
  - `construction-systems.md` - Build queue and construction
  - `orders.md` - Order system design
  - `events.md` - Fleet orders and intelligence events
- **mechanics/** - Game mechanics implementation
  - `combat-original.md` - Original combat design
  - `diplomatic-combat.md` - Diplomatic resolution in combat
  - `fleet-order-execution.md` - Fleet order processing
  - `scout-espionage-system.md` - Scout and espionage mechanics
- **telemetry/** - Diagnostic and metrics system
  - `README.md` - Telemetry system overview
  - `collectors.md` - Data collection
  - `iterators.md` - State iteration patterns
  - `index-maintenance.md` - Index management
- **refactor/** - Current refactoring work
  - `2025-12-19-refactor-notes.md` - Latest refactor notes

### Dev Tools

Located in `tools/`:
- **[ec4x-play.md](tools/ec4x-play.md)** - Dev player CLI/TUI for playtesting and Claude/LLM integration

### Playtesting Guides

Located in `guides/`:
- **[player-tui-playtest-checklist.md](guides/player-tui-playtest-checklist.md)** - Structured session checklist for TUI playtests
- **[player-tui-issue-template.md](guides/player-tui-issue-template.md)** - Issue capture template for playtest findings
- **[turn-resolution-operations.md](guides/turn-resolution-operations.md)** - Runbook for manual, scheduled, and hybrid turn advancement

### Bot & AI

Located in `bot/` and `ai/`:
- **[bot/README.md](bot/README.md)** - LLM Bot Playtesting Architecture
- **[ai/neural_network_training.md](ai/neural_network_training.md)** - Train neural networks from game data (AlphaGo-style)

### Features & Development

- **dev/** - Implementation notes
  - `zero_sum_prestige_implementation.md` - Prestige system implementation
- **features/** - Feature documentation
  - `SQUADRON_AUTO_BALANCE.md` - Squadron auto-balancing

### Player Documentation

- **player-manual/** - Player-facing documentation (if applicable)

### API Reference

- **api/** - Auto-generated API documentation

### Historical Documents

- **archive/** - Archived documentation from previous phases

---

## 🎯 Current Focus

**Branch:** refactor-engine

### Primary Goals

1. **Engine Refactoring** - Clean architecture following DoD principles
2. **Config System** - Migration from TOML to KDL (complete)
3. **Network Protocol** - Nostr-based multiplayer architecture
4. **Game Server** - Daemon design and implementation
5. **Player Client** - Terminal or web-based interface

### Development Philosophy

EC4X is fundamentally a **social game** designed for human players interacting over asynchronous turns. The game specification explicitly states:

> Diplomacy is between humans. The server doesn't care how you scheme; it only processes the orders you submit.

**Development Priority:**
1. ✅ Config System (KDL migration complete)
2. 🔄 Engine Refactoring (in progress)
3. 📋 Network Protocol (Nostr implementation)
4. 📋 Game Server (daemon + turn processing)
5. 📋 Player Client (human interface)
6. 📋 Play-Testing (Claude-based validation)
7. 📋 AI Opponents (optional, future)

---

## 🚀 Quick Start

**At the start of sessions working on the engine:**

```
@docs/README.md       # This file
@docs/TODO.md         # Current roadmap
@src/engine/architecture.md  # Engine structure
```

---

## 📋 Key Project Rules

1. **All enums MUST be `{.pure.}`** (NEP-1 requirement)
2. **No hardcoded game values** - use KDL configs
3. **Follow NEP-1 Nim conventions** - 2-space indent, camelCase, 80-char lines
4. **Data-Oriented Design** - Tables for entities, pure functions for logic
5. **Fog-of-war enforcement** - AI/clients only see what they should see
6. **Use nph** - Nim code formatter

---

## 🔧 Configuration System

**Location:** `config/` (KDL format)

All game balance values are externalized to KDL configuration files:
- `economy.kdl` - Economic parameters
- `tech.kdl` - Technology trees and costs
- `ships.kdl` - Ship statistics
- `ground_units.kdl` - Ground unit stats
- `facilities.kdl` - Facility costs and effects
- `combat.kdl` - Combat mechanics
- `diplomacy.kdl` - Diplomatic rules
- `espionage.kdl` - Espionage costs and effects
- `prestige.kdl` - Prestige rewards
- ... and more

**Pattern:**
```nim
let config = globalEconomyConfig  # Auto-loads from KDL
result.growth = config.population.naturalGrowthRate  # NOT hardcoded
```

---

## 🧪 Testing

**Test Structure:**
```
tests/
├── unit/            # Unit tests for individual modules
├── integration/     # Integration tests for system interactions
└── scenarios/       # Complex gameplay scenarios
```

**Run Tests:**
```bash
# Specific test
nim c -r tests/integration/test_kdl_tech.nim
nim c -r tests/integration/test_kdl_economy.nim

# All tests
nimble test
```

---

## 📊 Engine Architecture

**Data-Oriented Design Principles:**

```
src/engine/
├── types/          # Pure data structures (Fleet, Ship, GameState)
├── state/          # State management (entity tables, iterators)
├── entities/       # Entity mutators (createFleet, destroyColony)
├── systems/        # Game logic (combat, economy, research)
├── config/         # KDL configuration loaders
├── persistence/    # SQLite save/load
└── turn_cycle/     # Turn orchestration
```

**Key Pattern:** Read via `state/iterators`, write via `entities/*_ops`, implement logic in `systems/*`.

See [src/engine/architecture.md](../src/engine/architecture.md) for complete details.

---

## 🌐 Network Architecture

**Nostr Protocol:**
- Asynchronous turn-based gameplay
- Cryptographic verification of orders
- Decentralized relay network
- No trusted central server required

**Components:**
- **Game Server (Daemon)** - Processes turns, maintains game state
- **Player Client** - Submit orders, view game state
- **Nostr Relays** - Message transport layer

See [architecture/transport.md](architecture/transport.md) and [architecture/daemon.md](architecture/daemon.md).

---

## 📖 Additional Resources

- [Nim Language](https://nim-lang.org/)
- [NEP-1 Style Guide](https://nim-lang.org/docs/nep1.html)
- [Nim Manual](https://nim-lang.org/docs/manual.html)
- [KDL Spec](https://kdl.dev/spec/)
- [Nostr Protocol](https://github.com/nostr-protocol/nostr)

---

**Last Updated:** 2025-12-25
**Branch:** refactor-engine
**Status:** Engine refactoring in progress
