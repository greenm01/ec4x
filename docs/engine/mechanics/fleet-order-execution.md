# Fleet Order Execution System

**Status:** Implemented and operational (as of 2025-12-12)
**Location:** `src/engine/resolution/`

---

## Overview

The fleet order execution system implements the persistent order model from `operations.md` Section 6, where players "issue orders once; your fleets execute them persistently across turns until mission completion."

### Core Principle

**All orders are movement orders if the fleet is not at the mission objective.** Fleets traverse jump lanes incrementally (1-2 jumps per turn) until they reach their target system, then execute the order-specific action.

### Order Lifecycle Terminology (Universal for All Orders)

EC4X uses precise terminology to distinguish the four stages of order processing. **This applies to BOTH active orders AND standing orders:**

**1. Initiate** (Command Phase Part B)
- **Active orders:** Player submits explicit orders via OrderPacket
- **Standing orders:** Player configures standing order rules
- Events: `OrderIssued` (active orders)
- Phase: Command Phase Part B

**2. Validate** (Command Phase Part C)
- **Both order types:** Engine validates orders and configurations
- Active orders stored in `state.fleetOrders` for later activation
- Standing order configs validated (conditions, targets, parameters)
- Phase: Command Phase Part C

**3. Activate** (Maintenance Phase Step 1a)
- **Active orders:** Order becomes active, fleet starts moving toward target
- **Standing orders:** System checks conditions and generates fleet orders
- **Both:** Fleets begin traveling, movement happens
- Events: `StandingOrderActivated`, `StandingOrderSuspended`
- Phase: Maintenance Phase Step 1a

**4. Execute** (Conflict/Income Phases)
- **Both order types:** Fleet orders conduct their missions at target locations
- Combat orders execute in Conflict Phase (Bombard, Colonize, Blockade)
- Economic orders execute in Income Phase (Trade, Salvage)
- Events: `OrderCompleted`, `OrderFailed`, `OrderAborted`
- Phase: Depends on order type (Bombard→Conflict, Trade→Income)

**Key Insight:** Active and standing orders follow the SAME four-tier lifecycle:
- Active order: Initiate (Command B) → Validate (Command C) → Activate (Maintenance 1a) → Execute (Conflict/Income)
- Standing order: Initiate (Command B) → Validate (Command C) → Activate (Maintenance 1a) → Execute (Conflict/Income)

This document uses **"activate"** for Maintenance Phase (orders become active) and **"execute"** for Conflict/Income Phase (missions conduct at targets).

---

## Architecture Components

### 1. Order Storage

**Persistent Orders:** `state.fleetOrders: Table[FleetId, FleetOrder]`
- Orders remain in this table across turns until completion, failure, or override
- New orders overwrite existing orders for the same fleet
- Orders are removed only when: completed, failed, aborted, or fleet destroyed

**Standing Orders:** `state.standingOrders: Table[FleetId, StandingOrder]`
- Automated behaviors (AutoColonize, PatrolRoute, DefendSystem, etc.)
- Execute only when fleet has no explicit order in `state.fleetOrders`
- Include grace period countdown (`turnsUntilActivation`) after explicit order ends

### 2. Turn Cycle Integration

Fleet orders follow a **separation of movement and execution** architecture per the canonical turn cycle:

```
Turn N Sequence:
  1. Conflict Phase: Execute combat/colonization/espionage orders (for arrived fleets)
     - Step 4: Planetary combat (Bombard, Invade, Blitz) - checks arrivedFleets
     - Step 5: Colonization - checks arrivedFleets
     - Step 6b: Fleet espionage (SpyPlanet, SpySystem, HackStarbase) - checks arrivedFleets

  2. Income Phase: Execute economic orders (for arrived fleets)
     - Step 4: Salvage orders - checks arrivedFleets

  3. Command Phase: Commissioning → Player submission → Validation

  4. Maintenance Phase: Fleet movement ONLY (no order execution)
     - Step 1a: Activate ALL orders (active + standing - both become active/ready)
     - Step 1b: Order maintenance (lifecycle management, check completions)
     - Step 1c: Fleet movement (move all fleets toward order targets)
     - Step 1d: Detect arrivals (generate FleetArrived events)
     - Step 2: Construction/repair advancement
     - Step 3: Diplomatic actions
```

**Key Principle:** Maintenance Phase handles movement. Conflict and Income phases handle order execution based on arrival status tracked in `state.arrivedFleets`.

### 3. Arrival Tracking System

**State Table:** `state.arrivedFleets: Table[FleetId, SystemId]`
- Tracks fleets that have arrived at their order targets
- Populated in Maintenance Phase Step 1d
- Checked in Conflict Phase (Steps 4, 5, 6b) and Income Phase (Step 4)
- Cleared after order execution

**Event:** `FleetArrived`
- Generated when fleet reaches target system (Maintenance Phase Step 1d)
- Contains: houseId, fleetId, orderType, systemId
- Visibility: Private to owning house

**Lifecycle:**
1. **Turn N-1 Command Phase:** Player submits order → stored in `state.fleetOrders`
2. **Turn N Maintenance Phase Step 1c:** Fleet moves toward target (1-2 jumps)
3. **Turn N Maintenance Phase Step 1d:** If `fleet.location == order.targetSystem`:
   - Generate `FleetArrived` event
   - Add to `state.arrivedFleets[fleetId] = targetSystem`
4. **Turn N Conflict/Income Phase:** Execute order if `fleetId in state.arrivedFleets`
5. **After execution:** Remove from both `state.fleetOrders` and `state.arrivedFleets`

**Performance:** O(H×O) filtering at start of Conflict Phase, where H=houses, O=orders per house. Hash table lookups are O(1).

---

## Three-Step Execution Model

### Step 1a: Standing Order Activation

**File:** `src/engine/standing_orders.nim:activateStandingOrders()`

**Purpose:** Generate fleet orders from standing orders for fleets without explicit orders

**Logic:**
1. Check if fleet has explicit order in `state.fleetOrders`
   - If yes: Skip standing order, reset grace period countdown, emit `StandingOrderSuspended` event
2. Check if standing order enabled and not suspended
3. Check grace period countdown (`turnsUntilActivation`)
   - If > 0: Decrement and skip activation
   - If = 0: Activate standing order
4. Activate standing order type (AutoColonize, PatrolRoute, etc.)
5. Write generated fleet order to `state.fleetOrders`
6. Emit `StandingOrderActivated` event

**Key Feature:** Grace Period
- When explicit order completes, `turnsUntilActivation` resets to `activationDelayTurns`
- Gives player N turns to issue new orders before standing order resumes
- Default: 2 turns (configurable per standing order)

### Step 1b: Order Maintenance

**File:** `src/engine/resolution/fleet_order_execution.nim:performOrderMaintenance()`

**Purpose:** Manage order lifecycle - detect completions, validate execution conditions, generate events

**Logic:**
1. Collect all fleet orders (new from this turn + persistent from previous turns)
2. Filter by category (movement orders only in maintenance phase)
3. Sort by priority
4. For each order:
   - Validate at execution time (conditions may have changed)
   - If validation fails: Convert to SeekHome/Hold, emit `OrderAborted` event
   - Execute order-specific logic via `executor.executeFleetOrder()`
   - Generate events: `OrderIssued`, `OrderCompleted`, `OrderFailed`, `OrderAborted`
   - Remove completed/failed/aborted orders from `state.fleetOrders`
   - Reset standing order grace period on order end

**Validation Checks:**
- Fleet still exists (may have been destroyed in combat)
- Fleet ownership unchanged
- Order-specific: colonization capability, combat capability, target still valid
- **Patrol special case:** Cancel if patrol system captured by enemy

**Outcomes:**
- `Success`: Order executed successfully (may or may not be complete)
- `Failed`: Order failed validation, removed from queue
- `Aborted`: Order cancelled due to changed conditions, removed from queue

### Step 1c: Universal Fleet Movement

**File:** `src/engine/resolution/phases/maintenance_phase.nim` (lines 292-382)

**Purpose:** Move all fleets toward their persistent order targets via pathfinding

**Logic:**
1. Build `completedFleetOrders` HashSet from `OrderCompleted` events (O(1) lookup)
2. For each fleet in `state.fleetOrders`:
   - Skip if no target system
   - Skip if Hold order (explicit "stay here")
   - Skip if order already completed this turn (in completedFleetOrders)
   - Skip if fleet already at target
   - **Pathfinding:** `state.starMap.findPath(currentLocation, target, fleet)`
     - Respects lane restrictions based on fleet composition:
       - Crippled ships: Major lanes only
       - ETACs/TroopTransports: Major + Minor lanes only
       - Healthy combat fleet: All lane types
   - **Determine max jumps:**
     - Default: 1 jump per turn
     - 2-jump rule: ALL systems in path owned by house AND next 2 jumps are Major lanes
   - Move fleet 1-2 jumps along path
   - Update `state.fleets[fleetId].location`

**Key Feature:** Separation of Concerns
- Step 1b: "Is this order done?" (lifecycle management for Move orders)
- Step 1c: "How do we get there?" (physical movement for all orders)
- Step 1d: "Have we arrived?" (detect arrivals, generate FleetArrived events)
- Works for ALL order types: Move, Bombard, Colonize, Spy, etc.

**Jump Lane Types (from `assets.md`):**
- **Major lanes (50%):** Allow all ships, 1 movement point
- **Minor lanes (35%):** Block crippled ships only, 2 movement points
- **Restricted lanes (15%):** Block crippled ships, ETACs, transports, 3 movement points

### Step 1d: Fleet Arrival Detection

**File:** `src/engine/resolution/phases/maintenance_phase.nim` (lines 391-432)

**Purpose:** Detect which fleets have arrived at their order targets and mark them for execution

**Logic:**
1. For each fleet in `state.fleetOrders`:
   - Skip if fleet doesn't exist
   - Skip if order has no target system
   - Check if `fleet.location == order.targetSystem`
   - If arrived:
     - Generate `FleetArrived` event
     - Add to `state.arrivedFleets[fleetId] = targetSystem`
     - Log arrival

**Key Feature:** Bridge Between Phases
- Arrival detection (Maintenance Phase) is separate from order execution (Conflict/Income phases)
- `state.arrivedFleets` acts as a queue of "ready to execute" orders
- Cleared after execution to prevent duplicate execution

---

## Order Lifecycle Patterns

### Standard Completion Pattern

All order types follow this pattern (enforced by `completeFleetOrder()` helper):

1. **Execution:** Order-specific logic executes (colonization, movement, intel gathering, etc.)
2. **Event Generation:** `OrderCompleted` event created with details
3. **Order Removal:** `state.fleetOrders.del(fleetId)`
4. **Grace Period Reset:** `standing_orders.resetStandingOrderGracePeriod(state, fleetId)`
5. **Logging:** Info-level log of completion

**Example:** Colonization completion in `simultaneous.nim:191-202`

```nim
# Generate ColonyEstablished event for diagnostics
events.add(event_factory.colonyEstablished(houseId, systemId, prestigeAwarded))

# Remove colonization order on success (mission complete)
if fleetId in state.fleetOrders:
  state.fleetOrders.del(fleetId)
  standing_orders.resetStandingOrderGracePeriod(state, fleetId)
  logDebug(LogCategory.lcColonization, &"Fleet {fleetId} colonization order removed")

# Generate OrderCompleted event
events.add(event_factory.orderCompleted(
  houseId, fleetId, "Colonize",
  details = &"established colony at {systemId}",
  systemId = some(systemId)
))
```

### Failure/Abortion Pattern

When orders fail validation or conditions change:

1. **Validation Failure:** `validateOrderAtExecution()` returns `valid: false, shouldAbort: true`
2. **Conversion:** Order converted to SeekHome (if home colony exists) or Hold
3. **Event Generation:** `OrderAborted` event with reason
4. **Order Removal:** `state.fleetOrders.del(fleetId)`
5. **Grace Period Reset:** Standing order countdown resets
6. **Fallback:** Fleet seeks nearest owned colony or holds position

**Example:** JoinFleet abortion in `executor.nim:1214-1226`

```nim
if targetFleetOpt.isNone:
  # Target fleet destroyed - clear order and fall back to standing orders
  if fleet.id in state.fleetOrders:
    state.fleetOrders.del(fleet.id)
    standing_orders.resetStandingOrderGracePeriod(state, fleet.id)

  events.add(event_factory.orderAborted(
    houseId = fleet.owner,
    fleetId = fleet.id,
    orderType = "JoinFleet",
    reason = "target fleet no longer exists",
    systemId = some(fleet.location)
  ))
```

---

## Order Type Catalog

### Movement Orders (Maintenance Phase)

**Move (01):** Travel to target system
- Completion: Arrival at target (checked in Step 1b)
- Movement: Handled by Step 1c
- Events: `OrderCompleted` on arrival

**SeekHome (02):** Return to nearest owned colony
- Completion: Arrival at home colony
- Movement: Handled by Step 1c (same as Move)
- Events: `OrderCompleted` on arrival

**Patrol (03):** Patrol specific system
- Completion: Cancelled if system captured by enemy
- Movement: Handled by Step 1c until at patrol location
- Events: `OrderAborted` if patrol system lost
- Persistence: Indefinite until cancelled or conditions change

**Hold (04):** Hold position
- Completion: Never (player must override)
- Movement: Skipped in Step 1c (filter: `if orderType == Hold: continue`)
- Events: None (passive order)

### Combat Orders (Conflict Phase)

**Bombard (05), Invade (06), Blitz (07):** Planetary assault
- Storage: Stored in `state.fleetOrders` in Command Phase Part C
- Movement: Fleet travels toward target in Maintenance Phase Step 1c
- Execution: Executes in Conflict Phase when fleet arrives at target
- Completion: After successful assault or failure
- Events: `OrderCompleted` after assault resolution
- Cleanup: Order removed + grace period reset
- **Note:** Executes Turn N, N+1, or later depending on travel distance

### Colonization Orders (Maintenance Phase)

**Colonize (08):** Establish new colony
- Execution: `simultaneous.nim:resolveColonization()` (simultaneous resolution)
- Movement: Handled by Step 1c until at target
- Completion: After colony established (or conflict lost)
- Events: `ColonyEstablished`, `OrderCompleted` (or `OrderFailed`)
- Fallback: AutoColonize standing orders seek alternative targets if conflict lost
- Cleanup: Order removed in 3 locations:
  - `simultaneous.nim:establishColony()` (primary)
  - `simultaneous.nim` fallback success
  - `fleet_orders.nim:resolveColonizationOrder()` (legacy)

### Intelligence Orders (Maintenance Phase)

**SpyPlanet (09), SpySystem (10), HackStarbase (11):** Espionage
- Validation: Requires pure scout fleets (no combat ships, no spacelift)
- Movement: Handled by Step 1c until at target
- Execution: Intel gathering at target system
- Completion: After intel collected or validation failure
- Events: `IntelGathered`, `OrderCompleted`

**ViewWorld (19):** Long-range planetary scan
- Movement: Handled by Step 1c until at target
- Execution: Gather owner + planet class intel
- Completion: After scan (fleet remains at system)
- Events: `IntelGathered`, `OrderCompleted`
- Cleanup: Order removed after completion (added in Phase 5.2)

### Fleet Operations (Command Phase)

**JoinFleet (12):** Merge with another fleet
- Validation: Target fleet must exist and be at same location
- Abortion: Cancels if target fleet destroyed or unreachable
- Completion: After successful merge
- Events: `OrderCompleted` or `OrderAborted`

**Rendezvous (13), Salvage (14):** Fleet coordination
- Similar lifecycle to JoinFleet
- Validation at execution time
- Events: `OrderCompleted`, `OrderAborted`, `OrderFailed`

### Status Change Orders (Command Phase)

**Reserve (15), Mothball (16), Reactivate (17):** Fleet status changes
- Execution: Immediate (zero-turn commands)
- Persistence: Status locks fleet (prevents other orders until Reactivate)
- Cleanup: Manual via Reactivate command
- No completion events (status change only)

### Defensive Posture Orders (Persistent)

**GuardStarbase (20), GuardPlanet (21), BlockadePlanet (22):** Defensive positions
- Persistence: Indefinite until player overrides
- Movement: Handled by Step 1c until at target
- Completion: None (persistent defensive stance)
- No removal logic (order persists until cancelled by player)

---

## Key Implementation Details

### Lane Type Lookup

**Helper:** `starmap.nim:getLaneType(fromSystem, toSystem): Option[LaneType]`

Efficient lane type lookup for movement calculations:
- Iterates through `starMap.lanes` to find matching lane
- Returns `some(laneType)` if found, `none(LaneType)` if no lane exists
- Used in Step 1c for 2-jump rule validation

### Completed Orders Tracking

**Pattern:** Build HashSet before Step 1c

```nim
var completedFleetOrders = initHashSet[FleetId]()
for event in events:
  if event.eventType == GameEventType.OrderCompleted and event.fleetId.isSome:
    completedFleetOrders.incl(event.fleetId.get())
```

**Purpose:** O(1) lookup to skip fleets whose orders completed in Step 1b

**Why:** Prevents Step 1c from moving fleets after order completion, avoiding conflicts

### Grace Period Management

**Helper:** `standing_orders.nim:resetStandingOrderGracePeriod(state, fleetId)`

Called after EVERY order removal:
- Resets `turnsUntilActivation = activationDelayTurns`
- Logs debug message
- Ensures standing orders don't immediately resume after explicit order ends

**Locations (10+ call sites):**
- Move completions (2 locations)
- Colonization completions (3 locations)
- Order failures/abortions (4 locations)
- JoinFleet abortions (2 locations)

### Order Completion Helper

**Helper:** `fleet_orders.nim:completeFleetOrder(state, fleetId, orderType, details, systemId, events)`

Standardized completion pattern:
1. Generate `OrderCompleted` event
2. Remove order from `state.fleetOrders`
3. Reset standing order grace period
4. Log completion

**Usage:** Can be used for future order types to ensure consistency

---

## Event Generation

### Event Types

**Order Lifecycle Events:**
- `OrderIssued`: When order submitted (Step 1b)
- `OrderCompleted`: When order finishes successfully (Step 1b or order-specific handler)
- `OrderFailed`: When order fails validation (Step 1b)
- `OrderAborted`: When order cancelled due to changed conditions (Step 1b or validation)

**Standing Order Events:**
- `StandingOrderActivated`: When standing order activates (Step 1a)
- `StandingOrderSuspended`: When explicit order overrides standing order (Step 1a)

**Movement Events:**
- `FleetMoved`: When fleet moves toward target (Step 1c)
- Records: owner, fleetId, fromSystem, toSystem, jumpsCount

**Mission-Specific Events:**
- `ColonyEstablished`: Colonization success
- `IntelGathered`: Intelligence collected
- `CombatResolved`: Planetary assault outcome

### Event Timing

**Turn N Events:**
- `OrderIssued`: Command Phase (when submitted)
- `StandingOrderActivated/Suspended`: Maintenance Step 1a
- `FleetMoved`: Maintenance Step 1c (multiple per fleet if 2 jumps)
- `OrderCompleted/Failed/Aborted`: Maintenance Step 1b or order execution

**Turn N+1 or Later Events (when fleet arrives):**
- `CombatResolved`: Conflict Phase (when combat order executes at arrival)
- `FleetArrived`: Maintenance Phase (when fleet reaches order target)

---

## Fog-of-War Integration

Fleet order execution respects fog-of-war:
- Pathfinding only considers known jump lanes
- Intel gathering updates `house.intelligence` databases
- Hostile system detection uses intelligence reports (not omniscient state)
- Validation checks use player-visible information only

**Example:** Patrol cancellation (Phase 4)
```nim
# Check if patrol system is now hostile (lost to enemy)
if targetId in state.colonies:
  let colony = state.colonies[targetId]
  if colony.owner != houseId:
    let relation = state.houses[houseId].diplomaticRelations.getDiplomaticState(colony.owner)
    if relation == DiplomaticState.Enemy:
      return ExecutionValidationResult(valid: false, shouldAbort: true, ...)
```

Uses diplomatic relations (player knowledge), not global state.

---

## Testing & Validation

### Quick Balance Test

```bash
nimble testBalanceQuick  # 20 games, 7 turns (~10s)
```

**Verifies:**
- Order lifecycle (submission → movement → completion)
- Standing order activation after grace period
- Colonization order cleanup (no stuck orders)
- Fleet movement incremental progress

### Extended Balance Test

```bash
python3 scripts/run_balance_test_parallel.py --games 100 --turns 35
```

**CSV Diagnostics:** `balance_results/diagnostics/game_*.csv`

**Analysis Queries:**
```python
import polars as pl

# Check for stuck colonization orders
stuck_orders = (
    df.filter(pl.col("event_type") == "ColonyEstablished")
    .group_by(["game_id", "fleet_id"])
    .agg([
        pl.col("turn").min().alias("colonize_turn"),
        pl.col("turn").max().alias("last_turn")
    ])
    .collect()
)

# Verify grace period timing
grace_timing = (
    df.filter(pl.col("event_type").is_in(["OrderCompleted", "StandingOrderActivated"]))
    .sort(["game_id", "fleet_id", "turn"])
    .collect()
)

# Fleet movement tracking
fleet_movements = (
    df.filter(pl.col("event_type") == "FleetMoved")
    .group_by("fleet_id")
    .agg([
        pl.count().alias("total_moves"),
        pl.col("jumps_count").sum().alias("total_jumps")
    ])
    .collect()
)
```

### Integration Tests

**File:** `tests/integration/test_fleet_orders.nim`

**Coverage:**
- Order persistence across turns
- Step 1c fleet movement (1-2 jumps per turn)
- Lane restriction enforcement
- Colonization simultaneous resolution
- Standing order grace period timing
- Order completion event generation

---

## Known Edge Cases & Solutions

### Case 1: Fleet Destroyed During Movement

**Problem:** Fleet destroyed in combat before reaching order target

**Solution:**
- Validation in Step 1b checks `if fleetId notin state.fleets: continue`
- Fleet deletion automatically removes from `state.fleetOrders` (combat_resolution.nim:862)
- No orphaned orders remain in system

### Case 2: Colonization Target Already Colonized

**Problem:** Target system colonized by another player before fleet arrives

**Solution:**
- Validation in `establishColony()` checks `if systemId in state.colonies: return`
- Order continues persisting (fleet keeps moving toward target)
- Manual intervention required (player must issue new order or cancel)
- Future enhancement: AutoColonize fallback logic

### Case 3: Simultaneous Colonization Conflict

**Problem:** Multiple houses attempt to colonize same system same turn

**Solution:**
- Simultaneous resolution in `simultaneous.nim:resolveColonization()`
- Conflict resolver uses fleet strength + random tiebreaker
- Winner colonizes, losers get `OrderFailed` event
- AutoColonize fleets seek fallback targets (max 3 rounds)

### Case 4: Patrol System Captured

**Problem:** Enemy captures system being patrolled

**Solution:** (Phase 4)
- Validation in Step 1b detects enemy ownership + hostile relations
- Order converted to SeekHome (fleet returns to nearest owned colony)
- `OrderAborted` event generated with reason "Patrol system captured by enemy"

### Case 5: PathResult Empty (No Route)

**Problem:** Fleet blocked by lane restrictions (e.g., ETAC in Restricted lane)

**Solution:**
- Step 1c checks `if not pathResult.found or pathResult.path.len == 0: continue`
- Fleet stays at current location, order persists
- Warning logged: "No path found... (lane restrictions may apply)"
- Manual intervention required (player must issue new order or upgrade fleet)

---

## Future Enhancements

### 1. ETAC Auto-Reload for AutoColonize

**Current:** ETAC fleets complete colonization, order removed, standing order resumes, but ETAC has no colonists

**Proposed:**
- Add check in `executeAutoColonize()`: if no colonists, generate SeekHome order to nearest colony with available PTUs
- Load colonists automatically when fleet arrives
- Resume AutoColonize after reload

**Complexity:** Medium (requires cargo management integration)

### 2. Order Queueing

**Current:** New orders override existing orders immediately

**Proposed:**
- Allow multiple orders per fleet in queue
- Execute sequentially as each completes
- UI shows order queue for player

**Complexity:** High (major architecture change)

### 3. Conditional Orders

**Current:** Orders execute unconditionally until completion/abortion

**Proposed:**
- Add conditions: "Colonize if undefended", "Attack if fleet strength > X"
- Validation checks conditions each turn
- Abort if conditions not met

**Complexity:** Medium (extends validation system)

### 4. Formation Movement

**Current:** Fleets move independently

**Proposed:**
- Group fleets into formations
- All fleets in formation move together (slowest sets pace)
- Arrive at target simultaneously for coordinated attacks

**Complexity:** High (requires fleet coordination system)

---

## References

- **Spec:** `docs/specs/operations.md` Section 6 (Fleet Operations)
- **Architecture:** `docs/engine/architecture/ec4x_canonical_turn_cycle.md`
- **Event Matrix:** `docs/engine/architecture/active_fleet_order_game_events.md`
- **Assets Spec:** `docs/specs/assets.md` Section 2.1 (Jump Lanes)
- **Implementation Plan:** `~/.claude/plans/snoopy-finding-lecun.md` (Phase 1-5)

---

**Document Version:** 1.0
**Last Updated:** 2025-12-12
**Author:** EC4X Development Team
