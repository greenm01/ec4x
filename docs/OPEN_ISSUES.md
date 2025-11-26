# EC4X Open Issues & Gaps

**Last Updated:** 2025-11-26

This is the SINGLE source of truth for known bugs, missing features, and technical debt.
When an issue is fixed, check it off and update STATUS.md.

---

## Config System - Type Duplications (DRY Violations)

**Priority:** LOW (technical debt, not blocking)
**Status:** 🟡 **Identified** - Needs investigation and cleanup
**Discovered:** 2025-11-26 during type duplication audit

### Problem Description

Multiple config types have duplicate definitions - legacy `config.nim` vs modern `config/*.nim`:

**Confirmed Duplicates:**
- `EconomyConfig` - 2 definitions (config.nim:22 vs config/economy_config.nim:166)
- `CombatConfig` - 2 definitions
- `PrestigeConfig` - 2 definitions
- `ConstructionConfig` - 2 definitions
- `EspionageConfig` - 2 definitions
- `PopulationConfig` - 2 definitions
- Plus 9 more duplicate types

**Pattern:**
- **Legacy** (`config.nim`): Simple types with 6-8 fields, basic configuration
- **Modern** (`config/*.nim`): Comprehensive types with nested configs, TOML-based

### Impact

- Technical debt (same as Colony duplication issue)
- Potential confusion about which config to use
- Risk of using wrong/outdated config values
- Multiple places to update when changing config

### Analysis Needed

1. **Verify legacy config.nim is unused:**
   - Only found references in backup files (`resolve.nim.backup`)
   - No active imports detected
   - May be safe to deprecate/remove

2. **Document config system migration:**
   - When did migration happen?
   - Are there any remaining users of legacy config?
   - What's the migration path for new code?

3. **Check if duplicates are intentional:**
   - Some may be different types with same name
   - Verify no namespace collision issues

### Proposed Solution

**Phase 1: Investigation** (1 hour)
1. Search for all imports of `config.nim` (excluding backups)
2. Verify no active usage of legacy config types
3. Document which config types are truly duplicated vs different namespaces

**Phase 2: Cleanup** (1-2 hours)
1. If config.nim is unused, deprecate it (add deprecation warning)
2. Add note to config.nim directing to modern config/*.nim modules
3. Consider moving to `archive/` or deleting after verification

**Phase 3: Documentation** (30 min)
1. Document modern config system in README or architecture docs
2. Add convention: all new config goes in `config/*.nim` modules
3. Update STYLE_GUIDE.md with config system guidelines

**Total Estimated Effort:** 2-3 hours

### Related Issues

- Similar to Colony type duplication (KNOWN_ISSUES #-2)
- Part of broader technical debt cleanup

### Discovery Method

Found via systematic audit:
```bash
grep -rn "^  [A-Z][a-zA-Z]*\* = object" src/engine/ | awk -F: '{print $3}' | sort | uniq -c | sort -rn
```

---

## Diagnostics - Comprehensive Metric Tracking

**Priority:** COMPLETE
**Status:** ✅ **Fully implemented** (2025-11-26)

Expanded diagnostic system from 55 to 130 columns (+136% coverage) with comprehensive game metrics:

**Added Metrics (75 new fields):**
- Tech Levels: All 11 technologies (CST, WEP, EL, SL, TER, ELI, CLK, SLD, CIC, FD, ACO)
- Combat Performance: CER averages, crits, retreats, bombardment, shields
- Diplomatic Status: Pacts, violations, dishonor, isolation
- Espionage Activity: EBP/CIP spending, operations, detections
- Population & Colonies: Space Guild transfers, blockades
- Economic Health: Deficits, damage, salvage, tax penalties
- Squadron Capacity: Fighter/capital limits and violations
- House Status: Autopilot, defensive collapse, elimination countdown

**Key Discovery:** CST never reaches level 10 (Planet-Breaker requirement) within typical game lengths. Max observed: CST 4 by turn 100. This explains zero Planet-Breaker deployments.

**Files Modified:**
- `tests/balance/diagnostics.nim` - Complete expansion with 130-column CSV output

---

## AI - Act 2 Expansion Plateau

**Priority:** MEDIUM (gameplay balance, not blocker)
**Status:** 🟡 **Identified** - Act 1 fixed, Act 2 needs investigation with new diagnostics
**Discovered:** 2025-11-26 during phase-aware tactical validation
**Updated:** 2025-11-26 - Now have comprehensive diagnostics to investigate

### Problem Description

After fixing Act 1 paralysis (5 critical bugs), expansion continues properly through Turn 7 (4-5 colonies achieved), but plateaus in Act 2:

**Expected Progression:**
- Turn 7 (Act 1 end): 5-8 colonies
- Turn 15 (Act 2 end): 10-15 colonies (+5-7 growth)

**Actual Progression:**
- Turn 7: 4-5 colonies ✅ (~70% of target)
- Turn 15: 4-6 colonies ⚠️ (+1-2 growth, only 30-40% of target)

**Gap:** Act 2 expansion is ~80% below target

### Possible Causes

1. **Budget allocation insufficient:**
   - Current: 35% expansion, 30% military in Act 2
   - May need: 40-45% expansion to maintain momentum

2. **ETAC order execution:**
   - ETACs being built (21-43 per game)
   - But colonization orders may not be executing properly
   - Need to verify ETACs are receiving and executing colonization orders

3. **Map competition:**
   - 61 systems / 4 players = ~15 systems per player maximum
   - Players may be bumping into each other earlier than expected
   - Natural plateau due to territorial boundaries

4. **Strategic priority conflicts:**
   - Military/defense consuming ETACs before they can colonize?
   - Act 2 transition at Turn 8 may be too aggressive

### Investigation Steps (Now Enabled by Comprehensive Diagnostics)

With 130-column diagnostics now available, can investigate:

1. **Blockade Impact:** Check `blockaded_colonies` and `blockade_turns_total` metrics
   - Are blockades preventing expansion?

2. **Squadron Capacity Violations:** Check `squadron_limit_violation` and `fighter_cap_violation`
   - Are players hitting military caps that prevent ETAC production?

3. **Economic Throttling:** Check `treasury_deficit`, `tax_penalty_active`, `maintenance_deficit`
   - Are economic issues limiting expansion capability?

4. **Diplomatic Conflicts:** Check `enemy_count`, `pact_violations`, `space_wins/losses`
   - Are early wars draining resources from expansion?

5. **ETAC Production vs Orders:** Compare `etac_ships` count with `total_colonies`
   - Are ETACs being built but not colonizing?

6. **Tech Level Progression:** Check all `tech_*` fields
   - Is tech advancement too slow to support growth?

### Impact

- Act 1 is fully functional (300-400% improvement achieved)
- Game is playable and AI executes basic 4X gameplay
- Act 2 plateau is a tuning issue, not architectural failure
- Lower priority than Planet-Breaker deployment validation

### Related Issues

- See KNOWN_ISSUES.md #-1 for Act 1 paralysis fix details
- Part of broader 4-act balance validation

---

## Test Files - Nim Table Copy Bugs

**Priority:** MEDIUM (blocks integration test improvements)
**Status:** 🔴 **Not Started** - 74 bugs identified
**Discovered:** 2025-11-25 during post-fix audit

### Problem Description

Integration test files contain ~74 instances of direct Table modifications that don't persist:

```nim
# BROKEN - Modifies copy, changes lost:
state.houses["house1".HouseId].prestige = 5000
state.houses["house2".HouseId].eliminated = true
```

### Affected Files

| File | Bug Count | Impact |
|------|-----------|--------|
| `tests/integration/test_persistent_fleet_orders.nim` | 23 | Tests can't verify order persistence |
| `tests/integration/test_victory_conditions.nim` | 20 | Victory condition tests may pass incorrectly |
| `tests/integration/test_fleet_movement.nim` | 7 | Movement tests unreliable |
| `tests/integration/test_auto_seek_home.nim` | 8 | Auto-seek tests unreliable |
| `tests/integration/test_last_stand.nim` | 5 | Last stand tests unreliable |
| `tests/integration/test_space_guild.nim` | 4 | Guild transfer tests unreliable |
| `tests/integration/test_squadron_management.nim` | 3 | Squadron tests unreliable |
| `tests/integration/test_spy_scouts.nim` | 2 | Spy tests unreliable |
| `tests/integration/test_commissioning.nim` | 2 | Commissioning tests unreliable |
| **Total** | **74** | All integration tests affected |

### Why This Matters

- Tests may pass even when engine is broken (false positives)
- Tests may fail even when engine works (false negatives)
- Cannot rely on integration tests for regression detection
- Test setup code works (initial state) but mutation verification fails

### Solution

Apply get-modify-write pattern to all test mutations:

```nim
# CORRECT:
var house = state.houses["house1".HouseId]
house.prestige = 5000
state.houses["house1".HouseId] = house
```

### Implementation Plan

1. **Audit Phase** (30 min):
   - Review each test file to identify actual bugs vs setup code
   - Some direct writes in test setup are intentional (initial state)
   - Focus on mutations within test body that verify engine behavior

2. **Fix Phase** (2-3 hours):
   - Apply get-modify-write pattern to all test mutations
   - Run each test suite using `nimble test` to verify fixes
   - Ensure no test behavior changes (only correctness improves)

3. **Validation** (30 min):
   - Run full test suite: `nimble test`
   - Verify all tests still pass
   - Add regression test for Table copy semantics

**Estimated Effort:** 3-4 hours total

---

## Engine - Spacelift Cargo System

**Priority:** COMPLETE
**Status:** ✅ Fully implemented (2025-11-23)

- [x] Separate SpaceLiftShip type from Squadron (completed 2025-11-23)
- [x] Update Fleet to track squadrons and spacelift separately (completed 2025-11-23)
- [x] Implement cargo management as colony orders (CargoManagementOrder) (completed 2025-11-23)
- [x] Implement manual cargo order resolution (resolveCargoManagement) (completed 2025-11-23)
- [x] Implement auto-load functionality (autoLoadCargo) (completed 2025-11-23)
- [x] Add cargo validation to invasion orders (must have loaded marines) (completed 2025-11-23)
- [x] Add cargo validation to colonize orders (must have loaded PTU) (completed 2025-11-23)
- [x] Decide: auto-load at colonies or manual orders? (BOTH - dual system) (completed 2025-11-23)
- [x] Implement colony inventory tracking (marines, colonists available) (completed 2025-11-23)
- [x] Implement actual cargo transfer with quantity tracking (completed 2025-11-23)

**Files Affected:**
- `src/engine/spacelift.nim` - Complete with loadCargo/unloadCargo procs
- `src/engine/fleet.nim` - Complete
- `src/engine/orders.nim` - CargoManagementOrder complete
- `src/engine/resolve.nim` - Full cargo transfer with inventory tracking implemented
- `src/engine/commands/executor.nim` - Validation complete

**Implementation Details:**
- Manual cargo loading/unloading with colony.marines inventory tracking (resolve.nim:1065-1141)
- Automatic cargo loading with inventory checks (resolve.nim:1183-1244)
- LoadCargo: decrements colony.marines, loads onto TroopTransport ships
- UnloadCargo: unloads from ships, increments colony.marines
- ETAC ships load 1 PTU (colonist) for colonization missions
- Armies (colony.armies) remain at colonies for ground defense, not loaded on ships

---

## AI - Strategic Capabilities (Phase 2/3)

**Priority:** MEDIUM
**Status:** Phase 2/3 core infrastructure complete and compiling, heuristics pending

### Phase 2: Intelligence Operations
- [x] Intelligence data structures added
- [x] Pre-colonization reconnaissance (scouts gather planet/resource intel)
- [x] Intelligence-driven colonization target selection
- [x] Scout spy missions (SpyPlanet/SpySystem orders)
- [ ] Pre-invasion intelligence gathering
- [ ] Intelligence staleness handling (>5 turns = outdated)

### Phase 3: Fleet Coordination
- [x] Coordinated operation data structures
- [x] Task force assembly with Rendezvous orders
- [x] Strategic reserve system
- [x] FIX: Mutability error in generateFleetOrders (fixed - generateAIOrders now takes `var AIController`)
- [x] Heuristics to plan coordinated operations (identifyInvasionOpportunities, planCoordinatedInvasion)
- [x] Defense-in-depth fleet positioning (manageStrategicReserves assigns reserves to important colonies)
- [x] Strategic reserve response logic (respondToThreats moves reserves to intercept nearby enemies)

**Status:** Phase 2/3 complete and ready for balance testing

### Phase 4: Ground Force Management
- [x] Marine garrison planning (maintain garrisons at important colonies)
- [x] Transport loading logic (identify transports needing marines)
- [ ] Army construction for defensive depth (not yet implemented)
- [ ] Ground force budget allocation (using treasury checks)
- [x] Proactive garrison buildup at frontier colonies

### Phase 5: Economic Intelligence
- [x] Track enemy production capacity
- [x] Identify high-value economic targets
- [x] Economic warfare (blockade high-production colonies)
- [x] Resource denial strategy (target rich resource colonies)
- [x] Economic strength assessment for targeting

**Status:** Phase 4/5 core features complete and integrated (2025-11-23)

**Files Affected:**
- `tests/balance/ai_controller.nim` - All Phase 2/3 features implemented and compiling

---

## Economy - Minor Issues

**Priority:** LOW

- [ ] Research costs should migrate to TOML config
- [ ] Ship upkeep rates need balance testing
- [ ] Facility upkeep might need adjustment after AI testing

---

## Combat - Polish Items

**Priority:** LOW

- [ ] Multi-faction battle edge cases (3+ houses)
- [ ] Retreat mechanics balance testing
- [ ] Fighter squadron vs capital ship balance

---

## Documentation

**Priority:** LOW

- [x] API documentation system created (2025-11-23)
- [x] Regenerate API docs after cargo system implementation (completed 2025-11-23)
- [ ] Add more examples to STYLE_GUIDE.md
- [ ] Update operations.md with cargo mechanics once implemented

---

## Intel System - Fog of War Implementation

**Priority:** HIGH
**Status:** Partially implemented (engine has basic checks, but full system missing)

### Current State:
- [x] Basic visibility check implemented in engine (resolve.nim:1211-1233)
  - `hasVisibilityOn()`: Checks colony ownership, fleet presence, spy scouts
  - Used for Space Guild path validation to prevent intel leak exploits
- [ ] **Intel tables NOT implemented in storage layer**
- [ ] **Per-player view generation NOT implemented**
- [ ] **Delta-based state sync NOT implemented**

### Architecture (per docs/architecture/intel.md):

**Server Side (Daemon):**
- SQLite `intel_systems` table tracks per-player system visibility
- SQLite `intel_fleets` table tracks detected enemy fleet intel
- SQLite `intel_colonies` table tracks known colony details with staleness
- Turn resolution updates intel tables automatically
- Delta generation filters game state through intel tables before sending to clients

**Client Side:**
- Local cache of player's known game state (filtered view)
- Receives encrypted deltas from daemon (Nostr) or JSON files (localhost)
- Applies deltas to local cache
- Generates reports client-side from structured data
- CANNOT see information player doesn't have intel on

**Bandwidth Optimization:**
- Daemon sends only deltas (changes since last turn)
- Nostr: Encrypted per-player deltas via NIP-44
- Localhost: Per-player JSON files in separate house directories
- Typical delta: 2-5 KB vs 50-100 KB full state

### What's Missing:

1. **Storage layer** (src/storage/*.nim):
   - [ ] Create `intel_systems`, `intel_fleets`, `intel_colonies` tables
   - [ ] Implement per-player view queries
   - [ ] Intel update procs (visual detection, spy operations, staleness)

2. **Daemon intel updates** (src/daemon/*.nim):
   - [ ] Hook intel updates into turn resolution cycle
   - [ ] Generate per-player deltas after each turn
   - [ ] Filter game state through intel tables

3. **Client caching** (src/client/*.nim):
   - [ ] Local SQLite cache for player's view
   - [ ] Delta application logic
   - [ ] Staleness indicators in UI

4. **Transport layer** (src/transport/*.nim):
   - [ ] Per-player delta serialization
   - [ ] Chunk large deltas for Nostr (>32 KB)
   - [ ] Encrypted delta publishing

### Impact on Current Work:

**Space Guild Transfer System** (just implemented):
- ✅ Basic exploit prevention: `hasVisibilityOn()` checks prevent intel leak
- ⚠️  Temporary solution: Checks current game state, not player's intel view
- ❌ Proper solution: Guild path validation should query `intel_systems` table
- ❌ Player shouldn't know transfer failed due to enemy colony (fog of war leak)

**Workaround Status:**
Current `hasVisibilityOn()` is acceptable for now since:
- Game engine has full state (single-player AI testing)
- Prevents obvious exploits (probing enemy territory)
- Will be replaced when proper intel system is implemented

### Implementation Order:

1. **Phase 1** (Storage): Implement intel tables and queries
2. **Phase 2** (Engine): Hook intel updates into turn resolution
3. **Phase 3** (Daemon): Generate and distribute per-player deltas
4. **Phase 4** (Client): Local caching and delta application
5. **Phase 5** (Refactor): Replace `hasVisibilityOn()` with intel table queries

### Related Files:
- docs/architecture/intel.md - Complete fog of war spec
- docs/architecture/dataflow.md - Turn cycle with intel updates
- docs/architecture/storage.md - Intel table schemas (section 5)
- src/engine/resolve.nim:1211 - Temporary visibility check

---

## Notes

- **Archive policy:** When issue is resolved, move details to relevant commit message or STATUS.md milestone entry
- **Priority guide:** CRITICAL = blocks testing, HIGH = needed soon, MEDIUM = nice to have, LOW = polish
- **Do NOT create separate markdown files** - add issues here
