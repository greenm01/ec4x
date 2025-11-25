# EC4X AI Strategic Decision-Making Framework

**Created:** 2025-11-25
**Purpose:** Strategic framework for AI decision-making based on 4X game research and academic papers

## Overview

This document synthesizes research on 4X game AI algorithms, classic 4X game progression patterns, and multi-objective optimization to create a strategic framework for EC4X AI decision-making.

---

## Research Foundation

### Academic Sources

1. **[Designing AI Algorithms For Turn-Based Strategy Games](https://www.gamedeveloper.com/design/designing-ai-algorithms-for-turn-based-strategy-games)** - Priority-based task assignment framework
2. **[RTS AI Problems and Techniques](https://www.researchgate.net/publication/311176051_RTS_AI_Problems_and_Techniques)** - Comprehensive RTS AI survey
3. **[The Real-Time Strategy Game Multi-Objective Build Order Problem](https://cdn.aaai.org/ojs/12720/12720-52-16237-1-2-20201228.pdf)** - MOEA approach to build order optimization
4. **[AI for global decision-making in 4X games](https://gamedev.stackexchange.com/questions/206216/ai-for-global-decision-making-in-4x-games)** - Community discussion on 4X AI approaches
5. **[Stellaris AI modding](https://stellaris.fandom.com/wiki/AI_modding)** - Weight-based decision system in production 4X game

### Key AI Techniques

**Rule Engines** - IF/THEN conditions for basic logic
**Goal-Oriented Action Planning (GOAP)** - Backward chaining from desired state
**Utility AI** - Scoring system for situation evaluation
**Weight-Based Systems** - Parameterized decision-making (Stellaris approach)
**Multi-Objective Evolutionary Algorithms (MOEA)** - Balancing competing objectives

---

## Classic 4X Game Progression Patterns

### The Universal 4-Act Structure

Analysis of classic 4X games (Civilization, Master of Orion, Stellaris, Galactic Civilizations) reveals consistent progression:

#### Act 1: Land Grab (Early Game)
**Strategic Focus:** Expansion >> Military
**AI Behavior:**
- Rapid colony acquisition
- Economic foundation building
- Minimal military (defensive only)
- Scout-heavy intel gathering
- Peaceful coexistence (no territory conflicts yet)

**Resource Allocation:**
- 70-80% expansion (ETACs, colony infrastructure)
- 10-20% military (minimal defensive forces)
- 10% intelligence (exploration)

#### Act 2: Rising Tensions (Mid-Game)
**Strategic Focus:** Military Buildup + Consolidation
**AI Behavior:**
- Expansion slows (map filling up)
- **CRITICAL TRANSITION:** Shift from colonization to military production
- First territorial conflicts
- Tech race begins
- Defensive positioning

**Resource Allocation:**
- 30-40% expansion (opportunistic only)
- 50-60% military buildup
- 10% technology investment

**Phase Transition Triggers:**
- Map colonization > 50%
- Direct contact with enemy colonies
- Treasury accumulation (can afford military)
- Base economy established (maintenance sustainable)

#### Act 3: Total War (Late Game)
**Strategic Focus:** Conquest + Elimination
**AI Behavior:**
- Zero new colonization (conquest replaces expansion)
- Maximum military production
- Invasion fleets deployed
- Tech advantages decisive
- Clear winners/losers emerge

**Resource Allocation:**
- 0-10% expansion (only conquest)
- 80-90% military + invasions
- 10% tech (maintaining advantages)

#### Act 4: Endgame
**Strategic Focus:** Victory Push or Survival
**AI Behavior:**
- All-in strategies
- Desperate alliances or last betrayals
- Final confrontations

---

## Priority System Framework

### Inspiration: Priority-Based Task Assignment

From [Designing AI Algorithms For Turn-Based Strategy Games](https://www.gamedeveloper.com/design/designing-ai-algorithms-for-turn-based-strategy-games):

**Six Priority Tiers (Highest to Lowest):**
1. Defending colonies with production
2. Defending colonies without production
3. Attacking enemy home planets
4. Colonizing habitable planets
5. Attacking enemy ships
6. Exploring uncharted territory

**Scoring Formula:**
```
assignment_score = (6 - priority_tier + modifier) / distance_to_asset
```

**Key Insight:** Priorities aren't static - they're **context-dependent modifiers** applied to a distance-weighted scoring system.

### Adaptation to EC4X

**EC4X requires PHASE-AWARE priorities** that change based on game act:

#### Act 1 Priorities (Land Grab)
```
1. Colonizing habitable systems (HIGH)
2. Building ETACs for expansion (HIGH)
3. Defending existing colonies (MEDIUM)
4. Exploring uncharted territory (MEDIUM)
5. Building minimal military (LOW)
6. Attacking enemies (VERY LOW - avoid conflict)
```

#### Act 2 Priorities (Rising Tensions)
```
1. Defending threatened colonies (HIGH)
2. Building military forces (HIGH)
3. Colonizing remaining systems (MEDIUM)
4. First strike opportunities (MEDIUM)
5. Intelligence gathering (MEDIUM)
6. Building more ETACs (LOW - map filling)
```

#### Act 3 Priorities (Total War)
```
1. Defending home colonies (CRITICAL)
2. Invasion operations (HIGH)
3. Attacking enemy fleets (HIGH)
4. Building transports + military (HIGH)
5. Tech research for advantages (MEDIUM)
6. Colonization (NONE - conquest only)
```

---

## Multi-Objective Build Order Optimization

### Inspiration: MOEA for StarCraft

From [The Real-Time Strategy Game Multi-Objective Build Order Problem](https://cdn.aaai.org/ojs/12720/12720-52-16237-1-2-20201228.pdf):

**Key Concept:** Build orders must balance **competing objectives**:
- Military strength (immediate defense)
- Economic growth (long-term power)
- Tech advancement (strategic advantage)
- Unit diversity (tactical flexibility)

**MOEA Approach:** Use NSGA-II to generate Pareto-optimal build sequences

### EC4X Build Order Problem

**Current Issue:** AI builds in **sequential priority order**:
1. Infrastructure → 2. ETACs → 3. Frigates → 4. Scouts → 5. Fighters → 6. Military

This creates **resource starvation** - earlier priorities consume all treasury before later priorities execute.

**Multi-Objective Solution:**

Instead of strict sequential priority, use **budget allocation across objectives**:

```nim
# Pseudocode for multi-objective build allocation
type BuildObjective = enum
  Expansion,      # ETACs, colony infrastructure
  Defense,        # Starbases, ground batteries
  Military,       # Frigates, cruisers, dreadnoughts
  Intelligence,   # Scouts
  SpecialUnits,   # Fighters, carriers, raiders
  Technology      # Research investment

proc allocateBudget(house: House, act: GameAct, personality: AIPersonality): Table[BuildObjective, float] =
  ## Allocate treasury percentage to each objective based on game phase

  case act
  of Act1_LandGrab:
    result = {
      Expansion: 0.60,      # 60% to colonization
      Defense: 0.10,        # 10% to minimal defense
      Military: 0.10,       # 10% to basic military
      Intelligence: 0.15,   # 15% to scouts
      SpecialUnits: 0.05,   # 5% to fighters (if aggressive)
      Technology: 0.00      # No research yet
    }.toTable()

  of Act2_RisingTensions:
    result = {
      Expansion: 0.25,      # 25% to opportunistic colonization
      Defense: 0.15,        # 15% to starbase network
      Military: 0.40,       # 40% to military buildup ← CRITICAL SHIFT
      Intelligence: 0.10,   # 10% to intel
      SpecialUnits: 0.05,   # 5% to carriers/fighters
      Technology: 0.05      # 5% to key techs
    }.toTable()

  of Act3_TotalWar:
    result = {
      Expansion: 0.00,      # 0% - conquest only
      Defense: 0.15,        # 15% to critical defenses
      Military: 0.60,       # 60% to invasion fleets
      Intelligence: 0.05,   # 5% to target intel
      SpecialUnits: 0.10,   # 10% to transports
      Technology: 0.10      # 10% to tech advantages
    }.toTable()

  # Adjust allocations based on personality
  if personality.aggression > 0.7:
    result[Military] += 0.15
    result[Expansion] -= 0.15

  if personality.economicFocus > 0.7:
    result[Expansion] += 0.10
    result[Military] -= 0.10

proc generateBuildOrders(house: House, filtered: FilteredGameState): seq[BuildOrder] =
  let act = determineGameAct(filtered.turn)
  let budget = allocateBudget(house, act, controller.personality)

  # Calculate actual PP available for each objective
  var budgetPP: Table[BuildObjective, int]
  for obj, percentage in budget:
    budgetPP[obj] = int(house.treasury * percentage)

  # Build from each budget allocation
  result.add(buildExpansionUnits(budgetPP[Expansion]))
  result.add(buildDefenseUnits(budgetPP[Defense]))
  result.add(buildMilitaryUnits(budgetPP[Military]))      # ← Gets dedicated budget!
  result.add(buildIntelligenceUnits(budgetPP[Intelligence]))
  result.add(buildSpecialUnits(budgetPP[SpecialUnits]))
```

**Key Advantage:** Military gets **guaranteed budget allocation** in Act 2+, preventing starvation by ETAC spam.

---

## Utility AI + GOAP Hybrid Approach

### Inspiration: Modern Game AI Architecture

From [GOAP and Utility AI in Grab n' Throw](https://goldensyrupgames.com/blog/2024-05-04-grab-n-throw-utility-goap-ai/):

**Hybrid Pattern:**
1. **Utility AI** decides "WHAT to do" (strategic goals)
2. **GOAP** decides "HOW to do it" (tactical execution)

### EC4X Application

**Current System:** Pure utility AI (scoring + immediate action)

**Hybrid Improvement:**

```nim
# Strategic layer (Utility AI)
proc selectStrategicGoal(filtered: FilteredGameState, personality: AIPersonality): StrategicGoal =
  ## Score potential strategic goals based on current situation

  var goalScores: Table[StrategicGoal, float]

  # Score: Expand empire
  goalScores[ExpandEmpire] =
    (availableSystems / totalSystems) * personality.expansionDrive * actModifier

  # Score: Build military
  goalScores[BuildMilitary] =
    (enemyStrength / myStrength) * (1.0 - militaryRatio) * personality.aggression

  # Score: Invade enemy
  goalScores[InvadeEnemy] =
    (myStrength / enemyStrength) * hasTransports * personality.aggression * actPhase

  # Score: Defend colonies
  goalScores[DefendColonies] =
    threatenedColonies * (1.0 - personality.riskTolerance)

  # Score: Tech research
  goalScores[ResearchTech] =
    techGap * personality.techPriority

  return highestScoring(goalScores)

# Tactical layer (GOAP-like planning)
proc planGoalExecution(goal: StrategicGoal, state: FilteredGameState): seq[BuildOrder] =
  ## Generate action sequence to achieve strategic goal

  case goal
  of ExpandEmpire:
    # Preconditions: Need ETAC, need target system, need funds
    if not hasIdleETAC():
      return [buildETAC()]
    else:
      return [colonizeSystem(findBestTarget())]

  of BuildMilitary:
    # Preconditions: Need shipyard, need funds, need capacity
    if not hasShipyard():
      return [buildShipyard()]
    elif atCapacityLimit():
      return [buildStarbase()]  # Increase squadron limit
    else:
      return [buildMilitaryShip(selectShipType())]

  of InvadeEnemy:
    # Preconditions: Need military superiority, need transports, need target
    if militaryCount < enemyStrength * 1.5:
      return [buildMilitary()]  # Build up first
    elif transportCount == 0:
      return [buildTransport()]
    else:
      return [launchInvasion(selectWeakestTarget())]
```

---

## Phase Transition Logic

### The Critical Transition: Act 1 → Act 2

**Current Problem:** AI never transitions from expansion to military mode

**Root Cause:** No explicit phase detection and priority rebalancing

### Proposed Solution: Explicit Phase Detection

```nim
proc determineGameAct(state: FilteredGameState): GameAct =
  ## Determine current game act based on multiple indicators

  let turn = state.turn
  let mapSaturation = colonizedSystems / totalSystems
  let hasEnemyContact = visibleEnemyColonies.len > 0
  let economyEstablished = totalProduction > 400  # Arbitrary threshold
  let militaryPresence = enemyMilitaryStrength > 0

  # Act transitions use multiple criteria, not just turn count
  if turn <= 7:
    return Act1_LandGrab

  elif turn <= 15:
    # Act 2 can start early if conditions met
    if mapSaturation > 0.5 or hasEnemyContact:
      return Act2_RisingTensions
    else:
      return Act1_LandGrab  # Still expanding

  elif turn <= 25:
    # Act 3 requires actual conflict
    if militaryPresence > 0 or mapSaturation > 0.8:
      return Act3_TotalWar
    else:
      return Act2_RisingTensions  # Still building up

  else:
    return Act4_Endgame

proc updatePriorities(currentAct: GameAct, previousAct: GameAct): void =
  ## When act changes, log transition and update priorities

  if currentAct != previousAct:
    logInfo(LogCategory.lcAI, &"PHASE TRANSITION: {previousAct} → {currentAct}")

    # Explicitly recalculate all priorities
    recalculateBuildPriorities(currentAct)
    recalculateFleetAssignments(currentAct)
    recalculateResearchFocus(currentAct)
```

**Key Insight:** Phase transitions must be **explicit events** that trigger priority recalculation, not implicit side-effects.

---

## Implementation Recommendations

### 1. Budget Allocation System (Immediate)

Replace sequential priority with budget-based allocation:
- Each build objective gets % of treasury
- Military guaranteed 40%+ in Act 2
- Prevents ETAC starvation of military

### 2. Phase-Aware Decision Making (Critical)

Add explicit act detection and transition logging:
- Detect act based on multiple criteria
- Log phase transitions clearly
- Recalculate priorities on transition

### 3. Hybrid Goal Selection (Future)

Separate strategic goal selection (utility AI) from tactical execution (GOAP):
- "Build military" is strategic decision
- "Build frigate vs cruiser" is tactical decision
- Cleaner separation of concerns

### 4. Diagnostic Validation (Essential)

After changes, validate with diagnostic metrics:
- Turn 7: 0.0 fighters → Target: 3-8 fighters
- Turn 15: 0 invasions → Target: 1-3 invasions attempted
- Phase transitions logged in diagnostics

---

## Sources

- [Designing AI Algorithms For Turn-Based Strategy Games](https://www.gamedeveloper.com/design/designing-ai-algorithms-for-turn-based-strategy-games)
- [RTS AI Problems and Techniques](https://www.researchgate.net/publication/311176051_RTS_AI_Problems_and_Techniques)
- [The Real-Time Strategy Game Multi-Objective Build Order Problem](https://cdn.aaai.org/ojs/12720/12720-52-16237-1-2-20201228.pdf)
- [A Multi-objective Genetic Algorithm for Build Order Optimization in StarCraft II](https://www.researchgate.net/publication/257799598_A_Multi-objective_Genetic_Algorithm_for_Build_Order_Optimization_in_StarCraft_II)
- [GOAP and Utility AI in Grab n' Throw](https://goldensyrupgames.com/blog/2024-05-04-grab-n-throw-utility-goap-ai/)
- [Stellaris AI modding](https://stellaris.fandom.com/wiki/AI_modding)
- [AI for global decision-making in 4X games](https://gamedev.stackexchange.com/questions/206216/ai-for-global-decision-making-in-4x-games)

---

**Next Steps:**
1. Implement budget allocation system in `ai_controller.nim`
2. Add explicit phase transition detection and logging
3. Run Act 2 validation tests (turn 15, 100 games)
4. Validate fighter/invasion metrics improve
