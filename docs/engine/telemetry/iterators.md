# Telemetry Iterators and O(1) Lookups

## Overview

The telemetry system uses efficient iterators backed by secondary indexes for O(1) lookups. This document explains the implementation and performance characteristics.

## The Problem: O(n) Linear Scans

**Before optimization**, telemetry collectors iterated ALL entities and filtered:

```nim
# O(n) - scans every squadron in the game
for squadron in state.squadrons.entities.data:
  if squadron.houseId == houseId:  # Filter on every iteration
    totalSquadrons += 1
```

**Cost per collection:**
- Iterate 500 squadrons to find 20 owned → 500 iterations
- Iterate 2000 ships to find 50 owned → 2000 iterations
- Iterate 100 colonies to find 10 owned → 100 iterations

**Total cost:** O(all_entities) × 13 collectors × 4-12 houses × every turn

## The Solution: Secondary Indexes

**After optimization**, entities have secondary indexes for O(1) house lookups:

```nim
# Squadrons type with byHouse index
type
  Squadrons* = ref object
    entities*: EntityManager[SquadronId, Squadron]
    byFleet*: Table[FleetId, seq[SquadronId]]
    byHouse*: Table[HouseId, seq[SquadronId]]  # NEW - O(1) lookup
```

**Usage:**
```nim
# O(1) lookup + O(k) where k = owned squadrons
for squadron in state.squadronsOwned(houseId):
  totalSquadrons += 1  # Only iterates 20 owned squadrons
```

**Cost per collection:**
- O(1) lookup + 20 owned squadrons → 20 iterations
- O(1) lookup + 50 owned ships → 50 iterations
- O(1) lookup + 10 owned colonies → 10 iterations

**Speedup:** 10-100x depending on total vs owned entity ratio

## Available Iterators

### Military Asset Iterators (O(1) via byHouse)

#### squadronsOwned
```nim
iterator squadronsOwned*(state: GameState, houseId: HouseId): Squadron
```

**Implementation:**
```nim
if state.squadrons.byHouse.contains(houseId):
  for squadronId in state.squadrons.byHouse[houseId]:
    yield state.squadrons.entities.data[index[squadronId]]
```

**Performance:** O(1) lookup + O(k) where k = squadrons owned

**Example:**
```nim
var capitalSquadrons = 0
for squadron in state.squadronsOwned(houseId):
  if squadron.flagship.shipClass in {Cruiser, Battleship, ...}:
    capitalSquadrons += 1
```

#### shipsOwned
```nim
iterator shipsOwned*(state: GameState, houseId: HouseId): Ship
```

**Implementation:** Same pattern as squadronsOwned

**Performance:** O(1) lookup + O(k) where k = ships owned

**Example:**
```nim
var crippledShips = 0
for ship in state.shipsOwned(houseId):
  if ship.isCrippled:
    crippledShips += 1
```

### Facility Iterators (O(colonies * facilities) via coloniesOwned + byColony)

These iterators compose `coloniesOwned` with facility `byColony` indexes:

#### starbasesOwned
```nim
iterator starbasesOwned*(state: GameState, houseId: HouseId): Starbase
```

**Implementation:**
```nim
for colony in state.coloniesOwned(houseId):  # O(1) + O(k colonies)
  if state.starbases.byColony.contains(colony.id):
    for starbaseId in state.starbases.byColony[colony.id]:  # O(s starbases)
      yield starbase
```

**Performance:** O(1) + O(colonies_owned × starbases_per_colony)

Typically: 10 colonies × 1 starbase = 10 iterations (vs 100 total starbases)

**Example:**
```nim
var totalStarbases = 0
for starbase in state.starbasesOwned(houseId):
  if not starbase.isCrippled:
    totalStarbases += 1
```

#### spaceportsOwned, shipyardsOwned, drydocksOwned
Same pattern as starbasesOwned.

### Colony Iterators (O(1) via byOwner)

#### coloniesOwned
```nim
iterator coloniesOwned*(state: GameState, houseId: HouseId): Colony
```

**Implementation:**
```nim
if state.colonies.byOwner.contains(houseId):
  for colonyId in state.colonies.byOwner[houseId]:
    yield state.colonies.entities.data[index[colonyId]]
```

**Performance:** O(1) lookup + O(k) where k = colonies owned

**Example:**
```nim
var totalProduction = 0
for colony in state.coloniesOwned(houseId):
  totalProduction += colony.production
```

### Fleet Iterators (O(n) filter - no byHouse index yet)

#### fleetsOwned
```nim
iterator fleetsOwned*(state: GameState, houseId: HouseId): Fleet
```

**Implementation:**
```nim
for fleet in state.fleets.entities.data:
  if fleet.houseId == houseId:
    yield fleet
```

**Performance:** O(n) - filters all fleets

**Why no index?** Fleets are small (typically 10-30 total) so O(n) is acceptable. Adding `byHouse` index possible if needed.

### House Iterators (O(n) filter)

#### activeHouses
```nim
iterator activeHouses*(state: GameState): House
```

**Implementation:**
```nim
for house in state.houses.entities.data:
  if not house.isEliminated:
    yield house
```

**Performance:** O(n) - filters all houses (typically 4-12)

**Why no index?** Houses are very small (4-12 total), O(n) is negligible.

## Performance Analysis

### Typical Game State

| Entity | Total | Owned | Without Index | With Index | Speedup |
|--------|-------|-------|---------------|------------|---------|
| Colonies | 100 | 10 | 100 | 10 | **10x** |
| Squadrons | 500 | 20 | 500 | 20 | **25x** |
| Ships | 2000 | 50 | 2000 | 50 | **40x** |
| Starbases | 80 | 8 | 80 | 10 (via colonies) | **8x** |
| Fleets | 25 | 3 | 25 | 3 | 1x (no index) |
| Houses | 6 | 6 | 6 | 6 | 1x (no index) |

### Aggregate Telemetry Collection

**Per-turn cost for one house:**
- 13 collectors × multiple queries each
- Estimated 50-100 iterator calls per collection

**Without indexes:** 50 calls × 500 avg entities = 25,000 iterations
**With indexes:** 50 calls × 20 avg owned = 1,000 iterations

**Speedup:** **25x** per house per turn

**For genetic algorithms (thousands of games):**
- 1000 games × 30 turns × 6 houses × 25x speedup = **significant impact**

## Index Maintenance

**IMPORTANT:** The `byHouse` indexes are currently **defined but not populated**.

Entity operations must maintain these indexes when:
- Creating entities → add to index
- Destroying entities → remove from index
- Transferring entities → move between indexes

See [index-maintenance.md](./index-maintenance.md) for implementation details.

## Adding New Iterators

### When to Add O(1) Iterators

Add a new iterator with secondary index when:
1. **Query frequency is high** - Used every turn for telemetry/AI
2. **Entity count is large** - 100+ entities where filtering is expensive
3. **Ownership ratio is low** - Owned entities << total entities

### When O(n) is Acceptable

Keep O(n) filtering when:
1. **Entity count is small** - Less than 50 entities total
2. **Query frequency is low** - Rare queries not in hot path
3. **Ownership ratio is high** - Most entities are owned anyway

### Pattern: Add Secondary Index + Iterator

**1. Add index to entity collection type:**
```nim
type
  MyEntities* = object
    entities*: EntityManager[MyId, MyEntity]
    byHouse*: Table[HouseId, seq[MyId]]  # NEW
```

**2. Add iterator to `interators.nim`:**
```nim
iterator myEntitiesOwned*(state: GameState, houseId: HouseId): MyEntity =
  if state.myEntities.byHouse.contains(houseId):
    for entityId in state.myEntities.byHouse[houseId]:
      if state.myEntities.entities.index.contains(entityId):
        yield state.myEntities.entities.data[state.myEntities.entities.index[entityId]]
```

**3. Maintain index in entity operations:**
```nim
# On creation
if not state.myEntities.byHouse.contains(houseId):
  state.myEntities.byHouse[houseId] = @[]
state.myEntities.byHouse[houseId].add(entityId)

# On deletion
if state.myEntities.byHouse.contains(houseId):
  let idx = state.myEntities.byHouse[houseId].find(entityId)
  if idx >= 0:
    state.myEntities.byHouse[houseId].delete(idx)
```

## Related Documentation

- [index-maintenance.md](./index-maintenance.md) - Maintaining secondary indexes
- [../../architecture/dod.md](../../architecture/dod.md) - Data-Oriented Design patterns

---

**Last Updated:** 2025-12-21
**Performance Status:** Indexes defined, maintenance pending in entity_ops
