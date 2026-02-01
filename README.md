# EC4X - Asynchronous Turn-Based 4X Wargame

EC4X is an asynchronous turn-based wargame of the classic eXplore, eXpand, eXploit, and eXterminate (4X) variety for multiple players.

Inspired by Esterian Conquest and other classic BBS door games, EC4X combines the async rhythm of turn-based strategy with modern cryptographic identity and decentralized infrastructure.

**📖 [Read the Complete Game Specification](docs/specs/index.md)** - Full rules, gameplay mechanics, and strategic systems

## Game Overview

The twelve *dynatoi* (δυνατοί - "the powerful") - ancient Great Houses rising from the ashes - battle over a small region of space to dominate rivals and claim supremacy. The game features abstract strategic cycles that scale with map size - from decades in small skirmishes to centuries in epic campaigns.

**Game Details:**
- **Players:** 2-12
- **Turn Duration:** ~24 hours (real-time)
- **Victory Condition:** Turn limit reached (highest prestige wins) or last House standing
- **Starting Prestige:** 100 points

Turns cycle every 24 hours IRL, intentionally designed for async gameplay where players check in once per day.

## Architecture

EC4X supports **two transport modes** with the same game engine:

- **Localhost Mode** - File-based transport for offline/hotseat multiplayer and testing
- **Nostr Mode** - Decentralized relay-based transport with end-to-end encryption

**Components:**
- **Client** - Player interface (supports both modes, auto-detects transport)
- **Daemon** - Autonomous turn processing service (manages multiple games)
- **SQLite** - Single source of truth for game state (both modes)

**Key Features:**
- Server-authoritative game state
- Fog of war via intel system
- Bandwidth-efficient state deltas (Nostr)
- Transport-agnostic game engine

See **[Architecture Documentation](docs/architecture/overview.md)** for complete system design and implementation details.

## Development Status

**Engine Stable - Building Player Client**

✅ **Engine Status:**
- Core game engine stable and tested (343+ tests passing)
- All 13 game systems operational
- KDL-based configuration (14 config files)
- Full turn cycle tested (Conflict → Income → Command → Production)

🔄 **Current Work:**
- Building localhost game server for testing
- Building player client for human playtesting
- Preparing for initial playtesting sessions

📋 **Test Coverage:**
- Unit Tests: 9 suites passing
- Integration Tests: 310 tests passing
- Stress Tests: 24 tests passing

**Game Systems (Operational):**
- Combat system (space battles, ground combat, starbases)
- Economy system (production, construction, maintenance)
- Research system (tech trees, science levels)
- Prestige system (dynamic scaling, morale)
- Espionage system (covert operations, counter-intelligence)
- Diplomacy system (three-state relations)
- Colonization system (PTU, Space Guild)
- Victory conditions (turn limit, elimination)
- Fleet management (movement, orders, status)
- Star map generation (procedural hex grid)
- Fog-of-war intelligence system
- Configuration system (KDL format)
- Turn resolution (order processing)

## Documentation

### Game Rules
- **[Complete Game Specification](docs/specs/index.md)** - Full rules, gameplay, and strategic systems
- **[Documentation Overview](docs/README.md)** - Navigation guide for all documentation

### Architecture
- **[System Architecture](docs/architecture/overview.md)** - Core system design and components
- **[Combat Engine](docs/architecture/combat-engine.md)** - Combat system architecture
- **[Fleet System](docs/architecture/fleet_system.md)** - Fleet management architecture
- **[Intelligence System](docs/architecture/intel.md)** - Fog-of-war and intelligence mechanics

### Development
- **[TODO](docs/TODO.md)** - Current work tracking and roadmap
- **[Playtesting Plans](docs/play_testing/README.md)** - Human playtesting and training data collection

## Development Setup

### Prerequisites

- **Nim** 2.0+ and **Nimble**
- **OpenGL** development libraries (for client)
- **zstd** compression library

**macOS (Homebrew):**
```bash
brew install nim zstd
```

**Arch/CachyOS:**
```bash
sudo pacman -S nim nimble zstd libgl libx11 libxcursor libxi libxrandr
```

**Ubuntu/Debian:**
```bash
sudo apt install nim libgl-dev libx11-dev libxcursor-dev libxi-dev libxrandr-dev libzstd-dev
```

### Quick Start (Developers)

**Run tests:**
```bash
nimble testUnit           # Unit tests (9 suites)
nimble testIntegration    # Integration tests (310 tests)
nimble testStress         # Stress tests (24 tests)
```

**Build engine:**
```bash
nimble buildAll           # All binaries
nimble checkAll           # Verify compilation
```

**Note:** Player client not yet implemented. See [docs/TODO.md](docs/TODO.md) for roadmap.
