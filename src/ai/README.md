# EC4X AI System

Modular Rule-Based Advisor (RBA) implementation for EC4X AI players.

**Complete Documentation:** See [/docs/ai/README.md](../../docs/ai/README.md)

---

## Directory Structure

```
src/ai/
└── rba/                      # Rule-Based Advisor (modular AI)
    ├── player.nim            # Public API (14 lines)
    ├── controller_types.nim  # Type definitions (16 lines)
    ├── controller.nim        # Strategy profiles (169 lines)
    ├── intelligence.nim      # Intel gathering (310 lines)
    ├── diplomacy.nim         # Diplomatic assessment (224 lines)
    ├── tactical.nim          # Fleet operations (404 lines)
    ├── strategic.nim         # Combat assessment (257 lines)
    └── budget.nim            # Budget allocation (328 lines)

Total: 1,722 lines (8 modules)
```

---

## Quick Reference

### Creating AI Players

```nim
import ai/rba/player

# Predefined strategy
let ai = newAIController(houseId, AIStrategy.Aggressive)

# Custom personality (for genetic algorithms)
let personality = AIPersonality(
  aggression: 0.8,
  riskTolerance: 0.7,
  economicFocus: 0.3,
  expansionDrive: 0.9,
  diplomacyValue: 0.1,
  techPriority: 0.4
)
let customAI = newAIControllerWithPersonality(houseId, personality)

# Generate orders (fog-of-war aware)
let filteredView = createFogOfWarView(gameState, houseId)
let orders = generateAIOrders(ai, filteredView, rng)
```

### 12 AI Strategies

- **Aggressive** - Heavy military, early attacks (Harkonnen-style)
- **Economic** - Growth and tech focused (Richese-style)
- **Espionage** - Intelligence and sabotage (Ordos-style)
- **Diplomatic** - Pacts and manipulation (Corrino-style)
- **Balanced** - Mixed approach (Atreides-style)
- **Turtle** - Defensive consolidation (Bene Gesserit-style)
- **Expansionist** - Rapid colonization (Ixian-style)
- **TechRush** - Science focused (Vernius-style)
- **Raider** - Hit-and-run tactics (Moritani-style)
- **MilitaryIndustrial** - Sustained warfare (Ginaz-style)
- **Opportunistic** - Adaptive exploitation (Ecaz-style)
- **Isolationist** - Self-contained (Tleilaxu-style)

---

## Module Overview

### Public API (`player.nim`)

Clean entry point for AI system. Exports all subsystems and constructors.

**Exports:**
- `AIController`, `AIStrategy`, `AIPersonality`
- `newAIController()`, `newAIControllerWithPersonality()`
- `generateAIOrders()` - Main decision pipeline
- All subsystem modules

### Controller & Strategies (`controller.nim`)

Strategy definitions and personality mappings.

**Key Functions:**
- `getStrategyPersonality(strategy)` - Get predefined personality traits
- `getCurrentGameAct(turn)` - Determine current game phase (4-act structure)

### Intelligence (`intelligence.nim`)

Information gathering, reconnaissance, target identification.

**Key Functions:**
- `needsReconnaissance()` - Identify unexplored systems
- `updateIntelligence()` - Update system intel reports
- `findBestColonizationTarget()` - Colony site selection
- `identifyEnemyHomeworlds()` - Strategic target identification

### Diplomacy (`diplomacy.nim`)

Diplomatic situation assessment and strength calculations.

**Key Functions:**
- `calculateMilitaryStrength()` - Fleet power assessment
- `calculateEconomicStrength()` - Economic capability
- `assessDiplomaticSituation()` - Pact/enemy recommendations

### Tactical (`tactical.nim`)

Fleet coordination, operations planning, threat response.

**Key Functions:**
- `planCoordinatedOperation()` - Multi-fleet operations
- `manageStrategicReserves()` - Defense fleet allocation
- `respondToThreats()` - Automatic threat response
- `updateFallbackRoutes()` - Safe retreat planning

### Strategic (`strategic.nim`)

Combat assessment and invasion planning.

**Key Functions:**
- `assessCombatSituation()` - Combat odds calculation
- `assessInvasionViability()` - 3-phase invasion analysis (space, starbase, ground)
- `identifyInvasionOpportunities()` - Find weak targets

### Budget (`budget.nim`)

Multi-objective resource allocation across competing priorities.

**Key Functions:**
- `allocateBudget()` - High-level budget distribution
- `calculateObjectiveBudgets()` - Priority-based allocation
- `generateBuildOrdersWithBudget()` - Order generation with constraints

### Type Definitions (`controller_types.nim`)

Shared type definitions to break circular imports.

**Pattern:** Separate types from implementation, allowing tactical/strategic/etc. to all reference `AIController` without cycles.

---

## Design Principles

### Fog-of-War Enforcement

**All AI functions accept `FilteredGameState`, never `GameState`.**

```nim
# ❌ BAD - Would allow omniscient AI
proc assessCombat(controller: AIController, state: GameState, ...) = ...

# ✅ GOOD - Enforces fog-of-war
proc assessCombat(controller: AIController, filtered: FilteredGameState, ...) = ...
```

**Type safety:** Compiler prevents accidental use of full game state.

### Modular Design Benefits

- **Separation of concerns** - Each module handles one domain
- **Testable** - Mock FilteredGameState for unit tests
- **Extensible** - Add new behaviors without touching core
- **Maintainable** - ~250 lines per module vs 3,600-line monolith
- **Fast compilation** - Incremental builds (~2-3s per module)

### Circular Import Resolution

**Problem:** Modules need to reference `AIController` type, but can't all import from controller.nim (circular dependency).

**Solution:** Separate types into `controller_types.nim`:

```nim
# controller_types.nim - ONLY types, no implementation
type AIController* = ref object
  houseId*: HouseId
  personality*: AIPersonality
  # ...

# tactical.nim - imports types only
import ./controller_types
proc manageReserves*(controller: var AIController, ...) = ...

# strategic.nim - also imports types only
import ./controller_types
proc assessCombat*(controller: AIController, ...) = ...
```

---

## Testing

### Unit Testing (Planned)

```nim
# Mock FilteredGameState for isolated tests
let mockView = FilteredGameState(
  viewingHouse: "house-test",
  ownColonies: @[testColony],
  ownFleets: @[testFleet]
)

# Test intelligence module
suite "Intelligence":
  test "Reconnaissance needs detection":
    let controller = newAIController("house-test", AIStrategy.Balanced)
    assert needsReconnaissance(mockView, "system-unknown")
```

### Integration Testing (Balance Testing)

```bash
nimble testBalanceQuick    # 20 games, 7 turns (~10s)
nimble testBalanceAct1     # 100 games, Act 1
nimble testBalanceAll4Acts # 400 games, all 4 acts
```

### AI Optimization (Genetic Algorithms)

```bash
nimble evolveAI            # 50 generations, find optimal personalities
nimble coevolveAI          # 4-species competitive evolution
```

---

## Adding New AI Behaviors

### 1. Choose Appropriate Module

- **Intelligence** - Information gathering, reconnaissance
- **Diplomacy** - Strength assessment, pact decisions
- **Tactical** - Fleet coordination, operations
- **Strategic** - Combat assessment, invasion planning
- **Budget** - Resource allocation, build priorities

### 2. Respect Fog-of-War

All functions must accept `FilteredGameState`:

```nim
proc myNewFeature*(controller: var AIController,
                   filtered: FilteredGameState): MyResult =
  # Use filtered.ownColonies, filtered.visibleSystems
  # Never access full game state
```

### 3. Use Personality Traits

```nim
let personality = controller.personality

if personality.aggression >= 0.7:
  # Aggressive behavior
elif personality.economicFocus >= 0.6:
  # Economic behavior
```

### 4. Add Tests

Create unit tests and run balance tests to verify behavior.

---

## Performance Characteristics

**Decision Generation:** ~1-5ms per AI per turn (depends on game size)

**Memory:** Each AIController ~1-2KB, total AI memory <1MB for 12 players

**Bottleneck:** Game engine resolution (~50-100ms per turn), not AI decisions

---

## See Also

- **[Complete AI Documentation](../../docs/ai/README.md)** - Full system overview
- **[AI Architecture](../../docs/ai/ARCHITECTURE.md)** - Detailed design
- **[AI Personalities](../../docs/ai/PERSONALITIES.md)** - Strategy details
- **[Decision Framework](../../docs/ai/DECISION_FRAMEWORK.md)** - Decision-making process
- **[Testing Methodology](../../docs/testing/README.md)** - Balance testing approach
- **[AI Tuning Tools](../../tools/ai_tuning/USAGE.md)** - Genetic algorithm optimization
