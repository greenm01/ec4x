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

**4-Act Structure**
- Act 1 (turns 1-7): Land Grab - rapid colonization
- Act 2 (turns 8-15): Rising Tensions - military buildup
- Act 3 (turns 16-25): Total War - major conflicts
- Act 4 (turns 26-30): Endgame - victory push

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

## See Also

- [ARCHITECTURE.md](ARCHITECTURE.md) - Detailed system design
- [DECISION_FRAMEWORK.md](DECISION_FRAMEWORK.md) - Decision-making process
- [PERSONALITIES.md](PERSONALITIES.md) - Strategy details & use cases
- `../../src/ai/rba/README.md` - Implementation reference
- `../../tools/ai_tuning/README.md` - Optimization tools
