# EC4X Rule-Based AI (RBA) Quick-Start Guide

This guide covers the essential patterns for working with the EC4X Rule-Based AI system for balance testing and AI opponent development.

## Table of Contents
1. [Core Concepts](#core-concepts)
2. [Module Architecture](#module-architecture)
3. [AI Personalities](#ai-personalities)
4. [Balance Testing Workflow](#balance-testing-workflow)
5. [Extending the RBA](#extending-the-rba)
6. [Common Patterns](#common-patterns)

## Core Concepts

### What is the RBA?

The **Rule-Based Advisor (RBA)** is a modular AI system that:
- Provides 12 distinct AI personalities for balance testing
- Uses personality-driven decision weighting (aggression, economic, expansion, tech, diplomacy, risk)
- Generates complete order sets for AI-controlled houses
- Serves as baseline opponent and training data generator for neural network AI

**Location:** `src/ai/rba/` (8 specialized modules)

**Not to be confused with:** `tests/balance/ai_controller.nim` (thin wrapper for testing)

### RBA vs Neural Network AI

```
┌────────────────────────────────────────────────────────┐
│ Rule-Based AI (RBA)                                    │
│ • Written in Nim                                       │
│ • 12 fixed personalities                              │
│ • Deterministic, debuggable                           │
│ • Used for balance testing                            │
│ • Bootstrap data for NN training                      │
└──────────────────┬─────────────────────────────────────┘
                   │
                   ▼
┌────────────────────────────────────────────────────────┐
│ Neural Network AI (Future)                            │
│ • AlphaZero-style self-play                           │
│ • Trained on RBA games                                │
│ • Superior strategic play                             │
│ • ONNX inference (Nim + Python)                       │
└────────────────────────────────────────────────────────┘
```

### 4-Act Game Structure

EC4X games follow a 4-act structure for balance testing:

| Act | Name | Duration | Focus | Key Mechanics |
|-----|------|----------|-------|---------------|
| 1 | Land Grab | 7 turns | Colony expansion | Colonization, scout reconnaissance |
| 2 | Rising Tensions | 15 turns | Tech & economy | Research, facility construction, early skirmishes |
| 3 | Total War | 25 turns | Military conflict | 3-phase combat, fleet logistics, fighter capacity |
| 4 | Endgame | 30 turns | Victory conditions | Prestige racing, final assaults, diplomatic pivots |

**Balance Target:** All strategies should achieve 20-40% win rate across all acts.

## Module Architecture

### 8 Specialized Modules

```
src/ai/rba/
├── player.nim                   # Public API entry point
├── controller.nim               # Strategy definitions & personality weights
├── controller_types.nim         # Type definitions (circular import resolution)
├── config.nim                   # RBA configuration loading
├── intelligence.nim             # Reconnaissance & intel gathering
├── diplomacy.nim                # Strength assessment & diplomatic decisions
├── tactical.nim                 # Fleet coordination & tactical operations
├── strategic.nim                # Combat assessment & invasion planning
├── budget.nim                   # Multi-objective resource allocation
├── logistics.nim                # Fleet/squadron management
├── orders.nim                   # Order generation
├── economic.nim                 # Economic decisions
├── espionage.nim                # Espionage operations
├── standing_orders_manager.nim  # Standing order persistence
└── shared/                      # Shared utilities
    ├── types.nim
    └── utils.nim
```

### Data-Oriented Design Pattern

The RBA follows a **pure-function, data-oriented** approach:

```nim
# GOOD: Pure function - calculates threat, returns data
proc assessColonyThreat(state: GameState, colony: Colony,
                        personality: Personality): ThreatAssessment =
  # No mutations, no side effects
  result = ThreatAssessment(
    level: calculateThreatLevel(state, colony),
    sources: identifyThreats(state, colony),
    recommendation: decideCourse(personality, ...)
  )

# GOOD: Controller calls pure functions, accumulates results
proc generateOrders(state: GameState, houseId: HouseId): seq[FleetOrder] =
  let threats = intelligence.scanForThreats(state, houseId)
  let targets = strategic.selectTargets(state, houseId, threats)
  let allocations = budget.allocateResources(state, houseId, targets)
  result = orders.buildOrderSet(state, houseId, allocations)
```

**Benefits:**
- Testable: All functions can be unit tested
- Debuggable: No hidden state mutations
- Composable: Functions combine naturally
- Deterministic: Same input → same output

### Module Responsibilities

**intelligence.nim** - Information gathering
```nim
proc scanForThreats*(state: GameState, houseId: HouseId): seq[ThreatReport]
proc assessStrengthDifference*(state: GameState, ourHouse, theirHouse: HouseId): float
proc identifyWeakTargets*(state: GameState, houseId: HouseId): seq[SystemId]
```

**strategic.nim** - High-level planning
```nim
proc selectInvasionTargets*(state: GameState, houseId: HouseId,
                            personality: Personality): seq[InvasionPlan]
proc assessCombatReadiness*(state: GameState, houseId: HouseId): CombatAssessment
```

**tactical.nim** - Fleet operations
```nim
proc coordinateFleets*(state: GameState, houseId: HouseId,
                       targets: seq[InvasionPlan]): seq[FleetOrder]
proc organizeScouts*(state: GameState, houseId: HouseId): seq[FleetOrder]
```

**budget.nim** - Resource allocation
```nim
proc allocatePP*(state: GameState, houseId: HouseId,
                 personality: Personality): BudgetAllocation
proc prioritizeConstruction*(personality: Personality,
                             needs: seq[ConstructionNeed]): seq[BuildOrder]
```

**orders.nim** - Order generation
```nim
proc buildFleetOrders*(state: GameState, houseId: HouseId,
                       plans: seq[TacticalPlan]): seq[FleetOrder]
proc buildEconomicOrders*(state: GameState, houseId: HouseId,
                          budget: BudgetAllocation): seq[ColonyOrder]
```

## AI Personalities

### Personality System

Each AI personality is defined by 6 weights (0.0-1.0):

```nim
type PersonalityWeights* = object
  aggression*: float    # Military focus, attack timing
  economic*: float      # Production, research investment
  expansion*: float     # Colonization priority
  tech*: float          # Research allocation
  diplomacy*: float     # Alliance seeking, treaty adherence
  risk*: float          # Bold moves vs cautious play
```

### 12 Built-In Personalities

| Strategy | Aggression | Economic | Expansion | Tech | Diplomacy | Risk | Playstyle |
|----------|-----------|----------|-----------|------|-----------|------|-----------|
| **Aggressive** | 0.9 | 0.2 | 0.7 | 0.3 | 0.1 | 0.8 | Early military rush |
| **Economic** | 0.2 | 0.9 | 0.6 | 0.7 | 0.5 | 0.3 | Build empire economy |
| **Espionage** | 0.3 | 0.6 | 0.4 | 0.8 | 0.4 | 0.7 | Intel & sabotage |
| **Diplomatic** | 0.2 | 0.6 | 0.5 | 0.5 | 0.9 | 0.4 | Alliance builder |
| **Balanced** | 0.5 | 0.5 | 0.5 | 0.5 | 0.5 | 0.5 | Jack-of-all-trades |
| **Turtle** | 0.1 | 0.7 | 0.3 | 0.6 | 0.6 | 0.2 | Defensive play |
| **Expansionist** | 0.4 | 0.5 | 0.9 | 0.4 | 0.3 | 0.6 | Colony sprawl |
| **TechRush** | 0.2 | 0.7 | 0.4 | 0.9 | 0.5 | 0.4 | Science advantage |
| **Raider** | 0.7 | 0.3 | 0.5 | 0.4 | 0.2 | 0.8 | Hit-and-run tactics |
| **MilitaryIndustrial** | 0.6 | 0.7 | 0.6 | 0.5 | 0.3 | 0.5 | War economy |
| **Opportunistic** | 0.5 | 0.6 | 0.6 | 0.6 | 0.4 | 0.7 | Adaptive play |
| **Isolationist** | 0.3 | 0.8 | 0.4 | 0.7 | 0.1 | 0.3 | Solo development |

### Using Personalities in Code

```nim
import src/ai/rba/controller

# Get personality for AI player
let personality = getPersonality(Balanced)

# Use personality to weight decisions
if personality.weights.aggression > 0.7:
  # Prioritize military orders
  orders.add(buildCombatFleet(...))
else:
  # Focus on economy
  orders.add(buildColony(...))

# Weight-based priority calculation
let attackPriority = personality.weights.aggression * threatLevel
let economicPriority = personality.weights.economic * growthPotential
```

### Creating Custom Personalities

```nim
# Define new personality weights
let customWeights = PersonalityWeights(
  aggression: 0.8,
  economic: 0.4,
  expansion: 0.6,
  tech: 0.5,
  diplomacy: 0.2,
  risk: 0.9
)

# Register personality
registerPersonality("CustomRush", customWeights,
                    "High-risk early game aggressor")
```

## Balance Testing Workflow

### Nimble Task Workflow

**ALWAYS use nimble tasks** to ensure build/test alignment:

```bash
# Quick validation during development (7 turns, 20 games, ~10 seconds)
nimble testBalanceQuick

# 4-act structure testing (100 games each)
nimble testBalanceAct1    # Act 1: Land Grab (7 turns)
nimble testBalanceAct2    # Act 2: Rising Tensions (15 turns)
nimble testBalanceAct3    # Act 3: Total War (25 turns)
nimble testBalanceAct4    # Act 4: Endgame (30 turns)

# Test all 4 acts in sequence (400 games total, ~15 minutes)
nimble testBalanceAll4Acts

# Diagnostic tests with CSV output (50 games, 30 turns)
nimble testBalanceDiagnostics

# AI behavior stress test (1000 games, edge case detection)
nimble testStressAI
```

### Why Nimble Tasks Matter

The nimble task workflow ensures:
- ✅ **No Stale Binaries:** Uses `--forceBuild` flag - ALWAYS full recompilation
- ✅ **Git Hash Tracking:** Records git hash to `.build_git_hash` for traceability
- ✅ **Build Alignment:** Source code → Binary always in sync
- ✅ **Regression Safety:** Binary matches current code, not old cached version

**Git hash verification:**
```bash
# Check build hash
cat tests/balance/.build_git_hash

# Compare to current commit
git rev-parse --short HEAD

# Should match!
```

### Test Output Structure

**JSON Snapshots** (`balance_results/*.json`):
```json
{
  "metadata": {
    "testId": "4act_balanced_20250127_143022",
    "act": 1,
    "turns": 7,
    "houses": 4,
    "strategies": ["Aggressive", "Economic", "Balanced", "Turtle"]
  },
  "turns": [
    {
      "turn": 1,
      "houses": {
        "House1": {
          "prestige": 100,
          "treasury": 500,
          "fleetStrength": 150,
          "colonyCount": 3
        }
      }
    }
  ],
  "outcome": {
    "victor": "House2",
    "victoryType": "prestige",
    "victoryTurn": 7
  }
}
```

**CSV Diagnostics** (`diagnostics/*.csv`):
```csv
turn,house,prestige,treasury,gcv,ncv,fleets,colonies,tech_avg
1,House1,100,500,120,80,2,3,1.0
1,House2,100,480,115,75,2,3,1.0
...
```

### Analyzing Results

**Python analysis scripts:**
```bash
# Analyze fleet composition across games
python3 tests/balance/analyze_fleet_composition.py

# Comprehensive test suite with auto-analysis
python3 tests/balance/run_comprehensive_tests.py --workers 8

# Test all acts across map sizes
python3 tests/balance/test_all_acts_all_sizes.py
```

**Terminal-based analysis** (NEW):
```bash
# Interactive data explorer for RBA tuning
nimble balanceSummary

# Navigate results with arrow keys
# Filter by strategy, act, outcome
# Export focused datasets for deeper analysis
```

## Extending the RBA

### Adding a New Strategy Module

**1. Create module file:** `src/ai/rba/new_module.nim`

```nim
## New Strategy Module
## Handles [specific domain] decisions

import std/[tables, sequtils, options]
import ../../engine/gamestate
import controller_types

proc analyzeNewDomain*(state: GameState, houseId: HouseId,
                       personality: Personality): DomainAnalysis =
  ## Pure function - analyze domain, return data
  result = DomainAnalysis(
    priority: calculatePriority(state, personality),
    actions: identifyActions(state, houseId)
  )

proc selectNewAction*(state: GameState, houseId: HouseId,
                      analysis: DomainAnalysis): Option[Action] =
  ## Pure function - select best action from analysis
  if analysis.priority > 0.5:
    return some(analysis.actions[0])
  return none(Action)
```

**2. Integrate into controller:** `src/ai/rba/controller.nim`

```nim
import new_module

proc generateOrders*(state: GameState, houseId: HouseId): seq[FleetOrder] =
  let personality = getPersonality(houseId)

  # Call new module
  let newAnalysis = new_module.analyzeNewDomain(state, houseId, personality)
  let newAction = new_module.selectNewAction(state, houseId, newAnalysis)

  if newAction.isSome:
    result.add(convertToOrder(newAction.get()))
```

**3. Add tests:** `tests/rba/test_new_module.nim`

```nim
import unittest
import src/ai/rba/new_module

suite "New Module Tests":
  test "analyzeNewDomain returns valid analysis":
    let state = createTestState()
    let analysis = analyzeNewDomain(state, 0, Balanced.weights)

    check analysis.priority >= 0.0
    check analysis.priority <= 1.0
    check analysis.actions.len > 0
```

### Adding a New Personality

**1. Define weights:** `src/ai/rba/controller.nim`

```nim
proc getPersonality*(strategy: AIStrategy): Personality =
  case strategy
  # ... existing personalities ...
  of AIStrategy.YourNewStrategy:
    result = Personality(
      name: "YourNewStrategy",
      description: "Description of playstyle",
      weights: PersonalityWeights(
        aggression: 0.7,
        economic: 0.5,
        expansion: 0.6,
        tech: 0.6,
        diplomacy: 0.3,
        risk: 0.8
      )
    )
```

**2. Add to strategy enum:** `src/ai/rba/controller_types.nim`

```nim
type AIStrategy* = enum
  Aggressive
  Economic
  # ... existing strategies ...
  YourNewStrategy  # Add here
```

**3. Test in balance suite:**

```bash
# Edit tests/balance/run_simulation.nim
# Add YourNewStrategy to test configurations

# Run validation
nimble testBalanceQuick
```

## Common Patterns

### 1. Personality-Weighted Decisions

```nim
proc selectColonizationTarget(state: GameState, houseId: HouseId,
                               personality: Personality): Option[SystemId] =
  let candidates = findUncolonizedSystems(state)

  var bestScore = 0.0
  var bestTarget: Option[SystemId] = none(SystemId)

  for systemId in candidates:
    let system = state.starMap.systems[systemId]

    # Weight score by personality
    let economicValue = system.habitability * personality.weights.economic
    let strategicValue = system.proximity * personality.weights.aggression
    let expansionBonus = 1.0 * personality.weights.expansion

    let totalScore = economicValue + strategicValue + expansionBonus

    if totalScore > bestScore:
      bestScore = totalScore
      bestTarget = some(systemId)

  return bestTarget
```

### 2. Threat Assessment Pattern

```nim
proc assessThreatLevel(state: GameState, houseId: HouseId,
                       enemyFleet: Fleet): ThreatLevel =
  let ourStrength = calculateFleetStrength(state, houseId)
  let theirStrength = enemyFleet.combatStrength()
  let ratio = theirStrength / ourStrength

  if ratio > 2.0:
    return ThreatLevel.Critical
  elif ratio > 1.5:
    return ThreatLevel.High
  elif ratio > 1.0:
    return ThreatLevel.Moderate
  else:
    return ThreatLevel.Low
```

### 3. Multi-Objective Priority Calculation

```nim
proc prioritizeActions(state: GameState, houseId: HouseId,
                       personality: Personality): seq[Action] =
  var actions: seq[tuple[action: Action, priority: float]] = @[]

  # Collect candidate actions with scores
  for candidate in allPossibleActions(state, houseId):
    let priority = calculatePriority(candidate, personality)
    actions.add((candidate, priority))

  # Sort by priority (descending)
  actions.sort do (a, b: auto) -> int:
    cmp(b.priority, a.priority)

  # Return sorted actions
  return actions.mapIt(it.action)

proc calculatePriority(action: Action, personality: Personality): float =
  # Weighted sum based on personality
  result = 0.0
  result += action.militaryValue * personality.weights.aggression
  result += action.economicValue * personality.weights.economic
  result += action.diplomaticValue * personality.weights.diplomacy
  result += action.riskLevel * personality.weights.risk
```

### 4. Resource Budget Allocation

```nim
proc allocateBudget(state: GameState, houseId: HouseId,
                    personality: Personality): BudgetAllocation =
  let house = state.houses[houseId]
  let totalPP = house.treasury

  # Calculate allocation percentages from personality
  let militaryPct = personality.weights.aggression * 0.4
  let economicPct = personality.weights.economic * 0.4
  let techPct = personality.weights.tech * 0.2

  # Normalize to 1.0
  let total = militaryPct + economicPct + techPct
  let militaryBudget = (militaryPct / total) * totalPP
  let economicBudget = (economicPct / total) * totalPP
  let techBudget = (techPct / total) * totalPP

  result = BudgetAllocation(
    military: militaryBudget.int,
    economic: economicBudget.int,
    technology: techBudget.int
  )
```

### 5. State Query Helpers

```nim
# Get all colonies owned by house
proc getOwnedColonies(state: GameState, houseId: HouseId): seq[Colony] =
  result = @[]
  for colony in state.colonies.values:
    if colony.owner == houseId:
      result.add(colony)

# Get all fleets owned by house
proc getOwnedFleets(state: GameState, houseId: HouseId): seq[Fleet] =
  result = @[]
  for fleet in state.fleets.values:
    if fleet.owner == houseId:
      result.add(fleet)

# Calculate total military strength
proc getTotalMilitaryStrength(state: GameState, houseId: HouseId): int =
  result = 0
  for fleet in getOwnedFleets(state, houseId):
    result += fleet.combatStrength()
```

## Performance Considerations

### Optimization Patterns

**1. Cache expensive calculations:**
```nim
type AICache = object
  threatAssessments: Table[HouseId, ThreatAssessment]
  strengthRatios: Table[HouseId, float]
  lastUpdate: int

proc getOrCalculate(cache: var AICache, state: GameState,
                    houseId: HouseId): ThreatAssessment =
  if cache.lastUpdate == state.turn and houseId in cache.threatAssessments:
    return cache.threatAssessments[houseId]

  # Calculate fresh
  let assessment = calculateThreatAssessment(state, houseId)
  cache.threatAssessments[houseId] = assessment
  cache.lastUpdate = state.turn
  return assessment
```

**2. Batch process operations:**
```nim
# GOOD: Process all colonies once
let allColonies = getOwnedColonies(state, houseId)
for colony in allColonies:
  processColony(colony, state)

# BAD: Repeated table lookups
for systemId in systemIds:
  let colony = state.colonies[systemId]  # O(n) lookups
  processColony(colony, state)
```

**3. Early exit for expensive checks:**
```nim
proc shouldInvade(state: GameState, target: SystemId,
                  personality: Personality): bool =
  # Fast checks first
  if personality.weights.aggression < 0.5:
    return false  # Not aggressive enough

  # Expensive checks only if needed
  let strengthRatio = calculateStrengthRatio(state, target)
  return strengthRatio > 1.5
```

## Debugging RBA Behavior

### Logging Patterns

```nim
import ../../common/logger

# Log decisions with context
logDebug("RBA", "Selecting colonization target",
         "house=", houseId, " candidates=", candidates.len,
         " personality=", personality.name)

# Log priority calculations
logDebug("RBA", "Action priority calculated",
         "action=", action.kind, " priority=", $priority,
         "mil=", $militaryComponent, " eco=", $economicComponent)

# Log final orders
logInfo("RBA", "Generated orders",
        "house=", houseId, " count=", orders.len,
        "types=", orders.mapIt($it.kind).join(","))
```

### Test-Driven Development

```nim
# tests/rba/test_intelligence.nim
suite "Intelligence Module":
  test "scanForThreats detects nearby enemy fleets":
    let state = createTestState()
    addEnemyFleet(state, systemId = 10, strength = 100)

    let threats = intelligence.scanForThreats(state, houseId = 0)

    check threats.len == 1
    check threats[0].location == 10
    check threats[0].strength == 100
```

## Next Steps

1. **Read:** [RBA Config Reference](RBA_CONFIG_REFERENCE.md) for personality tuning
2. **Explore:** [ENGINE_QUICKSTART.md](ENGINE_QUICKSTART.md) for engine integration patterns
3. **Run:** `nimble testBalanceQuick` to validate RBA functionality
4. **Experiment:** Modify personality weights and observe behavior changes
5. **Extend:** Add custom strategies for specialized testing scenarios

## See Also

- **[RBA Config Reference](RBA_CONFIG_REFERENCE.md)** - Personality weights and tuning
- **[Analytics CLI](ANALYTICS_CLI.md)** - Balance data analysis tools
- **[Architecture Docs](../architecture/ai-system.md)** - Complete AI system design
- **[Balance Testing](../../tests/balance/README.md)** - Testing framework details
