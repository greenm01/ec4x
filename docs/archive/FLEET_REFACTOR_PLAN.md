# Fleet->Squadron Refactor - Implementation Plan

**Date:** 2025-11-21
**Status:** In Progress
**Goal:** Refactor Fleet to use Squadrons, enabling combat resolution

---

## Strategy: Non-Breaking Incremental Approach

Instead of a risky big-bang refactor, we'll use a **gradual migration** strategy:

1. Keep existing Fleet type temporarily
2. Create new Squadron-based fleet functions
3. Update systems one-by-one
4. Remove old code only when everything works
5. Maintain tests passing at each step

---

## Step 1: Update Fleet Type (Non-Breaking)

**File:** `src/engine/fleet.nim`

### Current State
```nim
type Fleet* = object
  id*: FleetId
  ships*: seq[Ship]          # Simple Ship (ShipType: Military/Spacelift)
  owner*: HouseId
  location*: SystemId
```

### New State
```nim
type Fleet* = object
  id*: FleetId
  squadrons*: seq[Squadron]  # CHANGED: Squadron (ShipClass: Corvette, etc.)
  owner*: HouseId
  location*: SystemId
```

### Migration Functions to Update
- `newFleet()` - Accept squadrons instead of ships
- `len()` - Count squadrons (or total ships in squadrons?)
- `isEmpty()` - Check if no squadrons
- `add()` - Add squadron (not ship)
- `remove()` - Remove squadron
- `canTraverse()` - Check squadron restrictions
- `combatStrength()` - Sum squadron AS
- `transportCapacity()` - Count spacelift squadrons
- String representation - Show squadron info

### Deprecated Functions (Remove Later)
- `militaryShips()` - No longer makes sense
- `spaceliftShips()` - No longer makes sense
- `crippledShips()` - Query squadrons instead
- `effectiveShips()` - Query squadrons instead
- Convenience constructors (`militaryFleet()`, etc.) - Replace with squadron-based versions

---

## Step 2: Create Squadron Construction Helpers

**File:** `src/engine/squadron.nim` (add to existing)

### New Helper Functions Needed
```nim
proc createMilitarySquadron*(
  shipClass: ShipClass,
  techLevel: int = 1,
  id: SquadronId = "",
  owner: HouseId = "",
  location: SystemId = 0
): Squadron =
  ## Create a military squadron with one flagship
  let flagship = EnhancedShip(
    shipClass: shipClass,
    stats: getShipStats(shipClass, techLevel),
    isCrippled: false,
    name: ""
  )
  newSquadron(flagship, id, owner, location)

proc createSpacelistSquadron*(...): Squadron =
  ## Create spacelift squadron (TroopTransport or ETAC)
  # Similar to above

proc createFleetSquadrons*(
  ships: seq[(ShipClass, int)],  # [(Corvette, 2), (Cruiser, 1)]
  techLevel: int,
  owner: HouseId,
  location: SystemId
): seq[Squadron] =
  ## Create multiple squadrons for a fleet
  var squadrons: seq[Squadron] = @[]
  var counter = 0
  for (shipClass, count) in ships:
    for i in 0..<count:
      let sq = createMilitarySquadron(
        shipClass,
        techLevel,
        id = &"sq-{owner}-{counter}",
        owner,
        location
      )
      squadrons.add(sq)
      counter += 1
  result = squadrons
```

---

## Step 3: Update GameState

**File:** `src/engine/gamestate.nim`

### Changes Needed
- `fleets` table already uses Fleet - no type change needed
- Fleet creation functions need to use squadrons
- Helper functions stay the same (just work with new Fleet internals)

### Functions to Verify
- `getFleet()` - Should work unchanged
- `getHouseFleets()` - Should work unchanged
- `createHomeFleet()` - Needs to create squadrons, not ships

---

## Step 4: Update Initial Game Setup

**File:** `src/main/moderator.nim` (likely)

### Current Pattern (Hypothetical)
```nim
# Old way
let fleet = militaryFleet(5)  # 5 generic military ships
state.fleets[fleetId] = fleet
```

### New Pattern
```nim
# New way
let squadrons = createFleetSquadrons(
  @[(ShipClass.Corvette, 3), (ShipClass.Destroyer, 2)],
  techLevel = 1,
  owner = houseId,
  location = systemId
)
let fleet = Fleet(
  id: fleetId,
  squadrons: squadrons,
  owner: houseId,
  location: systemId
)
state.fleets[fleetId] = fleet
```

---

## Step 5: Update Order Validation

**File:** `src/engine/orders.nim`

### Colonize Order Validation
```nim
# OLD: Check for Spacelift ship
var hasColonyShip = false
for ship in fleet.ships:
  if ship.shipType == ShipType.Spacelift and not ship.isCrippled:
    hasColonyShip = true
    break

# NEW: Check for spacelift squadron
var hasColonyShip = false
for squadron in fleet.squadrons:
  if squadron.flagship.shipClass in [ShipClass.TroopTransport, ShipClass.ETAC]:
    if squadron.flagship.isCrippled == false:
      hasColonyShip = true
      break
```

### Combat Order Validation
```nim
# OLD: Check for military ships
var hasMilitary = false
for ship in fleet.ships:
  if ship.shipType == ShipType.Military and not ship.isCrippled:
    hasMilitary = true

# NEW: Check for combat-capable squadrons
var hasMilitary = false
for squadron in fleet.squadrons:
  if squadron.getCurrentAS() > 0:  # Has attack strength
    hasMilitary = true
    break
```

---

## Step 6: Complete Battle Resolution

**File:** `src/engine/resolve.nim`

### resolveBattle() - Remove TODO, Implement Fully
```nim
proc resolveBattle(...) =
  # 1-4: Same (gather fleets, group by house)

  # 5. Build Task Forces - NOW WORKS!
  var taskForces: seq[combat_types.TaskForce] = @[]
  for houseId, fleets in houseFleets:
    # Gather all squadrons from all fleets
    var allSquadrons: seq[Squadron] = @[]
    for fleet in fleets:
      allSquadrons.add(fleet.squadrons)  # WORKS NOW!

    # Get prestige and tech
    let prestige = state.houses[houseId].prestige
    let isHomeworld = systemOwner.isSome and systemOwner.get() == houseId

    # Create Task Force
    let tf = combat.initializeTaskForce(
      houseId,
      allSquadrons,
      roe = 5,
      prestige = prestige,
      isHomeworld = isHomeworld
    )
    taskForces.add(tf)

  # 6-11: Resolve combat, apply results (same as before)
```

### resolveBombardment() - Implement Fully
```nim
proc resolveBombardment(...) =
  # Validation same as before

  # Convert squadrons to CombatSquadron
  var combatSquadrons: seq[CombatSquadron] = @[]
  for squadron in fleet.squadrons:
    combatSquadrons.add(combat.initializeCombatSquadron(squadron))

  # Get planetary defense
  let defense = state.colonies[targetId].planetaryDefense

  # Conduct bombardment
  let result = ground.conductBombardment(
    combatSquadrons,
    defense,
    seed = state.turn
  )

  # Apply damage
  state.colonies[targetId].infrastructureDamage += result.infrastructureDamage

  # Generate event
  events.add(...)
```

---

## Step 7: Update Movement Logic

**File:** `src/engine/resolve.nim` - `resolveMovementOrder()`

### Restricted Lane Check
```nim
# OLD: Check if ships can cross
if laneType == LaneType.Restricted:
  let canCross = fleet.ships.allIt(it.canCrossRestrictedLane())

# NEW: Check if squadrons can cross
if laneType == LaneType.Restricted:
  var canCross = true
  for squadron in fleet.squadrons:
    # Crippled squadrons can't cross restricted
    if squadron.flagship.isCrippled:
      canCross = false
      break
    # Spacelift squadrons can't cross restricted
    if squadron.flagship.shipClass in [ShipClass.TroopTransport, ShipClass.ETAC]:
      canCross = false
      break
```

---

## Step 8: Update Client/UI Display

**File:** `src/main/client.nim` (if exists)

### Fleet Display
```nim
# OLD: Show generic "5 military ships"
echo "Fleet has ", fleet.ships.len, " ships"

# NEW: Show specific ship classes
echo "Fleet composition:"
for squadron in fleet.squadrons:
  let status = if squadron.flagship.isCrippled: " (crippled)" else: ""
  echo "  - ", squadron.flagship.shipClass, status
```

---

## Step 9: Update Tests

**Files:** `tests/unit/test_fleet.nim`, `tests/integration/*`

### Test Updates Needed
- Fleet creation tests
- Fleet merge/split tests (if they use squadrons now)
- Movement tests with restricted lanes
- Combat tests (should now work!)

---

## Testing Strategy

### After Each Step
1. Run `nim c src/engine/resolve.nim` - Must compile
2. Run `nimble test` - All tests must pass
3. Commit with descriptive message

### Integration Testing
After all steps complete:
1. Create test scenario with 2 houses, multiple fleets
2. Test movement
3. Test combat encounter
4. Test bombardment
5. Test colonization
6. Verify all turn phases work end-to-end

---

## Risk Mitigation

### Potential Issues

**Issue:** Squadron ID generation collisions
- **Mitigation:** Use format `sq-{houseId}-{timestamp}-{counter}`

**Issue:** Performance with many squadrons
- **Mitigation:** Profile if needed, optimize later

**Issue:** Save/load compatibility
- **Mitigation:** Version game state format, migrate old saves

**Issue:** Breaking existing game saves
- **Mitigation:** Not a concern yet (no production saves exist)

---

## Rollback Plan

If refactor fails:
1. `git revert` to last working commit
2. Keep fleet.nim changes in separate branch
3. Re-evaluate approach

---

## Success Criteria

✅ All tests passing
✅ Battle resolution works end-to-end
✅ Bombardment works
✅ Movement with restricted lanes works
✅ Fleet display shows ship classes
✅ No compilation errors
✅ No runtime errors in turn resolution

---

## Timeline Estimate

- Step 1 (Fleet type): 30 min
- Step 2 (Squadron helpers): 30 min
- Step 3 (GameState): 15 min
- Step 4 (Initial setup): 30 min
- Step 5 (Order validation): 30 min
- Step 6 (Battle resolution): 1 hour
- Step 7 (Movement logic): 30 min
- Step 8 (Client display): 30 min
- Step 9 (Tests): 1 hour
- Integration testing: 1 hour

**Total:** ~6 hours (1 day with breaks)

---

## Current Status

- ⏳ Step 1: In progress
- ⏳ Steps 2-9: Pending

**Next Action:** Update Fleet type in fleet.nim
