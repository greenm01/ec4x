# Turn Resolution System - Implementation Analysis

**Date:** 2025-11-21
**Status:** Architecture complete, core implementations partial
**Goal:** Make EC4X playable by completing turn-by-turn gameplay loop

---

## Executive Summary

The turn resolution system has a **well-designed 4-phase architecture** already in place, with several components fully implemented and others marked as TODO. This analysis identifies what exists, what's missing, and provides an implementation plan to complete the system.

**Current Status:**
- ✅ Architecture: 4-phase turn pipeline defined
- ✅ Order system: Types and validation framework in place
- ✅ Movement: Full pathfinding with lane traversal rules
- ✅ Economy: M5 engine integration (income + maintenance)
- ✅ Colonization: Full prestige-based colonization
- ✅ Diplomacy: Status timers and elimination checks
- ✅ Combat: Battle & bombardment resolution COMPLETE (2025-11-21)
- ✅ Building: Construction orders COMPLETE (2025-11-21)
- ⏳ Validation: Basic framework, needs expansion

---

## 4-Phase Turn Architecture

### Phase 1: Conflict Phase ✅ COMPLETE
**Purpose:** Resolve all combat before other activities
**Why First:** Destroyed infrastructure affects production in Phase 2

**Implemented:**
- ✅ System identification (finds hostile fleet encounters)
- ✅ `resolveBattle()` - FULLY IMPLEMENTED (resolve.nim:458-606)
  - Gathers all fleets at system
  - Groups into attackers/defenders by ownership
  - Converts Fleet.squadrons → CombatSquadrons → TaskForces
  - Calls combat_engine.resolveCombat()
  - Applies losses to game state (updates crippled, removes destroyed)
  - Generates accurate combat reports
- ✅ `resolveBombardment()` - FULLY IMPLEMENTED (resolve.nim:622-691)
  - Validates fleet location and colony existence
  - Converts squadrons to CombatSquadrons
  - Calls conductBombardment() from ground combat system
  - Applies infrastructure damage to colonies
  - Generates bombardment events

**Dependencies:**
- ✅ src/engine/combat/engine.nim (integrated)
- ✅ src/engine/combat/ground.nim (integrated)

---

### Phase 2: Income Phase ✅ Complete
**Purpose:** Calculate taxes, production, and research
**Why Second:** Uses post-combat infrastructure values

**Implemented:**
- ✅ Ongoing espionage effects applied (lines 148-160)
- ✅ Colony conversion to economy format (lines 162-178)
- ✅ Tax policy building (lines 180-188)
- ✅ Tech level extraction (lines 200-203)
- ✅ Treasury management (lines 206-208)
- ✅ M5 economy engine call (lines 210-216)
- ✅ Results applied to game state (lines 218-228)
- ✅ Prestige events from economic activity (lines 224-228)

**Notes:**
- Complete integration with M5 economy engine
- All economy config values used
- Research prestige tracked (line 232 comment)

---

### Phase 3: Command Phase ✅ COMPLETE
**Purpose:** Execute player orders
**Why Third:** Orders execute after income generated

**Implemented:**
- ✅ `resolveBuildOrders()` - FULLY IMPLEMENTED (resolve.nim:272-365)
  - Validates colony existence and ownership
  - Checks for existing construction in progress
  - Converts gamestate.Colony ↔ economy.Colony
  - Creates construction projects (ships, buildings, infrastructure)
  - Calls construction.startConstruction()
  - Updates game state with construction progress
  - Generates construction started events
- ✅ Movement order priority sorting (lines 248-263)
- ✅ Movement execution with pathfinding (lines 309-428)
  - Full lane traversal rules (2-jump major lanes, 1-jump minor/restricted)
  - Ownership-based speed bonuses
  - Fleet encounter detection
- ✅ Colonization with prestige rewards (lines 429-471)

**Dependencies:**
- ✅ src/engine/economy/construction.nim (integrated)
- ⏳ construction_config.nim (exists, not yet integrated - uses hardcoded values)

---

### Phase 4: Maintenance Phase ✅ Complete
**Purpose:** Upkeep, timers, victory checks
**Why Last:** End-of-turn cleanup and state updates

**Implemented:**
- ✅ Espionage effect timer decrements (lines 458-470)
- ✅ Dishonored status timer updates (lines 474-479)
- ✅ Diplomatic isolation timer updates (lines 482-486)
- ✅ Colony conversion for maintenance (lines 489-503)
- ✅ Fleet data collection (lines 506-512)
- ✅ Treasury management (lines 515-517)
- ✅ M5 maintenance engine call (lines 520-524)
- ✅ Upkeep costs applied (lines 527-529)
- ✅ Completed project reporting (lines 532-533)
- ✅ Elimination checks (lines 536-551)
  - Standard: no colonies and no fleets
- ✅ Defensive collapse tracking (lines 554-570)
  - Prestige < 0 for consecutive turns
  - Uses globalPrestigeConfig values
- ✅ Victory condition check (lines 573-577)

**Notes:**
- Fully integrated with prestige_config
- Complete diplomatic status management
- Comprehensive elimination system

---

## Order System Analysis

### Order Types (orders.nim:8-25)

**Fully Supported:**
- ✅ Move - Full pathfinding with lane rules
- ✅ Colonize - Prestige-based establishment
- ✅ Hold - Trivial implementation

**Partially Supported:**
- ⏳ Bombard - Structure exists, needs implementation
- ⏳ Invade - Structure exists, needs implementation
- ⏳ Blitz - Structure exists, needs implementation

**Not Yet Supported:**
- ⏳ SeekHome - Defined but not implemented
- ⏳ Patrol - Defined but not implemented
- ⏳ GuardStarbase - Defined but not implemented
- ⏳ GuardPlanet - Defined but not implemented
- ⏳ BlockadePlanet - Defined but not implemented
- ⏳ SpyPlanet - Defined but not implemented
- ⏳ SpySystem - Defined but not implemented
- ⏳ HackStarbase - Defined but not implemented
- ⏳ JoinFleet - Defined but not implemented
- ⏳ Rendezvous - Defined but not implemented
- ⏳ Salvage - Defined but not implemented

---

## Order Validation System

### Current Implementation (orders.nim:64-157)

**Implemented Validations:**
- ✅ Fleet existence checks
- ✅ Move order: target system validation
- ✅ Colonize order: spacelift ship requirement
- ✅ Combat orders: military ship requirement
- ✅ Join fleet: target fleet existence
- ✅ Order packet: house existence and turn number

**TODO Validations (marked in code):**
- ⚠️ Move pathfinding check (line 89)
- ⚠️ Colonize system already colonized check (line 105)
- ⚠️ Join fleet location check (line 129)
- ⚠️ Build orders resource/capacity validation (line 153)
- ⚠️ Research allocation validation (line 154)
- ⚠️ Diplomatic action validation (line 155)

---

## Implementation Priority Matrix

### Critical Path (Must Have for Playability)

**Priority 1: Combat Resolution** 🔴
- **File:** src/engine/resolve.nim
- **Functions:** `resolveBattle()`, `resolveBombardment()`
- **Impact:** Core gameplay loop blocked without this
- **Effort:** Medium (systems exist, need integration)
- **Dependencies:** combat/engine.nim already integrated with combat_config

**Priority 2: Build Orders** 🔴
- **File:** src/engine/resolve.nim
- **Function:** `resolveBuildOrders()`
- **Impact:** Players can't construct ships/buildings
- **Effort:** Medium (economy system ready)
- **Dependencies:** construction_config ready for integration

**Priority 3: Order Validation Completion** 🟡
- **File:** src/engine/orders.nim
- **Functions:** Expand validation checks
- **Impact:** Prevents illegal moves, better UX
- **Effort:** Low (framework exists)
- **Dependencies:** None

### Extended Features (Nice to Have)

**Priority 4: Advanced Fleet Orders** 🟢
- SeekHome, Patrol, Guard orders
- **Impact:** Tactical depth
- **Effort:** Low-Medium per order

**Priority 5: Espionage Orders** 🟢
- SpyPlanet, SpySystem, HackStarbase
- **Impact:** Strategic gameplay variety
- **Effort:** Medium (espionage system exists)

**Priority 6: Fleet Management** 🟢
- JoinFleet, Rendezvous, Salvage
- **Impact:** Operational flexibility
- **Effort:** Low-Medium

---

## Data Flow Diagram

```
Turn N Orders
     ↓
Validation (orders.nim)
     ↓
Phase 1: CONFLICT
  - Space battles → combat/engine.nim
  - Bombardments → combat/ground.nim
  - Invasions → combat/ground.nim
     ↓
Phase 2: INCOME
  - Espionage effects → espionage/
  - Economy → economy/econ_engine.nim (M5)
  - Prestige → prestige.nim
     ↓
Phase 3: COMMAND
  - Build orders → economy/ (TODO)
  - Movement → starmap.findPath()
  - Colonization → economy/colonization.nim
     ↓
Phase 4: MAINTENANCE
  - Upkeep → economy/econ_engine.nim (M5)
  - Timer decrements → resolve.nim
  - Elimination checks → prestige_config
  - Victory checks → gamestate.nim
     ↓
Turn N+1 State
```

---

## Missing Pieces Analysis

### 1. Combat Resolution (resolveBattle)

**What's Needed:**
```nim
proc resolveBattle(state: var GameState, systemId: SystemId,
                  combatReports: var seq[CombatReport], events: var seq[GameEvent]) =
  # 1. Gather all fleets at systemId
  var attackers: seq[Fleet] = @[]
  var defenders: seq[Fleet] = @[]

  # 2. Determine attacker/defender based on system ownership
  let colonyOwner = if systemId in state.colonies:
                      some(state.colonies[systemId].owner)
                    else:
                      none(HouseId)

  # 3. Build BattleContext with tech levels
  for fleetId, fleet in state.fleets:
    if fleet.location == systemId:
      let techLevel = state.houses[fleet.owner].techTree.levels.energyLevel
      # Group into attackers/defenders...

  # 4. Call combat system
  let result = combat.resolveBattle(battleContext)

  # 5. Apply losses to state
  # 6. Generate reports
```

**Existing Systems to Use:**
- src/engine/combat/engine.nim (line references needed)
- globalCombatConfig for CER tables
- globalShipsConfig for ship stats

---

### 2. Bombardment Resolution (resolveBombardment)

**What's Needed:**
```nim
proc resolveBombardment(state: var GameState, houseId: HouseId, order: FleetOrder,
                       events: var seq[GameEvent]) =
  # 1. Validate fleet is at target system
  let fleetOpt = state.getFleet(order.fleetId)
  if fleetOpt.isNone: return
  let fleet = fleetOpt.get()

  # 2. Get target colony
  if order.targetSystem.isNone: return
  let targetId = order.targetSystem.get()
  if targetId notin state.colonies: return

  # 3. Call bombardment system
  let result = combat.resolveBombardment(fleet, state.colonies[targetId])

  # 4. Apply damage
  state.colonies[targetId].infrastructureDamage = result.damage

  # 5. Generate events
```

**Existing Systems to Use:**
- src/engine/combat/ground.nim:76 - getBombardmentCER()
- globalCombatConfig.bombardment

---

### 3. Build Order Resolution (resolveBuildOrders)

**What's Needed:**
```nim
proc resolveBuildOrders(state: var GameState, packet: OrderPacket, events: var seq[GameEvent]) =
  for order in packet.buildOrders:
    # 1. Validate colony exists and has capacity
    if order.colonySystem notin state.colonies: continue
    let colony = state.colonies[order.colonySystem]

    # 2. Check treasury
    let cost = calculateBuildCost(order.buildType, order.quantity)
    if state.houses[packet.houseId].treasury < cost: continue

    # 3. Start construction
    # Call economy.startConstruction()

    # 4. Deduct cost
    state.houses[packet.houseId].treasury -= cost

    # 5. Generate events
```

**Existing Systems to Use:**
- construction_config.nim (ready to integrate)
- src/engine/economy/ (partially integrated)

---

## Testing Strategy

### Unit Tests Needed

1. **Order Validation Tests**
   - Valid orders pass
   - Invalid orders rejected with correct errors
   - Edge cases (missing fleets, invalid systems)

2. **Phase Resolution Tests**
   - Each phase produces expected state changes
   - Phase ordering correct (conflict before income)
   - Timer decrements work correctly

3. **Combat Integration Tests**
   - Battles resolve correctly
   - Ship losses applied to state
   - Combat reports generated

4. **Economy Integration Tests**
   - Income calculated correctly
   - Upkeep deducted
   - Construction costs applied

### Integration Tests Needed

1. **Full Turn Tests**
   - Complete turn resolution end-to-end
   - Multi-house scenarios
   - Complex order interactions

2. **Victory Condition Tests**
   - Elimination detection
   - Defensive collapse
   - Victory detection

---

## Implementation Plan

### Phase 1: Critical Combat (Week 1)
1. Implement `resolveBattle()`
   - Integrate with combat/engine.nim
   - Apply ship losses
   - Generate combat reports
2. Implement `resolveBombardment()`
   - Use ground.nim bombardment system
   - Apply infrastructure damage
3. Test combat resolution
   - Unit tests for battle logic
   - Integration tests with turn system

### Phase 2: Build System (Week 2)
1. Implement `resolveBuildOrders()`
   - Integrate construction_config
   - Validate resources
   - Start construction projects
2. Expand validation system
   - Build order validation
   - Resource checks
3. Test build system
   - Construction tests
   - Resource validation tests

### Phase 3: Extended Orders (Week 3)
1. Implement patrol/guard orders
2. Implement espionage orders
3. Implement fleet management orders
4. Comprehensive testing

### Phase 4: Polish & Testing (Week 4)
1. Integration testing
2. Multi-turn scenarios
3. Victory condition testing
4. Performance optimization

---

## Success Criteria

**Minimum Viable Turn System:**
- ✅ Orders can be created and validated
- ⏳ Combat resolves with ship losses
- ⏳ Build orders create ships/buildings
- ✅ Movement works with pathfinding
- ✅ Economy calculates income/upkeep
- ✅ Elimination and victory detected

**Complete Turn System:**
- All 26 order types implemented
- Full validation for all order types
- Comprehensive test coverage (>80%)
- Performance: <1s per turn for 6-player game
- Documentation: All systems documented

---

## File Modification Summary

**Files to Modify:**
1. **src/engine/resolve.nim** (primary work)
   - Complete resolveBattle() (lines 419-439)
   - Complete resolveBombardment() (lines 441-449)
   - Complete resolveBuildOrders() (lines 272-277)

2. **src/engine/orders.nim** (validation expansion)
   - Add pathfinding validation (line 89)
   - Add colonization checks (line 105)
   - Add resource validation (line 153-155)

3. **tests/** (new test files)
   - tests/test_turn_resolution.nim
   - tests/test_order_validation.nim
   - tests/test_combat_integration.nim

**Files to Read (for integration):**
- src/engine/combat/engine.nim
- src/engine/economy/construction.nim (if exists)
- src/engine/config/construction_config.nim

---

## Conclusion

The turn resolution system is **75% complete** with excellent architecture and several fully functional subsystems. The remaining 25% consists of:

1. **Combat resolution integration** (critical)
2. **Build order processing** (critical)
3. **Extended order types** (optional)
4. **Enhanced validation** (quality of life)

**Estimated Effort:** 2-3 weeks for minimum viable system, 4 weeks for complete system.

**Biggest Risk:** Combat system integration complexity (unknown unknowns in combat/engine.nim)

**Next Step:** Implement `resolveBattle()` function to unblock critical gameplay path.

---

**Document Status:** Complete analysis
**Ready for Implementation:** Yes
**Blocking Issues:** None identified
