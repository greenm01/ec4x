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

**Phase 2.5 Complete - Ready for Neural Network Training**

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
- Configuration system (14 TOML files, 2000+ parameters)

**Test Coverage:** 101+ integration tests passing, all systems verified

✅ **Production Rule-Based AI (Complete):**
- **8 specialized modules:** intelligence, diplomacy, tactical, strategic, budget, orders, admiral, config
- **12 personality archetypes:** Aggressive, Economic, Espionage, Diplomatic, Balanced, Turtle, Expansionist, Tech Rush, Raider, Military Industrial, Opportunistic, Isolationist
- **Fog-of-war compliant:** Type-level enforcement via FilteredGameState
- **TOML-configurable:** All parameters tunable without recompilation (config/rba.toml)
- **Diagnostic framework:** 130 metrics tracked for balance analysis
- **Genetic algorithms:** Personality evolution and competitive co-evolution
- **4-act awareness:** Adaptive strategy across game phases

✅ **Neural Network Training Infrastructure (Phase 2.5 - Complete 2025-11-29):**
- **Training export module:** 600-dimensional state encoding (src/ai/training/export.nim)
- **Multi-head action encoding:** Diplomatic, fleet, build, and research decisions
- **JSON export pipeline:** PyTorch-compatible training data format
- **Clean architecture:** Zero duplication between test and production code
- **Production logging:** All AI code uses structured logging (no echo statements)

📊 **Progress: 31.3% Complete (2.5 of 8 phases)**

**Completed Phases:**
- ✅ Phase 1: Environment Setup (PyTorch + ROCm, ONNX Runtime)
- ✅ Phase 2: Rule-Based AI Enhancements (8 modules, 12 personalities, FoW integration)
- ✅ Phase 2.5: RBA Migration (production training export, clean architecture)

**Next Phase (Phase 3):**
- ⏳ Bootstrap data generation (10,000 games → 1.6M training examples)
- ⏳ State-action-outcome recording
- ⏳ Train/validation split (80/20)

**Future Phases:**
- Phase 4: Supervised learning (policy + value networks, ONNX export)
- Phase 5: Nim integration (ONNX Runtime, playable neural AI)
- Phase 6: Self-play reinforcement learning (AlphaZero-style)
- Phase 7: Production deployment (difficulty levels, model packaging)

**Repository Health:**
- Clean git history (binaries purged with git-filter-repo)
- Repository size: 26MB
- Comprehensive .gitignore (no binary tracking issues)

See **[AI Development Status](docs/ai/STATUS.md)** for detailed phase breakdown and metrics.

## Documentation

### Game Rules
- **[Complete Game Specification](docs/specs/index.md)** - Full rules, gameplay, and strategic systems

### AI System
- **[AI Documentation](docs/ai/README.md)** - AI system overview and navigation
- **[AI Development Status](docs/ai/STATUS.md)** - Phase progress (31.3% complete)
- **[AI Architecture](docs/ai/ARCHITECTURE.md)** - Modular RBA system design (8 subsystems + training export)
- **[AI Personalities](docs/ai/PERSONALITIES.md)** - 12 strategy archetypes explained
- **[Decision Framework](docs/ai/DECISION_FRAMEWORK.md)** - How AI makes decisions

### Milestones
- **[RBA Migration Complete](docs/milestones/RBA_MIGRATION_COMPLETE.md)** - Phase 2.5 completion (2025-11-29)

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

### Recommended: Automatic Environment with direnv

Install direnv and nix-direnv:
```bash
nix profile install nixpkgs#direnv nixpkgs#nix-direnv
```

Add to your shell config (`~/.bashrc` or `~/.config/fish/config.fish`):
```bash
# Bash
eval "$(direnv hook bash)"

# Fish
direnv hook fish | source
```

Allow direnv in the project directory:
```bash
cd /path/to/ec4x
direnv allow
```

Now the development environment loads automatically when you `cd` into the project directory.

### Alternative: Manual Environment

Enter the development shell manually:
```bash
nix develop
```

This provides nim, nimble, and git in an isolated environment.

### Quick Start
```bash
nimble build
./bin/moderator new my_game
./bin/client offline --players=4
```
