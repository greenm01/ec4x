# EC4X Open Issues & Gaps

**Last Updated:** 2025-11-23

This is the SINGLE source of truth for known bugs, missing features, and technical debt.
When an issue is fixed, check it off and update STATUS.md.

---

## Engine - Spacelift Cargo System

**Priority:** HIGH
**Status:** Architecture fixed (Phase 1), cargo loading not yet implemented

- [x] Separate SpaceLiftShip type from Squadron (completed 2025-11-23)
- [x] Update Fleet to track squadrons and spacelift separately (completed 2025-11-23)
- [ ] Implement LoadCargo fleet order (marines/colonists)
- [ ] Implement UnloadCargo fleet order
- [ ] Add cargo validation to invasion orders (must have loaded marines)
- [ ] Add cargo validation to colonize orders (must have loaded PTU)
- [ ] Decide: auto-load at colonies or manual orders?

**Files Affected:**
- `src/engine/spacelift.nim` - Architecture complete
- `src/engine/fleet.nim` - Architecture complete
- `src/engine/orders.nim` - Need LoadCargo/UnloadCargo
- `src/engine/resolve.nim` - Need cargo transfer logic
- `src/engine/commands/executor.nim` - Need validation updates

**Notes:**
- For now, AI testing assumes transports auto-load (workaround)
- After cargo system implemented, re-test AI invasion logic
- See spacelift.nim header comments for architecture details

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
- [ ] Heuristics to plan coordinated operations
- [ ] Defense-in-depth fleet positioning
- [ ] Strategic reserve response logic

**Files Affected:**
- `tests/balance/ai_controller.nim` - Phase 2/3 implementations complete, compiles successfully

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
