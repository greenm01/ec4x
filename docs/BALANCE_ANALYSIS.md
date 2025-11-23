# EC4X M3+ Balance Test Analysis
**Date:** 2025-11-23
**Tests Run:** 10 games × 100 turns each
**Engine Version:** 0.1.0

## Executive Summary

**CRITICAL FINDING:** Systematic prestige drain affects all houses, indicating a potential engine bug or severe balance issue.

## Test Results

### Win Rates (10 games)
- **house-corrino (Balanced):** 6 wins (60.0%)
- **house-atreides (Economic):** 3 wins (30.0%)
- **house-ordos (Aggressive):** 1 win (10.0%)
- **house-harkonnen (Turtle):** 0 wins (0.0%)

### Average Final Prestige
- **house-atreides:** +2.8
- **house-corrino:** +1.1
- **house-ordos:** -12.7
- **house-harkonnen:** -14.3

## Critical Issue: Universal Prestige Drain

ALL houses experience significant prestige loss over 100 turns:

```
Turn |  Ordos | Atreides | Corrino | Harkonnen
-----|--------|----------|---------|----------
   1 |    50  |      50  |     50  |      50
  10 |    42  |      49  |     47  |      37
  20 |    37  |      50  |     37  |      34
  30 |    37  |      44  |     31  |      17
  40 |    44  |      32  |     24  |      17
  50 |    46  |      20  |     19  |      11
  60 |    35  |      27  |     12  |      11
  70 |    26  |      21  |     12  |       4
  80 |    15  |       9  |     16  |       5
  90 |    -2  |       6  |      9  |      -1
 100 |    -6  |      -5  |      2  |      -6
```

### Analysis

**Net Change:** Starting at 50 prestige, ALL houses end near 0 or negative.

**Drain Rate:** ~0.5 prestige/turn across all strategies (50-60 prestige lost over 100 turns).

**Pattern:** Consistent downward trend despite different AI strategies (Aggressive, Economic, Balanced, Turtle).

## Final Game State (Game 10)

```
House         Prestige  Treasury  Colonies  Fleets  Strategy
---------     --------  --------  --------  ------  --------
Corrino            +2       366         1       0  Balanced
Atreides           -5       367         1       1  Economic
Ordos              -6       370         1       0  Aggressive
Harkonnen          -6       367         1       1  Turtle
```

**Key Observations:**
- All houses have exactly 1 colony (no expansion)
- Minimal fleet presence (0-1 fleets)
- Low treasuries (~370 IU vs 911 starting)
- **NO MILITARY CONFLICT** observed in reports

## Possible Causes

### 1. **Tax Penalty System** (Most Likely)
Location: `src/engine/resolve.nim` prestige calculation
Config: `config/prestige.toml` lines 140-165

**Hypothesis:** Tax penalties may be applying every turn regardless of actual tax rate.

Evidence from config:
```toml
tier_2_min = 51
tier_2_max = 60
tier_2_penalty = -1    # -1 prestige per turn
```

**Check:** Are AIs setting tax rates >50%? Default tax rate in game setup?

### 2. **Maintenance Shortfall Penalties**
Location: `config/prestige.toml` lines 123-125

```toml
maintenance_shortfall_base = -5    # -5 turn 1
maintenance_shortfall_increment = -2  # Escalates: -5, -7, -9...
```

**Evidence:** Treasuries dropping from 911 to ~370 IU suggests chronic shortfalls.

**Check:** Are fleets too expensive to maintain? Are houses perpetually in maintenance shortfall?

### 3. **Missing Prestige Gains**
**Observation:** No colony expansion (all houses stuck at 1 colony).

Expected gains NOT happening:
- Colony established: +5 prestige
- Tech advancement: +2 prestige
- Low tax bonus: +1 to +3 per colony per turn
- Fleet victories: +3 prestige

**Check:** Are AIs unable to expand/compete, or is expansion blocked?

### 4. **Espionage Over-Investment**
Location: `src/engine/resolve.nim:361-363` and `config/espionage.toml`

```nim
if investmentPercent > threshold:
  let prestigePenalty = -(investmentPercent - threshold) * penalty_per_percent
```

Config shows 5% threshold with -1 prestige per 1% over.

**Check:** Are AIs over-investing in espionage? (unlikely given low budgets)

## Economic Health Red Flags

Turn 10 report shows:
- Treasury: 470 IU (started at 911)
- **-29 IU change in one turn**
- Production: 36 PP from 1 colony
- Fleet maintenance: ~2 PP (1 fleet)

**Cash burn rate:** ~44 IU/turn (911 → 470 in 10 turns)

This suggests:
- **Maintenance costs may be miscalculated**
- **Income insufficient to cover costs**
- **No economic growth path**

## Recommendations

### Immediate Investigation Priority

1. **CRITICAL: Check tax prestige penalty application** (src/engine/resolve.nim)
   - Is penalty applying when it shouldn't?
   - Is rolling 6-turn average implemented correctly?
   - What are actual AI tax rates?

2. **URGENT: Verify maintenance calculation** (src/engine/economy/)
   - Are maintenance costs correct?
   - Are fleets too expensive relative to starting economy?
   - Is income calculation working?

3. **HIGH: Investigate AI expansion blocking**
   - Why are AIs not colonizing?
   - Are colonizers being built?
   - Are suitable planets available?

### Diagnostic Tests Needed

```bash
# 1. Check AI tax rates throughout game
python3 -c "
import json
with open('balance_results/full_simulation.json') as f:
    data = json.load(f)
    # TODO: Extract tax rates from turn reports
"

# 2. Run 10-turn test with verbose prestige logging
# Modify resolve.nim to log every prestige change

# 3. Run test with simplified economy (lower maintenance)
# Temporarily edit config/units.toml maintenance costs
```

## Engine Correctness Assessment

**STATUS:** ⚠️ **LIKELY BUG DETECTED**

**Evidence:**
- ✅ Engine runs without crashes
- ✅ Turn resolution completes successfully
- ✅ Prestige tracking works (values change)
- ✅ Victory detection works (highest prestige wins)
- ❌ Prestige drain affects ALL strategies equally
- ❌ NO economic growth observed
- ❌ NO territorial expansion observed
- ❌ Final prestige near-zero for all houses

**Conclusion:** Engine mechanics work, but balance or implementation bug causes unplayable economic death spiral.

## Next Steps

1. Add detailed prestige change logging to `src/engine/resolve.nim`
2. Run single 20-turn game with verbose output
3. Check turn report for prestige event breakdown
4. Verify tax rate and maintenance shortfall tracking
5. Fix identified bug(s)
6. Re-run balance tests

## Data Location

- Full simulation data: `balance_results/full_simulation.json`
- Turn-by-turn reports: `balance_results/simulation_reports/`
- Test logs: `/tmp/m3plus_engine_test.log`
