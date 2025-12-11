# Hoarding Investigation & Partial Fix

**Date:** 2025-12-10
**Issue:** Houses accumulating 50k-160k+ PP in treasury instead of spending on military buildup
**Status:** Partially resolved - early/mid game fixed, late game still needs work

---

## Initial Problem

Game analysis showed massive hoarding at turn 45:
```
house-corrino: 162,636 PP unspent
house-atreides: 86,576 PP unspent
house-harkonnen: 47,514 PP unspent
house-ordos: 36,002 PP unspent
```

Despite having:
- 205 total ships
- 26 marines
- Zero conquests (all expansion via peaceful ETAC colonization)

**User Goal:** Fix hoarding so houses can build large fleets capable of invasions

---

## Investigation Process

### 1. Initial Diagnosis - Zero Invasions

First investigated why no invasions were happening. Traced the flow:

```
Reconnaissance → Intel gathering → Vulnerable targets → Attack orders → Combat
```

**Finding:** Houses had NO reconnaissance system for Act 2+, resulting in:
- Act 1: `generateExplorationOrders` for initial exploration ✓
- Act 2+: **NO ongoing reconnaissance** ✗
- Result: `intelligence.colonyReports` empty → no vulnerable targets → no invasions

**Fix Implemented:** Added `generateReconnaissanceOrders()` to `exploration_ops.nim`:
- Identifies enemy colonies with stale intel (>5 turns old)
- Finds idle/underutilized scout-capable fleets
- Prioritizes targets by value × staleness
- Allocates 1-6 scouts based on personality (aggression + expansionDrive)
- Uses `ViewWorld` order type (safer deep-space scan)
- Wired into both `MergeForCombat` (Act 2) and `MaintainFormations` (Act 3+) strategies

**Location:** `src/ai/rba/domestikos/exploration_ops.nim:70-188`

### 2. Combat Order Selection Issue

Found that even with reconnaissance working, houses generated **Bombard** orders instead of **Invade/Blitz**, resulting in zero conquests.

**Root Cause:** `selectCombatOrderType` logic (`offensive_ops.nim:265-323`):
```nim
elif defenseStrength <= 5 and shipCount >= 2:
  # Moderate defenses → Bombard first to soften
  return FleetOrderType.Bombard
```

**Problem Chain:**
1. Most colonies have `defenseStrength > 2` (ground batteries)
2. AI chooses Bombard to "soften defenses first"
3. Bombardment ineffective (not enough capital ships to destroy batteries)
4. AI never follows up with invasion
5. Creates infinite loop: bombardments happen but no conquests

**User Insight:** "houses have a lot of ground batteries but not enough capital ships to pound them"

This revealed the REAL problem: houses can't build enough capital ships because of **hoarding**.

### 3. Budget Flow Analysis

Traced the budget allocation chain to understand hoarding:

```
Treasury → Requirements Generation → Budget Allocation → Spending
```

**Test Case (Turn 45 before fixes):**
```
Treasury: 52,740 PP available
Requirements: 16 build requirements (total: 1,225 PP)
Budget allocated: 3,125 PP (6% utilization!)
Military budget: 4,688 PP (99% exhausted, 25+ unfulfilled requirements)
Defense budget: 3,907 PP (16% utilized, 3,247 PP wasted!)
```

**Finding:** Only 6% of available treasury being utilized, with Military exhausted trying to fulfill requirements but Defense budget massively wasted.

### 4. Root Cause - Backward Capacity Filler Logic

Found the bug in `build_requirements.nim:1527-1532`:

```nim
let affordableFillerCount = if treasury > 5000:
    0  # HOARDING: Fix budget allocation, don't generate filler spam
  elif treasury > 1000:
    availableDocks div 2  # MODERATE: Generate some fillers
  else:
    availableDocks  # LOW TREASURY: Generate all fillers
```

**This logic was BACKWARDS!**

When treasury > 5000PP, it generated **ZERO** capacity fillers, creating a chicken-and-egg problem:

1. Treasury grows to 52k+ PP
2. Build requirements sees treasury > 5000PP
3. Generates **ZERO** capacity fillers ("fix budget allocation first")
4. Only generates 16 requirements worth 1,225PP
5. Budget allocator has nothing to spend money on
6. Treasury keeps growing
7. **Infinite hoarding loop**

---

## Fix Implemented

**File:** `src/ai/rba/domestikos/build_requirements.nim:1517-1520`

**Before:**
```nim
let affordableFillerCount = if treasury > 5000:
    0  # HOARDING: Fix budget allocation, don't generate filler spam
  elif treasury > 1000:
    availableDocks div 2
  else:
    availableDocks
```

**After:**
```nim
# Generate capacity fillers for all available docks
# The budget allocator will naturally limit spending based on available budget
# Generating requirements doesn't commit spending - it just gives options
let treasury = filtered.ownHouse.treasury
let affordableFillerCount = availableDocks
```

**Rationale:** Removed arbitrary treasury-based gating. The budget allocator will naturally limit spending. Generating requirements doesn't commit spending - it just provides options for the mediation system.

---

## Results

### Early/Mid Game (Act 2, Turn 15)

**BEFORE:**
- Treasury: 52k PP
- Generated: 16 requirements (1,225 PP)
- Budget allocated: 3,125 PP (6% utilization)

**AFTER:**
- Treasury: 4,110 PP
- Generated: 93 requirements (152 capacity fillers!)
- Budget allocated: 3,905 PP (95% utilization!)

### Late Game (Act 4, Turn 40)

**Test Results:**
- Treasury: 131,637 PP
- Generated: 125+ requirements (110+ capacity fillers)
- Budget allocated: 44,417 PP (34% utilization)

**Analysis:** Fix works in early/mid game but breaks down in late game.

---

## Remaining Issues

### Late Game Hoarding Persists

Game 22222 (45 turns with fix):
```
house-ordos: 58,853 PP unspent
house-corrino: 46,082 PP unspent
house-atreides: 38,042 PP unspent
house-harkonnen: 40,005 PP unspent
```

**Better than before** (was 160k max) but still significant.

### Root Causes Identified

1. **Budget Allocation Limitation**
   - Mediation uses 99% of *allocated* budget
   - But allocated budget is only 34% of treasury in late game
   - Requirements ARE being generated (125+ requirements)
   - Budget system not allocating enough of available treasury

2. **Requirement Fulfillment Rate**
   ```
   Mediation: fulfilled 40/157 requirements (25%)
   Budget: allocated 5466/5474PP (99.9%)
   ```
   - Mediation exhausts budget fulfilling only 25% of requirements
   - Requirements too expensive relative to allocated budget
   - High-priority requirements consume budget before lower-priority ones

3. **Income vs Spending Capacity**
   - As houses expand (12 colonies for corrino), income grows exponentially
   - Construction capacity doesn't scale proportionally
   - Build rate: 1.4-2.4 ships/turn (reasonable but not enough)
   - Can't spend fast enough to keep up with income growth

---

## Technical Details

### Files Modified

1. **exploration_ops.nim** - Added reconnaissance system
   - `generateReconnaissanceOrders()` proc (120 lines)
   - Lines 70-188

2. **domestikos.nim** - Wired reconnaissance into strategies
   - Act 2 `MergeForCombat`: lines 191-194
   - Act 3+ `MaintainFormations`: lines 220-223

3. **build_requirements.nim** - Fixed capacity filler generation
   - Removed treasury-based gating logic
   - Lines 1517-1520

### Budget Flow Chain

```
calculateProjectedTreasury(filtered)
  ↓ (returns current + income - maintenance)
allocateBudgetMultiAdvisor(projectedTreasury)
  ↓ (reserves 15%, mediates remaining 85%)
mediateRequirements(effectiveBudgetForMediation)
  ↓ (allocates to requirements in priority order)
generateBuildOrdersWithBudget(allocation.budgets[Domestikos])
  ↓ (creates actual build orders)
```

**Issue:** Even with full treasury passed through, only ~34-40% ends up allocated in late game.

### Mediation Behavior

From `basileus/mediation.nim:266-296`:
```nim
for weightedReq in weightedReqs:
  if req.estimatedCost <= remainingBudget:
    # Fulfill requirement
    remainingBudget -= req.estimatedCost
  else:
    # Cannot afford - add to unfulfilled list
```

Works correctly but exhausts budget on expensive high-priority requirements before reaching cheaper capacity fillers.

---

## Additional Findings

### Conquest Blockers (Separate from Hoarding)

Even with large fleets built, conquests still fail due to:

1. **Combat Order Selection** - Chooses Bombard for defended colonies
2. **Bombardment Ineffectiveness** - Ground batteries survive bombardments
3. **No Follow-up Logic** - No invasion after bombardment weakens defenses

**Location:** `offensive_ops.nim:265-323` - `selectCombatOrderType()`

### Reconnaissance Success

The reconnaissance system IS working correctly:
- Scouts being built for reconnaissance missions
- ViewWorld orders generated successfully
- Intelligence reports being gathered
- "Assigned 1 scouts for reconnaissance (1 stale intel targets)" messages visible

**Example Log:**
```
[23:27:19] [INFO] [AI] house-atreides Domestikos: Reconnaissance - fleet
house-atreides_fleet_10_23 → 31 (house-ordos, no intel)
[23:27:19] [INFO] [AI] house-atreides Domestikos: Assigned 1 scouts for
reconnaissance (1 stale intel targets)
```

---

## Next Steps

### Option 1: Fix Late Game Budget Allocation

Investigate why only 34% of treasury gets allocated in Act 4:
- Check if there's a hidden spending cap
- Review mediation priority queue construction
- Possibly increase budget passed to mediation beyond 85%
- Consider act-aware budget multipliers (more aggressive in Act 4)

### Option 2: Fix Conquest Pipeline

Address the Bombard vs Invade issue:
- Lower defense threshold for direct Invade orders
- Add bombardment follow-up logic (invade after N turns)
- Increase capital ship production ratios
- Balance ground battery costs/effectiveness

### Option 3: Structural Changes

- Add act-aware requirement priority boosts (make capacity fillers higher priority in Act 4)
- Implement multi-turn budget planning (commit to large fleet builds over multiple turns)
- Add "construction capacity exceeded" detection (build more shipyards when hoarding detected)

---

## Lessons Learned

1. **Backward Logic Bug** - The treasury > 5000 check was trying to prevent spam but created hoarding
2. **Chicken-and-Egg Problem** - Not generating requirements because of hoarding → causes more hoarding
3. **Multi-Layer Issue** - Hoarding has causes at multiple levels:
   - Requirements generation (fixed ✓)
   - Budget allocation (partially addressed)
   - Construction capacity (not addressed)
   - Economic scaling (not addressed)

4. **Diagnostic-Driven Debugging** - Using CSV analysis and log analysis was critical:
   ```python
   python3 scripts/analysis/check_conquests.py --seed 99999
   ```

---

## Testing Commands

```bash
# Build with fixes
nimble buildSimulation

# Test hoarding fix
./bin/run_simulation -s 22222 -t 45

# Analyze results
python3 scripts/analysis/analyze_single_game.py 22222

# Check conquests
python3 scripts/analysis/check_conquests.py --seed 22222

# Check requirement generation (during run)
./bin/run_simulation -s 33333 -t 15 2>&1 | \
  grep -E "Capacity fillers:|Generated.*build requirements|Budget allocation"
```

---

## References

- Related: [2025-12-09-invasion-debugging.md](2025-12-09-invasion-debugging.md) - ROE and marine loading fixes
- Code: `src/ai/rba/domestikos/build_requirements.nim`
- Code: `src/ai/rba/domestikos/exploration_ops.nim`
- Code: `src/ai/rba/treasurer/multi_advisor.nim`
- Code: `src/ai/rba/basileus/mediation.nim`
