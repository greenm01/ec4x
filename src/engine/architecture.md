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
├── @state/               # [STATE MANAGEMENT CORE - The "Database"]
    │   │                     # Provides generic, low-level mechanics for storing and accessing data.
    │   │                     # `entity_manager.nim` is private to this directory (included, not imported).
    │   ├── engine.nim      #   - The PUBLIC API for direct `GameState` entity access:
    │   │                     #     • CRUD: add/update/del/get by ID for all entity types
    │   │                     #     • Helpers: colonyBySystem, shipsByFleet, groundUnitsAtColony, etc.
    │   │                     #     • Count: fleetsCount, shipsCount, coloniesCount, etc.
    │   ├── entity_manager.nim#   - Implements the generic DoD storage pattern (data: seq, index: Table).
    │   ├── id_gen.nim        #   - Logic for generating new, unique entity IDs.
    │   ├── iterators.nim     #   - The PRIMARY READ-ONLY API for batch entity access (e.g., `fleetsInSystem`, `coloniesOwned`).
    │   │                     #   - ALWAYS use iterators instead of `.entities.data` with manual filtering.
    │   │                     #   - Provides O(1) indexed lookups via `byHouse`, `byOwner`, `bySystem` tables.
    │   ├── fleet_queries.nim #   - Derived fleet properties (hasColonists, canMergeWith, etc.) using iterators.
    │   └── fog_of_war.nim    #   - Complex READ-ONLY query system that transforms `GameState` into `PlayerView`.
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
    │   ├── neoria_ops.nim    #   - `createNeoria`, `destroyNeoria` (production facilities)
    │   ├── kastra_ops.nim    #   - `createKastra`, `destroyKastra` (defensive facilities)
    │   ├── facility_ops.nim  #   - Legacy ops (will be removed after migration)
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

# Entity Access Patterns (Quick Reference)

## Three-Layer Architecture

```
Systems (@systems/)         ← Business logic, validation
    ↕ (reads via iterators, writes via entity_ops)
Entity Ops (@entities/)     ← Index-aware mutations
    ↕ (uses)
State Core (@state/)        ← CRUD + batch access
```

## UFCS Style (Always Use This)

```nim
import ../state/[engine, iterators, fleet_queries]
import ../entities/fleet_ops

# ✅ UFCS style (Uniform Function Call Syntax)
let colonyOpt = state.colony(colonyId)
let fleetOpt = state.fleet(fleetId)
state.updateHouse(houseId, house)
state.createFleet(houseId, systemId)

# ❌ Function style (don't use)
let colonyOpt = colony(state, colonyId)  # Wrong!
fleet_ops.createFleet(state, houseId, systemId)  # Wrong!
```

## Reading Entities

### Single Entity (state/engine.nim)

```nim
# Get by ID (returns Option[T])
let colony = state.colony(colonyId)       # Option[Colony]
let fleet = state.fleet(fleetId)         # Option[Fleet]
let ship = state.ship(shipId)            # Option[Ship]
let house = state.house(houseId)         # Option[House]

# Existence check (faster than .isSome)
if state.hasFleet(fleetId):
  # Fleet exists

# Index-based lookup (O(1))
let colonyOpt = state.colonyBySystem(systemId)  # 1:1 relationship
let ships = state.shipsByFleet(fleetId)         # 1:many relationship
let units = state.groundUnitsAtColony(colonyId) # 1:many relationship

# Count entities
let fleetCount = state.fleetsCount()
let shipCount = state.shipsCount()
```

### Batch Iteration (state/iterators.nim)

```nim
# By ownership (O(1) via byOwner index)
for colony in state.coloniesOwned(houseId):
  totalPP += colony.production

for fleet in state.fleetsOwned(houseId):
  totalMaintenance += fleet.maintenanceCost

# By location (O(1) via bySystem index)
for fleet in state.fleetsInSystem(systemId):
  if fleet.houseId == enemyId:
    combatOccurs = true

# By condition
for house in state.activeHouses():  # Non-eliminated only
  calculatePrestige(house)

# WithId variants (for mutations)
for (fleetId, fleet) in state.fleetsOwnedWithId(houseId):
  var updated = fleet
  updated.fuelRemaining = updated.fuelMax
  state.updateFleet(fleetId, updated)
```

### Derived Queries (state/fleet_queries.nim)

```nim
# Fleet composition checks
if state.hasColonists(fleet):          # Any ETAC with colonists?
  attemptColonization()

if state.hasCombatShips(fleet):        # Any ships with AS > 0?
  engageCombat()

if state.isScoutOnly(fleet):           # Only scouts in fleet?
  executeSpy mission()

# Fleet cargo queries
let marines = state.totalCargoOfType(fleet, CargoClass.Marines)
if state.hasLoadedMarines(fleet):
  invasionPossible = true

# Fleet compatibility
let mergeCheck = state.canMergeWith(fleet1, fleet2)
if mergeCheck.canMerge:
  state.mergeFleets(fleet1.id, fleet2.id)

# Fleet strength
let totalAS = state.calculateFleetAS(fleet)
```

## Writing Entities

### Simple Updates (state/engine.nim)

```nim
# For fields that DON'T affect indexes (fuel, status, etc.)
let fleetOpt = state.fleet(fleetId)
if fleetOpt.isSome:
  var fleet = fleetOpt.get()
  fleet.fuelRemaining -= 1
  fleet.lastActionTurn = state.turn
  state.updateFleet(fleetId, fleet)  # UFCS style
```

### Index-Affecting Changes (entities/*_ops.nim)

```nim
import ../entities/[fleet_ops, colony_ops]

# Create/destroy (maintains all indexes) - use UFCS
let fleet = state.createFleet(houseId, systemId)
state.destroyColony(colonyId, events)

# Move (updates bySystem index)
state.moveFleet(fleetId, newSystemId)

# Change owner (updates byOwner index)
state.changeFleetOwner(fleetId, newHouseId)
```

## Common Patterns

### Pattern: Find and Update

```nim
# Find by condition, then update
for (fleetId, fleet) in state.fleetsInSystemWithId(systemId):
  if shouldRetreat(fleet):
    var updated = fleet
    updated.retreating = true
    state.updateFleet(fleetId, updated)
```

### Pattern: Count with Filter

```nim
var crippledShips = 0
for ship in state.shipsOwned(houseId):
  if ship.state == CombatState.Crippled:
    crippledShips += 1
```

### Pattern: Existence Check Before Access

```nim
# Fast existence check (doesn't allocate Option)
if state.hasFleet(fleetId):
  let fleet = state.fleet(fleetId).get()  # Safe: we checked existence
  processFleet(fleet)
```

### Pattern: Aggregate Derived Properties

```nim
var totalAS = 0
for fleet in state.fleetsOwned(houseId):
  totalAS += state.calculateFleetAS(fleet)  # Uses fleet_queries
```

## Entity Ops Responsibilities

| Module | Creates/Updates | Maintains Indexes |
|--------|----------------|-------------------|
| `fleet_ops.nim` | Fleet | bySystem, byOwner |
| `colony_ops.nim` | Colony | bySystem, byOwner |
| `ship_ops.nim` | Ship | byHouse, byFleet |
| `neoria_ops.nim` | Neoria (production) | byColony |
| `kastra_ops.nim` | Kastra (defense) | byColony |

## Common Mistakes

```nim
# ❌ Don't access .entities.data directly
for colony in state.colonies.entities.data:
  if colony.owner == houseId:  # Manual filtering is slow

# ✅ Use indexed iterator
for colony in state.coloniesOwned(houseId):  # O(1) lookup

# ❌ Don't modify indexed fields directly
var fleet = state.fleet(fleetId).get()
fleet.location = newSystem  # Breaks bySystem index!
state.updateFleet(fleetId, fleet)

# ✅ Use entity ops (UFCS style)
state.moveFleet(fleetId, newSystem)

# ❌ Don't use verbose index pattern
if state.colonies.bySystem.hasKey(systemId):
  let colonyId = state.colonies.bySystem[systemId]
  let colony = state.colony(colonyId).get()

# ✅ Use helper
let colony = state.colonyBySystem(systemId)

# ❌ Don't write business logic in entity_ops
proc moveFleet*(state: GameState, ...) =
  if fuelRemaining < distance:  # Business logic doesn't belong here!
    return

# ✅ Validate in systems layer, mutate via entity_ops (UFCS)
proc executeMove(state: GameState, ...):
  if fleet.fuelRemaining < distance:  # Business logic in systems/
    return
  state.moveFleet(...)                 # Mutation via entity_ops (UFCS)
```

## Module Import Guide

```nim
# For reading state
import ../state/[engine, iterators, fleet_queries]

# For mutations
import ../entities/[fleet_ops, colony_ops, ship_ops]

# Business logic
import ../systems/fleet/entity  # Fleet validation/logic
```

## Performance Notes

- Iterators: O(1) indexed lookups (coloniesOwned, fleetsInSystem)
- Helpers: O(1) index access (colonyBySystem, shipsByFleet)
- Entity ops: O(1) index updates (moveFleet maintains bySystem)
- All iterators inline to zero-cost loops (no allocation overhead)
