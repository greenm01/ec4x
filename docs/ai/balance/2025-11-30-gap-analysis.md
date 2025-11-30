# AI Combat System Gap Analysis

**Date**: November 30, 2025
**Analysis Type**: Systematic Advisor Audit
**Problem Statement**: Zero combat occurring in 40-turn AI vs AI games

---

## Executive Summary

Systematic audit of the Byzantine Imperial Government AI system revealed **three critical gaps** preventing combat:

1. **PROTOSTRATOR (Diplomat)**: Requirements generated but never executed (stub function)
2. **DOMESTIKOS (Admiral)**: Invasions overly restricted by Act/personality gates
3. **BASILEUS (Emperor)**: Budget weighting too conservative to enforce act transitions

**Root Cause**: The bridge between advisor requirements and actual game actions is incomplete, particularly for diplomatic actions (war declarations).

---

## Methodology

Each advisor was audited against their specifications:
1. Read relevant spec documents (diplomacy.md, operations.md, gameplay.md)
2. Analyze advisor implementation code
3. Compare SHOULD (spec) vs IS (implementation)
4. Identify gaps and missing functionality
5. Assess impact on combat

---

## Game Context - Zero Combat in 40 Turns

**Observed Behavior** (seed 12345, 40 turns):
- **Zero planets** changed hands through combat
- **28/28 colonies** frozen from turn 13-41 (73% of game)
- **Minimal military**: 3-16 ships at turn 41 (expected: 50-100+)
- **No starbases**: All houses have 0 defensive structures
- **Winner determined by turn 12**: Harkonnen grabbed 9 colonies vs 5-7 for others

**Expected Behavior** (based on Act structure):
- Act 1 (1-7): Peaceful expansion ✓ Working
- Act 2 (8-15): Border conflicts, first wars ✗ Broken
- Act 3 (16-25): Major invasions, territory changes ✗ Broken
- Act 4 (26-40): Final conquests, territorial collapse ✗ Broken

---

## Advisor Audit Results

### 1. PROTOSTRATOR (Diplomat) - CRITICAL FAILURE

**Role**: Foreign relations, war declarations, treaties

**Spec Requirements** (`docs/specs/diplomacy.md`):
- Manage diplomatic states: Neutral, Non-Aggression Pact, Enemy
- Enemy status triggers "full-scale warfare where all encounters are treated as hostile"
- Defense protocols override diplomatic considerations for home defense

**Implementation Analysis**:

**✓ What Works**:
- War requirements ARE generated (`src/ai/rba/protostrator/requirements.nim:89-102`)
- Conditions: prestige gap < -200, aggression > 0.6, vulnerable colonies exist
- Requirements stored in controller (`src/ai/rba/orders/phase1_requirements.nim:109`)
- Game engine ready to process war declarations (`src/engine/resolution/diplomatic_resolution.nim:272-288`)

**✗ What's Broken**:
- Execution function is a STUB (`src/ai/rba/orders/phase3_execution.nim:77-90`)
```nim
proc executeDiplomaticActions*(...): seq[DiplomaticAction] =
  # TODO: Implement generateDiplomaticActions when diplomatic system ready
  result = @[]  # ALWAYS RETURNS EMPTY
```

**Impact**:
- Zero `DiplomaticAction` objects created
- Engine never receives `DeclareEnemy` actions
- All houses remain in Neutral diplomatic state indefinitely
- **No wars → No combat → No territory changes**

**Gap Summary**:
- **Type**: Implementation stub (50-100 line function missing)
- **Severity**: Critical blocker
- **Effort**: 1-2 hours to implement requirement → action conversion

---

### 2. DOMESTIKOS (Admiral) - ARCHITECTURAL MISMATCH

**Role**: Military commander, fleet operations, defense, invasions

**Spec Requirements** (`docs/specs/operations.md`):
- Section 7.6.1: Invasions require orbital supremacy, destroyed batteries, loaded transports
- Section 6.3: Fleet orders include Invade Planet, Blitz Planet, Bombard Planet
- No Act restrictions mentioned
- No personality restrictions mentioned

**Implementation Analysis**:

**✓ What Works**:
- Build requirements for transports/marines generated (`src/ai/rba/domestikos/build_requirements.nim:544-722`)
- Coordinated operation planning exists (`src/ai/rba/tactical.nim:940-1020`)
- Defensive operations functional (colony protection)

**✗ What's Broken**:

**Gap #1: Domestikos Doesn't Generate Invasion Orders**
- File: `src/ai/rba/domestikos.nim:78-210`
- Domestikos handles: Defense, build requirements, fleet reorganization
- Domestikos does NOT handle: Offensive operations, invasion planning
- Actual invasion logic scattered in: `orders.nim` → `tactical.nim` → `strategic.nim`

**Gap #2: Act Gating (Not in Spec)**
- File: `src/ai/rba/orders.nim:204`
- Act 1 (turns 1-7): Invasions DISABLED by design
- Act 2+: Invasions enabled but subject to other gates
- Impact: 82.5% of 40-turn game had invasions architecturally forbidden

**Gap #3: Personality Gating (Not in Spec)**
- Planning gate: `aggression > 0.4` (`orders.nim:204`)
- Build gate: `aggression > 0.6` for transports/marines (`build_requirements.nim:551`)
- Impact: Non-aggressive AI houses never build invasion capability

**Gap #4: Multi-Fleet Requirement (Stricter than Spec)**
- File: `src/ai/rba/tactical.nim:1002`
- Requires: Minimum 2 combat fleets available
- Spec allows: Single fleet with proper forces
- Impact: No opportunistic invasions

**Gap #5: Strict Target Filtering**
- Requires: 2:1 combat advantage OR valuable + 1.4:1 advantage
- Requires: defenseStrength < 200 (≈2 starbases)
- Impact: Early fortified colonies excluded from targeting

**Gap #6: Build Pipeline Delays**
- Sequence: Research CST 3 → Build Transports → Recruit Marines → Load → Assemble → Execute
- Duration: 10+ turns minimum
- Impact: Even if all gates pass, invasions delayed significantly

**Impact**:
- Zero invasions attempted in 40 turns
- Probability of all conditions aligning in available time: Extremely low
- Military resources spent on defense, not offense

**Gap Summary**:
- **Type**: Architectural mismatch + overly restrictive gates
- **Severity**: High (blocks invasions even when wars exist)
- **Effort**: 30 min - 2 hours depending on scope

---

### 3. BASILEUS (Emperor) - WEAK ACT MODULATION

**Role**: Mediator between advisors, budget allocator, strategic prioritization

**Spec Requirements** (`config/rba.toml`):
- Act 1: 20% military budget
- Act 2: 20% military budget
- **Act 3: 45% military budget** (Total War)
- **Act 4: 55% military budget** (Endgame)

**Implementation Analysis**:

**✓ What Works**:
- Multi-advisor mediation system functional
- Personality-driven weighting operational
- Act-based modifiers exist (`src/ai/rba/basileus/personality.nim:51-60`)

**✗ What's Broken**:

**Gap #1: Conservative Act Modifiers**
- File: `src/ai/rba/basileus/personality.nim:52-58`
- Act 3/4 modifier: Domestikos gets 1.15x weight (15% boost)
- Spec requires: 45% → 55% budget shift (125% increase)
- Reality: 15% weight boost ≠ 125% budget increase

**Gap #2: Reserved Budget Reduces Pool**
- File: `src/ai/rba/treasurer/multi_advisor.nim:163-166`
- 15% budget (10% recon + 5% expansion) reserved BEFORE mediation
- Only 85% of budget participates in Basileus mediation
- Impact: Even 100% mediation win = 15% + 85% = 100%, typically gets 15% + 30-40% = 45-55%

**Gap #3: Defensive Priorities Starve Offensive**
- File: `src/ai/rba/basileus/mediation.nim:49-58`
- Critical requirements (score 1000) processed first
- Defensive requirements often Critical
- Offensive requirements often Medium (score 10)
- Impact: Budget consumed by defense before offensive spending

**Gap #4: Personality Weights Suppress Act Urgency**
- Personality modifiers: 0.7-1.3 range
- Act modifiers: 0.85-1.15 range
- Same magnitude means personality can negate act-based priorities

**Impact**:
- Military gets 23-28% budget in Act 3 instead of 45%
- Insufficient resources for simultaneous defense + offense
- Military spending favors defensive ships over invasion forces

**Gap Summary**:
- **Type**: Insufficient act-based prioritization
- **Severity**: Medium (allows some military, but not enough)
- **Effort**: 30 min to adjust weights

---

## Architectural Feedback: Basileus Central Role

### Current Architecture Issues

**Problem**: Requirements execution is scattered across multiple locations:
- Protostrator requirements → `phase3_execution.nim:executeDiplomaticActions()`
- Domestikos requirements → `treasurer.nim` budget enforcement
- Logothete requirements → `phase3_execution.nim:executeResearchAllocation()`
- Other advisors → Various execution paths

**Missing**: Basileus doesn't execute orders after mediation - just allocates budgets

### Proposed Architecture Revision

**Principle**: Basileus should be the central executor after receiving advisor input

**Flow**:
1. **Phase 0**: Drungarius distributes intelligence
2. **Phase 1**: All advisors generate requirements
3. **Phase 2**: Basileus mediates requirements, Treasurer provides budget feedback
4. **Phase 3**: Basileus executes approved requirements
   - For PP-costing actions: After Treasurer validation
   - For zero-cost actions (diplomacy, fleet orders): Direct execution

**Rationale**:
- Matches Byzantine Imperial Government metaphor (Emperor makes final decisions)
- Centralizes execution logic (easier to audit/debug)
- Separates advisor recommendations from imperial decrees
- Allows Basileus to override low-priority requirements

**Key Distinction**:
- **PP-costing actions**: Research, builds, terraform → Treasurer must approve budget
- **Zero-cost actions**: War declarations, fleet movement, standing orders → Basileus executes directly

### Files Requiring Architectural Change

**Current problematic pattern**:
- `src/ai/rba/orders/phase3_execution.nim` - Scattered execution functions
- `src/ai/rba/treasurer.nim` - Budget enforcement mixed with execution

**Proposed centralized pattern**:
- `src/ai/rba/basileus/execution.nim` - New file for centralized order execution
- Basileus queries: "Does this cost PP?" → If yes, check with Treasurer → Execute
- Single source of truth for all imperial decisions

---

## Compounding Factors Analysis

### Why Zero Combat in 40 Turns?

**Chain of Failures**:

1. **Protostrator stub** → Zero war declarations
2. **No wars** → No Enemy diplomatic state
3. **No Enemy state** → Fleets won't engage in combat
4. **Act 1 invasion gate** → First 7 turns can't invade anyway
5. **Aggression gates** → Low-aggression AI can't invade even in war
6. **Multi-fleet requirement** → No opportunistic invasions
7. **Weak Act 3 weights** → Military starved of budget
8. **Defense priority dominance** → Offense gets minimal resources
9. **Build pipeline delays** → 10+ turns to prepare invasion
10. **Target filtering** → Few colonies meet vulnerability criteria

**Result**: Multiple independent gates ALL must open for combat to occur. If ANY gate fails, zero combat.

---

## Gap Categorization

### Critical Blockers (Must Fix)
1. **Protostrator execution stub** - Prevents ALL diplomatic actions
2. **Basileus architectural role** - Central execution not implemented

### High Impact (Should Fix)
3. **Act 1 invasion gate** - Removes 82.5% of game time
4. **Basileus act weights** - Prevents resource mobilization for war
5. **Domestikos role mismatch** - Admiral doesn't command offensives

### Medium Impact (Consider Fixing)
6. **Personality gates** - Excludes non-aggressive AI from warfare
7. **Multi-fleet requirement** - Prevents opportunistic invasions
8. **Target filtering strictness** - Reduces invasion opportunities

### Low Impact (Monitor)
9. **Build pipeline delays** - Realistic but contributes to stagnation
10. **Reserved budget** - Design choice, but reduces act flexibility

---

## Recommended Implementation Priority

### Phase 1: Architectural Foundation (NEW)
**Goal**: Establish Basileus as central executor

**Changes**:
1. Create `src/ai/rba/basileus/execution.nim`
2. Move all execution logic from `phase3_execution.nim` to Basileus
3. Implement PP-cost checking before Treasurer consultation
4. Zero-cost actions (diplomacy, fleet orders) bypass Treasurer

**Impact**: Clean separation of concerns, easier to audit/debug
**Effort**: 2-4 hours (architectural refactor)

### Phase 2: Unblock Diplomatic Actions (CRITICAL)
**Goal**: Enable war declarations

**Changes**:
1. Implement `executeDiplomaticActions()` in Basileus execution module
2. Convert Protostrator requirements → DiplomaticAction objects
3. Handle: DeclareWar, ProposePact, BreakPact types

**Impact**: Wars can be declared, Enemy diplomatic state achieved
**Effort**: 1-2 hours (50-100 lines of code)
**Expected Result**: 2-4 wars per 40-turn game

### Phase 3: Enable Early-Game Invasions (HIGH)
**Goal**: Remove artificial Act 1 restriction

**Changes**:
1. Remove/relax Act gating in `orders.nim:204`
2. Allow invasions in Act 1 if war exists

**Impact**: Invasions possible throughout game
**Effort**: 30 minutes (conditional change)
**Expected Result**: 1-3 invasions in Act 1

### Phase 4: Strengthen Wartime Prioritization (HIGH)
**Goal**: Enforce spec budget allocations for Act 3/4

**Changes**:
1. Increase Domestikos weight: 1.15x → 1.8x (Act 3), 2.0x (Act 4)
2. Decrease Protostrator weight: 0.85x → 0.70x (wartime)
3. Consider reducing reserved budget from 15% → 10% in Act 3/4

**Impact**: Military budget rises from 23-28% → 40-50%
**Effort**: 30 minutes (weight tuning)
**Expected Result**: Larger fleets, more offensive capability

### Phase 5: Lower Invasion Barriers (MEDIUM)
**Goal**: Make invasions accessible to more AI personalities

**Changes**:
1. Lower invasion planning gate: `aggression > 0.4` → `> 0.3`
2. Lower build gate: `aggression > 0.6` → `> 0.4`
3. Consider single-fleet invasions (remove 2-fleet minimum)

**Impact**: More AI types can invade
**Effort**: 15-30 minutes (threshold adjustments)
**Expected Result**: 5-10 more invasion attempts per game

### Phase 6: Act-Based War Escalation (MEDIUM)
**Goal**: Increase war frequency as game progresses

**Changes**:
1. Pass `currentAct` to Protostrator requirements
2. Lower prestige gap thresholds in Act 2/3/4
3. Act 1: -300, Act 2: -150, Act 3: -50, Act 4: 0

**Impact**: More wars declared in late game
**Effort**: 30 minutes (act-aware logic)
**Expected Result**: 6-12 wars instead of 2-4

---

## Estimated Impact on Gameplay

### After Phase 1-2 (Architecture + Diplomacy)
- Wars declared: YES (2-4 per game)
- Invasions attempted: MAYBE (if other conditions met)
- Planets changing hands: 0-3
- **Game still mostly static**

### After Phase 1-4 (+ Invasions + Budget)
- Wars declared: YES (4-8 per game)
- Invasions attempted: YES (5-15 attempts)
- Planets changing hands: 3-10
- **Moderate late-game combat**

### After All Phases
- Wars declared: YES (6-12 per game)
- Invasions attempted: YES (15-30 attempts)
- Planets changing hands: 8-20
- **Active territorial warfare throughout game**

---

## Testing Methodology

### Baseline Validation
1. Run current code (seed 12345, 40 turns)
2. Confirm: 0 wars, 0 invasions, 28/28 colonies static
3. Record: Military spending %, diplomatic status, fleet sizes

### Incremental Testing
**After each phase**:
1. Run 3 different seeds × 40 turns
2. Collect diagnostics CSV
3. Measure:
   - War declarations (turn number, count)
   - Invasion attempts (turn number, outcome)
   - Planets changed hands (owner transitions)
   - Military budget % by act
   - Final colony distribution

### Success Criteria
- **Minimum**: At least 1 war by turn 10, 3 invasions by turn 25
- **Target**: 6+ wars, 15+ invasions, 8+ planets change hands
- **Budget**: 40%+ military spending in Act 3

---

## Files Requiring Changes

### New Files (Phase 1)
- `src/ai/rba/basileus/execution.nim` - Central execution logic

### Modified Files (Phases 2-6)
1. `src/ai/rba/orders/phase3_execution.nim` - Move logic to Basileus
2. `src/ai/rba/basileus/personality.nim` - Strengthen act weights
3. `src/ai/rba/orders.nim` - Remove Act 1 invasion gate
4. `src/ai/rba/domestikos/build_requirements.nim` - Lower aggression gates
5. `src/ai/rba/protostrator/requirements.nim` - Add act-aware war logic
6. `src/ai/rba/treasurer/multi_advisor.nim` - Consider reserved budget reduction

---

## Open Questions for Further Analysis

1. **Basileus Execution Authority**: Should Basileus be able to override Treasurer budget constraints in emergencies (e.g., existential threat)?

2. **Defensive vs Offensive Priority**: Should offensive requirements get priority boost in Act 3/4 to prevent defense from consuming all military budget?

3. **Single-Fleet Invasions**: Does removing the 2-fleet requirement make invasions too easy/common?

4. **Act 1 Combat**: Should Act 1 allow ANY combat, or is peaceful expansion the design intent?

5. **Personality Distribution**: What % of AI houses should be capable of aggression > 0.4? Current distribution unknown.

6. **Target Filtering**: Are the 2:1 advantage and defenseStrength < 200 requirements too strict?

7. **Build Pipeline**: Should CST 3 requirement be lowered to CST 2 to enable earlier invasions?

---

## Conclusion

**Root Cause**: The combat system is fundamentally sound (specs, engine, tactical logic all functional), but critical execution bridges are missing or too restrictive.

**Primary Blocker**: Protostrator execution stub (50-100 lines of missing code)

**Secondary Blockers**: Act gating, weak budget prioritization, scattered execution architecture

**Recommended Path**:
1. Implement Basileus central execution architecture (establishes clean foundation)
2. Unblock diplomatic actions (enables wars)
3. Relax invasion restrictions (enables combat)
4. Strengthen wartime budget allocation (provides resources)
5. Iterate based on test results

**Estimated Total Effort**: 4-8 hours for Phases 1-4 (core functionality)

**Expected Outcome**: Transition from 0% combat to 40-60% of games showing active territorial warfare

---

**Document Status**: Analysis complete, ready for implementation planning
**Next Step**: User review and priority approval before code changes
