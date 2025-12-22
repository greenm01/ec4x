# Secondary Index Maintenance

## Overview

The `byHouse` secondary indexes on `Squadrons` and `Ships` enable O(1) telemetry lookups but must be kept synchronized with entity changes.

**Current Status:** Indexes are **defined but not yet maintained** by entity operations.

**Future Work:** Update `squadron_ops.nim`, `ship_ops.nim`, and `fleet_ops.nim` to maintain these indexes.

## Indexes to Maintain

### 1. Squadrons.byHouse

**Type:** `Table[HouseId, seq[SquadronId]]`
**Location:** `src/engine/types/squadron.nim`

**Invariant:** `state.squadrons.byHouse[houseId]` contains all squadron IDs owned by `houseId`

### 2. Ships.byHouse

**Type:** `Table[HouseId, seq[ShipId]]`
**Location:** `src/engine/types/ship.nim`

**Invariant:** `state.ships.byHouse[houseId]` contains all ship IDs owned by `houseId`

## Maintenance Operations

### Pattern 1: Creation

**When:** Creating new squadrons or ships

**Code:**
```nim
proc createSquadron*(state: var GameState, houseId: HouseId, ...): SquadronId =
  let squadronId = ...  # Generate ID
  let squadron = Squadron(...)

  # Add to EntityManager
  state.squadrons.entities.addEntity(squadronId, squadron)

  # Add to byFleet index
  if not state.squadrons.byFleet.contains(fleetId):
    state.squadrons.byFleet[fleetId] = @[]
  state.squadrons.byFleet[fleetId].add(squadronId)

  # ✅ MAINTAIN byHouse INDEX
  if not state.squadrons.byHouse.contains(houseId):
    state.squadrons.byHouse[houseId] = @[]
  state.squadrons.byHouse[houseId].add(squadronId)

  return squadronId
```

**Files to Update:**
- `src/engine/entities/squadron_ops.nim` - Squadron creation
- `src/engine/entities/ship_ops.nim` - Ship creation

### Pattern 2: Deletion

**When:** Destroying squadrons or ships

**Code:**
```nim
proc destroySquadron*(state: var GameState, squadronId: SquadronId) =
  # Get squadron before deletion
  let squadronOpt = state.squadrons.entities.getEntity(squadronId)
  if squadronOpt.isNone:
    return

  let squadron = squadronOpt.get()
  let houseId = squadron.houseId
  let fleetId = squadron.fleetId  # If tracked

  # Remove from byFleet index
  if state.squadrons.byFleet.contains(fleetId):
    let idx = state.squadrons.byFleet[fleetId].find(squadronId)
    if idx >= 0:
      state.squadrons.byFleet[fleetId].delete(idx)

  # ✅ MAINTAIN byHouse INDEX
  if state.squadrons.byHouse.contains(houseId):
    let idx = state.squadrons.byHouse[houseId].find(squadronId)
    if idx >= 0:
      state.squadrons.byHouse[houseId].delete(idx)

  # Remove from EntityManager
  state.squadrons.entities.removeEntity(squadronId)
```

**Files to Update:**
- `src/engine/entities/squadron_ops.nim` - Squadron destruction
- `src/engine/entities/ship_ops.nim` - Ship destruction

### Pattern 3: Ownership Transfer

**When:** Transferring squadrons/ships between houses (diplomacy, capture, etc.)

**Code:**
```nim
proc transferSquadronOwnership*(
  state: var GameState,
  squadronId: SquadronId,
  oldHouseId: HouseId,
  newHouseId: HouseId
) =
  # Update squadron's house field
  let squadronOpt = state.squadrons.entities.getEntity(squadronId)
  if squadronOpt.isNone:
    return

  var squadron = squadronOpt.get()
  squadron.houseId = newHouseId
  state.squadrons.entities.updateEntity(squadronId, squadron)

  # ✅ MAINTAIN byHouse INDEX - Remove from old house
  if state.squadrons.byHouse.contains(oldHouseId):
    let idx = state.squadrons.byHouse[oldHouseId].find(squadronId)
    if idx >= 0:
      state.squadrons.byHouse[oldHouseId].delete(idx)

  # ✅ MAINTAIN byHouse INDEX - Add to new house
  if not state.squadrons.byHouse.contains(newHouseId):
    state.squadrons.byHouse[newHouseId] = @[]
  state.squadrons.byHouse[newHouseId].add(squadronId)
```

**Files to Update:**
- `src/engine/entities/squadron_ops.nim` - Squadron transfers
- `src/engine/entities/ship_ops.nim` - Ship transfers (if ships change houses independently)
- `src/engine/entities/fleet_ops.nim` - Fleet transfers (must update both indexes)

### Pattern 4: Fleet Transfers (Bulk Operation)

**When:** Moving squadrons between fleets of different houses

**Code:**
```nim
proc transferSquadronsToFleet*(
  state: var GameState,
  squadronIds: seq[SquadronId],
  targetFleetId: FleetId
) =
  let targetFleetOpt = state.fleets.entities.getEntity(targetFleetId)
  if targetFleetOpt.isNone:
    return

  let targetFleet = targetFleetOpt.get()
  let newHouseId = targetFleet.houseId

  for squadronId in squadronIds:
    let squadronOpt = state.squadrons.entities.getEntity(squadronId)
    if squadronOpt.isNone:
      continue

    var squadron = squadronOpt.get()
    let oldHouseId = squadron.houseId

    # Skip if already same house
    if oldHouseId == newHouseId:
      continue

    # Update squadron
    squadron.houseId = newHouseId
    state.squadrons.entities.updateEntity(squadronId, squadron)

    # ✅ MAINTAIN byHouse INDEX for squadrons
    # Remove from old house
    if state.squadrons.byHouse.contains(oldHouseId):
      let idx = state.squadrons.byHouse[oldHouseId].find(squadronId)
      if idx >= 0:
        state.squadrons.byHouse[oldHouseId].delete(idx)

    # Add to new house
    if not state.squadrons.byHouse.contains(newHouseId):
      state.squadrons.byHouse[newHouseId] = @[]
    state.squadrons.byHouse[newHouseId].add(squadronId)

    # ✅ MAINTAIN byHouse INDEX for ships in squadron
    # Ships inherit house from squadron
    for shipId in getAllShipsInSquadron(state, squadronId):
      # Remove from old house
      if state.ships.byHouse.contains(oldHouseId):
        let shipIdx = state.ships.byHouse[oldHouseId].find(shipId)
        if shipIdx >= 0:
          state.ships.byHouse[oldHouseId].delete(shipIdx)

      # Add to new house
      if not state.ships.byHouse.contains(newHouseId):
        state.ships.byHouse[newHouseId] = @[]
      state.ships.byHouse[newHouseId].add(shipId)
```

**Files to Update:**
- `src/engine/entities/fleet_ops.nim` - Fleet merges, splits, transfers

## Verification Strategy

### Consistency Checks

Add assertions to verify index consistency:

```nim
proc verifySquadronIndexes*(state: GameState) =
  ## Debug helper: verify byHouse index consistency

  # Build expected index from entities
  var expected: Table[HouseId, seq[SquadronId]]
  for squadron in state.squadrons.entities.data:
    if not expected.contains(squadron.houseId):
      expected[squadron.houseId] = @[]
    expected[squadron.houseId].add(squadron.id)

  # Sort for comparison
  for houseId in expected.keys:
    expected[houseId].sort()

  for houseId in state.squadrons.byHouse.keys:
    var actual = state.squadrons.byHouse[houseId]
    actual.sort()

    doAssert expected[houseId] == actual,
      "Squadron byHouse index inconsistent for house " & $houseId
```

**When to run:**
- During development: After every entity operation
- In production: Periodically (every N turns) with debug builds
- In tests: After each test operation

### Telemetry Cross-Check

Compare indexed iteration vs full scan:

```nim
proc verifyTelemetryCount*(state: GameState, houseId: HouseId) =
  # Count via index (fast path)
  var indexedCount = 0
  for squadron in state.squadronsOwned(houseId):
    indexedCount += 1

  # Count via full scan (slow path, for verification)
  var scannedCount = 0
  for squadron in state.squadrons.entities.data:
    if squadron.houseId == houseId:
      scannedCount += 1

  doAssert indexedCount == scannedCount,
    "Squadron count mismatch: indexed=" & $indexedCount &
    " scanned=" & $scannedCount
```

**When to run:**
- In tests: Every telemetry collection
- In debug builds: Periodically
- In production: Disabled (performance)

## Implementation Checklist

### Phase 1: Squadron Operations
- [ ] `squadron_ops.nim:createSquadron` - Add to byHouse on creation
- [ ] `squadron_ops.nim:destroySquadron` - Remove from byHouse on destruction
- [ ] `squadron_ops.nim:commissionSquadron` - Add to byHouse when commissioning
- [ ] Add verification checks to squadron operations

### Phase 2: Ship Operations
- [ ] `ship_ops.nim:createShip` - Add to byHouse on creation
- [ ] `ship_ops.nim:destroyShip` - Remove from byHouse on destruction
- [ ] `ship_ops.nim:commissionShip` - Add to byHouse when commissioning
- [ ] Add verification checks to ship operations

### Phase 3: Fleet Operations
- [ ] `fleet_ops.nim:transferSquadrons` - Update both indexes on transfer
- [ ] `fleet_ops.nim:mergeFleets` - Handle cross-house merges (if allowed)
- [ ] `fleet_ops.nim:splitFleet` - No index update needed (same house)
- [ ] Add verification checks to fleet operations

### Phase 4: Testing
- [ ] Unit tests for index maintenance in each operation
- [ ] Integration tests with telemetry cross-checks
- [ ] Stress tests with thousands of entity operations
- [ ] Genetic algorithm test run to verify no index corruption

### Phase 5: Documentation
- [ ] Add inline comments to maintained operations
- [ ] Update entity_ops documentation
- [ ] Add troubleshooting guide for index issues

## Common Issues and Solutions

### Issue: Index Contains Deleted Entity

**Symptom:** Iterator yields entities that don't exist in EntityManager

**Cause:** Entity deleted without removing from index

**Solution:** Always remove from ALL indexes before deleting from EntityManager

```nim
# ❌ WRONG - deleted from EntityManager first
state.squadrons.entities.removeEntity(squadronId)
state.squadrons.byHouse[houseId].delete(idx)  # Already deleted!

# ✅ CORRECT - remove from indexes first
state.squadrons.byHouse[houseId].delete(idx)
state.squadrons.byFleet[fleetId].delete(idx)
state.squadrons.entities.removeEntity(squadronId)  # Delete last
```

### Issue: Entity Missing from Index

**Symptom:** Entity exists but not yielded by iterator

**Cause:** Entity created without adding to index

**Solution:** Always add to ALL indexes after adding to EntityManager

```nim
# ✅ CORRECT - add to EntityManager, then indexes
state.squadrons.entities.addEntity(squadronId, squadron)
state.squadrons.byFleet[fleetId].add(squadronId)
state.squadrons.byHouse[houseId].add(squadronId)
```

### Issue: Duplicate Entries in Index

**Symptom:** Same entity yielded multiple times by iterator

**Cause:** Entity added to index multiple times

**Solution:** Check for existence before adding

```nim
# ✅ CORRECT - check before adding
if not state.squadrons.byHouse[houseId].contains(squadronId):
  state.squadrons.byHouse[houseId].add(squadronId)
```

### Issue: Wrong House Index After Transfer

**Symptom:** Entity shows under wrong house in telemetry

**Cause:** Transfer removed from wrong house or didn't add to new house

**Solution:** Always remove from old AND add to new

```nim
# ✅ CORRECT - complete transfer
# Remove from old
state.squadrons.byHouse[oldHouseId].delete(oldIdx)
# Add to new
state.squadrons.byHouse[newHouseId].add(squadronId)
```

## Performance Considerations

### Index Overhead

**Memory:** Negligible
- Each index entry is just an ID (8 bytes)
- Typical game: 500 squadrons × 8 bytes = 4 KB

**CPU:** Minimal
- Add/remove operations are O(1) for Table, O(n) for seq (small n)
- Typical seq length: 10-50 entities per house

**Trade-off:** Tiny maintenance cost for 10-100x telemetry speedup

### Optimization: Batch Operations

When creating/destroying many entities at once, batch index updates:

```nim
# Instead of updating index for each entity
for entity in entitiesToCreate:
  createEntity(...)  # Updates index individually

# Batch create, then update index once
let newIds = batchCreateEntities(...)
state.myEntities.byHouse[houseId].add(newIds)
```

## Related Documentation

- [iterators.md](./iterators.md) - How indexes enable O(1) lookups
- [../../architecture/dod.md](../../architecture/dod.md) - Data-Oriented Design patterns

---

**Last Updated:** 2025-12-21
**Implementation Status:** Pending (indexes defined but not maintained)
