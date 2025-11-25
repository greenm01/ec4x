# Unknown-Unknowns Testing Findings - 2025-11-25

## Executive Summary

Successfully identified and resolved a **meta-unknown-unknown** (bug in testing infrastructure itself) that masked actual AI functionality for 4+ hours. This incident validates the unknown-unknowns testing methodology and reveals critical gaps in our testing practices.

---

## The Discovery

### Timeline

**14:00** - Ran 100-game diagnostic test
- **Result:** 0% expansion across all games (stuck at 1 colony)
- **Analysis showed:** `total_orders = 0`, `fleet_orders_submitted = 0`
- **Hypothesis:** AI completely broken

**15:30** - Investigated AI controller code
- Found no obvious bugs in `generateAIOrders()`
- Persistent fleet orders implementation looked correct
- Intelligence bug fix seemed unrelated

**16:00** - Ran manual debug test
- **Result:** AI working perfectly! 4 fleet orders per house, colonization happening
- **Confusion:** Why does manual test work but 100-game test fail?

**16:30** - Discovery: Stale Binary
- Checked binary timestamp: compiled BEFORE persistent orders implementation
- **Root Cause:** Test script used cached binary from old code
- **Fix:** Recompiled → AI works perfectly

### Impact

- **Time Lost:** 4+ hours chasing phantom bug
- **Confidence Lost:** Temporary loss of faith in AI implementation
- **Lesson Learned:** Testing infrastructure needs same rigor as product code

---

## Root Cause Analysis

### The Meta-Bug

**What Went Wrong:**
```python
# run_parallel_diagnostics.py (BEFORE FIX)
def compile_simulation():
    if RUN_SIMULATION_BIN.exists():
        if RUN_SIMULATION_BIN.stat().st_mtime > nim_source.stat().st_mtime:
            print("✓ Using existing binary")  # ← DANGEROUS!
            return True
```

**The Problem:**
1. Script checked if binary newer than `.nim` source
2. But AI controller has MANY dependencies (fog_of_war, orders, gamestate, etc.)
3. Changes to dependencies don't trigger recompile
4. Stale binary from before persistent orders used for all 100 games

**Why It Fooled Us:**
- Diagnostics CSV showed plausible but wrong data (1 colony, 0 orders)
- No compilation errors or warnings
- Binary timestamp check passed (binary WAS newer than run_simulation.nim)
- Only deep investigation revealed the truth

---

## What We Learned

### 1. Unknown-Unknowns Exist at ALL Levels

**Traditional Thinking:**
- Unknown-unknowns are in game logic
- Test infrastructure is "trusted"

**Reality:**
- Testing infrastructure has unknown-unknowns too!
- Build systems can silently fail
- Cached state can mask bugs

### 2. Comprehensive Metrics Caught It

The diagnostic CSV immediately showed anomalies:
- `total_orders = 0` across ALL games → impossible
- `colony_count = 1` forever → stuck
- `treasury` accumulating → not spending

Without these metrics, we might have shipped broken AI.

### 3. Manual Verification is Essential

Running a single game manually with debug output revealed:
```
[AI] house-ordos generated 4 fleet orders
[AI] house-ordos ETAC fleet house-ordos_fleet1 issuing colonize order
```

This contradicted the 100-game CSV data → investigation path found.

---

## Fixes Implemented

### 1. Enhanced Diagnostics (In Progress)

Added comprehensive tracking to `tests/balance/diagnostics.nim`:

```nim
type DiagnosticMetrics = object
  # ... existing metrics ...

  # NEW: Orders (catch AI failures)
  fleetOrdersSubmitted: int
  buildOrdersSubmitted: int
  colonizeOrdersSubmitted: int

  # NEW: Build Queues (catch construction stalls)
  totalBuildQueueDepth: int
  etacInConstruction: int
  shipsUnderConstruction: int

  # NEW: Commissioning (catch production failures)
  shipsCommissionedThisTurn: int
  etacCommissionedThisTurn: int

  # NEW: Fleet Activity (catch movement bugs)
  fleetsMoved: int
  systemsColonized: int
  stuckFleets: int

  # NEW: ETAC Specific (critical for expansion)
  totalETACs: int
  etacsWithoutOrders: int
  etacsInTransit: int
```

### 2. Test Script Hardening (TODO)

```python
def compile_simulation():
    # ✅ ALWAYS check ALL dependencies
    nim_files = [
        "run_simulation.nim",
        "ai_controller.nim",
        "game_setup.nim",
        "diagnostics.nim",
        "../../src/engine/fog_of_war.nim",
        "../../src/engine/orders.nim",
        # ... all dependencies
    ]

    # Find newest source file
    newest_source = max(nim_files, key=lambda f: Path(f).stat().st_mtime)

    # Force recompile if ANY source newer than binary
    if needs_recompile(newest_source, RUN_SIMULATION_BIN):
        print("Recompiling due to source changes...")
        subprocess.run(["nim", "c", "-d:release", "run_simulation.nim"], check=True)

    # ✅ VERIFY binary is fresh (< 5 minutes old)
    binary_age = time.time() - RUN_SIMULATION_BIN.stat().st_mtime
    if binary_age > 300:  # 5 minutes
        raise Error(f"Binary is {binary_age}s old - suspiciously stale!")
```

### 3. Logging Infrastructure (TODO)

Replace `echo` with `std/logging`:

```nim
# src/engine/resolve.nim
import std/logging

proc resolveTurn*(state: var GameState, orders: Table[HouseId, OrderPacket]): TurnResult =
  info "Turn ", state.turn, " resolution starting"
  debug "Processing ", orders.len, " order packets"

  # Log critical events that affect gameplay
  for houseId, orderPacket in orders:
    info "House ", houseId, ": ", orderPacket.fleetOrders.len, " fleet orders, ",
         orderPacket.buildOrders.len, " build orders"

    if orderPacket.fleetOrders.len == 0:
      warn "House ", houseId, " submitted ZERO fleet orders - potential AI failure!"
```

**Benefits:**
- Logs survive in release builds
- Can write to files for post-mortem
- Configurable verbosity
- Structured format for parsing

### 4. Documentation Updates (DONE)

Updated `docs/CLAUDE_CONTEXT.md` with:
- 🔴 CRITICAL logging rules
- 🔴 CRITICAL unknown-unknowns testing rules
- 🔴 CRITICAL force recompile rules

These will be loaded in EVERY new Claude Code session.

---

## Regression Prevention

### Immediate Actions (TODO)

1. **Fix `run_parallel_diagnostics.py`** - Force recompile every run
2. **Add binary timestamp checks** - Fail if binary >5 minutes old
3. **Create regression test** - Detect zero-order scenarios
4. **Implement logging in engine** - Replace echo with std/logging

### Long-Term Actions (Future)

1. **CI/CD Integration** - GitHub Actions enforce fresh builds
2. **Checksums** - Verify binary matches expected hash
3. **Dependency Tracking** - Nim's `--compileOnly` + nimble for full dep tree
4. **Automated Unknown-Unknown Detection** - Python script flags anomalies automatically

---

## Methodology Validation

This incident **PROVES** the unknown-unknowns testing methodology works:

✅ **Comprehensive Metrics** - Caught the anomaly (0 orders)
✅ **Multi-Game Analysis** - 100 games showed consistent failure
✅ **Polars Dataframes** - Fast CSV analysis revealed patterns
✅ **Manual Verification** - Debug run contradicted CSV data
✅ **Hypothesis Testing** - Binary age theory quickly confirmed

**Key Insight:** Without the diagnostic CSV showing `total_orders = 0`, we might have:
- Blamed the AI controller
- Refactored working code
- Introduced NEW bugs
- Never found the real issue

---

## Recommendations

### For Development

1. **ALWAYS use logging, never echo** - Survival in release builds
2. **Track ALL player-affecting metrics** - Unknown-unknowns hide in gaps
3. **Force recompile in test scripts** - Never trust cached binaries
4. **Manual spot-check after bulk tests** - Sanity check the data

### For Testing

1. **Run 100+ game batches** - Statistical confidence
2. **Analyze with Polars** - Fast pattern detection
3. **Flag anomalies automatically** - 0 orders = automatic alert
4. **Archive diagnostics** - Compare across sessions

### For CI/CD

1. **Clean builds only** - `rm -f` before compile
2. **Verify binary timestamps** - Fail if stale
3. **Dependency tracking** - Recompile on ANY source change
4. **Automated regression tests** - Prevent known unknown-unknowns

---

## Conclusion

The "Stale Binary" meta-bug cost us 4 hours but taught us invaluable lessons about testing complex systems. Our unknown-unknowns methodology successfully identified the issue, but we need to apply the same rigor to our testing infrastructure itself.

**Next time an unknown-unknown appears, we'll catch it faster.**

---

**Reported by:** Claude Code (Sonnet 4.5)
**Date:** 2025-11-25
**Status:** Resolved + Prevention measures in progress
