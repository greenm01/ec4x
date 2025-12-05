# GOAP Phase 4: RBA Integration - Progress Report

## Status: Integration Modules Complete ✅

**Date:** 2025-12-04
**Phase:** 4 (RBA Integration)
**Modules Created:** 4 files, ~850 LOC
**Compilation Status:** All files compile cleanly ✅

---

## Phase 4 Deliverables

### ✅ Completed

#### 1. `src/ai/rba/goap/integration/conversion.nim` (180 LOC)

**Purpose:** Centralized conversion logic between RBA and GOAP systems

**Key Functions:**
```nim
proc extractAllGoalsFromState*(state: WorldStateSnapshot): seq[Goal]
  ## Main entry point for GOAP in RBA Phase 1.5
  ## Calls all 6 domain-specific goal extraction functions

proc prioritizeGoals*(goals: seq[Goal]): seq[Goal]
  ## Sort goals by priority (highest first)

proc filterAffordableGoals*(goals: seq[Goal], availableBudget: int): seq[Goal]
  ## Filter goals to only those we can afford

proc getDomainForGoal*(goal: Goal): DomainType
  ## Determine which domain a goal belongs to (for advisor routing)

proc groupGoalsByDomain*(goals: seq[Goal]): Table[DomainType, seq[Goal]]
  ## Group goals by their domain for advisor routing

type GoalAllocation* = tuple
  goal: Goal
  allocated: int
  fundingRatio: float

proc allocateBudgetToGoals*(goals: seq[Goal], totalBudget: int): seq[GoalAllocation]
  ## Greedy budget allocation: highest priority goals get funded first
```

**Design Notes:**
- DRY compliance: Single source of truth for goal aggregation
- All 6 domains integrated (Fleet, Build, Research, Diplomatic, Espionage, Economic)
- Budget allocation uses seq instead of Table to avoid Goal hashing issues

#### 2. `src/ai/rba/goap/integration/plan_tracking.nim` (270 LOC)

**Purpose:** Track GOAP plan execution across multiple turns

**Key Types:**
```nim
type
  PlanStatus* {.pure.} = enum
    Active        # Plan is currently being executed
    Completed     # Plan successfully achieved its goal
    Failed        # Plan failed (action couldn't be executed)
    Invalidated   # Plan no longer viable (preconditions violated)
    Paused        # Plan temporarily paused (lower priority work)

  TrackedPlan* = object
    plan*: GOAPlan
    status*: PlanStatus
    startTurn*: int
    currentActionIndex*: int
    turnsInExecution*: int
    actionsCompleted*: int
    actionsFailed*: int
    lastUpdateTurn*: int

  PlanTracker* = object
    activePlans*: seq[TrackedPlan]
    completedPlans*: seq[TrackedPlan]
    currentTurn*: int
```

**Key Functions:**
```nim
proc newPlanTracker*(): PlanTracker
proc addPlan*(tracker: var PlanTracker, plan: GOAPlan)
proc advancePlan*(tracker: var PlanTracker, planIndex: int)
proc failPlan*(tracker: var PlanTracker, planIndex: int)
proc pausePlan*(tracker: var PlanTracker, planIndex: int)
proc resumePlan*(tracker: var PlanTracker, planIndex: int)
proc isPlanStillValid*(plan: TrackedPlan, state: WorldStateSnapshot): bool
proc validateAllPlans*(tracker: var PlanTracker, state: WorldStateSnapshot)
proc archiveCompletedPlans*(tracker: var PlanTracker)
proc getActivePlanCount*(tracker: PlanTracker): int
proc getNextAction*(tracker: PlanTracker, planIndex: int): Option[Action]
proc advanceTurn*(tracker: var PlanTracker, newTurn: int, state: WorldStateSnapshot)
```

**Design Notes:**
- Immutable tracking: Plans are not mutated, status is tracked separately
- Plan validation: Checks if preconditions still hold each turn
- History tracking: Completed plans archived for analysis
- Goal-specific validation (e.g., DefendColony checks if colony still vulnerable)

#### 3. `src/ai/rba/goap/integration/replanning.nim` (240 LOC)

**Purpose:** Generate alternative plans when original plan fails or becomes invalid

**Key Types:**
```nim
type
  ReplanReason* {.pure.} = enum
    PlanFailed          # Action execution failed
    PlanInvalidated     # Preconditions no longer hold
    BudgetShortfall     # Not enough resources
    BetterOpportunity   # New, higher-priority goal emerged
    ExternalEvent       # Enemy action changed situation
```

**Key Functions:**
```nim
proc shouldReplan*(plan: TrackedPlan, state: WorldStateSnapshot): (bool, ReplanReason)
  ## Determine if a plan needs replanning

proc generateAlternativePlans*(state: WorldStateSnapshot, goal: Goal, maxAlternatives: int = 3): seq[GOAPlan]
  ## Generate multiple alternative plans for a goal

proc selectBestAlternative*(alternatives: seq[GOAPlan], state: WorldStateSnapshot, prioritizeSpeed: bool = false): Option[GOAPlan]
  ## Select best plan from alternatives (highest confidence, lowest cost, fewest turns)

proc repairPlan*(failedPlan: TrackedPlan, state: WorldStateSnapshot): Option[GOAPlan]
  ## Attempt to repair a failed plan (early failure = replan, late failure = partial repair)

proc replanWithBudgetConstraint*(tracker: var PlanTracker, state: WorldStateSnapshot, availableBudget: int): seq[GOAPlan]
  ## Replan all active goals with budget constraint (used in RBA Phase 2 mediation)

proc detectNewOpportunities*(currentGoals: seq[Goal], state: WorldStateSnapshot): seq[Goal]
  ## Detect new high-value goals (weakly defended colonies, alliance opportunities, etc.)

proc integrateNewOpportunities*(tracker: var PlanTracker, newGoals: seq[Goal], state: WorldStateSnapshot, maxConcurrentPlans: int = 5)
  ## Integrate newly detected opportunities into plan tracker (may pause lower-priority plans)
```

**Design Notes:**
- Opportunistic replanning: Detects invasion opportunities, alliance chances
- Budget-constrained replanning: Used in Phase 2 mediation
- Plan repair: Early failures replan from scratch, late failures try partial repair
- Phase 4 implementation: Alternative plan generation deferred to Phase 5

#### 4. `src/ai/rba/orders/phase1_5_goap.nim` (260 LOC)

**Purpose:** RBA Phase 1.5 integration point (called between Phase 1 and Phase 2)

**Key Types:**
```nim
type
  GOAPConfig* = object
    enabled*: bool                    # Enable/disable GOAP
    planningDepth*: int               # Max turns to plan ahead
    confidenceThreshold*: float       # Min confidence to execute plan
    maxConcurrentPlans*: int          # Max active plans at once
    defensePriority*: float           # Weight for defensive goals (0.0-1.0)
    offensePriority*: float           # Weight for offensive goals (0.0-1.0)
    logPlans*: bool                   # Debug: log all generated plans

  Phase15Result* = object
    goals*: seq[Goal]                           # Extracted strategic goals
    plans*: seq[GOAPlan]                        # Generated plans
    budgetEstimates*: Table[DomainType, int]    # Budget requirements by domain
    planningTimeMs*: float                      # Performance metric
```

**Key Functions:**
```nim
proc defaultGOAPConfig*(): GOAPConfig

proc extractStrategicGoals*(state: FilteredGameState, intel: IntelligenceSnapshot, config: GOAPConfig): seq[Goal]
  ## Extract all strategic goals from current game state
  ## Calls extractAllGoalsFromState and applies priority weights

proc generateStrategicPlans*(goals: seq[Goal], state: FilteredGameState, intel: IntelligenceSnapshot, config: GOAPConfig): seq[GOAPlan]
  ## Generate GOAP plans for goals, sorted by confidence * priority
  ## Filters by confidence threshold and limits to max concurrent plans

proc estimateBudgetRequirements*(plans: seq[GOAPlan]): Table[DomainType, int]
  ## Estimate budget requirements by domain for Phase 2 mediation

proc annotatePlansWithBudget*(plans: seq[GOAPlan], availableBudget: int): seq[tuple[plan: GOAPlan, allocated: int, fundingRatio: float]]
  ## Annotate plans with budget allocation (used when budget is limited)

proc executePhase15_GOAP*(state: FilteredGameState, intel: IntelligenceSnapshot, config: GOAPConfig): Phase15Result
  ## Main entry point: Execute Phase 1.5 GOAP Strategic Planning
  ## Called by order_generation.nim between phase1 and phase2
  ## Returns empty result if GOAP disabled

proc mergeGOAPEstimatesIntoDomestikosRequirements*(requirements: var BuildRequirements, budgetEstimates: Table[DomainType, int])
  ## Merge GOAP budget estimates into Domestikos build requirements (placeholder for Phase 4 enhancement)

proc integrateGOAPPlansIntoController*(controller: var AIController, plans: seq[GOAPlan])
  ## Store GOAP plans in AI controller for tracking (placeholder for Phase 4)
```

**Design Notes:**
- Backward compatible: Returns empty result if GOAP disabled
- Performance tracking: planningTimeMs field (not yet implemented)
- Priority weights: Defense/offense priorities applied from config
- Confidence filtering: Only executes plans above threshold
- Budget awareness: Estimates requirements for Phase 2 mediation

---

## Compilation Status

All 4 modules compile cleanly:
```bash
nim check src/ai/rba/goap/integration/conversion.nim  ✅
nim check src/ai/rba/goap/integration/plan_tracking.nim  ✅
nim check src/ai/rba/goap/integration/replanning.nim  ✅
nim check src/ai/rba/orders/phase1_5_goap.nim  ✅
```

Only warnings: Unused imports (expected for Phase 4 stubs)

---

## Remaining Phase 4 Work

### ⏳ Pending Tasks

#### 1. Update `src/ai/rba/controller_types.nim` (~50 LOC)

Add GOAP fields to AIController:
```nim
type
  AIController* = object
    # ... existing fields ...

    # GOAP Phase 4 additions:
    goapPlanTracker*: Option[PlanTracker]      # Multi-turn plan tracking
    goapConfig*: GOAPConfig                     # GOAP configuration
    goapEnabled*: bool                          # Quick check for GOAP status
```

#### 2. Enhance `src/ai/rba/orders/phase2_mediation.nim` (~100 LOC)

Integrate GOAP cost estimates into budget mediation:
```nim
proc mediateRequirements*(
  controller: var AIController,
  filtered: FilteredGameState,
  phase15Result: Phase15Result,  # NEW: GOAP result
  currentAct: GameAct
) =
  # Use phase15Result.budgetEstimates for informed mediation
  # Prioritize requirements that align with GOAP strategic plans
  # ...
```

#### 3. Call Phase 1.5 from order generation

Integrate into main RBA cycle (in `src/ai/rba/orders/order_generation.nim` or similar):
```nim
# Phase 1: Requirements generation
generateAllAdvisorRequirements(controller, filtered, intel, currentAct)

# Phase 1.5: GOAP strategic planning (NEW)
let phase15Result = executePhase15_GOAP(filtered, intel, controller.goapConfig)
integrateGOAPPlansIntoController(controller, phase15Result.plans)

# Phase 2: Mediation (enhanced with GOAP)
mediateRequirements(controller, filtered, phase15Result, currentAct)

# Phase 3: Execution
# Phase 4: Feedback
# Phase 5: Strategic ops (to be added)
```

---

## Key Design Decisions

### 1. Avoided Goal Hashing
**Problem:** Goal type contains ref types (PreconditionRef, SuccessConditionRef) which can't be hashed
**Solution:** Changed `allocateBudgetToGoals` to return `seq[GoalAllocation]` instead of `Table[Goal, int]`
**Impact:** Slightly less efficient lookup, but avoids complex hash function implementation

### 2. Placeholder Stubs for Phase 5 Features
**Examples:**
- `generateAlternativePlans`: Returns only base plan, alternative generation deferred
- `repairPlan`: Currently just replans from scratch, partial repair deferred
- `integrateGOAPPlansIntoController`: Placeholder until AIController fields added

**Rationale:** Phase 4 focuses on integration framework, Phase 5 will flesh out advanced features

### 3. Configuration-Driven GOAP
**Design:** All GOAP behavior controlled via GOAPConfig
**Benefits:**
- Easy to disable GOAP for A/B testing
- Priority weights (defense/offense) configurable per strategy
- Confidence threshold tunable for conservative vs aggressive play

### 4. DRY Principles Maintained
**Examples:**
- `conversion.nim` centralizes goal aggregation (not duplicated per advisor)
- `plan_tracking.nim` provides single plan status system
- `replanning.nim` handles all replanning logic

**No duplication** between domains or advisors

---

## Integration Points with Existing RBA

### Phase 0: Intelligence
- No changes (GOAP uses IntelligenceSnapshot from this phase)

### Phase 1: Requirements
- No changes (GOAP extracts goals from state in Phase 1.5)

### **Phase 1.5: GOAP Strategic Planning (NEW)**
- Calls `executePhase15_GOAP()`
- Produces strategic goals and plans
- Estimates budget requirements by domain

### Phase 2: Mediation
- **Enhancement needed:** Use GOAP budget estimates for informed mediation
- Prioritize requirements that align with strategic plans
- Detect budget shortfalls for replanning

### Phase 3: Execution
- No changes (executes mediated requirements as before)

### Phase 4: Feedback
- **Enhancement planned:** Trigger replanning for unfulfilled requirements
- Update plan tracker with execution results

### Phase 5: Strategic Ops (NEW - Phase 5 implementation)
- Multi-turn plan coordination
- Plan continuation across turns
- Invalidation detection

---

## Performance Considerations

### Memory Overhead (Estimated)
- WorldStateSnapshot: ~2 KB (turn state copy)
- PlanTracker: ~1 KB per active plan (max 5 plans = 5 KB)
- TrackedPlan: ~200 bytes per plan
- **Total: <10 KB** per house (negligible)

### CPU Overhead (Estimated)
- Goal extraction: <10ms (6 domain calls)
- A* planning: <100ms per goal (target, Phase 3 simplified)
- Plan validation: <5ms (per turn check)
- **Total Phase 1.5: <500ms** per turn (target)

**Note:** Phase 3 planner currently simplified (fixed depth), full A* in Phase 5

---

## Testing Status

### Unit Tests
- Phase 1-3: 35/35 passing ✅
- Phase 4: No new tests yet ⏳

### Integration Tests Needed (Phase 4)
- [ ] Full RBA turn cycle with GOAP enabled
- [ ] GOAP disabled (backward compatibility)
- [ ] Budget allocation with GOAP estimates
- [ ] Plan tracking across multiple turns
- [ ] Replanning triggered by budget shortfall

### Performance Tests Needed (Phase 4)
- [ ] Phase 1.5 completes in <500ms
- [ ] Memory overhead <10 KB per house
- [ ] 10-turn game with GOAP enabled

---

## Next Steps

### Immediate (Complete Phase 4)
1. ✅ Create integration modules (conversion, plan_tracking, replanning, phase1_5_goap)
2. ⏳ Update AIController with GOAP fields
3. ⏳ Enhance Phase 2 mediation with GOAP cost estimates
4. ⏳ Call Phase 1.5 from order generation
5. ⏳ Write integration tests

### Phase 5 (Feedback & Replanning)
- Implement Phase 5 strategic coordinator
- Enhance Phase 4 feedback with replanning triggers
- Multi-turn plan continuation
- Plan invalidation detection
- Alternative plan generation (full implementation)

### Phase 6 (Parameter Sweep)
- Create `src/ai/sweep/` framework
- Define GOAP parameters for tuning
- Run 100+ game parameter sweep
- Document optimal configurations

---

## Success Criteria (Phase 4)

### ✅ Completed
- [x] 4 integration modules created (~850 LOC)
- [x] All modules compile cleanly
- [x] DRY principles maintained
- [x] Small, focused files (<300 LOC each)
- [x] NEP-1 compliant (pure enums, doc comments)

### ⏳ Remaining
- [ ] AIController updated with GOAP fields
- [ ] Phase 2 mediation enhanced
- [ ] Phase 1.5 called from order generation
- [ ] Integration tests passing
- [ ] Performance tests passing
- [ ] Zero regressions in existing RBA tests

---

## File Summary

| File | LOC | Status | Purpose |
|------|-----|--------|---------|
| `conversion.nim` | 180 | ✅ Compiles | Goal aggregation, budget allocation |
| `plan_tracking.nim` | 270 | ✅ Compiles | Multi-turn plan execution tracking |
| `replanning.nim` | 240 | ✅ Compiles | Alternative plans, opportunistic replanning |
| `phase1_5_goap.nim` | 260 | ✅ Compiles | RBA Phase 1.5 integration point |
| **Total** | **950** | **✅ All compile** | **Phase 4 integration framework** |

---

## Conclusion

**Phase 4 integration modules are complete and compiling.** The framework for connecting GOAP strategic planning to the existing RBA tactical system is now in place.

**Remaining Phase 4 work:** ~150 LOC (AIController update, Phase 2 enhancement, call site integration)

**Estimated time to complete Phase 4:** 1-2 days

**Ready to proceed with Phase 5 and Phase 6 once Phase 4 integration is complete!** 🚀
