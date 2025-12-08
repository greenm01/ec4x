# AI Unit Progression by Act

**Purpose:** Defines when AI advisors (Domestikos, Eparch) can build each unit type across game acts.

**Last Updated:** 2025-12-06

---

## Table of Contents

1. [Unit Availability Table](#unit-availability-table)
2. [Construction Pipelines](#construction-pipelines)
3. [Act-Based Strategy](#act-based-strategy)
4. [Facility Requirements](#facility-requirements)
5. [Design Methodology](#design-methodology)

---

## Unit Availability Table

```
UNIT AVAILABILITY BY ACT
==================================================================================================
Unit Name           | Type      | CST | Cost | Act1 | Act2 | Act3 | Act4 | Pipeline | Notes
==================================================================================================
SHIPS - AUXILIARY/SUPPORT
--------------------------------------------------------------------------------------------------
ETAC                | Auxiliary |  1  |  25  |  X   |      |      |      | Dock     | Until cap
Scout               | Escort    |  1  |  50  |  X   |  X   |  X   |  X   | Dock     | Recon / Espionage
TroopTransport      | Auxiliary |  1  |  30  |      |  X   |  X   |  X   | Dock     | Invasion
Fighter             | Fighter   |  1  |  20  |  X   |  X   |  X   |  X   | Dock     | Colony def / space combat

SHIPS - LIGHT ESCORTS
--------------------------------------------------------------------------------------------------
Corvette            | Escort    |  1  |  20  |  X   |  X   |  X   |  X   | Dock     | Cheapest
Frigate             | Escort    |  1  |  30  |  X   |  X   |  X   |  X   | Dock     | Patrol
Destroyer           | Escort    |  1  |  40  |  X   |  X   |  X   |  X   | Dock     | Workhorse
LightCruiser        | Escort    |  1  |  60  |  X   |  X   |  X   |  X   | Dock     | Medium

SHIPS - CAPITAL (MEDIUM)
--------------------------------------------------------------------------------------------------
Cruiser             | Capital   |  1  |  80  |      |  X   |  X   |  X   | Dock     | Standard
HeavyCruiser        | Capital   |  2  |  80  |      |  X   |  X   |  X   | Dock     | Heavy
Battlecruiser       | Capital   |  3  | 100  |      |  X   |  X   |  X   | Dock     | Fast cap

SHIPS - CAPITAL (HEAVY)
--------------------------------------------------------------------------------------------------
Battleship          | Capital   |  4  | 150  |      |      |  X   |  X   | Dock     | Heavy
Dreadnought         | Capital   |  5  | 200  |      |      |  X   |  X   | Dock     | Very heavy
SuperDreadnought    | Capital   |  6  | 250  |      |      |      |  X   | Dock     | Ultra heavy

SHIPS - SUPPORT
--------------------------------------------------------------------------------------------------
Carrier             | Capital   |  3  | 120  |      |  X   |  X   |  X   | Dock     | Fighter ops
SuperCarrier        | Capital   |  5  | 200  |      |      |  X   |  X   | Dock     | Heavy carrier
Raider              | Capital   |  3  | 150  |      |  X   |  X   |  X   | Dock     | Commerce war

SHIPS - SPECIAL WEAPONS
--------------------------------------------------------------------------------------------------
PlanetBreaker       | Special   | 10  | 400  |      |      |      |  X   | Dock     | Strategic

GROUND UNITS - DEFENSIVE
--------------------------------------------------------------------------------------------------
GroundBattery       | Defensive |  1  |  20  |  X   |  X   |  X   |  X   | Colony   | Basic def
Army                | Defensive |  1  |  15  |  X   |  X   |  X   |  X   | Colony   | Ground def
PlanetaryShield     | Defensive |  5  | 100  |      |  X   |  X   |  X   | Colony   | Ultimate def

GROUND UNITS - OFFENSIVE
--------------------------------------------------------------------------------------------------
Marine              | Offensive |  1  |  25  |      |  X   |  X   |  X   | Colony   | Invasion (matches transports)

FACILITIES (EPARCH - INFRASTRUCTURE)
--------------------------------------------------------------------------------------------------
Spaceport           | Facility  |  1  | 100  |  X   |  X   |  X   |  X   | Colony   | Required for Shipyard/Drydock/Starbase
Shipyard            | Facility  |  1  | 150  |  X   |  X   |  X   |  X   | Colony   | Ship construction only
Drydock             | Facility  |  1  | 150  |  X   |  X   |  X   |  X   | Colony   | Ship repair only
Starbase            | Facility  |  3  | 300  |  X   |  X   |  X   |  X   | Colony   | Orbital defense/detection
```

**Legend:**
- **X** = Unit available in this act
- **CST** = Minimum Construction Tech level required
- **Cost** = Production Points to build
- **Pipeline** = Construction system (Dock vs Colony)

---

## Construction Pipelines

EC4X has **two separate construction pipelines** that operate independently:

### 1. Dock Construction Pipeline

**Units Built:** All ships (18 total, excluding facilities)

**Requirements:**
- Colony must have at least one **Spaceport** or **Shipyard**
- Available dock capacity (not all docks in use)
- Sufficient Production Points (PP)

**Dock Capacity:**
- **Spaceport**: 5 base docks × CST multiplier
  - CST I: 5 docks, CST II: 5.5 docks, CST III: 6 docks, etc.
  - Cost: 2× Shipyard cost for ship construction
  - Cannot repair ships
  - Can repair facilities (Starbases) without consuming dock capacity
- **Shipyard**: 10 base docks × CST multiplier
  - CST I: 10 docks, CST II: 11 docks, CST III: 12 docks, etc.
  - Cost: Standard ship construction cost
  - Can repair ships (only facility that repairs ships)

**CST Scaling Formula:**
```
docks = base_docks × (1.0 + (CST_level - 1) × 0.10)
```

**Example (CST VI):**
- Spaceport: 5 × (1.0 + 5 × 0.10) = 7.5 → 7 docks
- Shipyard: 10 × (1.0 + 5 × 0.10) = 15 docks

### 2. Colony Construction Pipeline

**Units Built:** Ground units (4) + Facilities (4: Spaceport, Shipyard, Drydock, Starbase)

**Requirements:**
- Colony exists
- Available construction slot (one project at a time per colony)
- Sufficient Production Points (PP)

**Special Notes:**
- Ground units consume population (souls) when commissioned
- Facilities are infrastructure (don't consume population)
- PlanetaryShield requires CST V minimum
- Starbases are facilities built via Colony pipeline (not ships in Dock pipeline)

## Repair Pipelines

EC4X has **one repair pipeline** that operates independently:

### 1. Dock Repair Pipeline

**Units Repaired:** All ships (18 total, excluding facilities)

**Requirements:**
- Colony must have at least one **Drydock** or one **Shipyard**
- Available dock capacity (not all docks in use)
- Sufficient Production Points (PP)

**Dock Capacity:**
- **Drydock**: 10 base docks × CST multiplier
  - CST I: 10 docks, CST II: 11 docks, CST III: 12 docks, etc.
  - Cost: Standard ship repair cost
  - Can repair ships (only facility that repairs ships)
- **Spaceport**: 5 base docks × CST multiplier
  - CST I: 5 docks, CST II: 5.5 docks, CST III: 6 docks, etc.
  - Cannot repair ships
  - Can repair facilities without consuming dock capacity
  
**CST Scaling Formula:**
```
docks = base_docks × (1.0 + (CST_level - 1) × 0.10)
```

**Example (CST VI):**
- Drydock: 10 × (1.0 + 5 × 0.10) = 15 docks

---

## Act-Based Strategy

### Act 1 - Land Grab (Turns 1-7 typical)

**Focus:** Rapid expansion, light forces, basic defense

**Primary Units:**
- **ETAC** (expansion to map ring cap)
- **Scout** (reconnaissance)
- **Corvette, Frigate, Destroyer** (cheap escorts)
- **LightCruiser** (medium escort)
- **Starbase** (orbital defense for key colonies)
- **Fighter** (colony/space defense)

**Ground Defense:**
- **GroundBattery** (cheap, effective)
- **Army** (garrison forces)

**Facilities:**
- **Spaceport** (minimum one per colony, required for Shipyard/Drydock/Starbase)
- **Shipyard** (preferred for production)
- **Drydock** (only facility that conducts ship repairs)
- **Starbase** (orbital defense for key colonies)

**Strategy:**
- Rush ETAC to capture systems
- Build cheap escorts for patrol/defense
- Minimal ground defense (batteries + armies)
- Establish Shipyard infrastructure early

---

### Act 2 - Rising Tensions (Turns 8-15 typical)

**Focus:** Military buildup, early aggression, invasion prep

**Primary Units:**
- **Scout** (ongoing recon)
- **TroopTransport** (invasion capability unlocks)
- **Fighter** (space combat, colony defense)
- **Cruiser, HeavyCruiser** (standard capitals)
- **Battlecruiser** (fast heavy hitter, CST III)
- **Carrier** (fighter deployment, CST III)
- **Raider** (commerce warfare, CST III)
- **Starbase** (fortified positions)

**Ground Forces:**
- **Marine** (invasion forces, matches transports)
- **GroundBattery** (continued defense)
- **Army** (garrison forces)
- **PlanetaryShield** (ultimate defense unlocks, CST V)

**Strategy:**
- Build balanced fleets (capitals + escorts + support)
- Prepare invasion capability (Transports + Marines)
- Fortify key colonies (Starbases, Shields)
- Commerce raiding (Raiders target enemy trade)

---

### Act 3 - Total War (Turns 16-25 typical)

**Focus:** Heavy fleet actions, invasions, attrition warfare

**Primary Units:**
- **Scout** (intel critical in war)
- **TroopTransport** (active invasions)
- **Fighter** (space superiority)
- **Battleship** (heavy capital, CST IV)
- **Dreadnought** (very heavy capital, CST V)
- **Battlecruiser, Cruiser** (mid-tier backbone)
- **Carrier** (fighter ops)
- **SuperCarrier** (heavy support, CST V)
- **Raider** (disrupt enemy economy)
- **Starbase** (contested system defense)

**Ground Forces:**
- **Marine** (offensive invasions)
- **GroundBattery, Army** (defensive garrisons)
- **PlanetaryShield** (high-value colony protection)

**Strategy:**
- Heavy capital ships dominate fleet battles
- Coordinated invasions (Transports + Marines + orbital support)
- Commerce denial (Raiders + blockades)
- Layered colony defense (Shields + Batteries + Armies + Starbase)

---

### Act 4 - Endgame (Turns 26-45 typical)

**Focus:** Total domination, strategic weapons, overwhelming force

**Primary Units:**
- **Scout** (final push coordination)
- **TroopTransport** (conquest operations)
- **Fighter** (space control)
- **SuperDreadnought** (ultimate capital, CST VI)
- **Dreadnought, Battleship** (heavy backbone)
- **SuperCarrier** (massive fighter ops)
- **Raider** (economic strangulation)
- **Starbase** (fortress colonies)
- **PlanetBreaker** (strategic bombardment, CST X)

**Ground Forces:**
- **Marine** (final invasions)
- **PlanetaryShield** (impenetrable defense)
- **GroundBattery, Army** (layered defense)

**Strategy:**
- Overwhelming fleet superiority (SuperDreadnoughts + support)
- Strategic bombardment (PlanetBreakers vs fortified targets)
- Total economic war (Raiders + blockades)
- Fortress homeworlds (Shields + Starbases + full garrisons)

---

## Facility Requirements

### Spaceport

**Purpose:** Basic ship construction, required for advanced facilities

**Characteristics:**
- Base cost: 100 PP
- Base docks: 5 (CST-scaled)
- Ship construction: 2× Shipyard cost
- Cannot repair ships
- Can repair facilities (Starbases, Shipyards, Drydocks) without consuming dock capacity
- Required for: Shipyard, Starbase

**Strategic Use:**
- Minimum one per colony (unlocks Shipyard/Starbase/Drydock)
- Emergency ship construction (if Drydocks destroyed)
- Not cost-effective for regular production
- Handles facility repair (Starbase, Shipyard, and Drydock) with no dock consumption and allows parallel construction.

### Shipyard

**Purpose:** Efficient ship construction only

**Characteristics:**
- Base cost: 150 PP
- Base docks: 10 (CST-scaled, 2× Spaceport)
- Ship construction: Standard construction cost
- Cannot repair ships (use Drydock for repairs)
- Requires: Spaceport

**Strategic Use:**
- Primary ship production facility
- Build multiple per high-production colony
- Significant advantage over Spaceports (capacity + cost)

### Drydock

**Purpose:** Efficient ship repair only

**Characteristics:**
- Base cost: 150 PP
- Base docks: 10 (CST-scaled)
- Ship repair: Standard repair cost
- Can repair ships (only facility that repairs ships)
- Cannot repair colony-based facilities (Spaceports, buildings)
- Cannot construct new ships (use Shipyard for construction)
- Requires: Spaceport

**Strategic Use:**
- Primary ship repair facility
- Critical for fleet maintenance and sustainability
- Build multiple at high-production colonies with active fleets

### Starbase

**Purpose:** Orbital defense, detection, economic bonuses

**Characteristics:**
- Base cost: 300 PP (fixed, no WEP scaling)
- Construction time: 3 turns
- Construction pipeline: Colony (not Dock)
- Combat stats: AS 45, DS 50 (both scale with WEP +10% per level)
- Requires: Spaceport
- Repair: Uses Spaceport, no dock consumption

**Strategic Use:**
- Orbital defense for key colonies
- Detection bonus (+2 ELI) for Scout/Raider detection
- Economic bonuses (5% growth/production per Starbase, max 3)
- Required for fighter squadron infrastructure (1 per 5 FS)
- Built via Colony pipeline (Eparch advisor, not Domestikos)

### Facility Strategy by Act

**Act 1:**
- One Spaceport per colony (minimum, unlocks Shipyard/Drydock/Starbase)
- One Shipyard at homeworld (construction core)
- One Drydock at homeworld (repair core)
- One Starbase at homeworld (defense + economic bonus)

**Act 2:**
- Shipyards and Drydocks at high-production colonies
- Starbases at strategic/high-value colonies (2-3 per colony for max bonuses)
- Second Spaceport only in emergencies

**Act 3:**
- Multiple Shipyards and Drydocks at major production centers
- Starbases at all contested systems (defense critical)
- Spaceports remain minimal (one per colony)

**Act 4:**
- Shipyard and Drydock networks across empire
- Starbase networks for fortress colonies
- Repair capacity critical (fleet + facility sustainability)

---

## Design Methodology

### CST-Gating Philosophy

Units are **CST-gated but Act-progressive**:

1. **Tech unlocks, Act guides usage**
   - CST requirements prevent premature builds (e.g., PlanetBreaker at CST X)
   - Act progression determines when AI prioritizes unit types
   - Example: Battlecruiser unlocks at CST III but AI prioritizes in Act 2+

2. **Fallback cascades**
   - If CST requirement not met, AI builds lower-tier alternatives
   - Example: Act 4 wants SuperDreadnought (CST VI) → falls back to Dreadnought (CST V) → Battleship (CST IV) → etc.

3. **Strategic timing matches gameplay**
   - Act 1 = Expansion (ETACs, scouts, light escorts)
   - Act 2 = Buildup (capitals, carriers, invasion prep)
   - Act 3 = War (heavy capitals, active invasions)
   - Act 4 = Endgame (ultimate weapons, overwhelming force)

### Capacity Filler Integration

The **capacity filler** (Domestikos advisor) implements this table via 20-slot rotation:

- **Slots 0-8 (45%)**: ETAC (until cap) or Act-appropriate military
- **Slots 9-10 (10%)**: Military ships (Act-progressive)
- **Slots 11-12 (10%)**: Scouts (all acts)
- **Slots 13-14 (10%)**: SpecialUnits (Fighter → Transport → PlanetBreaker)
- **Slot 15 (5%)**: Defense (GroundBattery → Starbase)
- **Slot 16 (5%)**: Defense (Army → Marine → PlanetaryShield)
- **Slot 17 (5%)**: Mid-tier military
- **Slots 18-19 (10%)**: Affordable military

Each slot checks current Act and selects appropriate units from candidate lists (CST-gated).

### Ground Unit Strategy

**Defensive progression:**
1. **Act 1**: Batteries + Armies (cheap, effective)
2. **Act 2**: Add PlanetaryShields (CST V, high-value colonies)
3. **Act 3-4**: Layered defense (Shields + Batteries + Armies)

**Offensive progression:**
1. **Act 1**: No invasion capability
2. **Act 2**: Marines + TroopTransports unlock (early aggression)
3. **Act 3-4**: Coordinated invasions (Marines + orbital support)

### Facility Strategy

**Spaceport:**
- Minimum one per colony (requirement for Shipyard/Starbase)
- Emergency ship construction only (2× cost inefficient)
- Handles facility repairs (Starbases, Shipyards, Drydocks - no dock consumption)
- Not prioritized for multiple builds

**Shipyard:**
- Primary ship production facility (2× Spaceport capacity, 1× cost)
- Build multiple at high-production colonies
- Scales with CST (capacity increases 10% per level)

**Drydock:**
- Only facility that repairs ships (critical for fleet sustainability)
- Build multiple at high-production colonies
- Scales with CST (capacity increases 10% per level)

**Starbase:**
- Built via Colony pipeline (Eparch advisor)
- Requires Spaceport (uses it for construction/repair)
- Orbital defense + detection + economic bonuses
- Build 2-3 per colony for maximum benefits (5% each, 15% max)
- Repairs at Spaceport without consuming dock capacity

---

## Related Documentation

- **Construction System**: [construction-systems.md](construction-systems.md)
- **Economy Mechanics**: [../specs/economy.md](../specs/economy.md)
- **Ship Reference**: [../specs/reference.md](../specs/reference.md)
- **AI Budget System**: [../ai/balance/RBA_BUDGET_ALLOCATION_FIX.md](../ai/balance/RBA_BUDGET_ALLOCATION_FIX.md)

---

**Maintained by:** AI Development Team
**Last Review:** 2025-12-06
**Next Review:** After Phase 3 balance testing
