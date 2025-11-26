# EC4X Known Issues & Architectural Limitations

**Last Updated:** 2025-11-26

This document tracks known architectural limitations and design issues that affect game balance or AI behavior.

---

## -1. AI Early Game Paralysis

**Status:** ✅ **RESOLVED** (2025-11-26, commits d8a7e12, 7d2849d)
**Discovered:** 2025-11-26 during tactical system diagnosis
**Impact:** AI completely paralyzed in Act 1, achieving only 1 colony by Turn 7 (target: 5-8 colonies)

### Problem Description

Five critical bugs prevented AI from executing basic 4X gameplay (eXplore, eXpand, eXploit, eXterminate):

**Bug #1: ETAC Build Logic Backwards** ✅ **FIXED**
- Was: `needETACs = militaryCount < 2` (treated colonizers as military units!)
- Fixed: Act-aware logic - ALWAYS build in Act 1, opportunistic in Act 2, zero in Act 3+
- File: `src/ai/rba/orders.nim:151-157`

**Bug #2: Static Tactical Priorities Blocked Exploration** ✅ **FIXED**
- Was: "Pickup squadrons" priority blocked ALL fleets from exploring
- Fixed: Complete rewrite with phase-aware 4-act priority system
- File: `src/ai/rba/tactical.nim:521-902` (full rewrite)

**Bug #3: Scout Build Logic Misunderstood Role** ✅ **FIXED**
- Was: `needScouts = scoutCount < myColonies.len` (1 colony = 1 scout max)
- Fixed: Act-aware - minimal in Act 1 (any ship can explore!), spy-focused in Act 2+
- File: `src/ai/rba/orders.nim:160-166`

**Bug #4: ETAC Production Gate Blocked Construction** ✅ **FIXED**
- Was: Required `colony.production >= 50` to build ETACs
- Problem: Early colonies average 17-26 PP production
- Fixed: Removed production gate entirely - budget is the only limit
- File: `src/ai/rba/budget.nim:122-125`

**Bug #5: Act 2 Budget Collapse Crushed Momentum** ✅ **FIXED**
- Was: Only 20% budget allocated to expansion in Act 2
- Fixed: Increased to 35% to maintain colonization momentum
- File: `src/ai/rba/budget.nim:43`

### Solution Implemented

**Phase-Aware Tactical System:**
- Act 1 (Turns 1-7): Exploration >> Colonization >> Defense (60% expansion, 10% military)
- Act 2 (Turns 8-15): Military >> Defense >> Opportunistic Colonization (35% expansion, 30% military)
- Act 3 (Turns 16-25): Invasions >> Defense >> Combat (0% expansion, 55% military)
- Act 4 (Turns 26-30): All-in victory push (60% military)

**Key Insights:**
- ETACs are colonization ships, NOT military units
- Any ship can explore (engine auto-generates intel on fleet encounters)
- Scouts are for spying on known colonies, not exploration
- Phase-aware priorities critical for 4-act game structure
- Production gates on strategic units are dangerous

### Results

**Before Fix:**
- Turn 7: 1 colony (complete paralysis)
- Turn 15: 1 colony (zero progression)
- ETACs: 2 (never increased)

**After Fix:**
- Turn 7: 4-5 colonies ✅ (Target: 5-8)
- Turn 15: 4-6 colonies ⚠️ (Target: 10-15, needs tuning)
- ETACs: 21-43 built ✅
- **Improvement: 300-400% increase in early game expansion!**

**Testing:** 96/100 games successful in Act 1 & Act 2 tests, 0 AI collapses

### Remaining Work

**Act 2 Expansion Plateau** (Lower Priority)
- Expected: +5-7 colonies from Turn 7→15
- Actual: +1-2 colonies from Turn 7→15
- Likely causes: Budget still insufficient, ETACs not executing orders, map competition
- Recommendation: Investigate ETAC order execution, possibly increase Act 2 budget to 40-45%

### Related Commits

- **d8a7e12:** Phase-aware tactical priorities (Bugs #1-3)
- **7d2849d:** Production gate removal + Act 2 budget fix (Bugs #4-5)

---

## 0. Zero Invasions - Reconnaissance Gap

**Status:** ✅ **RESOLVED** (2025-11-25, commit 698c105)
**Discovered:** 2025-11-24 during diagnostic analysis
**Impact:** AI never attempted planetary invasions, major gameplay mechanic was non-functional

### Problem Description

The AI invasion system had THREE bugs preventing invasions:

**Bug 1: Aggression Threshold Too High** ✅ **FIXED** (2025-11-24)
- Was: `p.aggression > 0.5` (only Aggressive strategy could invade)
- Fixed: `p.aggression >= 0.4` (Balanced strategy can invade too)

**Bug 2: Defense Logic Inverted** ✅ **FIXED** (2025-11-24)
- Was: `defenseStrength > 150` (only invade STRONG targets!)
- Fixed: `defenseStrength < 200` (invade WEAK/MODERATE targets)

**Bug 3: Intelligence Reports Not Used for Targeting** ✅ **FIXED** (2025-11-25, commit 698c105)
- **Root Cause:** `identifyVulnerableTargets()` only checked `filtered.visibleColonies`
- Intelligence reports from scouts/combat/surveillance were ignored
- Even with intel database populated, AI couldn't target intel-only colonies for invasion
- **Fix:** Modified `identifyVulnerableTargets()` to include colonies from `filtered.ownHouse.intelligence.colonyReports`

### Solution Implemented

**File:** `src/ai/rba/tactical.nim` (lines 327-357)

```nim
proc identifyVulnerableTargets*(controller: var AIController, filtered: FilteredGameState): seq[...] =
  ## USES INTELLIGENCE REPORTS: Includes colonies from intelligence database, not just visible
  result = @[]
  var addedSystems: seq[SystemId] = @[]

  # Add currently visible colonies
  for visCol in filtered.visibleColonies:
    if visCol.owner == controller.houseId:
      continue
    let strength = controller.assessRelativeStrength(filtered, visCol.owner)
    result.add((visCol.systemId, visCol.owner, strength))
    addedSystems.add(visCol.systemId)

  # Add colonies from intelligence database (even if not currently visible)
  for systemId, report in filtered.ownHouse.intelligence.colonyReports:
    if report.targetOwner == controller.houseId:
      continue
    if systemId in addedSystems:
      continue
    let strength = controller.assessRelativeStrength(filtered, report.targetOwner)
    result.add((systemId, report.targetOwner, strength))
    addedSystems.add(systemId)
```

### Results

**Before Fix:**
- 0 invasions in 7-turn test (20 games)
- Intelligence database populated but unused for targeting

**After Fix:**
- 95 invasions in 7-turn test (20 games)
- AI now properly utilizes scout/combat/surveillance intel for invasion targeting
- All 96 games in Act 2 test completed with 0 collapses

### Related Commits

- **698c105:** Enable invasion targeting via intelligence reports
- **c79b78b:** Include ETACs in transport diagnostic counting
- **cdbbde5:** Fix transport/fighter commissioning persistence

---

## 1. Build Queue Single-Threading Bottleneck

**Status:** 🔴 **Known Limitation** - Requires architectural refactor
**Discovered:** 2025-11-24 during Phase 2c scout/fighter diagnostic testing
**Impact:** Prevents AI from reaching optimal scout/fighter production targets

### Problem Description

The current build queue system in `tests/balance/ai_controller.nim` uses a **single-threaded priority queue per colony**:

```nim
# Priority 4: Builder Construction (ETACs)
if needBuilder and house.treasury > builderCost:
  result.add(...)
  break  # ← BOTTLENECK: Only 1 build per colony per turn

# Priority 5: Defense Construction
if needDefense and house.treasury > defenseCost:
  result.add(...)
  break  # ← BOTTLENECK

# Priority 6: Military Construction
if needMilitary and house.treasury > militaryCost:
  result.add(...)
  break  # ← BOTTLENECK

# Priority 7: Scout/Fighter Construction
if needScouts and house.treasury > scoutCost:
  result.add(...)
  break  # ← BOTTLENECK
```

**Result:** Only 1 unit can be built per colony per turn, regardless of production capacity.

### Impact on Balance

| Unit Type | Target | Actual (30 turns) | Gap |
|-----------|--------|-------------------|-----|
| Scouts    | 5-7    | 2-4               | -60% |
| Fighters  | 8+     | 0                 | -100% |

**Root Cause:** Higher priority builds (ETACs, defenses, military) dominate the queue. Scouts and fighters grow at ~1/turn maximum **across ALL colonies**, not per-colony.

### Diagnostic Evidence

From 50-game diagnostic batch (30 turns each):
- Average scouts: 2.3 (was 2.7 before threshold lowering)
- Average fighters: 0.0 (despite adding fighter build logic)
- Even after aggressively lowering thresholds:
  - Scout: techPriority 0.4→0.3, aggression 0.4→0.3
  - Fighter: aggression 0.4→0.3, treasury 80→60 PP
  - Removed military count requirements

**Conclusion:** The build conditions are correct, but the queue architecture prevents execution.

---

## Proposed Solution: Capacity-Based Multi-Build System

### Design Goals

1. Allow **multiple builds per turn** per colony
2. Limit builds by **production capacity** instead of arbitrary "one and break"
3. Maintain priority system for resource allocation
4. Preserve existing balance for high-priority builds

### Proposed Architecture

```nim
type
  BuildCapacity = object
    availablePP: int          # Colony's production + treasury contribution
    buildsThisTurn: int       # Number of builds queued
    maxBuilds: int            # Based on colony production (e.g., production / 20)

proc calculateBuildCapacity(colony: Colony, house: House): BuildCapacity =
  ## Calculate how many builds this colony can afford this turn
  let productionBudget = colony.production
  let treasuryContribution = min(house.treasury div 10, productionBudget)

  result.availablePP = productionBudget + treasuryContribution
  result.maxBuilds = max(1, colony.production div 20)  # 1 build per 20 PP production
  result.buildsThisTurn = 0

proc canAffordBuild(capacity: var BuildCapacity, cost: int): bool =
  ## Check if colony can afford another build this turn
  if capacity.buildsThisTurn >= capacity.maxBuilds:
    return false
  if capacity.availablePP < cost:
    return false

  capacity.availablePP -= cost
  capacity.buildsThisTurn += 1
  return true
```

### Modified Build Logic

```nim
proc generateBuildOrders(state: FilteredGameState, p: AIPersonality): seq[BuildOrder] =
  result = @[]

  for colony in state.visibleColonies:
    if colony.details.isNone or colony.owner != state.viewingHouse:
      continue

    var capacity = calculateBuildCapacity(colony.details.get(), state.houses[state.viewingHouse])

    # Priority 4: Builders (highest priority)
    if needBuilder and capacity.canAffordBuild(builderCost):
      result.add(...)
      # NO BREAK - continue to next priority

    # Priority 5: Defense
    if needDefense and capacity.canAffordBuild(defenseCost):
      result.add(...)
      # NO BREAK

    # Priority 6: Military
    if needMilitary and capacity.canAffordBuild(militaryCost):
      result.add(...)
      # NO BREAK

    # Priority 7: Scouts/Fighters (now can execute if capacity remains)
    if needScouts and capacity.canAffordBuild(scoutCost):
      result.add(...)
      # NO BREAK

    if needFighters and capacity.canAffordBuild(fighterCost):
      result.add(...)
```

### Expected Results

With this refactor:
- High-production colonies (50+ PP) could build 2-3 units/turn
- Low-production colonies (10-20 PP) build 1 unit/turn (unchanged)
- Priority system still respected (builders/defense first)
- Scouts/fighters can be built **in addition to** higher-priority builds
- Natural resource constraint (can't build more than production allows)

**Estimated Impact:**
- Scouts: 2-4 → 5-7 (target achieved)
- Fighters: 0 → 4-8 (depends on aggression)

---

## Implementation Plan

### Phase 1: Design Validation (1-2 hours)
1. Create `tests/balance/test_build_capacity.nim`
2. Unit test capacity calculation logic
3. Validate build limit formulas (production / 20? production / 30?)
4. Test resource depletion edge cases

### Phase 2: Refactor Build Logic (2-3 hours)
1. Add `BuildCapacity` type to ai_controller.nim
2. Implement `calculateBuildCapacity()` and `canAffordBuild()`
3. Remove all `break` statements from build priority checks
4. Replace treasury checks with capacity checks

### Phase 3: Balance Testing (1-2 hours)
1. Run 50-game diagnostic batch
2. Analyze scout/fighter production rates
3. Check for economic impacts (treasury depletion?)
4. Validate high-priority builds still execute (ETACs, defense)

### Phase 4: Tuning (1 hour)
1. Adjust build limit formula if needed (production / 15? / 25?)
2. Fine-tune treasury contribution limits
3. Re-test and validate targets achieved

**Total Estimated Effort:** 5-8 hours

---

## Alternative Approaches Considered

### Option A: Parallel Build Queues
**Idea:** Separate queues for economic, military, and intel builds
**Pros:** Clean separation of concerns
**Cons:** More complex, harder to balance resource allocation
**Verdict:** Too complex for current needs

### Option B: Remove Lower-Priority Breaks Only
**Idea:** Keep breaks for high-priority builds, remove for scouts/fighters
**Pros:** Minimal code change
**Cons:** Doesn't solve underlying capacity issue, scouts/fighters compete with each other
**Verdict:** Band-aid fix, doesn't scale

### Option C: Increase Scout/Fighter Priority
**Idea:** Move scouts/fighters higher in priority queue
**Pros:** Zero code change to build system
**Cons:** Breaks strategic balance (scouts before defense? fighters before military?)
**Verdict:** Wrong approach, priority order is correct

---

## References

- **Session Summary:** `/tmp/session_summary.md`
- **Diagnostic Analysis:** `tests/balance/analyze_phase2_gaps.py`
- **AI Controller:** `tests/balance/ai_controller.nim:2390-2650` (build order generation)
- **Phase 2c Completion:** `docs/TODO.md` (Scout Operational Modes)

---

## Notes

This limitation was discovered through systematic diagnostic testing:
1. Added scout_count metric to diagnostics
2. Ran 50-game batch with 30 turns each
3. Observed 2.3 average scouts (target: 5-7)
4. Lowered build thresholds aggressively → no change
5. Investigated code → discovered `break` statements
6. Confirmed architectural bottleneck

The build conditions themselves are correct. The issue is purely architectural - the single-threaded queue prevents proper execution of valid build decisions.
