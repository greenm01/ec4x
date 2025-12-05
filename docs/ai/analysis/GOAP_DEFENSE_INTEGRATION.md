# GOAP + Act-Aware Defense Integration

**Date:** 2025-12-05
**Status:** Design Document - Shows how GOAP planning would enhance the Act-aware defense system

## Executive Summary

Your Act-aware defense system currently works through **pure RBA** (Domestikos → Treasurer → CFO). This document explains how **GOAP planning** would add a strategic layer on top, providing multi-turn planning, resource optimization, and precondition handling.

**Current System:** ✅ Tactical, reactive, per-turn decision-making
**With GOAP:** Strategic, proactive, multi-turn planning

## Architecture Comparison

### Current: Pure RBA (Phase 1.5) ✅ WORKING

```
┌─────────────┐
│ Domestikos  │  Per-colony threat assessment
└──────┬──────┘  Act-aware baseline targets (1→2→3 batteries)
       │         Intelligence-driven escalation (threat >0.5)
       ↓
┌─────────────┐
│ Requirements│  BuildRequirement(Defense, priority, cost, targetSystem)
└──────┬──────┘  Critical/High/Medium/Low priority
       │
       ↓
┌─────────────┐
│  Treasurer  │  Budget allocation: 100% tactical for Defense/Military
└──────┬──────┘  Proportional allocation based on requiredPP
       │
       ↓
┌─────────────┐
│     CFO     │  Build highest-priority orders within budget
└─────────────┘  THIS TURN ONLY (no lookahead)
```

**Strengths:**
- ✅ Fast, reactive decision-making
- ✅ Responsive to immediate threats
- ✅ Simple, deterministic behavior
- ✅ Economic sustainability (validated at 1197 PP avg treasury)

**Limitations:**
- ⚠️ No multi-turn planning (can't plan "build battery now, then army in 2 turns")
- ⚠️ Greedy allocation (may fund 10 colonies at 10% each instead of fully defending 3)
- ⚠️ No precondition planning (can't plan "build spaceport → then shipyard → then ships")
- ⚠️ Reactive only (waits for threat before acting, no proactive positioning)

### With GOAP: Strategic Planning + RBA Execution (Phase 2)

```
┌──────────────────────────────────────────────────────────────┐
│                    STRATEGIC LAYER (GOAP)                    │
└──────────────────────────────────────────────────────────────┘
                               ↓
┌─────────────┐
│ World State │  Analyze game state: threats, economy, intel
│  Snapshot   │  Create immutable planning state
└──────┬──────┘
       │
       ↓
┌─────────────┐
│ Goal        │  DefendColony(systemId, priority=0.9)
│ Generation  │  ConstructStarbase(systemId, priority=0.7)
└──────┬──────┘  BuildFleet(defensive_squadron, priority=0.6)
       │
       ↓
┌─────────────┐
│ A* Planner  │  Find optimal action sequence (multi-turn)
└──────┬──────┘  Consider preconditions, costs, effects
       │
       ↓
┌─────────────┐
│  GOAPlan    │  Turn 1: BuildBattery(SystemA, 50PP)
└──────┬──────┘  Turn 2: BuildBattery(SystemA, 50PP)
       │         Turn 3: BuildArmy(SystemA, 15PP)
       │         Total: 115PP, 3 turns, 85% confidence
       │
┌──────┴────────────────────────────────────────────────────────┐
│                     TACTICAL LAYER (RBA)                      │
└───────────────────────────────────────────────────────────────┘
       │
       ↓
┌─────────────┐
│ Domestikos  │  Convert GOAP plan actions → RBA requirements
└──────┬──────┘  Execute THIS TURN's actions from plan
       │
       ↓
┌─────────────┐
│  Treasurer  │  Allocate budget for THIS TURN's requirements
└──────┬──────┘  Ensure budget reserved for future plan turns
       │
       ↓
┌─────────────┐
│     CFO     │  Execute THIS TURN's orders
└─────────────┘  Track plan progress, trigger replanning if needed
```

**Advantages:**
- ✅ Multi-turn optimization (plan 3-5 turns ahead)
- ✅ Complete goals fully before starting new ones
- ✅ Precondition planning (spaceport → shipyard → ships)
- ✅ Proactive positioning (fortify before enemies arrive)
- ✅ Resource reservation (ensure future turns can execute plan)

**Trade-offs:**
- ⚠️ More complex (A* search, plan tracking, replanning)
- ⚠️ Less reactive (committed to plan for multiple turns)
- ⚠️ Plan invalidation (enemy moves may require replanning)

## Concrete Example: Border Defense

### Scenario

**Turn 5 State:**
- Treasury: 300 PP
- Income: 80 PP/turn
- Border Colony (System 7): 0 batteries, 0 armies
- Enemy Fleet: 3 systems away, moving toward border
- Act: Act 1 (Land Grab)

### Current RBA Behavior

**Turn 5 Decision:**
```nim
# Domestikos analyzes System 7
let threat = estimateLocalThreat(system7, filtered, controller)
# threat = 0.3 (enemy 3 systems away)

# Act 1 baseline: 1 battery
# Threat escalation: 0.3 > 0.2 → at least 2 batteries
let targetBatteries = max(1, 2) = 2

# Generate requirement
BuildRequirement(
  buildObjective: Defense,
  priority: High,  # threat >0.2
  estimatedCost: 100,  # 2 batteries @ 50 PP
  targetSystem: system7
)
```

**Treasurer Allocation:**
```nim
# Calculate requiredPP for Defense: 100 PP
# Available budget: 300 PP
# Allocate 100% tactical: Defense gets 33% (100/300)

# CFO executes highest-priority within budget
# Builds: 1 battery at System 7 (50 PP)
# Remaining: 250 PP for other objectives
```

**Result:**
- Turn 5: 1 battery built ✅
- Turn 6: Will request 1 more battery (total 2)
- Turn 7: Enemy arrives, defenses incomplete ⚠️

**Issue:** Greedy allocation split budget across multiple objectives instead of completing System 7's defenses.

### GOAP Behavior

**Turn 5 Planning:**

```nim
# 1. Create WorldStateSnapshot
let snapshot = WorldStateSnapshot(
  turn: 5,
  treasury: 300,
  production: 80,
  vulnerableColonies: @[system7],
  knownEnemyFleets: @[(fleetId: enemy_fleet_1, distance: 3)]
)

# 2. Generate strategic goal
let goal = Goal(
  goalType: DefendColony,
  priority: 0.9,  # High priority: enemy approaching
  target: some(system7),
  requiredResources: 100,  # 2 batteries needed
  deadline: some(7),  # Enemy arrives turn 8
  preconditions: @[
    controlsSystem(system7),
    hasMinBudget(100)
  ],
  successCondition: hasDefenses(system7, batteries=2)
)

# 3. A* Planner searches for action sequence
let plan = planActions(snapshot, goal, availableActions)

# Found plan:
GOAPlan(
  goal: goal,
  actions: @[
    Action(
      actionType: BuildFacility,
      cost: 50,
      duration: 1,
      target: system7,
      description: "Build Battery at System 7"
    ),
    Action(
      actionType: BuildFacility,
      cost: 50,
      duration: 1,
      target: system7,
      description: "Build Battery at System 7"
    )
  ],
  totalCost: 100,
  estimatedTurns: 2,
  confidence: 0.85,
  dependencies: @[]
)
```

**Turn 5 Execution:**
```nim
# Convert GOAP plan → RBA requirement for THIS TURN
BuildRequirement(
  buildObjective: Defense,
  priority: Critical,  # From GOAP goal priority=0.9
  estimatedCost: 50,  # Turn 1 of plan
  targetSystem: system7,
  planId: some(plan.id)  # Track plan execution
)

# Treasurer reserves budget for plan completion
# Turn 5: 50 PP allocated
# Turn 6: 50 PP reserved (ensure plan completion)

# CFO executes
# Builds: 1 battery at System 7 (50 PP)
# Marks plan progress: 50% complete
```

**Turn 6 Execution:**
```nim
# Continue executing plan (no replanning needed)
BuildRequirement(
  buildObjective: Defense,
  priority: Critical,
  estimatedCost: 50,  # Turn 2 of plan
  targetSystem: system7,
  planId: some(plan.id)
)

# Builds: 1 battery at System 7 (50 PP)
# Marks plan: 100% complete ✅
```

**Result:**
- Turn 5: 1 battery built ✅
- Turn 6: 1 battery built ✅
- Turn 7: Defenses complete (2 batteries), enemy arrives at defended colony ✅

**Advantage:** GOAP ensured goal completion by reserving budget for both turns, preventing budget fragmentation.

## Defense Planning Enhancements

### 1. Multi-Colony Optimization

**RBA Approach (Current):**
```nim
# Generate requirement per colony independently
for colony in filtered.ownColonies:
  if colony.batteries < targetBatteries:
    requirements.add(BuildRequirement(...))

# Treasurer allocates budget proportionally
# Result: 10 colonies each get 10% budget → none complete defenses
```

**GOAP Approach:**
```nim
# Generate goals for all vulnerable colonies
let goals = @[
  DefendColony(system7, priority=0.9),  # Border, high threat
  DefendColony(system3, priority=0.7),  # Interior, medium threat
  DefendColony(system5, priority=0.5)   # Core, low threat
]

# A* Planner prioritizes highest-value goals
let plan = planForMultipleGoals(snapshot, goals, budget=300)

# Plan: Complete System 7 defenses FIRST, then System 3
# Turn 1-2: Fully defend System 7 (100 PP)
# Turn 3-4: Fully defend System 3 (100 PP)
# Turn 5+:   Defend System 5 when budget allows

# Result: 2 colonies fully defended vs. 10 colonies partially defended
```

**Advantage:** Focus resources on highest-priority targets instead of spreading thin.

### 2. Precondition Planning

**Scenario:** Colony wants starbase (requires shipyard → requires spaceport)

**RBA Approach:**
```nim
# Turn 1: Try to build starbase → FAIL (no shipyard)
# Turn 2: Manually add "build shipyard" requirement
# Turn 3: Try to build shipyard → FAIL (no spaceport)
# Turn 4: Manually add "build spaceport" requirement
# Turn 5: Finally build spaceport
# Turn 7: Build shipyard
# Turn 10: Build starbase

# Total: 10 turns (manual dependency management)
```

**GOAP Approach:**
```nim
# Goal: ConstructStarbase(system7, priority=0.8)

# A* Planner backtracks through preconditions:
let plan = GOAPlan(
  actions: @[
    BuildFacility(Spaceport),   # Turn 1, enables shipyard
    BuildFacility(Shipyard),    # Turn 2, enables starbase
    BuildFacility(Starbase)     # Turn 3, goal achieved
  ],
  totalCost: 350,  # 100 + 150 + 200
  estimatedTurns: 3
)

# Total: 3 turns (automatic dependency resolution)
```

**Advantage:** GOAP automatically plans prerequisite chain without manual requirement generation.

### 3. Opportunity Cost Analysis

**Scenario:** 300 PP budget, multiple competing objectives

**RBA Approach (Greedy):**
```nim
# Allocate proportionally
Defense: 40% (120 PP) → Build 2 batteries (100 PP)
Military: 30% (90 PP) → Build 1 scout (30 PP)
Research: 20% (60 PP) → Invest 60 RP
Expansion: 10% (30 PP) → Invest 6 IU

# Result: All objectives partially funded
```

**GOAP Approach (Optimal Sequencing):**
```nim
# Generate all goals
let goals = @[
  DefendColony(system7, priority=0.9, cost=100),
  BuildFleet(scout, priority=0.7, cost=30),
  AchieveTechLevel(Weapons, priority=0.6, cost=60),
  ExpandProduction(system3, priority=0.5, cost=30)
]

# A* evaluates all sequences, chooses highest-value:
let plan = GOAPlan(
  turn1: DefendColony(system7) → 100 PP, utility=0.9
  turn2: BuildFleet(scout) → 30 PP, utility=0.7
  turn3: AchieveTechLevel(Weapons) → 60 PP, utility=0.6
  totalUtility: 2.2
)

# Alternative sequence considered:
# turn1: BuildFleet + AchieveTechLevel (90 PP), utility=1.3
# turn2: DefendColony (100 PP), utility=0.9
# totalUtility: 2.2 (same)

# Planner chooses sequence with earliest high-priority completion
```

**Advantage:** GOAP considers all valid sequences and chooses optimal order, not just proportional split.

### 4. Threat-Driven Replanning

**Scenario:** Enemy fleet changes course mid-plan

**RBA Approach:**
```nim
# Turn 5: Building defenses at System 7 (enemy 3 turns away)
# Turn 6: Enemy changes course → now heading to System 3
# Turn 7: Continue building System 7 defenses (no replanning)
# Turn 8: Enemy arrives at System 3 (undefended) ⚠️

# Issue: No plan tracking, can't detect invalidation
```

**GOAP Approach:**
```nim
# Turn 5: Executing plan to defend System 7
# Turn 6: Detect world state change (enemy redirected to System 3)

# Replanning trigger:
if not validateBuildPlan(currentPlan, newSnapshot):
  # Plan invalidated: System 7 no longer highest priority
  let newGoal = DefendColony(system3, priority=0.95)
  let newPlan = planActions(newSnapshot, newGoal, availableActions)

  # Switch to new plan immediately
  # Turn 6: Start building System 3 defenses
  # Turn 7-8: Complete System 3 defenses before enemy arrival ✅
```

**Advantage:** GOAP tracks plan validity and replans when strategic situation changes.

## Integration with Act-Aware System

The Act-aware defense system **fits perfectly** into GOAP planning:

### Act-Aware Baseline in GOAP Goals

```nim
# GOAP goal generation uses Act-aware baselines
proc generateDefenseGoals*(
  snapshot: WorldStateSnapshot,
  currentAct: GameAct
): seq[Goal] =

  result = @[]

  for colony in snapshot.undefendedColonies:
    # Act-aware baseline determines goal target
    let baselineTarget = case currentAct
      of GameAct.Act1_LandGrab: 1 battery
      of GameAct.Act2_RisingTensions: 2 batteries
      of GameAct.Act3_TotalWar: 3 batteries

    # Intelligence-driven escalation
    let threat = estimateLocalThreat(colony, snapshot)
    let targetDefenses = if threat > 0.5:
      3  # Emergency fortification
    elif threat > 0.2:
      max(baselineTarget, 2)
    else:
      baselineTarget

    # Generate goal with Act-aware + threat-based target
    result.add(Goal(
      goalType: DefendColony,
      target: some(colony),
      priority: priorityFromThreat(threat),
      requiredResources: targetDefenses * 50,  # 50 PP per battery
      deadline: deadlineFromThreat(threat, snapshot.turn)
    ))
```

**Key Point:** GOAP uses the SAME Act-aware logic you already built, just wraps it in strategic planning.

### Multi-Turn Phased Buildup

```nim
# GOAP can plan the Act 1 → Act 2 → Act 3 defense progression

# Act 1 (Turn 1-10): Minimal defenses
let act1Plan = GOAPlan(
  turn1: BuildBattery(system7),  # 1 battery baseline
  turn2: BuildBattery(system3),  # Spread across colonies
  turn3: BuildBattery(system5)
)

# Act 2 transition (Turn 11): Upgrade to 2 batteries
let act2Plan = GOAPlan(
  turn11: BuildBattery(system7),  # Upgrade to 2
  turn12: BuildBattery(system3),  # Upgrade to 2
  turn13: BuildArmy(system7)      # Start army buildup
)

# Act 3 (Turn 20+): War economy, full fortification
let act3Plan = GOAPlan(
  turn20: BuildBattery(system7),  # Upgrade to 3
  turn21: BuildArmy(system7),     # Upgrade to 2 armies
  turn22: BuildStarbase(system7)  # Complete fortification
)
```

**Advantage:** GOAP can plan long-term defense progression matching economic growth curve.

## Implementation Roadmap

### Phase 1: Current (RBA Only) ✅ COMPLETE

**Status:** Validated and working
**Capabilities:**
- Per-colony Act-aware defense requirements
- Intelligence-driven threat escalation
- 100% tactical budget allocation
- Economic sustainability

**Keep this as fallback** - GOAP is enhancement, not replacement.

### Phase 2: Basic GOAP Integration (3-5 days)

**Add:**
1. Defense goal generation in `domains/build/goals.nim`
2. Simple defense planner (2-3 turn plans)
3. RBA-GOAP bridge for plan execution
4. Plan tracking (mark progress, detect completion)

**Example:**
```nim
# In build/goals.nim
proc createDefendColonyGoal*(
  systemId: SystemId,
  priority: float,
  targetBatteries: int,
  currentAct: GameAct
): Goal =
  let cost = targetBatteries * 50
  let deadline = estimateDeadline(priority, currentAct)

  result = Goal(
    goalType: DefendColony,
    priority: priority,
    target: some(systemId),
    requiredResources: cost,
    deadline: some(deadline),
    preconditions: @[
      controlsSystem(systemId),
      hasMinBudget(cost)
    ],
    successCondition: hasDefenses(systemId, batteries=targetBatteries)
  )
```

### Phase 3: Multi-Colony Optimization (5-7 days)

**Add:**
1. Multi-goal planning (defend 3 colonies in sequence)
2. Budget reservation system (ensure plan completion)
3. Priority-based sequencing (highest-priority goals first)

**Example:**
```nim
# Plan optimal defense sequence for budget
proc planDefenseSequence*(
  snapshot: WorldStateSnapshot,
  goals: seq[Goal],
  budget: int
): GOAPlan =
  # Sort by priority
  let sorted = goals.sortedByIt(-it.priority)

  var plan = initGOAPlan()
  var remainingBudget = budget

  # Greedy: fund highest-priority goals to completion
  for goal in sorted:
    if goal.requiredResources <= remainingBudget:
      plan.actions.add(actionsForGoal(goal))
      remainingBudget -= goal.requiredResources
    # Skip goals we can't afford (don't partial-fund)

  return plan
```

### Phase 4: Adaptive Replanning (7-10 days)

**Add:**
1. Plan validation (detect invalidation conditions)
2. Replanning triggers (enemy movement, budget shortage)
3. Plan merging (combine defense + fleet plans)
4. Confidence tracking (reduce confidence as world state changes)

**Example:**
```nim
# Detect when plan needs replanning
proc shouldReplan*(
  currentPlan: GOAPlan,
  newSnapshot: WorldStateSnapshot
): bool =
  # Check if goal still valid
  if not goalStillRelevant(currentPlan.goal, newSnapshot):
    return true

  # Check if preconditions still met
  if not validateBuildPlan(currentPlan, newSnapshot):
    return true

  # Check if better plan now available
  let newPlan = planActions(newSnapshot, currentPlan.goal, availableActions)
  if newPlan.isSome and newPlan.get().totalCost < currentPlan.totalCost * 0.8:
    return true  # >20% cost improvement available

  return false
```

## Performance Considerations

### Computational Cost

**RBA (Current):**
- O(N) colonies × O(1) requirement generation = O(N)
- Very fast: <1ms for 10 colonies

**GOAP:**
- O(B^D) where B = branching factor, D = plan depth
- Typical: ~10-100ms for 3-turn plan with 20 actions
- Worst case: ~1000ms for 5-turn plan with 50 actions

**Mitigation:**
- Cache plans (reuse if world state similar)
- Limit plan depth to 3-5 turns
- Use domain-specific actions (not all 50+ actions)
- Incremental replanning (modify plan instead of rebuild)

### Memory Overhead

**RBA:** ~1 KB per requirement (100 colonies × 1 KB = 100 KB)
**GOAP:** ~10 KB per plan (5 plans × 10 KB = 50 KB)
**Total:** ~150 KB additional memory (negligible)

## Conclusion

### Should You Add GOAP to Defense System?

**Add GOAP if:**
- ✅ You want multi-turn strategic planning (optimize 3-5 turns ahead)
- ✅ You want complete goal achievement (fully defend 3 colonies vs. partially defend 10)
- ✅ You want complex dependency handling (spaceport → shipyard → starbase)
- ✅ You want proactive positioning (fortify before enemies arrive)
- ✅ You're willing to spend 10-20 days implementing + testing

**Keep RBA-only if:**
- ✅ Current tactical system meets your needs (it's working well!)
- ✅ Fast, reactive decision-making is more important than strategic planning
- ✅ You want to avoid additional complexity
- ✅ Computational budget is tight (<10ms per AI update)

### Recommendation

Your **Act-aware RBA system is excellent** and working correctly. I'd recommend:

1. **Short term (now):** Keep pure RBA, run 30-turn comprehensive tests
2. **Medium term (1-2 weeks):** Add basic GOAP for defense goal generation + 2-turn plans
3. **Long term (1-2 months):** Expand to multi-colony optimization + adaptive replanning

The beauty of the hybrid architecture is that **GOAP is optional** - you can enable it when strategic planning adds value, fall back to pure RBA when fast reactions matter.

---

**Your Act-aware defense system is production-ready. GOAP is an enhancement, not a fix.**
