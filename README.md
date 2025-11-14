# EC4X - Asynchronous Turn-Based 4X Wargame

EC4X is an asynchronous turn-based wargame of the classic eXplore, eXpand, eXploit, and eXterminate (4X) variety for multiple players.

Inspired by Esterian Conquest and other classic BBS door games, EC4X combines the async rhythm of turn-based strategy with modern cryptographic identity and decentralized infrastructure.

## Game Overview

Upstart Houses battle over a small region of space to dominate rivals and seize the imperial throne. The game starts at the dawn of the third imperium in year 2001. Each turn comprises one month of a thirteen month Terran Computational Calendar.

Turns cycle every 24 hours in real life (IRL) time, intentionally designed for async gameplay where players check in once per day.

Victory is won by crushing your rivals and earning the most **Prestige** by end of game.

## Architecture

EC4X runs on the **Nostr protocol**, like a modern BBS door game with cryptographic identity:

- **Nostr Protocol**: Players submit encrypted orders as Nostr events to relays
- **Daemon**: Subscribes to order events, resolves turns on schedule (midnight by default)
- **Desktop Client**: Terminal UI (TUI) for order entry, publishes to Nostr relays
- **Nostr Relay**: Stores game history permanently, delivers events between players and daemon
- **Hybrid Tabletop**: Supports printed hex maps + digital order submission
- **Discord Bot** (optional): Monitors Nostr events, posts turn summaries to Discord

See **[Architecture Documentation](docs/EC4X-Architecture.md)** for complete system design.

## Current Status

✅ **Working:**
- Robust starmap generation (2-12 players)
- Hexagonal coordinate system with procedural lane generation
- A* pathfinding with fleet traversal rules
- Game rule compliance (hub connectivity, player placement)
- Comprehensive test suite (58 tests, 100% passing)
- Build system and development environment

🚧 **In Development:**
- Nostr protocol implementation (crypto, events, WebSocket client)
- Turn resolution engine (income, command, conflict, maintenance phases)
- Fleet order system (16 order types)
- Daemon (subscriber/processor/publisher for Nostr events)
- Desktop client with TUI for order entry
- PDF/SVG map generation for hybrid tabletop play
- Nostr relay deployment (nostr-rs-relay)

## Documentation

- **[Game Specification](docs/specs/)** - Complete game rules and mechanics
  - [Gameplay](docs/specs/gameplay.md) - How to play, prestige, turns
  - [Military Assets](docs/specs/military.md) - Ships, fleets, special units
  - [Economy](docs/specs/economy.md) - Economics, R&D, construction
  - [Operations](docs/specs/operations.md) - Movement and combat
  - [Diplomacy](docs/specs/diplomacy.md) - Diplomacy and espionage
  - [Reference Tables](docs/specs/reference.md) - Ship stats and data tables
- **[Architecture Guide](docs/EC4X-Architecture.md)** - System design and structure
- **[Nostr Implementation](docs/EC4X-Nostr-Implementation.md)** - Protocol modules and code structure
- **[Nostr Events Schema](docs/EC4X-Nostr-Events.md)** - Event kinds, tags, and data flow
- **[VPS Deployment](docs/EC4X-VPS-Deployment.md)** - Production deployment with Nostr relay
- **[Deployment Guide](docs/EC4X-Deployment.md)** - General deployment instructions

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
