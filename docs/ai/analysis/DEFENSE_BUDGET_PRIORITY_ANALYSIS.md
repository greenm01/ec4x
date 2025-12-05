# Defense Budget Priority Analysis

**Date:** 2025-12-04
**Status:** Systematic Issue Identified - Requires Unknown-Unknown Testing
**Type:** Architecture & Game Balance

## Executive Summary

Investigation into low defensive structure coverage (70.5% colonies undefended) revealed a **systematic architectural issue** with defense budget allocation. While fixes enabled defensive structures to be built (facility requirement bug) and made budgets intelligence-driven (100% tactical allocation), ground batteries still have only **3.1% fulfillment rate** (5 fulfilled, 156 unfulfilled in 20-turn test).

**Root Cause:** All defensive assets (shields, batteries, armies, defense ships) share the same Medium priority and compete for the Defense budget. Early-processed items consume the budget before batteries are evaluated.

**Recommendation:** Run **unknown-unknown tests** to explore architectural alternatives and game balance implications.

---

## Investigation Timeline

### 1. Initial Discovery (Balance Test Results)

```
Before Fixes:
- Undefended Colonies: 70.5%
- Planetary Shields: 16.9%
- Ground Batteries: 12.4%
- Armies: 4.3%
- Bombardments: 0 (in 3,029 invasions)
```

### 2. Bugs Fixed

#### Bug #1: Facility Requirement (`src/ai/rba/budget.nim:1062-1087`)
**Issue:** Defense buildings incorrectly required shipyard/spaceport
- Defense buildings (batteries, armies, shields) are planet-side infrastructure
- Code required facilities for ALL Domestikos requirements
- Result: All defense orders rejected - "no suitable colonies"

**Fix:** Added `requiresFacility` check based on `req.shipClass.isSome`

#### Bug #2: Budget Not Tactical (`src/ai/rba/treasurer/consultation.nim:111-148`)
**Issue:** Defense budget blended 70% requirements + 30% Act-based config
- Domestikos: "Need 300PP Defense"
- Treasurer: "Here's 210PP" (70% of request)

**Fix:** Made Defense/Military 100% tactical-driven (pure requirements-based)

#### Bug #3: Ground Battery Cost (`config/construction.toml:59`)
**Issue:** Ground batteries too expensive (100PP each, 300PP for 3 per colony)

**Fix:** Reduced to 50PP per battery (same as Battleship)

### 3. Post-Fix Results

```
After Fixes:
- Undefended Colonies: 49.8% (↓ 20.7 percentage points)
- Planetary Shields: 24% (↑ 7.1%)
- Ground Batteries: 6% (↓ 6.4%) ← PROBLEM
- Armies: 6% (↑ 1.7%)
```

**Unexpected:** Ground batteries went DOWN despite fixes enabling them to be built.

### 4. Deep Analysis (20-Turn Simulation)

```
Ground Battery Statistics:
- Requested: 161 times
- Fulfilled: 5 times (3.1%)
- Unfulfilled: 156 times (96.9%)
- Houses that can afford: 1 out of 4 (house-ordos only)
```

**Pattern:** "insufficient Defense budget" for 3 out of 4 houses consistently.

---

## Root Cause: Intra-Defense Priority Competition

### The Problem

All defensive assets are **Medium priority** in Domestikos requirements:

| Asset Type | Priority | Cost per Request | Frequency |
|------------|----------|------------------|-----------|
| Defense Gap Ships (Destroyers) | Medium | 40PP | Per undefended colony |
| Planetary Shields | Medium | 50PP | Per high-value colony |
| Armies (2×) | Medium | 30PP | Per colony |
| Ground Batteries (3×) | Medium | 150PP | Per colony |

### Processing Order

Domestikos generates requirements in this order (`build_requirements.nim:640-682`):

1. **Defense gap ships** - Generated first for undefended colonies
2. **Planetary shields** - Generated second for high-value colonies
3. **Ground batteries** - Generated third (baseline defense)
4. **Armies** - Generated fourth (ground defense)

### Budget Depletion Sequence

Example: 300PP Defense budget, 1 colony needing full defense:

```
Available: 300PP

1. Defense gap ship: 40PP    → Remaining: 260PP ✅
2. Planetary shield: 50PP     → Remaining: 210PP ✅
3. Ground batteries (3×): 150PP → Remaining: 60PP ✅
4. Armies (2×): 30PP          → Remaining: 30PP ✅
```

**This works!** But with multiple colonies:

```
Available: 300PP, 2 colonies

Colony 1:
1. Defense gap ship: 40PP     → Remaining: 260PP ✅
2. Planetary shield: 50PP     → Remaining: 210PP ✅
3. Armies (2×): 30PP          → Remaining: 180PP ✅
4. Ground batteries (3×): 150PP → Remaining: 30PP ✅

Colony 2:
1. Defense gap ship: 40PP     → Remaining: -10PP ❌ INSUFFICIENT
2. Planetary shield: 50PP     → ❌ INSUFFICIENT
3. Armies (2×): 30PP          → ❌ INSUFFICIENT
4. Ground batteries (3×): 150PP → ❌ INSUFFICIENT
```

**Reality is worse:** Early-game houses have 3-4 colonies and only 200-300PP budget.

---

## Why This Is Systematic, Not Tuning

### Evidence

1. **Budget Allocation Works** ✅
   - Defense budget is 100% tactical-driven
   - Domestikos consultation properly calculates required PP
   - No hard-coded Act-based limits

2. **Defense Orders Are Created** ✅
   - Domestikos generates battery requirements correctly
   - CFO properly processes them (no facility requirement)
   - Orders reach the budget evaluation stage

3. **The Problem: Sequential Depletion** ❌
   - All Medium-priority items compete equally
   - First-come-first-served within priority level
   - Batteries consistently come last in generation order
   - Budget depleted by time batteries are evaluated

### Not Simple Tuning

- **Can't just increase Defense budget** - would over-allocate to early items
- **Can't just reorder generation** - all items are legitimately important
- **Can't just lower battery cost** - already same as Battleship (50PP)

This is an **architectural design question** about resource allocation strategy.

---

## Unknown-Unknown Questions for Testing

### 1. Priority Hierarchy

**Question:** Should defensive infrastructure have different priorities than defensive fleets?

**Options to Test:**

**Option A: Infrastructure First**
```nim
Priority.High:
  - Planetary Shields (prevent bombardment damage)
  - Ground Batteries (stop invasions)

Priority.Medium:
  - Armies (last-line ground defense)
  - Defense Gap Ships (mobile reserve)
```

**Option B: Threat-Based Prioritization**
```nim
If enemy fleets nearby:
  Priority.Critical: Defense Gap Ships (immediate threat)
  Priority.High: Shields, Batteries

If peaceful expansion:
  Priority.High: Shields, Batteries (infrastructure)
  Priority.Low: Defense Gap Ships (no immediate need)
```

**Option C: Cost-Effectiveness Priority**
```nim
Priority by PP/DefenseStrength ratio:
  - Batteries: 50PP for 50 DS = 1.0 ratio (best)
  - Armies: 15PP for 8 DS = 1.9 ratio
  - Shields: 50PP for block chance (situation-dependent)
  - Destroyers: 40PP for 6 DS + mobility = 6.7 ratio
```

**Tradeoffs:**
- Infrastructure is permanent but immobile
- Ships are mobile but can be destroyed
- Shields block bombardment but not invasion
- Batteries stop bombardment, armies stop invasion

### 2. Budget Subdivision

**Question:** Should Defense budget be subdivided into Infrastructure vs Fleet?

**Option A: Unified Defense Budget** (current)
- Flexibility: AI allocates based on situation
- Risk: Sequential processing bias

**Option B: Subdivided Budget**
```nim
Defense Budget = 30% of total
  Infrastructure (60%): Shields, Batteries, Armies
  Fleet Defense (40%): Defense Gap Ships, Guard Fleets
```

**Option C: Minimum Guarantees**
```nim
Defense Budget = 30% of total
  Minimum 20% for Infrastructure (guaranteed)
  Remaining 10% for Fleet Defense
```

**Tradeoffs:**
- Subdivision ensures infrastructure funding
- But reduces AI flexibility to respond to threats
- May lead to inefficient allocation in some scenarios

### 3. Cost Ratios

**Question:** Are current costs balanced for defensive value?

**Current Costs:**
| Asset | Cost | Defense Strength | Mobility |
|-------|------|------------------|----------|
| Ground Battery | 50PP | 50 DS | Fixed |
| Destroyer | 40PP | 6 DS | Mobile |
| Army | 15PP | 8 DS | Fixed |
| Shield SLD1 | 50PP | ~15% block | Fixed |

**Observations:**
- Battery has 10× DS per PP vs Destroyer (50/50 vs 6/40)
- But Destroyer can defend multiple colonies
- Battery requires 3× per colony (150PP total commitment)

**Testing Options:**
1. Lower battery cost to 30PP (3× = 90PP per colony)
2. Increase ship costs (Destroyer 40PP → 60PP)
3. Reduce batteries required per colony (3 → 2 or 1)
4. Keep current costs, adjust priorities instead

### 4. Proactive vs Reactive Defense

**Question:** Should colonies have baseline defenses built automatically?

**Option A: Reactive** (current)
- Domestikos identifies defense gaps → generates requirements
- Treasurer allocates budget → CFO executes
- Result: Defenses built only when budget available

**Option B: Proactive Baseline**
```nim
When colony established:
  Automatically queue:
    - 1 Ground Battery (minimum defense)
    - Cost: 50PP from colony's first production
```

**Option C: Phased Defense Buildup**
```nim
Colony Age:
  0-5 turns: 1 Battery (basic defense)
  6-10 turns: +1 Battery, +1 Army (established)
  11+ turns: +1 Battery, +Shield (mature)
```

**Tradeoffs:**
- Proactive ensures every colony has SOME defense
- But reduces flexibility for expansion/military
- May slow early-game expansion (opportunity cost)

### 5. Priority Escalation

**Question:** Should unfulfilled defense requirements escalate in priority?

**Current:** All defense requirements stay Medium priority
- If unfulfilled turn 1, stays Medium turn 2
- Competes equally with new requirements

**Option: Escalation System**
```nim
Unfulfilled Requirements:
  Turn 1: Priority.Medium
  Turn 2-3: Priority.High (escalated)
  Turn 4+: Priority.Critical (urgent)
```

**Tradeoffs:**
- Ensures chronic issues get addressed
- But may starve new strategic needs
- Could lead to cascading priority inflation

---

## Recommended Testing Approach

### Phase 1: Quick Validation Tests

Test **Option A (Infrastructure First)** from Question 1:
```nim
# In build_requirements.nim:
Shields: RequirementPriority.High
Batteries: RequirementPriority.High
Armies: RequirementPriority.Medium
Defense Ships: RequirementPriority.Medium
```

**Hypothesis:** This should significantly increase battery fulfillment rate.

**Expected Results:**
- Battery fulfillment: 3.1% → 40%+
- Shield coverage: 24% → 35%+
- May reduce defensive ship coverage

**If this works:** Validates that priority ordering is the core issue.

### Phase 2: Cost-Effectiveness Tests

If Phase 1 works, test cost adjustments:
1. Battery cost: 50PP → 30PP (cheaper infrastructure)
2. Battery requirement: 3 per colony → 2 per colony
3. Destroyer cost: 40PP → 60PP (more expensive mobile defense)

**Metrics to Track:**
- Defense coverage (% colonies with batteries, shields, armies)
- Bombardment frequency (should increase with better defenses)
- Invasion success rate (should decrease with better defenses)
- Win rate by strategy (does defense become too strong?)

### Phase 3: Unknown-Unknown Tests

Run **parameter sweeps** across multiple dimensions:

```python
test_configs = {
    'battery_cost': [30, 40, 50, 60],
    'battery_count': [1, 2, 3],
    'battery_priority': ['High', 'Medium', 'Low'],
    'defense_budget_min': [0.15, 0.20, 0.25, 0.30],
}

# Test all combinations (4 × 3 × 3 × 4 = 144 configurations)
# Run 10 games each = 1,440 total games
# Analyze for emergent patterns
```

**Look for:**
- Unexpected equilibria (e.g., heavy defense meta)
- Cascade effects (batteries → more bombardments → slower wars)
- Strategy shifts (aggressive becomes dominant with cheap batteries)

---

## Implementation Recommendations

### Immediate Action: Intelligence-Driven Priority

**CORRECT APPROACH: Dynamic priority based on intelligence analysis**

Priority should be determined by **tactical situation**, not hard-coded:

```nim
# Determine priority based on intelligence reports:

func calculateDefensePriority(
  colony: Colony,
  intelligence: FilteredIntelligence,
  threatLevel: float
): RequirementPriority =
  ## Intelligence-driven priority calculation

  # High threat nearby → infrastructure is CRITICAL
  if threatLevel > 0.7:
    return RequirementPriority.Critical

  # Medium threat or recent invasions in region → HIGH priority
  if threatLevel > 0.3 or recentInvasionsNearby(colony, intelligence):
    return RequirementPriority.High

  # Low threat but undefended → MEDIUM priority (build over time)
  if colony.defenseStrength == 0:
    return RequirementPriority.Medium

  # Has some defense, peaceful → LOW priority (maintain)
  return RequirementPriority.Low
```

**Rationale:**
- Priority reflects actual tactical situation
- Responds to enemy movements and threats
- Colonies under threat get defenses first
- Peaceful colonies build defenses gradually
- Maintains AI intelligence-driven philosophy

### If That Works: Iterate on Costs

After validating priority ordering matters:
1. Run cost sweep tests (Phase 2 above)
2. Analyze bombardment/invasion balance
3. Tune to desired strategic depth

### If That Doesn't Work: Architectural Change

If priority alone doesn't fix it, consider:
- Budget subdivision (Question 2, Option C: Minimum Guarantees)
- Proactive baseline defense (Question 4, Option B)
- Escalation system (Question 5)

But test priority fix FIRST - it's the simplest hypothesis.

---

## Success Metrics

### Primary Goals

1. **Defensive Coverage**
   - Target: 60%+ colonies have at least 1 battery
   - Current: ~6% (post-fix)

2. **Bombardment Frequency**
   - Target: 20%+ of invasions preceded by bombardment
   - Current: 0%

3. **Strategic Diversity**
   - All 4 strategies remain viable (15-35% win rate each)
   - No single strategy dominates (>50% win rate)

### Secondary Goals

4. **AI Budget Efficiency**
   - <10% Defense budget unspent
   - Balanced allocation across infrastructure + fleet

5. **Gameplay Flow**
   - Wars take 5-10 turns (not instant conquest)
   - Defended colonies survive 2-3 turns under attack
   - Attackers must choose bombardment vs direct assault

### Warning Signs

- ⚠️ Turtle strategy >60% win rate (defense too strong)
- ⚠️ Aggressive strategy <5% win rate (defense too strong)
- ⚠️ All invasions succeed turn 1 (defense too weak)
- ⚠️ Wars extend beyond 15 turns (defense too strong)

---

## Conclusion

This is a **systematic architectural issue**, not a simple tuning problem. The fixes applied (facility requirement, tactical budgets, cost reduction) were necessary but insufficient. The core issue is **intra-defense priority competition** - all Medium-priority items compete for the same budget, and sequential processing creates a first-mover advantage.

**Recommended Path Forward:**
1. **Immediate:** Change battery/army priority to High (test hypothesis)
2. **If successful:** Run cost-effectiveness tests
3. **If not:** Consider architectural changes (budget subdivision, etc.)
4. **Throughout:** Monitor for emergent gameplay patterns

The goal is to create **strategic depth** where:
- Defenses matter (bombardment becomes necessary)
- But don't dominate (aggressive strategies remain viable)
- AI makes intelligent trade-offs (infrastructure vs fleet)
- Budget allocation remains intelligence-driven (not hard-coded)

Unknown-unknown testing will reveal which approach achieves this balance.

---

## References

### Related Files

- `src/ai/rba/domestikos/build_requirements.nim` - Defense requirement generation
- `src/ai/rba/treasurer/consultation.nim` - Budget allocation logic
- `src/ai/rba/budget.nim` - Order execution and facility requirements
- `config/construction.toml` - Cost configuration
- `config/rba.toml` - Budget allocation configuration

### Balance Test Results

- `balance_results/parallel_test_20251204_234847.json` - Post-fix test results
- `balance_results/reports/detailed_20251204_234847.md` - Detailed analysis

### Related Documents

- `docs/ai/RBA_WORK_COMPLETE_NEXT_STEPS.md` - RBA system status
- `docs/ai/README.md` - AI system overview
