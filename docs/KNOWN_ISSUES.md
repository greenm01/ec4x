# EC4X Known Issues & Active Bugs

**Last Updated:** 2025-12-01 (Post-Dynamic Expansion Implementation)
**Status:** 2 critical balance issues identified in 400-game test suite

This document tracks ACTIVE issues only. Resolved issues archived in `docs/archive/`.

---

## 🔴 CRITICAL: Active Balance Issues

### Issue #1: Alliance Pacts Not Forming (Zero Pacts Across 400 Games)

**Status:** 🔴 **CRITICAL**
**Discovered:** 2025-12-01 during 4-Act balance testing (400 games)
**Impact:** Diplomatic system partially broken - NAP/Alliance proposals never made
**Severity:** High - Eliminates entire diplomatic strategy path

#### Evidence

Balance test results (400 games, 96 per act):
```
Ally (pacts):             0      ← PROBLEM
Hostile (tensions):   10,907     ← Working
Enemy (open war):      4,363     ← Working
```

- Diplomacy IS working (hostile/enemy states functioning)
- Auto-escalation to Hostile and Enemy works correctly
- BUT: Zero alliance pacts formed across all games

#### Root Cause

**Dynamic prestige thresholds still too high for balanced games**

Calculated thresholds vs actual prestige gaps:
```
Act 1 (avg prestige ~3200):
  Moderate threshold (15%):  480
  Actual prestige gaps:      200-214

Act 2 (avg prestige ~4400):
  Moderate threshold (15%):  660
  Actual prestige gaps:      398

Act 3-4 (avg prestige ~5500):
  Moderate threshold (15%):  825
  Actual prestige gaps:      480-539
```

**Problem:** Houses are too evenly matched in balanced 4-player games for pact proposals to trigger.

#### Analysis

Current implementation (`src/ai/rba/protostrator/requirements.nim:20-63`):
- Overwhelming: 35% of avg prestige (seek NAP to avoid conflict)
- Moderate: 15% of avg prestige (NAP if diplomatic-focused)
- Strong: 25% of avg prestige (alliance consideration)

These percentages assume significant power imbalances (like real-world great power diplomacy).
In balanced 4-player games, prestige spreads are much tighter (~5-10% of average).

#### Proposed Fix

Reduce threshold percentages to match balanced gameplay:
- Overwhelming: 35% → **8%** (250-440 gap in Act 1-4)
- Moderate: 15% → **5%** (160-275 gap in Act 1-4)
- Strong: 25% → **6%** (190-330 gap in Act 1-4)

This would make pact proposals trigger for realistic power differences in 4-player games.

#### Files Involved

- `src/ai/rba/protostrator/requirements.nim:56-58` - Dynamic threshold calculation

---

### Issue #2: Strategy Imbalance (Turtle & Balanced Dominating)

**Status:** 🔴 **CRITICAL**
**Discovered:** 2025-12-01 during 4-Act balance testing (400 games)
**Impact:** Two strategies dominate with 80%+ combined win rate
**Severity:** High - Eliminates strategic diversity

#### Evidence

Win rates by strategy and act (96 games per act):
```
Act 1 Results:
  Turtle:       27.1% ← Slightly strong
  Economic:     32.3% ← Balanced
  Aggressive:   20.8% ← Balanced
  Balanced:     19.8% ← Balanced

Act 2 Results:
  Turtle:       39.6% ← DOMINANT
  Balanced:     40.6% ← DOMINANT
  Aggressive:    8.3% ← WEAK
  Economic:     11.5% ← WEAK

Act 3 Results:
  Balanced:     36.5% ← DOMINANT
  Turtle:       40.6% ← DOMINANT
  Economic:     11.5% ← WEAK
  Aggressive:   11.5% ← WEAK

Act 4 Results:
  Turtle:       49.0% ← EXTREME DOMINANCE
  Balanced:     36.5% ← DOMINANT
  Aggressive:    6.2% ← CRITICALLY WEAK
  Economic:      8.3% ← CRITICALLY WEAK
```

**Key Findings:**
1. **Turtle dominance increases over time** (27% → 49% win rate)
2. **Aggressive strategy collapses** (21% → 6% win rate)
3. **Economic strategy fails** (32% → 8% win rate)
4. **Imbalance worsens with game length** (balanced Act 1 → extreme Act 4)

#### Expected vs Actual

**Expected:** All 4 strategies should be viable (20-30% win rate each)
**Actual:** Two strategies win 80-85% of games combined

#### Potential Root Causes

**Theory 1: Aggressive Strategy Issues**
- Early military spending may not pay off
- Combat losses unsustainable
- Territory conquest not rewarding enough
- Wars declared but not won decisively

**Theory 2: Economic Strategy Issues**
- Pure economy doesn't convert to military fast enough
- Late-game military catch-up too slow
- Infrastructure investment not paying off
- Passive early game = weak position later

**Theory 3: Turtle/Balanced Advantages**
- Defensive play more sustainable
- Balanced approach hedges all risks
- Turtle benefits from conflict between others
- Resource efficiency > expansion speed

#### Investigation Needed

1. **Combat effectiveness by strategy** - Are aggressive houses winning their wars?
2. **Economic conversion rate** - How fast can economic houses build military?
3. **Colony count by strategy** - Are aggressive/economic expanding successfully?
4. **Treasury/production trends** - Resource advantage not translating to wins?

#### Files to Investigate

- `src/ai/rba/personality.nim` - Strategy personality definitions
- `src/ai/rba/budget.nim` - Resource allocation by strategy
- `src/ai/rba/orders.nim` - Build priority by strategy
- `src/ai/rba/tactical.nim` - Military posture by strategy

---

## ✅ RESOLVED: Recent Fixes (2025-12-01)

### Fixed: Colony Expansion Stalled at 8 Colonies

**Resolution:** Implemented dynamic fog-of-war-based ETAC production
- Replaced hardcoded threshold (myColonies < 8) with `countUncolonizedSystems()`
- ETAC production now continues while uncolonized systems visible
- **Result:** 2,094 colonies established across 400 games (was 0 in Acts 2-4)

### Fixed: Combat Diagnostics Showing Zero

**Resolution:** Added combat tracking to House object and resolution pipeline
- Track wins/losses/total from combat reports during turn resolution
- Wire combat stats into diagnostic collection
- **Result:** 74,404 combats properly tracked across 400 games (was showing 0)

### Fixed: VIEW A WORLD Mission Missing

**Resolution:** Implemented Order 19 (long-range planetary reconnaissance)
- Ships scan planet owner + class from system edge
- AI prioritizes View World in Act 1 for intelligence gathering
- **Result:** New reconnaissance capability for strategic planning

---

## Archive

**Older resolved issues:** See `docs/archive/KNOWN_ISSUES_2025-11-29.md` for:
- Population Transfer System Initialization (resolved 2025-11-29)
- Sequential Order Processing Bias (resolved 2025-11-27)
- AI Subsystem Integration Bugs (resolved 2025-11-27)
- Espionage, Scout Production, Mothballing issues (all resolved 2025-11-27)
