# Construction, Repair, and Commissioning Architecture

## Overview

EC4X uses **three primary systems** for military asset production:

1. **Facility Dock Construction** - Capital ships requiring orbital infrastructure (Spaceport/Shipyard)
2. **Facility Dock Repairs** - Damaged ships requiring orbital repair facilities (Drydock)
3. **Colony Construction/Repairs** - Planet-side military production (fighters, ground units, defensive facilities)

Each system has different capacity limits, payment timing, queuing mechanisms, and commissioning rules.

**Related Documentation:**
- **Turn Cycle:** `docs/engine/ec4x_canonical_turn_cycle.md` (timing and integration)
- **Specs:** `docs/specs/02-assets.md` (facility capacities), `docs/specs/04-research_development.md` (terraforming, ACO)

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
- **Capacity:** 10 construction docks
- **Function:** Construction ONLY (repairs go to Drydock)
- **Cost:** Standard (no penalty)
- **Requirements:** Requires operational spaceport for orbital lift support

**Drydock** (Orbital Repair Facility)
- **Capacity:** 5 repair docks
- **Function:** Ship repairs ONLY (no construction)
- **Repair Cost:** 25% of original ship build cost
- **Repair Duration:** 1 turn
- **Requirements:** Requires operational spaceport for orbital lift support

### Capacity Rules

- **Per-Facility Limits:** Each facility independently tracks its dock usage
- **Hard Limit:** Cannot queue projects beyond available dock capacity
- **Active Projects:** Each active construction/repair consumes 1 dock
- **Crippled Shipyards:** Have 0 capacity until repaired

### Queue Architecture

**Fundamental Principle:** Queue entry = physical dock occupied. No separate waiting list.

**Facility Queues (Dock-Limited):**

```nim
type Spaceport = object
  constructionQueue: seq[ConstructionProject]  # Max length 5
  capacity: int = 5

type Shipyard = object
  constructionQueue: seq[ConstructionProject]  # Max length 10
  capacity: int = 10

type Drydock = object
  repairQueue: seq[RepairProject]              # Max length 5
  capacity: int = 5
```

**Colony Queues (Unlimited):**

```nim
type Colony = object
  constructionQueue: seq[ConstructionProject]  # No limit
  repairQueue: seq[RepairProject]              # No limit
  # Industrial capacity model, not physical docks
```

**Key Properties:**
- `queue.len` = docks currently occupied
- When `queue.len = capacity`, facility at max
- Every queue entry actively being worked on
- Dock freed when project commissioned

### Facility Assignment Algorithm

When a capital ship construction order is submitted:

1. **Prioritize Shipyards** - Try shipyards first (no cost penalty, construction only)
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

**Each Production Phase:**

For Spaceports and Shipyards (Construction):
1. Advance all projects in constructionQueue (decrement turnsRemaining)
2. Mark completed projects with status = PendingCommission
3. Projects stay in queue until commissioned next turn
4. Docks remain occupied until commissioning

For Drydocks (Repairs):
1. Advance all repairs in repairQueue (decrement turnsRemaining)
2. For completed repairs (turnsRemaining = 0):
   - Check house treasury for repair cost
   - If sufficient: Pay, commission immediately, remove from queue, free dock
   - If insufficient: Mark as Stalled, ship stays in queue, dock occupied
3. Next turn: Re-check stalled repairs for funding

For Colony Queues:
1. Advance all construction/repair projects
2. For completed construction: Commission immediately (no dock limit)
3. For completed repairs: Pay and commission immediately

**Key Difference:**
- Construction: Complete → Wait → Commission next turn
- Repairs: Complete → Pay → Commission same turn (if funds available)

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

**Production Phase** (`resolveMaintenancePhase`):
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

## 2. Drydock Repair System

### Overview

**Drydock repairs** provide a specialized system for restoring damaged capital ships to operational status. Unlike construction (which creates new assets), repairs have **deferred payment timing** to support auto-repair convenience without forcing premature financial commitment.

### Repair Submission

#### Manual Repair Orders

**When:** CMD5 (Player Submission Window)

Players can manually submit repair orders for any damaged ship at a colony with available drydock capacity.

**Order Validation:**
```nim
proc validateRepairOrder(state: GameState, order: RepairOrder): Result[void, string] =
  # Check ship exists and is damaged
  let ship = state.ship(order.shipId).get()
  if ship.status != Damaged:
    return err("Ship is not damaged")
  
  # Check ship is at colony
  if ship.location != order.colonyId:
    return err("Ship must be at colony with drydock")
  
  # Check drydock capacity
  let drydocks = state.drydocksAt(order.colonyId)
  if drydocks.allSaturated():
    return err("No available drydock capacity")
  
  return ok()
```

#### Auto-Repair Submission

**When:** CMD3 (Auto-Repair Submission, before player window)

**Purpose:** Convenience mechanism to automatically submit repair orders for damaged ships at colonies with available drydock capacity.

**Algorithm:**
```nim
proc submitAutoRepairs(state: var GameState, colonyId: ColonyId):
  let colony = state.colony(colonyId).get()
  
  # Skip if auto-repair disabled
  if not colony.autoRepair:
    return
  
  # Get all damaged ships at colony
  let damagedShips = state.shipsAt(colonyId).filterIt(it.status == Damaged)
  
  # Priority: Ships > Starbases/Ground Units > Facilities
  let prioritized = prioritizeRepairs(damagedShips)
  
  # Submit repairs up to available capacity
  for ship in prioritized:
    let drydock = findAvailableDrydock(state, colonyId)
    if drydock.isSome:
      submitRepair(state, ship.id, drydock.get().id)
      events.add(AutoRepairSubmitted, ship.id)
    else:
      break  # No more capacity
```

**Priority Order:**
1. **Ships** (capital ships) - Highest military value
2. **Starbases** (orbital defense) - Strategic defense assets
3. **Ground Units** (marines, armies) - Planetary defense
4. **Facilities** (damaged spaceports/shipyards) - Economic infrastructure

**Key Properties:**
- Runs automatically if `colony.autoRepair = true` (default: false)
- Respects drydock capacity limits
- Players can cancel auto-submitted repairs during submission window (CMD5)
- Manual repairs always allowed regardless of auto-repair setting

### Repair Advancement

**When:** Production Phase Step 2c (same as construction advancement)

**Algorithm:**
```nim
proc advanceDrydockQueue(state: var GameState, drydock: var Drydock):
  # Advance all repairs (decrement turns)
  for repair in drydock.repairQueue.mitems:
    if repair.status == InProgress:
      repair.turnsRemaining -= 1
      
      # Mark as completed (but not commissioned yet)
      if repair.turnsRemaining == 0:
        repair.status = AwaitingPayment
        events.add(RepairCompleted, repair)
```

**Important:** Repairs that complete during Production Phase are marked as `AwaitingPayment` but do NOT commission immediately. They wait for the next turn's CMD2 (Unified Commissioning).

### Payment & Stalling Mechanism

#### When Payment is Checked

**Once per turn:** CMD2 (Unified Commissioning)

**NOT checked during Production Phase** - repairs advance mechanically without payment validation.

#### Commissioning Algorithm

```nim
proc commissionRepairedShips(state: var GameState, drydock: var Drydock):
  var i = 0
  while i < drydock.repairQueue.len:
    let repair = drydock.repairQueue[i]
    
    # Only process completed repairs
    if repair.status != AwaitingPayment:
      i += 1
      continue
    
    let house = state.houses[repair.ownerId]
    
    # Check treasury (FIFO order)
    if house.treasury >= repair.cost:
      # PAYMENT HAPPENS HERE
      house.treasury -= repair.cost
      
      # Commission ship
      let ship = state.ships[repair.targetShipId]
      ship.status = Undamaged
      ship.commissioning.turnCommissioned = state.turn
      
      # Remove from queue, free dock
      drydock.repairQueue.delete(i)
      events.add(ShipRepairCommissioned, repair)
      
      # Continue processing (don't increment i, element deleted)
    
    else:
      # STALL - insufficient funds
      repair.status = Stalled
      events.add(RepairStalled, repair, house.treasury, repair.cost)
      i += 1  # Keep in queue, move to next
```

#### Stalling Behavior

**What happens when payment fails:**
1. Repair status changes to `Stalled`
2. Ship remains in drydock queue
3. Dock stays occupied (reduces colony repair capacity)
4. Event logged: `RepairStalled` (includes shortfall amount)

**Recovery:**
- Next turn Command Phase A: Re-check stalled repairs (FIFO order)
- If treasury sufficient: Pay, commission, free dock
- If still insufficient: Remain stalled

**Strategic Implications:**

*For Defenders:*
- Stalled repairs occupy valuable dock space
- Ships in drydocks vulnerable to facility destruction
- May need to prioritize treasury management
- Consider canceling low-priority repairs to free capacity

*For Attackers:*
- Drydocks with stalled repairs easier to overwhelm (reduced capacity)
- Destroying drydocks eliminates stalled ships entirely
- Economic pressure creates military vulnerabilities

#### FIFO Processing Example

**Scenario:** 3 repairs complete same turn, limited funds

```
Turn 12 Production Phase:
  Drydock Queue:
    [0] Cruiser (repair complete, cost: 30 PP)
    [1] Destroyer (repair complete, cost: 20 PP)
    [2] Battleship (repair complete, cost: 50 PP)

Turn 13 CMD2 (Unified Commissioning):
  House Treasury: 40 PP
  
  Processing (FIFO order):
  [0] Cruiser: 40 >= 30 ✓
      → Pay 30 PP (Treasury: 10 PP)
      → Commission ship
      → Remove from queue
  
  [1] Destroyer: 10 < 20 ✗
      → Stall (stays in queue)
      → Event: "Repair stalled: Destroyer needs 20 PP, have 10 PP"
  
  [2] Battleship: (not checked, FIFO stops at first stall)
      → Stall (stays in queue)
  
  Result:
    - 1 ship commissioned (Cruiser)
    - 2 ships stalled (Destroyer, Battleship)
    - 2 docks remain occupied
```

### Payment Timing

**Deferred until commissioning** (CMD2)

**Rationale:**
1. **Auto-Repair is a convenience** - Players need ability to cancel before payment
2. **Submission window allows cancellation** - Players see auto-repairs, can cancel in CMD5
3. **No premature commitment** - Repairs advance mechanically, payment only when commissioning

**Comparison to Construction:**
- **Construction:** Upfront payment (deliberate player choice)
- **Repairs:** Deferred payment (supports auto-repair without forcing commitment)

### Repair Duration

**All ship repairs: 1 turn**

Simplified mechanic (no variable duration based on damage severity). Repair time represents drydock scheduling, not damage extent.

**Timeline:**
```
Turn N Command Phase:
  - Auto-repair submits OR player submits repair order
  - Ship enters drydock queue
  - Dock occupied

Turn N Production Phase:
  - Repair advances (turnsRemaining: 1 → 0)
  - Repair status: InProgress → AwaitingPayment
  - Ship still in queue, dock still occupied

Turn N+1 CMD2 (Unified Commissioning):
   - Treasury check
   - If sufficient: Pay, commission, free dock
   - If insufficient: Stall, keep in queue
```

### Repair Costs

**Ship repairs: 25% of original construction cost**

**Formula:**
```nim
proc calculateRepairCost(shipClass: ShipClass, cstLevel: int): int =
  let baseCost = getShipConstructionCost(shipClass, cstLevel)
  result = (baseCost * 25) div 100  # Integer division
```

**Examples:**
- Scout (base 10 PP) → repair 2.5 PP (rounds to 2 PP)
- Cruiser (base 80 PP) → repair 20 PP
- Battleship (base 200 PP) → repair 50 PP

**No spaceport penalty** - repairs always at drydocks (orbital facilities), no planet-side launch cost.

### Vulnerability Windows

**Ships in drydocks are vulnerable to:**

1. **Facility Destruction** (Conflict Phase Step 8)
   - Drydock destroyed in orbital combat
   - ALL ships in drydock queue are destroyed
   - No commissioning occurs (facility doesn't exist)

2. **Facility Crippling** (Conflict Phase Step 8)
   - Drydock crippled (>50% damage)
   - Drydock queue CLEARED (repairs canceled)
   - Ships return to damaged status at colony
   - No refunds (repairs not paid yet)

3. **Colony Conquest** (Conflict Phase Step 8)
   - Colony captured by enemy
   - ALL facility queues cleared (including drydocks)
   - Ships captured as damaged (remain at colony, new owner)
   - No refunds (repairs not paid yet)

**Strategic Considerations:**
- Repairs take 1 full turn minimum (can't emergency-repair during combat)
- Proactive defense required (repair before threats arrive)
- High-value ships in drydocks become priority targets
- Consider moving damaged ships to safer colonies for repairs

### Integration with Commissioning

**Unified CMD2 (Commissioning):**

All asset commissioning happens in single step, including repaired ships:

```nim
proc unifiedCommissioning(state: var GameState):
  # 1. Commission ships from construction (Spaceports/Shipyards)
  for facility in state.allSpaceports():
    commissionCompletedShips(state, facility)
  
  for facility in state.allShipyards():
    commissionCompletedShips(state, facility)
  
  # 2. Commission repaired ships from drydocks (WITH PAYMENT)
  for facility in state.allDrydocks():
    commissionRepairedShips(state, facility)  # Includes treasury check
  
  # 3. Commission colony-built assets
  for colony in state.allColonies():
    commissionColonyAssets(state, colony)
```

**Key Points:**
- Repaired ships commission alongside newly-built ships
- Single commissioning phase simplifies mental model
- Treasury check happens once per turn (not during Production Phase)
- Stalled repairs stay in queue until next turn's CMD2

### Auto-Assignment to Fleets

**Repaired ships treated like newly commissioned ships:**

When `colony.autoJoinFleets = true` (default), repaired ships are automatically assigned to fleets during CMD4 (Colony Automation).

**Behavior:**
- Repaired ship commissions in CMD2
- Auto-assignment happens in CMD4 (after commissioning)
- Ship assigned to fleet at colony (new fleet if none exists)
- No tracking of original fleet membership

**Rationale:**
- Simplicity: Treat all commissioned ships uniformly
- Consistency: Same auto-assignment logic for all ships
- Avoids complexity: Don't track pre-damage fleet assignments

**Alternative:** Players can manually reassign ships during submission window if auto-assignment disabled.

### Data Models

```nim
type RepairProject = object
  targetShipId: ShipId
  ownerId: HouseId
  facilityId: FacilityId  # Which drydock
  turnsRemaining: int     # Decremented in Production Phase
  cost: int               # Calculated at submission, paid at commissioning
  status: RepairStatus    # InProgress → AwaitingPayment → (Commissioned or Stalled)
  submittedTurn: int

type RepairStatus {.pure.} = enum
  InProgress         # Currently advancing in Production Phase
  AwaitingPayment    # Completed, waiting for Command Phase A treasury check
  Stalled            # Payment failed, waiting for funds

type Drydock = object
  id: FacilityId
  colonyId: ColonyId
  repairQueue: seq[RepairProject]  # Max length 5
  capacity: int = 5
  status: FacilityStatus  # Operational, Crippled, Destroyed
```

### Code Modules

**Repair Submission:**
- `src/engine/resolution/construction.nim` - `resolveRepairOrders()`
- `src/engine/resolution/automation.nim` - `submitAutoRepairs()`

**Repair Advancement:**
- `src/engine/economy/facility_queue.nim` - `advanceDrydockQueue()`

**Repair Commissioning:**
- `src/engine/resolution/commissioning.nim` - `commissionRepairedShips()`

**Repair Cost Calculation:**
- `src/engine/economy/projects.nim` - `calculateRepairCost()`

---

## PP Payment Timing

EC4X uses **different payment timing** for construction vs repairs.

### Construction: Upfront Payment

**When:** CMD6 (Order Processing & Validation)

**Rationale:** Deliberate player choice → commit resources upfront

**Algorithm:**

```nim
proc resolveBuildOrders(state: var GameState, packet: CommandPacket):
  for order in packet.buildOrders:
    let cost = calculateBuildCost(order)
    
    # Validate budget BEFORE queuing
    if state.houses[houseId].treasury < cost:
      events.add(BuildOrderRejected, "Insufficient funds")
      continue
    
    # DEDUCT PAYMENT IMMEDIATELY
    state.houses[houseId].treasury -= cost
    
    # Find facility with capacity
    let facility = assignFacility(state, order.colonyId, order.shipClass)
    if facility.isNone:
      events.add(BuildOrderRejected, "No dock capacity")
      state.houses[houseId].treasury += cost  # Refund
      continue
    
    # Add to queue
    facility.get().constructionQueue.add(ConstructionProject(
      shipClass: order.shipClass,
      turnsRemaining: 1,
      cost: cost,  # Already paid
      status: InProgress
    ))
```

### Repairs: Deferred Payment

**When:** CMD2 (Unified Commissioning in Command Phase)

**Rationale:** Auto-repair is AI helper → player needs cancel option before payment.
Repair queue advancement happens in PRD2, but actual payment occurs at CMD2 commissioning.

**Algorithm:**

```nim
proc advanceRepairQueues(state: var GameState):
  # Drydock repairs (ships)
  for drydock in state.allDrydocks():
    # Advance all
    for repair in drydock.repairQueue.mitems:
      repair.turnsRemaining -= 1
    
    # Process completed (FIFO order)
    var i = 0
    while i < drydock.repairQueue.len:
      let repair = drydock.repairQueue[i]
      
      if repair.turnsRemaining == 0:
        let house = state.houses[repair.houseId]
        
        if house.treasury >= repair.cost:
          # PAYMENT HERE
          house.treasury -= repair.cost
          
          # Commission immediately
          let ship = state.ships[repair.targetShipId]
          ship.status = Undamaged
          createFleetForRepairedShip(state, ship, drydock.colonyId)
          
          # Remove from queue, free dock
          drydock.repairQueue.delete(i)
          events.add(RepairCompleted, repair)
        
        else:
          # STALL
          repair.status = Stalled
          events.add(RepairStalled, repair, repair.cost)
          i += 1  # Stays in queue
      
      else:
        i += 1  # Still in progress
  
  # Colony repairs (same logic for ground units, facilities, starbases)
```

### FIFO Processing Example

**Scenario:** 3 repairs complete, limited funds

```
Treasury: 40 PP
Repairs in queue: Cruiser (30 PP), Destroyer (20 PP), Battleship (50 PP)

Processing (FIFO order):
1. Cruiser: 40 >= 30 ✓ → Pay (Treasury: 10 PP), commission
2. Destroyer: 10 < 20 ✗ → Stall
3. Battleship: (Not checked, previous stall stops processing)

Result: 1 commissioned, 2 stalled
```

### Stalling Mechanism

**What Happens:**
- Repair completes but payment fails
- Status changes to `Stalled`
- Ship stays in drydock queue
- Dock remains occupied
- Re-checked every Production Phase 2c

**Recovery:**
- Next turn: Check stalled repairs first
- If funds available: Pay, commission, free dock
- If still insufficient: Continue stalling

**Vulnerability:**
- Stalled ships occupy docks (reduces capacity)
- Ships in docks vulnerable to facility destruction
- May stall indefinitely (bankruptcy scenario)
- Creates strategic pressure to fund repairs

### Data Models

```nim
type ConstructionProject = object
  shipClass: ShipClass
  turnsRemaining: int
  cost: int  # Already paid at submission
  status: ConstructionStatus  # InProgress, PendingCommission
  facilityId: FacilityId
  submittedTurn: int

type RepairProject = object
  targetEntity: EntityId
  entityType: RepairableType
  turnsRemaining: int
  cost: int  # To be paid on completion
  paidFor: bool  # Always false until completion
  status: RepairStatus  # InProgress, Stalled
  facilityId: Option[FacilityId]  # Some for drydock, None for colony
  submittedTurn: int

type ConstructionStatus {.pure.} = enum
  InProgress
  PendingCommission

type RepairStatus {.pure.} = enum
  InProgress
  Stalled
```

---

## 3. Queue Lifecycle & Combat Effects

### Overview

**Construction and repair queues are vulnerable to combat.**

When facilities are destroyed/crippled or colonies are conquered, queues are **immediately cleared** during Conflict Phase Step 8. This creates strategic pressure to complete projects before threats arrive and rewards attackers for disrupting enemy production.

### Queue Clearing Trigger Conditions

**Comprehensive Matrix:**

| Event | Spaceport Queue | Shipyard Queue | Drydock Queue | Colony Construction | Colony Repair | Terraforming | Timing |
|-------|----------------|----------------|---------------|-------------------|---------------|--------------|---------|
| **Neoria Destroyed** | ✅ Clear | ✅ Clear | ✅ Clear | ❌ Unaffected | ❌ Unaffected | ❌ Unaffected | Conflict Step 8 |
| **Neoria Crippled** | ✅ Clear | ✅ Clear | ✅ Clear | ❌ Unaffected | ❌ Unaffected | ❌ Unaffected | Conflict Step 8 |
| **Colony Conquered** | ✅ Clear* | ✅ Clear* | ✅ Clear* | ✅ Clear | ✅ Clear | ✅ Clear | Conflict Step 8 |
| **Bombardment >50%** | ❌ Unaffected | ❌ Unaffected | ❌ Unaffected | ✅ Clear | ✅ Clear | ✅ Clear | Conflict Step 8 |

*Facility queues also cleared by facility destruction during orbital combat before invasion

**Definitions:**
- **Neoria:** Orbital facilities (Spaceports, Shipyards, Drydocks) with construction/repair queues
- **Destroyed:** Facility reduced to 0 HP, removed from game
- **Crippled:** Facility >50% damaged, capacity reduced to 0
- **Conquered:** Colony ownership transferred via successful planetary invasion
- **Bombardment >50%:** Infrastructure damage exceeds 50% threshold

### What Gets Cleared When

#### 1. Facility Destruction/Crippling

**Trigger:** Neoria (Spaceport/Shipyard/Drydock) destroyed or crippled in orbital combat

**Immediate Effects (Conflict Phase Step 8):**

```nim
proc handleFacilityDestruction(state: var GameState, facilityId: FacilityId):
  let facility = state.facility(facilityId).get()
  
  case facility.facilityType:
    of Spaceport:
      # Clear construction queue
      for project in facility.constructionQueue:
        events.add(ConstructionCanceled, project, "Facility destroyed")
      facility.constructionQueue.clear()
    
    of Shipyard:
      # Clear construction queue
      for project in facility.constructionQueue:
        events.add(ConstructionCanceled, project, "Facility destroyed")
      facility.constructionQueue.clear()
    
    of Drydock:
      # Clear repair queue, destroy ships in drydocks
      for repair in facility.repairQueue:
        state.destroyShip(repair.targetShipId)
        events.add(ShipDestroyedInDrydock, repair.targetShipId, facilityId)
      facility.repairQueue.clear()
    
    else:
      discard  # Kastras (Starbases) have no queues

proc handleFacilityCrippling(state: var GameState, facilityId: FacilityId):
  let facility = state.facility(facilityId).get()
  
  # Crippled = >50% damage
  if facility.damagePercent > 50:
    facility.status = Crippled
    facility.capacity = 0  # No new orders accepted
    
    # Clear queues (same as destruction, but facility survives)
    case facility.facilityType:
      of Spaceport, Shipyard:
        for project in facility.constructionQueue:
          events.add(ConstructionCanceled, project, "Facility crippled")
        facility.constructionQueue.clear()
      
      of Drydock:
        for repair in facility.repairQueue:
          # Ships return to colony as damaged (not destroyed like destruction case)
          let ship = state.ships[repair.targetShipId]
          ship.location = facility.colonyId
          ship.status = Damaged
          events.add(RepairCanceled, repair.targetShipId, "Facility crippled")
        facility.repairQueue.clear()
      
      else:
        discard
```

**Key Differences:**
- **Destroyed:** Ships in drydocks destroyed, facility removed from game
- **Crippled:** Ships in drydocks returned to colony as damaged, facility remains (can be repaired)

#### 2. Colony Conquest

**Trigger:** Successful planetary invasion (attacker wins planetary combat)

**Immediate Effects (Conflict Phase Step 8):**

```nim
proc handleColonyConquest(state: var GameState, colonyId: ColonyId, newOwner: HouseId):
  let colony = state.colony(colonyId).get()
  let oldOwner = colony.ownerId
  
  # 1. Transfer ownership
  colony.ownerId = newOwner
  events.add(ColonyCaptured, colonyId, oldOwner, newOwner)
  
  # 2. Clear ALL queues (facility + colony)
  
  # Facility queues (Spaceports/Shipyards/Drydocks)
  for facility in state.facilitiesAt(colonyId):
    case facility.facilityType:
      of Spaceport, Shipyard:
        for project in facility.constructionQueue:
          events.add(ConstructionCanceled, project, "Colony conquered")
        facility.constructionQueue.clear()
      
      of Drydock:
        for repair in facility.repairQueue:
          # Ships captured as damaged by new owner
          let ship = state.ships[repair.targetShipId]
          ship.ownerId = newOwner
          ship.status = Damaged
          events.add(ShipCaptured, repair.targetShipId, newOwner)
        facility.repairQueue.clear()
      
      else:
        discard
  
  # Colony queues (construction/repair/terraforming)
  for project in colony.constructionQueue:
    events.add(ConstructionCanceled, project, "Colony conquered")
  colony.constructionQueue.clear()
  
  for repair in colony.repairQueue:
    events.add(RepairCanceled, repair, "Colony conquered")
  colony.repairQueue.clear()
  
  if colony.terraformingProject.isSome:
    events.add(TerraformingCanceled, colony.terraformingProject.get(), "Colony conquered")
    colony.terraformingProject = none(TerraformingProject)
  
  # 3. Transfer ownership of ALL assets at colony
  transferColonyAssets(state, colonyId, newOwner)
```

**Assets Transferred:**
- Facilities (Spaceports, Shipyards, Drydocks, Starbases)
- Ground units (Marines, Armies, surviving defenders)
- Damaged ships (in drydocks or at colony)
- Fighters (in colony hangars or on ground)
- Infrastructure (IU, population)

**Assets Destroyed:**
- All queues (construction, repair, terraforming)
- In-progress projects (sunk costs for construction, no refunds for repairs)

#### 3. Severe Bombardment (>50% Infrastructure Damage)

**Trigger:** Orbital bombardment reduces colony infrastructure below 50%

**Immediate Effects (Conflict Phase Step 8):**

```nim
proc handleSevereBombardment(state: var GameState, colonyId: ColonyId):
  let colony = state.colony(colonyId).get()
  
  # Check infrastructure damage threshold
  if colony.infrastructureDamagePercent > 50:
    # Clear colony queues ONLY (not facility queues)
    
    for project in colony.constructionQueue:
      events.add(ConstructionCanceled, project, "Severe bombardment")
    colony.constructionQueue.clear()
    
    for repair in colony.repairQueue:
      events.add(RepairCanceled, repair, "Severe bombardment")
    colony.repairQueue.clear()
    
    if colony.terraformingProject.isSome:
      events.add(TerraformingCanceled, colony.terraformingProject.get(), "Severe bombardment")
      colony.terraformingProject = none(TerraformingProject)
    
    events.add(InfrastructureDamaged, colonyId, colony.infrastructureDamagePercent)
```

**Key Points:**
- **Only affects colony queues** (construction, repair, terraforming)
- **Does NOT affect facility queues** (Spaceports/Shipyards/Drydocks)
- Facilities must be targeted directly in orbital combat to clear their queues
- Represents disruption of planet-side industrial capacity

### Payment Implications

**The timing of payment determines refund eligibility:**

#### Construction: Upfront Payment (No Refunds)

**Payment:** CMD6 (Order Processing & Validation)

**Queue Clearing:** Conflict Phase Step 8 (next turn)

**Result:** Construction costs are **sunk costs** - no refunds when queues cleared

**Example:**
```
Turn 10 Command Phase:
  Player submits: Build Battleship (200 PP)
  Treasury: 500 PP → 300 PP (immediate payment)
  Battleship enters Shipyard queue (turnsRemaining: 1)

Turn 11 Conflict Phase:
  Enemy fleet attacks, destroys Shipyard
  Shipyard queue cleared (Battleship canceled)
  
  Treasury: Still 300 PP (NO REFUND)
  
  Strategic Loss: 200 PP sunk cost + loss of future asset
```

**Rationale:** Players made deliberate choice to invest PP. Queue clearing represents strategic risk, not system error.

#### Repairs: Deferred Payment (No Costs Yet)

**Payment:** CMD2 (commissioning, next turn)

**Queue Clearing:** Conflict Phase Step 8 (before payment)

**Result:** Repair costs **not yet paid** - no refunds needed

**Example:**
```
Turn 10 Command Phase:
  Auto-repair submits: Repair Cruiser (20 PP)
  Treasury: Unchanged (no payment yet)
  Cruiser enters Drydock queue (turnsRemaining: 1)

Turn 10 Production Phase:
  Repair advances (turnsRemaining: 0)
  Status: InProgress → AwaitingPayment
  Treasury: Still unchanged

Turn 11 Conflict Phase:
  Enemy fleet attacks, cripples Drydock
  Drydock queue cleared (Cruiser repair canceled)
  Cruiser returns to colony as Damaged
  
  Treasury: Still unchanged (NO PAYMENT EVER MADE)
  
  Strategic Loss: Wasted repair time (1 turn), ship still damaged
```

**Rationale:** Deferred payment supports auto-repair convenience without premature commitment. Queue clearing before payment means no refunds needed.

### Strategic Considerations

#### For Defenders

**Proactive Defense Required:**

The 1-turn commissioning lag creates a **2-turn warning window requirement**:

```
Turn N: Intelligence reports enemy fleet en route
Turn N: Order defenses (won't commission this turn)
Turn N+1 Conflict Phase: Defenses still in queue (vulnerable)
Turn N+1 Command Phase: Defenses commission
Turn N+2 Conflict Phase: Defenses operational, can fight

Conclusion: Need 2 turns advance warning to defend proactively
```

**Completion Priority:**

When threats detected:
1. **Complete high-value projects** before combat (Battleships, Starbases)
2. **Delay low-priority projects** until threat passes
3. **Consider canceling** risky projects if attack imminent
4. **Evacuate damaged ships** from threatened drydocks to safer colonies

**Economic Risk Management:**
- **Construction:** Already paid → complete if possible (don't waste sunk costs)
- **Repairs:** Not paid yet → cancel if completion unlikely (avoid wasting dock time)

#### For Attackers

**Timing Attacks:**

Optimal attack timing disrupts maximum enemy investment:

```
Enemy Construction Patterns:
Turn 8 Command: Enemy orders 5 Battleships (1000 PP total)
Turn 8 Production: Battleships advance (turnsRemaining: 1 → 0)
Turn 8 End: Battleships pending commission (still in queues)

Attacker's Decision:
Option A: Attack Turn 9 Conflict Phase
  → Destroy Shipyards BEFORE commissioning
  → Enemy loses 1000 PP investment + 5 Battleships never commission
  → Maximum disruption

Option B: Attack Turn 10 Conflict Phase
  → Battleships already commissioned (Turn 9 Command)
  → Enemy has 5 operational Battleships defending
  → Harder fight, less economic damage
```

**Target Prioritization:**

High-value targets for queue disruption:
1. **Shipyards with Battleship/Dreadnought queues** (200-300 PP each)
2. **Drydocks with capital ships** (25% original cost + ship value)
3. **Colonies with long terraforming projects** (multi-turn investment)
4. **Spaceports with full queues** (opportunity cost of lost capacity)

**Bombardment Strategy:**

Severe bombardment (>50% infrastructure) clears colony queues but NOT facility queues:

```
Strategic Choice:
- Orbital combat → Destroy facilities → Clear facility queues
- Bombardment → Damage infrastructure → Clear colony queues

Combine for maximum disruption:
1. Orbital combat: Destroy Shipyards (clear ship construction)
2. Bombardment >50%: Clear colony construction/repair/terraforming
3. Invasion: Conquer colony, capture remaining assets
```

### Integration with Turn Cycle

**Conflict Phase Step 8 (Immediate Combat Effects):**

Queue clearing happens immediately after combat resolution, ensuring clean state for subsequent phases:

```
Conflict Phase Sequence:
Step 1-7: Combat resolution (space, orbital, planetary)
Step 8: IMMEDIATE COMBAT EFFECTS
  ├─ Entity destruction (ships, facilities, ground units)
  ├─ Facility queue clearing (destroyed/crippled Neorias)
  ├─ Colony conquest effects (ownership transfer + ALL queue clearing)
  └─ Severe bombardment effects (>50% infrastructure → colony queue clearing)

Income Phase Step 4: Calculate Maintenance
  ├─ Uses post-combat ownership (from Step 8)
  └─ Only commissioned assets pay (queued assets exempt)

Income Phase Step 5: Capacity Enforcement
  ├─ Uses post-combat IU/infrastructure values (from Step 8)
  └─ Overage calculations respect queue clearing

CMD2: Unified Commissioning
   ├─ Only processes surviving queues (cleared queues empty)
   └─ No validation needed (entity existence = survival)
```

**Key Principle:** Conflict Phase Step 8 clears queues → Income Phase sees clean state → Command Phase processes survivors

### Code Flow Example

**Scenario:** Shipyard destroyed in orbital combat

```nim
# Conflict Phase Step 8: Orbital Combat Resolution
proc resolveOrbitalCombat(state: var GameState, systemId: SystemId):
  # ... combat calculations ...
  
  # Shipyard reduced to 0 HP
  let shipyard = state.facility(shipyardId).get()
  shipyard.hp = 0
  shipyard.status = Destroyed
  
  # IMMEDIATE queue clearing
  for project in shipyard.constructionQueue:
    events.add(ConstructionCanceled, 
      projectId: project.id,
      shipClass: project.shipClass,
      reason: "Facility destroyed",
      sunkCost: project.cost)  # Already paid, no refund
  
  shipyard.constructionQueue.clear()
  
  # Remove facility from game
  state.removeFacility(shipyardId)

# Income Phase Step 4: Maintenance Calculation
proc calculateMaintenance(state: GameState, house: House):
  # Destroyed shipyard no longer exists → no assets to maintain from that queue
  for ship in house.commissionedShips():
    house.maintenanceCost += ship.maintenanceCost
  
  # Ships that were in destroyed shipyard queue never commissioned → not counted

# CMD2: Unified Commissioning
proc unifiedCommissioning(state: var GameState):
  # Destroyed shipyard no longer exists → no queue to process
  for facility in state.allShipyards():  # Destroyed facility not in iteration
    commissionCompletedShips(state, facility)
```

### Events Generated

**Queue Clearing Events:**

```nim
type GameEvent = object
  turn: int
  phase: GamePhase
  eventType: EventType
  # ... event-specific data ...

# Construction Canceled
EventType.ConstructionCanceled:
  projectId: ProjectId
  shipClass: ShipClass
  facilityId: FacilityId
  colonyId: ColonyId
  reason: string  # "Facility destroyed" | "Facility crippled" | "Colony conquered" | "Severe bombardment"
  sunkCost: int   # PP already paid (no refund)

# Repair Canceled
EventType.RepairCanceled:
  repairId: RepairId
  targetShipId: ShipId
  facilityId: Option[FacilityId]  # Some for drydock, None for colony
  colonyId: ColonyId
  reason: string
  # No cost field (repairs not paid yet)

# Ship Destroyed in Drydock
EventType.ShipDestroyedInDrydock:
  shipId: ShipId
  shipClass: ShipClass
  facilityId: FacilityId
  colonyId: ColonyId
  # Facility destroyed → ships in drydocks destroyed

# Ship Captured (Crippled Drydock or Colony Conquest)
EventType.ShipCaptured:
  shipId: ShipId
  shipClass: ShipClass
  oldOwner: HouseId
  newOwner: HouseId
  status: ShipStatus  # Always Damaged
  location: ColonyId

# Terraforming Canceled
EventType.TerraformingCanceled:
  colonyId: ColonyId
  projectType: TerraformingType
  turnsInvested: int
  reason: string
```

### Testing Scenarios

**Critical test cases for queue clearing:**

1. **Facility Destroyed:** Spaceport with 3 ships in queue destroyed → all 3 canceled, sunk costs recorded
2. **Facility Crippled:** Drydock with 2 ships crippled → repairs canceled, ships returned as damaged
3. **Colony Conquered:** Colony with facility queues + colony queues → ALL cleared, assets transferred
4. **Severe Bombardment:** 60% infrastructure damage → colony queues cleared, facility queues intact
5. **Multiple Events:** Shipyard destroyed + Colony conquered → don't double-clear queues
6. **FIFO Integrity:** Queue cleared mid-advancement → no partial projects commissioned
7. **Stalled Repairs:** Drydock destroyed with stalled repairs → ships destroyed, no payment ever made

### Configuration

**Queue clearing thresholds:**

**File:** `config/combat.kdl`

```toml
[facilities]
crippled_threshold = 0.50  # >50% damage = crippled, queues cleared

[bombardment]
infrastructure_threshold = 0.50  # >50% damage = colony queues cleared
```

### Design Principles

**Immediate Effects:**
- Queue clearing happens in Conflict Phase Step 8 (not deferred)
- No validation needed in subsequent phases (entity existence = survival)
- Clean state for Income/Command phases

**No Refunds:**
- Construction: Already paid → sunk costs
- Repairs: Not paid yet → no refunds needed
- Strategic risk, not system error

**Event-Driven:**
- All queue clearing generates events for player visibility
- Events include sunk costs (construction) or lost opportunities (repairs)
- Strategic intelligence from event logs

---

## 4. Colony Construction

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

**Each Production Phase:**

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

## System Comparison

| Feature | Facility Docks | Colony Queue |
|---------|---------------|--------------|
| **What** | Capital ships (construction/repair) | Fighters, ground units, facilities |
| **Capacity** | 5-10 docks per facility | No hard limit (industrial capacity) |
| **Payment** | Construction: Upfront / Repairs: Deferred | Upfront |
| **Queue Model** | Queue entry = dock occupied | All entries active (no waiting list) |
| **Cost Penalty** | 2x at spaceports | None |
| **Advancement** | Per-facility FIFO | Single queue FIFO |
| **Commissioning** | Command Phase A (next turn) | Command Phase A (next turn) |
| **Maintenance Lag** | 1 turn (commission N, pay N+1) | 1 turn (commission N, pay N+1) |

**Note:** Other systems documented in specs:
- Terraforming → `docs/specs/04-research_development.md` Section 4.6
- Carrier hangar → `docs/specs/02-assets.md` Section 2.4.1

---

## Data Flow Diagram

```
=== TURN N: Command Phase ===

CMD2: Unified Commissioning
         ↓
┌─────────────────────────────────┐
│ Commission ALL completed assets │
│ - Ships from facilities         │
│ - Repaired ships (with payment) │
│ - Colony-built assets            │
│ → Frees capacity                │
└─────────────┬───────────────────┘
              ↓
CMD3: Auto-Repair Submission
              ↓
CMD4: Colony Automation
         (Auto-assign, Auto-load)
              ↓
CMD5: Player Window
              ↓
CMD6: Order Processing
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
=== TURN N: Production Phase ===
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
        │ Mark Completed:      │
        │ AwaitingCommission   │
        │ (Stay in queues)     │
        └──────────┬───────────┘
                   │
=== TURN N: Conflict Phase ===
                   ↓
        ┌──────────────────────┐
        │ Steps 1-7: Combat    │
        └──────────┬───────────┘
                   ↓
        ┌──────────────────────┐
        │ Step 8: IMMEDIATE    │
        │ COMBAT EFFECTS       │
        │ - Destroy entities   │
        │ - Clear queues       │
        │ - Transfer ownership │
        └──────────┬───────────┘
                   │
       (Turn boundary - state persisted)
                   │
=== TURN N+1: Income Phase ===
                   ↓
        ┌──────────────────────┐
        │ Calculate Maintenance│
        │ (Newly commissioned  │
        │  assets exempt)      │
        └──────────┬───────────┘
                   ↓
=== TURN N+1: Command Phase ===
                   ↓
        ┌──────────────────────┐
        │ CMD2: Commission     │
        │ Survivors from N     │
        │ (Frees capacity)     │
        └──────────┬───────────┘
                   ↓
        ┌──────────────────────┐
        │ CMD3-6: Automation   │
        │ and New Orders       │
        │ (Use freed capacity) │
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
- `advanceShipyardQueue(shipyard, colonyId)` - Advance shipyard construction only
- `advanceDrydockQueue(drydock, colonyId)` - Advance drydock repairs
- `advanceColonyQueues(colony)` - Advance all facilities at colony
- `advanceAllQueues(state)` - Advance all facilities across all colonies
- `startConstruction(colony, project)` - Add to colony queue (legacy)
- `advanceConstruction(colony)` - Advance colony queue (legacy)

**Purpose:** Queue advancement for facility queues (capital ships/repairs) and colony queues (fighters/buildings).

### Unified Commissioning System (2026-01-09)

**Module:** `src/engine/resolution/commissioning.nim`

EC4X uses a **unified commissioning system** where ALL assets commission in CMD2, regardless of type or build location.

#### Commissioning Timing

**When:** CMD2 (Unified Commissioning)

**What:** ALL completed assets from ALL sources:
- Ships from Spaceports/Shipyards (construction)
- Repaired ships from Drydocks (repairs with payment)
- Colony-built assets (fighters, marines, facilities, etc.)

**Strategic Rationale:** 
- Architectural simplicity (single commissioning point)
- No split timing complexity (uniform 1-turn lag)
- Clean separation: Production advances → Conflict resolves → Command commissions

#### All Assets Commission in CMD2

**Universal 1-Turn Lag:**

All assets experience the same commissioning delay:

```
Turn N Command Phase:
  - Player submits build order
  - Payment (construction: upfront, repairs: deferred)

Turn N Production Phase:
  - Project advances (turnsRemaining: 1 → 0)
  - Status: InProgress → AwaitingCommission
  - Asset NOT operational yet

Turn N Conflict Phase:
  - Assets in queues vulnerable to combat
  - Facilities can be destroyed/crippled
  - Colonies can be conquered

Turn N+1 CMD2 (Unified Commissioning):
   - UNIFIED COMMISSIONING
   - All completed assets commission together
   - Ships/fighters/marines/facilities operational
   - Docks freed, capacity available
```

**Key Properties:**
- No immediate commissioning (no same-turn defense)
- Proactive defense required (build 2 turns ahead of threats)
- All asset types treated uniformly
- Simpler mental model, no special cases

#### Commissioning Algorithm

```nim
proc unifiedCommissioning(state: var GameState):
  # CMD2: Commission ALL completed assets
  
  # 1. Ships from Spaceports
  for spaceport in state.allSpaceports():
    for project in spaceport.constructionQueue:
      if project.status == AwaitingCommission:
        let ship = createShip(state, project.shipClass, spaceport.colonyId)
        ship.commissioning.turnCommissioned = state.turn
        events.add(ShipCommissioned, ship.id, project)
        # Remove from queue, free dock
        spaceport.constructionQueue.removeProject(project.id)
  
  # 2. Ships from Shipyards
  for shipyard in state.allShipyards():
    for project in shipyard.constructionQueue:
      if project.status == AwaitingCommission:
        let ship = createShip(state, project.shipClass, shipyard.colonyId)
        ship.commissioning.turnCommissioned = state.turn
        events.add(ShipCommissioned, ship.id, project)
        shipyard.constructionQueue.removeProject(project.id)
  
  # 3. Repaired ships from Drydocks (WITH PAYMENT CHECK)
  for drydock in state.allDrydocks():
    commissionRepairedShips(state, drydock)  # Includes treasury check/stalling
  
  # 4. Colony-built assets (fighters, marines, facilities, etc.)
  for colony in state.allColonies():
    for project in colony.constructionQueue:
      if project.status == AwaitingCommission:
        commissionColonyAsset(state, colony, project)
        colony.constructionQueue.removeProject(project.id)
```

**No Validation Needed:**
- If entity exists in game state, it survived Conflict Phase
- Destroyed facilities/conquered colonies already handled in Conflict Phase Step 8
- Entity existence = implicit validation

#### Maintenance Timing

**Assets commissioned Turn N pay maintenance starting Turn N+1:**

```nim
# Income Phase Step 4: Calculate Maintenance
proc calculateMaintenance(state: GameState, house: var House):
  for ship in house.ships:
    if ship.commissioning.turnCommissioned < state.turn:
      # Commissioned previous turn or earlier → pay maintenance
      house.maintenanceCost += ship.maintenanceCost
    else:
      # Commissioned this turn → exempt (pay next turn)
      discard
```

**Simple 1-Turn Lag Rule:**
- No tracking of "commission turn" needed beyond first turn
- Assets commissioned Turn N exempt Turn N Income Phase
- Assets commissioned Turn N pay Turn N+1 Income Phase onwards

**Example:**
```
Turn 10 Command Phase A:
  Ship commissions (turnCommissioned = 10)

Turn 10 Income Phase:
  Ship exempt from maintenance (just commissioned)

Turn 11 Income Phase:
  Ship pays maintenance (commissioned last turn)

Turn 12+ Income Phase:
  Ship continues paying maintenance
```

#### Strategic Implications

**Proactive Defense Required:**

The 1-turn commissioning lag creates a **2-turn warning window requirement**:

```
Turn N: Intelligence reports enemy fleet en route
Turn N Command: Order defenses (won't commission this turn)
Turn N Production: Defenses complete, but not commissioned
Turn N Conflict: Defenses still in queues (vulnerable to combat)
Turn N+1 Command A: Defenses commission
Turn N+1 Conflict: Defenses operational, can engage threats

Conclusion: Need 2 turns advance warning to defend against incoming threats
```

**Comparison to Same-Turn Defense:**

Old system (split commissioning):
- Turn N Command: Order marines
- Turn N Production: Marines commission immediately
- Turn N+1 Conflict: Marines defend ✓ (1-turn warning)

New system (unified commissioning):
- Turn N Command: Order marines
- Turn N Production: Marines complete, NOT commissioned
- Turn N+1 Conflict: Marines STILL in queue (can't defend)
- Turn N+2 Conflict: Marines operational ✓ (2-turn warning)

**Gameplay Impact:**
- Rewards intelligence gathering (scouting, forward observers)
- Rewards planning over reactive play
- Punishes late responses to threats
- Makes surprise attacks more valuable

#### Commissioning Flow Diagram

```
Turn N Command Phase:
  CMD2: Unified Commissioning
    ├─ Commission ships from Spaceports/Shipyards
    ├─ Commission repaired ships from Drydocks (with payment)
    └─ Commission colony-built assets
  CMD3: Auto-Repair Submission
  CMD4: Colony Automation
  CMD5: Player Submission Window
  CMD6: Command Validation & Storage

Turn N Production Phase:
  Step 2: Queue Advancement
    ├─ Advance facility queues (construction/repair)
    ├─ Advance colony queues
    └─ Mark completed projects: AwaitingCommission

Turn N Conflict Phase:
  Step 8: Immediate Combat Effects
    ├─ Destroy entities
    ├─ Clear facility queues (destroyed/crippled)
    ├─ Clear all queues (colony conquest)
    └─ Clean state for next turn

Turn N+1 Income Phase:
  Step 4: Calculate Maintenance
    └─ Assets commissioned Turn N exempt (1-turn lag)

Turn N+1 Command Phase:
  CMD2: Unified Commissioning
    └─ Survivors from Turn N commission here
```

#### Example: Battleship Construction Timeline

```
Turn 10 Command Phase:
  CMD5: Player orders Battleship at Colony X
  CMD6: Payment (200 PP), added to Shipyard queue
  
  Shipyard queue: [Battleship(turnsRemaining: 1)]

Turn 10 Production Phase:
  Battleship advances (turnsRemaining: 1 → 0)
  Status: InProgress → AwaitingCommission
  
  Shipyard queue: [Battleship(status: AwaitingCommission)]

Turn 10 Conflict Phase:
  Enemy fleet attacks Colony X
  Destroys Shipyard in orbital combat
  Queue cleared → Battleship canceled (200 PP sunk cost)
  
  Shipyard: Destroyed
  Battleship: Never commissioned

Turn 11 Command Phase A:
  (If shipyard survived)
  Battleship commissions, dock freed
  Ship operational, auto-assigned to fleet
```

### Automation

**Module:** `src/engine/resolution/automation.nim`

**When:** CMD4 (after commissioning CMD2, after auto-repair CMD3, before player window CMD5)

**Functions:**
- `processColonyAutomation(state, orders)` - Batch automation processor
  - Auto-assign ships to fleets (per-colony toggle, `colony.autoJoinFleets`, default: true)
  - Auto-load fighters to carriers (per-colony toggle, `colony.autoLoadFighters`, default: true)
  - Auto-load marines to transports (per-colony toggle, `colony.autoLoadMarines`, default: true)

**Auto-Assign Ships:**
```nim
proc autoAssignShipsToFleets(state: var GameState, colony: Colony):
  if not colony.autoJoinFleets:
    return
  
  # Get all newly commissioned + repaired ships at colony (no fleet assignment)
  let unassignedShips = state.shipsAt(colony.id).filterIt(it.fleetId.isNone)
  
  for ship in unassignedShips:
    # Create new fleet or add to existing fleet at colony
    let fleet = findOrCreateFleet(state, colony.id, colony.ownerId)
    fleet.ships.add(ship.id)
    ship.fleetId = some(fleet.id)
    events.add(ShipAutoAssigned, ship.id, fleet.id)
```

**Key Properties:**
- Treats newly commissioned and repaired ships uniformly (both auto-assigned)
- No tracking of original fleet membership for repaired ships
- Creates new fleets if none exist at colony
- Respects per-colony toggle (`colony.autoJoinFleets`)

**Auto-Load Fighters:**
```nim
proc autoLoadFightersToCarriers(state: var GameState, colony: Colony):
  if not colony.autoLoadFighters:
    return
  
  let availableFighters = colony.fightersAvailable
  let carriers = state.carriersAt(colony.id).filterIt(
    it.status == Active and it.isStationary()
  )
  
  for carrier in carriers:
    let capacity = carrier.hangarCapacity - carrier.fighters.len
    let toLoad = min(capacity, availableFighters)
    carrier.fighters.add(availableFighters[0..<toLoad])
    colony.fightersAvailable.delete(0, toLoad)
```

**Restrictions:**
- Only loads to Active carriers (not Reserve/Mothballed)
- Only loads to stationary carriers (not moving/orders pending)
- Respects hangar capacity (ACO tech-based limits)

**Auto-Load Marines:**
```nim
proc autoLoadMarinesToTransports(state: var GameState, colony: Colony):
  if not colony.autoLoadMarines:
    return
  
  let availableMarines = colony.marinesAvailable
  let transports = state.troopTransportsAt(colony.id)
  
  for transport in transports:
    let capacity = transport.marineCapacity - transport.marines
    let toLoad = min(capacity, availableMarines)
    transport.marines += toLoad
    colony.marinesAvailable -= toLoad
```

**Purpose:** Automate routine asset management tasks, reducing micromanagement burden while preserving player control through toggles.

### Integration

**Module:** `src/engine/resolve.nim`

**Command Phase orchestration:**
```nim
proc resolveCommandPhase(state: var GameState):
  # CMD2: Unified Commissioning
  unifiedCommissioning(state)  # ALL assets commission here
  
  # CMD3: Auto-Repair Submission
  for colony in state.allColonies():
    if colony.autoRepair:
      submitAutoRepairs(state, colony.id)
  
  # CMD4: Colony Automation
  for colony in state.allColonies():
    autoAssignShipsToFleets(state, colony)  # Newly commissioned + repaired ships
    autoLoadFightersToCarriers(state, colony)
    autoLoadMarinesToTransports(state, colony)
  
  # CMD5: Player Submission Window (24-hour window)
  # (Players can cancel auto-repairs, submit manual orders)
  
  # CMD6: Command Validation & Storage
  processAllOrders(state)  # Build orders, move orders, etc.
```

**Module:** `src/engine/economy/engine.nim`

**Production Phase orchestration:**
```nim
proc resolveProductionPhase(state: var GameState):
  # Step 2: Queue Advancement
  advanceAllQueues(state)  # Facility + colony queues
  
  # Completed projects marked AwaitingCommission
  # (Commission next turn in CMD2)
```

**Module:** `src/engine/combat/orchestrator.nim`

**Conflict Phase orchestration:**
```nim
proc resolveConflictPhase(state: var GameState):
  # Steps 1-7: Combat resolution
  resolveSpaceCombat(state)
  resolveOrbitalCombat(state)
  resolvePlanetaryCombat(state)
  
  # Step 8: IMMEDIATE COMBAT EFFECTS
  processImmediateCombatEffects(state)
    # - Entity destruction
    # - Queue clearing (facilities)
    # - Colony conquest effects
    # - Severe bombardment effects
```

**Key Flow:**
1. **Command A:** Commission survivors from last turn
2. **Command B-E:** Submit orders, automate, validate
3. **Production:** Advance queues, mark completed
4. **Conflict:** Resolve combat, clear queues immediately
5. **Income:** Calculate based on post-combat state
6. **Next Command A:** Commission new survivors

---

## Configuration

### Dock Capacity

**File:** `config/facilities.kdl`

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
