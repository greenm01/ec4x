# EC4X Quality-of-Life Features Roadmap

**Last Updated:** 2025-11-26
**Status:** Design complete, implementation in progress

## Overview

This document outlines quality-of-life features that improve gameplay for both human players and AI, reduce micromanagement, prevent mistakes, and optimize engine performance.

All features follow the principle: **Comprehensive logging at every level** for debugging, diagnostics, and player transparency.

---

## Priority Matrix

| Priority | Feature | Status | Benefit | Effort |
|----------|---------|--------|---------|--------|
| **HIGH** | Budget Tracking | ✅ COMPLETE | Prevents overspending | 2 days |
| **HIGH** | Standing Orders | 🟡 50% DONE | Reduces micromanagement | 3.5 days |
| **HIGH** | Fleet Ownership Validation | ⏳ PLANNED | Prevents cheating | 0.5 days |
| **MEDIUM** | Movement Range Calculator | ⏳ PLANNED | Prevents invalid orders | 1 day |
| **MEDIUM** | Construction Queue Preview | ⏳ PLANNED | Better planning | 0.5 days |
| **MEDIUM** | Batch Order System | ⏳ PLANNED | Mass operations | 1 day |
| **LOW** | Order Undo/Rollback | ⏳ PLANNED | Convenience | 0.5 days |
| **LOW** | Turn History Diff Viewer | ⏳ PLANNED | Analysis tool | 0.5 days |

---

## ✅ COMPLETED: Budget Tracking System

**Implemented:** 2025-11-26
**Files Modified:**
- `src/engine/orders.nim` - OrderValidationContext, budget validation
- `src/ai/rba/budget.nim` - BudgetTracker for AI
- `src/engine/resolution/economy_resolution.nim` - Budget validation integration

### What It Does

**3-Tier System:**
1. **Engine-Level**: Validates all orders against available budget
2. **AI-Level**: Tracks spending across objectives to prevent overspending
3. **Preview**: Shows total costs before submission

### Comprehensive Logging Examples

```
[Economy] house-atreides Build Order Validation: 15 orders, 1000 PP available
[Economy] Build order validated: 50 PP committed, 950 PP remaining
[Economy] Build order rejected: need 200 PP, have 45 PP remaining
[Economy] house-atreides Build Order Summary: 12/15 orders accepted,
          847 PP committed, 153 PP remaining, 3 orders rejected

[AI] house-atreides Budget Tracker initialized: 1000 PP total
[AI] house-atreides Budget Summary: Total=1000PP, Spent=847PP, Remaining=153PP
[AI]   Expansion: 522/550PP (95%), 28PP remaining
[AI]   Military: 235/300PP (78%), 65PP remaining
```

### Impact
- **Before**: AI could overspend by 60%+ (1650 PP when only 1000 PP available)
- **After**: Impossible to overspend, full visibility

---

## 🟡 IN PROGRESS: Standing Orders System

**Implementation Status:** 50% complete (types done, execution pending)
**Design Doc:** `docs/architecture/standing-orders.md`
**Files Modified:**
- `src/engine/order_types.nim` - StandingOrder types ✅
- `src/engine/gamestate.nim` - standingOrders table ✅
- Standing order execution logic - ⏳ PENDING

### What It Does

**Persistent fleet behaviors** that execute automatically when no explicit order given:

| Order Type | Purpose | Example |
|------------|---------|---------|
| **PatrolRoute** | Follow path indefinitely | Border patrol loop |
| **DefendSystem** | Guard system per ROE | Homeworld defense |
| **AutoColonize** | ETACs find & colonize | Automatic expansion |
| **AutoRepair** | Return to shipyard when damaged | Self-healing fleets |
| **AutoEvade** | Retreat when outnumbered | Preserve forces |
| **GuardColony** | Defend specific colony | Strategic defense |
| **BlockadeTarget** | Maintain blockade | Siege warfare |

### ROE Integration

Standing orders respect **Rules of Engagement (0-10)**:
- **ROE 0**: Avoid all hostiles
- **ROE 5**: Engage if evenly matched
- **ROE 10**: Fight regardless of odds

Example: Patrol with ROE=2 → retreats from stronger forces

### Comprehensive Logging Examples

```
[Orders] === Standing Orders Execution: Turn 42 ===
[Orders] fleet-alpha-1 Standing Order Created: PatrolRoute with ROE=5
[Orders] fleet-alpha-1 Patrol: system-5 → system-7 (step 2/4)
[Orders] fleet-beta-2 Auto-Colonize: Targeting system-12 (class Eden, 3 jumps)
[Orders] fleet-gamma-3 Auto-Repair: HP 35% < threshold 50%, returning to system-1
[Orders] Standing Orders Summary: 12 executed, 3 skipped, 1 failed

[Debug] fleet-alpha-1 Auto-Evade: Enemy strength 450, our strength 200,
        ratio 0.44 < ROE 5 threshold 0.5 → evading
[Debug] fleet-beta-2 Auto-Colonize: Evaluating 5 candidate systems
[Debug] fleet-gamma-3 Auto-Repair: HP 85% above threshold 50%, no action

[Warn] fleet-delta-4 Standing order failed: No valid path to target
[Warn] fleet-epsilon-5 Patrol route blocked: system-7 now enemy-controlled
```

### Benefits

| Stakeholder | Benefit |
|-------------|---------|
| **Players** | Set-and-forget for routine tasks, consistent behavior |
| **AI** | Simpler order generation (doctrine + exceptions vs all orders) |
| **Code** | Separation of concerns, comprehensive logging, testable |

### Implementation Status

✅ **Phase 1: Core System** (COMPLETE)
- StandingOrder types added to `order_types.nim`
- `standingOrders: Table[FleetId, StandingOrder]` in GameState
- Compiles successfully

⏳ **Phase 2: Execution Logic** (PENDING)
- `executeStandingOrders()` function
- PatrolRoute, DefendSystem, AutoColonize implementation
- Comprehensive logging integration

⏳ **Phase 3: AI Integration** (PENDING)
- AI issues standing orders for routine tasks
- Diagnostic metrics

⏳ **Phase 4: Testing** (PENDING)
- Balance tests with standing orders enabled

---

## ⏳ PLANNED: Fleet Ownership & Target Validation

**Priority:** HIGH
**Effort:** 0.5 days
**Status:** Design complete, awaiting implementation

### What It Does

Validates orders before execution to prevent:
1. **Ownership violations**: Players issuing orders to enemy fleets
2. **Invalid targets**: Movement to unreachable/nonexistent systems
3. **Conflicting orders**: Fleet can't move and patrol simultaneously

### Implementation Approach

```nim
proc validateFleetOwnership*(order: FleetOrder, state: GameState): ValidationResult =
  ## Validate fleet belongs to house issuing order
  if order.fleetId notin state.fleets:
    return ValidationResult(valid: false, error: "Fleet not found")

  let fleet = state.fleets[order.fleetId]
  if fleet.owner != order.issuedBy:  # Need to add issuedBy field
    logWarn(LogCategory.lcOrders,
            &"SECURITY: {order.issuedBy} attempted to control {order.fleetId} " &
            &"(owned by {fleet.owner})")
    return ValidationResult(valid: false, error: "Fleet not owned by house")

  return ValidationResult(valid: true, error: "")
```

### Comprehensive Logging

```
[Orders] Validating 15 orders for house-atreides
[Orders] ✓ fleet-alpha-1: Move order valid (target system-5 reachable)
[Warn] SECURITY: house-harkonnen attempted to control fleet-alpha-1 (owned by house-atreides)
[Orders] ✗ fleet-beta-2: Invalid target system-99 (does not exist)
[Orders] Order Validation Summary: 13/15 valid, 2 rejected
```

---

## ⏳ PLANNED: Movement Range Calculator

**Priority:** MEDIUM
**Effort:** 1 day
**Status:** Design complete

### What It Does

Pre-calculates reachable systems for fleets, preventing invalid movement orders:

```nim
proc calculateMovementRange*(fleet: Fleet, starmap: StarMap,
                             maxJumps: int = 3): seq[SystemId] =
  ## Returns all systems fleet can reach within movement allowance
  ## Accounts for:
  ## - Jump lane restrictions (normal vs restricted)
  ## - Cloaking tech requirements
  ## - Fuel/supply limits (future)
  ## - Hostile territory (future)
```

### Player Experience

```bash
> client move-options fleet-alpha-1
  Reachable systems (3 jumps):
    ✓ system-delta (2 jumps, normal lanes)
    ✓ system-gamma (3 jumps, normal lanes)
    ⚠ system-beta (2 jumps, 1 restricted - need Cloaking)
    ✗ system-omega (4 jumps, out of range)
```

### Comprehensive Logging

```
[Fleet] Calculating movement range for fleet-alpha-1 at system-5
[Debug] Pathfinding: Found 12 reachable systems within 3 jumps
[Debug] system-7: 2 jumps via normal lanes (valid)
[Debug] system-9: 2 jumps via restricted lane (invalid: no cloaking)
[Fleet] Movement range: 10 valid systems, 2 restricted, 1 out of range
```

### Performance Optimization

- **Cache results**: Movement range valid for entire turn
- **Nim inline**: Mark hot-path functions with `{.inline.}`
- **Pre-allocate**: `newSeqOfCap[SystemId](expected_size)`

---

## ⏳ PLANNED: Construction Queue Preview

**Priority:** MEDIUM
**Effort:** 0.5 days

### What It Does

Shows construction queue with completion estimates:

```
Colony Prime - Construction Queue (3 active, 5 waiting):

Active (Shipyard III, 300 IU → 300 PP/turn):
  [1] ████████░░ Battleship (650 PP) - Turn 44
  [2] ██░░░░░░░░ Starbase (300 PP)  - Turn 46
  [3] ░░░░░░░░░░ ETAC (50 PP)       - Turn 47

Waiting:
  [4] Frigate (30 PP)       - Turn 48
  [5] Destroyer (40 PP)     - Turn 49
```

### Comprehensive Logging

```
[Economy] Colony Prime construction queue updated: 3 active, 5 waiting
[Debug] Project 1: Battleship 520/650 PP (80%), 1.3 turns remaining
[Debug] Project 2: Starbase 0/300 PP (0%), queued behind project 1
[Economy] Queue capacity: 8/10 docks used
```

---

## ⏳ PLANNED: Batch Order System

**Priority:** MEDIUM
**Effort:** 1 day

### What It Does

Mass operations with filters to reduce tedium:

```bash
# Build scouts at ALL colonies with shipyards
> client batch-build --filter="has:shipyard" --ship=Scout --quantity=1
  Applied to 8 colonies: system-1, system-5, system-7...

# Set tax rate to 60% across all core worlds
> client batch-tax --filter="population>500" --rate=60
  Applied to 4 colonies

# Invest 10% of budget in CST research across all colonies
> client batch-research --field=CST --percent=10
  Allocated 100 PP across 10 colonies (10 PP each)
```

### Comprehensive Logging

```
[Orders] Batch operation: build Scout at colonies with shipyards
[Orders] Filter "has:shipyard" matched 8 colonies
[Orders] Generated 8 build orders: system-1, system-5, system-7...
[Orders] Batch operation complete: 8 orders created, 125 PP committed

[Warn] Batch operation partially failed: 2/10 colonies rejected (insufficient docks)
```

---

## Implementation Guidelines

### Nim Performance Optimizations

Based on budget tracking implementation:

1. **Use `var` parameters for mutations**
   ```nim
   proc recordSpending*(tracker: var BudgetTracker, amount: int) =
     tracker.spent += amount  # Modifications persist
   ```

2. **Cache table lookups**
   ```nim
   # BAD: Multiple lookups
   for order in orders:
     let colony = state.colonies[order.colonySystem]  # Lookup every iteration

   # GOOD: Cache reference
   let colony = state.colonies[order.colonySystem]  # Lookup once
   for order in orders:
     # Use cached colony
   ```

3. **Use `{.inline.}` for hot paths**
   ```nim
   proc canAfford*(tracker: BudgetTracker, cost: int): bool {.inline.} =
     tracker.remaining >= cost
   ```

4. **Pre-allocate sequences**
   ```nim
   var result = newSeqOfCap[BuildOrder](estimatedSize)  # No reallocs
   for i in 0..<count:
     result.add(...)
   ```

### Logging Standards

**Every QoL feature must have:**

1. **INFO logs** - High-level actions
   ```nim
   logInfo(LogCategory.lcOrders,
           &"{fleetId} Standing Order Created: {orderType}")
   ```

2. **DEBUG logs** - Decision logic
   ```nim
   logDebug(LogCategory.lcOrders,
            &"{fleetId} Evaluating 5 candidate systems for colonization")
   ```

3. **WARN logs** - Failures
   ```nim
   logWarn(LogCategory.lcOrders,
           &"{fleetId} Operation failed: {reason}")
   ```

4. **Summary logs** - Per-turn aggregate
   ```nim
   logInfo(LogCategory.lcOrders,
           &"Standing Orders: {executed} executed, {failed} failed")
   ```

### Testing Requirements

All QoL features must:
1. **Compile cleanly** - No warnings
2. **Pass balance tests** - `nimble testBalanceQuick`
3. **Have diagnostic metrics** - Track usage in `diagnostics.nim`
4. **Generate logs** - Verify logging output

---

## Next Steps

### Immediate (Week 1)
1. ✅ Budget tracking (COMPLETE)
2. 🟡 Standing orders execution logic (50% done)
3. ⏳ Fleet ownership validation

### Short-term (Week 2-3)
1. Movement range calculator
2. Construction queue preview
3. Batch order system

### Long-term (Month 2+)
1. Order undo/rollback
2. Turn history diff viewer
3. Advanced standing orders (conditional triggers)

---

## Success Metrics

| Metric | Target | Current |
|--------|--------|---------|
| **AI overspending incidents** | 0 | 0 ✅ (budget tracking) |
| **Player order errors** | <5% | TBD |
| **AI order generation time** | <100ms/turn | TBD |
| **Player satisfaction** | >8/10 | TBD |
| **Code coverage (QoL)** | >80% | ~40% |

---

## Related Documentation

- [Budget Tracking Implementation](../src/engine/orders.nim) - Complete system
- [Standing Orders Design](./architecture/standing-orders.md) - Full specification
- [Architecture Overview](./architecture/overview.md) - System integration
- [AI RBA System](./ai/README.md) - AI integration points
