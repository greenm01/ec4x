# Phase 2 AI Blocker: Colonization Deadlock

**Date:** 2025-11-25
**Status:** 🔴 **CRITICAL BLOCKER** - Prevents Phase 3
**Severity:** High - AI cannot progress beyond early game

---

## Problem Summary

AI colonization is fundamentally broken. After extensive testing, all AI players get stuck at **2 colonies** (out of 61 available systems) and never expand further. This prevents proper game progression and makes 4-act structure validation impossible.

---

## Symptoms

### Observed Behavior (100-turn test):
- **Turn 7:** AI reaches 2 colonies (uses both starting ETACs)
- **Turn 10+:** AI permanently stuck at 2 colonies
- **Turn 100:** Still at 2 colonies (0% map coverage)
- **Military:** 0 scouts, 0 fighters, 0 military ships built
- **Treasury:** 887k-1.2M PP accumulated but not spent
- **Espionage:** 0 missions conducted

### Expected Behavior (per 4-act structure):
- **Act 1 (Turn 7):** 5-8 colonies
- **Act 2 (Turn 15):** 10-15 colonies
- **Act 3 (Turn 25):** 15-25 colonies
- **Act 4 (Turn 30):** Victory or elimination

---

## Root Cause Analysis

### Initial Hypothesis: Circular Dependency in `isEarlyGame`

Located in `tests/balance/ai_controller.nim:2416`:

```nim
let isEarlyGame = filtered.turn < 10 or myColonies.len < 3
let needETACs = (etacCount < etacTarget and isEarlyGame)
let needScouts = scoutCount < 2 and not isEarlyGame
```

**The circular dependency:**
1. At turn 10, AI has 2 colonies (< 3)
2. `isEarlyGame = (10 < 10) or (2 < 3) = false or true = true`  ✅ Still early game
3. `etacTarget = if isEarlyGame: 4 else: 2`  → etacTarget = 4
4. `etacCount = 0` (both starting ETACs used)
5. `needETACs = (0 < 4) and true = true`  ✅ Should build ETACs

**Wait, this should work!**

The logic suggests ETACs should be built. So the circular dependency hypothesis is **incorrect**.

---

## Fix Attempts

### Attempt 1: Remove Colony Count from `isEarlyGame`

**Change:**
```nim
let isEarlyGame = filtered.turn < 10  # Removed colony count
let needETACs = (etacCount < etacTarget and p.expansionDrive > 0.3)
```

**Result:** FAILED
- Games hang/run extremely slowly
- Massive log output (9.5M lines for 7-turn game vs ~28 expected)
- Likely infinite build loop
- Reverted changes

### Attempt 2: Change ETAC Gating to expansionDrive

**Change:**
```nim
let needETACs = (etacCount < etacTarget and p.expansionDrive > 0.3)
# Instead of: and isEarlyGame
```

**Result:** FAILED
- AI still stuck at 2 colonies
- Balanced strategy has `expansionDrive: 0.5` (> 0.3), so condition should pass
- No error messages, just no expansion

---

## Deeper Investigation Needed

The issue is **NOT** the `needETACs` condition itself. Possibilities:

### 1. Build Priority Conflicts
- Other build orders may be taking priority over ETACs
- Check `generateBuildOrders()` priority logic at line ~2487

### 2. Infrastructure Blocking
- ETACs require shipyards
- Check if shipyard availability blocks ETAC construction
- Look at line ~2501: "Don't block ETAC building - homeworld starts with shipyard"

### 3. Treasury/Maintenance Issues
- ETACs cost 25 PP each
- Check if maintenance costs are consuming budget
- AI has 887k-1.2M PP, so this seems unlikely

### 4. ETAC Count Not Updating
- Check if `etacCount` calculation is correct
- Located at line ~2299: Count spacelift ships in fleets AND colonies
- Maybe ETACs are being built but not counted?

### 5. Colonization Logic Broken
- Even if ETACs are built, are they being used to colonize?
- Check `generateFleetMovementOrders()` for colonization logic

---

## Test Data

### Homeworld Validation: ✅ PASS
- All 4 homeworlds properly placed on outer ring
- Even distribution in different 90° sectors
- 61 total systems, 57 uncolonized (plenty of targets)

### Fog-of-War Tests: ✅ 35/35 PASS
- All visibility levels working
- No information leakage
- Engine production-ready

### AI Diagnostic Tests: ⚠️ FUNCTIONAL BUT BROKEN BEHAVIOR
- 20/20 games completed (no crashes)
- All games show same pattern: stuck at 2 colonies
- Zero military/scout buildup

---

## Impact Assessment

### Phase 2 Status
- **2a-2k:** Marked complete in TODO.md
- **Fog-of-war:** Fully validated ✅
- **AI behavior:** BROKEN 🔴

### Phase 3 Blocked
Cannot proceed to Bootstrap Data Generation (10k+ training examples) until AI can:
1. Expand beyond 2 colonies
2. Build military units
3. Conduct espionage
4. Complete 4-act dramatic arc

---

## Recommended Next Steps

### Debugging Approach
1. **Add detailed logging** to `generateBuildOrders()` to see what's actually being built
2. **Check build order execution** - are ETAC build orders even being created?
3. **Trace ETAC lifecycle** - built → counted → used for colonization
4. **Verify colonization logic** - are there uncolonized systems within range?
5. **Check squadron limits** - is AI hitting squadron cap?

### Alternative Approaches
1. **Review recent commits** - was colonization working before? When did it break?
2. **Compare with genetic algorithm AI** - does coevolution AI work differently?
3. **Manual walkthrough** - step through single-turn execution with debugger
4. **Simplify** - remove all conditionals except basic ETAC building

### Timeline
- **Priority:** Critical
- **Estimated effort:** 4-8 hours of careful debugging
- **Blocker for:** Phase 3 Bootstrap Data Generation

---

## Files Involved

- `tests/balance/ai_controller.nim` - AI decision logic (2413-2427, 2487+)
- `tests/balance/run_simulation.nim` - Game simulation harness
- `src/engine/resolve.nim` - Turn resolution and build processing
- `src/engine/economy/construction.nim` - Construction mechanics

---

## References

- `docs/BALANCE_TESTING_METHODOLOGY.md` - 4-act structure requirements
- `docs/PHASE2_UNKNOWN_UNKNOWN_TESTING.md` - Testing plan
- `docs/FOG_OF_WAR_TESTING_COMPLETE.md` - Validated systems
- Balance test results: `balance_results/diagnostics/game_*.csv`

---

**Last Updated:** 2025-11-25
**Next Action:** Deep debugging session on AI build order generation
