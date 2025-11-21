# Prestige System Integration Plan

**Date:** 2025-11-21
**Status:** Design Phase

## Current State Analysis

### Existing Implementation

**✅ What Exists:**
1. **Prestige Module** (`src/engine/prestige.nim`) - 259 lines
   - Well-designed event system with `PrestigeEvent` and `PrestigeReport`
   - Predefined prestige values for all sources
   - Combat prestige awards (victories, squadrons, retreats)
   - Tax-based prestige (bonuses/penalties)
   - Tech advancement prestige
   - Victory condition checks (5000 prestige threshold)
   - Morale modifiers based on prestige

2. **Economy Integration** (partial)
   - `calculateTaxPenalty()` - High tax prestige penalties
   - `calculateTaxBonus()` - Low tax prestige bonuses
   - Tracked in `HouseIncomeReport.totalPrestigeBonus`
   - **BUT**: Values calculated but NOT applied to House.prestige!

3. **Research Integration** (missing)
   - No prestige awards for tech advancement
   - No tracking of research milestones

**❌ What's Missing:**
1. **Prestige not actually updated** - Calculations exist but don't modify `House.prestige`
2. **No turn-by-turn tracking** - No prestige reports stored in game state
3. **Research prestige missing** - Tech advancements not rewarded
4. **Combat integration incomplete** - Prestige module ready, but not called from combat
5. **Victory checking** - Prestige victory not checked in resolve.nim
6. **Prestige history** - No tracking of prestige changes over time

### Architecture Assessment

**✅ Strengths:**
- Clean separation of concerns (prestige.nim is standalone)
- Event-based system is flexible and extensible
- Economy already calculates tax prestige correctly
- Constants well-defined from specifications

**⚠️ Issues:**
- **Disconnected modules** - Prestige calculated but never applied
- **No central orchestration** - Each module calculates independently
- **Missing feedback loop** - Prestige should affect morale → affects combat → affects prestige

## Integration Strategy

### Phase 1: Connect Economy → Prestige ✅ (Highest Priority)

**Goal:** Apply tax prestige bonuses/penalties to House.prestige each turn

**Implementation:**
1. Add `PrestigeReport` to `IncomePhaseReport`
2. Create prestige events from tax calculations
3. Apply prestige changes in `resolve.nim` Income Phase
4. Store prestige reports in game state history

**Files to Modify:**
- `src/engine/economy/types.nim` - Add `prestigeEvents` to reports
- `src/engine/economy/income.nim` - Generate `PrestigeEvent` objects
- `src/engine/economy/engine.nim` - Return prestige events with income report
- `src/engine/resolve.nim` - Apply prestige changes to `House.prestige`

**Benefit:** Tax policy becomes meaningful for victory condition!

---

### Phase 2: Connect Research → Prestige ⚙️ (High Priority)

**Goal:** Award +2 prestige for each tech level advancement

**Implementation:**
1. Modify `attemptELAdvancement()` to return prestige event
2. Modify `attemptTechAdvancement()` to return prestige event
3. Add prestige events to research reports
4. Apply in resolve.nim during research allocation

**Files to Modify:**
- `src/engine/research/types.nim` - Add `prestigeEvents` to `TechAdvancement`
- `src/engine/research/advancement.nim` - Create prestige events on advancement
- `src/engine/resolve.nim` - Apply research prestige changes

**Benefit:** Tech race becomes part of victory path!

---

### Phase 3: Connect Combat → Prestige ⚔️ (Medium Priority)

**Goal:** Award prestige for combat victories, losses, retreats

**Implementation:**
1. Combat module already has prestige hooks (from M4)
2. Call `awardCombatPrestige()` after each battle
3. Add to `CombatReport`
4. Apply in resolve.nim Conflict Phase

**Files to Modify:**
- `src/engine/combat/engine.nim` - Generate prestige events
- `src/engine/resolve.nim` - Apply combat prestige
- `src/engine/gamestate.nim` - Store prestige in combat reports

**Benefit:** Combat victories matter for overall strategy!

---

### Phase 4: Victory Condition Integration 🏆 (High Priority)

**Goal:** Check for prestige victory and defensive collapse

**Implementation:**
1. Call `checkPrestigeVictory()` in Maintenance Phase
2. Call `checkDefensiveCollapse()` to eliminate houses at < 0 prestige
3. End game when victory achieved
4. Generate victory events

**Files to Modify:**
- `src/engine/resolve.nim` - Add victory checks to Maintenance Phase
- `src/engine/gamestate.nim` - Add victory state tracking

**Benefit:** Game can actually end! Victory condition works!

---

### Phase 5: Prestige History & UI 📊 (Low Priority)

**Goal:** Track prestige changes for player visibility

**Implementation:**
1. Add `prestigeHistory: seq[PrestigeReport]` to `House`
2. Store reports each turn
3. Provide query functions for UI
4. Calculate prestige trends (gaining/losing)

**Files to Modify:**
- `src/engine/gamestate.nim` - Add prestige history
- `src/engine/prestige.nim` - Add query/analysis functions

**Benefit:** Players can see their prestige trajectory!

---

## Proposed Unified Architecture

```
Turn Resolution Flow (with Prestige):

resolveTurn()
  │
  ├─ Phase 1: Conflict
  │   ├─ Resolve battles
  │   ├─ Generate CombatReport (with prestige events)
  │   └─ Apply prestige changes → House.prestige
  │
  ├─ Phase 2: Income
  │   ├─ Calculate GCO/NCV
  │   ├─ Calculate tax prestige (bonuses/penalties)
  │   ├─ Generate PrestigeEvents for tax policy
  │   ├─ Apply prestige changes → House.prestige
  │   └─ Return IncomePhaseReport (includes prestige)
  │
  ├─ Phase 3: Command
  │   ├─ Process research allocations
  │   ├─ Attempt tech advancements
  │   ├─ Generate PrestigeEvents for tech advances
  │   ├─ Apply prestige changes → House.prestige
  │   └─ Execute movement/colonization orders
  │
  └─ Phase 4: Maintenance
      ├─ Pay upkeep
      ├─ Advance construction
      ├─ Check prestige victory (>= 5000)
      ├─ Check defensive collapse (< 0 for 3 turns)
      ├─ Store prestige reports in history
      └─ End game if victory achieved
```

---

## Implementation Plan

### Step 1: Create Unified Prestige Tracker

**New File:** `src/engine/prestige/tracker.nim`

```nim
type
  PrestigeTracker* = object
    ## Centralized prestige tracking
    housePrestige*: Table[HouseId, int]
    turnReports*: seq[Table[HouseId, PrestigeReport]]
    defenseCollapseCounters*: Table[HouseId, int]

proc initPrestigeTracker*(): PrestigeTracker
proc addEvent*(tracker: var PrestigeTracker, houseId: HouseId, event: PrestigeEvent)
proc applyEvents*(tracker: var PrestigeTracker, turn: int)
proc checkVictory*(tracker: PrestigeTracker): Option[HouseId]
proc checkCollapse*(tracker: var PrestigeTracker): seq[HouseId]
```

**Benefit:** Single source of truth for all prestige

---

### Step 2: Modify Economy Reports

**File:** `src/engine/economy/types.nim`

```nim
# Add to HouseIncomeReport:
prestigeEvents*: seq[PrestigeEvent]  # Tax-based prestige changes

# Add to IncomePhaseReport:
# (already has houseReports which will include prestigeEvents)
```

**File:** `src/engine/economy/income.nim`

```nim
import ../prestige  # Add import

proc calculateHouseIncome*(...): HouseIncomeReport =
  # ... existing code ...

  # Generate prestige events
  var prestigeEvents: seq[PrestigeEvent] = @[]

  # Low tax bonus
  if result.totalPrestigeBonus > 0:
    prestigeEvents.add(createPrestigeEvent(
      PrestigeSource.LowTaxBonus,
      result.totalPrestigeBonus,
      "Low tax bonus"
    ))

  # High tax penalty
  if result.taxPenalty < 0:
    prestigeEvents.add(createPrestigeEvent(
      PrestigeSource.HighTaxPenalty,
      result.taxPenalty,
      "High tax penalty (avg: " & $result.taxAverage6Turn & "%)"
    ))

  result.prestigeEvents = prestigeEvents
```

---

### Step 3: Modify Research Reports

**File:** `src/engine/research/types.nim`

```nim
import ../../common/types/core
import ../prestige  # Add import

type
  TechAdvancement* = object
    houseId*: HouseId
    field*: TechField
    fromLevel*: int
    toLevel*: int
    cost*: int
    prestigeEvent*: Option[PrestigeEvent]  # ADD THIS
```

**File:** `src/engine/research/advancement.nim`

```nim
proc attemptELAdvancement*(tree: var TechTree, currentEL: int): Option[TechAdvancement] =
  # ... existing advancement code ...

  if successful:
    let prestigeEvent = awardTechPrestige(
      "",  # Set by caller
      "Economic Level",
      currentEL + 1
    )

    return some(TechAdvancement(
      # ... existing fields ...
      prestigeEvent: some(prestigeEvent)
    ))
```

---

### Step 4: Integrate in resolve.nim

**File:** `src/engine/resolve.nim`

```nim
import prestige  # Add import

proc resolveIncomePhase(state: var GameState, orders: Table[HouseId, OrderPacket]) =
  # ... existing income code ...

  # Apply prestige changes
  for houseId, houseReport in incomeReport.houseReports:
    for event in houseReport.prestigeEvents:
      state.houses[houseId].prestige += event.amount
      echo "    ", state.houses[houseId].name, ": ",
           (if event.amount > 0: "+" else: ""), event.amount, " prestige (", event.description, ")"

proc resolveMaintenancePhase(state: var GameState, events: var seq[GameEvent]) =
  # ... existing maintenance code ...

  # Check victory conditions
  for houseId, house in state.houses:
    if checkPrestigeVictory(house.prestige):
      state.phase = GamePhase.Completed
      events.add(GameEvent(
        eventType: gePrestigeVictory,
        houseId: houseId,
        description: house.name & " achieved prestige victory! (" & $house.prestige & " prestige)",
        systemId: none(SystemId)
      ))
      echo "  *** ", house.name, " has won by prestige! ***"
      return
```

---

## Testing Strategy

### Unit Tests

**File:** `tests/unit/test_prestige_integration.nim`

```nim
suite "Prestige Integration":
  test "Tax bonus awards prestige":
    # Low tax (20%) with 5 colonies = +5 prestige

  test "Tax penalty reduces prestige":
    # High average tax (80%) = -4 prestige

  test "Tech advancement awards prestige":
    # EL1 → EL2 = +2 prestige

  test "Combat victory awards prestige":
    # Victory = +1, squadron destroyed = +1 each

  test "Prestige victory triggers at 5000":
    # House with 5000+ prestige wins

  test "Defensive collapse at < 0 for 3 turns":
    # House eliminated after 3 turns negative
```

### Integration Tests

**File:** `tests/integration/test_prestige_game.nim`

```nim
suite "Prestige Game Flow":
  test "Full game with prestige victory":
    # Simulate 100 turns
    # Low tax strategy
    # Verify prestige accumulation
    # Check victory at ~5000

  test "Prestige affects morale":
    # High prestige → +ROE modifier
    # Low prestige → -ROE modifier
```

---

## Expected Results

After full integration:

1. **Tax strategy matters for victory**
   - Low tax (20%): +5 prestige/turn (5 colonies) = +500 prestige in 100 turns
   - High tax (80%): -4 prestige/turn = -400 prestige in 100 turns
   - **900 prestige swing!**

2. **Tech race affects victory**
   - +2 prestige per tech level
   - Reaching EL10 = +18 prestige (EL2 through EL10)
   - Multiple tech trees = substantial prestige gain

3. **Combat victories accumulate**
   - Each battle victory = +1 to +10 prestige
   - 50 battles over game = +50 to +500 prestige

4. **Victory timeline**
   - Conservative estimate: 200-400 turns to 5000 prestige
   - Aggressive low-tax strategy: 150-250 turns
   - Combat-focused strategy: 100-200 turns (if winning)

5. **Defensive collapse**
   - Losing wars → negative prestige
   - High tax + losses = death spiral
   - Elimination after 3 turns < 0 prestige

---

## Implementation Priority

### Immediate (Phase C):
1. ✅ Economy → Prestige connection (30 min)
2. ✅ Victory condition checks (15 min)
3. ✅ Basic integration tests (30 min)

**Total: ~75 minutes of work**

### Near-term (Phase D):
4. Research → Prestige connection (30 min)
5. Combat → Prestige connection (45 min - depends on combat module state)
6. Prestige history tracking (20 min)

**Total: ~95 minutes additional**

### Future:
7. Advanced prestige analytics
8. UI integration for prestige tracking
9. Diplomatic prestige sources
10. Special prestige events (wonders, achievements)

---

## Risk Assessment

**Low Risk:**
- Economy integration (calculations already exist)
- Victory checks (simple threshold)
- Basic testing

**Medium Risk:**
- Research integration (may need refactoring)
- Prestige history (memory/performance concerns)

**High Risk:**
- Combat integration (M4 combat system may need updates)
- Morale feedback loop (complex interactions)

---

## Recommendations

**Immediate Actions:**
1. **Start with Economy → Prestige** (easiest, highest impact)
2. **Add Victory Checks** (needed for game to end!)
3. **Write Integration Tests** (validate the flow)

**Then:**
4. Research → Prestige (medium difficulty)
5. Combat → Prestige (depends on M4 state)

**This gives you:**
- Working prestige system in ~75 minutes
- Games that can actually end
- Tax strategy that matters
- Foundation for full prestige integration

**Don't do yet:**
- Prestige history (can wait)
- Advanced analytics (nice-to-have)
- UI integration (separate concern)

---

## Conclusion

The prestige system **core is well-designed** but **not connected** to the game loop. Integration requires:
- Adding prestige events to existing reports
- Applying events to House.prestige in resolve.nim
- Checking victory conditions

**Estimated effort:** ~2-3 hours total for full integration
**Recommended approach:** Incremental (economy first, then research, then combat)

**Next step:** Implement Economy → Prestige connection (Phase 1)

