# Construction Systems Architecture

## Overview

EC4X uses **three parallel construction systems** to handle different types of production:

1. **Facility Dock Construction** - Capital ships requiring orbital infrastructure
2. **Colony Construction** - Planet-side production (fighters, ground units, facilities)
3. **Terraforming** - Planetary development (separate system)

Each system has different capacity limits, queuing mechanisms, and advancement rules.

---

## 1. Facility Dock Construction

### What Gets Built Here

**Capital Ships** - Non-fighter spacecraft requiring orbital construction facilities:
- Scouts, Destroyers, Cruisers, Heavy Cruisers
- Battle Cruisers, Battleships, Dreadnoughts, Super Dreadnoughts
- Carriers, Super Carriers, Raiders
- Transport ships (ETAC, Troop Transports)

**Ship Repairs** - Damaged ships requiring orbital repair facilities

### Facilities

**Spaceport** (Planet-Side Launch Facility)
- **Capacity:** 5 construction docks
- **Function:** Construction only (no repairs)
- **Cost Penalty:** Ships built at spaceports cost 2x PP (100% increase)
- **Reason:** Launching pre-built ships from planetary surface to orbit is expensive
- **Exception:** Penalty does NOT apply to Shipyard/Starbase construction

**Shipyard** (Orbital Construction Facility)
- **Capacity:** 10 docks
- **Function:** Construction AND repair
- **Cost:** Standard (no penalty)
- **Requirements:** Requires spaceport at colony for orbital lift support

### Capacity Rules

- **Per-Facility Limits:** Each facility independently tracks its dock usage
- **Hard Limit:** Cannot queue projects beyond available dock capacity
- **Active Projects:** Each active construction/repair consumes 1 dock
- **Crippled Shipyards:** Have 0 capacity until repaired

### Queue Architecture

Each facility has its own independent queue:

```
Spaceport:
  - constructionQueue: seq[ConstructionProject]
  - activeConstruction: Option[ConstructionProject]

Shipyard:
  - constructionQueue: seq[ConstructionProject]
  - activeConstruction: Option[ConstructionProject]
  - repairQueue: seq[RepairProject]
  - activeRepairs: seq[RepairProject]  # Can be multiple
```

### Facility Assignment Algorithm

When a capital ship construction order is submitted:

1. **Prioritize Shipyards** - Try shipyards first (no cost penalty, can repair)
2. **Even Distribution** - Among facilities of same type, choose one with most available docks
3. **Fallback to Spaceports** - If no shipyard capacity, use spaceport (2x cost)
4. **Reject if No Capacity** - Order rejected if all facilities at capacity

**Example:**
- Colony has 2 shipyards (10 docks each) and 1 spaceport (5 docks)
- Shipyard A: 7/10 docks used (3 available)
- Shipyard B: 9/10 docks used (1 available)
- Spaceport: 2/5 docks used (3 available)
- **New order assigned to:** Shipyard A (most available, no penalty)

### Queue Advancement (FIFO)

**Each Maintenance Phase:**

1. **Advance Active Projects** - Decrement turnsRemaining on all active projects
2. **Complete Finished Projects** - Remove completed projects, free docks
3. **Pull from Queue** - Fill available docks with queued projects (FIFO order)

**Shipyard Multi-Dock Behavior:**
- Construction: 1 active project maximum
- Repairs: Can run multiple simultaneously (up to available docks)
- Total active projects ≤ 10 docks

**Priority:** FIFO (First In, First Out) - no priority distinction between construction and repair

### Special Cases

**Shipyard/Starbase Construction:**
- Built in orbit (don't occupy ground facilities)
- Require spaceport for orbital lift assist
- **DO NOT consume dock capacity**
- No spaceport cost penalty (orbital construction)

**Fighter Construction:**
- Built planet-side (distributed manufacturing)
- **DO NOT use facility docks** → routed to Colony Construction system
- No capacity limits beyond colony industrial capacity

### Integration Points

**Order Submission** (`resolveBuildOrders`):
```nim
# Check if ship requires dock
if shipRequiresDock(shipClass):
  # Assign to facility
  assignedFacility = assignFacility(state, colonyId, Ship, shipClass)
  if assignedFacility.isNone:
    # Reject - no capacity
  else:
    # Add to facility queue with facilityId
    assignAndQueueProject(state, colonyId, project)
```

**Maintenance Phase** (`resolveMaintenancePhase`):
```nim
# Advance facility queues
for colony in colonies:
  let results = advanceColonyQueues(colony)
  # Results include completed projects and repairs
```

**Cost Calculation:**
```nim
# Spaceport builds cost 2x (except Shipyard/Starbase)
if facilityType == Spaceport and shipClass != Fighter:
  cost = baseCost * 2
else:
  cost = baseCost
```

---

## 2. Colony Construction

### What Gets Built Here

**Planet-Side Production** - Items built using colony industrial capacity:

- **Fighters** - Distributed planetary manufacturing
- **Ground Units:**
  - Armies (AD) - Recruited from population
  - Marines (MD) - Recruited from population
- **Defensive Facilities:**
  - Ground Batteries - Planetary defense
  - Planetary Shields (SLD1-6) - Orbital bombardment protection
- **Infrastructure:**
  - Spaceports - Built with heavy industry, then commissioned
  - Shipyards - Coordinated from planet-side, built in orbit
  - Starbases - Orbital defense platforms
- **Economic:**
  - Industrial Units (IU) - Manufacturing capacity investment
  - Infrastructure - Colony development/repair

### Queue Architecture

**Colony-Wide Queue** (Legacy System):

```
Colony:
  - underConstruction: Option[ConstructionProject]  # Active project
  - constructionQueue: seq[ConstructionProject]     # Queued projects
```

### Capacity Rules

- **No Dock Limits** - Represents colony-wide industrial capacity
- **Single Active Project** - One project advances at a time
- **Queue Unlimited** - No hard limit on queued projects (budget-limited)

### Queue Advancement

**Each Maintenance Phase:**

1. **Advance Active Project** - Decrement turnsRemaining
2. **Complete if Finished** - Add to completed projects
3. **Pull Next from Queue** - Move first queued project to underConstruction

### Special Considerations

**Population Recruitment:**
- Armies and Marines consume population (souls)
- Must leave colony above minimum viable size
- Recruitment cost: PP + population

**Facility Construction:**
- Spaceports/Shipyards built planet-side, then commissioned
- After completion, new facility added to colony
- New facilities start with empty queues

---

## 3. Terraforming

### What Gets Built Here

**Planetary Development** - Upgrading planet class for better production:

- Class 1 → Class 2
- Class 2 → Class 3
- ... up to Class 6

### Architecture

**Separate Slot** (Not part of construction queue):

```
Colony:
  - activeTerraforming: Option[TerraformProject]
```

### Rules

- **Independent System** - Doesn't interfere with construction or facility queues
- **One at a Time** - Only one terraforming project per colony
- **Turn-Based** - Advances each turn, doesn't use dock capacity
- **Tech-Dependent** - Speed depends on Terraforming (TER) tech level

---

## System Comparison

| Feature | Facility Docks | Colony Queue | Terraforming |
|---------|---------------|--------------|--------------|
| **What** | Capital ships + repairs | Fighters, ground units, facilities | Planet upgrades |
| **Capacity** | 5-10 docks per facility | No hard limit | 1 project per colony |
| **Multiple Active** | Yes (shipyard repairs) | No | No |
| **Queue Location** | Per-facility | Colony-wide | Separate slot |
| **Cost Penalty** | 2x at spaceports | None | None |
| **Advancement** | Per-facility FIFO | Single queue FIFO | Independent |

---

## Data Flow Diagram

```
=== TURN N: Command Phase ===
Build Order Submission
         ↓
    ┌────────────┐
    │ Routing    │
    │ Decision   │
    └─────┬──────┘
          │
    ┌─────┴─────────────────────┐
    ↓                           ↓
Capital Ship?          Everything Else?
    ↓                           ↓
┌───────────────┐      ┌──────────────────┐
│ Facility Dock │      │ Colony Queue     │
│ Construction  │      │ Construction     │
└───────┬───────┘      └────────┬─────────┘
        │                       │
        ↓                       ↓
┌──────────────┐       ┌──────────────────┐
│ Assign       │       │ Add to           │
│ to Facility  │       │ underConstruction│
│ (Spaceport/  │       │ or               │
│  Shipyard)   │       │ constructionQueue│
└──────┬───────┘       └────────┬─────────┘
       │                        │
       └────────┬───────────────┘
                ↓
=== TURN N: Maintenance Phase ===
        ┌──────────────┐
        │ Maintenance  │
        │ Phase        │
        └──────┬───────┘
               │
      ┌────────┴────────┐
      ↓                 ↓
┌──────────────┐  ┌──────────────┐
│ Advance      │  │ Advance      │
│ Facility     │  │ Colony       │
│ Queues       │  │ Queue        │
└──────┬───────┘  └──────┬───────┘
       │                 │
       └────────┬────────┘
                ↓
        ┌──────────────────────┐
        │ Store Completed      │
        │ Projects in          │
        │ pendingCommissions   │
        └──────────┬───────────┘
                   │
       (Turn boundary - state persisted)
                   │
=== TURN N+1: Command Phase ===
                   ↓
        ┌──────────────────────┐
        │ 1. Commission        │
        │    Completed Units   │
        │    (Frees capacity)  │
        └──────────┬───────────┘
                   ↓
        ┌──────────────────────┐
        │ 2. Auto-Load         │
        │    Fighters to       │
        │    Carriers          │
        │    (if enabled)      │
        └──────────┬───────────┘
                   ↓
        ┌──────────────────────┐
        │ 3. New Build Orders  │
        │    (uses freed       │
        │     capacity)        │
        └──────────────────────┘
```

---

## Code Modules

### Project Definitions ("What to Build")

**Module:** `src/engine/economy/projects.nim`
- `createShipProject(shipClass, cstLevel)` - Create ship construction project
- `createBuildingProject(buildingType)` - Create building construction project
- `createIndustrialProject(colony, units)` - Create IU investment project
- `getShipBuildTime(shipClass, cstLevel)` - Get ship build time (always 1 turn)
- `getIndustrialUnitCost(colony)` - Calculate IU investment cost with scaling

**Purpose:** Pure factory functions that define construction projects. No state mutation, no queue management.

### Build Order Processing ("How Orders Work")

**Module:** `src/engine/resolution/construction.nim`
- `resolveBuildOrders(state, packet, events)` - Main build order processor
  - Validates colony ownership and budget
  - Routes to facility queues (capital ships) OR colony queues (fighters/buildings)
  - Handles dual construction system routing
  - Deducts treasury and generates events
  - Called in Command Phase after commissioning

**Purpose:** Order submission, validation, capacity routing, and treasury management.

### Facility Dock Construction

**Module:** `src/engine/economy/capacity/construction_docks.nim`
- `shipRequiresDock(shipClass)` - Check if ship needs dock capacity
- `assignFacility(state, colonyId, projectType, itemId)` - Assign to best facility
- `assignAndQueueProject(state, colonyId, project)` - Add to facility queue
- `getAvailableFacilities(state, colonyId)` - Get facilities with capacity
- `processCapacityReporting(state)` - Check for violations (should never happen)

**Purpose:** Capacity checking and facility assignment algorithms.

### Queue Management

**Module:** `src/engine/economy/facility_queue.nim`
- `advanceSpaceportQueue(spaceport, colonyId)` - Advance spaceport construction
- `advanceShipyardQueue(shipyard, colonyId)` - Advance shipyard construction + repairs
- `advanceColonyQueues(colony)` - Advance all facilities at colony
- `advanceAllQueues(state)` - Advance all facilities across all colonies
- `startConstruction(colony, project)` - Add to colony queue (legacy)
- `advanceConstruction(colony)` - Advance colony queue (legacy)

**Purpose:** Queue advancement for both facility queues (capital ships) and colony queues (fighters/buildings).

### Split Commissioning System (2025-12-09)

**Module:** `src/engine/resolution/commissioning.nim`

EC4X uses a **dual-phase commissioning system** based on strategic timing requirements:

#### Planetary Defense Commissioning (Maintenance Phase)

**Function:** `commissionPlanetaryDefense(state, completedProjects, events)`
- **When:** Maintenance Phase Step 2b (same turn as completion)
- **What:** Facilities, ground units, fighters
- **Strategic Rationale:** Defenders need immediate protection against threats arriving next turn's Conflict Phase

**Assets Commissioned:**
- **Facilities:** Starbases, Spaceports, Shipyards, Drydocks
- **Ground Defense:** Ground Batteries, Planetary Shields (SLD1-6)
- **Ground Forces:** Marines, Armies
- **Fighters:** Built planetside, commission with planetary defense

**Result:** Available for defense in NEXT turn's Conflict Phase ✓

#### Military Unit Commissioning (Command Phase)

**Function:** `commissionShips(state, completedProjects, events)`
- **When:** Command Phase Part A (next turn after completion)
- **What:** Ships built in orbital docks
- **Strategic Rationale:** Ships may be destroyed in docks during Conflict Phase; verify dock survival first

**Assets Commissioned:**
- **Capital Ships:** All ship classes (Corvette → PlanetBreaker)
- **Spacelift Ships:** ETAC, TroopTransport

**Result:** Frees dock capacity for new construction, ships auto-assigned to fleets

#### Commissioning Comparison Table

| Asset Type | Commissioning Phase | Timing | Rationale |
|------------|---------------------|--------|-----------|
| **Starbases** | Maintenance Phase 2b | Same turn | Orbital defense platform |
| **Spaceports** | Maintenance Phase 2b | Same turn | Construction facility |
| **Shipyards** | Maintenance Phase 2b | Same turn | Construction/repair facility |
| **Drydocks** | Maintenance Phase 2b | Same turn | Repair facility |
| **Ground Batteries** | Maintenance Phase 2b | Same turn | Surface defenses |
| **Planetary Shields** | Maintenance Phase 2b | Same turn | Bombardment protection |
| **Marines** | Maintenance Phase 2b | Same turn | Invasion defense |
| **Armies** | Maintenance Phase 2b | Same turn | Garrison defense |
| **Fighters** | Maintenance Phase 2b | Same turn | Built planetside |
| **Capital Ships** | Command Phase Part A | Next turn | Built in docks (may be destroyed) |
| **Spacelift Ships** | Command Phase Part A | Next turn | Built in docks (may be destroyed) |

#### Commissioning Flow Diagram

```
Turn N Maintenance Phase:
  ├─ Step 2a: Construction completes
  ├─ Step 2b: Split completed projects
  │    ├─ Planetary Defense → commissionPlanetaryDefense() [IMMEDIATE]
  │    │    └─ Marines, Fighters, Facilities operational
  │    └─ Military Units → pendingMilitaryCommissions [STORED]
  │
Turn N+1 Conflict Phase:
  └─ Planetary defense assets defend against attacks ✓

Turn N+1 Command Phase Part A:
  └─ commissionShips() [AFTER combat dock survival check]
       └─ Ships operational, docks freed for new construction
```

#### Strategic Example: Marine Defense

```
Turn 5 Command Phase:
  Player sees enemy fleet approaching
  Submits build order: 3 Marines

Turn 5 Maintenance Phase:
  Marines complete construction (1-turn build time)
  → commissionPlanetaryDefense() executes immediately
  → 3 Marines operational at colony

Turn 6 Conflict Phase:
  Enemy fleet arrives, attempts invasion
  → 3 Marines defend successfully! ✓
  Colony survives due to immediate commissioning
```

### Automation

**Module:** `src/engine/resolution/automation.nim`
- `processColonyAutomation(state, orders)` - Batch automation processor
  - Auto-load fighters to carriers (per-colony toggle, default: true)
  - Auto-repair submission (per-colony toggle, default: false)
  - Auto-squadron balancing (always enabled)
- `autoLoadFightersToCarriers(state, colony, systemId, orders)` - Auto-load fighters
  - Only loads to Active stationary carriers (Hold/Guard orders or no orders)
  - Respects carrier hangar capacity (ACO tech-based limits)
  - Skips moving carriers and Reserve/Mothballed fleets

**Purpose:** Convert completed projects to operational units and handle automatic fleet/colony management.

### Integration

**Module:** `src/engine/resolve.nim`
- Command Phase orchestration:
  1. Commission completed projects (frees capacity)
  2. Process colony automation (auto-loading, auto-repair, auto-squadron)
  3. Process build orders (uses freed capacity)

**Module:** `src/engine/economy/engine.nim`
- `resolveMaintenancePhaseWithState()` - Advances both facility and colony queues

---

## Configuration

### Dock Capacity

**File:** `config/facilities.toml`

```toml
[spaceport]
docks = 5
upkeep_cost = 2

[shipyard]
docks = 10
upkeep_cost = 4
requires_spaceport = true
```

### Cost Penalties

**File:** `src/engine/orders.nim` (calculateBuildOrderCost)

```nim
# Spaceport builds ships at 2x cost (100% increase)
if facilityType == Spaceport:
  cost = baseCost * 2
else:
  cost = baseCost
```

**Exceptions:**
- Fighters: No penalty (distributed manufacturing)
- Shipyard/Starbase construction: No penalty (orbital construction)

---

## Design Principles

### Data-Oriented Design (DoD)

1. **Pure Functions** - Capacity calculations don't mutate state
2. **Explicit Mutations** - Queue operations clearly modify state
3. **Batch Processing** - Advance all queues together in maintenance phase

### Don't Repeat Yourself (DRY)

1. **Single Source of Truth** - Facility assignment logic in one place
2. **Shared Helpers** - `shipRequiresDock()` used across modules
3. **Unified Advancement** - One function advances all facility queues

### Separation of Concerns

1. **Capacity Module** - Tracks limits, assigns facilities
2. **Queue Module** - Advances projects, handles completion
3. **Resolution Module** - Routes orders, integrates systems

---

## Future Enhancements

### Potential Improvements

1. **True FIFO Priority** - Timestamp queue entries to interleave construction/repair perfectly
2. **Facility Targeting** - Allow players to specify which facility to use
3. **Rush Orders** - Pay extra PP to expedite construction
4. **Parallel Construction** - Multiple shipyards work on same large project
5. **Facility Specialization** - Facilities gain bonuses for repeated builds

### Migration Notes

**Legacy Support:**
- `colony.underConstruction` and `colony.constructionQueue` remain for colony-side construction
- Existing save games don't need migration (no saves yet implemented)
- Old capacity checking methods deprecated but not removed for backwards compatibility

---

## Common Issues & Solutions

### "Build order rejected - no capacity"

**Cause:** All facility docks at colony are occupied

**Solutions:**
1. Wait for current projects to complete
2. Build additional spaceport/shipyard at colony
3. Build at different colony with available capacity

### "Ship costs 2x expected"

**Cause:** Ship being built at spaceport instead of shipyard

**Solutions:**
1. Build shipyard at colony (removes penalty for future builds)
2. Accept 2x cost as penalty for planet-side launch
3. Build at colony with existing shipyard

### "Fighters not showing in facility queues"

**Expected:** Fighters use colony queue, not facility docks

**Reason:** Fighters built with distributed planetary manufacturing, don't require orbital facilities

### "Shipyard construction doesn't occupy docks"

**Expected:** Shipyards and Starbases built in orbit, assisted by spaceport

**Reason:** These facilities are assembled in space, don't occupy ground launch capacity

---

## Testing

### Unit Tests

**File:** `tests/unit/test_construction_dock_capacity.nim`

Test coverage should include:
- Facility assignment algorithm
- Capacity checking (per-facility)
- Queue advancement (FIFO)
- Cost calculation (spaceport penalty)
- Special cases (Shipyard/Starbase, Fighters)

### Integration Tests

**File:** `tests/integration/test_construction_comprehensive.nim`

Test scenarios:
1. Build capital ship at colony with shipyard → standard cost
2. Build capital ship at colony with spaceport only → 2x cost
3. Build capital ship when all facilities at capacity → reject
4. Build fighter → routes to colony queue, no dock consumption
5. Build multiple ships → distributed across facilities
6. Advance maintenance → both facility and colony queues advance

---

---

## 4. Carrier Hangar Capacity

### What This Tracks

**Fighter Squadrons Embarked on Carriers** - Fighters loaded onto Carrier (CV) and Super Carrier (CX) ships:
- Carriers (CV) - Medium carriers with fighter complement
- Super Carriers (CX) - Large carriers with extended hangar capacity

### Capacity Limits

**Based on ACO (Advanced Carrier Operations) tech level:**

| ACO Level | CV Capacity | CX Capacity |
|-----------|------------|------------|
| ACO I     | 3 FS       | 5 FS       |
| ACO II    | 4 FS       | 6 FS       |
| ACO III   | 5 FS       | 8 FS       |

### Enforcement Model

**Hard Physical Limit** - Cannot load beyond capacity:
- **Blocking at load time** - Fighter loading orders rejected if carrier at capacity
- **No grace period** - Physical space constraint (like construction docks)
- **Per-carrier tracking** - Each carrier independently tracks its hangar load
- **House-wide tech** - All carriers upgrade capacity immediately when ACO researched

**Exception:** If carrier already overloaded due to ACO tech downgrade, existing fighters remain (grandfathered) but no new loading allowed until under capacity.

### Ownership Transfer

**When fighters embark on carriers:**
- Ownership transfers from colony to carrier
- DO NOT count against colony fighter capacity
- Carrier provides all logistics (no infrastructure requirements)
- Can transit through any system without capacity impact

**When fighters disembark:**
- Ownership transfers back to colony
- Count against colony fighter capacity (must have space available)
- If colony at capacity, disembarkation blocked

### Loading Mechanics

**Auto-Loading at Commissioning:**
- When fighters commissioned at colony with docked carriers
- Automatically load to available carrier hangar space
- Prioritizes Super Carriers (CX) first (larger capacity)
- Then Carriers (CV)
- Respects hangar capacity limits

**Manual Loading:**
- Player orders fighters to load onto specific carrier
- Carrier must be at colony with fighters
- Validates available hangar space before loading
- Rejected if carrier at capacity

### Capacity Check Timing

**Maintenance Phase:**
- Check all carriers for hangar capacity violations
- **Violations should NEVER occur** (blocked at load time)
- If found, logged as warnings for debugging

**Load Time:**
- Primary enforcement point
- Validates hangar space available
- Rejects loading if over capacity

### Strategic Implications

**Carrier Types:**
- Super Carriers (CX) have 60-67% more capacity than Carriers (CV)
- Players should prioritize building CX for fighter operations
- CV useful for smaller fighter complements or distributed operations

**ACO Tech Research:**
- Immediately upgrades ALL carrier capacities house-wide
- No ship refits required
- Strategic timing: research before major fighter production

**Tech Downgrade Risk:**
- Rare but possible if house loses ACO tech
- Already-embarked fighters remain (no forced disembarkment)
- Prevents new loading until under new capacity limit

### Integration with Other Systems

**Colony Fighter Capacity:**
- Embarked fighters DON'T count against colony capacity
- Frees up colony infrastructure for additional fighters
- Strategic: load fighters to carriers to expand total fighter force

**Fighter Squadron Capacity:**
- Colony limits: Based on IU/PU/FD tech (with 2-turn grace period)
- Carrier limits: Based on ACO tech (hard blocking)
- Players can "overflow" colony capacity by loading to carriers

**Combat:**
- Embarked fighters participate in carrier-based combat
- If carrier destroyed/crippled, embarked fighters lost
- If carrier survives, fighters can be used in subsequent battles

---

## Code Modules

### Carrier Hangar Capacity

**Module:** `src/engine/economy/capacity/carrier_hangar.nim`
- `isCarrier(shipClass)` - Check if ship is a carrier (CV/CX)
- `getCarrierMaxCapacity(shipClass, acoLevel)` - Calculate max hangar capacity
- `getCurrentHangarLoad(squadron)` - Count embarked fighters
- `analyzeCarrierCapacity(state, fleetId, squadronIdx)` - Check single carrier
- `checkViolations(state)` - Check all carriers for violations
- `canLoadFighters(state, fleetId, squadronIdx, fightersToLoad)` - Validate loading
- `getAvailableHangarSpace(state, fleetId, squadronIdx)` - Get remaining capacity
- `findCarrierBySquadronId(state, squadronId)` - Locate carrier by ID
- `processCapacityEnforcement(state)` - Maintenance phase check (debugging only)

### Integration

**Module:** `src/engine/economy/engine.nim`
- `resolveMaintenancePhaseWithState()` - Calls carrier hangar capacity check

**Module:** Loading logic (TBD)
- Fighter loading orders will call `canLoadFighters()` before executing

---

## References

- **Spec:** `docs/specs/economy.md` Section 4.13 (ACO tech)
- **Spec:** `docs/specs/assets.md` Section 2.4.1 (Carrier mechanics)
- **Spec:** `docs/specs/reference.md` Table 10.5 (Capacity limits)
- **Implementation:** `src/engine/economy/capacity/carrier_hangar.nim`
- **Implementation:** `src/engine/economy/engine.nim` (maintenance integration)
- **Configuration:** ACO tech progression in `src/common/types/tech.nim`

---

## System Comparison (Updated)

| Feature | Facility Docks | Colony Queue | Terraforming | Carrier Hangar |
|---------|---------------|--------------|--------------| ---------------|
| **What** | Capital ships + repairs | Fighters, ground units, facilities | Planet upgrades | Embarked fighters |
| **Capacity** | 5-10 docks per facility | No hard limit | 1 project per colony | 3-8 FS per carrier |
| **Multiple Active** | Yes (shipyard repairs) | No | No | N/A |
| **Queue Location** | Per-facility | Colony-wide | Separate slot | Per-carrier |
| **Cost Penalty** | 2x at spaceports | None | None | None |
| **Advancement** | Per-facility FIFO | Single queue FIFO | Independent | N/A |
| **Enforcement** | Hard limit at build | Budget-limited | None | Hard limit at load |
| **Grace Period** | None | None | None | None |

---

## Common Issues & Solutions (Updated)

### \"Cannot load fighters to carrier\"

**Cause:** Carrier at hangar capacity

**Solutions:**
1. Wait for carrier to disembark fighters at colony
2. Use different carrier with available hangar space
3. Research ACO tech to increase carrier capacities
4. Build additional carriers (CX preferred for capacity)

### \"Fighters won't disembark from carrier\"

**Cause:** Colony at fighter capacity (no space to receive)

**Solutions:**
1. Disband excess fighter squadrons at colony
2. Wait for fighter grace period to expire (if in violation)
3. Build more Industrial Units (IU) to increase colony fighter capacity
4. Transfer fighters to different colony with available capacity

### \"Carrier shows violation in maintenance log\"

**Cause:** BUG - carriers should never exceed capacity (blocked at load time)

**Solutions:**
1. Report the bug with details (how carrier got overloaded)
2. Carrier will function normally but cannot load new fighters
3. Disembark fighters to get under capacity limit
