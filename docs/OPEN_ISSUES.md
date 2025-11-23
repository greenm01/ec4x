# EC4X Open Issues & Gaps

**Last Updated:** 2025-11-23

This is the SINGLE source of truth for known bugs, missing features, and technical debt.
When an issue is fixed, check it off and update STATUS.md.

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
