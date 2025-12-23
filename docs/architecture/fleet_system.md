# Fleet System Architecture

## Overview

The fleet system follows EC4X's Data-Oriented Design (DoD) architecture pattern, with clear separation between state mutations (entities layer) and business logic (systems layer).

## Design Pattern: Entities vs Systems

### Entities Layer (`src/engine/entities/fleet_ops.nim`)

**Purpose**: Index-aware state mutations only
**Responsibilities**:
- Create, destroy, move, transfer entity ownership
- Maintain secondary indexes (`bySystem`, `byOwner`)
- NO business logic, validation, or algorithms

**Operations**:
```nim
proc createFleet*(state: var GameState, owner: HouseId,
                  location: SystemId): Fleet
  ## Creates fleet and updates both bySystem and byOwner indexes

proc destroyFleet*(state: var GameState, fleetId: FleetId)
  ## Destroys fleet, removes from all indexes, destroys all squadrons

proc moveFleet*(state: var GameState, fleetId: FleetId, destId: SystemId)
  ## Moves fleet, updates bySystem index

proc changeFleetOwner*(state: var GameState, fleetId: FleetId,
                       newOwner: HouseId)
  ## Transfers ownership, updates byOwner index
```

### Systems Layer (`src/engine/systems/fleet/`)

**Purpose**: Domain logic and business rules
**Responsibilities**:
- Validation: `canMergeWith`, `canTraverse`, compatibility checks
- Complex operations: merge, split, balance
- Query operations: `combatStrength`, `isCloaked`
- High-level coordination with prestige/events (via engine.nim)

**Module Organization**:

#### `engine.nim` - High-level Coordination API
```nim
type
  FleetOperationResult* = object
    success*: bool
    reason*: string
    fleetId*: Option[FleetId]

proc createFleetCoordinated*(state: var GameState, houseId: HouseId,
                             location: SystemId): FleetOperationResult
  ## 1. Validation (location valid, house active)
  ## 2. Call entities/fleet_ops.createFleet()
  ## 3. Return result
  ##
  ## NOTE: No prestige integration - fleet operations don't award prestige.
  ## Combat prestige is handled in combat module.

proc mergeFleets*(state: var GameState, sourceId: FleetId,
                  targetId: FleetId): FleetOperationResult
  ## 1. Validation (canMergeWith from entity.nim)
  ## 2. Transfer squadrons from source to target
  ## 3. Call entities/fleet_ops.destroyFleet(source)
  ## 4. Return result

proc splitFleet*(state: var GameState, fleetId: FleetId,
                 squadronIndices: seq[int]): FleetOperationResult
  ## 1. Validation
  ## 2. Create new fleet via entities/fleet_ops.createFleet()
  ## 3. Transfer squadrons to new fleet
  ## 4. Return result
```

#### `entity.nim` - Fleet Business Logic
Contains fleet-specific algorithms:
- `canMergeWith` - Intel/combat mixing validation
- `combatStrength` - Calculate effective combat power
- `isCloaked` - Stealth detection logic
- `balanceSquadrons` - Optimize squadron composition
- Other fleet queries and operations

## Secondary Indexes

### bySystem: Table[SystemId, seq[FleetId]]
- **Purpose**: O(1) spatial queries
- **Use case**: "What fleets are in system X?"
- **Maintained by**: `fleet_ops.nim` (create, destroy, move)

### byOwner: Table[HouseId, seq[FleetId]]
- **Purpose**: O(1) ownership queries
- **Use case**: "What fleets does house Y own?"
- **Maintained by**: `fleet_ops.nim` (create, destroy, changeOwner)
- **Added**: 2025-12-22 (fleet refactoring)
- **Rationale**: Colonies and Ships have byOwner indexes. Fleets need same for:
  - AI fleet management
  - Maintenance calculations
  - Diagnostics collection

## Decision Matrix: Where Does an Operation Belong?

| Operation Type | Layer | Example |
|----------------|-------|---------|
| Create/Destroy entity | entities/ | `createFleet`, `destroyFleet` |
| Move/Transfer entity | entities/ | `moveFleet`, `transferSquadron` |
| Change ownership | entities/ | `changeFleetOwner` |
| Complex mutations | systems/ | `mergeFleets`, `splitFleet` |
| Validation | systems/ | `canMergeWith`, `canTraverse` |
| Query operations | systems/ | `combatStrength`, `isCloaked` |
| Algorithms | systems/ | `balanceSquadrons` |
| High-level + events | systems/*/engine.nim | Like `colony/engine.nim` |

## Squadron and Ship Systems

Following the same pattern:

### Squadron System (`src/engine/systems/squadron/`)
- **entities/squadron_ops.nim**: Create, destroy, transfer squadrons
  - Maintains `byFleet` index
- **systems/squadron/engine.nim**: High-level squadron coordination (stub)
- **systems/squadron/entity.nim**: Squadron business logic

### Ship System (`src/engine/systems/ship/`)
- **entities/ship_ops.nim**: Add, remove ships
  - Maintains `bySquadron` index
- **systems/ship/engine.nim**: High-level ship coordination (stub)
- **systems/ship/entity.nim**: Ship business logic

## Migration Notes

### Completed (2025-12-22)
- ✅ Added `byOwner` index to Fleets type
- ✅ Updated `fleet_ops.nim` to maintain `byOwner` index
- ✅ Added `changeFleetOwner` proc
- ✅ Created `systems/fleet/engine.nim` (high-level API, NO prestige)
- ✅ Created squadron/ and ship/ stub directories
- ✅ Moved `fleet/squadron.nim` → `squadron/entity.nim`
- ✅ Moved `fleet/ship.nim` → `ship/entity.nim`

### Deferred (Awaiting Full Port)
- ⏸️ Phase 3: Refactor systems layer to use entities layer
  - 6+ files use old GameState structure
  - Requires full port of combat, command, conflict modules
- ⏸️ Phase 4: Update import paths
  - ~30 files import from old paths
  - Requires full port of importing modules
- ⏸️ Phase 5: Extract fleet movement from `turn_cycle/production_phase.nim`
  - File uses old GameState structure
  - Requires turn_cycle port

## Pattern Consistency

The fleet system now matches the colony system structure exactly:

### Colony Pattern (Reference)
```
entities/
  colony_ops.nim          # establishColony, destroyColony, changeColonyOwner
systems/
  colony/
    engine.nim            # High-level API with prestige integration
    conflicts.nim         # Multi-entity coordination
```

### Fleet Pattern (New)
```
entities/
  fleet_ops.nim           # createFleet, destroyFleet, moveFleet, changeFleetOwner
systems/
  fleet/
    engine.nim            # High-level API (NO prestige - combat handles it)
    entity.nim            # Business logic and queries
```

## Best Practices

### DO:
- ✅ Use `fleet_ops.createFleet()` for state mutations
- ✅ Use `fleet/engine.nim` for coordinated operations with validation
- ✅ Use `fleet/entity.nim` for business logic and queries
- ✅ Follow the decision matrix for operation placement

### DON'T:
- ❌ Manually manipulate `state.fleets.bySystem` or `state.fleets.byOwner`
- ❌ Call `state.fleets.entities.removeEntity()` directly
- ❌ Put business logic in `fleet_ops.nim`
- ❌ Put index manipulation in `fleet/engine.nim` or `fleet/entity.nim`

## Example Usage

### Creating a Fleet
```nim
# Systems layer: High-level API with validation
import systems/fleet/engine

let result = createFleetCoordinated(state, houseId, systemId)
if result.success:
  echo "Fleet created: ", result.fleetId.get()
else:
  echo "Failed: ", result.reason
```

### Merging Fleets
```nim
# Systems layer: Validates and coordinates
import systems/fleet/engine

let result = mergeFleets(state, sourceFleetId, targetFleetId)
if result.success:
  echo "Fleets merged into: ", result.fleetId.get()
else:
  echo "Cannot merge: ", result.reason
```

### Moving a Fleet
```nim
# Entities layer: Direct state mutation
import entities/fleet_ops

fleet_ops.moveFleet(state, fleetId, newSystemId)
# bySystem index automatically updated
```

## Future Work

1. **Complete Phase 3**: Refactor combat/command/conflict modules to use new structure
2. **Complete Phase 4**: Update import paths after module ports
3. **Complete Phase 5**: Extract fleet movement to `systems/fleet/movement.nim`
4. **Implement Squadron/Ship Engines**: Fill out engine.nim stubs with coordinated operations
5. **Add Integration Tests**: Test fleet operations with full GameState

---

**Last Updated**: 2025-12-22
**Related**: `/src/engine/architecture.md`, `/docs/architecture/colony_system.md`
