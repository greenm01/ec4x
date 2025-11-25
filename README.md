# EC4X - Asynchronous Turn-Based 4X Wargame

EC4X is an asynchronous turn-based wargame of the classic eXplore, eXpand, eXploit, and eXterminate (4X) variety for multiple players.

Inspired by Esterian Conquest and other classic BBS door games, EC4X combines the async rhythm of turn-based strategy with modern cryptographic identity and decentralized infrastructure.

**📖 [Read the Complete Game Specification](docs/specs/index.md)** - Full rules, gameplay mechanics, and strategic systems

## Game Overview

Upstart Houses battle over a small region of space to dominate rivals and seize the imperial throne. The game features abstract strategic cycles that scale with map size - from decades in small skirmishes to centuries in epic campaigns. Victory is achieved through prestige accumulation across a dramatic 4-act structure.

**Game Details:**
- **Players:** 2-12
- **Turn Duration:** ~24 hours (real-time)
- **Victory Condition:** Highest prestige or last House standing
- **Starting Prestige:** 50 points

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

**Engine Complete - AI Training Phase**

✅ **Complete Game Engine (13 Major Systems):**
- Combat system (space battles, ground combat, starbases)
- Economy system (production, construction, maintenance, salvage)
- Research system (6 tech levels, exponential costs)
- Prestige system (18 sources, morale modifiers)
- Espionage system (7 actions, counter-intelligence)
- Diplomacy system (non-aggression pacts, violations)
- Colonization system (PTU requirements, ownership tracking)
- Victory conditions (3 types: prestige, elimination, turn limit)
- Morale system (7 levels based on prestige)
- Turn resolution (4-phase turn structure)
- Fleet management (movement, merge/split operations)
- Star map generation (procedural, 2-12 players)
- Configuration system (13 TOML files, 2000+ parameters)

**Test Coverage:** 101+ integration tests passing, all systems verified

🤖 **Current Phase - AI Development:**
- ✅ Modular Rule-Based Advisor (RBA) implemented (8 modules, 1,722 lines)
- ✅ 12 distinct AI personalities (Aggressive, Economic, Espionage, Diplomatic, etc.)
- ✅ Fog-of-war aware decision making
- ✅ Genetic algorithm optimization tools (personality evolution)
- ✅ 4-act game structure awareness (Land Grab → Rising Tensions → Total War → Endgame)
- ⏳ Balance testing and tuning (400+ game validation)
- ⏳ Neural network training pipeline (future: AlphaZero-style self-play)

**AI Architecture:** Modular expert system with personality-driven behavior
- 8 specialized subsystems: intelligence, diplomacy, tactical, strategic, budget
- 12 personality archetypes with 6 continuous traits (aggression, risk, economy, expansion, diplomacy, tech)
- Genetic algorithms for personality optimization and exploit discovery
- Competitive co-evolution for balance testing
- See [AI System Documentation](docs/ai/README.md) for details

🔮 **Future Phases:**
- Neural network training (PyTorch + ROCm GPU acceleration)
- ONNX inference integration (Nim + ONNX Runtime)
- UI development (TUI for order entry, game visualization)
- Network integration (Nostr protocol, decentralized multiplayer)

## Documentation

### Game Rules
- **[Complete Game Specification](docs/specs/index.md)** - Full rules, gameplay, and strategic systems

### AI System
- **[AI Documentation](docs/ai/README.md)** - AI system overview and navigation
- **[AI Architecture](docs/ai/ARCHITECTURE.md)** - Modular RBA system design (8 subsystems)
- **[AI Personalities](docs/ai/PERSONALITIES.md)** - 12 strategy archetypes explained
- **[Decision Framework](docs/ai/DECISION_FRAMEWORK.md)** - How AI makes decisions

### Testing & Balance
- **[Testing Overview](docs/testing/README.md)** - Testing levels and methodology
- **[Balance Methodology](docs/testing/BALANCE_METHODOLOGY.md)** - Regression testing approach

### Technical Documentation
- **[Architecture Guide](docs/EC4X-Architecture.md)** - System design and implementation structure
- **[Nostr Implementation](docs/EC4X-Nostr-Implementation.md)** - Protocol modules and event handling
- **[Nostr Events Schema](docs/EC4X-Nostr-Events.md)** - Event kinds, tags, and data flow
- **[Deployment Guide](docs/EC4X-VPS-Deployment.md)** - Production deployment with Nostr relay

## Development Setup

### Prerequisites

This project uses Nix flakes. Enable experimental features:
```bash
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
```

### Enter Development Shell
```bash
nix develop
```

This provides nim, nimble, and git in an isolated environment (launches fish shell if available).

### Quick Start
```bash
nimble build
./bin/moderator new my_game
./bin/client offline --players=4
```
