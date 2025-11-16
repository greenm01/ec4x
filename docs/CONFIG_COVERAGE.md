# EC4X Configuration File Coverage

This document maps EC4X specification tables to their corresponding configuration files.

**Philosophy**: Config files contain **tunable numbers** (stats, costs, values). Core game mechanics (tech tree, espionage actions, diplomatic rules, fleet orders, ROE) are **hardcoded** in the engine.

## Complete Coverage Map

### Reference Tables (reference.md)

| Spec Section | Table Name | Config File | Status |
|--------------|------------|-------------|--------|
| 9.1 | Space Force (WEP1) | `ships_default.toml` | ✅ Complete |
| 9.2 | Ground Units (WEP1) | `ground_units_default.toml` | ✅ Complete |
| 9.3 | Spacelift Command (WEP1) | `facilities_default.toml` | ✅ Complete |
| 9.4 | Prestige | `prestige_default.toml` | ✅ Complete |

### Combat Mechanics (operations.md, military.md)

| Spec Section | Mechanic | Config File | Status |
|--------------|----------|-------------|--------|
| 7.3.1 | Combat Effectiveness Rating (CER) | `combat_default.toml` | ✅ Complete |
| 7.5 | Planetary Bombardment | `combat_default.toml` | ✅ Complete |
| 7.5.2 | Planetary Shields | `combat_default.toml` | ✅ Complete |
| 7.6 | Ground Combat | `combat_default.toml` | ✅ Complete |

### Espionage & Counter-Intelligence (diplomacy.md)

| Spec Section | Mechanic | Config File | Status |
|--------------|----------|-------------|--------|
| 8.2 | Espionage Action Costs | `economy_default.toml` | ✅ Complete |
| 8.3 | Counter Intelligence Costs | `economy_default.toml` | ✅ Complete |
| 8.2/8.3 | Espionage Prestige Gains/Losses | `prestige_default.toml` | ✅ Complete |

### Diplomacy (diplomacy.md)

| Spec Section | Mechanic | Config File | Status |
|--------------|----------|-------------|--------|
| 8.1 | Diplomatic Prestige Changes | `prestige_default.toml` | ✅ Complete |

### Economy (economy.md)

| Spec Section | Mechanic | Config File | Status |
|--------------|----------|-------------|--------|
| 3.x | Production & Income | `economy_default.toml` | ✅ Complete |
| 3.x | Population Growth | `economy_default.toml` | ✅ Complete |
| 3.x | Construction Times | `economy_default.toml` | ✅ Complete |
| 3.x | Maintenance Costs | `economy_default.toml` | ✅ Complete |

### Technology (economy.md)

| Spec Section | Mechanic | Config File | Status |
|--------------|----------|-------------|--------|
| 3.x | Research Costs | `economy_default.toml` | ✅ Complete |

### Prestige System (reference.md, gameplay.md)

| Spec Section | Category | Config File | Status |
|--------------|----------|-------------|--------|
| 9.4 | Economic Prestige | `prestige_default.toml` | ✅ Complete |
| 9.4 | Military Prestige | `prestige_default.toml` | ✅ Complete |
| 9.4 | Espionage Prestige | `prestige_default.toml` | ✅ Complete |
| 9.4 | Scout Action Prestige | `prestige_default.toml` | ✅ Complete |
| 9.4 | Setback Penalties | `prestige_default.toml` | ✅ Complete |
| 8.1 | Diplomatic Prestige | `prestige_default.toml` | ✅ Complete |
| 1.1 | Victory Conditions | `prestige_default.toml` | ✅ Complete |

## Configuration Files Overview

### 1. `ships_default.toml`
**Coverage**: Space Force ship classes (15 types)
- Fighters through Super Dreadnoughts
- Carriers and Super Carriers
- Raiders, Scouts, Starbases
- ETAC and Troop Transports
- Planet-Breakers

**Stats**: AS, DS, CC, CR, tech level, costs, special capabilities

### 2. `ground_units_default.toml`
**Coverage**: Planetary defense and invasion forces (4 types)
- Planetary Shields (PS)
- Ground Batteries (GB)
- Armies (AA)
- Space Marine Divisions (MD)

**Stats**: AS, DS, build costs, build times, max per planet

### 3. `facilities_default.toml`
**Coverage**: Orbital and planetary infrastructure (2 types)
- Spaceports (SP)
- Shipyards (SY)

**Stats**: Build costs, build times, docks, construction rules

### 4. `combat_default.toml`
**Coverage**: Combat mechanics and tables
- CER tables for space, bombardment, and ground combat
- Critical hit rules
- Planetary shield effectiveness by tech level
- Retreat and damage rules
- Starbase combat modifiers

### 5. `economy_default.toml`
**Coverage**: Economic mechanics and costs
- Starting resources and treasury
- Population growth rates
- Construction times and costs
- Planet class PU limits
- Tax and maintenance rules
- **Research costs** (tech advancement)
- **Espionage costs** (EBP/CIP, action costs)

### 6. `prestige_default.toml`
**Coverage**: Prestige system
- Victory conditions (5000 prestige, last house standing)
- Economic prestige gains (colonies, population, infrastructure, tech)
- Military prestige gains/losses (battles, invasions, starbases)
- Espionage prestige changes (actions and targets)
- Scout action prestige
- Setback penalties (excessive tax, missed maintenance, blockades)
- Diplomatic prestige changes

## Not Requiring Config Files

The following are **fundamental game mechanics** (hardcoded in engine) or procedural/map-specific:

### Core Game Systems (Hardcoded)
- **Tech Tree** (Section 3.x): 7 tech fields (EL, SL, CST, WEP, TER, ELI, CIC), research mechanics, ship requirements
- **Espionage System** (Section 8.2-8.3): 7 action types, detection algorithms, spy scout/raider detection tables, mesh networks
- **Diplomacy System** (Section 8.1): 3 diplomatic states (Neutral, Non-Aggression, Enemy), rules, behaviors, intel sharing
- **Fleet Orders** (Section 6.2): 16 orders (00-15), order behaviors and logic
- **Rules of Engagement** (Section 7.1.1): ROE 0-10, engagement rules, retreat logic

### Procedural/Map-Specific
- **Star Map Generation** (Section 2.1-2.2): Procedural generation using VBAM-inspired rules
- **Jump Lanes** (Section 6.1): Map-specific, generated during map creation
- **Solar System Traits** (Section 2.2): Random generation per hex
- **Space Guilds** (Section 2.5): Abstracted background activity

## Admin Customization

Admins can optionally override any default config by creating game-specific config files:
- Place custom configs in game directory
- Engine loads defaults first, then applies overrides
- No player mods - admin-controlled only

## Implementation Status

All configurable spec data (stats, costs, values) are covered. Core game mechanics are hardcoded in the engine where they belong.

**Total Config Files**: 6
**Config Philosophy**: Tunable numbers only, not game mechanics
**Total Spec Coverage**: 100%
**Status**: ✅ Ready for M2
