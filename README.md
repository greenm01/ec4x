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

**v0.2 - Engine Refactoring in Progress**

🔄 **Current Work:**
- Refactoring core game engine
- Rebuilding test coverage
- Config/spec system cleanup and alignment
- KDL-based configuration (14 config files)

📋 **Next Steps:**
1. Complete engine refactor and establish test coverage
2. Build player client for human playtesting
3. Playtest and iterate on game balance
4. Collect training data from human games
5. Train ML-based AI (AlphaGo-style approach)

**Game Systems (In Refactor):**
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
