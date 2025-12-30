# EC4X Specification v0.1

Written by Mason A. Green

In memory of Jonathan F. Pratt.

---

## Introduction

Welcome to EC4X—an asynchronous turn-based wargame of galactic conquest.

You are the Duke of an upstart House battling for dominance in a contested region of space. Your rivals seek the same prize: the imperial throne. Command your forces, expand your territory, crush your enemies, and seize the crown.

**The year is 3000.** The second Esterian Empire has collapsed. Reckless monetary policy, corrupt bureaucracies, and socialist excess bankrupted the old order. Revolution swept through the core worlds. The Emperor is dead. His heirs squabble over the ruins.

You lead one of the Great Houses rising from the ashes. Your mandate is absolute: conquer the region, subjugate your rivals, and establish the third imperium under your banner.

**Strategic cycles operate on the Cipher Ledger**—a quantum-entangled network embedded in jump lane stabilizers enabling instantaneous cryptographic settlement across interstellar space. Each cycle represents the time required to gather intelligence, coordinate operations, and consolidate control across your territory. In tight regional conflicts, cycles pass quickly (1-2 years). Sprawling multi-sector campaigns unfold over decades (10-15 years per cycle).

Turns cycle as soon as all players complete their commands, generally within 24 hours of real time. EC4X is intentionally slow burn—strategic empire building, not tactical skirmishing.

**The game automates tedious micromanagement.** Squadrons form automatically. Fleets organize themselves. Construction queues process without constant attention. You command at the strategic level—issuing fleet commands, setting research priorities, allocating resources. The game handles tactical execution.

EC4X runs on your machine or across the Nostr network. For tabletop sessions, run the game server on localhost—players connect from their laptops around the table. For remote play between friends, the server operates over Nostr protocol, enabling asynchronous turn submission with cryptographic verification. The game server acts as moderator, processing turns automatically and maintaining fog of war. No human moderator required—the software handles everything.

---

## Influences

EC4X pays homage to these classics:

- Esterian Conquest (EC)
- Victory by Any Means (VBAM)
- Empire of The Sun (EOS)
- Space Empires 4X
- Solar Starfire
- Stellar Conquest

Purchase physical copies of these titles to fully appreciate the art form. Dive deep.

### The Esterian Conquest Legacy

Esterian Conquest was an obscure bulletin board system (BBS) door game from the early 1990s that inspired this project. EC is a gem. Great times were had battling friends, family, and anonymous players over phone lines on slow noisy modems. Graphics were crude but the ANSI art was fantastic.

The early 1990s was a simpler time—just before the internet exploded and supercomputers landed in our pockets. EC turns progressed once daily. Strategic planning occurred in your imagination offline. You eagerly awaited each day's battle reports. Games lasted weeks to months. You printed maps and reports on dot matrix printers and marked them up with pencil endlessly. The times were good.

That era is gone but tabletop wargaming thrives. EC4X recaptures some of that magic.

The game provides complexity sufficient for dynamic strategic decision making and surprising outcomes without degenerating into accounting exercises. The background narrative is wide open—limited only by your imagination.

---

## Game Specification

The complete EC4X game specification is organized into the following documents:

### Core Rules

- **[Gameplay](01-gameplay.md)** - How you play, prestige system, setup, and turn structure

### Game Systems

- **[Military Assets](02-assets.md)** - Ships, squadrons, fleets, C2 Pool, and special units
- **[Economy](03-economy.md)** - Economics system
- **[Research & Development](04-research_development.md)** - R&D systems
- **[Construction](05-construction.md)** - Construction systems

### Operations

- **[Operations](06-operations.md)** - Movement mechanics
- **[Combat](07-combat.md)** - Combat mechanics
- **[Diplomacy](08-diplomacy.md)** - Diplomatic states and espionage
- **[Intelligence](09-intelligence.md)** - Intelligence gathering, reports, and fog of war

### Reference

- **[Game Data Tables](10-reference.md)** - Ship stats, tech trees, and data tables
- **[Glossary](11-glossary.md)** - Comprehensive definitions of game terms and abbreviations

---

## Quick Reference

- **Version**: 0.1
- **Players**: 2-12
- **Turn Duration**: ~24 hours (real-time)
- **Victory Condition**: Reach 2500 prestige or be the last House standing
- **Starting Prestige**: 50 points
- **Elimination**: Below 0 prestige for 3 consecutive turns

---