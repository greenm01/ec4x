# EC4X - Asynchronous Turn-Based 4X Wargame

EC4X is an asynchronous turn-based wargame of the classic eXplore, eXpand, eXploit, and eXterminate (4X) variety for multiple players.

Inspired by Esterian Conquest and other classic BBS games, EC4X combines the "slow burn" rhythm of play-by-mail gaming with modern automation.

## Game Overview

Upstart Houses battle over a small region of space to dominate rivals and seize the imperial throne. The game starts at the dawn of the third imperium in year 2001. Each turn comprises one month of a thirteen month Terran Computational Calendar.

Turns cycle every 24 hours in real life (IRL) time, intentionally designed for async gameplay where players check in once per day.

Victory is won by crushing your rivals and earning the most **Prestige** by end of game.

## Architecture

EC4X uses a unique **SSH file-drop architecture** optimized for asynchronous gameplay:

- **SSH Transport**: Players submit orders via SSH (no persistent connections needed)
- **Daemon**: Systemd service processes turns on schedule (midnight by default)
- **ANSI Client**: Lightweight terminal interface for order entry
- **Hybrid Tabletop**: Supports printed hex maps + digital order submission
- **Discord Bot** (optional): Social layer for game coordination and turn notifications

See **[Architecture Documentation](docs/EC4X-Architecture.md)** for complete details.

## Current Status

✅ **Working:**
- Robust starmap generation (2-12 players)
- Hexagonal coordinate system with procedural lane generation
- A* pathfinding with fleet traversal rules
- Game rule compliance (hub connectivity, player placement)
- Comprehensive test suite (58 tests, 100% passing)
- Build system and development environment

🚧 **In Development:**
- Turn resolution engine (income, command, conflict, maintenance phases)
- SSH transport layer and file-drop packet system
- Fleet order system (16 order types)
- Daemon with turn scheduler
- ANSI UI for order entry
- PDF/SVG map generation for hybrid tabletop play

## Documentation

- **[Game Specification](docs/ec4x_specs.md)** - Complete game rules and mechanics
- **[Architecture Guide](docs/EC4X-Architecture.md)** - System design and structure
- **[Deployment Guide](docs/EC4X-Deployment.md)** - Production setup instructions
- **[Implementation Summary](docs/IMPLEMENTATION_SUMMARY.md)** - Technical achievements

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

This provides nim, nimble, git, and nushell in an isolated environment.

### Quick Start
```bash
nimble build
./bin/moderator new my_game
./bin/client offline --players=4
```
