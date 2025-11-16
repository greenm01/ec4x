# EC4X Configuration File Coverage

This document maps EC4X specification tables to their corresponding configuration files.

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
| 8.2 | Espionage Actions | `espionage_default.toml` | ✅ Complete |
| 8.3 | Counter Intelligence | `espionage_default.toml` | ✅ Complete |
| 2.4.2 | Spy Scout Detection Tables | `espionage_default.toml` | ✅ Complete |
| 2.4.3 | Raider Detection Tables | `espionage_default.toml` | ✅ Complete |
| 2.4.2 | ELI Mesh Network Modifiers | `espionage_default.toml` | ✅ Complete |

### Diplomacy (diplomacy.md)

| Spec Section | Mechanic | Config File | Status |
|--------------|----------|-------------|--------|
| 8.1 | Diplomatic States | `diplomacy_default.toml` | ✅ Complete |
| 8.1 | Diplomatic Rules | `diplomacy_default.toml` | ✅ Complete |
| 8.1 | Intel Sharing | `diplomacy_default.toml` | ✅ Complete |

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
| 3.x | Tech Fields | `tech_default.toml` | ✅ Complete |
| 3.x | Research Costs | `tech_default.toml` | ✅ Complete |
| 3.x | Ship Tech Requirements | `tech_default.toml` | ✅ Complete |

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
**Coverage**: Economic mechanics
- Starting resources and treasury
- Population growth rates
- Construction times and costs
- Planet class PU limits
- Tax and maintenance rules

### 6. `tech_default.toml`
**Coverage**: Technology research system
- 7 tech fields (EL, SL, CST, WEP, TER, ELI, CIC)
- Research cost formulas (quadratic scaling)
- Ship tech requirements
- Tech level advancement rules

### 7. `espionage_default.toml`
**Coverage**: Espionage and counter-intelligence
- EBP/CIP costs and thresholds
- 7 espionage actions (tech theft, sabotage, assassination, etc.)
- Counter-intelligence detection modifiers
- Spy scout detection tables (ELI1-5 vs ELI1-5)
- Raider detection tables (ELI1-5 vs CLK1-5)
- ELI mesh network modifiers
- Starbase detection bonuses

### 8. `diplomacy_default.toml`
**Coverage**: Diplomatic relations
- 3 diplomatic states (Neutral, Non-Aggression, Enemy)
- Rules and behaviors per state
- Intel sharing under non-aggression
- Defense protocols
- Reputation effects

### 9. `prestige_default.toml`
**Coverage**: Prestige system
- Victory conditions (5000 prestige, last house standing)
- Economic prestige gains (colonies, population, infrastructure, tech)
- Military prestige gains/losses (battles, invasions, starbases)
- Espionage prestige changes (actions and targets)
- Scout action prestige
- Setback penalties (excessive tax, missed maintenance, blockades)
- Diplomatic prestige changes

## Not Requiring Config Files

The following mechanics are fundamental game mechanics, procedural, or map-specific and do not require default config files:

- **Fleet Orders** (Section 6.2): Fundamental game mechanics (16 orders: 00-15)
- **Rules of Engagement** (Section 7.1.1): Core combat behavior (ROE 0-10)
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

All spec data tables are now covered by configuration files. The config system is complete for M2.

**Total Config Files**: 9
**Total Spec Coverage**: 100%
**Status**: ✅ Ready for M2
