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
        ┌──────────────┐
        │ Commission   │
        │ Completed    │
        │ Units        │
        └──────────────┘
```

---

## Code Modules

### Facility Dock Construction

**Module:** `src/engine/economy/capacity/construction_docks.nim`
- `shipRequiresDock(shipClass)` - Check if ship needs dock capacity
- `assignFacility(state, colonyId, projectType, itemId)` - Assign to best facility
- `assignAndQueueProject(state, colonyId, project)` - Add to facility queue
- `getAvailableFacilities(state, colonyId)` - Get facilities with capacity
- `processCapacityReporting(state)` - Check for violations (should never happen)

**Module:** `src/engine/economy/facility_queue.nim`
- `advanceSpaceportQueue(spaceport, colonyId)` - Advance spaceport construction
- `advanceShipyardQueue(shipyard, colonyId)` - Advance shipyard construction + repairs
- `advanceColonyQueues(colony)` - Advance all facilities at colony
- `advanceAllQueues(state)` - Advance all facilities across all colonies

### Colony Construction

**Module:** `src/engine/economy/construction.nim`
- `createShipProject(shipClass)` - Create ship construction project
- `createBuildingProject(buildingType)` - Create building project
- `createIndustrialProject(colony, units)` - Create IU investment
- `advanceConstruction(colony)` - Advance colony queue
- `startConstruction(colony, project)` - Add to colony queue

### Integration

**Module:** `src/engine/resolution/economy_resolution.nim`
- `resolveBuildOrders()` - Routes orders to facility or colony queues

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

## References

- **Spec:** `docs/specs/economy.md` Section 5 (Construction)
- **Spec:** `docs/specs/assets.md` Section 2.3 (Facilities)
- **Implementation:** `src/engine/economy/capacity/construction_docks.nim`
- **Implementation:** `src/engine/economy/facility_queue.nim`
- **Configuration:** `config/facilities.toml`
