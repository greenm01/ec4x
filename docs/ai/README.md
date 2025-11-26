# EC4X AI Documentation

## Overview

EC4X uses a **Rule-Based Advisor (RBA)** system for AI players. The AI is modular, fog-of-war aware, and designed for strategic depth across 12 different personality archetypes.

**Location:** `src/ai/rba/`

---

## Documentation Structure

- **[ARCHITECTURE.md](ARCHITECTURE.md)** - Modular AI system design
- **[DECISION_FRAMEWORK.md](DECISION_FRAMEWORK.md)** - How AI makes decisions
- **[PERSONALITIES.md](PERSONALITIES.md)** - 12 strategy archetypes explained

---

## Quick Reference

### AI System Components

```
src/ai/rba/
├── player.nim           # Public API
├── controller.nim       # Strategy profiles & constructors
├── controller_types.nim # Type definitions
├── budget.nim          # Multi-objective budget allocation
├── intelligence.nim    # Intel gathering & reconnaissance
├── diplomacy.nim       # Diplomatic assessment
├── tactical.nim        # Fleet operations & coordination
└── strategic.nim       # Combat & invasion assessment
```

### Key Concepts

**Rule-Based Advisor (RBA)**
- Expert system using personality traits
- Respects fog-of-war (uses `FilteredGameState`)
- Modular decision-making across 8 subsystems

**AI Personality**
- 6 continuous traits (0.0-1.0): `aggression`, `riskTolerance`, `economicFocus`, `expansionDrive`, `diplomacyValue`, `techPriority`
- 12 predefined strategies (Aggressive, Economic, Espionage, etc.)
- Genetic algorithms can evolve custom personalities

**4-Act Structure** (Phase-Aware AI)
- Act 1 (turns 1-7): Land Grab - rapid colonization
  - Priority: Exploration >> Colonization >> Minimal Defense
  - Budget: 60% expansion, 10% military, 15% intelligence
  - Behavior: Aggressive ETAC production, fleet fan-out exploration
- Act 2 (turns 8-15): Rising Tensions - military buildup
  - Priority: Military >> Defense >> Opportunistic Colonization
  - Budget: 35% expansion, 30% military, 15% defense
  - Behavior: Shift to military production, maintain expansion momentum
- Act 3 (turns 16-25): Total War - major conflicts
  - Priority: Invasions >> Defense >> Combat
  - Budget: 0% expansion, 55% military, 15% special units
  - Behavior: Coordinated invasions, zero colonization (conquest only)
- Act 4 (turns 26-30): Endgame - victory push
  - Priority: All-in strategies, final confrontations
  - Budget: 60% military, 10% defense, 15% special units
  - Behavior: Desperate alliances, last betrayals, victory conditions

---

## Usage

### Creating AI Players

```nim
import ai/rba/player

# Predefined strategy
let ai = newAIController(houseId, AIStrategy.Aggressive)

# Custom personality
let personality = AIPersonality(
  aggression: 0.8,
  riskTolerance: 0.7,
  economicFocus: 0.3,
  expansionDrive: 0.9,
  diplomacyValue: 0.1,
  techPriority: 0.4
)
let customAI = newAIControllerWithPersonality(houseId, personality)

# Generate orders (respects fog-of-war)
let filteredView = createFogOfWarView(gameState, houseId)
let orders = generateAIOrders(ai, filteredView, rng)
```

### 12 AI Strategies

| Strategy | Aggression | Economic | Expansion | Tech | Diplomacy | Risk |
|----------|-----------|----------|-----------|------|-----------|------|
| Aggressive | 0.9 | 0.2 | 0.7 | 0.3 | 0.1 | 0.8 |
| Economic | 0.2 | 0.9 | 0.6 | 0.7 | 0.5 | 0.3 |
| Espionage | 0.3 | 0.6 | 0.4 | 0.8 | 0.4 | 0.7 |
| Diplomatic | 0.2 | 0.6 | 0.5 | 0.5 | 0.9 | 0.4 |
| Balanced | 0.5 | 0.5 | 0.5 | 0.5 | 0.5 | 0.5 |
| Turtle | 0.1 | 0.7 | 0.3 | 0.6 | 0.6 | 0.2 |
| Expansionist | 0.4 | 0.5 | 0.9 | 0.4 | 0.3 | 0.6 |
| TechRush | 0.2 | 0.7 | 0.4 | 0.9 | 0.5 | 0.4 |
| Raider | 0.7 | 0.3 | 0.5 | 0.4 | 0.2 | 0.8 |
| MilitaryIndustrial | 0.6 | 0.7 | 0.6 | 0.5 | 0.3 | 0.5 |
| Opportunistic | 0.5 | 0.6 | 0.6 | 0.6 | 0.4 | 0.7 |
| Isolationist | 0.3 | 0.8 | 0.4 | 0.7 | 0.1 | 0.3 |

---

## Testing & Optimization

**Balance Testing:** See [../testing/BALANCE_METHODOLOGY.md](../testing/BALANCE_METHODOLOGY.md)
- Regression testing with fixed strategies
- 4-act progression validation
- Engine stability verification

**AI Tuning:** See `tools/ai_tuning/USAGE.md`
- Genetic algorithm optimization
- Competitive co-evolution
- Exploit discovery

---

## Implementation Notes

### Fog-of-War Integration

AI **MUST** use `FilteredGameState`, never full `GameState`:

```nim
# ❌ BAD - omniscient AI
let orders = generateAIOrders(controller, gameState, rng)

# ✅ GOOD - respects fog-of-war
let filteredView = createFogOfWarView(gameState, controller.houseId)
let orders = generateAIOrders(controller, filteredView, rng)
```

### Decision Pipeline

1. **Strategic Planning** (`tactical.nim`)
   - Update operation status
   - Manage strategic reserves
   - Plan coordinated invasions

2. **Intelligence** (`intelligence.nim`)
   - Update system intel
   - Identify reconnaissance needs
   - Find colonization targets

3. **Order Generation**
   - Fleet orders (movement, combat)
   - Build orders (ships, structures)
   - Research allocation
   - Diplomatic actions
   - Espionage missions

4. **Budget Allocation** (`budget.nim`)
   - Multi-objective optimization
   - Resource constraints
   - Priority-based distribution

### Modular Design Benefits

- **Separation of concerns** - Each module handles one domain
- **Testable** - Mock FilteredGameState for unit tests
- **Extensible** - Add new behaviors without touching core
- **Maintainable** - ~250 lines per module vs 3,600-line monolith

---

## Recent Improvements

### 2025-11-26: Comprehensive Diagnostic System Expansion

**Expanded diagnostic metrics from 55 to 130 columns (+136% coverage):**

Added 75 new metrics derived from specifications and config files:
- **Tech Levels:** All 11 technologies (CST, WEP, EL, SL, TER, ELI, CLK, SLD, CIC, FD, ACO)
- **Combat Performance:** CER averages, critical hits, retreats, bombardment rounds, shield activations
- **Diplomatic Status:** Active pacts, violations, dishonor status, isolation tracking
- **Espionage Activity:** EBP/CIP spending, operation outcomes, counter-intel successes
- **Population & Colonies:** Space Guild transfers, blockaded colonies, blockade durations
- **Economic Health:** Treasury deficits, infrastructure damage, salvage recovered, tax penalties
- **Squadron Capacity:** Fighter/capital squadron limits and violations, starbase requirements
- **House Status:** Autopilot, defensive collapse, elimination countdown, MIA risk

**Key Finding:** CST never reaches level 10 (Planet-Breaker requirement) within typical game lengths. Maximum CST observed: level 4 by turn 100. This explains zero Planet-Breaker deployments across all balance tests.

**Impact:** Comprehensive metrics enable detection of unknown-unknowns like:
- Squadron capacity violations limiting military growth
- Blockades preventing expansion
- Espionage disrupting economies
- Tax penalties throttling development
- Diplomatic destabilization cascading into collapse

### 2025-11-26: Phase-Aware Tactical System

Fixed 5 critical bugs that caused complete AI paralysis in early game:

**Bug #1: ETAC Build Logic** (`orders.nim`)
- Was treating ETACs as military units instead of colonizers
- Now: Act-aware logic - ALWAYS build in Act 1, opportunistic in Act 2, zero in Act 3+

**Bug #2: Static Tactical Priorities** (`tactical.nim`)
- "Pickup squadrons" priority blocked ALL fleets from exploring
- Now: Complete rewrite with phase-aware 4-act priority system

**Bug #3: Scout Build Logic** (`orders.nim`)
- Limited to 1 scout per colony (incorrect understanding of scout role)
- Now: Scouts for spying on known enemies, not exploration (any ship can explore!)

**Bug #4: ETAC Production Gate** (`budget.nim`)
- Required 50+ colony production to build ETACs (early colonies average 17-26 PP)
- Now: Removed production gate - budget is the only limit

**Bug #5: Act 2 Budget Collapse** (`budget.nim`)
- Only allocated 20% to expansion in Act 2, crushing momentum
- Now: 35% expansion budget maintains colonization through Act 2

**Results:**
- Before: 1 colony by Turn 7 (complete paralysis)
- After: 4-5 colonies by Turn 7 (300-400% improvement) ✅
- 1,536 games validated (Acts 1-4) with 0 AI collapses
- Act 1 functional, Act 2 needs further tuning (plateau at 4-6 colonies by Turn 30)

**Key Insights:**
- ETACs are colonization ships, not military units
- Any ship can explore (engine auto-generates intel on fleet encounters)
- Scouts are for spying on known colonies, not exploration
- Phase-aware priorities critical for 4-act game structure
- Production gates on strategic units are dangerous

---

## See Also

- [ARCHITECTURE.md](ARCHITECTURE.md) - Detailed system design
- [DECISION_FRAMEWORK.md](DECISION_FRAMEWORK.md) - Decision-making process
- [PERSONALITIES.md](PERSONALITIES.md) - Strategy details & use cases
- `../../src/ai/rba/README.md` - Implementation reference
- `../../tools/ai_tuning/README.md` - Optimization tools
