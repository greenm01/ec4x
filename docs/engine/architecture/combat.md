# Combat System Architecture

**Purpose:** Implementation architecture for EC4X combat system  
**Last Updated:** 2026-01-09  
**Status:** Unified Commissioning + Immediate Combat Effects

---

## Overview

EC4X combat follows a **theater progression model** (Space → Orbital → Planetary) with immediate combat effects processing. This document describes the combat system architecture, integration with other systems, and event-driven state management.

**Core Principles:**
- **Immediate Effects:** Combat consequences applied instantly (Conflict Phase Step 8)
- **Event-Driven:** All combat effects generate events for telemetry/prestige
- **No Validation:** Entity existence = survival (destroyed entities removed, queues cleared)
- **Clean State:** Income Phase receives clean post-combat state (correct ownership, cleared queues)

**Related Documentation:**
- **Specification:** `docs/specs/07-combat.md` (gameplay rules)
- **Turn Cycle:** `docs/engine/architecture/ec4x_canonical_turn_cycle.md` (phase timing)
- **Construction/Repair:** `docs/engine/architecture/construction-repair-commissioning.md` (queue mechanics)
- **Colony Management:** `docs/engine/mechanics/colony-management.md` (automation, terraforming)

---

## Theater Progression

### Space Combat (Theater 1)
- **Participants:** Mobile fleets (active, patrol, offensive missions)
- **Exclusions:** Guard fleets (orbital only), Reserve fleets (orbital only), Scouts (intel only)
- **Outcome:** Attackers achieve space superiority → Proceed to Orbital Combat

### Orbital Combat (Theater 2)
- **Participants:** Guard fleets, Reserve fleets, Starbases, unassigned ships, mothballed fleets (screened)
- **Facilities:** Starbases fight directly (AS/DS contribution), orbital Neorias screened (Shipyards/Drydocks)
- **Outcome:** Attackers achieve orbital supremacy → Proceed to Planetary Combat
- **Screened Units Destroyed:** If defenders eliminated, screened units lost (mothballed ships, orbital Neorias, auxiliary vessels)

### Planetary Combat (Theater 3)
- **Bombardment:** Fleet AS vs Ground Batteries + Planetary Shields
- **Invasion:** Marines vs Ground Forces (requires all batteries destroyed)
- **Blitz:** Combined bombardment + invasion (marines land under fire)
- **Outcome:** Colony captured (ownership transfer) OR invasion repelled

**Key Property:** Sequential progression - must win each theater to advance.

---

## Conflict Phase Integration

### Step 1-7: Combat Resolution
- Execute all combat operations (Space, Orbital, Planetary, Blockade, Colonization, Intelligence)
- Mark entities as Destroyed or Crippled (CombatState enum)
- Generate combat events (ShipDestroyed, FacilityDestroyed, ColonyCaptured, etc.)

### Step 8: Immediate Combat Effects

**Purpose:** Apply all combat consequences before turn boundary. Ensures Income Phase sees clean state.

**Timing:** After all combat resolution, before Income Phase

**Processing Order:**

**1. Entity Destruction**
- Remove destroyed entities from game state:
  - Ships (CombatState.Destroyed)
  - Neorias (Spaceports, Shipyards, Drydocks)
  - Kastras (Starbases)
  - Ground units (marines, armies, ground batteries, planetary shields)
- Delete entity from EntityManager
- Update secondary indexes (bySystem, byOwner, byColony)
- **Implementation:** `cleanup.cleanupDestroyedEntities(state, systemId)`

**2. Crippled Facility Queue Clearing**

**Crippled Neorias (Spaceports/Shipyards/Drydocks):**
- Neoria.state = Crippled
- Neoria.effectiveDocks = 0 (non-functional until repaired)
- Clear Neoria.constructionQueue (Spaceports/Shipyards)
- Clear Neoria.repairQueue (Drydocks)
- Ships/projects in crippled docks = LOST (not commissioned)
- Facility entity remains (can be repaired: 25% build cost via colony repair queue)
- Generate `ColonyProjectsLost` event (telemetry)

**Crippled Kastras (Starbases):**
- Kastra.state = Crippled
- Kastra AS/DS reduced to 50%
- No queues to clear (Kastras don't have construction/repair queues)
- Can be repaired via colony repair queue (25% build cost)

**Rationale:** Crippled facilities non-functional (0 capacity). Ships in crippled docks vulnerable, cannot commission.

**3. Colony Conquest Effects**

**Trigger:** Planetary invasion/blitz successful (attacker survived, defender eliminated)

**Ownership Transfer:**
```nim
colony_ops.changeColonyOwner(state, colonyId, attackingHouseId)
colony.owner = attackingHouseId  # Immediate
```

**Queue Clearing:**
- Clear `colony.constructionQueue` (all pending construction projects)
- Clear `colony.repairQueue` (all pending repair projects)
- Clear `colony.underConstruction` (active construction project)
- Cancel `colony.activeTerraforming` (terraforming project)

**Payment Implications:**
- Construction: Paid upfront (Command Phase E) = sunk cost for previous owner
- Repairs: Deferred payment (not yet paid) = no refund
- Terraforming: Paid upfront (Command Phase E) = sunk cost

**Facility Queues:** Also cleared by facility destruction during orbital combat (Spaceports/Shipyards/Drydocks destroyed)

**Events Generated:**
- `ColonyCaptured` (includes infrastructureLost, projectsLost counts)
- Event cached with deltas for prestige calculation (Income Phase Step 7)

**Rationale:** Conqueror inherits empty colony without previous owner's work-in-progress. Represents disruption of colony operations during conquest.

**4. Severe Bombardment Effects (>50% Infrastructure Damage)**

**Trigger:** Bombardment destroys >50% of colony infrastructure
```nim
if infrastructureDamaged > (colony.infrastructure * 0.5):
```

**Queue Clearing:**
- Clear `colony.constructionQueue`
- Clear `colony.repairQueue`
- Clear `colony.underConstruction`
- Cancel `colony.activeTerraforming`

**Rationale:** Severe bombardment (>50% infrastructure destroyed) disrupts all colony operations. Industrial capacity devastated, projects cannot continue.

**Events Generated:**
- `InfrastructureDamaged` (infrastructureLost amount)
- `ColonyProjectsLost` (construction/repair counts)

**Strategic Impact:**
- Timing bombardment to hit during construction = deny enemy assets
- Attacking during pending commissions = maximize enemy losses

---

## Combat Effects on Queues

### Trigger Conditions Table

| Event | Spaceport Queue | Shipyard Queue | Drydock Queue | Colony Construction | Colony Repair | Terraforming | Timing |
|-------|----------------|----------------|---------------|---------------------|---------------|--------------|--------|
| Neoria Destroyed | ✅ Cleared | ✅ Cleared | ✅ Cleared | ❌ N/A | ❌ N/A | ❌ N/A | Conflict Step 8 |
| Neoria Crippled | ✅ Cleared | ✅ Cleared | ✅ Cleared | ❌ N/A | ❌ N/A | ❌ N/A | Conflict Step 8 |
| Colony Conquered | ✅ Cleared* | ✅ Cleared* | ✅ Cleared* | ✅ Cleared | ✅ Cleared | ✅ Cancelled | Conflict Step 8 |
| Bombardment >50% | ❌ N/A | ❌ N/A | ❌ N/A | ✅ Cleared | ✅ Cleared | ✅ Cancelled | Conflict Step 8 |

*Facility queues also cleared by facility destruction during orbital combat

### Queue Clearing Implementation

**Destroyed Facilities:**
```nim
# cleanup.cleanupDestroyedEntities(state, systemId)
for neoriaId in destroyedNeorias:
  let neoria = state.neoria(neoriaId).get()
  
  # Clear queues
  for projectId in neoria.constructionQueue:
    project_ops.completeConstructionProject(state, projectId)
  for projectId in neoria.repairQueue:
    project_ops.completeRepairProject(state, projectId)
  
  # Delete entity
  neoria_ops.destroyNeoria(state, neoriaId)
```

**Crippled Facilities:**
```nim
# cleanup.clearCrippledFacilityQueues(state, systemId, events)
for neoria in state.neoriasAtColony(colonyId):
  if neoria.state == Crippled:
    # Clear queues
    for projectId in neoria.constructionQueue:
      project_ops.completeConstructionProject(state, projectId)
    for projectId in neoria.repairQueue:
      project_ops.completeRepairProject(state, projectId)
    
    # Set capacity to 0
    neoria.effectiveDocks = 0
    state.updateNeoria(neoria.id, neoria)
    
    # Generate event
    events.add(colonyProjectsLost(...))
```

**Colony Conquest:**
```nim
# Process colony conquest effects
if invasionSuccess:
  let oldOwner = colony.owner
  
  # Transfer ownership
  colony_ops.changeColonyOwner(state, colonyId, attackingHouseId)
  
  # Clear all colony queues
  for projectId in colony.constructionQueue:
    project_ops.completeConstructionProject(state, projectId)
  for projectId in colony.repairQueue:
    project_ops.completeRepairProject(state, projectId)
  
  colony.underConstruction = none(ConstructionProjectId)
  colony.activeTerraforming = none(TerraformProject)
  state.updateColony(colonyId, colony)
  
  # Generate events
  events.add(colonyCaptured(attackingHouseId, oldOwner, colonyId, ...))
```

**Severe Bombardment:**
```nim
# Check infrastructure damage threshold
if infrastructureDamaged > (colony.infrastructure * 0.5):
  # Clear colony queues (same logic as conquest)
  cleanup.clearColonyQueues(state, colonyId, events)
  
  # Generate events
  events.add(infrastructureDamaged(...))
  events.add(colonyProjectsLost(...))
```

---

## Payment Implications

### Construction (Upfront Payment)
- **When:** Command Phase E (order submission)
- **Amount:** Full build cost (ship, facility, terraforming)
- **Lost on Combat:** Sunk cost (no refund)
- **Rationale:** Deliberate player choice requires upfront commitment

**Example:**
```
Turn 5 Command E: Order Battleship (pay 500 PP)
Turn 5 Production: Battleship construction advances
Turn 6 Conflict: Colony conquered → Battleship construction LOST
Result: 500 PP sunk cost (no refund)
```

### Repair (Deferred Payment)
- **When:** Command Phase A (commissioning, next turn after completion)
- **Amount:** 25% of original build cost
- **Lost on Combat:** No payment yet made = no refund, but no cost
- **Rationale:** Auto-repair convenience requires cancel option before payment

**Example:**
```
Turn 5 Command B: Auto-repair submits Cruiser (no payment)
Turn 5 Production: Repair advances
Turn 6 Conflict: Drydock crippled → Cruiser repair LOST
Result: No PP lost (payment deferred, never made)
```

### Terraforming (Upfront Payment)
- **When:** Command Phase E (order submission)
- **Amount:** Full terraforming cost (planet class upgrade)
- **Lost on Combat:** Sunk cost (no refund)
- **Rationale:** Multi-turn project requires upfront commitment

**Example:**
```
Turn 5 Command E: Order Terraforming Class 2→3 (pay 200 PP)
Turn 5 Production: Terraforming advances (5 turns remaining)
Turn 6 Conflict: Colony conquered → Terraforming CANCELLED
Result: 200 PP sunk cost (no refund)
```

---

## Integration with Commissioning

### Vulnerability Window

**Pending Commissions Vulnerable:**
- Ships complete Production Phase → marked PendingCommission
- Sit in docks/queues until Command Phase A (next turn)
- **Vulnerable window:** Entire Conflict Phase + Income Phase

**Protection:**
- Facility destroyed → Pending ships in docks LOST
- Facility crippled → Pending ships in docks LOST
- Colony conquered → All pending colony assets LOST

### Proactive Defense Required

**1-Turn Commissioning Lag:**
```
Turn 5 Command: Scout spots enemy fleet 1 jump away
Turn 5 Command E: Order 3 Marines for defense
Turn 5 Production: Marines complete, marked PendingCommission

Turn 6 Conflict: Enemy arrives, invades
  → Marines NOT commissioned yet (still pending)
  → Marines DON'T defend
  → Colony conquered, Marines LOST

Correct Timeline (2-turn ahead planning):
Turn 4 Command E: Order 3 Marines (proactive)
Turn 4 Production: Marines complete
Turn 5 Command A: Marines commissioned
Turn 5-6: Marines available at colony
Turn 6 Conflict: Enemy arrives → Marines defend ✓
```

**Implication:** Defenders must build defenses **2 turns ahead** of threats. Intelligence and forward planning critical.

### Strategic Considerations

**For Defenders:**
- Complete high-value projects before threats arrive
- Evacuate ships from docks if attack imminent
- Stalled repairs especially vulnerable (occupy docks for multiple turns)
- Don't queue expensive projects during wartime (sunk cost risk)

**For Attackers:**
- Time attacks to hit during enemy construction cycles
- Target facilities to destroy pending commissions
- Conquest during pending commissions = maximum enemy asset denial
- Bombardment >50% = destroy all colony work-in-progress

---

## Event Schema

### ColonyCaptured
```nim
GameEvent(
  eventType: ColonyCaptured,
  turn: currentTurn,
  attackingHouseId: some(attackerHouseId),
  defendingHouseId: some(defenderHouseId),
  systemId: some(systemId),
  newOwner: some(attackerHouseId),
  oldOwner: some(defenderHouseId),
  # Extended fields for telemetry
  infrastructureLost: some(infrastructureDamaged),  # IU destroyed
  projectsLost: some(ProjectCounts(
    constructionCount: queuedConstructionCount,
    repairCount: queuedRepairCount,
    terraformingCancelled: terraformingWasActive
  )),
  # Cached deltas for prestige (Income Phase Step 7)
  changeAmount: some(prestigeDeltaAttacker)
)
```

### FacilityDestroyed
```nim
GameEvent(
  eventType: FacilityDestroyed,
  turn: currentTurn,
  houseId: some(facilityOwner),
  systemId: some(systemId),
  details: some("Spaceport/Shipyard/Drydock destroyed"),
  # Track what was lost
  projectsLost: some(ProjectCounts(...))
)
```

### FacilityCrippled
```nim
GameEvent(
  eventType: FacilityCrippled,
  turn: currentTurn,
  houseId: some(facilityOwner),
  systemId: some(systemId),
  details: some("Spaceport/Shipyard/Drydock crippled, capacity = 0"),
  projectsLost: some(ProjectCounts(...))
)
```

### InfrastructureDamaged
```nim
GameEvent(
  eventType: InfrastructureDamaged,
  turn: currentTurn,
  houseId: some(colonyOwner),
  systemId: some(systemId),
  infrastructureLost: some(iuDestroyed),
  populationLost: some(ptuKilled),
  # Trigger for queue clearing
  details: some("Severe bombardment >50%, queues cleared")
)
```

### ColonyProjectsLost
```nim
GameEvent(
  eventType: ColonyProjectsLost,
  turn: currentTurn,
  houseId: some(colonyOwner),
  systemId: some(systemId),
  projectsLost: some(ProjectCounts(
    constructionCount: lostCount,
    repairCount: lostCount,
    terraformingCancelled: bool
  ))
)
```

**Event Usage:**
- Telemetry: Historical analysis, balance testing
- Prestige: Calculate prestige deltas (cached in events)
- Intel: Enemy combat reports for scout observations
- UI: Player notifications, combat logs

---

## Code Modules

### combat/orchestrator.nim
**Purpose:** Theater progression orchestration

**Key Functions:**
- `resolveSystemCombat(state, systemId, orders, events)` - Main entry point
- `resolveSpaceCombat(...)` - Theater 1
- `resolveOrbitalCombat(...)` - Theater 2
- `resolvePlanetaryCombat(...)` - Theater 3 (bombardment/invasion/blitz)
- `resolveBlockades(...)` - Blockade resolution

**Integration:** Called by turn cycle Conflict Phase

### combat/cleanup.nim
**Purpose:** Post-combat entity removal and queue clearing

**Key Functions:**
- `cleanupPostCombat(state, systemId)` - Master cleanup function
- `cleanupDestroyedEntities(state, systemId)` - Remove destroyed entities
- `cleanupDestroyedNeorias(state, systemId)` - Clear facility queues (destroyed)
- `clearCrippledFacilityQueues(state, systemId, events)` - Clear facility queues (crippled)
- `clearColonyConstructionQueue(state, colonyId, generateEvent, events)` - Clear colony queues
- `clearColonyConstructionOnConquest(state, colonyId, newOwner)` - Conquest-specific clearing
- `clearColonyConstructionOnBombardment(state, colonyId, events)` - Bombardment-specific clearing

**Integration:** Called by Conflict Phase Step 8

### combat/planetary.nim
**Purpose:** Planetary combat mechanics

**Key Functions:**
- `resolveBombardment(state, fleets, colonyId, rng)` - Orbital bombardment
- `resolveInvasion(state, fleets, colonyId, rng)` - Standard invasion
- `resolveBlitz(state, fleets, colonyId, rng)` - Blitz operation
- `destroyShields(state, colonyId)` - Destroy planetary shields (invasion)
- `destroySpaceports(state, colonyId)` - Destroy spaceports (invasion)

**Integration:** Called by orchestrator during planetary combat theater

### entities/colony_ops.nim
**Purpose:** Colony entity operations

**Key Functions:**
- `changeColonyOwner(state, colonyId, newOwner)` - Transfer ownership
- `establishColony(...)` - Create new colony (colonization)
- `destroyColony(state, colonyId)` - Remove colony entirely

**Integration:** Called by combat cleanup during conquest processing

### entities/project_ops.nim
**Purpose:** Construction/repair project lifecycle

**Key Functions:**
- `completeConstructionProject(state, projectId)` - Cancel/complete project
- `completeRepairProject(state, projectId)` - Cancel/complete repair

**Integration:** Called by cleanup when clearing queues

---

## Design Patterns

### Event-Driven State Changes

**Pattern:** Combat generates events, events drive state changes

**Benefits:**
- Single source of truth (event log)
- Telemetry/analytics built-in
- Deterministic (replay events = recreate state)
- Testable (events as data, not side effects)

**Example:**
```nim
# Conflict Phase: Generate event
events.add(colonyCaptured(...))

# Conflict Phase Step 8: Process event
for event in events:
  if event.eventType == ColonyCaptured:
    changeColonyOwner(state, event.colonyId, event.newOwner)
    clearColonyQueues(state, event.colonyId, events)
```

### No Validation Pattern

**Pattern:** Entity existence = survival validation

**Benefits:**
- Simpler code (no validation checks needed)
- Clear mental model ("if it exists, it survived")
- Single cleanup point (Conflict Phase Step 8)

**Example:**
```nim
# Command Phase A: Commission pending ships
for neoria in state.allNeorias():
  for projectId in neoria.constructionQueue:
    if project.status == PendingCommission:
      commissionShip(state, project)
      # No validation needed - if neoria exists, it survived combat
```

**Why It Works:** Destroyed/crippled facilities had queues cleared in Conflict Phase. Only surviving facilities have pending commissions.

### Immediate Effects Pattern

**Pattern:** Apply combat effects in Conflict Phase, not deferred to later phases

**Benefits:**
- Income Phase sees clean state (correct ownership, cleared queues)
- No phantom queue entries
- Maintenance calculations accurate
- Capacity enforcement uses correct values

**Tradeoff:** Conflict Phase does more work, but subsequent phases simpler

---

## Testing Considerations

### Unit Tests

**File:** `tests/unit/test_combat_effects.nim`

**Coverage:**
- Queue clearing (destroyed/crippled facilities)
- Colony conquest (ownership transfer + queue clearing)
- Bombardment effects (>50% threshold)
- Event generation (all combat event types)

### Integration Tests

**File:** `tests/integration/test_combat_commissioning.nim`

**Scenarios:**
1. Ship completes Turn N → Facility destroyed Turn N Conflict → Ship LOST (not commissioned)
2. Ship completes Turn N → Facility survives Turn N Conflict → Ship commissioned Turn N+1 Command A
3. Colony queued projects → Colony conquered Turn N → Queues cleared, conqueror inherits empty colony
4. Drydock repair pending → Drydock crippled Turn N → Repair LOST, ship not commissioned
5. Severe bombardment (>50% damage) → Colony queues cleared, terraforming cancelled

### Balance Testing

**Scenarios:**
- Proactive vs reactive defense (1-turn commissioning lag impact)
- Stalled repair vulnerability (ships in docks for multiple turns)
- Timing attacks during enemy construction cycles
- Conquest vs bombardment (asset denial strategies)

---

## Future Enhancements

### Potential Improvements

**1. Partial Queue Preservation (Design Alternative)**
- Instead of clearing all queues, preserve X% of progress
- Represents salvaging partially-completed work
- More forgiving for defenders, less punishing for conquest

**2. Refund Mechanics**
- Partial refunds for cancelled projects (e.g., 50% of construction cost)
- Makes conquest/bombardment less economically devastating
- Reduces sunk cost risks

**3. Queue Priority System**
- High-priority projects continue even during bombardment
- Low-priority projects cancelled first
- Player control over critical vs expendable projects

**4. Facility Repair During Combat**
- Emergency repairs during multi-round combat
- Costs PP, reduces combat effectiveness temporarily
- Adds tactical depth to prolonged sieges

### Migration Notes

**Current Implementation Status:**
- ✅ Theater progression (orchestrator.nim)
- ✅ Entity destruction cleanup (cleanup.nim)
- ⚠️ Crippled facility queue clearing (documented, needs implementation)
- ⚠️ Colony conquest queue clearing (documented, needs implementation)
- ⚠️ Bombardment >50% queue clearing (documented, needs implementation)
- ⚠️ Unified commissioning (documented, needs refactoring)

**Implementation Priority:**
1. Crippled facility queue clearing (Conflict Phase Step 8)
2. Colony conquest effects (ownership + queues)
3. Bombardment effects (>50% threshold)
4. Unified commissioning (Command Phase A restructure)

---

## Related Systems

### Prestige System
- Combat events drive prestige calculations (Income Phase Step 7)
- Cached deltas in events (no recalculation needed)
- Colony captured: Attacker +prestige, Defender -prestige

### Capacity Enforcement
- Uses post-combat ownership (Income Phase Step 5)
- IU values updated after conquest/bombardment
- Capital/total/fighter squadron limits based on clean state

### Intelligence System
- Scout observations generate combat intel reports
- Events filtered by fog-of-war visibility
- Perfect intelligence for direct participants

### Diplomatic System
- Combat outcomes trigger diplomatic state changes
- Colony capture = casus belli
- Blockades require enemy/hostile status

---

**End of Combat System Architecture Documentation**
