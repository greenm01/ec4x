# globalRBAConfig Migration Plan

## Executive Summary

**Problem**: 242 accesses to `globalRBAConfig` across 41 RBA files create a race condition in multithreaded AI generation (pthread-based C FFI). Multiple threads modify `globalRBAConfig` via `reloadRBAConfig()` calls, causing memory corruption and segfaults.

**Solution**: Migrate all RBA subsystems to use `controller.rbaConfig` instead of `globalRBAConfig`.

**Status**: `controller.rbaConfig` already exists and contains all needed fields. 8 files already use it correctly, demonstrating the pattern works.

---

## Current Architecture

### Global State Path (BROKEN)
```
Thread 1: reloadRBAConfig() → globalRBAConfig (MODIFY)
Thread 2: reloadRBAConfig() → globalRBAConfig (MODIFY) ⚠️ RACE!
Thread 3: reloadRBAConfig() → globalRBAConfig (MODIFY) ⚠️ RACE!
Thread 4: reloadRBAConfig() → globalRBAConfig (MODIFY) ⚠️ RACE!

All threads: 41 files read globalRBAConfig in 242 places (UNSAFE)
```

### Explicit Config Path (INTENDED)
```
CGame.rbaConfig → CFilteredState.rbaConfig → controller.rbaConfig
Each thread: Reads controller.rbaConfig (SAFE - no modification)
```

---

## Usage Statistics

### By File (Top 20)
```
33 accesses - src/ai/rba/protostrator/assessment.nim
33 accesses - src/ai/rba/domestikos/offensive_ops.nim
27 accesses - src/ai/rba/eparch/requirements.nim
19 accesses - src/ai/rba/drungarius/requirements.nim
19 accesses - src/ai/rba/basileus/personality.nim
14 accesses - src/ai/rba/logothete/allocation.nim
11 accesses - src/ai/rba/domestikos/defensive_ops.nim
 7 accesses - src/ai/rba/eparch/economic_requirements.nim
 6 accesses - src/ai/rba/eparch/terraforming.nim
 6 accesses - src/ai/rba/drungarius/operations.nim
 6 accesses - src/ai/rba/domestikos/requirements/standing_order_support.nim
 6 accesses - src/ai/rba/domestikos/build_requirements.nim
 5 accesses - src/ai/rba/tactical.nim
 5 accesses - src/ai/rba/domestikos/unit_priority.nim
 5 accesses - src/ai/rba/domestikos/intelligence_ops.nim
 4 accesses - src/ai/rba/treasurer/budget/splitting.nim
 4 accesses - src/ai/rba/strategic.nim
 4 accesses - src/ai/rba/domestikos/requirements/reprioritization.nim
 3 accesses - src/ai/rba/logistics.nim
 3 accesses - src/ai/rba/domestikos/staging.nim
```

### By Config Subsection (Top 20)
```
27 - globalRBAConfig.domestikos_offensive
23 - globalRBAConfig.domestikos
20 - globalRBAConfig.eparch_facilities
16 - globalRBAConfig.protostrator_stance_recommendations
15 - globalRBAConfig.basileus
14 - globalRBAConfig.drungarius
12 - globalRBAConfig.protostrator
11 - globalRBAConfig.domestikos_defensive
 8 - globalRBAConfig.logothete_allocation
 8 - globalRBAConfig.intelligence
 7 - globalRBAConfig.eparch
 7 - globalRBAConfig.drungarius_operations
 6 - globalRBAConfig.reprioritization
 6 - globalRBAConfig.economic
 5 - globalRBAConfig.tactical
 5 - globalRBAConfig.protostrator_pact_assessment
 4 - globalRBAConfig.strategic
 4 - globalRBAConfig.drungarius_requirements
 4 - globalRBAConfig.domestikos_unit_priorities_act
 4 - globalRBAConfig.domestikos_intelligence_ops
```

---

## Migration Patterns

### Pattern 1: Direct Access in Proc
**Current (BROKEN):**
```nim
proc someFunction(controller: AIController, ...): Result =
  let cfg = globalRBAConfig.domestikos
  if value > cfg.some_threshold:
    ...
```

**Fixed:**
```nim
proc someFunction(controller: AIController, ...): Result =
  let cfg = controller.rbaConfig.domestikos
  if value > cfg.some_threshold:
    ...
```

**Examples:**
- `src/ai/rba/eparch/expansion.nim:167`
- `src/ai/rba/domestikos/build_requirements.nim:182,292`

### Pattern 2: Act-Specific Config Selection
**Current (BROKEN):**
```nim
let affordability = case currentAct:
  of Act1_LandGrab: globalRBAConfig.domestikos.affordability_act1
  of Act2_RisingTensions: globalRBAConfig.domestikos.affordability_act2
  of Act3_TotalWar: globalRBAConfig.domestikos.affordability_act3
  of Act4_Endgame: globalRBAConfig.domestikos.affordability_act4
```

**Fixed:**
```nim
let affordability = case currentAct:
  of Act1_LandGrab: controller.rbaConfig.domestikos.affordability_act1
  of Act2_RisingTensions: controller.rbaConfig.domestikos.affordability_act2
  of Act3_TotalWar: controller.rbaConfig.domestikos.affordability_act3
  of Act4_Endgame: controller.rbaConfig.domestikos.affordability_act4
```

**Examples:**
- `src/ai/rba/domestikos/build_requirements.nim:68-71`
- `src/ai/rba/treasurer/allocation.nim:32-38`

### Pattern 3: Inline Access
**Current (BROKEN):**
```nim
if dist <= globalRBAConfig.tactical.response_radius_jumps:
  ...
```

**Fixed:**
```nim
if dist <= controller.rbaConfig.tactical.response_radius_jumps:
  ...
```

**Examples:**
- `src/ai/rba/tactical.nim:99,145,150,198`

---

## Migration Strategy

### Phase 1: High-Impact Files (8 files, 154 accesses = 64% of total)
**Priority: CRITICAL** - These 8 files account for 2/3 of all global accesses

1. `protostrator/assessment.nim` (33 accesses)
2. `domestikos/offensive_ops.nim` (33 accesses)
3. `eparch/requirements.nim` (27 accesses)
4. `drungarius/requirements.nim` (19 accesses)
5. `basileus/personality.nim` (19 accesses)
6. `logothete/allocation.nim` (14 accesses)
7. `domestikos/defensive_ops.nim` (11 accesses)
8. `eparch/economic_requirements.nim` (7 accesses)

**Approach:**
- Each file already receives `controller: AIController` parameter
- Simple find-replace: `globalRBAConfig.` → `controller.rbaConfig.`
- Verify compilation after each file

### Phase 2: Medium-Impact Files (10 files, 58 accesses = 24% of total)
**Priority: HIGH**

Files with 4-6 accesses each:
- `eparch/terraforming.nim`
- `drungarius/operations.nim`
- `domestikos/requirements/standing_order_support.nim`
- `domestikos/build_requirements.nim`
- `tactical.nim`
- `domestikos/unit_priority.nim`
- `domestikos/intelligence_ops.nim`
- `treasurer/budget/splitting.nim`
- `strategic.nim`
- `domestikos/requirements/reprioritization.nim`

### Phase 3: Low-Impact Files (23 files, 30 accesses = 12% of total)
**Priority: MEDIUM**

Files with 1-3 accesses each (remaining 23 files).

### Phase 4: Remove Global Config Reloading
**Priority: CRITICAL** - Must be done AFTER Phases 1-3

**Remove this call from FFI:**
```nim
# src/c_api/engine_ffi.nim:246
rba_config.reloadRBAConfig()  # DELETE THIS - causes race condition
```

**Keep explicit config path:**
```nim
# CGame already has: rbaConfig: RBAConfig
# CFilteredState already has: rbaConfig: RBAConfig
# controller already has: rbaConfig: RBAConfig
# ✅ Thread-safe: Each thread reads from immutable config
```

---

## Testing Strategy

### Per-Phase Testing
```bash
# After each file migration
nimble buildSimulation

# After Phase 1 complete (64% migrated)
./bin/run_simulation -s 12345 -t 15

# After Phase 2 complete (88% migrated)
./bin/run_simulation -s 99999 -t 25

# After Phase 3 complete (100% migrated)
nimble testBalanceQuick  # 20 games, parallel
```

### Verification
- No segfaults during parallel AI generation
- Config values match expectations (spot-check 5-10 decisions)
- Performance unchanged (parallel speedup maintained)

---

## Implementation Checklist

### Pre-Migration
- [x] Survey all globalRBAConfig usage (242 accesses, 41 files)
- [x] Verify controller.rbaConfig exists and is complete
- [x] Document migration patterns
- [ ] Create backup branch

### Phase 1: High-Impact (8 files)
- [ ] protostrator/assessment.nim (33)
- [ ] domestikos/offensive_ops.nim (33)
- [ ] eparch/requirements.nim (27)
- [ ] drungarius/requirements.nim (19)
- [ ] basileus/personality.nim (19)
- [ ] logothete/allocation.nim (14)
- [ ] domestikos/defensive_ops.nim (11)
- [ ] eparch/economic_requirements.nim (7)
- [ ] Test: `./bin/run_simulation -s 12345 -t 15`

### Phase 2: Medium-Impact (10 files)
- [ ] All 10 files (58 accesses total)
- [ ] Test: `./bin/run_simulation -s 99999 -t 25`

### Phase 3: Low-Impact (23 files)
- [ ] All 23 files (30 accesses total)
- [ ] Test: `nimble testBalanceQuick`

### Phase 4: Remove Global Reload
- [ ] Remove `rba_config.reloadRBAConfig()` from engine_ffi.nim
- [ ] Test: Full 20-game parallel run
- [ ] Verify no segfaults
- [ ] Performance benchmarking

### Post-Migration
- [ ] Update CLAUDE.md if needed
- [ ] Document thread-safety guarantees
- [ ] Consider making globalRBAConfig {.deprecated.}

---

## Risk Assessment

### Low Risk
- Config structure already supports all needed fields
- 8 files already use controller.rbaConfig correctly
- Simple mechanical refactoring (find-replace)
- Each phase is independently testable

### Medium Risk
- High volume of changes (242 call sites)
- Potential for typos during refactoring

### Mitigation
- Implement in phases (test after each)
- Use compiler to catch errors (missing fields will fail to compile)
- Run simulation after each phase
- Keep backup branch for rollback

---

## Success Criteria

- [ ] Zero `globalRBAConfig` accesses remaining in src/ai/rba/
- [ ] No segfaults during parallel AI generation
- [ ] All integration tests pass
- [ ] Performance metrics unchanged
- [ ] Can run 100+ game parallel batch without crashes

---

**Estimated Effort**: 2-4 hours
**Risk Level**: Low-Medium
**Blocking**: Critical for ETAC persistence fix and general stability

---

**Created**: 2025-12-15
**Author**: Claude (analysis) + User (architecture)
