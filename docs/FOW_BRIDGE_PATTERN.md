# Fog-of-War Bridge Pattern (Temporary)

## Purpose

This document describes the **temporary bridge pattern** used to integrate fog-of-war into the existing AI controller without requiring immediate refactoring of all 25+ helper functions.

## Pattern Overview

### Problem
- AI controller has 2,800+ lines with 25+ helper functions
- All functions expect full `GameState` with perfect information
- Refactoring all functions at once is risky and time-consuming

### Solution
- `generateAIOrders()` now receives `FilteredGameState`
- Creates a temporary `GameState` structure from filtered data
- Existing helper functions work unchanged
- **AI still has limited visibility** (only sees filtered data)

## Implementation

**Location:** `tests/balance/ai_controller.nim:2526`

```nim
proc generateAIOrders*(controller: var AIController, filtered: FilteredGameState, rng: var Rand): OrderPacket =
  # Create temporary GameState from filtered view
  var state = GameState(
    turn: filtered.turn,
    year: filtered.year,
    month: filtered.month,
    starMap: filtered.starMap,
    houses: initTable[HouseId, House](),
    colonies: initTable[SystemId, Colony](),
    fleets: initTable[FleetId, Fleet](),
    diplomacy: init Table[(HouseId, HouseId), DiplomaticState]()
  )

  # Populate with own assets (full details)
  state.houses[controller.houseId] = filtered.ownHouse
  for colony in filtered.ownColonies:
    state.colonies[colony.systemId] = colony
  for fleet in filtered.ownFleets:
    state.fleets[fleet.id] = fleet

  # Add visible enemy houses (prestige/diplomacy only)
  for houseId, prestige in filtered.housePrestige:
    if houseId != controller.houseId:
      var enemyHouse = House(
        id: houseId,
        prestige: prestige,
        treasury: 0,  # Unknown
        eliminated: filtered.houseEliminated.getOrDefault(houseId, false)
      )
      state.houses[houseId] = enemyHouse

  # Add diplomacy info
  for key, dipState in filtered.houseDiplomacy:
    let (house1, house2) = key
    state.diplomacy[(house1, house2)] = dipState

  # Now call existing helper functions with bridge state
  result = OrderPacket(
    houseId: controller.houseId,
    turn: state.turn,
    fleetOrders: generateFleetOrders(controller, state, rng),  # Works with bridge
    buildOrders: generateBuildOrders(controller, state, rng),  # Works with bridge
    # ...
  )
```

## What This Achieves

### ✅ Benefits
1. **FoW is enforced** - AI only sees filtered data
2. **No enemy colony details** - Not in `state.colonies` unless visible
3. **No enemy fleet details** - Not in `state.fleets` unless detected
4. **No enemy treasury/tech** - Enemy houses have zero/unknown values
5. **Existing code works** - All 25+ helper functions unchanged
6. **Fast integration** - Working FoW in ~100 lines of bridge code

### ⚠️ Limitations
1. **Memory overhead** - Creates temporary GameState each turn
2. **Type confusion** - Mixing `FilteredGameState` and `GameState`
3. **Technical debt** - Bridge must eventually be removed
4. **Incomplete filtering** - Some helpers may assume data that's missing

## What AI Cannot See (With Bridge)

### Enemy Assets
```nim
# Enemy colonies NOT in state.colonies
let weakestEnemy = findWeakestEnemyColony(state, controller.houseId, rng)
# Returns None if no enemy colonies visible!

# Enemy fleets NOT in state.fleets
let enemyStrength = calculateMilitaryStrength(state, enemyHouseId)
# Returns 0 if enemy fleets not detected!
```

### Enemy Details
```nim
# Enemy house exists but with minimal data
let enemyHouse = state.houses[enemyHouseId]
# enemyHouse.treasury == 0 (unknown)
# enemyHouse.techTree == default (unknown)
# enemyHouse.prestige == actual (public info)
```

## Migration Path

### Phase 1: Bridge Active ✅ (Current)
- FoW enforced via bridge pattern
- Helper functions unchanged
- AI has limited visibility

### Phase 2: Gradual Refactoring (Next)
Refactor one subsystem at a time:

**Example: Fleet management**
```nim
# OLD (uses bridge state)
proc generateFleetOrders(controller: AIController, state: GameState, rng: var Rand): seq[FleetOrder]

# NEW (uses filtered directly)
proc generateFleetOrders(controller: AIController, filtered: FilteredGameState, rng: var Rand): seq[FleetOrder]
```

**Refactoring order (by priority):**
1. `generateFleetOrders()` - Fleet movement with visibility
2. `generateBuildOrders()` - Construction priorities
3. `generateResearchAllocation()` - Tech advancement
4. `identifyInvasionOpportunities()` - Enemy colony detection
5. `assessCombatSituation()` - Fleet strength assessment
6. ... (remaining 20 functions)

### Phase 3: Bridge Removal (Final)
- All helpers use `FilteredGameState` directly
- Remove bridge code from `generateAIOrders()`
- Delete this document (no longer needed)

## Testing Strategy

### Current State
- Simulation runner applies FoW filtering ✅
- AI receives `FilteredGameState` ✅
- Bridge creates compatible `GameState` ✅
- Helper functions work unchanged ✅
- Balance tests pass ✅

### Validation
Run a test game and verify AI behavior:
```bash
tests/balance/run_simulation 20 42
```

Check logs for:
- AI doesn't order attacks on unscouted systems
- AI sends scouts to adjacent/unknown systems
- AI doesn't build in response to unseen enemy threats

## Related Documentation

- `docs/FOG_OF_WAR_INTEGRATION.md` - Full integration plan
- `docs/architecture/intel.md` - FoW specification
- `src/engine/fog_of_war.nim` - Core FoW system

---

**Status:** Bridge active ✅ | FoW enforced ✅ | Gradual refactoring pending ⏳

**Note:** This is a **temporary** pattern. The goal is to remove the bridge and have all functions use `FilteredGameState` directly.
