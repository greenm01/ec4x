# Phase 2 Act-by-Act Testing: Complete Findings

**Date:** 2025-11-23
**Goal:** Validate 4-act game structure for 30-turn multi-generational timeline

---

## Test Results Summary

### Baseline (No Acceleration)
- **Turn 7:** 1 colony, 50 prestige (NO colonization happening)
- **Turn 15:** 2-3 colonies, 55-75 prestige (far below target 150-500)
- **Turn 100:** 10-20 colonies, 150-400 prestige

### After Full Acceleration
- **Turn 15:** 2-5 colonies, 76-140 prestige
- **Turn 30:** 2-5 colonies, 109-189 prestige
- **Gap:** Prestige ~10x too low for epic feel (target: 1000-3000 by Turn 30)

---

## All Acceleration Changes Implemented

### 1. Config-Based Acceleration
- ✅ ETAC cost: 50 PP → 25 PP (-50%)
- ✅ Prestige awards: 3x multiplier (all categories)
- ✅ Production per population: 1 PP → 2 PP (2x)
- ✅ Tech research costs: Halved (0.5x)
- ✅ Population growth: 2% → 5% per turn (2.5x)
- ✅ IU investment cost: 30 PP → 15 PP (0.5x)

### 2. Starting Conditions
- ✅ ETACs: 0 → 5 pre-loaded with PTUs
- ✅ Treasury: 420 PP → 1000 PP
- ✅ Starting tech: EL1/SL1/CST1 → EL3/SL2/CST2

---

## Critical Discovery: Original EC Comparison

### From Original EC Player's Guide

**Starting Conditions:**
```
Fleet: 2 ETACs + 2 Cruisers + 2 Destroyers
Homeworld Production: 100 PP/year
```

**Our Current Implementation:**
```
Fleet: 5 ETACs + 1 Destroyer (MORE ETACs than original!)
Homeworld Production: ~10-20 PP/turn (10x LOWER than original!)
```

### THE REAL BOTTLENECK: Starting Production

**Original EC explicitly states:**
> "You begin with 1 planet having a current production level of 100 points per year"

**Our implementation:**
- Homeworld starts with only 5M population
- At 2 PP per 10M population = only ~10 PP/turn
- **This is 10x lower than original EC!**

**Config says 840 PU but code uses 5M souls - huge discrepancy!**

---

## Original EC Strategy Insights

### Tax Rate Strategy (We're Missing This!)

**Original EC recommends:**
1. Start with high tax (65%) for immediate revenue
2. **LOWER tax as you expand** to help new colonies grow faster
3. Trade-off: Immediate revenue vs long-term production

**Our AI:** Keeps tax at 50% constantly (not optimal!)

### Game Pacing

**Original EC timeline:**
- "After first few rounds" → neighbors discover each other
- "Middle game" → all planets colonized, shift to conquest
- "End game" → total war

Suggests **30-60 day games** with 1 turn/day = 30-60 turns total.

---

## Recommendations for Next Session

### Priority 1: Fix Starting Production (CRITICAL)
```nim
// src/engine/gamestate.nim: createHomeColony()
population: 5,  # Currently 5M souls
// SHOULD BE:
population: 100,  # 100M souls for ~100 PP/turn production
```

This single change would:
- Match original EC starting production (100 PP/year)
- Enable rapid early ETAC construction (4 per turn at 25 PP each)
- Unlock the land-grab phase that's currently missing

### Priority 2: Implement Dynamic Tax Strategy
AI should:
1. Start at 60-65% tax (maximize initial revenue)
2. Lower to 30-40% tax after 3-5 colonies (accelerate new colony growth)
3. Adjust based on expansion phase

### Priority 3: Validate ETAC Count
- Original EC: 2 starting ETACs
- Our implementation: 5 starting ETACs
- With fixed production (100 PP/turn), we can build 4 ETACs/turn
- **Consider reducing to 2-3 starting ETACs** and rely on production

### Priority 4: Prestige Multiplier Decision
After fixing production, re-test and decide:
- Option A: Keep 3x prestige, target 50-60 turn games
- Option B: Increase to 5-10x prestige, target 30 turn games
- Option C: Test and tune based on new production baseline

---

## Technical Debt Discovered

1. **Config vs Code Mismatch:**
   - `game_setup/standard.toml` says `population_units = 840`
   - `src/engine/gamestate.nim` hardcodes `population: 5`
   - Config value is ignored!

2. **Tech Naming Inconsistency:**
   - Config: `shield_level`
   - Spec: `science_level`
   - Both refer to same concept (SL)

3. **Balance Test vs Full Game:**
   - Balance tests use `tests/balance/game_setup.nim` (hardcoded)
   - Full game uses `game_setup/standard.toml`
   - Need to keep both in sync!

---

## Files Modified This Session

**Config files:**
- `config/ships.toml` - ETAC cost 50→25
- `config/prestige.toml` - All awards 3x
- `config/economy.toml` - Production 2x, growth 2.5x, IU cost 0.5x
- `config/tech.toml` - All research costs 0.5x
- `game_setup/standard.toml` - Starting PP 1000, tech EL3/SL2/CST2, 5 ETACs

**Test files:**
- `tests/balance/game_setup.nim` - Added 5 starting ETACs
- `run_balance_test_parallel.py` - Added --turns parameter

**Documentation:**
- `docs/BALANCE_TESTING_METHODOLOGY.md` - 4-act structure, Phase 2 testing

---

## Next Session Action Items

1. [ ] Fix homeworld starting population (5M → 100M souls)
2. [ ] Verify production calculation matches 100 PP/turn baseline
3. [ ] Test with corrected starting production
4. [ ] Implement dynamic tax strategy in AI
5. [ ] Re-run 30-turn tests and compare to original EC pacing
6. [ ] Make final decision on prestige multipliers vs game length

**Expected Impact:** Fixing starting production should unlock the entire early-game land grab phase that's currently missing, potentially solving the pacing issue without further multiplier adjustments.
