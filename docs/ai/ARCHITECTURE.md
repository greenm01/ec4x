# EC4X AI Architecture

## Overview

EC4X's AI uses a **modular Rule-Based Advisor (RBA)** architecture. The system is separated into 8 specialized modules, each handling a specific domain of decision-making.

**Design Philosophy:** Expert system with personality-driven behavior, fog-of-war aware, and strategically deep.

---

## Module Structure

```
src/ai/rba/
├── player.nim              # Public API (14 lines)
├── controller_types.nim    # Type definitions (16 lines)
├── controller.nim          # Strategy profiles (169 lines)
├── budget.nim             # Budget allocation (328 lines)
├── intelligence.nim       # Intel gathering (310 lines)
├── diplomacy.nim          # Diplomatic assessment (224 lines)
├── tactical.nim           # Fleet operations (404 lines)
└── strategic.nim          # Combat assessment (257 lines)

Total: 1,722 lines (vs 3,679-line monolith)
```

---

## Core Components

### 1. Public API (`player.nim`)

**Responsibility:** Clean entry point for AI system

```nim
import ai/rba/player

let ai = newAIController(houseId, AIStrategy.Aggressive)
let orders = generateAIOrders(ai, filteredView, rng)
```

**Exports:**
- `AIController`, `AIStrategy`, `AIPersonality`
- `newAIController()`, `newAIControllerWithPersonality()`
- `getStrategyPersonality()`, `getCurrentGameAct()`
- All subsystem modules (intelligence, diplomacy, tactical, strategic, budget)

---

### 2. Type Definitions (`controller_types.nim`)

**Responsibility:** Break circular imports

**Pattern:** Separate type definitions from implementation to avoid dependency cycles.

```nim
type AIController* = ref object
  houseId*: HouseId
  strategy*: AIStrategy
  personality*: AIPersonality
  intelligence*: Table[SystemId, IntelligenceReport]
  operations*: seq[CoordinatedOperation]
  reserves*: seq[StrategicReserve]
  fallbackRoutes*: seq[FallbackRoute]
```

**Why:** Allows tactical.nim, strategic.nim, etc. to all import controller types without circular dependencies.

---

### 3. Controller & Strategies (`controller.nim`)

**Responsibility:** Strategy definitions and constructors

**12 Predefined Strategies:**

```nim
proc getStrategyPersonality*(strategy: AIStrategy): AIPersonality =
  case strategy
  of AIStrategy.Aggressive:
    AIPersonality(
      aggression: 0.9,
      riskTolerance: 0.8,
      economicFocus: 0.2,
      expansionDrive: 0.7,
      diplomacyValue: 0.1,
      techPriority: 0.3
    )
  # ... 11 more strategies
```

**Constructors:**
- `newAIController(houseId, strategy)` - Use predefined strategy
- `newAIControllerWithPersonality(houseId, personality)` - Custom personality (for GA)

**4-Act Detection:**
```nim
proc getCurrentGameAct*(turn: int): GameAct =
  if turn <= 7: Act1_LandGrab
  elif turn <= 15: Act2_RisingTensions
  elif turn <= 25: Act3_TotalWar
  else: Act4_Endgame
```

---

### 4. Intelligence (`intelligence.nim`)

**Responsibility:** Information gathering, reconnaissance, target identification, travel time analysis

**Key Functions:**

```nim
# System reconnaissance
proc needsReconnaissance*(filtered: FilteredGameState, targetSystem: SystemId): bool
proc updateIntelligence*(controller: var AIController, filtered: FilteredGameState,
                        systemId: SystemId, turn: int, confidenceLevel: float)

# Target identification
proc findBestColonizationTarget*(controller: AIController, filtered: FilteredGameState,
                                 fromSystem: SystemId): Option[SystemId]
proc identifyEnemyHomeworlds*(controller: AIController, filtered: FilteredGameState): seq[SystemId]

# Economic intel
proc gatherEconomicIntelligence*(controller: var AIController,
                                 filtered: FilteredGameState): seq[EconomicIntelligence]

# Travel time & ETA calculations (NEW)
proc calculateETA*(starMap: StarMap, fromSystem: SystemId, toSystem: SystemId,
                   fleet: Fleet): Option[int]
proc calculateMultiFleetETA*(starMap: StarMap, assemblyPoint: SystemId,
                              fleets: seq[Fleet]): Option[int]
```

**Intelligence Report:**
```nim
type IntelligenceReport* = object
  systemId*: SystemId
  lastUpdated*: int              # Turn number
  hasColony*: bool
  owner*: Option[HouseId]
  estimatedFleetStrength*: int
  estimatedDefenses*: int
  planetClass*: Option[PlanetClass]
  resources*: Option[ResourceRating]
  confidenceLevel*: float        # 0.0-1.0
```

**Fog-of-War Integration:** All queries use `FilteredGameState`, never full game state.

---

### 5. Diplomacy (`diplomacy.nim`)

**Responsibility:** Diplomatic situation assessment

**Key Functions:**

```nim
# Strength assessment
proc calculateMilitaryStrength*(filtered: FilteredGameState, houseId: HouseId): int
proc calculateEconomicStrength*(filtered: FilteredGameState, houseId: HouseId): int

# Diplomatic analysis
proc assessDiplomaticSituation*(controller: AIController, filtered: FilteredGameState,
                                targetHouse: HouseId): DiplomaticAssessment

# Helper utilities
proc getOwnedFleets*(filtered: FilteredGameState, houseId: HouseId): seq[Fleet]
proc getOwnedColonies*(filtered: FilteredGameState, houseId: HouseId): seq[Colony]
proc getFleetStrength*(fleet: Fleet): int
```

**Diplomatic Assessment:**
```nim
type DiplomaticAssessment* = object
  targetHouse*: HouseId
  relativeMilitaryStrength*: float   # Our strength / their strength
  relativeEconomicStrength*: float
  mutualEnemies*: seq[HouseId]
  geographicProximity*: int
  violationRisk*: float              # 0.0-1.0
  currentState*: DiplomaticState
  recommendPact*: bool
  recommendBreak*: bool
  recommendEnemy*: bool
```

---

### 6. Tactical (`tactical.nim`)

**Responsibility:** Fleet coordination, operations planning, threat response

**Coordinated Operations:**

```nim
# Multi-fleet operations
proc planCoordinatedOperation*(controller: var AIController, filtered: FilteredGameState,
                               opType: OperationType, targetSystem: SystemId,
                               requiredFleets: seq[FleetId], assemblyPoint: SystemId)
proc updateOperationStatus*(controller: var AIController, filtered: FilteredGameState)
proc removeCompletedOperations*(controller: var AIController, turn: int)

# Strategic reserves
proc identifyImportantColonies*(controller: AIController, filtered: FilteredGameState): seq[SystemId]
proc manageStrategicReserves*(controller: var AIController, filtered: FilteredGameState)

# Threat response
proc respondToThreats*(controller: var AIController, filtered: FilteredGameState):
                       seq[tuple[reserveFleet: FleetId, threatSystem: SystemId]]

# Fallback routes (safe retreat planning)
proc updateFallbackRoutes*(controller: var AIController, filtered: FilteredGameState)
proc findFallbackSystem*(controller: AIController, currentSystem: SystemId): Option[SystemId]
```

**Operation Types:**
- Invasion - Multi-fleet assault on enemy colony
- Defense - Coordinated defense of important system
- Raid - Quick strike with concentrated force
- Blockade - Economic warfare with fleet support

**Strategic Reserve Pattern:**
- Important colonies get dedicated defense fleets
- Reserve fleets automatically respond to nearby threats
- Response radius based on system connectivity

---

### 7. Strategic (`strategic.nim`)

**Responsibility:** Combat assessment, invasion planning

**Key Functions:**

```nim
# Combat evaluation
proc assessCombatSituation*(controller: AIController, filtered: FilteredGameState,
                            targetSystem: SystemId): CombatAssessment

# Invasion planning
proc assessInvasionViability*(controller: AIController, filtered: FilteredGameState,
                              targetSystem: SystemId): InvasionViability
proc identifyInvasionOpportunities*(controller: AIController, filtered: FilteredGameState):
                                     seq[SystemId]

# Colony assessment
proc calculateDefensiveStrength*(filtered: FilteredGameState, systemId: SystemId): int
proc estimateColonyValue*(filtered: FilteredGameState, systemId: SystemId): int
```

**Combat Assessment:**
```nim
type CombatAssessment* = object
  targetSystem*: SystemId
  ourStrength*: int
  enemyStrength*: int
  enemyStarbaseStrength*: int
  combatOdds*: float                # 0.0-1.0 (our win probability)
  recommendAttack*: bool
```

**Invasion Viability (3-Phase Analysis):**
```nim
type InvasionViability* = object
  targetSystem*: SystemId

  # Phase 1: Space Combat
  canWinSpaceCombat*: bool
  spaceOdds*: float

  # Phase 2: Starbase Assault
  canOvercomeStarbase*: bool
  starbaseOdds*: float

  # Phase 3: Ground Invasion
  canInvade*: bool
  marinesNeeded*: int

  # Recommendations
  recommendInvade*: bool
  recommendBlitz*: bool             # Quick strike before reinforcements
  recommendBlockade*: bool          # Economic warfare alternative
```

---

### 8. Budget (`budget.nim`)

**Responsibility:** Multi-objective resource allocation

**Budget Allocation System:**

```nim
# High-level allocation
proc allocateBudget*(controller: AIController, filtered: FilteredGameState): BudgetAllocation

# Objective-based budgets
proc calculateObjectiveBudgets*(controller: AIController, filtered: FilteredGameState,
                               totalBudget: int): Table[BuildObjective, int]

# Order generation with budget constraints
proc generateBuildOrdersWithBudget*(controller: AIController, filtered: FilteredGameState,
                                   budgets: Table[BuildObjective, int]): seq[BuildOrder]
```

**Build Objectives (Priority-Based):**
```nim
type BuildObjective* {.pure.} = enum
  EmergencyDefense,      # Under attack - highest priority
  Colonization,          # ETACs for expansion
  MilitaryExpansion,     # Offensive fleets
  EconomicGrowth,        # Infrastructure
  TechAdvancement,       # Research facilities
  Reconnaissance         # Scout ships
```

**Budget Formula:**
```nim
let totalProduction = calculateTotalProduction(filtered, controller.houseId)
let baseDefenseBudget = (totalProduction * 20) div 100  # 20% for defense
let offensiveBudget = (totalProduction * 30) div 100    # 30% for offense
let economicBudget = (totalProduction * 40) div 100     # 40% for growth
let scoutBudget = (totalProduction * 10) div 100        # 10% for recon
```

**Personality Influence:**
- High `aggression` → More military budget
- High `economicFocus` → More infrastructure budget
- High `expansionDrive` → More ETAC budget
- High `techPriority` → More research facility budget

---

## Decision Flow

### Order Generation Pipeline

```nim
proc generateAIOrders*(controller: var AIController, filtered: FilteredGameState,
                      rng: var Rand): OrderPacket =
  # 1. Strategic planning
  controller.updateOperationStatus(filtered)
  if filtered.turn mod 5 == 0:
    controller.updateFallbackRoutes(filtered)
  controller.manageStrategicReserves(filtered)

  # 2. Identify invasion opportunities
  if personality.aggression >= 0.4 and countAvailableFleets >= 2:
    let opportunities = controller.identifyInvasionOpportunities(filtered)
    if opportunities.len > 0:
      controller.planCoordinatedInvasion(filtered, opportunities[0], filtered.turn)

  # 3. Generate orders
  result = OrderPacket(
    houseId: controller.houseId,
    turn: filtered.turn,
    fleetOrders: generateFleetOrders(controller, filtered, rng),
    buildOrders: generateBuildOrders(controller, filtered, rng),
    researchAllocation: generateResearchAllocation(controller, filtered),
    diplomaticActions: generateDiplomaticActions(controller, filtered, rng),
    espionageAction: generateEspionageAction(controller, filtered, rng),
    # ... other orders
  )
```

### Fleet Order Generation (Example)

```nim
proc generateFleetOrders(controller: var AIController, filtered: FilteredGameState,
                        rng: var Rand): seq[FleetOrder] =
  for fleet in filtered.ownFleets:
    # 1. Check for active operations
    if isPartOfOperation(controller, fleet.id):
      # Execute coordinated operation
      continue

    # 2. Assess current situation
    let combat = assessCombatSituation(controller, filtered, fleet.location)

    # 3. Retreat if losing
    if combat.combatOdds < 0.3:
      let fallback = controller.findFallbackSystem(fleet.location)
      if fallback.isSome:
        result.add(createMoveOrder(fleet.id, fallback.get()))
        continue

    # 4. Attack if winning
    if combat.recommendAttack:
      result.add(createAttackOrder(fleet.id, combat.targetSystem))
      continue

    # 5. Default: scout or patrol
    let target = findReconnaissanceTarget(controller, filtered, fleet.location)
    if target.isSome:
      result.add(createMoveOrder(fleet.id, target.get()))
```

---

## Design Patterns

### 1. Circular Import Resolution

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

### 2. Helper Function Consolidation

**Problem:** `isSystemColonized()`, `getColony()`, `getFleetStrength()` were duplicated in 3 modules.

**Solution:** Keep in one canonical location, cross-import:

```nim
# intelligence.nim - canonical location
proc isSystemColonized*(filtered: FilteredGameState, systemId: SystemId): bool
proc getColony*(filtered: FilteredGameState, systemId: SystemId): Option[Colony]

# diplomacy.nim - canonical location for military helpers
proc getFleetStrength*(fleet: Fleet): int

# tactical.nim - imports from intelligence
import ./intelligence
if isSystemColonized(filtered, systemId): ...

# strategic.nim - imports from both
import ./intelligence
import ./diplomacy
let strength = getFleetStrength(fleet)
```

### 3. Fog-of-War Enforcement

**Pattern:** All AI functions accept `FilteredGameState`, never `GameState`.

```nim
# ❌ BAD - Would allow omniscient AI
proc assessCombat(controller: AIController, state: GameState, ...) = ...

# ✅ GOOD - Enforces fog-of-war
proc assessCombat(controller: AIController, filtered: FilteredGameState, ...) = ...
```

**Type Safety:** Compiler prevents accidental use of full game state.

---

## Module Dependencies

```
player.nim
  └── controller.nim
  └── controller_types.nim
  └── intelligence.nim
  └── diplomacy.nim
  └── tactical.nim
      └── intelligence.nim (for isSystemColonized)
  └── strategic.nim
      └── intelligence.nim (for isSystemColonized, getColony)
      └── diplomacy.nim (for getFleetStrength)
  └── budget.nim

Common imports: ../common/types, ../../engine/[gamestate, fog_of_war, orders, ...]
```

**No circular dependencies:** controller_types.nim breaks all cycles.

---

## Testing Strategy

### Unit Testing (Planned)

```nim
# Mock FilteredGameState for isolated tests
let mockView = FilteredGameState(
  viewingHouse: "house-test",
  ownColonies: @[testColony],
  ownFleets: @[testFleet],
  visibleSystems: initTable[SystemId, VisibleSystem]()
)

# Test intelligence module
suite "Intelligence":
  test "Reconnaissance needs detection":
    let controller = newAIController("house-test", AIStrategy.Balanced)
    assert needsReconnaissance(mockView, "system-unknown")
    assert not needsReconnaissance(mockView, "system-owned")
```

### Integration Testing (Current)

```bash
nimble testBalanceQuick    # 20 games, 7 turns
nimble testBalanceAct1     # 100 games, Act 1
nimble testBalanceAll4Acts # 400 games, full progression
```

### AI Optimization (Genetic Algorithms)

```bash
nimble evolveAI           # 50 generations, find optimal personalities
nimble coevolveAI         # 4-species competitive evolution
```

---

## Performance Characteristics

**Compilation:**
- Modular design: Fast incremental compilation (~2-3s per module)
- Monolith design: Slow full recompilation (~10s for 3,679 lines)

**Runtime:**
- Decision generation: ~1-5ms per AI per turn (depends on game size)
- Bottleneck: Game engine resolution (~50-100ms per turn)

**Memory:**
- Each AIController: ~1-2KB (small state)
- Intelligence reports: ~100 bytes per system
- Total AI memory: <1MB for 12 players

---

## Future Extensions

### Planned Enhancements

1. **Machine Learning Integration**
   - Train NNA (Neural Network Advisor) using RBA training data
   - Hybrid approach: RBA for known situations, NNA for novel scenarios

2. **Adaptive Personalities**
   - AI learns from player behavior
   - Adjusts personality mid-game based on success/failure

3. **Meta-Game Awareness**
   - Track player tendencies across games
   - Counter-strategy development

4. **Communication System**
   - Negotiation protocols
   - Coordinated multi-AI strategies (team games)

### Extension Points

**New Modules:**
```nim
src/ai/rba/
├── espionage.nim      # Dedicated espionage planning
├── research.nim       # Tech tree optimization
├── trade.nim          # Economic diplomacy
└── meta_strategy.nim  # Long-term planning
```

**Plugin Architecture:**
```nim
type AIModule* = object
  name*: string
  priority*: int
  evaluate*: proc(controller: AIController, filtered: FilteredGameState): Decision
```

---

## See Also

- [README.md](README.md) - AI documentation overview
- [DECISION_FRAMEWORK.md](DECISION_FRAMEWORK.md) - Decision-making details
- [PERSONALITIES.md](PERSONALITIES.md) - Strategy archetypes
- `../../src/ai/rba/` - Implementation source code
- `../testing/BALANCE_METHODOLOGY.md` - Testing approach
