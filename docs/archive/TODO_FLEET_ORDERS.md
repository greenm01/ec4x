# TODO: Implement Fleet Order Generation

**Priority:** HIGH (Required to test Planet-Breakers)
**Estimated Effort:** 3-4 hours
**Location:** `src/ai/rba/tactical.nim` or `src/ai/rba/orders.nim`

---

## Why This Is Needed

Without fleet orders, the AI cannot:
- Move fleets to invade enemy colonies
- Deploy Planet-Breakers (CST 10 superweapons) in Act 3-4
- Run realistic balance tests (fleets just sit idle)

**Current Behavior:** All fleets idle at their starting locations.

**Desired Behavior:** Fleets move strategically to invade, defend, scout, and retreat.

---

## Implementation Options

### Option 1: Create `generateFleetOrders()` in tactical.nim (Recommended)

**Pros:**
- Keeps fleet logic in the tactical module where it belongs
- Better separation of concerns
- Helper functions already in tactical.nim

**Cons:**
- Adds new public function to module

**Implementation:**
```nim
# In src/ai/rba/tactical.nim
proc generateFleetOrders*(controller: var AIController,
                          filtered: FilteredGameState,
                          rng: var Rand): seq[FleetOrder] =
  ## Generate fleet orders based on strategic situation
  result = @[]

  # 1. Update intelligence for visible systems
  # 2. Update coordinated operation status
  # 3. For each fleet:
  #    - Check for coordinated operation assignment
  #    - Check for strategic reserve duties
  #    - Check if at colony with unassigned squadrons
  #    - Issue movement/combat orders
```

### Option 2: Inline in orders.nim

**Pros:**
- Everything in one place
- Simpler for initial implementation

**Cons:**
- orders.nim becomes very large
- Mixes concerns (coordination vs execution)

---

## Required Features (Priority Order)

### 1. Squadron Pickup (Highest Priority) ⚠️

**Without this, newly built ships never get assigned to fleets!**

```nim
# If at a friendly colony with unassigned squadrons, hold position
if isSystemColonized(filtered, fleet.location):
  let colonyOpt = getColony(filtered, fleet.location)
  if colonyOpt.isSome and colony.owner == controller.houseId:
    if colony.unassignedSquadrons.len > 0:
      order.orderType = FleetOrderType.Hold
      order.targetSystem = some(fleet.location)
      result.add(order)
      continue
```

### 2. Coordinated Operations (High Priority)

**Required for invasions and Planet-Breaker deployment**

```nim
# Check if fleet is part of a coordinated operation
for op in controller.operations:
  if fleet.id in op.requiredFleets:
    if fleet.location != op.assemblyPoint:
      # Move to assembly point
      order.orderType = FleetOrderType.Rendezvous
      order.targetSystem = some(op.assemblyPoint)
    elif controller.shouldExecuteOperation(op, filtered.turn):
      # Execute operation
      case op.operationType:
        of Invasion: order.orderType = FleetOrderType.Invade
        of Raid: order.orderType = FleetOrderType.Blitz
        of Blockade: order.orderType = FleetOrderType.BlockadePlanet
      order.targetSystem = some(op.targetSystem)
    else:
      # Wait at assembly point
      order.orderType = FleetOrderType.Hold
    result.add(order)
    continue
```

### 3. Strategic Reserve Response (Medium Priority)

**Defend important colonies from threats**

```nim
# Check if fleet is strategic reserve responding to threat
let threats = controller.respondToThreats(filtered)
for threat in threats:
  if threat.reserveFleet == fleet.id:
    order.orderType = FleetOrderType.Move
    order.targetSystem = some(threat.threatSystem)
    result.add(order)
    continue
```

### 4. Scouting Missions (Low Priority)

**Gather intelligence on unexplored systems**

```nim
# Single scouts should explore unknown systems
if isSingleScoutSquadron(fleet.squadrons[0]):
  # Find unexplored system
  let target = findUnexploredSystem(controller, filtered)
  if target.isSome:
    order.orderType = FleetOrderType.Move
    order.targetSystem = target
    result.add(order)
    continue
```

### 5. Default Behavior (Fallback)

**Hold position if no other orders**

```nim
# Default: Hold position
order.orderType = FleetOrderType.Hold
order.targetSystem = some(fleet.location)
result.add(order)
```

---

## Helper Functions Needed

Most of these already exist in `tactical.nim`:

- ✅ `getOwnedFleets()` - Get all fleets for this house
- ✅ `isSingleScoutSquadron()` - Check if squadron is solo scout
- ✅ `updateOperationStatus()` - Update operation progress
- ✅ `shouldExecuteOperation()` - Check if ready to execute
- ✅ `respondToThreats()` - Identify threats to reserves
- ❌ `findUnexploredSystem()` - **NEEDS IMPLEMENTATION**
- ❌ `getColony()` - **EXISTS in intelligence.nim, import it**

---

## Reference Implementation

See `tests/balance/ai_controller.nim.OLD:290-510` for complete implementation.

**Key Sections:**
- Lines 326-337: Squadron pickup
- Lines 340-375: Coordinated operations
- Lines 377-389: Strategic reserve response
- Lines 391-425: Combat situation assessment
- Lines 427-510: Scouting and default behavior

---

## Testing After Implementation

### 1. Smoke Test (7 turns)
```bash
./tests/balance/run_simulation 7 12345 4 4
```
**Expected:** Fleets move to pick up squadrons, scouts explore systems

### 2. Act 2 Test (15 turns)
```bash
./tests/balance/run_simulation 15 12345 4 4
```
**Expected:** Some invasions happen, coordinated operations execute

### 3. Act 3 Test (25 turns)
```bash
./tests/balance/run_simulation 25 12345 4 4
```
**Expected:** Planet-Breakers deployed (check diagnostics for ship counts)

### 4. Diagnostic Verification
```bash
# Check if Planet-Breakers appear in games
grep "planet.breaker" balance_results/diagnostics/game_*.csv
```

---

## Implementation Checklist

- [ ] Create `generateFleetOrders()` function
- [ ] Implement squadron pickup logic (highest priority)
- [ ] Implement coordinated operations support
- [ ] Implement strategic reserve response
- [ ] Implement scouting mission logic
- [ ] Add default hold behavior
- [ ] Import/create missing helper functions
- [ ] Update `src/ai/rba/orders.nim` to call new function
- [ ] Compile and run smoke test
- [ ] Run Act 3 test to verify Planet-Breakers
- [ ] Update documentation

---

## Success Criteria

✅ **Minimum Viable Implementation:**
- Squadron pickup works (fleets absorb new ships)
- Coordinated invasions execute (at least basic functionality)
- Fleets don't all sit idle

✅ **Full Implementation:**
- Strategic reserves respond to threats
- Scouts explore unknown systems
- Fallback routes work for retreating fleets
- Planet-Breakers deploy in Act 3-4 games
