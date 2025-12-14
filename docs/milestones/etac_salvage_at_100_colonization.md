# ETAC Salvage at 100% Colonization

**Status:** ✅ Complete
**Date:** 2025-12-14
**Git Hash:** TBD (run `cat bin/.build_git_hash` after next build)

## Summary

When colonization reaches 100%, ETACs automatically salvage themselves to recover production points instead of sitting idle.

## Problem

ETACs with AutoColonize standing orders were stuck in a loop:
1. Tactical module issues Move/Salvage orders at 100% colonization
2. AutoColonize standing order remains active
3. When orders complete, AutoColonize reactivates
4. ETAC gets sent to a new target (even though no targets exist)
5. ETAC stuck on Hold orders, never salvages

## Root Cause

**Standing orders persist until explicitly cleared.** When tactical issued salvage-related orders, it didn't clear the AutoColonize standing order, causing reactivation.

## Solution

When tactical issues salvage-related orders (Move or Salvage) at 100% colonization, it now **clears the AutoColonize standing order** to prevent reactivation.

### Code Changes

**File:** `src/ai/rba/tactical.nim`

Added standing order clearing in four cases:

1. **Empty ETACs salvaging** (lines 659-663)
   ```nim
   if fleet.id in controller.standingOrders:
     controller.standingOrders.del(fleet.id)
     logInfo(LogCategory.lcAI,
             &"Fleet {fleet.id} AutoColonize standing order cleared (empty ETAC salvaging)")
   ```

2. **ETACs with cargo moving to colony for salvage** (lines 585-590)
   ```nim
   if fleet.id in controller.standingOrders:
     controller.standingOrders.del(fleet.id)
     logInfo(LogCategory.lcAI,
             &"Fleet {fleet.id} AutoColonize standing order cleared (moving for salvage)")
   ```

3. **ETACs with cargo at colony salvaging** (lines 606-610)
   ```nim
   if fleet.id in controller.standingOrders:
     controller.standingOrders.del(fleet.id)
     logInfo(LogCategory.lcAI,
             &"Fleet {fleet.id} AutoColonize standing order cleared (issuing Salvage)")
   ```

4. **ETACs that arrived via Move order** (lines 550-554)
   ```nim
   if fleet.id in controller.standingOrders:
     controller.standingOrders.del(fleet.id)
     logInfo(LogCategory.lcAI,
             &"Fleet {fleet.id} AutoColonize standing order cleared (arrived for salvage)")
   ```

## ETAC Salvage Flow (Complete)

### Case 1: Empty ETAC (no PTU cargo)
1. Colonization reaches 100%
2. Tactical detects empty ETAC
3. **Clear AutoColonize standing order**
4. Issue Salvage order
5. Salvage executes in Income Phase
6. ETAC scrapped, production recovered

### Case 2: Loaded ETAC at colony
1. Colonization reaches 100%
2. Tactical detects loaded ETAC at colony
3. **Clear AutoColonize standing order**
4. Issue Salvage order
5. Zero-turn UnloadCargo executes in Command Phase Part A
6. Salvage executes in Income Phase
7. ETAC scrapped, production recovered

### Case 3: Loaded ETAC not at colony
1. Colonization reaches 100%
2. Tactical detects loaded ETAC away from colony
3. **Clear AutoColonize standing order**
4. Issue Move order to nearest colony
5. Move executes, ETAC travels to colony
6. Next turn: Tactical detects arrived ETAC (has Move order, at colony)
7. Issue Salvage order (UnloadCargo + Salvage same turn)
8. Zero-turn UnloadCargo executes in Command Phase Part A
9. Salvage executes in Income Phase
10. ETAC scrapped, production recovered

## Test Results

**Test:** Seed 42, 4 players, turn 20
**100% Colonization:** Turn 14 (61/61 systems)
**ETAC Count:**
- Turn 14: 46 ETACs (before salvage)
- Turn 15: 5 ETACs (41 salvaged)
- Turns 16-19: 5-3 ETACs (continuing to salvage)

**Breakdown by house:**
- **Atreides:** 12 ETACs → 0 (all salvaged turn 15)
- **Corrino:** 3 ETACs with cargo → salvaged turns 15-18
- **Harkonnen:** 1 ETAC with cargo → salvaged turns 15-19
- **Ordos:** 1 ETAC with cargo → salvaged turns 16-19

## Key Design Principles

1. **Standing orders must be explicitly cleared** when tactical overrides them
2. **Zero-turn commands execute before active orders** in Command Phase
3. **UnloadCargo + Salvage happen same turn** for arrived ETACs
4. **Empty ETACs salvage immediately** (no travel needed)
5. **Loaded ETACs travel to colony first** if not already there

## Related Files

- `src/ai/rba/tactical.nim` - Salvage order generation + standing order clearing
- `src/ai/rba/orders.nim` - UnloadCargo zero-turn command generation
- `src/ai/rba/standing_orders_manager.nim` - Skip AutoColonize at 100%
- `src/engine/standing_orders.nim` - AutoColonize activation logic
- `src/engine/commands/zero_turn_commands.nim` - UnloadCargo execution
- `src/engine/victory/engine.nim` - Leaderboard with colony counts

## Future Enhancements

Potential improvements (not required for current functionality):
- Track salvage PP recovery in diagnostics
- Add prestige bonus for efficient salvaging
- Allow player override (keep ETACs for defense/exploration)
- Salvage other ship types at victory/defeat conditions

## Verification

To verify ETAC salvage behavior:

```bash
# Run test simulation
LD_LIBRARY_PATH=bin ./bin/run_simulation_c --seed 42 --turns 20 --players 4

# Analyze ETAC behavior
python3.11 scripts/analysis/verify_etac_salvage_simple.py
```

Expected output:
- 100% colonization reached turn 14
- ETAC count drops dramatically turn 15 (90%+ reduction)
- Salvage orders issued for ETACs with cargo
- All ETACs gone by turn 20

## Lessons Learned

1. **Standing orders are persistent by design** - they don't auto-clear when overridden
2. **Tactical module owns fleet behavior** - it must manage standing order lifecycle
3. **Database snapshots show turn-start state** - orders may not be visible until next turn
4. **Empty vs loaded ETACs have different flows** - handle both cases
5. **User feedback is critical** - the root cause was identified from user insight about standing order persistence

## Credits

**User insight:** "When the ETAC issues a Move command with intent to salvage, it needs to change the Standing Order from AutoColonize to None"

This directly identified the root cause and solution approach.
