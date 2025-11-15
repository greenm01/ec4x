# EC4X - Asynchronous Turn-Based 4X Wargame

EC4X is an asynchronous turn-based wargame of the classic eXplore, eXpand, eXploit, and eXterminate (4X) variety for multiple players.

Inspired by Esterian Conquest and other classic BBS door games, EC4X combines the async rhythm of turn-based strategy with modern cryptographic identity and decentralized infrastructure.

**📖 [Read the Complete Game Specification](docs/specs/index.md)** - Full rules, gameplay mechanics, and strategic systems

## Game Overview

Upstart Houses battle over a small region of space to dominate rivals and seize the imperial throne. The game starts at the dawn of the third imperium in year 2001. Each turn comprises one month of a thirteen month Terran Computational Calendar.

**Game Details:**
- **Players:** 2-12
- **Turn Duration:** ~24 hours (real-time)
- **Victory Condition:** Highest prestige or last House standing
- **Starting Prestige:** 50 points

Turns cycle every 24 hours IRL, intentionally designed for async gameplay where players check in once per day.

## Architecture

EC4X runs on the **Nostr protocol**, like a modern BBS door game with cryptographic identity:

- **Desktop Client** - Terminal UI for order entry, publishes encrypted orders to Nostr relays
- **Daemon** - Subscribes to order events, resolves turns on schedule (midnight default)
- **Nostr Relay** - Stores game history permanently, delivers events between players and daemon
- **Hybrid Tabletop** - Supports printed hex maps + digital order submission

See **[Architecture Documentation](docs/EC4X-Architecture.md)** for complete system design and implementation details.

## Development Approach

**Offline First:** Game engine is being developed for local/hotseat multiplayer before adding Nostr integration. This ensures solid gameplay mechanics before network complexity.

**Current Status:**

✅ **Working (Offline Playable Foundation):**
- Robust starmap generation (2-12 players)
- Hexagonal coordinate system with procedural lane generation
- A* pathfinding with fleet traversal rules
- Game state types and turn resolution framework
- Order system (16 types defined, validation framework)
- Comprehensive test suite (58 tests, 100% passing)
- Build system and development environment

🚧 **Next Phase (Complete Offline Game):**
- Combat resolution (ship damage, battles, casualties)
- Economy system (production, construction, research)
- Movement integration (pathfinding + turn rules)
- Basic TUI for order entry
- Hotseat multiplayer support

🔮 **Future (Network Integration):**
- Nostr protocol implementation (crypto, events, WebSocket client)
- Daemon (subscriber/processor/publisher for Nostr events)
- Desktop client network integration
- PDF/SVG map generation for hybrid tabletop play
- Production VPS deployment

## Documentation

### Game Rules
- **[Complete Game Specification](docs/specs/index.md)** - Full rules, gameplay, and strategic systems

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
