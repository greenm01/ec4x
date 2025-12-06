# EC4X Open Issues & Active Work

**Last Updated:** 2025-12-01 (Post-Dynamic Expansion Implementation)
**Status:** 2 critical balance issues require investigation and fixes

This is the SINGLE source of truth for active bugs, missing features, and ongoing work.
Resolved issues are archived in `docs/archive/`.

---

## 🔴 CRITICAL: Balance Issues Requiring Immediate Attention

### 1. Alliance Pacts Not Forming (Zero Pacts Across 400 Games)

**Priority:** 🔴 **CRITICAL**
**Status:** 🔴 **Active** - Requires threshold adjustment
**Detailed Analysis:** See `KNOWN_ISSUES.md` Issue #1

**Quick Summary:**
- Zero alliance pacts formed across 400-game test suite
- Dynamic prestige thresholds (35%, 15%, 25%) too high for balanced games
- Actual prestige gaps (200-539) much smaller than moderate threshold (480-825)

**Proposed Fix:**
Reduce threshold percentages in `src/ai/rba/protostrator/requirements.nim:56-58`:
```nim
# Current (TOO HIGH):
result.overwhelming = (avgPrestige * 35) div 100  # 35%
result.moderate = (avgPrestige * 15) div 100      # 15%
result.strong = (avgPrestige * 25) div 100        # 25%

# Proposed (REALISTIC):
result.overwhelming = (avgPrestige * 8) div 100   # 8%
result.moderate = (avgPrestige * 5) div 100       # 5%
result.strong = (avgPrestige * 6) div 100         # 6%
```

**Estimate:** 15 minutes
**Files:** 1 file, 3 lines changed

---

### 2. Strategy Imbalance (Turtle & Balanced Dominating)

**Priority:** 🔴 **CRITICAL**
**Status:** 🔴 **Active** - Requires investigation
**Detailed Analysis:** See `KNOWN_ISSUES.md` Issue #2

**Quick Summary:**
- Turtle/Balanced win 80-85% of games combined (should be ~50%)
- Aggressive strategy collapses: 21% → 6% win rate (Act 1 → Act 4)
- Economic strategy fails: 32% → 8% win rate (Act 1 → Act 4)
- Imbalance worsens with game length

**Investigation Plan:**
1. Run diagnostic analysis by strategy type
2. Check combat effectiveness (aggressive winning wars?)
3. Check economic conversion (economic building military fast enough?)
4. Check expansion rates (colony counts by strategy)
5. Check resource efficiency (treasury/production trends)

**Files to Investigate:**
- `src/ai/rba/personality.nim` - Strategy personality definitions
- `src/ai/rba/budget.nim` - Resource allocation by strategy
- `src/ai/rba/orders.nim` - Build priority by strategy
- `src/ai/rba/tactical.nim` - Military posture by strategy

**Estimate:** Investigation: 1-2 hours, Fix: Unknown (depends on findings)

---

## ✅ RESOLVED: Recent Completions (2025-12-01)

### Phase 0-3: Dynamic AI Systems Implementation

**Completed:** 2025-12-01
**Test Results:** 400 games across 4 acts
**Commit:** c6eb3a5

**Implemented:**
1. ✅ **VIEW A WORLD Mission (Order 19)**
   - Long-range planetary reconnaissance from system edge
   - AI prioritizes intelligence gathering in Act 1
   - Enables strategic ETAC targeting

2. ✅ **Dynamic Colony Expansion**
   - Fog-of-war-based ETAC production (replaces hardcoded threshold)
   - **Result:** 2,094 colonies established (was 0 in Acts 2-4)
   - Scales with any map size

3. ✅ **ETAC Auto-Reload System**
   - Verified working correctly (already implemented)
   - ETACs unload colonists → auto-reload with 1 PTU

4. ✅ **Dynamic Prestige Thresholds**
   - Replaced hardcoded values (500, 200, 300) with % of average prestige
   - Scales with game progression and map size
   - **Note:** Percentages too high, need adjustment (see Issue #1)

5. ✅ **Combat Diagnostic Collection**
   - Added combat tracking to House object
   - Wire combat results into diagnostics
   - **Result:** 74,404 combats properly tracked (was showing 0)

---

## Archive

**Historical issues:** See `docs/archive/OPEN_ISSUES_2025-11-29.md` for:
- AI subsystem integration bugs (espionage, scouts, mothballing) - all resolved
- Population transfer system - resolved
- Sequential order processing bias - resolved
