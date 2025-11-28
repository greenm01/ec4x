# RBA Standing Orders Integration

## Overview

This document describes how the RBA AI system uses engine standing orders, specifically the distinction between **strategic commitments** and **fallback behaviors**.

Related documentation:
- Engine design: `docs/architecture/standing-orders.md`
- RBA architecture: `docs/ai/ARCHITECTURE.md`

## The Problem: Command Hierarchy vs Engine Design

### Engine's Standing Orders Design

The engine treats ALL standing orders as **fallback behaviors**:
- Standing orders execute only when a fleet has NO explicit order
- Explicit orders always take priority over standing orders
- This is by design for player quality-of-life (see `docs/architecture/standing-orders.md`)

```nim
# Engine logic (src/engine/standing_orders.nim:796-803)
for fleetId, fleet in state.fleets:
  if fleetId in state.fleetOrders:  # Has explicit order?
    skippedCount += 1
    continue  # Skip standing order execution
```

### RBA's Command Hierarchy

The RBA AI has a **command hierarchy**:
1. **Admiral** (strategic) - Assigns strategic priorities (DefendSystem for colony defense)
2. **Tactical** (operational) - Generates tactical orders (Move, Hold, Patrol)
3. **Logistics** (support) - Optimizes asset lifecycle (repairs, rebalancing)

**The Conflict**: Admiral's DefendSystem assignments were implemented as standing orders, but Tactical was issuing explicit orders (Hold, Move for colonization) that overrode them. This caused Unknown-Unknown #3: "Standing Orders: 4 assigned, 0 executed, 4 under tactical control"

## The Solution: Strategic vs Fallback Distinction

### Architecture Decision

**RBA-Level Fix** (chosen) vs Engine-Level Fix (considered but rejected):

**Why RBA-Level**:
- Preserves engine simplicity (standing orders = fallback, as designed)
- The distinction between "strategic" and "fallback" is an AI command hierarchy concern, not a game mechanic
- No breaking changes for players or other AI implementations
- Clear separation: Admiral (strategic) → explicit orders, Standing Orders Manager (tactical) → fallback orders

**Alternative Considered**: Add priority/category to engine's StandingOrder type so engine can distinguish strategic vs fallback. Rejected because:
- More complex engine changes
- Would require player UI updates
- Broader scope than the actual problem
- Could be revisited later if players request "priority standing orders"

### Implementation

**File**: `src/ai/rba/orders.nim`

The order generation flow now has two standing orders phases:

```nim
# Phase 1: Standing Orders Assignment (line 413-428)
let standingOrders = assignStandingOrders(controller, filtered, filtered.turn)
controller.standingOrders = standingOrders

# Phase 2: Strategic Conversion (line 430-461)
# Convert DefendSystem/AutoRepair to explicit FleetOrders BEFORE Tactical
for fleetId, standingOrder in standingOrders:
  if standingOrder.orderType in {DefendSystem, AutoRepair}:
    let orderOpt = convertStandingOrderToFleetOrder(standingOrder, fleet, filtered)
    if orderOpt.isSome:
      result.fleetOrders.add(orderOpt.get())  # Now explicit!
      strategicOrdersConverted += 1

# Phase 3: Tactical Orders (line 463-468)
# Tactical generates orders, but skips fleets with explicit orders (including strategic conversions)
let tacticalOrders = generateFleetOrders(controller, filtered, rng)

# Phase 4: Fallback Execution (line 569-616)
# Convert remaining standing orders for fleets WITHOUT explicit orders
for fleetId, standingOrder in standingOrders:
  if standingOrder.orderType in {DefendSystem, AutoRepair}:
    continue  # Already converted in Phase 2

  if fleetId notin fleetsWithExplicitOrders:
    # Execute fallback standing order (AutoEvade, AutoColonize, etc.)
```

### Standing Order Categories

**Strategic Orders** (converted to explicit FleetOrders immediately):
- **DefendSystem** - Admiral's strategic assignment of Defender fleets to colonies
- **AutoRepair** - Fleet lifecycle management (return to shipyard when damaged)

**Fallback Orders** (execute only when no explicit order):
- **AutoEvade** - Tactical retreat when outnumbered
- **AutoColonize** - ETAC automatic colonization
- **Patrol** - Routine patrol routes

### Logging

The implementation adds clear logging to track both phases:

```
[INFO] house-atreides === Converting Strategic Standing Orders ===
[DEBUG] house-atreides Fleet atreides_fleet_1: Converted DefendSystem to explicit FleetOrder (strategic commitment)
[INFO] house-atreides Converted 4 strategic standing orders to explicit FleetOrders

[INFO] house-atreides === TACTICAL ORDERS ===
... (Tactical skips fleets with explicit orders)

[INFO] house-atreides Standing Orders: 4 assigned, 4 strategic converted, 0 fallback executed, 4 total explicit orders
```

**Key Metrics**:
- `X assigned` - Total standing orders assigned by Standing Orders Manager
- `Y strategic converted` - Strategic orders converted to explicit FleetOrders (DefendSystem, AutoRepair)
- `Z fallback executed` - Fallback orders executed (AutoEvade, AutoColonize, etc.)
- `W total explicit orders` - Total fleet orders (tactical + logistics + strategic)

## Benefits

### 1. Clear Command Hierarchy

Admiral's strategic decisions (DefendSystem) now correctly override Tactical's opportunistic decisions (Hold, Move for colonization):

```
OLD FLOW (BROKEN):
1. Tactical: "Hold at current location"
2. Standing Orders: "DefendSystem colony 42" (assigned but never executes)
3. Result: Fleet holds position instead of defending

NEW FLOW (WORKING):
1. Strategic Conversion: "DefendSystem colony 42" → Move to 42 (explicit order)
2. Tactical: Sees explicit order, skips this fleet
3. Result: Fleet moves to defend colony 42
```

### 2. Simpler Logic

No need for complex skip checks in Tactical module. The natural explicit order priority handles everything:

**Removed** (tactical.nim, 4 locations):
```nim
# Skip fleets with DefendSystem standing orders
if controller.standingOrders.hasKey(fleet.id):
  let standingOrder = controller.standingOrders[fleet.id]
  if standingOrder.orderType == StandingOrderType.DefendSystem:
    continue
```

**Now**: Tactical just checks `if fleetId in explicitOrders: skip` (natural behavior)

### 3. Maintainable

The execution order is now explicit and documented:
1. Standing Orders Assignment
2. **Strategic Conversion** ← New phase
3. Tactical Orders
4. Logistics Orders
5. Fallback Standing Orders Execution

### 4. No Engine Changes

The engine's standing orders system remains unchanged. This is purely an RBA implementation detail about how standing orders are used.

## Testing

### Validation

Test that strategic conversions work:
```bash
./tests/balance/run_simulation 10 2>&1 | grep -E "Converting Strategic|strategic converted"
```

Expected output:
```
[INFO] house-ordos === Converting Strategic Standing Orders ===
[DEBUG] house-ordos Fleet ordos_fleet_1: Converted DefendSystem to explicit FleetOrder (strategic commitment)
[INFO] house-ordos Converted 4 strategic standing orders to explicit FleetOrders
[INFO] house-ordos Standing Orders: 4 assigned, 4 strategic converted, 0 fallback executed
```

### Before/After Metrics

**Before Fix** (Unknown-Unknown #3):
```
Standing Orders: 4 assigned, 0 executed, 4 under tactical/logistics control
```

**After Fix**:
```
Standing Orders: 4 assigned, 4 strategic converted, 0 fallback executed, 4 total explicit orders
```

**Colony Defense Coverage** (Turn 7):
- Before: 74.2% colonies undefended (standing orders not executing)
- After: 54.9% colonies undefended (limited by fleet budget, not execution failure)
- Remaining gap: CFO-Admiral budget negotiation (separate issue)

## Future Extensions

### Engine-Level Priority System (Optional)

If players request "priority standing orders" (e.g., "guard homeworld ALWAYS" vs "explore if idle"), consider adding priority/category to engine's StandingOrder type:

```nim
type
  StandingOrderPriority* {.pure.} = enum
    Strategic,   # Always execute (like explicit order)
    Fallback     # Execute only if no explicit order

  StandingOrder* = object
    priority*: StandingOrderPriority  # Default: Fallback
    # ... existing fields
```

This would move the strategic vs fallback distinction into the engine, benefiting all AI implementations and players.

**Current Status**: Not needed. RBA-level solution is sufficient and cleaner.

## Related Issues

- Unknown-Unknown #3: Defender Fleet Positioning Failure (RESOLVED)
- Colony defense budget allocation (separate issue - CFO-Admiral negotiation)

## Implementation History

- **2025-11-28**: RBA-level strategic vs fallback distinction implemented
- Architecture decision documented in plan file: `.claude/plans/polished-greeting-gray.md`
- Files modified: `src/ai/rba/orders.nim`, `src/ai/rba/tactical.nim`
