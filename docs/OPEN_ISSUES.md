# EC4X Open Issues & Gaps

**Last Updated:** 2025-11-23

This is the SINGLE source of truth for known bugs, missing features, and technical debt.
When an issue is fixed, check it off and update STATUS.md.

---

## Engine - Spacelift Cargo System

**Priority:** HIGH
**Status:** Core functionality complete (2025-11-23), inventory tracking pending

- [x] Separate SpaceLiftShip type from Squadron (completed 2025-11-23)
- [x] Update Fleet to track squadrons and spacelift separately (completed 2025-11-23)
- [x] Implement cargo management as colony orders (CargoManagementOrder) (completed 2025-11-23)
- [x] Implement manual cargo order resolution (resolveCargoManagement) (completed 2025-11-23)
- [x] Implement auto-load functionality (autoLoadCargo) (completed 2025-11-23)
- [x] Add cargo validation to invasion orders (must have loaded marines) (completed 2025-11-23)
- [x] Add cargo validation to colonize orders (must have loaded PTU) (completed 2025-11-23)
- [x] Decide: auto-load at colonies or manual orders? (BOTH - dual system) (completed 2025-11-23)
- [ ] Implement colony inventory tracking (marines, colonists available)
- [ ] Implement actual cargo transfer with quantity tracking

**Files Affected:**
- `src/engine/spacelift.nim` - Architecture complete
- `src/engine/fleet.nim` - Architecture complete
- `src/engine/orders.nim` - CargoManagementOrder complete
- `src/engine/resolve.nim` - Cargo resolution complete (TODO: inventory)
- `src/engine/commands/executor.nim` - Validation complete

**Notes:**
- Cargo loading framework complete, but TODO items remain for colony inventory checks
- Auto-load and manual cargo orders both functional
- AI can now issue cargo orders, but currently logs placeholder messages
- Next: Implement Colony inventory fields for marines/colonists tracking

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
- [ ] Regenerate API docs after cargo system implementation
- [ ] Add more examples to STYLE_GUIDE.md
- [ ] Update operations.md with cargo mechanics once implemented

---

## Notes

- **Archive policy:** When issue is resolved, move details to relevant commit message or STATUS.md milestone entry
- **Priority guide:** CRITICAL = blocks testing, HIGH = needed soon, MEDIUM = nice to have, LOW = polish
- **Do NOT create separate markdown files** - add issues here
