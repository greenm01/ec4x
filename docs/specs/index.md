# EC4X Specification v0.1

Written by Mason A. Green

In memory of Jonathan F. Pratt.

---

## Introduction

EC4X is an asynchronous turn-based wargame of the classic eXplore, eXpand, eXploit, and eXterminate (4X) variety.

Upstart Houses battle over a small region of space to dominate usurpers and seize the imperial throne. Your role is to serve as House Duke and lead your people to greatness.

The game begins at the dawn of the third imperium in the year 2001. Each turn comprises one month of a thirteen month [Terran Computational Calendar](https://www.terrancalendar.com/ "Terran Computational Calendar").

Turns cycle as soon as all players have completed their turns, or generally a maximum of one day In Real Life (IRL) time. EC4X is intentionally slow burn.

EC4X is intended to facilitate remote play between friends over email or local tabletop play. The SSH-based architecture supports asynchronous turn submission with automated processing. EC4X is a flexible framework; adapt it to your own requirements.

## Influences

EC4X pays homage and is influenced by the following great titles:

- Esterian Conquest (EC)
- Victory by Any Means (VBAM)
- Empire of The Sun (EOS)
- Space Empires 4X
- Solar Starfire
- Stellar Conquest

Although not required, it is highly recommended to purchase physical copies of these classics to fully appreciate the art. Dive deep.

### The Esterian Conquest Legacy

Esterian Conquest was an obscure bulletin board system (BBS) door game from the early 1990's that inspired this project. EC is a gem, and great times were had battling friends, family, and anonymous players over the phone lines on slow noisy modems. Graphics were crude but the ANSI art was fantastic. The early 1990's was a simple time, just before the internet blew up and super computers landed in all of our pockets. EC turns progressed once a day and most of the strategic planning occurred in one's imagination offline. Players eagerly awaited each new day's battle reports, and games would last several weeks to several months. Maps and reports were printed on dot matrix printers and marked up with pencil to no end. The times were good. That era is long gone but tabletop wargaming is still alive and well in 2024. EC4X is an attempt to recapture some of that magic.

While not intended to be an accounting exercise, there is enough complexity in EC4X to allow for dynamic strategic decision making and surprising outcomes.

The background narrative of EC4X is wide open and only limited by the scope of your imagination.

---

## Game Specification

The complete EC4X game specification is organized into the following documents:

### Core Rules
- **[Gameplay](gameplay.md)** - How to play, prestige, setup, and turn structure

### Game Systems
- **[Military Assets](assets.md)** - Ships, fleets, squadrons, and special units
- **[Economy](economy.md)** - Economics, R&D, and construction systems

### Operations
- **[Operations](operations.md)** - Movement and combat mechanics
- **[Diplomacy](diplomacy.md)** - Diplomacy and espionage

### Reference
- **[Game Data Tables](reference.md)** - Ship stats, tech trees, and data tables

---

## Quick Reference

- **Version**: 0.1
- **Players**: 2-12
- **Turn Duration**: ~24 hours (real-time)
- **Victory Condition**: Highest prestige or last House standing
- **Starting Prestige**: 50 points
- **Elimination**: Below 0 prestige for 3 consecutive turns

---

## Implementation & Architecture

The EC4X technical implementation is documented in the following guides:

### Architecture Documentation
- **[Architecture Overview](../architecture/overview.md)** - System design, components, and philosophy
- **[Storage Layer](../architecture/storage.md)** - SQLite schema and database design (per-game)
- **[Transport Layer](../architecture/transport.md)** - Localhost and Nostr transport modes
- **[Intel System](../architecture/intel.md)** - Fog of war and visibility mechanics
- **[Daemon Design](../architecture/daemon.md)** - TEA pattern and async event loop
- **[Data Flow](../architecture/dataflow.md)** - Complete turn cycle and data flow
- **[TEA Implementation](../architecture/tea-implementation.md)** - The Elm Architecture guide

### Nostr Protocol
- **[Nostr Events](../EC4X-Nostr-Events.md)** - Event kind specifications
- **[Nostr Implementation](../EC4X-Nostr-Implementation.md)** - Protocol implementation guide

### Deployment
- **[Deployment Guide](../EC4X-Deployment.md)** - Server setup and configuration
- **[VPS Deployment](../EC4X-VPS-Deployment.md)** - Production deployment guide

---