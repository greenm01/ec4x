# Fighter Grace Period Management - Imperial Government Enhancement

## Problem Statement

Fighters are currently built without carrier capacity and auto-disbanded after a 2-turn grace period. This wastes production points and leaves colonies undefended.

**Current Behavior:**
```
Turn 7: CST 3 reached, needFighters=true
Turn 8: Build 3 fighters at Colony A (60PP spent)
Turn 9: Fighters commissioned
Turn 10: Grace period expires → All 3 fighters auto-disbanded
Result: 60PP wasted, no defensive capability gained
```

## Root Cause

No RBA module tracks the fighter grace period or coordinates carrier construction timing. The build system operates per-colony per-turn without strategic lookahead.

## Proposed Solution: Grace Period Coordinator

Add a **Logistics Officer** or enhance the **Admiral** to track and manage fighter grace periods.

### Architecture: `src/ai/rba/logistics/fighter_coordinator.nim`

```nim
type
  FighterGracePeriodStatus = object
    colonyId: int
    fightersWithoutCapacity: int
    turnsUntilDisbanding: int  # 0 = will disband this turn, 1 = next turn, 2 = grace period active
    carrierInConstruction: bool

proc trackFighterGracePeriods*(state: GameState, houseId: string): seq[FighterGracePeriodStatus] =
  ## Called each turn BEFORE build orders generated
  ## Returns colonies with fighters at risk of auto-disbanding

proc shouldPrioritizeCarrier*(status: FighterGracePeriodStatus): bool =
  ## Returns true if carrier construction is urgent
  ## Priority: turnsUntilDisbanding <= 1 AND not carrierInConstruction

proc adjustBuildPriorities*(tracker: var BudgetTracker, urgentCarriers: seq[int]) =
  ## Reallocates budget to SpecialUnits for urgent carrier construction
  ## May reduce Military/Defense spending temporarily
```

### Integration Points

**1. Pre-Build Analysis (orders.nim:440)**
```nim
# NEW: Track grace period status BEFORE generating build orders
let gracePeriodStatus = trackFighterGracePeriods(filtered, controller.houseId)
let urgentCarrierColonies = gracePeriodStatus.filterIt(shouldPrioritizeCarrier(it))

# Pass to build system
result.buildOrders = generateBuildOrdersWithBudget(
  controller, filtered, ...,
  urgentCarrierColonies  # NEW parameter
)
```

**2. Budget Reallocation (budget.nim:1183)**
```nim
# If colony has urgent carrier need, boost SpecialUnits budget
if colony.systemId in urgentCarrierColonies:
  let emergencyCarrierBudget = min(180, tracker.getRemainingBudget(Military) * 0.5)
  tracker.reallocate(Military, SpecialUnits, emergencyCarrierBudget)
  logInfo(LogCategory.lcAI, &"URGENT: Reallocating {emergencyCarrierBudget}PP to save {status.fightersWithoutCapacity} fighters")
```

**3. Build Order Priority (budget.nim:754)**
```nim
# Build carriers FIRST if grace period urgent, even if budget marginal
if needCarriers and (isUrgentCarrier or cstLevel >= 3):
  # Try to build carrier even if it uses entire SpecialUnits budget
  let carrierCost = if cstLevel >= 5: 200 else: 120
  if tracker.canAfford(SpecialUnits, carrierCost) or isUrgentCarrier:
    # ... build carrier
```

### Benefits

1. **Prevents PP Waste**: Fighters only built when carriers can be constructed
2. **Strategic Coordination**: Admiral/Logistics communicate about force composition
3. **Budget Flexibility**: Emergency reallocation when grace period expires soon
4. **Matches Imperial Theme**: Logistics Officer managing fleet support assets

### Implementation Priority

**Phase 1 (Immediate - 2 hours):**
- Add `trackFighterGracePeriods()` to logistics.nim
- Log warnings when grace period < 2 turns

**Phase 2 (Next Session - 3 hours):**
- Implement budget reallocation for urgent carriers
- Add carrier priority boosting logic

**Phase 3 (Future - 4 hours):**
- Full Logistics Officer module with sub-modules
- Fighter squadron assignment coordination
- Carrier fleet doctrine (how many fighters per carrier)

## Alternative: Simpler Fix

If full grace period tracking is too complex:

**Option A: Don't build standalone fighters**
- Only build fighters WITH carriers (lines 767-810)
- Remove standalone fighter code (lines 843-861)
- Ensures fighters always have capacity

**Option B: Check existing carriers before building fighters**
```nim
# Line 843: Only build standalone fighters if carriers exist
let hasCarriers = colony.ships.anyIt(it.class in [ShipClass.Carrier, ShipClass.SuperCarrier])
if needFighters and hasCarriers:
  # Build fighters only if carrier capacity available
```

**Option C: Increase carrier construction priority**
- Already implemented (removed canAffordMoreShips gate)
- May still fail if budget < 120PP

## Recommended Approach

Start with **Option B** (check for carriers) as immediate fix, then implement **Phase 1** tracking for monitoring, then **Phase 2** for full coordination.

## Test Plan

1. Run balance test with seed that previously showed fighter auto-disbanding
2. Verify carriers built BEFORE fighters
3. Confirm no "Auto-disbanding excess fighter squadron" messages
4. Check diagnostics show fighters > 0 in end-game state

---

**Author:** Claude
**Date:** 2025-11-28
**Related Commit:** 2372e3b - fix(rba): Enable fighter/carrier construction
