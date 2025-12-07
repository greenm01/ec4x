# Unit Progression Bugs - Analysis Report

**Date:** 2025-12-07
**Test Seed:** 99999
**Analyst:** Claude + User
**Status:** 🔴 CRITICAL - Multiple systems broken

---

## Executive Summary

RBA unit progression is completely broken. The AI builds wrong units at wrong times, violating the act-based progression defined in `docs/ai/mechanics/unit-progression.md`. Root cause: **CST research progressing 10x too fast**, unlocking all tech by turn 10 instead of turn 30+.

---

## Critical Issues

### 1. 🔴 CST Progression TOO FAST (Root Cause)

**Observed:** CST advances 1 level per turn from turn 2-14
**Expected:** CST should advance slowly to gate units by act

```
ACTUAL:              EXPECTED:
Turn 2:  CST 2       Turn 7:  CST I-II
Turn 4:  CST 4       Turn 15: CST III-IV
Turn 6:  CST 6       Turn 25: CST V-VI
Turn 10: CST 10      Turn 30: CST VI-VIII
```

**Impact:** All unit gates (CST requirements) become meaningless. SuperDreadnoughts unlock at turn 6, PlanetBreakers at turn 10.

**Fix Required:** Slow down CST research rate in config/rba.toml or config/economy.toml

---

### 2. 🔴 Troop Transports in Act 1 (Turn 6-7)

**Observed:** Transports appearing at turn 6-7 (still Act 1)
**Expected:** Transports should NOT appear until Act 2 (turn 8+)

**Evidence:**
```
Turn 6 (Act1): 3 transports built
Turn 7 (Act1): 6 transports total
```

**Root Cause:** Act1 score for TroopTransport is 1.5 in `unit_priority.nim` line 32
**Fix Required:** Set TroopTransport Act1 score to 0.0 (hard gate)

---

### 3. 🔴 Heavy Capitals in Act 1 (Turn 6-7)

**Observed:** Battleships appearing at turn 6-7 (Act 1)
**Expected:** Heavy capitals should wait until Act 3 (turn 16+)

**Evidence:**
```
Turn 6 (Act1): 1 battleship
Turn 7 (Act1): 3 battleships total
```

**Root Cause:** CST 6 reached at turn 6, unlocking Battleships (CST IV)
**Fix Required:** Slow CST progression (primary fix)

---

### 4. 🔴 ZERO Marines Built

**Observed:** 0 marines across all 30 turns
**Expected:** Marines should pair with transports starting Act 2

**Evidence:**
```
Turn 8-30: 9 transports, 0 marines
```

**Impact:** Transports are useless without marines. Invasions impossible.

**Root Cause:** Marine building logic missing or broken in Eparch advisor
**Fix Required:** Check `src/ai/rba/eparch/` for marine build logic

---

### 5. 🔴 Fleet Stagnation After Turn 10

**Observed:** Ship counts frozen from turn 10-30 (20 turns of no growth)
**Expected:** Continuous fleet buildup through Acts 2-4

**Evidence:**
```
Turn 10: 15 destroyers, 5 light cruisers, 5 battleships
Turn 30: 15 destroyers, 5 light cruisers, 5 battleships (unchanged)
```

**Root Cause:** Unknown - budget exhaustion? Build queue stall? CST cap?

**Fix Required:** Investigate Domestikos build queue and budget allocation

---

### 6. 🔴 Skipping Medium Capitals

**Observed:** Only 2 medium capitals (Cruiser/HeavyCruiser/Battlecruiser) by turn 10
**Expected:** Act 2 should focus on medium capitals as fleet backbone

**Evidence:**
```
Turn 10 (Act2): 2 battlecruisers, 0 cruisers, 0 heavy cruisers
Turn 10 (Act2): 5 battleships (skipped straight to heavy)
```

**Root Cause:** CST advancing too fast lets AI skip medium tier
**Fix Required:** Slow CST progression (primary fix)

---

## Working Correctly ✅

- **ETAC progression:** Grows in Act 1, plateaus at 4 per player ✅
- **Fighter production:** Increases over time (6→8) ✅
- **No early SuperDreadnoughts/PlanetBreakers** in first few turns ✅

---

## Root Cause Analysis

### Primary Issue: CST Research Rate

The CST progression rate is calibrated for a different game pace. Current rate:
- **1 CST level per turn** for turns 2-14
- **Reaches CST 10** by turn 10

This suggests either:
1. Research budget allocation is too high (check `config/rba.toml`)
2. Research costs are too low (check `config/economy.toml`)
3. Breakthrough chances are too high (tech advancement too easy)

### Secondary Issue: Act Scoring Weights

Even with correct CST gating, Act1 scores allow wrong units:
- **TroopTransport**: 1.5 in Act1 (should be 0.0)
- **Battleship**: 0.5 in Act1 (low but still buildable if CST allows)

The scoring system assumes CST will gate units, but when CST advances too fast, the scores become meaningless.

---

## Recommended Fixes (Priority Order)

### 1. CRITICAL: Slow Down CST Research

**File:** `config/rba.toml` or `config/economy.toml`

**Goal:** Stretch CST progression across 30 turns instead of 10

**Expected Pacing:**
```
Turn 7:  CST II  (Act 1 end - light ships only)
Turn 15: CST IV  (Act 2 end - medium capitals)
Turn 25: CST VI  (Act 3 end - heavy capitals)
Turn 30: CST VIII (Act 4 - ultimate weapons)
```

### 2. HIGH: Hard-Gate Transports in Act 1

**File:** `src/ai/rba/domestikos/unit_priority.nim:32`

**Change:**
```nim
# BEFORE
ShipClass.TroopTransport: 1.5,

# AFTER
ShipClass.TroopTransport: 0.0,  # HARD GATE - Act 2+ only
```

### 3. HIGH: Fix Marine Building

**File:** `src/ai/rba/eparch/` (location TBD)

**Investigate:** Why are marines never built?
- Check Eparch build_requirements
- Check marine unit gating logic
- Verify marines unlock in Act 2

### 4. MEDIUM: Investigate Fleet Stagnation

**Files:** `src/ai/rba/domestikos/`, `src/ai/rba/budget.nim`

**Debug:**
- Check why builds stop at turn 10
- Verify budget allocation continues
- Check build queue capacity
- Review production spending logs

### 5. LOW: Adjust Act Scores for Heavy Capitals

**File:** `src/ai/rba/domestikos/unit_priority.nim:36-38`

**Change:**
```nim
# Act 1 scores for heavy capitals
ShipClass.Battleship: 0.0,        # was 0.5 - HARD GATE
ShipClass.Dreadnought: 0.0,       # was 0.5 - HARD GATE
ShipClass.SuperDreadnought: 0.0,  # was 0.5 - HARD GATE
```

---

## Testing Strategy

### Phase 1: CST Fix Validation

1. Adjust CST research rate in config
2. Run `./bin/run_simulation -s 99999 -t 30`
3. Verify CST progression with:
   ```bash
   python3 scripts/analysis/analyze_unit_progression.py 99999
   ```
4. Expected: CST ~VI by turn 30, not turn 6

### Phase 2: Unit Progression Validation

1. Apply Act1 transport/capital hard gates
2. Run test batch: `python3 scripts/run_balance_test_parallel.py --games 20 --turns 30`
3. Analyze: `python3 scripts/analysis/analyze_unit_progression.py`
4. Expected:
   - No transports before turn 8
   - No heavy capitals before turn 16
   - Medium capitals built in Act 2

### Phase 3: Marine Build Validation

1. Fix marine building logic (once located)
2. Run test: `./bin/run_simulation -s 99999 -t 30`
3. Check marine count matches transport count ±2

### Phase 4: Fleet Growth Validation

1. Fix budget/build stagnation (once located)
2. Run long game: `./bin/run_simulation -s 99999 -t 50`
3. Verify continuous fleet growth through all acts

---

## Files to Investigate

### Confirmed Issues
- `src/ai/rba/domestikos/unit_priority.nim` - Act scoring (transports, capitals)
- `config/rba.toml` - Research budget allocation
- `config/economy.toml` - Research costs and tech advancement

### To Investigate
- `src/ai/rba/eparch/` - Marine building logic (missing?)
- `src/ai/rba/domestikos/build_requirements.nim` - Why builds stop at turn 10
- `src/ai/rba/budget.nim` - Budget allocation issues?
- `src/ai/rba/treasurer.nim` - Spending patterns

---

## Impact on Gameplay

**Current State:** AI rushes to max tech by turn 10, then stops building ships entirely. Early-game is dominated by premature capital ships. Mid/late-game is stagnant.

**Expected State:** Gradual tech progression with distinct act phases:
- Act 1: Expansion race with light ships
- Act 2: Military buildup with medium capitals
- Act 3: Total war with heavy capitals and invasions
- Act 4: Endgame with ultimate weapons

**Player Experience:** Currently broken - no strategic variety, no progression arc, no mid-game fleet battles.

---

## Next Steps

1. **User:** Share CST research configuration from `config/rba.toml` or `config/economy.toml`
2. **Claude:** Calculate corrected research rates
3. **User:** Apply fixes to `unit_priority.nim` (transport/capital hard gates)
4. **User:** Test with seed 99999 and share results
5. **Claude:** Analyze new results and iterate

---

**References:**
- `docs/ai/mechanics/unit-progression.md` - Intended behavior
- `scripts/analysis/analyze_unit_progression.py` - Analysis tool
- Test data: `balance_results/diagnostics/game_99999.csv`

---

**Last Updated:** 2025-12-07
**Status:** Awaiting config review and fixes
