src/engine/
    │
    ├── globals.nim         # [GLOBAL VARIABLES] Threadvar module-level storage.
    │
    ├── engine.nim          # [MAIN APPLICATION ENTRY] Orchestrates game lifecycle.
    │                       #   - Initializes new games.
    │                       #   - Loads/Saves state via `@persistence`.
    │                       #   - Drives the main turn cycle via `@turn_cycle/turn_executor.nim`.
    │
    ├── @config/            # [GAME DATA CONFIGURATION] All static game rules and values.
    │   └── *.nim           #   - Loaded during game initialization.
    │
    ├── @types/             # [DATA SCHEMA] Defines ALL pure data structures (Fleet, Ship, GameState).
    │   ├── capacity.nim    #   - Defines types for the capacity system.
    │   └── *.nim           #   - Universal data types for the entire engine.
    │
    ├── @init/              # [GAME SETUP & BOOTSTRAP]
    │   ├── engine.nim      #   - Entry for new game creation.
    │   ├── house.nim       #   - House initialization with tech tree validation.
    │   ├── colony.nim      #   - Homeworld colony creation with facilities.
    │   ├── fleet.nim       #   - Starting fleet composition and creation.
    │   ├── multipliers.nim #   - Dynamic prestige/population multipliers.
    │   └── validation.nim  #   - Validates initial game setup.
    │
    ├── @persistence/       # [SAVE/LOAD MANAGEMENT]
    │   ├── schema.nim      #   - Serialization/deserialization logic.
    │   ├── writer.nim      #   - Writes `GameState` to storage.
    │   ├── queries.nim     #   - Reads `GameState` from storage.
    │   └── types.nim       #   - Types specific to save data.
    │
    │                                     (READ-ONLY ACCESS)
    │                         ┌──────────────────────────────────────────────┐
    │                         │                                              │
    ├── @state/               # [STATE MANAGEMENT CORE - The "Database"]     ▼
    │   │                     # Provides generic, low-level mechanics for storing and accessing data.
    │   ├── entity_manager.nim#   - Implements the generic DoD storage pattern (data: seq, index: Table).
    │   ├── game_state.nim    #   - `initGameState` constructor, simple getters, and trackers (e.g., `GracePeriodTracker`).
    │   ├── id_gen.nim        #   - Logic for generating new, unique entity IDs.
    │   ├── iterators.nim     #   - The PRIMARY READ-ONLY API for the engine (e.g., `fleetsInSystem`, `coloniesOwned`).
    │   │                     #   - ALWAYS use iterators instead of `.entities.data` with manual filtering.
    │   │                     #   - Provides O(1) indexed lookups via `byHouse`, `byOwner`, `bySystem` tables.
    │   └── fog_of_war.nim    #   - A complex READ-ONLY query system that transforms `GameState` into a `PlayerView`.
    │
    │                                     (WRITE/MUTATION ACCESS)
    │                         ┌──────────────────────────────────────────────┐
    │                         │                                              │
    ├── @entities/            # [ENTITY-SPECIFIC MUTATORS - The "Write API"] ▼
    │   │                     # Handles complex state changes for specific entities, ensuring data consistency.
    │   │                     # **KEY PRINCIPLE**: Index-aware mutations only. NO business logic.
    │   │
    │   ├── fleet_ops.nim     #   - `createFleet`, `destroyFleet`, `moveFleet`, `changeFleetOwner`
    │   │                     #   - Maintains `bySystem` (spatial) and `byOwner` (ownership) indexes
    │   │
    │   ├── ship_ops.nim      #   - `add/remove` -> updates ship list AND `bySquadron` index
    │   ├── colony_ops.nim    #   - `establishColony`, `destroyColony`, `changeColonyOwner`
    │   │                     #   - Maintains `bySystem` and `byOwner` indexes
    │   ├── squadron_ops.nim  #   - `createSquadron`, `destroySquadron`, `transferSquadron`
    │   │                     #   - Maintains `byFleet` index
    │   ├── ground_unit_ops.nim
    │   ├── facility_ops.nim
    │   ├── project_ops.nim
    │   └── population_transfer_ops.nim
    │
    │
    │                         (Reads from @state, Writes via @entities)
    │                         ┌──────────────────────────────────────────────┐
    │                         │                                              │
    ├── @systems/             # [GAME LOGIC IMPLEMENTATION - The "Domain Experts"]
    │   │                     # Contains all the detailed algorithms for game features.
    │   │                     # **KEY PRINCIPLE**: Business logic, validation, algorithms. NO index manipulation.
    │   │
    │   ├── colony/           #   - Colony domain logic
    │   │   ├── engine.nim    #     - High-level API: `establishColony` (validation + prestige)
    │   │   ├── conflicts.nim #     - Simultaneous colonization resolution
    │   │   └── ...           #     - Other colony-specific systems
    │   │
    │   ├── fleet/            #   - Fleet domain logic
    │   │   ├── engine.nim    #     - High-level API: `createFleetCoordinated`, `mergeFleets`, `splitFleet`
    │   │   ├── entity.nim    #     - Fleet business logic: `canMergeWith`, `combatStrength`, `balanceSquadrons`
    │   │   └── ...           #     - Other fleet-specific systems
    │   │
    │   ├── squadron/         #   - Squadron domain logic
    │   │   ├── engine.nim    #     - High-level API (stub for future)
    │   │   ├── entity.nim    #     - Squadron business logic
    │   │   └── ...           #     - Other squadron-specific systems
    │   │
    │   ├── ship/             #   - Ship domain logic
    │   │   ├── engine.nim    #     - High-level API (stub for future)
    │   │   ├── entity.nim    #     - Ship business logic
    │   │   └── ...           #     - Other ship-specific systems
    │   │
    │   ├── economy/          #   - Logic for calculating income, production, maintenance
    │   ├── combat/           #   - Logic for resolving space and ground battles
    │   ├── research/         #   - Logic for tech tree advancement
    │   ├── capacity/         #   - Logic for enforcing squadron and ship capacity limits
    │   └── ...etc            #   - Each module takes `GameState`, performs reads via `@state/iterators`,
    │                         #     and writes changes via the `@entities` managers
    │
    │
    │                         (Orchestrates @systems)
    │                         ┌──────────────────────────────────────────────┐
    │                         │                                              │
    └── @turn_cycle/          # [ORCHESTRATION - The "Main Loop"]            ▼
        │                     # Lightweight modules that define the sequence of the game.
        ├── turn_executor.nim #   - The main driver. Calls each phase in order.
        ├── income_phase.nim  #   - Calls the relevant system(s), e.g., `systems/economy/engine.calculateIncome(state)`.
        ├── conflict_phase.nim#   - Calls `systems/combat/engine.resolveAllCombats(state)`.
        └── ...etc            #   - Passes the `GameState` from one system to the next.

# Entity Management Developer Guide

## The Three-Layer Pattern

EC4X uses a strict three-layer pattern for entity management:

```
┌─────────────────────────────────────────────────────────────┐
│ Layer 3: SYSTEMS (@systems/)                                │
│ • Business logic, validation, algorithms                    │
│ • Reads via iterators, writes via entity ops                │
│ • Example: combat resolution, economic calculations         │
└─────────────────────────────────────────────────────────────┘
                              ▲
                              │ reads via iterators
                              │ writes via entity ops
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ Layer 2: ENTITY OPS (@entities/)                            │
│ • Index-aware mutations only                                │
│ • Maintains bySystem, byOwner, byHouse indexes              │
│ • NO business logic                                         │
└─────────────────────────────────────────────────────────────┘
                              ▲
                              │ uses
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ Layer 1: STATE CORE (@state/)                               │
│ • entity_manager.nim: Generic DoD storage (data, index)     │
│ • iterators.nim: Read-only access patterns                  │
│ • Generic operations: entity(), addEntity(), updateEntity() │
└─────────────────────────────────────────────────────────────┘
```

## Reading Entities (Always Use Iterators)

**✅ CORRECT - Use iterators from @state/iterators.nim:**

```nim
import ../state/iterators

# Iterate colonies owned by a house
for colony in state.coloniesOwned(houseId):
  totalProduction += colony.production

# Iterate fleets at a system
for fleet in state.fleetsAtSystem(systemId):
  if fleet.houseId == enemyHouse:
    combatOccurs = true

# Iterate all active houses
for house in state.activeHouses():
  calculatePrestige(house)
```

**❌ WRONG - Don't access .entities.data directly:**

```nim
# DON'T DO THIS:
for colony in state.colonies.entities.data:
  if colony.owner == houseId:  # Manual filtering is error-prone
    totalProduction += colony.production
```

**Why use iterators?**
- O(1) indexed lookups (coloniesOwned uses byOwner index)
- Clear intent (self-documenting code)
- Type-safe (compiler enforces correct usage)
- Cache-friendly (batch processing)

## Writing Entities (Always Use Entity Ops)

**✅ CORRECT - Use entity ops from @entities/:**

```nim
import ../entities/[fleet_ops, colony_ops, squadron_ops]

# Create a new fleet (maintains bySystem and byOwner indexes)
let fleetId = fleet_ops.createFleet(state, houseId, systemId, "Alpha Fleet")

# Move fleet (updates bySystem index automatically)
fleet_ops.moveFleet(state, fleetId, newSystemId)

# Destroy colony (removes from byOwner and bySystem indexes)
colony_ops.destroyColony(state, systemId, events)

# Change fleet ownership (updates byOwner index for both houses)
fleet_ops.changeFleetOwner(state, fleetId, newHouseId)
```

**❌ WRONG - Don't mutate entities directly:**

```nim
# DON'T DO THIS:
let idx = state.fleets.entities.index[fleetId]
state.fleets.entities.data[idx].location = newSystemId
# ^^^ Breaks bySystem index! Other code will fail to find this fleet!

# DON'T DO THIS:
var colony = state.colonies.entities.data[idx]
colony.owner = newHouseId  # Breaks byOwner index!
state.colonies.entities.data[idx] = colony
```

**Why use entity ops?**
- Maintains all indexes automatically (bySystem, byOwner, byHouse, etc.)
- Ensures data consistency
- Single source of truth for mutations
- Easy to audit and test

## Simple Updates (Use entity_manager.nim)

For simple field updates that don't affect indexes:

```nim
import ../state/entity_manager

# Get entity (read-only)
let fleetOpt = state.fleets.entities.entity(fleetId)
if fleetOpt.isSome:
  var fleet = fleetOpt.get()

  # Modify fields that don't affect indexes
  fleet.fuelRemaining -= 1
  fleet.lastActionTurn = state.turn

  # Update entity
  state.fleets.entities.updateEntity(fleetId, fleet)
```

**When to use updateEntity vs entity ops:**
- `updateEntity()`: Simple field changes (fuel, status flags, turn counters)
- Entity ops: Changes that affect indexes (location, owner, creation, deletion)

## Iterator Variants

Iterators come in two flavors:

**1. Read-only (no ID):**
```nim
for colony in state.coloniesOwned(houseId):
  # Read-only access, no mutations
  totalPU += colony.population.units
```

**2. WithId (for mutations):**
```nim
for (systemId, colony) in state.coloniesOwnedWithId(houseId):
  # Can mutate via updateEntity or entity ops
  var updated = colony
  updated.blockaded = false
  state.colonies.entities.updateEntity(systemId, updated)
```

## Common Patterns

### Pattern 1: Count and Filter
```nim
var totalShips = 0
for squadron in state.squadronsOwned(houseId):
  if not squadron.destroyed:
    totalShips += squadron.ships.len
```

### Pattern 2: Find Entity
```nim
var targetFleet: Option[Fleet] = none(Fleet)
for fleet in state.fleetsAtSystem(systemId):
  if fleet.houseId == enemyHouse:
    targetFleet = some(fleet)
    break
```

### Pattern 3: Batch Update
```nim
for (fleetId, fleet) in state.fleetsOwnedWithId(houseId):
  var updated = fleet
  updated.fuelRemaining = updated.fuelMax
  state.fleets.entities.updateEntity(fleetId, updated)
```

### Pattern 4: Create and Link
```nim
# Create squadron via entity ops (maintains indexes)
let squadronId = squadron_ops.createSquadron(
  state, houseId, fleetId, shipClass, shipCount
)

# Squadron is automatically added to:
# - squadrons.byHouse[houseId]
# - squadrons.byFleet[fleetId]
# - fleet.squadrons list
```

## Entity Ops Responsibilities

Each `*_ops.nim` module maintains specific indexes:

| Module | Creates/Updates | Maintains Indexes |
|--------|----------------|-------------------|
| `fleet_ops.nim` | Fleet | bySystem, byOwner |
| `colony_ops.nim` | Colony | bySystem, byOwner |
| `squadron_ops.nim` | Squadron | byHouse, byFleet |
| `ship_ops.nim` | Ship | byHouse, bySquadron |
| `facility_ops.nim` | Starbase, Spaceport, etc. | byColony |

**Golden Rule:** If a mutation affects an index, use the entity ops module.

## Performance Notes

- Iterators have zero allocation overhead (compiler inlines them)
- O(1) indexed lookups for coloniesOwned, fleetsAtSystem, etc.
- O(n) for allColonies, allFleets (use sparingly)
- Entity ops maintain index consistency without performance penalty

## Common Mistakes

### ❌ Mistake 1: Direct data access
```nim
for colony in state.colonies.entities.data:  # WRONG
  if colony.owner == houseId:
    # ...
```

### ✅ Fix: Use iterator
```nim
for colony in state.coloniesOwned(houseId):  # CORRECT
  # ...
```

### ❌ Mistake 2: Manual index updates
```nim
state.fleets.bySystem[oldSystem].delete(fleetId)  # WRONG
state.fleets.bySystem[newSystem].add(fleetId)
```

### ✅ Fix: Use entity ops
```nim
fleet_ops.moveFleet(state, fleetId, newSystem)  # CORRECT
```

### ❌ Mistake 3: Modifying indexed fields
```nim
var fleet = state.fleets.entities.entity(fleetId).get()
fleet.location = newSystem  # WRONG - breaks bySystem index
state.fleets.entities.updateEntity(fleetId, fleet)
```

### ✅ Fix: Use entity ops
```nim
fleet_ops.moveFleet(state, fleetId, newSystem)  # CORRECT
```

## Quick Reference

**Need to...** | **Use...**
--- | ---
Read entities | `@state/iterators.nim`
Create/destroy entities | `@entities/*_ops.nim`
Change location/owner | `@entities/*_ops.nim`
Update simple fields | `@state/entity_manager.updateEntity()`
Check if exists | `@state/entity_manager.entity(id).isSome`
Business logic | `@systems/*/` (reads via iterators, writes via ops)

---

**Remember:** Iterators for reads, entity ops for writes, never touch indexes directly.
