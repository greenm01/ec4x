# Fleet->Squadron Architecture Issue

**Date:** 2025-11-21
**Status:** Blocking battle resolution
**Priority:** High

---

## Problem Statement

EC4X has **two incompatible ship/fleet type systems**:

### System A: Simple Fleet System (gamestate/orders/resolve)
```nim
# src/engine/ship.nim
type Ship* = object
  shipType*: ShipType      # Enum: Military or Spacelift
  isCrippled*: bool

# src/engine/fleet.nim
type Fleet* = object
  ships*: seq[Ship]       # Simple ships
  owner*: HouseId
  location*: SystemId
```

### System B: Combat Squadron System (combat/)
```nim
# src/engine/squadron.nim
type EnhancedShip* = object
  shipClass*: ShipClass    # Enum: Corvette, Cruiser, Carrier, Fighter, etc. (20+ types)
  stats*: ShipStats        # Full combat stats (AS, DS, CC, CR)
  isCrippled*: bool
  name*: string

type Squadron* = object
  flagship*: EnhancedShip  # Capital ship leading squadron
  ships*: seq[EnhancedShip] # Supporting ships
  owner*: HouseId
  location*: SystemId
```

**The Mismatch:**
- Fleet system uses `ShipType` (2 values: Military/Spacelift)
- Combat system needs `ShipClass` (20+ values: Corvette, Cruiser, etc.)
- Ship has no combat stats; EnhancedShip has full stats from ships_config.toml

---

## Impact

### Blocked Features
1. **Battle Resolution** - Cannot convert Fleet->Squadron for combat
2. **Ship Construction** - Which ShipClass is being built?
3. **Tech Upgrades** - Cannot apply WEP bonuses without ShipClass
4. **Fleet Display** - Cannot show ship types/stats to players

### Working Features
- Movement (doesn't need ShipClass)
- Colonization (uses ship type check)
- Order validation (basic checks only)

---

## Root Cause Analysis

The codebase has **two development paths that diverged**:

1. **High-level game engine** (Fleet/GameState/Orders)
   - Designed for simple turn-by-turn gameplay
   - Uses abstract Ship/ShipType for movement rules
   - Good for MVP, insufficient for full game

2. **Combat system** (combat/, Squadron)
   - Designed for detailed tactical combat
   - Uses full ship stats and classifications
   - Complete implementation with config integration
   - **Cannot interface with Fleet system**

---

## Solution Options

### Option A: Refactor Fleet to Use Squadrons ⭐ RECOMMENDED
**Approach:** Replace `ships: seq[Ship]` with `squadrons: seq[Squadron]`

**Changes Required:**
```nim
# src/engine/fleet.nim
type Fleet* = object
  squadrons*: seq[Squadron]  # CHANGED from ships: seq[Ship]
  owner*: HouseId
  location*: SystemId

# Impact: Update all Fleet usage
- src/engine/gamestate.nim (Fleet creation)
- src/engine/orders.nim (validation checks)
- src/main/moderator.nim (fleet initialization)
- src/main/client.nim (fleet display)
```

**Benefits:**
- ✅ Unified ship representation
- ✅ Full combat stats available
- ✅ Tech upgrades work correctly
- ✅ Proper ship construction

**Effort:** Medium (2-3 days)
- Update Fleet type
- Refactor fleet creation/management
- Update all Fleet consumers
- Test all fleet operations

---

### Option B: Add ShipClass to Ship Type
**Approach:** Extend Ship to include ShipClass

**Changes Required:**
```nim
# src/engine/ship.nim
type Ship* = object
  shipType*: ShipType      # Military or Spacelift
  shipClass*: ShipClass    # ADDED: Corvette, Cruiser, etc.
  isCrippled*: bool

# Add conversion function
proc toEnhancedShip*(ship: Ship, techLevel: int = 1): EnhancedShip =
  EnhancedShip(
    shipClass: ship.shipClass,
    stats: getShipStats(ship.shipClass, techLevel),
    isCrippled: ship.isCrippled,
    name: ""
  )
```

**Benefits:**
- ✅ Minimal changes to Fleet type
- ✅ Conversion layer possible

**Drawbacks:**
- ⚠️ Still need to convert Ship->EnhancedShip for combat
- ⚠️ Duplicate ship data (ShipClass stored, stats computed)
- ⚠️ Tech level must be passed separately

**Effort:** Low-Medium (1-2 days)

---

### Option C: Maintain Separate Systems
**Approach:** Keep both systems, build bridges as needed

**Changes Required:**
- Add conversion functions as needed
- Store ShipClass mapping alongside Fleet
- Maintain sync between systems manually

**Benefits:**
- ✅ No breaking changes

**Drawbacks:**
- ❌ Architectural debt increases
- ❌ Error-prone conversions
- ❌ Confusing for future developers
- ❌ Still need Option A or B eventually

**Effort:** Low (1 day) but ongoing maintenance burden

---

## Recommendation

**Choose Option A: Refactor Fleet to Use Squadrons**

**Rationale:**
1. **Long-term correctness** - One ship representation, no sync issues
2. **Combat system is complete** - Squadron system is production-ready
3. **Config integration exists** - ships_config.toml already integrated
4. **Tech system ready** - WEP modifiers already implemented
5. **Cleaner architecture** - No conversion layers needed

**Migration Path:**
1. Create `Fleet2` type with squadrons (non-breaking)
2. Update moderator to create Fleet2 with proper squadrons
3. Update gamestate to use Fleet2
4. Update resolve.nim to use Squadron combat directly
5. Rename Fleet2 -> Fleet (breaking change, but everything updated)
6. Remove old Ship type, keep only EnhancedShip

---

## Impact on Turn Resolution

### Current State (resolveBattle in resolve.nim:419)
```nim
proc resolveBattle(...) =
  # Get fleets at system
  var fleetsAtSystem: seq[(FleetId, Fleet)] = @[]
  # ...

  # BLOCKED HERE: Cannot convert Fleet.ships (seq[Ship]) to Squadron
  # Ship has no ShipClass, cannot create EnhancedShip
  # Battle resolution skipped with warning
```

### After Option A Implementation
```nim
proc resolveBattle(...) =
  # Get fleets at system
  var fleetsAtSystem: seq[(FleetId, Fleet)] = @[]
  # ...

  # Gather squadrons directly from fleets
  var allSquadrons: seq[Squadron] = @[]
  for fleet in fleets:
    allSquadrons.add(fleet.squadrons)  # Works immediately!

  # Create Task Force
  let tf = combat.initializeTaskForce(houseId, allSquadrons, roe, prestige)

  # Resolve combat
  let result = combat.resolveCombat(context)

  # Apply results back to fleet.squadrons
```

---

## Related Files

**Files to Modify (Option A):**
- src/engine/fleet.nim (Fleet type definition)
- src/engine/gamestate.nim (Fleet creation)
- src/engine/orders.nim (Fleet validation)
- src/engine/resolve.nim (Battle resolution - remove TODO)
- src/main/moderator.nim (Initial fleet setup)
- src/main/client.nim (Fleet display)

**Files Already Compatible:**
- src/engine/combat/ (all files - use Squadron already)
- src/engine/squadron.nim (ready to use)
- src/engine/config/ships_config.nim (integrated)

**Test Files to Update:**
- tests/unit/test_fleet.nim
- tests/integration/ (any fleet tests)

---

## Implementation Checklist

When implementing Option A:

- [ ] Create Fleet2 type with squadrons field
- [ ] Add newFleet2() constructor accepting squadrons
- [ ] Update GameState to store Fleet2 in fleets table
- [ ] Update getFleet() / getHouseFleets() to return Fleet2
- [ ] Update moderator.nim initial fleet creation
- [ ] Update client.nim fleet display (can show ship classes now!)
- [ ] Update orders.nim fleet validation (check ShipClass, not ShipType)
- [ ] Update resolve.nim resolveBattle() (remove TODO, implement fully)
- [ ] Update resolve.nim resolveMovementOrder() (check squadron composition)
- [ ] Update resolve.nim resolveColonizationOrder() (check for Spacelift squadron)
- [ ] Run all tests, fix breakages
- [ ] Rename Fleet2 -> Fleet (final breaking change)
- [ ] Remove old Ship type from codebase
- [ ] Update documentation

**Estimated Time:** 2-3 days for full refactor + testing

---

## Temporary Workaround

**Status:** Implemented in resolve.nim:451-483

Battle resolution currently:
1. Detects fleet encounters
2. Groups fleets by house
3. **Skips combat** with warning: "Battle resolution skipped (fleet->squadron conversion not yet implemented)"
4. Generates placeholder CombatReport with no victor

**Result:** Fleets can move and encounter each other, but battles don't resolve until fleet architecture is fixed.

---

## Conclusion

The Fleet->Squadron architecture issue is a **high-priority blocker** for full turn resolution.

**Action Items:**
1. **Short-term:** Document issue (this file) and move forward with other turn systems (build orders, validation)
2. **Medium-term:** Implement Option A (Fleet refactor) to unblock combat
3. **Long-term:** Ensure all new features use Squadron system exclusively

**Next Steps:**
- Complete resolveBombardment() and resolveBuildOrders() (can work with current Fleet system)
- Schedule Fleet refactor as separate task
- Update TURN_RESOLUTION_ANALYSIS.md with this finding

---

**Document Status:** Complete
**Blocking Issue:** Documented
**Solution:** Identified (Option A)
**Owner:** TBD
**Target:** Next sprint
