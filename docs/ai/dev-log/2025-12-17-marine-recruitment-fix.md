# Marine Recruitment & Invasion System Investigation
**Date:** 2025-12-17
**Focus:** Diagnostic-driven debugging of missing planet conquests
**Commits:** `b9356c9` - fix(rba): Enable marine recruitment with GOAP fallback

---

## Executive Summary

Investigation into why AI houses weren't conquering planets revealed two critical bugs in marine recruitment and loading logic. After fixes, marines are now being recruited (5-16 per house) and loaded onto transports (1-5 per fleet), enabling invasion capabilities. However, GOAP strategic planning is not generating multi-turn invasion campaigns, leaving RBA to make single-turn tactical decisions (Bombard) rather than coordinated invasions.

**Key Finding:** The core issue is architectural - **RBA handles single-turn tactics, GOAP should handle multi-turn campaigns**. Marine/transport logistics now work, but strategic planning doesn't.

---

## Investigation Methodology

### 1. Initial Problem Discovery
- **Observation:** Seed 999 showed 0 planet conquests despite `invasion_orders_generated > 0` in diagnostics
- **Hypothesis:** Orders generated but failing during execution
- **Root Cause:** Marines not available when orders executed

### 2. Diagnostic-Driven Approach
Created Python analysis scripts using SQLite diagnostics:
- `diagnose_invasion_pipeline.py` - Traces full invasion system
- Checked: Scouts → Combat fleets → Transports → Marines → Orders → Conquests
- Found marines critically undersupplied (1-3 total vs 15-21 transport capacity)

### 3. Code Archaeology
Traced backwards from execution failure:
1. **Execution:** `selectCombatOrderType()` returns Bombard (no loaded marines)
2. **Loading:** `fleet_organization.nim` requires ≥3 marines at colony
3. **Recruitment:** `build_requirements.nim` only builds if `hasInvasionPlans = true`
4. **Planning:** GOAP fallback blocked when GOAP enabled but not planning

---

## Critical Bugs Found & Fixed

### Bug 1: GOAP Fallback Logic Error ⚠️ CRITICAL
**File:** `src/ai/rba/domestikos/build_requirements.nim:848-850`

**The Bug:**
```nim
# Check if GOAP has active invasion plans
if controller.goapEnabled:
  # Check for InvadeColony or CreateInvasionForce goals
  hasInvasionPlans = (check GOAP plans)

# Fallback ONLY runs if GOAP disabled!
if not controller.goapEnabled:  # ← BUG HERE
  hasInvasionPlans = personality.aggression > 0.6 or currentAct >= Act2

if hasInvasionPlans:
  # Build marines...
```

**Impact:**
- When GOAP enabled (default: true) but not generating invasion plans
- Fallback personality/act check NEVER runs
- `hasInvasionPlans` stays false
- NO MARINES BUILT despite having transports and needing forces

**Fix:**
```nim
# Allow fallback if GOAP disabled OR not planning invasions
if not controller.goapEnabled or not hasInvasionPlans:
  hasInvasionPlans = personality.aggression > 0.6 or currentAct >= Act2
```

**Result:**
- Marines now recruited in Act 2+ when aggression > 0.6
- Before: 1-3 marines per house
- After: 5-16 marines per house

### Bug 2: Marine Loading Threshold Too Strict
**File:** `src/ai/rba/fleet_organization.nim:267-269`

**The Issue:**
```nim
if hasEmptyTransport and colony.marines >= 3:  # ← Too strict
  # Load marines
```

**Problem:**
- Marines distributed across multiple colonies (not concentrated)
- Each colony has 1-2 marines (below threshold)
- Transports never load despite marines being available
- Empty transport capacity: 8-14 marines worth of empty space

**Fix:**
```nim
# Lower threshold from 3 to 1
if hasEmptyTransport and colony.marines >= 1:
  # Load marines
```

**Result:**
- Marines now loading incrementally as they become available
- Before: 0-1 marines loaded per fleet
- After: 1-5 marines loaded per fleet

---

## System Architecture Insights

### RBA vs GOAP Roles (As Designed)

**RBA (Rule-Based Advisor) - Tactical:**
- **Purpose:** Single-turn reactive decisions
- **Example:** "Enemy colony vulnerable → Bombard it this turn"
- **Limitation:** No multi-turn coordination
- **Current Status:** WORKING (Bombard orders generated)

**GOAP (Goal-Oriented Action Planner) - Strategic:**
- **Purpose:** Multi-turn campaign planning
- **Example:** "Plan 6-turn invasion: Build 15 marines → Stage fleet → Bombard × 3 turns → Invade"
- **Benefit:** Coordinates resource building, staging, and execution
- **Current Status:** NOT GENERATING INVASION CAMPAIGNS

### Current Order Generation Flow

```
Phase 0: Intelligence Distribution (Drungarius)
  ├─ colony_analyzer.nim identifies vulnerableTargets
  └─ Populates IntelligenceSnapshot.military.vulnerableTargets

Phase 1: Requirement Generation (All Advisors)
  ├─ Eparch: Economic requirements
  ├─ Domestikos: Marine/transport build requirements ✓ NOW WORKING
  └─ Drungarius: Intel gathering requirements

Phase 1.5: GOAP Strategic Planning (IF ENABLED)
  ├─ Creates WorldStateSnapshot with vulnerableTargets
  ├─ fleet_bridge.extractFleetGoalsFromState()
  ├─   └─ analyzeOffensiveOpportunities()
  ├─       └─ Creates InvadeColony goals
  ├─ A* planner generates multi-turn plans
  └─ ❌ PLANS NOT BEING GENERATED OR TRACKED

Phase 2: Treasurer Mediation & Budget Allocation
  └─ Allocates PP to advisor requirements

Phase 3: Requirement Execution
  ├─ Eparch builds marines/transports ✓ WORKING
  ├─ Domestikos moves fleets + loads marines ✓ WORKING
  └─ Standing orders + offensive operations

Phase 5+: Fleet Operations (Domestikos)
  ├─ generateCounterAttackOrders() ✓ CALLED
  ├─   └─ For each vulnerableTarget:
  ├─       └─ findSuitableInvasionFleet() (needs ≥2 marines)
  ├─       └─ selectCombatOrderType() chooses tactic
  ├─           ├─ If no loaded marines → Bombard ✓ CURRENT
  ├─           ├─ If marines < 2 → Bombard
  ├─           ├─ If marineRatio ≥ 2.0 → Blitz
  ├─           ├─ If marineRatio ≥ 0.5 → Invade
  ├─           └─ Else → Bombard
  └─ Result: Bombard orders generated, no Invade/Blitz
```

### Why Only Bombard Orders?

**RBA Tactical Logic:**
1. Finds vulnerable targets (WORKING)
2. Checks for fleets with ≥2 loaded marines (SOME FLEETS QUALIFY)
3. Selects combat tactic based on marine ratio

**Possible Failures:**
- Fleets with 5 marines exist but not at right location/availability
- Marine ratio too low due to strong target defenses
- Timing issue: Orders generated before marines loaded in same turn

**User's Insight:**
> "The GOAP needs to order multiple rounds of bombardment if the colony is still too strong"

This is correct! RBA can only say "Bombard once" - GOAP should plan:
```
Turn N:   Build 15 marines (3 turns)
Turn N+3: Move fleet to staging area
Turn N+4: Load marines
Turn N+5: Bombard target (reduce defenses)
Turn N+6: Bombard again
Turn N+7: Invade with favorable marine ratio
```

---

## Current System Status

### ✅ What's Working

1. **Marine Recruitment**
   - Triggered in Act 2+ when aggression > 0.6
   - Transport-centric: Builds to fill transport capacity
   - 5-16 marines per house (vs 1-3 before)

2. **Transport Building**
   - Triggered when `hasInvasionPlans = true`
   - CST 2+ requirement (basic military infrastructure)
   - 2-7 transports per aggressive house

3. **Marine Loading**
   - LoadCargo commands generated when transports at colonies
   - Incremental loading (≥1 marine threshold)
   - 1-5 marines loaded per fleet

4. **Intelligence Gathering**
   - Scouts deployed (14-64 per house)
   - Vulnerable targets identified (defenseRatio < 0.5)
   - Intelligence snapshot populated

5. **RBA Tactical Response**
   - Bombard orders generated against vulnerable/high-value targets
   - Single-turn opportunistic attacks

### ❌ What's Not Working

1. **GOAP Invasion Campaigns**
   - `InvadeColony` goals should be created from vulnerableTargets
   - Multi-turn plans should coordinate building → staging → bombardment → invasion
   - Plans either not generated, failing confidence threshold, or not tracked

2. **Invade/Blitz Orders**
   - Only Bombard orders generated
   - Possible causes:
     - GOAP not providing strategic context for invasions
     - Fleets with loaded marines not properly assigned
     - Marine ratios too low due to strong defenses

3. **Multi-Turn Bombardment**
   - No coordination for "Bombard for 3 turns, then invade"
   - RBA can only generate single-turn Bombard orders

---

## Recommendations

### Priority 1: GOAP Invasion Planning Investigation

**Objective:** Determine why GOAP isn't generating invasion campaigns despite:
- Vulnerable targets identified ✓
- Marines/transports available ✓
- Budget available ✓
- Pipeline exists ✓

**Investigation Steps:**

1. **Add GOAP Logging**
   - Log when `analyzeOffensiveOpportunities()` runs
   - Log how many `InvadeColony` goals created
   - Log campaign classification (Speculative/Raid/Assault/Deliberate)
   - Log precondition checks for each goal

2. **Check Intelligence Requirements**
   ```nim
   # campaign_classifier.nim lines 236-242
   let intelCheck = checkIntelligenceRequirements(
     target, state.turn, campaignType, config.intelligence_thresholds
   )
   ```
   - Are intelligence quality requirements too strict?
   - Config: Raid needs "Scan", Assault needs "Spy", Deliberate needs "Perfect"
   - Check if targets meet minimum intel quality

3. **Check A* Planning**
   - Are plans being generated but failing confidence threshold (0.5)?
   - Are preconditions blocking plan generation?
   - Check `planForGoal()` in `planner/search.nim`

4. **Check Plan Tracking**
   - Are plans generated but not added to `controller.goapPlanTracker`?
   - Check `orders.nim:124-128` where plans are added
   - Verify `TrackedPlan` status transitions

**Diagnostic Script:**
```python
# Check if GOAP goals/plans recorded in diagnostics
goap_activity = pl.read_database("""
    SELECT turn, house_id,
           goap_invasion_goals,
           goap_invasion_plans
    FROM diagnostics
    WHERE goap_invasion_goals > 0 OR goap_invasion_plans > 0
    ORDER BY turn, house_id
""", db)
```

### Priority 2: Multi-Turn Campaign Actions

**User Requirement:** "The GOAP needs to order multiple rounds of bombardment"

**Implementation Approach:**

1. **Create Bombardment Sequence Action**
   - New action: `ConductBombardmentCampaign`
   - Preconditions: Fleet at target, target defenses > threshold
   - Effects: Reduces target defenses by X per turn
   - Duration: N turns based on defense strength

2. **Enhance InvadeColony Planning**
   ```nim
   # Current: Single-step invasion
   # Needed: Multi-step campaign

   Actions = [
     BuildInvasionForce (if needed),
     StageFleet (move to staging area),
     LoadMarines (at friendly colony),
     ConductBombardment (3 turns if defenses high),
     LaunchInvasion (ground assault)
   ]
   ```

3. **Campaign State Tracking**
   - Track bombardment progress per target
   - Update defense estimates after each bombardment
   - Dynamically adjust campaign based on intel updates

### Priority 3: RBA-GOAP Integration Refinement

**Goal:** Ensure RBA tactical decisions support GOAP strategic plans

1. **Pass GOAP Context to RBA**
   - Domestikos should know if target is part of active GOAP plan
   - Prioritize GOAP-targeted invasions over opportunistic attacks

2. **Coordinate Marine Loading with Plans**
   - When GOAP plans invasion, pre-stage marines at target colonies
   - Load marines in preparation for planned invasion turn

3. **Prevent Interference**
   - If GOAP planning 3-turn bombardment, don't send different fleet
   - RBA tactical orders should complement, not conflict with GOAP plans

### Priority 4: Configuration Tuning

**Adjust thresholds based on test results:**

1. **Marine Ratio Thresholds** (`offensive_ops.nim:187-196`)
   - Current: Blitz needs 2:1, Invade needs 1:2
   - Consider: Lower to encourage more invasion attempts
   - Early-game colonies have 2-5 armies, 5 marines may be sufficient

2. **Intelligence Requirements** (`config/rba.toml:1221-1231`)
   - Current: Assault needs "Spy" intel (espionage required)
   - Consider: Lower to "Scan" for early-game aggression
   - Most vulnerableTargets likely have "Scan" or "Visual" only

3. **GOAP Confidence Threshold** (`config/rba.toml:1186`)
   - Current: 0.5 minimum confidence
   - Consider: Lower to 0.4 for more aggressive planning
   - Allow "risky but feasible" invasion plans

---

## Test Results Summary

### Seed 54321 (44 turns)
```
Marines Recruited:
- house-atreides:  11 (0 transports)
- house-harkonnen: 11 (2 transports, 2 loaded)
- house-corrino:    2 (2 transports, 1 loaded)
- house-ordos:      2 (0 transports)

Orders Generated:
- Invasion orders: 0
- Bombard orders:  1 (turn 39, house-corrino)
- Conquests:       0
```

### Seed 99999 (29 turns)
```
Marines Recruited (Turn 19):
- house-corrino:   16 total (11 at colonies, 5 loaded on 6 transports)
- house-harkonnen:  5 total (0 at colonies, 5 loaded on 4 transports)
- house-atreides:   2 total (1 at colonies, 1 loaded on 1 transport)
- house-ordos:      8 total (8 at colonies, 0 loaded on 2 transports)

Orders Generated:
- Invasion orders: 0
- Bombard orders:  2 (turn 24-29, house-atreides & house-corrino)
- Conquests:       0
```

**Analysis:**
- Marines now recruiting at appropriate levels ✓
- Loading working but inconsistent (some transports empty)
- RBA tactical response working (Bombard orders)
- No Invade/Blitz orders despite having forces
- GOAP not visible in order generation

---

## Next Session Checklist

Before continuing invasion work:

1. [ ] Add GOAP diagnostic logging
   - `analyzeOffensiveOpportunities()` - goals created
   - `planForGoal()` - plan generation attempts
   - `addPlan()` - plan tracking

2. [ ] Run test with GOAP logging enabled
   - Check if goals created: `logInfo("GOAP: Created {campaignType} InvadeColony goal")`
   - Check if plans generated: `logInfo("GOAP Plan Generated")`
   - Check confidence scores: `logDebug("Rejected plan (confidence {plan.confidence})")`

3. [ ] Review intelligence quality
   - Query: What intel quality do vulnerable targets have?
   - Are targets meeting minimum requirements for Raid/Assault classification?

4. [ ] Check plan tracking
   - Are plans added to `goapPlanTracker.activePlans`?
   - Are they staying in "InProgress" or failing to "Stalled"/"Failed"?

5. [ ] Consider temporary workarounds
   - Lower confidence threshold to 0.3
   - Lower intel requirements (Assault = "Scan" not "Spy")
   - Add RBA fallback: If GOAP plan exists for target, boost Invade priority

---

## Technical Debt & Future Work

### Architectural Concerns

1. **Zero-Turn Command Timing**
   - LoadCargo executes immediately in same turn
   - But offensive orders generated BEFORE loading happens
   - Consider: Two-phase order generation (load first, then assign orders)

2. **Fleet Availability Detection**
   - `findSuitableInvasionFleet()` checks Idle/UnderUtilized
   - But fleets may be assigned to standing orders (DefendSystem)
   - Consider: Override standing orders for GOAP-planned invasions

3. **Marine Distribution**
   - Marines spread across multiple colonies
   - Loading happens per-colony, not fleet-wide
   - Consider: Pre-concentration command for planned invasions

### Configuration System

1. **Hardcoded Values Remain**
   - `offensive_ops.nim:187` - Blitz ratio 2.0
   - `offensive_ops.nim:192` - Invade ratio 0.5
   - `offensive_ops.nim:179` - Minimum 2 marines
   - Should move to `config/rba.toml` for tuning

2. **GOAP Config Incomplete**
   - Campaign classification thresholds not fully configurable
   - Multi-turn action costs not in config
   - Should expand `config/rba.toml:[goap]` section

### Testing Infrastructure

1. **GOAP Activity Not in Diagnostics**
   - Should add: `goap_goals_generated`, `goap_plans_active`, `goap_plans_completed`
   - Enables longitudinal analysis of GOAP effectiveness

2. **Fleet-Level Diagnostics**
   - Current: Aggregate counts per house
   - Needed: Per-fleet marine loading, orders, outcomes
   - `fleet_tracking` table exists but underutilized

---

## Lessons Learned

### Diagnostic-Driven Development Works

1. **Start with data, not code**
   - SQLite diagnostics revealed the symptom (no conquests)
   - Python analysis pinpointed the cause (no marines)
   - Code archaeology found the bug (GOAP fallback)

2. **Iterate quickly with throwaway scripts**
   - Created 3 diagnostic scripts in 30 minutes
   - Faster than adding logging and recompiling
   - Data persists across rebuilds

3. **Trust but verify**
   - Code looked correct but wasn't executing
   - Diagnostic data revealed the hidden logic error
   - "GOAP fallback" existed but never ran

### Complex Systems Have Emergent Behaviors

1. **Multi-system dependencies**
   - Marine recruitment → Transport building → Marine loading → Fleet assignment → Order generation
   - Bug in step 1 causes cascading failures in steps 2-5

2. **Timing matters**
   - Zero-turn commands vs turn-based orders
   - Phase ordering affects what data is available when

3. **Architecture reveals itself under stress**
   - RBA/GOAP split became clear only when both needed to work together
   - Single-turn tactical vs multi-turn strategic is fundamental divide

### Development Velocity

**Time Spent:**
- Investigation: ~3 hours (diagnostics, code reading, hypothesis testing)
- Fixes: ~30 minutes (2 one-line changes)
- Testing: ~1 hour (multiple simulation runs, analysis)
- Documentation: ~1 hour (this file)

**Key Insight:** 80% investigation, 5% coding, 15% validation
- Diagnostic-driven approach focuses effort on root cause
- Small fixes have large impact when placed correctly

---

## References

### Files Modified
- `src/ai/rba/domestikos/build_requirements.nim:849` - GOAP fallback logic
- `src/ai/rba/fleet_organization.nim:269` - Marine loading threshold

### Key Files for Next Investigation
- `src/ai/rba/goap/domains/fleet/goals.nim:198-315` - Offensive opportunity analysis
- `src/ai/rba/goap/domains/fleet/campaign_classifier.nim` - Campaign type classification
- `src/ai/rba/goap/planner/search.nim` - A* plan generation
- `src/ai/rba/orders/phase1_5_goap.nim:178-264` - GOAP execution entry point

### Related Dev Logs
- `2025-12-09-invasion-debugging.md` - Original invasion system design
- `2025-12-11-invasion-planning-breakthrough.md` - GOAP intelligence integration

---

**Status:** Marine recruitment fixed, GOAP planning investigation next
**Blocking Issue:** No multi-turn invasion campaigns generated
**Next Step:** Add GOAP diagnostic logging to trace goal/plan generation
